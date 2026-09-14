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
