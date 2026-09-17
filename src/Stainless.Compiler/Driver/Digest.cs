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

using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace Stainless.Driver;

/// <summary>
/// A fingerprint of what a library promises, computed rather than declared.
///
/// A version number is a claim a person makes, and people are wrong about them:
/// nothing stops 1.2.3 being rebuilt with a field added to the middle of a
/// class, and nothing about the number says it happened. The consumer's
/// compilation baked that class's offsets into its own code, so the mistake is
/// not a link error -- it is a program that reads the wrong four bytes and
/// keeps going.
///
/// This closes that. The digest is taken over the described surface itself --
/// every layout, every offset, every dispatch slot and every symbol -- so two
/// builds agree here exactly when a consumer compiled against one can be linked
/// against the other. It goes in the metadata, the lock file records what was
/// resolved, and a build that finds the two different says so instead of
/// running.
///
/// It is not a security measure. It catches a mistake rather than an attacker,
/// which is why a truncated hash is enough.
/// </summary>
public static class Digest
{
    /// <summary>
    /// How much of the hash is kept. 128 bits is far past what a mistake could
    /// collide with, and short enough to sit in a lock file and be compared by
    /// eye.
    /// </summary>
    private const int HexLength = 32;

    /// <summary>
    /// What separates one piece of the canonical text from the next.
    ///
    /// A control character rather than a punctuation mark, because everything
    /// being joined is a name, a symbol or a number -- none of which can contain
    /// one, so nothing needs escaping and two different surfaces cannot render
    /// to the same text by putting a separator inside a name.
    /// </summary>
    private const string Separator = "\u001f";

    /// <summary>
    /// The digest of a whole library: what it is called, the runtime it needs,
    /// and every type and function it describes.
    ///
    /// The library's *file name* is deliberately not in it. Renaming shapes.dll
    /// changes nothing about how the code inside it is called, and a digest that
    /// moved when a file was renamed would cry wolf.
    /// </summary>
    public static string OfMetadata(ModuleMetadata metadata)
    {
        var parts = new List<string>
        {
            "metadata",
            Number(metadata.Version),
            metadata.Package ?? "",
            metadata.SharedRuntime ? "shared" : "static",
        };

        foreach (var type in metadata.Types
                     .OrderBy(t => t.Module + "." + t.Name, StringComparer.Ordinal))
            parts.AddRange(Canonical(type));

        foreach (var function in metadata.Functions
                     .OrderBy(f => f.Symbol, StringComparer.Ordinal))
            parts.AddRange(Canonical(function));

        return Hash(parts);
    }

    /// <summary>
    /// The digest of one type, so a mismatch can name what moved rather than
    /// saying only that something did.
    /// </summary>
    public static string OfType(MetadataType type) => Hash(Canonical(type));

    /// <summary>
    /// The digest of one free function, for the same reason: so a surface that
    /// changed somewhere other than in a type can still say where.
    /// </summary>
    public static string OfFunction(MetadataFunction function) => Hash(Canonical(function));

    /// <summary>
    /// A digest of an arbitrary list of facts, for a caller that has assembled
    /// its own. <see cref="ProjectBuilder"/> uses it for the reason a build was
    /// allowed to be skipped.
    ///
    /// The caller owns the order. Joining with the separator below is what makes
    /// two different lists impossible to render to one string.
    /// </summary>
    public static string OfParts(IEnumerable<string> parts) => Hash(parts);

    /// <summary>
    /// Everything about a type that a consumer's compilation can depend on.
    ///
    /// Field and parameter *names* are in here along with the offsets, and that
    /// is deliberate even though renaming one changes no machine code: this
    /// language has named arguments, so a parameter's name is part of how it is
    /// called, and a public field's name is how it is read. The digest covers
    /// the surface a consumer binds against, which is a little wider than the
    /// bytes it emits.
    ///
    /// What is not in here is anything a consumer cannot observe: where a
    /// declaration was written, and what order the file happened to list things
    /// in.
    /// </summary>
    private static List<string> Canonical(MetadataType type)
    {
        var parts = new List<string>
        {
            "type",
            type.Kind.ToString(),
            type.Module + "." + type.Name,
            Number(type.Size),
            Number(type.Alignment),
            type.Base ?? "",
            type.TypeInfoSymbol ?? "",
            type.Underlying ?? "",
            type.IsThreadsafe ? "threadsafe" : "",
            type.IsOpaque ? "opaque" : "",
            type.AliasTarget ?? "",
            Number(type.InstanceSize),
            type.DestroySymbol ?? "",
        };

        // Slot by slot, in order, and the count with them. A derived class in
        // another binary copied this table and appended after it, so both what
        // is in a slot and how many there are are things it compiled in.
        parts.Add("vtable");
        parts.Add(Number(type.VirtualTable.Count));
        parts.AddRange(type.VirtualTable.Select(slot => slot ?? "abstract"));

        // A closure's or a delegate's signature, which is the whole of what it
        // is: it has no fields to describe it by, so without this two closures
        // of different shapes would fingerprint alike.
        parts.Add("signature");
        parts.Add(type.Returns ?? "");

        foreach (var parameter in type.Signature)
            parts.AddRange([parameter.Mode.ToString(), parameter.Type, parameter.Name]);

        // Events by name and type. Their methods are already in the digest as
        // methods; what this adds is that the name is an event -- which decides
        // what a consumer is allowed to write, so turning one into an ordinary
        // field would break code that compiled against it.
        foreach (var declared in type.Events.OrderBy(e => e.Name, StringComparer.Ordinal))
            parts.AddRange([
                "event",
                declared.Name,
                declared.Type,
                declared.IsPublic ? "public" : declared.IsProtected ? "protected" : "",
            ]);

        // By offset and then by name: the offsets are the layout, and the name
        // settles the order of two fields that share one -- a union's cases, and
        // the bit-fields inside a single storage unit.
        foreach (var field in type.Fields
                     .OrderBy(f => f.Offset)
                     .ThenBy(f => f.BitOffset)
                     .ThenBy(f => f.Name, StringComparer.Ordinal))
            parts.AddRange([
                "field",
                field.Name,
                field.Type,
                Number(field.Offset),
                field.IsPublic ? "public" : "private",
                field.IsBackingField ? "backing" : "",
                field.BitWidth is { } width ? Number(width) : "",
                Number(field.BitOffset),
            ]);

        foreach (var member in type.Members.OrderBy(m => m.Name, StringComparer.Ordinal))
            parts.AddRange([
                "member",
                member.Name,
                member.Value.ToString(CultureInfo.InvariantCulture),
            ]);

        foreach (var method in type.Methods.OrderBy(m => m.Symbol, StringComparer.Ordinal))
            parts.AddRange(Canonical(method));

        return parts;
    }

