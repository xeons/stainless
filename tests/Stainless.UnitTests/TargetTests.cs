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

using Stainless.Binding;
using Stainless.Driver;
using Xunit;
using ProcessArchitecture = System.Runtime.InteropServices.Architecture;

namespace Stainless.UnitTests;

/// <summary>
/// What a target decides: how wide a pointer is, what the headers measure, and
/// how a calling convention decorates a name.
///
/// <para>
/// The end-to-end cases under tests/cases/x86-* prove a 32-bit program runs and
/// prints the right numbers, which is the test that matters. These are the ones
/// that would still fail if it printed the right numbers by accident: a byte
/// count that is right for the wrong arguments, a header that measures correctly
/// at one width and not the other.
/// </para>
/// </summary>
public class TargetTests
{
    /// <summary>
    /// Every target is restored after each test.
    ///
    /// <see cref="TargetPlatform.Current"/> is an <c>AsyncLocal</c>, so a value
    /// set here does not escape into a test running beside this one. Putting it
    /// back anyway keeps the tests in this class independent of their order.
    /// </summary>
    private static void Under(TargetPlatform target, Action body)
    {
        var before = TargetPlatform.Current;
        TargetPlatform.Current = target;
        try { body(); }
        finally { TargetPlatform.Current = before; }
    }

    // ----------------------------------------------------------- the widths

    [Fact]
    public void PointerIsEightBytesOn64Bit()
    {
        Under(TargetPlatform.X64Windows, () =>
        {
            Assert.Equal(8, PrimitiveTypeSymbol.NUInt.Size);
            Assert.Equal(8, PrimitiveTypeSymbol.NInt.Size);
        });
    }

    [Fact]
    public void PointerIsFourBytesOnX86()
    {
        Under(TargetPlatform.X86Windows, () =>
        {
            Assert.Equal(4, PrimitiveTypeSymbol.NUInt.Size);
            Assert.Equal(4, PrimitiveTypeSymbol.NInt.Size);
        });
    }

    /// <summary>Every other primitive is the same width everywhere.</summary>
    [Fact]
    public void FixedWidthPrimitivesDoNotMove()
    {
        Under(TargetPlatform.X86Windows, () =>
        {
            Assert.Equal(1, PrimitiveTypeSymbol.Byte.Size);
            Assert.Equal(2, PrimitiveTypeSymbol.Short.Size);
            Assert.Equal(4, PrimitiveTypeSymbol.Int.Size);
            Assert.Equal(8, PrimitiveTypeSymbol.Long.Size);
            Assert.Equal(8, PrimitiveTypeSymbol.Double.Size);
        });
    }

    private const string WideFields = """
        struct IntLong { public int A; public long B; }
        struct ByteDouble { public byte A; public double B; public int C; }
        struct Closed { public int A; public Op F; public int B; }
        public closure int Op(int x);
        """;

    /// <summary>
    /// A <c>long</c> or a <c>double</c> starts on a four-byte boundary inside an
    /// i386 System V struct and an eight-byte one everywhere else. The x86 case
    /// that checks this against clang only runs on Linux, so this is what holds
    /// it on a Windows machine.
    /// </summary>
    [Theory]
    [InlineData("x86-linux", 12, 4, 16, 4, 12)]
    [InlineData("x86-windows", 16, 8, 24, 8, 16)]
    [InlineData("x64-linux", 16, 8, 24, 8, 16)]
    [InlineData("arm64-linux", 16, 8, 24, 8, 16)]
    public void WideScalarsAlignAsTheTargetsCDoes(
        string target, int intLong, int longAt, int byteDouble, int doubleAt, int intAt) =>
        Under(TargetPlatform.Parse(target)!, () =>
        {
            var first = Front.Struct(WideFields, "IntLong");
            Assert.Equal(intLong, first.Size);
            Assert.Equal(longAt, first.Fields[1].Offset);

            var second = Front.Struct(WideFields, "ByteDouble");
            Assert.Equal(byteDouble, second.Size);
            Assert.Equal(doubleAt, second.Fields[1].Offset);
            Assert.Equal(intAt, second.Fields[2].Offset);
        });

