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

namespace Stainless.Binding;

/// <summary>What an embedded file's memory may be used for, as <c>access:</c> spells it.</summary>
[Flags]
public enum EmbedAccess
{
    Read = 1,
    Write = 2,
    Execute = 4,
}

/// <summary>
/// One file carried in the binary by <c>embed</c>: which file, where it goes,
/// and what its memory may be used for.
///
/// <para>
/// There is one of these per distinct object, not per <c>embed</c> written.
/// Two that name the same file, section and access are the same bytes, so they
/// are one array: the object is immortal and has no identity worth keeping
/// apart, and a second copy would be the file twice in the binary for nothing.
/// </para>
///
/// <para>
/// Everything about how the object is spelled for an assembler is here rather
/// than in the emitter, because the binder has to ask the same questions first
/// — which section a default lands in, and what that section already is —
/// to refuse the combinations an assembler would silently get wrong.
/// </para>
/// </summary>
public sealed class EmbeddedFile(
    int index, string path, string section, EmbedAccess access, long length)
{
    /// <summary>Distinguishes this object's label from every other's.</summary>
    public int Index { get; } = index;

    /// <summary>The file, as a full path in the host's own spelling.</summary>
    public string Path { get; } = path;

    /// <summary>
    /// The section the object is placed in: the one written, or the target's
    /// default for the access when none was.
    /// </summary>
    public string Section { get; } = section;

    public EmbedAccess Access { get; } = access;

    /// <summary>
    /// How many bytes the file had when it was bound, which is the length word
    /// the object is given. The assembler is held to it — see
    /// <see cref="Assembly"/> — so a file that changes between binding and
    /// assembling cannot leave the length describing different bytes.
    /// </summary>
    public long Length { get; } = length;

    /// <summary>
    /// The object's symbol. Local to the object file, so every compilation can
    /// number its own from zero.
    /// </summary>
    public string Label => "_SLembed" + Index;

    // ------------------------------------------------------------ access

    /// <summary>
    /// <c>access:</c> as a set of flags, or null when it is not one.
    ///
    /// Each of r, w and x at most once, in any order, and r always: memory a
    /// program cannot read is not something a <c>byte[]</c> can describe, and
    /// a section with no read permission is one no object format here makes.
    /// </summary>
    public static EmbedAccess? ParseAccess(string written)
    {
        EmbedAccess access = 0;

        foreach (char letter in written)
        {
            EmbedAccess flag = letter switch
            {
                'r' => EmbedAccess.Read,
                'w' => EmbedAccess.Write,
                'x' => EmbedAccess.Execute,
                _ => 0,
            };

            if (flag == 0 || access.HasFlag(flag))
                return null;

            access |= flag;
        }

        return access.HasFlag(EmbedAccess.Read) ? access : null;
    }

    /// <summary>The access in the order the documentation writes it: r, w, x.</summary>
    public static string Spell(EmbedAccess access) =>
        "r" + (access.HasFlag(EmbedAccess.Write) ? "w" : "") +
        (access.HasFlag(EmbedAccess.Execute) ? "x" : "");

    // ----------------------------------------------------------- sections

    /// <summary>
    /// Where an embed with no <c>section:</c> goes, or null for the one
    /// access that has no default.
    ///
    /// Read-only data, writable data, and code — the sections the target's own
    /// compiler would have used for a <c>const</c> array, an initialized
    /// array, and a function. Writable and executable at once has no such
    /// section on any target, and quietly making one would be the wrong way to
    /// get memory that is both: it is something to ask for by name.
    /// </summary>
    public static string? DefaultSection(EmbedAccess access, TargetPlatform target) =>
        Spell(access) switch
        {
            "r" => target.IsWindows ? ".rdata" : ".rodata",
            "rw" => ".data",
            "rx" => ".text",
            _ => null,
        };

    /// <summary>
    /// Why a section name cannot be written into a directive, or null when it
    /// can.
    ///
    /// The name is quoted when it is written, so an assembler's comment and
    /// separator characters are safe inside it. What is refused is what no
    /// quoting settles: an empty name, a quote or a backslash, which would end
    /// or escape the quoting, and a comma, whitespace or a control character,
    /// which a linker script or a <c>/SECTION:</c> option could not name
    /// afterwards.
    /// </summary>
    public static string? SectionProblem(string name)
    {
        if (name.Length == 0)
            return "a section name cannot be empty";

        foreach (char c in name)
        {
            if (c is '"' or '\\')
                return $"a section name cannot contain '{c}'";
            if (c == ',')
                return "a section name cannot contain a comma";
            if (char.IsWhiteSpace(c))
                return "a section name cannot contain whitespace";
            if (char.IsControl(c))
                return "a section name cannot contain a control character";
        }

        return null;
    }

    /// <summary>
    /// The access a section already has on this target whatever a directive
    /// asks for, or null for a section this program is free to define.
    ///
    /// <b>An assembler does not take flags for a section it knows.</b> Checked
    /// against clang 22: <c>.section .text,"a"</c> on ELF and
    /// <c>.section .text,"dr"</c> on COFF both give an executable section,
    /// silently, and <c>.section .rodata,"aw"</c> is an error. So an embed
    /// asking for other access in one of these would be granted the section's
    /// access instead — writable data that faults, or data that executes —
    /// and the compiler refuses it rather than let the assembler decide.
    ///
    /// A suffix does not escape it. On ELF <c>.text.stub</c> asked for as
    /// <c>"a"</c> still comes out executable — the assembler adds the flags of
    /// the section the name extends — and on COFF the linker folds a
    /// <c>.text$stub</c> group into <c>.text</c> whatever its own flags were.
    /// So a name after a dot (ELF) or a dollar sign (COFF) is held to the
    /// section it extends. <see cref="EmbedAccess"/> 0 marks a section that
    /// holds no bytes at all.
    /// </summary>
    public static EmbedAccess? KnownSectionAccess(string name, TargetPlatform target)
    {
        (string Name, EmbedAccess Access)[] known = target.IsWindows
            ?
            [
                (".text", EmbedAccess.Read | EmbedAccess.Execute),
                (".data", EmbedAccess.Read | EmbedAccess.Write),
                (".rdata", EmbedAccess.Read),
                (".bss", 0),
            ]
            :
            [
                (".text", EmbedAccess.Read | EmbedAccess.Execute),
                (".data", EmbedAccess.Read | EmbedAccess.Write),
                (".rodata", EmbedAccess.Read),
                (".bss", 0),
                (".tdata", 0),
                (".tbss", 0),
            ];

        string separator = target.IsWindows ? "$" : ".";

        foreach (var (section, access) in known)
            if (name == section || name.StartsWith(section + separator, StringComparison.Ordinal))
                return access;

        return null;
    }

    /// <summary>
    /// The longest section name a PE image keeps. The header has eight bytes
    /// for it; an object file can hold a longer one through its string table,
    /// and lld-link then cuts it to eight in the image it links — checked with
    /// clang 22, where <c>.longsectionname</c> became <c>.longsec</c> with no
    /// diagnostic.
    /// </summary>
    public const int ImageSectionNameLimit = 8;

    // ----------------------------------------------------------- emission

    /// <summary>
    /// The object, as the assembly lines that make it — header words, then the
    /// file — for the module's <c>module asm</c>.
    ///
    /// <para>
    /// <b>Assembly rather than an IR global</b>, because only the assembly
    /// states a section's flags. An IR global with a <c>section</c> gets a
    /// section LLVM chooses the flags of: on ELF it becomes a second section of
    /// the same name beside the one a directive described. Writing the bytes in
    /// the directive's own section is the only placement that is the same on
    /// every format.
    /// </para>
    ///
    /// <para>
    /// <b>The type word is zero.</b> A pointer there would be a relocation, and
    /// a relocation in a read-only or executable section is refused when a
    /// position-independent Linux executable is linked. Nothing reads it: the
    /// counts are the immortal sentinel, which every retain and release checks
    /// before anything else, and an array's type information has no dispatch
    /// table, interfaces or COM layout for anything to look up.
    /// </para>
    ///
    /// <para>
    /// <c>.incbin</c> is given the length as a count, so a file that shrank
    /// after it was bound fails to assemble rather than leaving the length word
    /// longer than the bytes behind it.
    /// </para>
    /// </summary>
    public IReadOnlyList<string> Assembly(TargetPlatform target)
    {
        string word = target.PointerWidth == 8 ? ".quad" : ".long";
        string alignment = target.PointerWidth == 8 ? "3" : "2";

        var lines = new List<string>
        {
            SectionDirective(target),
            ".p2align " + alignment,
            Label + ":",
            word + " -1",           // strong: SL_IMMORTAL
            word + " -1",           // weak
            word + " 0",            // type: see above
            word + " " + Length,
        };

        // An empty file is a header with a length of zero, and `.incbin` of
        // nothing is a directive some assemblers read as "to the end".
        if (Length > 0)
            lines.Add($".incbin \"{AssemblerString(Path.Replace('\\', '/'))}\",0,{Length}");

        // Back to where LLVM expects to be: it writes its own section
        // directives, but anything it emits before the next one would land here.
        lines.Add(".text");
        return lines;
    }

    /// <summary>
    /// The <c>.section</c> line, in the syntax of the target's object format.
    ///
    /// COFF's flags are letters for what the section is and what it permits —
    /// <c>dr</c> read-only data, <c>dw</c> writable data, <c>xr</c> code,
    /// <c>xw</c> writable code — and ELF's are <c>a</c>llocated plus
    /// <c>w</c>rite and e<c>x</c>ecute. Each was checked with llvm-readobj on
    /// clang 22; <c>drwx</c> in particular loses its write permission, which
    /// is why the writable executable one is <c>xw</c>. The two syntaxes are
    /// not interchangeable: each is an assembler error on the other format.
    /// ELF's type is spelled <c>%progbits</c> rather than <c>@progbits</c>,
    /// because <c>@</c> starts a comment in some ARM assemblers.
    /// </summary>
    public string SectionDirective(TargetPlatform target)
    {
        bool write = Access.HasFlag(EmbedAccess.Write);
        bool execute = Access.HasFlag(EmbedAccess.Execute);
        string name = AssemblerString(Section);

        if (target.IsWindows)
        {
            string flags = (execute, write) switch
            {
                (false, false) => "dr",
                (false, true) => "dw",
                (true, false) => "xr",
                (true, true) => "xw",
            };
            return $".section \"{name}\",\"{flags}\"";
        }

        return $".section \"{name}\",\"a{(write ? "w" : "")}{(execute ? "x" : "")}\",%progbits";
    }

    /// <summary>Text inside an assembler's double quotes.</summary>
    private static string AssemblerString(string text) =>
        text.Replace("\\", "\\\\").Replace("\"", "\\\"");

    /// <summary>
    /// A line of assembly as the body of an IR <c>module asm "..."</c>.
    ///
    /// LLVM's string escapes are a backslash and two hex digits, so a quote is
    /// <c>\22</c> and a backslash <c>\5C</c>; every byte outside printable
    /// ASCII is escaped the same way, which is what keeps a path with a
    /// non-ASCII directory name intact.
    /// </summary>
    public static string IrString(string line)
    {
        var escaped = new StringBuilder();
        foreach (byte b in Encoding.UTF8.GetBytes(line))
        {
            if (b is >= 0x20 and < 0x7F && b != (byte)'"' && b != (byte)'\\')
                escaped.Append((char)b);
            else
                escaped.Append('\\').Append(b.ToString("X2", CultureInfo.InvariantCulture));
        }
        return escaped.ToString();
    }
}
