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
using Stainless.Emit;
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// The two struct-passing conventions, asked one shape at a time.
///
/// The end-to-end <c>sysv-abi</c> case pins the System V answers against
/// clang, which is the authority and stays the authority. What is here is what
/// that case cannot be: the Win64 side, which nothing else states in a table;
/// the properties both conventions must have whatever they decide; and a
/// place to add a shape without adding a program that has to link and run.
/// </summary>
public class AbiTests
{
    /// <summary>The shapes, declared once and laid out by the compiler.</summary>
    private const string Shapes = """
        public struct B1 { public sbyte A; }
        public struct B2 { public short A; }
        public struct B3 { public sbyte A; public sbyte B; public sbyte C; }
        public struct B4 { public int A; }
        public struct B5 { public int A; public sbyte B; }
        public struct B8 { public long A; }
        public struct B9 { public long A; public sbyte B; }
        public struct B16 { public long A; public long B; }
        public struct B17 { public long A; public long B; public sbyte C; }
        public struct F2 { public float A; public float B; }
        public struct F3 { public float A; public float B; public float C; }
        public struct D2 { public double A; public double B; }
        public struct D3 { public double A; public double B; public double C; }
        public struct MixDI { public double A; public int B; }
        public struct MixID { public int A; public double B; }
        public struct MixFI { public float A; public int B; }
        public struct MixBD { public sbyte A; public double B; }
        public struct MixFL { public float A; public long B; }
        public struct Empty { }
        public struct Ptr { public sbyte* A; }
        public struct TwoPtr { public sbyte* A; public sbyte* B; }
        public struct Inline3 { public int[3] A; }
        public struct Inline17 { public sbyte[17] A; }
        public struct Nested { public B4 A; public B4 B; }
        public struct D4 { public double A; public double B; public double C; public double D; }
        public struct FD { public float A; public double B; }
        public struct InlineF3 { public float[3] A; }
        [Align(16)] public struct Wide16 { public long A; public long B; }
        """;

    private static ArgInfo Win64Arg(string name) =>
        Win64Abi.ClassifyArgument(Front.Struct(Shapes, name), LlvmEmitter.LlvmTypeOf);

    private static ArgInfo Win64Return(string name) =>
        Win64Abi.ClassifyReturn(Front.Struct(Shapes, name), LlvmEmitter.LlvmTypeOf);

    private static ArgInfo SysVArg(string name) =>
        SysVAbi.ClassifyArgument(Front.Struct(Shapes, name), LlvmEmitter.LlvmTypeOf);

    private static ArgInfo SysVReturn(string name) =>
        SysVAbi.ClassifyReturn(Front.Struct(Shapes, name), LlvmEmitter.LlvmTypeOf);

    private static ArgInfo Arm64Arg(string name) =>
        Aapcs64Abi.ClassifyArgument(Front.Struct(Shapes, name), LlvmEmitter.LlvmTypeOf);

    private static ArgInfo Arm64Return(string name) =>
        Aapcs64Abi.ClassifyReturn(Front.Struct(Shapes, name), LlvmEmitter.LlvmTypeOf);

    private static PrimitiveTypeSymbol Primitive(string name) =>
        PrimitiveTypeSymbol.All.First(p => p.Name == name);

    /// <summary>
    /// What each shape actually measures.
    ///
    /// Padding is why a name cannot be trusted: <c>{ int; sbyte; }</c> is
    /// eight bytes and travels in a register under both conventions, and
    /// <c>{ long; sbyte; }</c> is sixteen and travels in one under neither the
    /// same way. Every expectation below rests on these numbers, so they are
    /// stated rather than assumed.
    /// </summary>
    [Theory]
    [InlineData("B1", 1)]
    [InlineData("B2", 2)]
    [InlineData("B3", 3)]
    [InlineData("B4", 4)]
    [InlineData("B5", 8)]
    [InlineData("B8", 8)]
    [InlineData("B9", 16)]
    [InlineData("B16", 16)]
    [InlineData("B17", 24)]
    [InlineData("F2", 8)]
    [InlineData("F3", 12)]
    [InlineData("D2", 16)]
    [InlineData("D3", 24)]
    [InlineData("MixDI", 16)]
    [InlineData("MixFI", 8)]
    [InlineData("Empty", 1)]
    [InlineData("Inline3", 12)]
    [InlineData("Inline17", 17)]
    [InlineData("Nested", 8)]
    public void ShapesMeasureWhatTheyLookLike(string shape, int size) =>
        Assert.Equal(size, Front.Struct(Shapes, shape).Size);