    /// <summary>
    /// A bit-field is reached through no more bytes than it needs. On i386
    /// System V `struct { sbyte c; long x : 3; }` is four bytes holding an
    /// eight-byte unit, and loading the whole unit read past the value's end.
    /// </summary>
    [Fact]
    public void ABitFieldIsNotReadPastItsStruct() =>
        Under(TargetPlatform.X86Linux, () =>
        {
            const string source = """
                public struct G { public sbyte C; public long X : 3; }
                public long Read(G g) => g.X;
                public G Write(G g) { g.X = -2; return g; }
                """;

            // The bit-field rules are the ABI's, and this host's is not Linux's.
            string ir = Front.ModuleIr(source, CppAbi.Itanium);
            var program = Front.BindModule(source, out _, CppAbi.Itanium);
            Assert.Equal(4, program.Structs.First(s => s.Name == "G").Size);

            var bodies = Bodies(ir, "4Test4Read", "4Test5Write");
            // The unit is loaded and stored with its alignment stated; the
            // function's own i64 return slot is not, and is not the question.
            Assert.Contains("load i16", bodies);
            Assert.DoesNotMatch(@"(load i64|store i64 \S+), ptr \S+, align", bodies);
        });

    private static string Bodies(string ir, params string[] names) =>
        string.Join("\n", names.Select(name =>
        {
            int definition = ir.IndexOf(name, StringComparison.Ordinal);
            int from = ir.LastIndexOf("define", definition, StringComparison.Ordinal);
            int to = ir.IndexOf("\n}", definition, StringComparison.Ordinal);
            return ir[from..to];
        }));

    /// <summary>A closure is two pointers, whatever a pointer measures.</summary>
    [Theory]
    [InlineData("x86-windows", 4, 8, 12, 16)]
    [InlineData("x64-windows", 8, 16, 24, 32)]
    public void AClosureIsTwoWords(string target, int closureAt, int closureSize, int afterAt, int size) =>
        Under(TargetPlatform.Parse(target)!, () =>
        {
            var type = Front.Struct(WideFields, "Closed");
            Assert.Equal(closureAt, type.Fields[1].Offset);
            Assert.Equal(closureSize, type.Fields[1].Type.Size);
            Assert.Equal(afterAt, type.Fields[2].Offset);
            Assert.Equal(size, type.Size);
        });

    /// <summary>
    /// Every integer type reaches one of <c>Text.FromInteger</c>'s overloads on
    /// every target. Which overload is exact moves with the width of
    /// <c>nuint</c>, so a rule that only worked because two types happened to be
    /// the same size would pass on one target and not another.
    /// </summary>
    [Theory]
    [InlineData("x64-windows")]
    [InlineData("x86-windows")]
    [InlineData("x86-linux")]
    [InlineData("arm64-linux")]
    public void EveryIntegerHasAFromInteger(string target) =>
        Under(TargetPlatform.Parse(target)!, () =>
        {
            string[] types = ["sbyte", "byte", "short", "ushort", "int", "uint", "long", "ulong", "nint", "nuint"];
            string body = string.Join("\n", types.Select((t, i) =>
                $"    {t} v{i} = 1; String s{i} = Text.FromInteger(v{i}); String i{i} = $\"{{v{i}}}\";"));

            Front.BindBody(body + "\n    String literal = Text.FromInteger(42);", out var diagnostics);
            Assert.Empty(Front.Codes(diagnostics));
        });

    /// <summary>
    /// The two headers are three and four words, which is what the runtime's
    /// <c>SlObject</c> and <c>SlArray</c> are. They disagreed before the target
    /// work, and the disagreement was silent.
    /// </summary>
    [Fact]
    public void HeadersAreCountedInWords()
    {
        Under(TargetPlatform.X64Windows, () =>
        {
            Assert.Equal(24, ClassTypeSymbol.HeaderSize);
            Assert.Equal(32, ArrayTypeSymbol.HeaderSize);
        });

        Under(TargetPlatform.X86Windows, () =>
        {
            Assert.Equal(12, ClassTypeSymbol.HeaderSize);
            Assert.Equal(16, ArrayTypeSymbol.HeaderSize);
        });
    }

