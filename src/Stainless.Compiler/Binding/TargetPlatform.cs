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

/// <summary>The instruction set a program is being built for.</summary>
public enum TargetArch
{
    /// <summary>x86-64: what every build was before this existed.</summary>
    X64,

    /// <summary>32-bit x86. Pointers are four bytes and a declaration may name
    /// a calling convention.</summary>
    X86,

    /// <summary>64-bit ARM.</summary>
    Arm64,
}

/// <summary>
/// What the compiler is building for: how wide a pointer is, which C++ names to
/// write, and what to hand clang.
///
/// <para>
/// It exists because a pointer stopped being eight bytes. Everything that used
/// to read <c>8</c> -- <c>nuint</c>, a class reference, the object header --
/// reads <see cref="PointerWidth"/> now, and the runtime agrees because its own
/// header is three <c>size_t</c> rather than three fixed-width fields.
/// </para>
///
/// <para>
/// <b>It is ambient rather than threaded, and that is a real trade.</b> A type's
/// size is a property of the type <i>and</i> the target, so the honest signature
/// is <c>Size(target)</c> -- and there are 112 places that ask a type its size
/// or its alignment, none of which has a target to hand. Passing one to each
/// would be a larger change than the feature, and every one of those call sites
/// is inside a single compilation, which builds for exactly one target. So the
/// target is scoped to the compilation instead, and <see cref="Current"/> is
/// what the type system reads.
/// </para>
///
/// <para>
/// The scoping is <see cref="AsyncLocal{T}"/> rather than a plain static,
/// because the unit tests bind in parallel: a plain static would let a test
/// building for x86 change what a test building for x64 measures, and the
/// failure would be a wrong number rather than a crash.
/// </para>
/// </summary>
public sealed record TargetPlatform
{
    public required TargetArch Architecture { get; init; }

    /// <summary>How many bytes a pointer occupies.</summary>
    public required int PointerWidth { get; init; }

    /// <summary>Which scheme C++ names are written in.</summary>
    public required CppAbi Abi { get; init; }

    /// <summary>What clang is told to build for.</summary>
    public required string Triple { get; init; }

    /// <summary>True for a Microsoft target, which differs in more than names:
    /// the x86 struct-return rule and the decorated symbol are both Windows'.</summary>
    public bool IsWindows => Triple.Contains("windows", StringComparison.Ordinal);

    /// <summary>True where a declaration may name a calling convention and have
    /// it mean something. There is one convention on every 64-bit target.</summary>
    public bool HasCallingConventions => Architecture == TargetArch.X86;

    /// <summary>
    /// The object header: strong count, weak count, TypeInfo pointer. Three
    /// pointer-width words, which is what the runtime's <c>SlObject</c> is.
    /// </summary>
    public int ObjectHeaderSize => PointerWidth * 3;

    /// <summary>
    /// An array's header: the object header plus a length. Four pointer-width
    /// words, matching the runtime's <c>SlArray</c>.
    /// </summary>
    public int ArrayHeaderSize => PointerWidth * 4;

    /// <summary>
    /// The boundary a <c>long</c>, a <c>ulong</c> or a <c>double</c> starts on.
    ///
    /// Eight everywhere but i386 System V, where it is four: gcc and clang put
    /// the <c>long long</c> in <c>struct { int a; long long b; }</c> at offset
    /// 4 and make the struct 12 bytes, while MSVC on 32-bit Windows keeps the
    /// eight of every 64-bit ABI and makes it 16. Reading the size as the
    /// alignment, as every other primitive does, laid out every such struct
    /// for x86 Linux the Windows way.
    /// </summary>
    public int WideScalarAlignment => Architecture == TargetArch.X86 && !IsWindows ? 4 : 8;

    /// <summary>The LLVM integer type a <c>nuint</c> or a <c>nint</c> is.</summary>
    public string NativeIntType => PointerWidth == 8 ? "i64" : "i32";

    // ------------------------------------------------------------- the set

    public static readonly TargetPlatform X64Windows = new()
    {
        Architecture = TargetArch.X64,
        PointerWidth = 8,
        Abi = CppAbi.Microsoft,
        Triple = "x86_64-pc-windows-msvc",
    };

