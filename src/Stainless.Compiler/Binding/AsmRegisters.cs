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

namespace Stainless.Binding;

/// <summary>What a register can hold, as far as an <c>asm</c> operand is concerned.</summary>
public enum AsmRegisterKind
{
    /// <summary>An integer register: integers, <c>bool</c>, enums, pointers.</summary>
    General,

    /// <summary>A vector register, which an operand uses for one <c>float</c> or <c>double</c>.</summary>
    Vector,
}

/// <summary>
/// One register name an <c>asm</c> operand may write.
/// </summary>
/// <param name="Name">The name as the table spells it, in lower case.</param>
/// <param name="Whole">
/// The register the name is part of: <c>rax</c> for <c>eax</c>, <c>v3</c> for
/// <c>d3</c>. Two operands naming the same whole register name one register,
/// and this is also the spelling LLVM honours in a clobber.
/// </param>
/// <param name="Bits">
/// How many bits the name reaches. Zero for a vector register named whole,
/// which holds a <c>float</c> or a <c>double</c> equally.
/// </param>
/// <param name="Refusal">
/// Why the register cannot be an operand at all, or null when it can.
/// </param>
public sealed record AsmRegister(
    string Name, string Whole, int Bits, AsmRegisterKind Kind, string? Refusal = null);

/// <summary>
/// The registers of each architecture an <c>asm</c> statement can name, and
/// the ones a block is assumed to change.
///
/// <para>
/// <b>Every register a C call may change is declared changed by every
/// block.</b> The alternative, Rust's, is to make the author list each one; a
/// list that is wrong by one register is then a miscompilation that depends on
/// which value the optimiser happened to keep there, so it passes at one
/// optimisation level and fails at another. The cost of the rule chosen here
/// is that a value live across a block cannot stay in a volatile register — it
/// moves to a callee-saved one or to the stack, exactly as it would across a
/// call. A block is at worst as expensive to have around as a call to the same
/// instructions, and that is the price of never getting the list wrong.
/// </para>
///
/// <para>
/// A callee-saved register the block changes, it restores. That is what a C
/// function promises, and the same promise is asked for the same reason: the
/// alternative would be declaring every register changed, which makes the
/// enclosing function save all of them whether or not the block touched one.
/// </para>
///
/// <para>
/// The spellings of the whole registers are the ones LLVM honours, which is
/// not always the one it accepts. <c>~{x30}</c> on AArch64 parses and is
/// silently ignored — the function then does not save its link register — and
/// <c>~{lr}</c> is what works. <c>{x29}</c> and <c>{x30}</c> as operands are
/// refused outright where <c>{fp}</c> and <c>{lr}</c> are not.
/// </para>
/// </summary>
public static class AsmRegisters
{
    /// <summary>The register of that name on the target, or null when there is none.</summary>
    public static AsmRegister? Find(TargetPlatform target, string name)
    {
        var table = target.Architecture switch
        {
            TargetArch.X64 => X64,
            TargetArch.X86 => X86,
            _ => target.IsWindows ? Arm64Windows : Arm64Linux,
        };

        return table.TryGetValue(name.ToLowerInvariant(), out var register) ? register : null;
    }

    /// <summary>
    /// The registers a block is assumed to change on the target, in the
    /// spelling a clobber takes: the ones a C call may change.
    /// </summary>
    public static IReadOnlyList<string> Volatile(TargetPlatform target) => target.Architecture switch
    {
        TargetArch.X64 => target.IsWindows ? Win64Volatile : SysVVolatile,
        TargetArch.X86 => X86Volatile,
        _ => target.IsWindows ? Arm64WindowsVolatile : Arm64LinuxVolatile,
    };

    /// <summary>
    /// Everything a block is declared to change, in the order the clobbers are
    /// written: the volatile set, then the register of any operand not already
    /// in it, then the flags.
    ///
    /// <para>
    /// <b>An operand's register is always among them</b>, callee-saved or not.
    /// LLVM reads an input register that is not declared clobbered as still
    /// holding its value after the block, and will read it from there: a block
    /// that zeroed <c>rcx</c> after taking <c>{rcx}</c> had the value it
    /// destroyed added into the result. Declaring it costs nothing for a
    /// volatile register, and for a callee-saved one it is what makes the
    /// function save and restore it, so a block may leave <c>rbx</c> changed
    /// once it has named it.
    /// </para>
    ///
    /// <para>
    /// On x86 the flags are the three clang writes for every inline assembly
    /// it emits. On ARM64 <c>nzcv</c> is the same fact spelled for that
    /// machine.
    /// </para>
    /// </summary>
    public static IReadOnlyList<string> Clobbers(TargetPlatform target, IEnumerable<AsmRegister> operands)
    {
        var clobbers = new List<string>(Volatile(target));

        foreach (var register in operands)
            if (!clobbers.Contains(register.Whole))
                clobbers.Add(register.Whole);

        if (target.Architecture == TargetArch.Arm64)
            clobbers.Add("nzcv");
        else
            clobbers.AddRange(["dirflag", "fpsr", "flags"]);

        return clobbers;
    }