    [Fact]
    public void NativeIntegerIsSpelledForTheTarget()
    {
        Assert.Equal("i64", TargetPlatform.X64Linux.NativeIntType);
        Assert.Equal("i32", TargetPlatform.X86Linux.NativeIntType);
    }

    /// <summary>clang's own default for i686 Linux has no SSE in some versions.</summary>
    [Fact]
    public void X86NamesAProcessorWithSse2()
    {
        Assert.Equal("pentium4", TargetPlatform.X86Linux.Cpu);
        Assert.Equal("pentium4", TargetPlatform.X86Windows.Cpu);
        Assert.Null(TargetPlatform.X64Linux.Cpu);
    }

    // ------------------------------------------------------------- the names

    [Theory]
    [InlineData("x86", 4)]
    [InlineData("i686", 4)]
    [InlineData("x86-windows", 4)]
    [InlineData("x86-linux", 4)]
    [InlineData("x64", 8)]
    [InlineData("amd64", 8)]
    [InlineData("x64-linux", 8)]
    public void NamedTargetsParse(string name, int pointerWidth)
    {
        // A bare name takes the host's system, and a Mac has no 32-bit one, so
        // the host is fixed here; the per-host answers are tested on their own.
        var target = TargetPlatform.Parse(name, TargetOS.Linux);

        Assert.NotNull(target);
        Assert.Equal(pointerWidth, target!.PointerWidth);
    }

    [Fact]
    public void AnUnknownTargetIsNotGuessedAt()
    {
        Assert.Null(TargetPlatform.Parse("sparc"));
        Assert.Null(TargetPlatform.Parse(""));
        Assert.Null(TargetPlatform.RefusalFor("sparc", TargetOS.MacOS));
    }

    [Theory]
    [InlineData("arm64-macos", "Arm64MacOS")]
    [InlineData("aarch64-macos", "Arm64MacOS")]
    [InlineData("arm64-darwin", "Arm64MacOS")]
    [InlineData("aarch64-darwin", "Arm64MacOS")]
    [InlineData("ARM64-MacOS", "Arm64MacOS")]
    [InlineData("x64-macos", "X64MacOS")]
    [InlineData("x86_64-macos", "X64MacOS")]
    [InlineData("x64-darwin", "X64MacOS")]
    [InlineData("x86_64-darwin", "X64MacOS")]
    [InlineData("x64-windows", "X64Windows")]
    [InlineData("arm64-linux", "Arm64Linux")]
    public void ASystemNamedIsTheSystemWhateverTheHost(string name, string expected)
    {
        foreach (var host in Enum.GetValues<TargetOS>())
            Assert.Same(Instance(expected), TargetPlatform.Parse(name, host));
    }

    /// <summary>A bare architecture takes the host's system.</summary>
    [Theory]
    [InlineData("x64", TargetOS.Windows, "X64Windows")]
    [InlineData("x64", TargetOS.Linux, "X64Linux")]
    [InlineData("x64", TargetOS.MacOS, "X64MacOS")]
    [InlineData("amd64", TargetOS.MacOS, "X64MacOS")]
    [InlineData("arm64", TargetOS.Windows, "Arm64Windows")]
    [InlineData("arm64", TargetOS.Linux, "Arm64Linux")]
    [InlineData("arm64", TargetOS.MacOS, "Arm64MacOS")]
    [InlineData("aarch64", TargetOS.MacOS, "Arm64MacOS")]
    [InlineData("x86", TargetOS.Windows, "X86Windows")]
    [InlineData("x86", TargetOS.Linux, "X86Linux")]
    public void ABareArchitectureTakesTheHostSystem(string name, TargetOS host, string expected)
    {
        Assert.Same(Instance(expected), TargetPlatform.Parse(name, host));
        Assert.Null(TargetPlatform.RefusalFor(name, host));
    }