    // --------------------------------------------------------------- Win64

    /// <summary>
    /// Win64 asks only how big it is: exactly 1, 2, 4 or 8 bytes travels in one
    /// integer register of that width.
    /// </summary>
    [Theory]
    [InlineData("B1", "i8")]
    [InlineData("B2", "i16")]
    [InlineData("B4", "i32")]
    [InlineData("B8", "i64")]
    [InlineData("Ptr", "i64")]
    [InlineData("B5", "i64")]
    public void Win64PutsARegisterSizedStructInOneInteger(string shape, string spelling)
    {
        var info = Win64Arg(shape);
        Assert.Equal(PassStyle.Coerce, info.Style);
        Assert.Equal(spelling, info.LlvmType);
        Assert.Equal([spelling], info.Pieces);
    }

    /// <summary>
    /// And every other size goes to memory -- including sizes System V would
    /// happily put in registers, which is the whole reason the flag exists.
    /// </summary>
    [Theory]
    [InlineData("B3")]
    [InlineData("B9")]
    [InlineData("B16")]
    [InlineData("B17")]
    [InlineData("D2")]
    [InlineData("MixDI")]
    [InlineData("TwoPtr")]
    [InlineData("Inline3")]
    public void Win64PassesAnythingElseIndirectly(string shape)
    {
        var info = Win64Arg(shape);
        Assert.Equal(PassStyle.Indirect, info.Style);
        Assert.Equal("ptr", info.LlvmType);
        Assert.Empty(info.Pieces);
    }

    /// <summary>
    /// Win64 has no floating-point struct rule at all: two doubles is sixteen
    /// bytes and goes to memory, where System V puts it in two xmm registers.
    /// </summary>
    [Fact]
    public void Win64IgnoresWhatIsInTheStruct()
    {
        Assert.Equal(PassStyle.Indirect, Win64Arg("D2").Style);
        Assert.Equal(PassStyle.Coerce, SysVArg("D2").Style);
    }

    /// <summary>Win64 returns exactly as it passes, with no gathering step.</summary>
    [Theory]
    [InlineData("B4")]
    [InlineData("B8")]
    [InlineData("B16")]
    [InlineData("MixDI")]
    public void Win64ReturnsAsItPasses(string shape) =>
        Assert.Equal(Win64Arg(shape).LlvmType, Win64Return(shape).LlvmType);

    // -------------------------------------------------------------- System V

    /// <summary>
    /// System V cuts a value of sixteen bytes or less into eightbytes and asks
    /// what lies in each. These are the answers clang gives for the same
    /// shapes, which is what the end-to-end case checked them against.
    /// </summary>
    [Theory]
    [InlineData("B3", new[] { "i24" })]
    [InlineData("B5", new[] { "i64" })]
    [InlineData("B9", new[] { "i64", "i8" })]
    [InlineData("B16", new[] { "i64", "i64" })]
    [InlineData("F2", new[] { "<2 x float>" })]
    [InlineData("F3", new[] { "<2 x float>", "float" })]
    [InlineData("D2", new[] { "double", "double" })]
    [InlineData("MixDI", new[] { "double", "i32" })]
    [InlineData("MixID", new[] { "i32", "double" })]
    [InlineData("MixFI", new[] { "i64" })]
    [InlineData("MixBD", new[] { "i8", "double" })]
    [InlineData("MixFL", new[] { "float", "i64" })]
    [InlineData("Inline3", new[] { "i64", "i32" })]
    [InlineData("Nested", new[] { "i64" })]
    [InlineData("TwoPtr", new[] { "ptr", "ptr" })]
    public void SysVCutsAStructIntoRegisters(string shape, string[] pieces)
    {
        var info = SysVArg(shape);
        Assert.Equal(PassStyle.Coerce, info.Style);
        Assert.Equal(pieces, info.Pieces);
    }

    [Theory]
    [InlineData("B17")]
    [InlineData("D3")]
    [InlineData("Inline17")]
    public void SysVSendsAnythingOverSixteenBytesToMemory(string shape)
    {
        var info = SysVArg(shape);
        Assert.Equal(PassStyle.Indirect, info.Style);
        Assert.Equal("ptr", info.LlvmType);
    }

    /// <summary>
    /// A register is sized by what is in it rather than by the eightbyte it
    /// sits in. <c>{ long; sbyte; }</c> is sixteen bytes and its second
    /// register is an i8: reading eight bytes there would read past the object.
    /// </summary>
    [Theory]
    [InlineData("B9", "i8")]
    [InlineData("B3", "i24")]
    [InlineData("MixDI", "i32")]
    public void ARegisterIsSizedByWhatItHolds(string shape, string last) =>
        Assert.Equal(last, SysVArg(shape).Pieces[^1]);