    /// <summary>
    /// A few names a person might try, for the message that says a name is not
    /// a register. Not the whole table: that would be the message.
    /// </summary>
    public static string Examples(TargetPlatform target) => target.Architecture switch
    {
        TargetArch.X64 => "rax to r15, eax to r15d, ax to r15w, al to r15b, and xmm0 to xmm15",
        TargetArch.X86 => "eax, ebx, ecx, edx, esi and edi, their 16- and 8-bit names, and xmm0 " +
                          "to xmm7",
        _ => "x0 to x30, w0 to w30, and v0 to v31 with their d and s names",
    };

    /// <summary>What the architecture is called in a message.</summary>
    public static string ArchitectureName(TargetPlatform target) => target.Architecture switch
    {
        TargetArch.X64 => "x64",
        TargetArch.X86 => "x86",
        _ => "arm64",
    };

    /// <summary>
    /// The constraint LLVM is given for an operand: the name as written on x86,
    /// where every width of a register has a name LLVM takes.
    ///
    /// On ARM64 two things differ. The link register is <c>lr</c> to LLVM,
    /// which refuses <c>x30</c>. And a vector register is spelled by the width
    /// of what it carries, <c>s</c> for a <c>float</c> and <c>d</c> for a
    /// <c>double</c>: <c>{v0}</c> with a <c>float</c> crashes the code
    /// generator, and <c>{d0}</c> with one converts the value to a double on
    /// the way in, which is a different number of bits in the register.
    /// </summary>
    public static string Constraint(TargetPlatform target, AsmRegister register, bool isSingle)
    {
        if (target.Architecture != TargetArch.Arm64) return register.Name;

        if (register.Kind == AsmRegisterKind.Vector)
            return (isSingle ? "s" : "d") + register.Whole[1..];

        return register.Name == "x30" ? "lr" : register.Name;
    }

    // ------------------------------------------------------------- x86-64

    private static readonly Dictionary<string, AsmRegister> X64 = BuildX64();

    private static Dictionary<string, AsmRegister> BuildX64()
    {
        var table = new Dictionary<string, AsmRegister>(StringComparer.Ordinal);

        // The eight registers x86 has always had, each with four names.
        (string, string, string, string, string?)[] legacy =
        [
            ("rax", "eax", "ax", "al", null),
            ("rbx", "ebx", "bx", "bl", null),
            ("rcx", "ecx", "cx", "cl", null),
            ("rdx", "edx", "dx", "dl", null),
            ("rsi", "esi", "si", "sil", null),
            ("rdi", "edi", "di", "dil", null),
            ("rbp", "ebp", "bp", "bpl", FramePointer),
            ("rsp", "esp", "sp", "spl", StackPointer),
        ];

        foreach (var (wide, half, word, low, refusal) in legacy)
            AddGeneral(table, wide, refusal, (wide, 64), (half, 32), (word, 16), (low, 8));

        for (int i = 8; i <= 15; i++)
        {
            string wide = $"r{i}";
            AddGeneral(table, wide, null, (wide, 64), ($"r{i}d", 32), ($"r{i}w", 16), ($"r{i}b", 8));
        }

        for (int i = 0; i <= 15; i++)
            table[$"xmm{i}"] = new AsmRegister($"xmm{i}", $"xmm{i}", 0, AsmRegisterKind.Vector);

        return table;
    }

    // ------------------------------------------------------------- x86

    private static readonly Dictionary<string, AsmRegister> X86 = BuildX86();

    private static Dictionary<string, AsmRegister> BuildX86()
    {
        var table = new Dictionary<string, AsmRegister>(StringComparer.Ordinal);

        AddGeneral(table, "eax", null, ("eax", 32), ("ax", 16), ("al", 8));
        AddGeneral(table, "ebx", null, ("ebx", 32), ("bx", 16), ("bl", 8));
        AddGeneral(table, "ecx", null, ("ecx", 32), ("cx", 16), ("cl", 8));
        AddGeneral(table, "edx", null, ("edx", 32), ("dx", 16), ("dl", 8));

        // No byte names: 'sil' and 'dil' need a REX prefix, which 32-bit code
        // does not have.
        AddGeneral(table, "esi", null, ("esi", 32), ("si", 16));
        AddGeneral(table, "edi", null, ("edi", 32), ("di", 16));

        table["ebp"] = new AsmRegister("ebp", "ebp", 32, AsmRegisterKind.General, FramePointer);
        table["bp"] = new AsmRegister("bp", "ebp", 16, AsmRegisterKind.General, FramePointer);
        table["esp"] = new AsmRegister("esp", "esp", 32, AsmRegisterKind.General, StackPointer);
        table["sp"] = new AsmRegister("sp", "esp", 16, AsmRegisterKind.General, StackPointer);

        for (int i = 0; i <= 7; i++)
            table[$"xmm{i}"] = new AsmRegister($"xmm{i}", $"xmm{i}", 0, AsmRegisterKind.Vector);

        return table;
    }