    /// <summary>Darwin has no 32-bit target, and saying so beats "unknown".</summary>
    [Theory]
    [InlineData("x86", TargetOS.MacOS)]
    [InlineData("i686", TargetOS.MacOS)]
    [InlineData("i386", TargetOS.MacOS)]
    [InlineData("x86-macos", TargetOS.Windows)]
    [InlineData("i686-darwin", TargetOS.Linux)]
    public void A32BitMacIsRefusedWithAReason(string name, TargetOS host)
    {
        Assert.Null(TargetPlatform.Parse(name, host));
        Assert.Contains("macOS has no 32-bit target", TargetPlatform.RefusalFor(name, host));
    }

    [Fact]
    public void AnX86NamedWithItsSystemStillParsesOnAMac()
    {
        Assert.Same(TargetPlatform.X86Linux, TargetPlatform.Parse("x86-linux", TargetOS.MacOS));
        Assert.Same(TargetPlatform.X86Windows, TargetPlatform.Parse("x86-windows", TargetOS.MacOS));
    }

    [Theory]
    [InlineData(TargetOS.Windows, ProcessArchitecture.X64, "X64Windows")]
    [InlineData(TargetOS.Windows, ProcessArchitecture.Arm64, "Arm64Windows")]
    [InlineData(TargetOS.Linux, ProcessArchitecture.X64, "X64Linux")]
    [InlineData(TargetOS.Linux, ProcessArchitecture.Arm64, "Arm64Linux")]
    [InlineData(TargetOS.MacOS, ProcessArchitecture.X64, "X64MacOS")]
    [InlineData(TargetOS.MacOS, ProcessArchitecture.Arm64, "Arm64MacOS")]
    public void TheHostMapsToItsOwnSystem(
        TargetOS os, ProcessArchitecture architecture, string expected)
    {
        Assert.Same(Instance(expected), TargetPlatform.HostFor(os, architecture));
    }

    [Fact]
    public void TheHostIsThisMachine()
    {
        var host = TargetPlatform.Host;

        Assert.Equal(TargetPlatform.HostOS, host.Os);
        Assert.Equal(OperatingSystem.IsWindows(), host.IsWindows);
        Assert.Equal(OperatingSystem.IsMacOS(), host.IsDarwin);
        Assert.Equal(8, host.PointerWidth);
    }

    /// <summary>Every name round-trips, and every instance has one.</summary>
    [Theory]
    [InlineData("X64Windows", "x64-windows", TargetOS.Windows, ObjectFormat.Coff)]
    [InlineData("X86Windows", "x86-windows", TargetOS.Windows, ObjectFormat.Coff)]
    [InlineData("Arm64Windows", "arm64-windows", TargetOS.Windows, ObjectFormat.Coff)]
    [InlineData("X64Linux", "x64-linux", TargetOS.Linux, ObjectFormat.Elf)]
    [InlineData("X86Linux", "x86-linux", TargetOS.Linux, ObjectFormat.Elf)]
    [InlineData("Arm64Linux", "arm64-linux", TargetOS.Linux, ObjectFormat.Elf)]
    [InlineData("X64MacOS", "x64-macos", TargetOS.MacOS, ObjectFormat.MachO)]
    [InlineData("Arm64MacOS", "arm64-macos", TargetOS.MacOS, ObjectFormat.MachO)]
    public void EachTargetKnowsItsSystemAndFormat(
        string instance, string name, TargetOS os, ObjectFormat format)
    {
        var target = Instance(instance);

        Assert.Equal(name, target.Name);
        Assert.Same(target, TargetPlatform.Parse(name, TargetOS.Windows));
        Assert.Contains(name, TargetPlatform.Names);
        Assert.Equal(os, target.Os);
        Assert.Equal(format, target.Format);
        Assert.Equal(os == TargetOS.Windows, target.IsWindows);
        Assert.Equal(os == TargetOS.Linux, target.IsLinux);
        Assert.Equal(os == TargetOS.MacOS, target.IsDarwin);
        Assert.Equal(format == ObjectFormat.MachO, target.IsMachO);
    }