    /// <summary>
    /// Merging is what makes a mixed eightbyte an integer, and it is why size
    /// predicts nothing: <c>{ float; int; }</c> is one integer register where
    /// <c>{ float; float; }</c> of the same size is one SSE register.
    /// </summary>
    [Fact]
    public void IntegerWinsAMergedEightByte()
    {
        Assert.Equal(["i64"], SysVArg("MixFI").Pieces);
        Assert.Equal(["<2 x float>"], SysVArg("F2").Pieces);
        Assert.Equal(8, Front.Struct(Shapes, "MixFI").Size);
        Assert.Equal(8, Front.Struct(Shapes, "F2").Size);
    }

    /// <summary>
    /// A parameter in two registers is two parameters; a return in two is one
    /// LLVM struct. A function has one return and may have many parameters, so
    /// the same classification is spelled two ways.
    /// </summary>
    [Theory]
    [InlineData("B9", "{ i64, i8 }")]
    [InlineData("D2", "{ double, double }")]
    [InlineData("MixDI", "{ double, i32 }")]
    [InlineData("F3", "{ <2 x float>, float }")]
    public void SysVGathersATwoRegisterReturnIntoAStruct(string shape, string spelling)
    {
        Assert.Equal(spelling, SysVReturn(shape).LlvmType);
        Assert.Equal(SysVArg(shape).Pieces, SysVReturn(shape).Pieces);
    }

    [Theory]
    [InlineData("B3")]
    [InlineData("B5")]
    [InlineData("F2")]
    [InlineData("MixFI")]
    public void AOneRegisterReturnIsNotGathered(string shape) =>
        Assert.Equal(SysVArg(shape).LlvmType, SysVReturn(shape).LlvmType);

    // --------------------------------------------------------------- AAPCS64

    /// <summary>
    /// AAPCS64 asks first whether every member is the same floating-point type.
    /// Four or fewer of them and no padding is a homogeneous aggregate, which
    /// travels in one SIMD register each -- <c>{ double x4 }</c> crosses in
    /// registers at thirty-two bytes, where <c>{ long; long; sbyte; }</c> at
    /// twenty-four does not.
    /// </summary>
    [Theory]
    [InlineData("F2", "[2 x float]")]
    [InlineData("F3", "[3 x float]")]
    [InlineData("InlineF3", "[3 x float]")]
    [InlineData("D2", "[2 x double]")]
    [InlineData("D3", "[3 x double]")]
    [InlineData("D4", "[4 x double]")]
    public void Arm64PutsAHomogeneousAggregateInSimdRegisters(string shape, string spelling)
    {
        var info = Arm64Arg(shape);
        Assert.Equal(PassStyle.Coerce, info.Style);
        Assert.Equal([spelling], info.Pieces);
        Assert.Equal(0, info.PaddedSize);
    }

    /// <summary>
    /// And these are the near misses: two floating-point types is not one,
    /// five members is more than four, and a float beside an int is neither.
    /// </summary>
    [Theory]
    [InlineData("FD", "[2 x i64]")]
    [InlineData("MixFI", "i64")]
    [InlineData("MixFL", "[2 x i64]")]
    [InlineData("MixDI", "[2 x i64]")]
    [InlineData("MixBD", "[2 x i64]")]
    public void Arm64IsNotFooledByAFloatInTheStruct(string shape, string spelling) =>
        Assert.Equal([spelling], Arm64Arg(shape).Pieces);

    /// <summary>
    /// Everything else of sixteen bytes or less travels in one or two general
    /// registers, and an argument register is sized by the register rather than
    /// by the value: a three-byte struct is an <c>i64</c> here where System V
    /// makes it an <c>i24</c>.
    /// </summary>
    [Theory]
    [InlineData("B1", "i64")]
    [InlineData("B3", "i64")]
    [InlineData("B4", "i64")]
    [InlineData("B5", "i64")]
    [InlineData("B8", "i64")]
    [InlineData("Nested", "i64")]
    [InlineData("B9", "[2 x i64]")]
    [InlineData("B16", "[2 x i64]")]
    [InlineData("Inline3", "[2 x i64]")]
    public void Arm64PutsEverythingElseSmallInGeneralRegisters(string shape, string spelling)
    {
        var info = Arm64Arg(shape);
        Assert.Equal(PassStyle.Coerce, info.Style);
        Assert.Equal([spelling], info.Pieces);
    }

