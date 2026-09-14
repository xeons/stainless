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
using Stainless.Syntax;
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// The decorated names a calling convention produces.
///
/// <para>
/// The byte count in a <c>__stdcall</c> name is not decoration for its own
/// sake: the callee removes the arguments, so a caller and a callee that
/// disagree about how many there are leave the stack unbalanced. Encoding the
/// count means the linker refuses first -- which only works if the count is
/// right, and a count that is wrong by four produces a name nothing defines.
/// </para>
///
/// <para>
/// tests/cases/x86-conventions calls real C functions compiled with the real
/// keywords, which is the test that proves the whole path. These pin the
/// arithmetic, including the shapes that case does not reach.
/// </para>
/// </summary>
public class ConventionTests
{
    private static void Under(TargetPlatform target, Action body)
    {
        var before = TargetPlatform.Current;
        TargetPlatform.Current = target;
        try { body(); }
        finally { TargetPlatform.Current = before; }
    }

    /// <summary>An <c>extern "C"</c> declaration with the given parameters.</summary>
    private static FunctionSymbol Declared(
        string name, CallingConvention convention, params TypeSymbol[] parameters)
    {
        var function = new FunctionSymbol
        {
            Name = name,
            ModuleName = "Probe",
            ReturnType = PrimitiveTypeSymbol.Int,
            Linkage = LinkageKind.ExternC,
            CallingConvention = convention,
            Span = default,
        };

        for (int i = 0; i < parameters.Length; i++)
            function.Parameters.Add(new ParameterSymbol($"p{i}", parameters[i], i));

        return function;
    }

    private static readonly TypeSymbol Int = PrimitiveTypeSymbol.Int;
    private static readonly TypeSymbol Long = PrimitiveTypeSymbol.Long;
    private static readonly TypeSymbol Byte = PrimitiveTypeSymbol.Byte;
    private static readonly TypeSymbol Double = PrimitiveTypeSymbol.Double;

    // ------------------------------------------------------------------ x86

    [Fact]
    public void StdcallCountsItsArgumentBytes()
    {
        Under(TargetPlatform.X86Windows, () =>
        {
            Assert.Equal("_f@8", Mangler.Decorated(
                Declared("f", CallingConvention.Stdcall, Int, Int)));

            Assert.Equal("_f@20", Mangler.Decorated(
                Declared("f", CallingConvention.Stdcall, Int, Int, Int, Int, Int)));

            Assert.Equal("_f@0", Mangler.Decorated(
                Declared("f", CallingConvention.Stdcall)));
        });
    }

    /// <summary>
    /// A <c>long</c> is two stack slots on x86, and anything narrower than a
    /// slot still occupies a whole one.
    /// </summary>
    [Fact]
    public void EachArgumentTakesAWholeSlot()
    {
        Under(TargetPlatform.X86Windows, () =>
        {
            Assert.Equal("_f@12", Mangler.Decorated(
                Declared("f", CallingConvention.Stdcall, Long, Int)));

            Assert.Equal("_f@8", Mangler.Decorated(
                Declared("f", CallingConvention.Stdcall, Byte, Byte)));

            Assert.Equal("_f@16", Mangler.Decorated(
                Declared("f", CallingConvention.Stdcall, Double, Double)));
        });
    }

    [Fact]
    public void EachConventionHasItsOwnDecoration()
    {
        Under(TargetPlatform.X86Windows, () =>
        {
            Assert.Equal("_f@8",
                Mangler.Decorated(Declared("f", CallingConvention.Stdcall, Int, Int)));
            Assert.Equal("@f@8",
                Mangler.Decorated(Declared("f", CallingConvention.Fastcall, Int, Int)));
            Assert.Equal("f@@8",
                Mangler.Decorated(Declared("f", CallingConvention.Vectorcall, Int, Int)));
        });
    }

    /// <summary>
    /// <c>__cdecl</c> adds nothing here. Its leading underscore is the target's
    /// own symbol prefix, which LLVM applies to every global -- writing it here
    /// as well would ask the linker for <c>__f</c>.
    /// </summary>
    [Fact]
    public void CdeclIsNotDecorated()
    {
        Under(TargetPlatform.X86Windows, () =>
        {
            Assert.Equal("f", Mangler.Decorated(
                Declared("f", CallingConvention.Cdecl, Int, Int)));

            Assert.Equal("f", Mangler.Decorated(
                Declared("f", CallingConvention.Default, Int, Int)));

            Assert.False(Mangler.IsDecorated(Declared("f", CallingConvention.Cdecl, Int)));
        });
    }

    // ------------------------------------------------------------------ x64

    /// <summary>
    /// There is one convention on x64, so naming another says nothing about the
    /// symbol. clang agrees: it writes a plain <c>@f</c> for a
    /// <c>__stdcall</c> declaration on a 64-bit target.
    /// </summary>
    [Fact]
    public void SixtyFourBitIgnoresAllButVectorcall()
    {
        Under(TargetPlatform.X64Windows, () =>
        {
            Assert.Equal("f", Mangler.Decorated(
                Declared("f", CallingConvention.Stdcall, Int, Int)));

            Assert.Equal("f", Mangler.Decorated(
                Declared("f", CallingConvention.Fastcall, Int, Int)));
        });
    }