    /// <summary>What clang says for these triples: LP64, Itanium names, its
    /// own CPU, eight-byte doubles and one calling convention.</summary>
    [Fact]
    public void TheMacTargetsAreDarwin()
    {
        Assert.Equal("arm64-apple-macosx15.0", TargetPlatform.Arm64MacOS.Triple);
        Assert.Equal("x86_64-apple-macosx15.0", TargetPlatform.X64MacOS.Triple);

        foreach (var mac in new[] { TargetPlatform.Arm64MacOS, TargetPlatform.X64MacOS })
        {
            Assert.Equal(8, mac.PointerWidth);
            Assert.Equal(CppAbi.Itanium, mac.Abi);
            Assert.Null(mac.Cpu);
            Assert.False(mac.HasCallingConventions);
            Assert.Equal(8, mac.WideScalarAlignment);
            Assert.Equal("i64", mac.NativeIntType);
            Assert.Equal(24, mac.ObjectHeaderSize);
            Assert.Equal(32, mac.ArrayHeaderSize);
        }

        Assert.Equal(TargetArch.Arm64, TargetPlatform.Arm64MacOS.Architecture);
        Assert.Equal(TargetArch.X64, TargetPlatform.X64MacOS.Architecture);
    }

    private static TargetPlatform Instance(string name) =>
        (TargetPlatform)typeof(TargetPlatform).GetField(name)!.GetValue(null)!;

    /// <summary>The system decides the C++ scheme, which decides the mangling.</summary>
    [Fact]
    public void EachTargetCarriesItsAbi()
    {
        Assert.Equal(CppAbi.Microsoft, TargetPlatform.X86Windows.Abi);
        Assert.Equal(CppAbi.Itanium, TargetPlatform.X86Linux.Abi);
        Assert.True(TargetPlatform.X86Windows.IsWindows);
        Assert.False(TargetPlatform.X86Linux.IsWindows);
    }

    /// <summary>There is one convention on every 64-bit target.</summary>
    [Fact]
    public void OnlyX86HasCallingConventions()
    {
        Assert.True(TargetPlatform.X86Windows.HasCallingConventions);
        Assert.False(TargetPlatform.X64Windows.HasCallingConventions);
    }

    // ------------------------------------------- the module definition file

    private const string ComServer =
        "module Server;\n" +
        "import Standard.Com;\n" +
        "export \"C\" __stdcall int DllGetClassObject(Guid* a, Guid* b, byte** c) { return 0; }\n" +
        "export \"C\" __stdcall int DllCanUnloadNow() { return 1; }\n" +
        "export \"C\" int Plain(int n) { return n; }\n";

    /// <summary>
    /// On x86 a convention decorates the symbol, and the export table has to
    /// carry the name the source wrote: Windows' COM loader looks up
    /// <c>DllGetClassObject</c>, not <c>_DllGetClassObject@12</c>.
    /// </summary>
    [Fact]
    public void ADecoratedExportIsRenamedByTheModuleDefinition() =>
        Under(TargetPlatform.X86Windows, () =>
        {
            var program = Front.Bind(ComServer, out var diagnostics);
            Assert.Empty(Front.Codes(diagnostics));

            string definition = Assert.IsType<string>(ModuleDefinition.For(program));

            Assert.Contains("DllGetClassObject = _DllGetClassObject@12", definition);
            Assert.Contains("DllCanUnloadNow = _DllCanUnloadNow@0", definition);

            // An undecorated export is already exported under its own name, so
            // naming it here would be one more thing to keep correct.
            Assert.DoesNotContain("Plain", definition);
        });

    /// <summary>
    /// And on x64 nothing is decorated, so there is nothing to rename and no
    /// file to write. A .def would replace the linker's own export list.
    /// </summary>
    [Fact]
    public void NoModuleDefinitionWhereNothingIsDecorated() =>
        Under(TargetPlatform.X64Windows, () =>
        {
            var program = Front.Bind(ComServer, out var diagnostics);
            Assert.Empty(Front.Codes(diagnostics));
            Assert.Null(ModuleDefinition.For(program));
        });