    /// <summary>
    /// A struct holding nothing but pointers keeps them as pointers, which is
    /// the same register and the spelling LLVM can reason about. One holding a
    /// pointer and anything else does not.
    /// </summary>
    [Fact]
    public void Arm64KeepsAStructOfPointersAsPointers()
    {
        Assert.Equal(["ptr"], Arm64Arg("Ptr").Pieces);
        Assert.Equal(["[2 x ptr]"], Arm64Arg("TwoPtr").Pieces);

        // And a result does not: clang spells every returned register as an
        // integer, pointers included.
        Assert.Equal("i64", Arm64Return("Ptr").LlvmType);
        Assert.Equal("[2 x i64]", Arm64Return("TwoPtr").LlvmType);
    }

    /// <summary>
    /// A value asking to be aligned to sixteen gets one sixteen-byte register
    /// rather than two of eight, because a pair has to start at an even one and
    /// a single <c>i128</c> is how that is said.
    /// </summary>
    [Fact]
    public void Arm64GivesASixteenAlignedValueOneRegister()
    {
        Assert.Equal(["i128"], Arm64Arg("Wide16").Pieces);
        Assert.Equal("i128", Arm64Return("Wide16").LlvmType);
    }

    /// <summary>
    /// Over sixteen bytes and not homogeneous is a pointer to a copy the caller
    /// made -- and it must not be spelled <c>byval</c>, which LLVM lowers to the
    /// value on the outgoing stack instead.
    /// </summary>
    [Theory]
    [InlineData("B17")]
    [InlineData("Inline17")]
    public void Arm64PassesALargeStructAsAPointerAndNotByval(string shape)
    {
        var info = Arm64Arg(shape);
        Assert.Equal(PassStyle.Indirect, info.Style);
        Assert.True(info.IndirectAsPointer);

        // A result is `sret` the way it is everywhere, so it says nothing.
        Assert.Equal(PassStyle.Indirect, Arm64Return(shape).Style);
        Assert.False(Arm64Return(shape).IndirectAsPointer);
    }

    /// <summary>
    /// A result of eight bytes or less is sized by the value rather than by the
    /// register, which is the one place AAPCS64's two directions disagree.
    /// </summary>
    [Theory]
    [InlineData("B1", "i8")]
    [InlineData("B2", "i16")]
    [InlineData("B3", "i24")]
    [InlineData("B4", "i32")]
    [InlineData("B5", "i64")]
    [InlineData("B8", "i64")]
    public void Arm64SizesAResultByTheValue(string shape, string spelling)
    {
        Assert.Equal(spelling, Arm64Return(shape).LlvmType);
        Assert.Equal("i64", Arm64Arg(shape).LlvmType);
    }

    /// <summary>
    /// A homogeneous aggregate comes back as itself: the registers are the
    /// same ones it went out in, and that is how clang spells them.
    /// </summary>
    [Theory]
    [InlineData("F2")]
    [InlineData("D3")]
    public void Arm64ReturnsAHomogeneousAggregateAsItself(string shape)
    {
        var type = Front.Struct(Shapes, shape);
        Assert.Equal(LlvmEmitter.LlvmTypeOf(type), Arm64Return(shape).LlvmType);
    }

    /// <summary>
    /// Where the registers reach past the value, how far is recorded -- because
    /// the emitter has to read them out of a padded copy rather than out of the
    /// object, which would read bytes the object does not have.
    /// </summary>
    [Theory]
    [InlineData("B1", 8)]
    [InlineData("B3", 8)]
    [InlineData("Inline3", 16)]
    [InlineData("B8", 0)]
    [InlineData("B16", 0)]
    [InlineData("F3", 0)]
    [InlineData("Wide16", 0)]
    public void Arm64SaysWhenARegisterReachesPastTheValue(string shape, int padded) =>
        Assert.Equal(padded, Arm64Arg(shape).PaddedSize);

    // ------------------------------------------------- what both must agree on

    /// <summary>
    /// Neither convention touches anything that is not a struct: an int is an
    /// int in a register whichever ABI is in force.
    /// </summary>
    [Fact]
    public void NeitherConventionTouchesAScalar()
    {
        var program = Front.BindModule("public int F(int a) { return a; }", out _);
        var parameter = program.Functions
            .First(f => f.Symbol.Name == "F").Symbol.Parameters[0].Type;

        foreach (var info in new[]
        {
            Win64Abi.ClassifyArgument(parameter, LlvmEmitter.LlvmTypeOf),
            SysVAbi.ClassifyArgument(parameter, LlvmEmitter.LlvmTypeOf),
        })
        {
            Assert.Equal(PassStyle.Direct, info.Style);
            Assert.Equal("i32", info.LlvmType);
            Assert.Empty(info.Pieces);
        }
    }

