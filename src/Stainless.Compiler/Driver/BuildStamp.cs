// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

using System.Text.Json;
using System.Text.Json.Serialization;

namespace Stainless.Driver;

/// <summary>
/// Why the last build of a dependency produced what it did, so the next one can
/// tell whether it would produce the same thing.
///
/// This is the only place in the compiler that decides not to do work, and that
/// makes it the only place that can be wrong in a way nothing reports: a build
/// that is skipped when it should not have been is a program linked against a
/// library that no longer matches its source, and it will link perfectly. So
/// the rule here is deliberately blunt -- **every input, or rebuild**. There is
/// no per-file dependency graph, no timestamps, and no attempt to work out that
/// a change could not have mattered. A package is one compilation unit; either
/// everything that fed it is identical or it is built again.
///
/// Timestamps are the thing this is not. A file restored from an archive, a
/// clock that went backwards, a checkout that rewrote mtimes -- each makes a
/// timestamp say "unchanged" about different bytes. A digest of the bytes
/// cannot.
/// </summary>
public sealed record BuildStamp
{
    /// <summary>The file this is kept in, inside the package's own intermediates.</summary>
    public const string FileName = "build.json";

    public const int CurrentFormat = 1;

    public int Format { get; init; } = CurrentFormat;

    /// <summary>
    /// Everything that decided what the last build produced, as one hash. What
    /// goes into it is <see cref="ProjectBuilder"/>'s business; what matters
    /// here is that it is compared whole.
    /// </summary>
    public required string Inputs { get; init; }

    /// <summary>
    /// What that build produced, so a skip can hand back the same answer
    /// without reading the library again to find it.
    /// </summary>
    public required string AbiDigest { get; init; }

    /// <summary>
    /// Every file the build embedded, with the digest of its bytes then.
    ///
    /// <b>Kept apart from <see cref="Inputs"/> because it cannot be known in
    /// advance.</b> Everything in that hash is read before the build starts;
    /// which files an <c>embed</c> names is only known once the program has
    /// been bound. A package's own directory is already in its source digest,
    /// but an <c>embed</c> may name a file anywhere — a sibling directory, an
    /// absolute path — and a build that did not look at it again would link
    /// yesterday's bytes into today's library and report nothing.
    /// </summary>
    public IReadOnlyList<StampedFile> Embedded { get; init; } = [];

    /// <summary>
    /// Whether every embedded file still has the bytes it had when the stamp
    /// was written. A file that is gone or cannot be read has not: it digests
    /// to nothing, which matches no digest, and the build then reports it.
    /// </summary>
    public bool EmbeddedFilesAreUnchanged() =>
        Embedded.All(file => file.Digest.Length > 0 && Digest.OfFile(file.Path) == file.Digest);

    /// <summary>The digest of each of these files, as a stamp records them.</summary>
    public static IReadOnlyList<StampedFile> Digests(IEnumerable<string> paths) =>
        paths.Distinct(StringComparer.Ordinal)
             .Select(path => new StampedFile(path, Digest.OfFile(path)))
             .ToList();

    private static readonly JsonSerializerOptions Format_ = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public static BuildStamp? Read(string path)
    {
        if (!File.Exists(path)) return null;

        try
        {
            var stamp = JsonSerializer.Deserialize<BuildStamp>(File.ReadAllText(path), Format_);

            // A stamp from a format this compiler does not know says nothing
            // about what is on disk, and the safe reading of "says nothing" is
            // "build it".
            return stamp?.Format == CurrentFormat ? stamp : null;
        }
        catch (Exception e) when (e is IOException or JsonException)
        {
            return null;
        }
    }

    /// <summary>
    /// Writes the stamp, and says nothing if it cannot.
    ///
    /// A stamp that failed to write costs a rebuild next time, which is the
    /// same thing that happens when there is no stamp at all. Failing the build
    /// over it would turn a slow build into no build.
    /// </summary>
    public void Write(string path)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path)) ?? ".");
            File.WriteAllText(path, JsonSerializer.Serialize(this, Format_));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            // Deliberately silent. See above.
        }
    }
}

/// <summary>A file a build read, by where it is and what its bytes were.</summary>
public sealed record StampedFile(string Path, string Digest);