    /// <summary>
    /// A file passed with <c>--def</c> is kept, and the compiler's own renames
    /// are added after it rather than instead of it.
    ///
    /// Replacing them would make <c>--def</c> a trap: passing one to add an
    /// alias would silently drop the renaming that makes a decorated export
    /// reachable under its declared name at all.
    /// </summary>
    [Fact]
    public void ASuppliedDefinitionIsKeptAndAddedTo() =>
        Under(TargetPlatform.X86Windows, () =>
        {
            string work = Directory.CreateTempSubdirectory("stainless-def").FullName;
            try
            {
                string supplied = Path.Combine(work, "extra.def");
                File.WriteAllText(supplied, "EXPORTS\n    Alias = _DllCanUnloadNow@0\n");

                var program = Front.Bind(ComServer, out _);
                string? path = ModuleDefinition.Resolve(
                    program, supplied, shared: true, work, Path.Combine(work, "server.dll"));

                Assert.NotNull(path);
                Assert.NotEqual(supplied, path);

                string merged = File.ReadAllText(path!);
                Assert.Contains("Alias = _DllCanUnloadNow@0", merged);
                Assert.Contains("DllGetClassObject = _DllGetClassObject@12", merged);
            }
            finally { Directory.Delete(work, recursive: true); }
        });

    /// <summary>
    /// With nothing of its own to add, the compiler hands the linker the file
    /// it was given rather than a copy of it.
    /// </summary>
    [Fact]
    public void ASuppliedDefinitionPassesStraightThroughOnX64() =>
        Under(TargetPlatform.X64Windows, () =>
        {
            string work = Directory.CreateTempSubdirectory("stainless-def").FullName;
            try
            {
                string supplied = Path.Combine(work, "extra.def");
                File.WriteAllText(supplied, "EXPORTS\n    Alias = DllCanUnloadNow\n");

                var program = Front.Bind(ComServer, out _);
                string? path = ModuleDefinition.Resolve(
                    program, supplied, shared: true, work, Path.Combine(work, "server.dll"));

                Assert.Equal(Path.GetFullPath(supplied), path);
            }
            finally { Directory.Delete(work, recursive: true); }
        });

    /// <summary>
    /// An executable marks nothing exported, so there is no export table to
    /// correct and naming its functions would invent one.
    /// </summary>
    [Fact]
    public void NothingIsGeneratedForAnExecutable() =>
        Under(TargetPlatform.X86Windows, () =>
        {
            var program = Front.Bind(ComServer, out _);
            Assert.Null(ModuleDefinition.Resolve(
                program, supplied: null, shared: false, ".", "program.exe"));
        });

    /// <summary>A .def is a PE concept; ELF exports by visibility.</summary>
    [Fact]
    public void NoModuleDefinitionOffWindows() =>
        Under(TargetPlatform.X86Linux, () =>
        {
            var program = Front.Bind(ComServer, out var diagnostics);
            Assert.Empty(Front.Codes(diagnostics));
            Assert.Null(ModuleDefinition.For(program));
        });

    // ------------------------------------------------------------ exporting

    private const string Exported = """export "C" int Answer() => 42;""";

    /// <summary>The target decides, not the machine compiling.</summary>
    [Fact]
    public void AWindowsLibraryMarksItsExports() =>
        Under(TargetPlatform.X64Windows, () =>
            Assert.Contains("define dllexport i32 @Answer", Front.ModuleIr(Exported)));

    [Fact]
    public void ALinuxLibraryExportsByVisibility() =>
        Under(TargetPlatform.X64Linux, () =>
        {
            string ir = Front.ModuleIr(Exported, CppAbi.Itanium);
            Assert.Contains("define i32 @Answer", ir);
            Assert.DoesNotContain("dllexport", ir);
        });

    /// <summary>Bit-fields are laid out by the target's C ABI.</summary>
    [Fact]
    public void ALinuxTargetPacksBitFieldsAcrossTypes() =>
        Under(TargetPlatform.X64Linux, () =>
        {
            var program = Front.Bind("""
                module Test;
                public struct Mixed { public int A : 3; public byte B : 2; }
                """, out _, shared: true);
            Assert.Equal(4, program.Structs.Single(s => s.Name == "Mixed").Size);
        });
}