    public static readonly TargetPlatform X64Linux = new()
    {
        Architecture = TargetArch.X64,
        PointerWidth = 8,
        Abi = CppAbi.Itanium,
        Triple = "x86_64-pc-linux-gnu",
    };

    public static readonly TargetPlatform X86Windows = new()
    {
        Architecture = TargetArch.X86,
        PointerWidth = 4,
        Abi = CppAbi.Microsoft,
        Triple = "i686-pc-windows-msvc",
    };

    public static readonly TargetPlatform X86Linux = new()
    {
        Architecture = TargetArch.X86,
        PointerWidth = 4,
        Abi = CppAbi.Itanium,
        Triple = "i686-pc-linux-gnu",
    };

    /// <summary>
    /// 64-bit ARM, Microsoft's. The C++ names are Microsoft's here as they are
    /// on x64, and the argument passing is AAPCS64 either way -- which is the
    /// one architecture where the two systems agree about structs.
    /// </summary>
    public static readonly TargetPlatform Arm64Windows = new()
    {
        Architecture = TargetArch.Arm64,
        PointerWidth = 8,
        Abi = CppAbi.Microsoft,
        Triple = "aarch64-pc-windows-msvc",
    };

    public static readonly TargetPlatform Arm64Linux = new()
    {
        Architecture = TargetArch.Arm64,
        PointerWidth = 8,
        Abi = CppAbi.Itanium,
        Triple = "aarch64-unknown-linux-gnu",
    };

    /// <summary>
    /// The target a build gets when nothing names one: this machine, 64-bit.
    ///
    /// The architecture is asked for rather than assumed, because an ARM64 host
    /// is a real machine to be sitting at and taking x86-64 as the default
    /// there would build something it cannot run.
    ///
    /// <c>STAINLESS_CPP_ABI</c> still overrides the name mangling, which is how
    /// the scheme a host does not use gets exercised against a real compiler.
    /// </summary>
    public static TargetPlatform Host
    {
        get
        {
            bool windows = OperatingSystem.IsWindows();
            var native =
                System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture ==
                System.Runtime.InteropServices.Architecture.Arm64
                    ? windows ? Arm64Windows : Arm64Linux
                    : windows ? X64Windows : X64Linux;

            return native with { Abi = CppMangler.HostAbi };
        }
    }

    /// <summary>
    /// The target named on a command line, or null when the name is not one.
    /// Short names rather than triples, because a triple has four fields and
    /// three of them are never the interesting one.
    /// </summary>
    public static TargetPlatform? Parse(string name) => name.ToLowerInvariant() switch
    {
        "x64" or "x86_64" or "amd64" =>
            OperatingSystem.IsWindows() ? X64Windows : X64Linux,
        "x86" or "i686" or "i386" or "win32" =>
            OperatingSystem.IsWindows() ? X86Windows : X86Linux,
        "arm64" or "aarch64" =>
            OperatingSystem.IsWindows() ? Arm64Windows : Arm64Linux,

        "x64-windows" or "x86_64-windows" => X64Windows,
        "x64-linux" or "x86_64-linux" => X64Linux,
        "x86-windows" or "i686-windows" => X86Windows,
        "x86-linux" or "i686-linux" => X86Linux,
        "arm64-windows" or "aarch64-windows" => Arm64Windows,
        "arm64-linux" or "aarch64-linux" => Arm64Linux,

        _ => null,
    };

    /// <summary>Every name <see cref="Parse"/> accepts, for a diagnostic.</summary>
    public static string Names =>
        "x64, x86, arm64, x64-windows, x64-linux, x86-windows, x86-linux, " +
        "arm64-windows, arm64-linux";

    // ------------------------------------------------------------- ambient

    private static readonly AsyncLocal<TargetPlatform?> _current = new();

    /// <summary>
    /// What this compilation is building for. Setting it flows to everything
    /// the setting call goes on to do, and to nothing running beside it.
    /// </summary>
    public static TargetPlatform Current
    {
        get => _current.Value ?? Host;
        set => _current.Value = value;
    }

    public override string ToString() => Triple;
}
