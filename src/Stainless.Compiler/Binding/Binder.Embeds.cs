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
using System.Text;
using Stainless.Source;
using Stainless.Syntax;

namespace Stainless.Binding;

/// <summary>
/// <c>embed</c>: a file's bytes as an immortal <c>byte[]</c> the linker places.
/// </summary>
public sealed partial class Binder
{
    /// <summary>
    /// Every distinct object, by what makes two embeds the same one: the file,
    /// the section it lands in and the access it is given.
    /// </summary>
    private readonly Dictionary<(string Path, string Section, EmbedAccess Access), EmbeddedFile>
        _embeds = [];

    /// <summary>
    /// The access each section has been given by the first embed placed in it,
    /// so that a second asking for different access is refused where it is
    /// written rather than by the assembler, or not at all.
    /// </summary>
    private readonly Dictionary<string, (EmbedAccess Access, SourceSpan Span)> _embedSections =
        new(StringComparer.Ordinal);

    /// <summary>
    /// <c>embed(path)</c>, <c>embed(path, section: ".s")</c>,
    /// <c>embed(path, access: "rw")</c>.
    ///
    /// <para>
    /// Every argument is a string literal, because each one decides something
    /// about the binary and the binary is decided before the program runs. A
    /// path computed at run time is a file read, which is what
    /// <c>Standard.File</c> is for.
    /// </para>
    ///
    /// <para>
    /// The file is looked at here — that it exists, is a file, can be opened,
    /// and how long it is — so that a missing one is an error on the literal
    /// that named it. The bytes are not read: the assembler reads them, and a
    /// build stamp digests them, and neither needs the binder to hold a copy of
    /// a file that may be large.
    /// </para>
    /// </summary>
    private BoundExpression BindEmbed(EmbedSyntax syntax)
    {
        StringArgument? path = null;
        StringArgument? section = null;
        StringArgument? access = null;
        bool failed = false;

        foreach (var argument in syntax.Arguments)
        {
            string? name = argument is NamedArgumentSyntax named ? named.Name : null;
            var value = argument is NamedArgumentSyntax { Value: var inner } ? inner : argument;

            if (argument is RefArgumentSyntax or OutArgumentSyntax)
            {
                diagnostics.Error("SL0703", argument.Span,
                    "'embed' takes string literals; 'ref' and 'out' have nothing to refer to here");
                failed = true;
                continue;
            }

            ref StringArgument? slot = ref path;
            switch (name)
            {
                case null when path is null && section is null && access is null:
                    break;

                case null:
                    diagnostics.Error("SL0703", argument.Span,
                        "'embed' takes one path, and then 'section:' and 'access:' by name");
                    failed = true;
                    continue;

                case "section":
                    slot = ref section;
                    break;

                case "access":
                    slot = ref access;
                    break;

                default:
                    diagnostics.Error("SL0703", ((NamedArgumentSyntax)argument).NameSpan,
                        $"'embed' has no argument named '{name}'; it takes a path, then " +
                        "'section:' and 'access:'");
                    failed = true;
                    continue;
            }

            if (slot is not null)
            {
                diagnostics.Error("SL0703", argument.Span,
                    $"'{name}' is given twice; 'embed' takes each argument once");
                failed = true;
                continue;
            }

            // A literal and nothing else. `const` strings are refused too:
            // what goes in the binary should be readable where it is asked
            // for, and a constant is one more place to look.
            if (value is not LiteralSyntax { Kind: TokenKind.StringLiteral, Value: string text })
            {
                diagnostics.Error("SL0704", value.Span,
                    $"'embed' needs {(name is null ? "the path" : $"'{name}'")} as a string " +
                    "literal, because it is decided when the program is built rather than when " +
                    "it runs; to read a file at run time, use 'Standard.File'");
                failed = true;
                continue;
            }

            slot = new StringArgument(text, value.Span);
        }

        if (path is null)
        {
            if (!failed)
                diagnostics.Error("SL0703", syntax.Span,
                    "'embed' needs the path of the file to carry, as a string literal");
            return new BoundErrorExpression(syntax.Span);
        }

        if (failed) return new BoundErrorExpression(syntax.Span);

        var target = TargetPlatform.Current;

        // The three arguments are independent, so each is checked whatever the
        // others turned out to be: a program with a bad access and a missing
        // file hears about both at once.
        var resolved = ResolveEmbeddedPath(path.Value, syntax.Span.File);

        // --- access -----------------------------------------------------------
        EmbedAccess granted = EmbedAccess.Read;
        if (access is { } writtenAccess)
        {
            if (EmbeddedFile.ParseAccess(writtenAccess.Text) is not { } parsed)
            {
                diagnostics.Error("SL0707", writtenAccess.Span,
                    $"'{Printable(writtenAccess.Text)}' is not an access; write the letters " +
                    "'r', 'w' and 'x', each at most once and 'r' always — \"r\", \"rw\", " +
                    "\"rx\" or \"rwx\"");
                return new BoundErrorExpression(syntax.Span);
            }

            granted = parsed;
        }

        // --- section ----------------------------------------------------------
        string placed;
        if (section is { } writtenSection)
        {
            if (EmbeddedFile.SectionProblem(writtenSection.Text) is { } problem)
            {
                diagnostics.Error("SL0709", writtenSection.Span,
                    $"'{Printable(writtenSection.Text)}' cannot name a section: {problem}");
                return new BoundErrorExpression(syntax.Span);
            }

            placed = writtenSection.Text;

            if (target.IsWindows &&
                Encoding.UTF8.GetByteCount(placed) > EmbeddedFile.ImageSectionNameLimit)
                diagnostics.Warning("SL0710", writtenSection.Span,
                    $"'{placed}' is longer than the {EmbeddedFile.ImageSectionNameLimit} bytes a " +
                    "PE image keeps for a section name, so the linker will cut it to " +
                    $"'{TruncatedSectionName(placed)}' in {target.Triple}'s executable; the " +
                    "bytes are unaffected, but a tool looking for the section by its full name " +
                    "will not find it");
        }
        else if (EmbeddedFile.DefaultSection(granted, target) is { } fallback)
        {
            placed = fallback;
        }
        else
        {
            diagnostics.Error("SL0708", access!.Value.Span,
                "memory both writable and executable has no default section; name one with " +
                "'section:', so that asking for it is something the source says out loud");
            return new BoundErrorExpression(syntax.Span);
        }

        // Last, and only for an embed that is otherwise sound: the first one
        // placed in a section is what decides its access, and one that failed
        // for another reason should not get to decide it.
        if (resolved is null)
            return new BoundErrorExpression(syntax.Span);

        if (!SectionAccepts(placed, granted, section?.Span ?? access?.Span ?? syntax.Span, target))
            return new BoundErrorExpression(syntax.Span);

        var key = (resolved.Value.Path, placed, granted);
        if (!_embeds.TryGetValue(key, out var file))
        {
            file = new EmbeddedFile(
                _embeds.Count, resolved.Value.Path, placed, granted, resolved.Value.Length);
            _embeds[key] = file;
        }

        return new BoundEmbed(syntax.Span, ArrayOf(PrimitiveTypeSymbol.Byte), file);
    }