    /// <summary>
    /// An empty struct is one byte, following C++ rather than the GNU
    /// zero-size extension, and each convention treats it as clang++ does.
    /// Win64 passes the byte. System V, and Darwin on ARM64, leave it out. The
    /// other ARM64 systems pass it in a register and, like Darwin, return it
    /// as nothing. 32-bit x86 leaves it out of a Linux parameter list and out
    /// of a Windows result.
    /// </summary>
    [Fact]
    public void EachConventionTreatsAnEmptyStructAsClangDoes()
    {
        var empty = Front.Struct(Shapes, "Empty");
        Assert.Equal(1, empty.Size);

        Assert.Equal(PassStyle.Coerce, Win64Arg("Empty").Style);
        Assert.Equal(PassStyle.Coerce, Win64Return("Empty").Style);

        Assert.Equal(PassStyle.Ignore, SysVArg("Empty").Style);
        Assert.Equal(PassStyle.Ignore, SysVReturn("Empty").Style);

        Assert.Equal(PassStyle.Coerce, Arm64Arg("Empty").Style);
        Assert.Equal(PassStyle.Ignore, Arm64Return("Empty").Style);
        Assert.Equal(PassStyle.Ignore,
            Aapcs64Abi.ClassifyArgument(empty, LlvmEmitter.LlvmTypeOf, darwin: true).Style);
        Assert.Equal(PassStyle.Ignore,
            Aapcs64Abi.ClassifyReturn(empty, LlvmEmitter.LlvmTypeOf, darwin: true).Style);

        Assert.Equal(PassStyle.Ignore,
            X86Abi.ClassifyArgument(empty, LlvmEmitter.LlvmTypeOf, windows: false).Style);
        Assert.Equal(PassStyle.Indirect,
            X86Abi.ClassifyArgument(empty, LlvmEmitter.LlvmTypeOf, windows: true).Style);
        Assert.Equal(PassStyle.Indirect,
            X86Abi.ClassifyReturn(empty, LlvmEmitter.LlvmTypeOf, windows: false).Style);
        Assert.Equal(PassStyle.Ignore,
            X86Abi.ClassifyReturn(empty, LlvmEmitter.LlvmTypeOf, windows: true).Style);
    }

    // ------------------------------------------------------ narrow integers

    /// <summary>
    /// How C widens each narrow type, which is what every convention that
    /// widens at all writes. <c>char</c> is C's, and so signed.
    /// </summary>
    [Theory]
    [InlineData("sbyte", ArgExtension.Sign)]
    [InlineData("short", ArgExtension.Sign)]
    [InlineData("char", ArgExtension.Sign)]
    [InlineData("byte", ArgExtension.Zero)]
    [InlineData("ushort", ArgExtension.Zero)]
    [InlineData("bool", ArgExtension.Zero)]
    [InlineData("char16", ArgExtension.Zero)]
    [InlineData("int", ArgExtension.None)]
    [InlineData("uint", ArgExtension.None)]
    [InlineData("char32", ArgExtension.None)]
    [InlineData("long", ArgExtension.None)]
    [InlineData("float", ArgExtension.None)]
    public void ANarrowIntegerIsWidenedAsCWidensIt(string name, ArgExtension expected) =>
        Assert.Equal(expected, ArgInfo.ExtensionOf(Primitive(name)));

    /// <summary>An enum is widened as its underlying type is.</summary>
    [Fact]
    public void AnEnumIsWidenedByItsUnderlyingType()
    {
        var program = Front.BindModule("""
            public enum Small : sbyte { A = -1 }
            public enum Wide : ushort { B = 1 }
            public enum Plain { C }
            public void F(Small s, Wide w, Plain p) { }
            """, out _);

        var parameters = program.Functions.First(f => f.Symbol.Name == "F").Symbol.Parameters;

        Assert.Equal(ArgExtension.Sign, ArgInfo.ExtensionOf(parameters[0].Type));
        Assert.Equal(ArgExtension.Zero, ArgInfo.ExtensionOf(parameters[1].Type));
        Assert.Equal(ArgExtension.None, ArgInfo.ExtensionOf(parameters[2].Type));
    }

