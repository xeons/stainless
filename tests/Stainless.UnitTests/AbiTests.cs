// Stainless - an experimental systems language.
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
        """;

    private static ArgInfo Win64Arg(string name) =>
        Win64Abi.ClassifyArgument(Front.Struct(Shapes, name), LlvmEmitter.LlvmTypeOf);

    private static ArgInfo Win64Return(string name) =>
        Win64Abi.ClassifyReturn(Front.Struct(Shapes, name), LlvmEmitter.LlvmTypeOf);

    private static ArgInfo SysVArg(string name) =>
        SysVAbi.ClassifyArgument(Front.Struct(Shapes, name), LlvmEmitter.LlvmTypeOf);

    private static ArgInfo SysVReturn(string name) =>
        SysVAbi.ClassifyReturn(Front.Struct(Shapes, name), LlvmEmitter.LlvmTypeOf);

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
    /// zero-size extension -- and the two conventions then disagree about it.
    /// Win64 sees a one-byte struct and gives it a register; System V finds no
    /// field in the eightbyte and sends the whole thing to memory.
    ///
    /// This is recorded, not blessed. clang passes an empty struct in no
    /// register at all under System V, so the memory answer is a divergence
    /// rather than agreement; it is the one shape here that was not checked
    /// against clang, because an empty struct crossing a real call is not
    /// something any Stainless program does yet. If this test starts failing
    /// because someone fixed it, the fix is probably right.
    /// </summary>
    [Fact]
    public void TheTwoConventionsDisagreeAboutAnEmptyStruct()
    {
        Assert.Equal(1, Front.Struct(Shapes, "Empty").Size);
        Assert.Equal(PassStyle.Coerce, Win64Arg("Empty").Style);
        Assert.Equal(PassStyle.Indirect, SysVArg("Empty").Style);
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

        Assert.Contains(
            "double %arg.v.0, i32 %arg.v.1",
            Front.Function(Front.ModuleIr(source, CppAbi.Itanium), "4Take"));

        Assert.Contains(
            "ptr byval(%struct.Test_Pair) %arg.v",
            Front.Function(Front.ModuleIr(source, CppAbi.Microsoft), "4Take"));
    }
}
