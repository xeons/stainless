// Stainless - an experimental systems language.
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
/// What resolution decided, written down so the next build decides the same.
///
/// A project file says what would do -- "any 1.2 of this" -- and that is the
/// right thing for it to say, because it is written by a person for the next
/// person. A build needs the other thing: exactly which commit, exactly which
/// version, exactly which bytes. That is this, and the reason the two are
/// separate files is that one of them is edited and one of them is not.
///
/// It belongs in version control. Two people with the same lock file build the
/// same program; two people with only the project file build whatever was
/// newest on the day.
/// </summary>
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record PackageLock
{
    public const string FileName = "stainless.lock";

    public const int CurrentFormat = 1;

    public int Format { get; init; } = CurrentFormat;

    /// <summary>The package this lock was resolved for, so a stray one is obvious.</summary>
    public required string Root { get; init; }

    /// <summary>
    /// Every package the root needs, directly or not, in a stable order.
    ///
    /// Flat rather than nested, because the graph is resolved to one version per
    /// package: a nested shape would have to repeat a shared dependency, and
    /// repeating it is how two copies of it start looking reasonable.
    /// </summary>
    public List<LockedPackage> Packages { get; init; } = [];

    private static readonly JsonSerializerOptions Format_ = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    public static string PathFor(ProjectFile project) =>
        System.IO.Path.Combine(project.Directory, FileName);

    public static PackageLock? Read(string path, out string error)
    {
        error = "";

        if (!File.Exists(path)) return null;

        try
        {
            var locked = JsonSerializer.Deserialize<PackageLock>(File.ReadAllText(path), Format_);

            if (locked is null)
            {
                error = $"'{path}' is empty";
                return null;
            }

            if (locked.Format > CurrentFormat)
            {
                error = $"'{path}' is format {locked.Format} and this compiler reads " +
                        $"{CurrentFormat}; upgrade the compiler, or delete the lock file and " +
                        "resolve again";
                return null;
            }

            return locked;
        }
        catch (Exception e) when (e is IOException or JsonException)
        {
            error = $"could not read '{path}': {e.Message}. Delete it and run " +
                    "'stainless restore' to resolve again";
            return null;
        }
    }

    public void Write(string path) =>
        File.WriteAllText(path, JsonSerializer.Serialize(this, Format_) + Environment.NewLine);

    public LockedPackage? Find(string name) =>
        Packages.FirstOrDefault(p => string.Equals(p.Name, name, StringComparison.Ordinal));
}

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record LockedPackage
{
    public required string Name { get; init; }
    public required string Version { get; init; }

    /// <summary>
    /// Where it came from, as one string: <c>path:../geometry</c> or
    /// <c>git:https://example/x.git</c>. One string rather than the fields that
    /// produced it, because what a lock file needs is an identity to compare,
    /// not a description to re-read.
    /// </summary>
    public required string Source { get; init; }

    /// <summary>
    /// The exact commit, for a git package. This is the whole point of locking
    /// one: a tag can be moved, and a branch is expected to.
    /// </summary>
    public string? Revision { get; init; }

    public DependencyLink Link { get; init; } = DependencyLink.Source;

    /// <summary>
    /// A fingerprint of the source that was resolved, from
    /// <see cref="Digest.OfDirectory"/>.
    ///
    /// It answers the question a version number cannot for a path dependency,
    /// which has no commit and no release: is the directory I am building today
    /// the directory I resolved? For a path into a sibling checkout the answer
    /// is often no, and that is worth saying out loud rather than discovering.
    /// </summary>
    public string SourceDigest { get; init; } = "";

    /// <summary>
    /// A fingerprint of the library's described surface, from
    /// <see cref="Digest.OfMetadata"/>, for a package linked as
    /// <see cref="DependencyLink.Shared"/>.
    ///
    /// Absent until the package has been built once: it cannot be known before
    /// then, because it is computed from the metadata the build emits. Absent
    /// for ever for a source dependency, which has no library and therefore no
    /// surface of its own to fingerprint.
    /// </summary>
    public string? AbiDigest { get; init; }

    /// <summary>
    /// What this package itself depends on, by name. Kept so the build order can
    /// be worked out from the lock alone, without re-reading every project file
    /// in the graph.
    /// </summary>
    public List<string> Dependencies { get; init; } = [];
}