    /// <summary>
    /// Which conventions widen, read off clang for each target: every narrow
    /// type on Darwin ARM64, x86-64 System V and 32-bit x86; only <c>bool</c>
    /// on Win64; nothing on ARM64 Linux or Windows. A result follows the same
    /// rule as a parameter.
    /// </summary>
    [Fact]
    public void OnlySomeConventionsWiden()
    {
        var narrow = PrimitiveTypeSymbol.Short;
        var flag = PrimitiveTypeSymbol.Bool;
        Func<TypeSymbol, string> spell = LlvmEmitter.LlvmTypeOf;

        Assert.Equal(ArgExtension.Sign, Aapcs64Abi.ClassifyArgument(narrow, spell, darwin: true).Extension);
        Assert.Equal(ArgExtension.Sign, Aapcs64Abi.ClassifyReturn(narrow, spell, darwin: true).Extension);
        Assert.Equal(ArgExtension.None, Aapcs64Abi.ClassifyArgument(narrow, spell).Extension);
        Assert.Equal(ArgExtension.None, Aapcs64Abi.ClassifyReturn(flag, spell).Extension);

        Assert.Equal(ArgExtension.Sign, SysVAbi.ClassifyArgument(narrow, spell).Extension);
        Assert.Equal(ArgExtension.Sign, SysVAbi.ClassifyReturn(narrow, spell).Extension);
        Assert.Equal(ArgExtension.Sign, X86Abi.ClassifyArgument(narrow, spell, windows: true).Extension);
        Assert.Equal(ArgExtension.Sign, X86Abi.ClassifyReturn(narrow, spell, windows: false).Extension);

        Assert.Equal(ArgExtension.None, Win64Abi.ClassifyArgument(narrow, spell).Extension);
        Assert.Equal(ArgExtension.Zero, Win64Abi.ClassifyArgument(flag, spell).Extension);
        Assert.Equal(ArgExtension.Zero, Win64Abi.ClassifyReturn(flag, spell).Extension);
    }

    /// <summary>
    /// A variadic function on Windows ARM64 takes a homogeneous aggregate as
    /// any other struct of its size, named arguments included: clang passes
    /// <c>{ float x3 }</c> as <c>[2 x i64]</c> and four doubles behind a
    /// pointer. Darwin and Linux keep the SIMD registers.
    /// </summary>
    [Fact]
    public void WindowsArm64DoesNotExpandAnAggregateForAVariadicFunction()
    {
        var three = Front.Struct(Shapes, "F3");
        var four = Front.Struct(Shapes, "D4");
        Func<TypeSymbol, string> spell = LlvmEmitter.LlvmTypeOf;

        var packed = Aapcs64Abi.ClassifyArgument(three, spell, windowsVariadic: true);
        Assert.Equal(PassStyle.Coerce, packed.Style);
        Assert.Equal("[2 x i64]", packed.LlvmType);

        var large = Aapcs64Abi.ClassifyArgument(four, spell, windowsVariadic: true);
        Assert.Equal(PassStyle.Indirect, large.Style);
        Assert.True(large.IndirectAsPointer);

        Assert.Equal("[3 x float]", Aapcs64Abi.ClassifyArgument(three, spell, darwin: true).LlvmType);
    }

    /// <summary>
    /// A coerced value's registers cover the whole of it and no more, which is
    /// the invariant that a shape being one register out would break.
    /// </summary>
    [Theory]
    [InlineData("B3")]
    [InlineData("B5")]
    [InlineData("B9")]
    [InlineData("B16")]
    [InlineData("F2")]
    [InlineData("F3")]
    [InlineData("D2")]
    [InlineData("MixDI")]
    [InlineData("MixBD")]
    [InlineData("Inline3")]
    public void CoercedRegistersCoverTheWholeValue(string shape)
    {
        var info = SysVArg(shape);
        int size = Front.Struct(Shapes, shape).Size;

        // One register per eightbyte, no more and no fewer.
        Assert.Equal((size + 7) / 8, info.Pieces.Count);
    }

    // -------------------------------------------------- and through the emitter