    /// <summary>
    /// <c>__vectorcall</c> is the one that survives, and its count is in
    /// eight-byte slots there rather than four.
    /// </summary>
    [Fact]
    public void VectorcallStillDecoratesOn64Bit()
    {
        Under(TargetPlatform.X64Windows, () =>
        {
            Assert.Equal("f@@16", Mangler.Decorated(
                Declared("f", CallingConvention.Vectorcall, Int, Int)));
        });
    }

    // ---------------------------------------------------------------- ELF

    /// <summary>
    /// Decoration is Microsoft's and stops where PE does.
    ///
    /// <para>
    /// An i386 ELF <c>__stdcall</c> gets the convention -- the callee still
    /// removes the arguments -- and the plain name, which is what gcc has
    /// always done and what clang writes for <c>i686-unknown-linux-gnu</c>.
    /// This is the one part of a convention that is the object format's
    /// question rather than the architecture's, and getting it wrong is a link
    /// error rather than a wrong answer: the first 32-bit Linux build went
    /// looking for <c>_add_stdcall@8</c> and there was no such symbol.
    /// </para>
    /// </summary>
    [Fact]
    public void ElfDecoratesNothing()
    {
        Under(TargetPlatform.X86Linux, () =>
        {
            Assert.Equal("f", Mangler.Decorated(
                Declared("f", CallingConvention.Stdcall, Int, Int)));

            Assert.Equal("f", Mangler.Decorated(
                Declared("f", CallingConvention.Fastcall, Int, Int)));

            Assert.Equal("f", Mangler.Decorated(
                Declared("f", CallingConvention.Vectorcall, Int, Int)));

            Assert.False(Mangler.IsDecorated(
                Declared("f", CallingConvention.Stdcall, Int, Int)));
        });

        Under(TargetPlatform.X64Linux, () =>
            Assert.Equal("f", Mangler.Decorated(
                Declared("f", CallingConvention.Vectorcall, Int, Int))));
    }

    /// <summary>
    /// ARM64 has one convention, so naming another changes neither the symbol
    /// nor the call.
    /// </summary>
    [Fact]
    public void Arm64HasNothingToTellApart()
    {
        Under(TargetPlatform.Arm64Windows, () =>
        {
            Assert.Equal("f", Mangler.Decorated(
                Declared("f", CallingConvention.Stdcall, Int, Int)));

            Assert.Equal("f", Mangler.Decorated(
                Declared("f", CallingConvention.Vectorcall, Int, Int)));
        });
    }

    // -------------------------------------------------------------- parsing

    [Fact]
    public void AConventionReachesTheDeclaration()
    {
        var unit = Front.Parse("""
            module M;
            extern "C" __stdcall int MessageBoxW(nint owner);
            """);

        var function = Assert.IsType<FunctionDeclSyntax>(unit.Declarations[0]);
        Assert.Equal(CallingConvention.Stdcall, function.CallingConvention);
    }

    /// <summary>
    /// Written on the block, it belongs to every declaration in it -- which is
    /// the only reason to write one there rather than on two hundred lines.
    /// </summary>
    [Fact]
    public void ABlockGivesItsConventionToEveryMember()
    {
        var unit = Front.Parse("""
            module M;
            extern "C" __stdcall {
                int GetMessageW(nint message);
                int TranslateMessage(nint message);
            }
            """);

        Assert.All(
            unit.Declarations.OfType<FunctionDeclSyntax>(),
            f => Assert.Equal(CallingConvention.Stdcall, f.CallingConvention));
    }

    /// <summary>A member may still name its own, which wins over the block's.</summary>
    [Fact]
    public void AMemberOverridesTheBlock()
    {
        var unit = Front.Parse("""
            module M;
            extern "C" __stdcall {
                int Standard(nint a);
                __cdecl int Different(nint a);
            }
            """);

        var functions = unit.Declarations.OfType<FunctionDeclSyntax>().ToList();

        Assert.Equal(CallingConvention.Stdcall, functions[0].CallingConvention);
        Assert.Equal(CallingConvention.Cdecl, functions[1].CallingConvention);
    }

    /// <summary>Nothing written means the platform's own.</summary>
    [Fact]
    public void NoConventionIsTheDefault()
    {
        var unit = Front.Parse("""
            module M;
            extern "C" int puts(byte* text);
            """);

        var function = Assert.IsType<FunctionDeclSyntax>(unit.Declarations[0]);
        Assert.Equal(CallingConvention.Default, function.CallingConvention);
    }

    /// <summary>
    /// A name that merely begins with underscores is still a name. Only the four
    /// are matched, so a program may declare <c>__stdcall_helper</c>.
    /// </summary>
    [Fact]
    public void OnlyTheFourNamesAreConventions()
    {
        var unit = Front.Parse("""
            module M;
            extern "C" int __builtin_popcount(uint value);
            """);

        var function = Assert.IsType<FunctionDeclSyntax>(unit.Declarations[0]);

        Assert.Equal(CallingConvention.Default, function.CallingConvention);
        Assert.Equal("__builtin_popcount", function.Name);
    }
}