    // ------------------------------------------------------------- ARM64

    private static readonly Dictionary<string, AsmRegister> Arm64Linux = BuildArm64(windows: false);
    private static readonly Dictionary<string, AsmRegister> Arm64Windows = BuildArm64(windows: true);

    private static Dictionary<string, AsmRegister> BuildArm64(bool windows)
    {
        var table = new Dictionary<string, AsmRegister>(StringComparer.Ordinal);

        for (int i = 0; i <= 30; i++)
        {
            // x30 is named 'lr' in a clobber, because that is the only spelling
            // LLVM acts on; see the class remarks.
            string whole = i == 30 ? "lr" : $"x{i}";

            string? refusal = i switch
            {
                29 => FramePointer,
                18 when windows =>
                    "reserved by Windows, which keeps the current thread's environment block " +
                    "in it; nothing but the system may change it",
                _ => null,
            };

            AddGeneral(table, whole, refusal, ($"x{i}", 64), ($"w{i}", 32));
        }

        table["lr"] = new AsmRegister("lr", "lr", 64, AsmRegisterKind.General);
        table["fp"] = new AsmRegister("fp", "x29", 64, AsmRegisterKind.General, FramePointer);
        table["sp"] = new AsmRegister("sp", "sp", 64, AsmRegisterKind.General, StackPointer);
        table["wsp"] = new AsmRegister("wsp", "sp", 32, AsmRegisterKind.General, StackPointer);

        for (int i = 0; i <= 31; i++)
        {
            string whole = $"v{i}";
            table[whole] = new AsmRegister(whole, whole, 0, AsmRegisterKind.Vector);
            table[$"d{i}"] = new AsmRegister($"d{i}", whole, 64, AsmRegisterKind.Vector);
            table[$"s{i}"] = new AsmRegister($"s{i}", whole, 32, AsmRegisterKind.Vector);
        }

        return table;
    }

    // ------------------------------------------------------------- the sets

    /// <summary>
    /// Microsoft x64: <c>rax</c>, <c>rcx</c>, <c>rdx</c>, <c>r8</c> to
    /// <c>r11</c>, and <c>xmm0</c> to <c>xmm5</c>. <c>rsi</c>, <c>rdi</c> and
    /// <c>xmm6</c> up are the callee's to preserve.
    /// </summary>
    private static readonly string[] Win64Volatile =
    [
        "rax", "rcx", "rdx", "r8", "r9", "r10", "r11",
        "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5",
    ];

    /// <summary>
    /// System V AMD64: <c>rsi</c> and <c>rdi</c> carry arguments and so are
    /// not preserved, and no vector register is.
    /// </summary>
    private static readonly string[] SysVVolatile =
    [
        "rax", "rcx", "rdx", "rsi", "rdi", "r8", "r9", "r10", "r11",
        .. Enumerable.Range(0, 16).Select(i => $"xmm{i}"),
    ];

    /// <summary>
    /// 32-bit x86, the same on both systems: three general registers, and
    /// every vector register, since none carries anything across a call there.
    /// </summary>
    private static readonly string[] X86Volatile =
    [
        "eax", "ecx", "edx",
        .. Enumerable.Range(0, 8).Select(i => $"xmm{i}"),
    ];

    /// <summary>
    /// AAPCS64: <c>x0</c> to <c>x17</c> and the link register, and the vector
    /// registers but <c>v8</c> to <c>v15</c>, whose low halves the callee
    /// keeps. <c>x18</c> is the platform register, and Linux leaves it to be
    /// used as a temporary.
    /// </summary>
    private static readonly string[] Arm64LinuxVolatile =
    [
        .. Enumerable.Range(0, 19).Select(i => $"x{i}"),
        "lr",
        .. Enumerable.Range(0, 8).Select(i => $"v{i}"),
        .. Enumerable.Range(16, 16).Select(i => $"v{i}"),
    ];

    /// <summary>
    /// The same, less <c>x18</c>: Windows keeps the thread environment block in
    /// it, so it is not something a block may change, let alone something to
    /// declare changed.
    /// </summary>
    private static readonly string[] Arm64WindowsVolatile =
    [
        .. Enumerable.Range(0, 18).Select(i => $"x{i}"),
        "lr",
        .. Enumerable.Range(0, 8).Select(i => $"v{i}"),
        .. Enumerable.Range(16, 16).Select(i => $"v{i}"),
    ];

    private const string StackPointer =
        "the stack pointer; a block that moved it would leave every local in the function " +
        "at the wrong address";

    private const string FramePointer =
        "the frame pointer, which the function may address its own locals through";

    private static void AddGeneral(
        Dictionary<string, AsmRegister> table, string whole, string? refusal,
        params (string Name, int Bits)[] names)
    {
        foreach (var (name, bits) in names)
            table[name] = new AsmRegister(name, whole, bits, AsmRegisterKind.General, refusal);
    }
}
