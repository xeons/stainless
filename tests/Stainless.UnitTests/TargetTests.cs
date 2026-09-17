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
        var target = TargetPlatform.Parse(name);

        Assert.NotNull(target);
        Assert.Equal(pointerWidth, target!.PointerWidth);
    }

    [Fact]
    public void AnUnknownTargetIsNotGuessedAt()
    {
        Assert.Null(TargetPlatform.Parse("sparc"));
        Assert.Null(TargetPlatform.Parse(""));
    }

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
}