    /// <summary>
    /// The classifiers are not consulted on their own -- a signature is what
    /// actually crosses a call -- so one shape is followed all the way into the
    /// IR under both ABIs, to show the flag reaches that far.
    /// </summary>
    [Fact]
    public void TheAbiFlagReachesTheEmittedSignature()
    {
        const string source = """
            public struct Pair { public double A; public int B; }
            public double Take(Pair v) { return v.A; }
            """;

        // Both ABIs are x64's, whatever this machine is.
        var before = TargetPlatform.Current;
        TargetPlatform.Current = TargetPlatform.X64Windows;
        string itanium;
        string microsoft;
        try
        {
            itanium = Front.ModuleIr(source, CppAbi.Itanium);
            microsoft = Front.ModuleIr(source, CppAbi.Microsoft);
        }
        finally
        {
            TargetPlatform.Current = before;
        }

        // Qualified by the module, because a fragment alone finds whatever
        // the standard library happens to call something: `Standard.Xml` has
        // a `Take` of its own, and it was matching first.
        Assert.Contains("double %arg.v.0, i32 %arg.v.1", Front.Function(itanium, "4Test4Take"));
        Assert.Contains("ptr byval(%struct.Test_Pair) %arg.v", Front.Function(microsoft, "4Test4Take"));
    }

    /// <summary>
    /// The same, for the convention no test can run: ARM64 is classified and
    /// emitted here and executed nowhere, so the IR is the whole of the
    /// evidence and it is stated rather than described.
    ///
    /// <para>
    /// Three things are being watched. A twelve-byte struct arrives in two
    /// eight-byte registers and is written into sixteen bytes that are not the
    /// object, because storing them over the object would overwrite four bytes
    /// past the end of it. A homogeneous aggregate arrives as its members. And
    /// a large one arrives as a bare pointer rather than as <c>byval</c>, which
    /// LLVM would lower to the value on the outgoing stack instead.
    /// </para>
    /// </summary>
    [Fact]
    public void Arm64ReachesTheEmittedSignature()
    {
        const string source = """
            public struct Tri { public int A; public int B; public int C; }
            public struct Trio { public float A; public float B; public float C; }
            public struct Big { public long A; public long B; public sbyte C; }
            public int Three(Tri v) { return v.A; }
            public float Floats(Trio v) { return v.A; }
            public long Large(Big v) { return v.A; }
            """;

        var before = TargetPlatform.Current;
        TargetPlatform.Current = TargetPlatform.Arm64Linux;
        string ir;
        try { ir = Front.ModuleIr(source); }
        finally { TargetPlatform.Current = before; }

        string three = Front.Function(ir, "4Test5Three");
        Assert.Contains("[2 x i64] %arg.v", three);
        Assert.Contains("@llvm.memcpy", three);

        Assert.Contains("[3 x float] %arg.v", Front.Function(ir, "4Test6Floats"));

        string large = Front.Function(ir, "4Test5Large");
        Assert.Contains("ptr %arg.v", large);
        Assert.DoesNotContain("byval", large);
    }

    /// <summary>
    /// Darwin's widening reaches every place a signature is written: a
    /// definition, an export, a C declaration, a direct call, a call through a
    /// delegate and one through a closure. A callee told the caller widened
    /// reads the whole register, so a site that forgot would hand it garbage
    /// in the upper bits.
    /// </summary>
    [Fact]
    public void DarwinWideningReachesEverySignature()
    {
        const string source = """
            public delegate short Narrow(byte b);
            public struct Empty { }
            extern "C" bool flag(sbyte a, char c);
            extern "C" int report(byte* format, ...);
            export "C" ushort widen(short a) => (ushort)a;
            public short Half(byte b) => (short)(b / 2);
            public int Skip(int a, Empty e, int b) => a + b;
            public int Use(Narrow through)
            {
                Empty e;
                Func<sbyte, bool> closure = (sbyte v) => v > 0;
                bool f = flag(1, 'a');
                short s = through(3);
                bool c = closure(-1);
                report("x", (byte)1);
                return Skip(1, e, 2) + Half(4) + (int)widen(5);
            }
            """;

        var before = TargetPlatform.Current;
        TargetPlatform.Current = TargetPlatform.Arm64MacOS;
        string ir;
        try { ir = Front.ModuleIr(source); }
        finally { TargetPlatform.Current = before; }

        Assert.Contains("declare zeroext i1 @flag(i8 signext, i8 signext)", ir);
        Assert.Contains("define zeroext i16 @widen(i16 signext %arg.a)", ir);
        Assert.Contains("signext i16 @_SL4Test4HalfhEs(i8 zeroext %arg.b)", ir);
        Assert.Contains("i32 @_SL4Test4Skip", ir);
        Assert.Contains("(i32 %arg.a, i32 %arg.b)", Front.Function(ir, "4Test4Skip"));

        string use = Front.Function(ir, "4Test3Use");
        Assert.Contains("call zeroext i1 @flag(i8 signext 1, i8 signext 97)", use);
        Assert.Contains("call signext i16 %", use);
        Assert.Contains("(i8 zeroext 3)", use);
        Assert.Contains("call zeroext i1 %", use);
        Assert.Contains("i8 signext -1)", use);
        Assert.Contains("call i32 (ptr, ...) @report(ptr ", use);
        Assert.Contains("call i32 @_SL4Test4Skip", use);
        Assert.Contains("(i32 1, i32 2)", use);
        Assert.Contains("call signext i16 @_SL4Test4HalfhEs(i8 zeroext 4)", use);
        Assert.Contains("call zeroext i16 @widen(i16 signext 5)", use);
    }