    private readonly record struct StringArgument(string Text, SourceSpan Span);

    /// <summary>
    /// Whether a section can be given this access: one the target already
    /// defines has the access it has, and one this program defines has the
    /// access the first embed placed in it asked for.
    /// </summary>
    private bool SectionAccepts(
        string section, EmbedAccess access, SourceSpan span, TargetPlatform target)
    {
        if (EmbeddedFile.KnownSectionAccess(section, target) is { } fixedAccess)
        {
            if (fixedAccess == 0)
            {
                diagnostics.Error("SL0711", span,
                    $"'{section}' holds no bytes in the file on {target.Triple} — the loader " +
                    "zeroes it — so an embedded file cannot be placed there; choose another " +
                    "section");
                return false;
            }

            if (fixedAccess != access)
            {
                diagnostics.Error("SL0711", span,
                    $"'{section}' is always \"{EmbeddedFile.Spell(fixedAccess)}\" on " +
                    $"{target.Triple}, and the assembler would keep that whatever an embed " +
                    $"asked for, so \"{EmbeddedFile.Spell(access)}\" cannot be placed there; " +
                    "name a section of its own");
                return false;
            }

            return true;
        }

        if (_embedSections.TryGetValue(section, out var first))
        {
            if (first.Access == access) return true;

            diagnostics.Error("SL0711", span,
                $"'{section}' was already given \"{EmbeddedFile.Spell(first.Access)}\" by the " +
                $"embed at {first.Span}; a section has one set of permissions, so this one " +
                $"cannot also be \"{EmbeddedFile.Spell(access)}\" — name a different section");
            return false;
        }

        _embedSections[section] = (access, span);
        return true;
    }