    private static List<string> Canonical(MetadataFunction function)
    {
        var parts = new List<string>
        {
            "function",
            function.Symbol,
            function.Module ?? "",
            function.Name,
            function.Returns,
            function.Kind.ToString(),
            function.IsStatic ? "static" : "instance",
            function.IsProtected ? "protected" : "",
            function.IsVariadic ? "variadic" : "",
            Number(function.VirtualSlot),
            function.Accessor ?? "",
        };

        // In declaration order, because for a parameter list that *is* the
        // meaning: swapping two parameters of the same type changes every call.
        foreach (var parameter in function.Parameters)
            parts.AddRange([
                "parameter",
                parameter.Mode.ToString(),
                parameter.Type,
                parameter.Name,
            ]);

        return parts;
    }

    /// <summary>
    /// The digest of a directory of source: every file's path and contents.
    ///
    /// This is the other question, and it is asked at a different moment. The
    /// metadata digest asks whether a binary is the one a consumer compiled
    /// against; this asks whether the source resolved last week is the source
    /// being built today, which is what makes a lock file a lock for a
    /// dependency that has no binary at all.
    /// </summary>
    public static string OfDirectory(string directory)
    {
        string root = Path.GetFullPath(directory);
        if (!System.IO.Directory.Exists(root)) return "";

        var parts = new List<string>();

        var files = System.IO.Directory
            .EnumerateFiles(root, "*", SearchOption.AllDirectories)
            .Where(f => !IsIgnored(root, f))
            .Select(f => (Relative: Relative(root, f), Full: f))
            // Ordinal, on the forward-slashed relative path, so a lock file
            // written on Windows and verified on Linux agrees with itself.
            .OrderBy(f => f.Relative, StringComparer.Ordinal);

        foreach (var (relative, full) in files)
        {
            byte[] contents;
            try
            {
                contents = File.ReadAllBytes(full);
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                // An unreadable file is not a different file. Leaving it out
                // would make the digest depend on who ran the build.
                continue;
            }

            parts.Add(relative);
            parts.Add(Convert.ToHexStringLower(SHA256.HashData(contents)));
        }

        return Hash(parts);
    }

    /// <summary>
    /// The digest of one file's bytes, or an empty string when it cannot be
    /// read.
    ///
    /// Empty rather than an exception because the only question asked of it
    /// is whether a file is the one a build last saw, and a file that cannot
    /// be read is not — the build that follows will say why.
    /// </summary>
    public static string OfFile(string path)
    {
        try
        {
            using var stream = File.OpenRead(path);
            return Convert.ToHexStringLower(SHA256.HashData(stream));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException
                                      or ArgumentException or NotSupportedException)
        {
            return "";
        }
    }

    private static string Relative(string root, string path) =>
        Path.GetRelativePath(root, path).Replace('\\', '/');

    /// <summary>
    /// What a source digest leaves out: the things a build writes. Hashing them
    /// would make a package's digest change the first time it was built, which
    /// is precisely when nothing about it has changed.
    /// </summary>
    private static bool IsIgnored(string root, string path)
    {
        foreach (string part in Relative(root, path).Split('/'))
            if (part is "obj" or "bin" or "build" or ".git")
                return true;

        return false;
    }

    private static string Number(int value) => value.ToString(CultureInfo.InvariantCulture);

    private static string Hash(IEnumerable<string> parts) =>
        Convert.ToHexStringLower(
            SHA256.HashData(Encoding.UTF8.GetBytes(string.Join(Separator, parts))))[..HexLength];
}