    /// <summary>
    /// ARM64 Linux widens nothing, as clang does not, so the same source keeps
    /// its bare types there.
    /// </summary>
    [Fact]
    public void Arm64LinuxWidensNothing()
    {
        const string source = "export \"C\" ushort widen(short a) => (ushort)a;";

        var before = TargetPlatform.Current;
        TargetPlatform.Current = TargetPlatform.Arm64Linux;
        string ir;
        try { ir = Front.ModuleIr(source); }
        finally { TargetPlatform.Current = before; }

        Assert.Contains("define i16 @widen(i16 %arg.a)", ir);
    }

    private static readonly string[] s_vectorShapes =
        ["vbyte2", "vbyte3", "vshort3", "vbyte8", "vint2", "vfloat2", "vfloat3", "vint4", "vdouble3", "vbyte64"];

    /// <summary>
    /// How clang 21 declared <c>T pass(T a)</c> over ext_vector_type for a
    /// target, one shape per rule a convention has for vectors.
    /// </summary>
    private static string ClangVectorSignature(string target, string vector)
    {
        string plain = LlvmEmitter.LlvmTypeOf(VectorTypeSymbol.Named(vector)!);
        string name = "@pass_" + vector;
        bool wide = target == "x64-linux";

        return target switch
        {
            "x64-windows" => $"define {plain} {name}({plain} %arg.a)",
            "x86-windows" => $"define {plain} {name}({plain} inreg %arg.a)",
            "x86-linux" => $"define {plain} {name}({(vector is "vbyte8" or "vint2" ? "i64" : plain)} %arg.a)",
            "x64-linux" or "x64-macos" => vector switch
            {
                "vbyte2" => $"define i16 {name}(i16 %arg.a)",
                "vbyte3" => $"define i32 {name}(i32 %arg.a)",
                "vshort3" or "vbyte8" or "vint2" or "vfloat2" => $"define double {name}(double %arg.a)",
                "vdouble3" => $"define {plain} {name}(ptr byval({plain}) align {(wide ? 32 : 16)} %arg.a)",
                "vbyte64" => $"define {plain} {name}(ptr byval({plain}) align {(wide ? 64 : 16)} %arg.a)",
                _ => $"define {plain} {name}({plain} %arg.a)",
            },
            _ => vector switch
            {
                "vbyte2" or "vbyte3" => $"define {plain} {name}(i32 %arg.a)",
                "vshort3" => $"define {plain} {name}(<2 x i32> %arg.a)",
                "vfloat3" => $"define {plain} {name}(<4 x i32> %arg.a)",
                "vdouble3" or "vbyte64" => $"define void {name}(ptr sret({plain}) %sret.result, ptr %arg.a)",
                _ => $"define {plain} {name}({plain} %arg.a)",
            },
        };
    }

    [Theory]
    [InlineData("x64-windows")]
    [InlineData("x86-windows")]
    [InlineData("arm64-windows")]
    [InlineData("x64-linux")]
    [InlineData("x86-linux")]
    [InlineData("arm64-linux")]
    [InlineData("x64-macos")]
    [InlineData("arm64-macos")]
    public void AVectorCrossesAsClangPassesIt(string target)
    {
        string source = string.Concat(
            s_vectorShapes.Select(v => $"export \"C\" {v} pass_{v}({v} a) => a;\n"));

        var before = TargetPlatform.Current;
        TargetPlatform.Current = TargetPlatform.Parse(target)!;
        string ir;
        try { ir = Front.ModuleIr(source, TargetPlatform.Current.Abi); }
        finally { TargetPlatform.Current = before; }

        // Windows marks an export, which clang's own definition does not say.
        ir = ir.Replace("define dllexport ", "define ");
        Assert.All(s_vectorShapes, v => Assert.Contains(ClangVectorSignature(target, v), ir));
    }
}