    /// <summary>
    /// The embedded file as a full path and a length, or null once the reason
    /// it cannot be embedded has been reported against the literal.
    ///
    /// <para>
    /// <b>Relative to the file that wrote the <c>embed</c></b>, not to the
    /// directory the compiler was started in. A source file and the data beside
    /// it move together, and a build started from anywhere else — a project
    /// file two directories up, the test harness, an editor — then finds the
    /// same bytes. It is the rule <c>llvm-rc</c> follows for a resource script,
    /// and the one C's <c>#include "..."</c> starts with.
    /// </para>
    ///
    /// <para>
    /// A source with no directory of its own — the standard library, compiled
    /// from the compiler's resources, or text an editor or a test handed over
    /// under a made-up name — has nothing to be relative to, and that is an
    /// error rather than a guess at the working directory. An absolute path
    /// needs no directory and is accepted from anywhere.
    /// </para>
    /// </summary>
    private (string Path, long Length)? ResolveEmbeddedPath(
        StringArgument written, SourceText source)
    {
        string full;
        try
        {
            if (written.Text.Length == 0)
            {
                diagnostics.Error("SL0706", written.Span,
                    "an empty path names no file to embed");
                return null;
            }

            if (Path.IsPathRooted(written.Text))
            {
                full = Path.GetFullPath(written.Text);
            }
            else
            {
                // `DebugInfo.File` guards the same made-up paths the same way:
                // `<standard>/Text.sl` and `<test>` are names, not places.
                string? directory = null;
                try
                {
                    string sourcePath = Path.GetFullPath(source.Path);
                    if (File.Exists(sourcePath)) directory = Path.GetDirectoryName(sourcePath);
                }
                catch (Exception e) when (e is ArgumentException or NotSupportedException
                                              or IOException)
                {
                    directory = null;
                }

                if (directory is null)
                {
                    diagnostics.Error("SL0705", written.Span,
                        $"'{source.Path}' is not a file on disk, so there is no directory to " +
                        $"find '{Printable(written.Text)}' relative to; give an absolute path, " +
                        "or compile the source from a file");
                    return null;
                }

                full = Path.GetFullPath(Path.Combine(directory, written.Text));
            }
        }
        catch (Exception e) when (e is ArgumentException or NotSupportedException
                                      or PathTooLongException)
        {
            diagnostics.Error("SL0706", written.Span,
                $"'{Printable(written.Text)}' is not a path this system can open: {e.Message}");
            return null;
        }

        if (Directory.Exists(full))
        {
            diagnostics.Error("SL0706", written.Span,
                $"'{full}' is a directory; 'embed' carries the bytes of one file");
            return null;
        }

        long length;
        try
        {
            // The length from the directory entry rather than from an open
            // stream: a FIFO or a device is not a file to embed, and opening
            // one for reading can block, or have no length to ask for.
            var info = new FileInfo(full);
            if (!info.Exists)
            {
                diagnostics.Error("SL0706", written.Span,
                    $"there is no file at '{full}' to embed");
                return null;
            }

            length = info.Length;

            // Then opened, where there is anything to read, so that a file this
            // user cannot read is reported here rather than by the assembler as
            // a compiler bug. Nothing reads an empty one.
            if (length > 0)
            {
                using var stream = new FileStream(
                    full, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            diagnostics.Error("SL0706", written.Span,
                $"'{full}' cannot be read, so it cannot be embedded: {e.Message}");
            return null;
        }

        // The length is one pointer-sized word, and on a 32-bit target the
        // whole address space is four gigabytes — half of it the system's.
        long limit = TargetPlatform.Current.PointerWidth == 8 ? long.MaxValue : int.MaxValue;
        if (length > limit)
        {
            diagnostics.Error("SL0706", written.Span,
                $"'{full}' is {length} bytes, more than an array on " +
                $"{TargetPlatform.Current.Triple} can hold");
            return null;
        }

        return (full, length);
    }

    /// <summary>What lld-link keeps of a long section name in a PE image.</summary>
    private static string TruncatedSectionName(string name)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(name);
        return Encoding.UTF8.GetString(bytes, 0, EmbeddedFile.ImageSectionNameLimit);
    }

    /// <summary>A string for a message, with the characters that would break one shown escaped.</summary>
    private static string Printable(string text)
    {
        var shown = new StringBuilder();
        foreach (char c in text)
        {
            if (char.IsControl(c))
                shown.Append("\\u").Append(((int)c).ToString("x4", CultureInfo.InvariantCulture));
            else
                shown.Append(c);
        }
        return shown.ToString();
    }
}
