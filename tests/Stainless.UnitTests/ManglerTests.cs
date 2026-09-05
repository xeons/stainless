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
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// Name mangling, which is where a signature becomes a linker symbol.
///
/// The C++ half has a witness: a program that links against clang's output
/// agrees with clang or it does not link. The Stainless half has none -- both
/// sides of every call are ours -- so a symbol that is wrong in a consistent
/// way links perfectly and stays wrong.
/// </summary>
public class ManglerTests
{
    /// <summary>Every distinct parameter type the language has, in one module.</summary>
    private const string EveryShape = """
        import Standard.Com;

        [Guid("11111111-1111-1111-1111-111111111111")]
        public com interface ICom { int A(); }

        public interface IPlain { int P(); }
        public class Cls { }
        public struct St { public int X; }
        public enum En { A }
        public variant Var { Ok(int Value); No; }
        public delegate int Del(int x);

        public void TakeNothing() { }
        public void TakePrim(int a) { }
        public void TakePointer(int* a) { }
        public void TakeArray(int[] a) { }
        public void TakeSlice(int[:] a) { }
        public void TakeFixed3(ref int[3] a) { }
        public void TakeFixed4(ref int[4] a) { }
        public void TakeFixedLong(ref long[3] a) { }
        public void TakeOptional(Cls? a) { }
        public void TakeWeak(weak Cls? a) { }
        public void TakeClass(Cls a) { }
        public void TakeInterface(IPlain a) { }
        public void TakeCom(ICom a) { }
        public void TakeStruct(St a) { }
        public void TakeEnum(En a) { }
        public void TakeVariant(Var a) { }
        public void TakeDelegate(Del a) { }
        """;

    private static readonly Lazy<BoundProgram> Shapes = new(() =>
    {
        var program = Front.BindModule(EveryShape, out var diagnostics);
        Assert.Empty(Front.Codes(diagnostics));
        return program;
    });

    private static IEnumerable<FunctionSymbol> Takers() => Shapes.Value.Modules
        .SelectMany(m => m.Functions)
        .Where(f => f.ModuleName == "Test" && f.Name.StartsWith("Take", StringComparison.Ordinal));

    private static string Mangled(string name) =>
        Mangler.Mangle(Takers().First(f => f.Name == name));

    // ---------------------------------------------------------------- shape

    /// <summary>
    /// The grammar, spelled out: the module path, then the name, then the
    /// parameters, then <c>E</c>, then the return type.
    /// </summary>
    [Fact]
    public void ASymbolIsPathThenParametersThenReturn() =>
        Assert.Equal("_SL4Test11TakeNothingvEv", Mangled("TakeNothing"));

    [Theory]
    [InlineData("TakePrim", "_SL4Test8TakePrimiEv")]
    [InlineData("TakePointer", "_SL4Test11TakePointerPiEv")]
    [InlineData("TakeArray", "_SL4Test9TakeArrayAiEv")]
    [InlineData("TakeOptional", "_SL4Test12TakeOptionalOC8Test_ClsEv")]
    [InlineData("TakeWeak", "_SL4Test8TakeWeakWC8Test_ClsEv")]
    [InlineData("TakeClass", "_SL4Test9TakeClassC8Test_ClsEv")]
    [InlineData("TakeInterface", "_SL4Test13TakeInterfaceI11Test_IPlainEv")]
    [InlineData("TakeStruct", "_SL4Test10TakeStructS7Test_StEv")]
    [InlineData("TakeEnum", "_SL4Test8TakeEnumE7Test_EnEv")]
    [InlineData("TakeDelegate", "_SL4Test12TakeDelegateD8Test_DelEv")]
    public void EachTypeHasItsOwnCode(string name, string expected) =>
        Assert.Equal(expected, Mangled(name));

    /// <summary>
    /// A com interface is not an <c>InterfaceTypeSymbol</c> -- the two have
    /// different dispatch and different references -- so it needs a code of
    /// its own. It had none and fell through to the fallback, which is also
    /// what "no parameters" is spelled as, so every com interface parameter
    /// mangled to nothing at all.
    /// </summary>
    [Fact]
    public void AComInterfaceHasItsOwnCode() =>
        Assert.Equal("_SL4Test7TakeComM9Test_IComEv", Mangled("TakeCom"));

    /// <summary>
    /// A fixed-length array carries its length and its element, so three of
    /// them are three symbols. This fell through to the same fallback.
    /// </summary>
    [Fact]
    public void AFixedArrayCarriesItsLengthAndElement()
    {
        Assert.Equal("_SL4Test10TakeFixed3F3_iEv", Mangled("TakeFixed3"));
        Assert.Equal("_SL4Test10TakeFixed4F4_iEv", Mangled("TakeFixed4"));
        Assert.Equal("_SL4Test13TakeFixedLongF3_lEv", Mangled("TakeFixedLong"));
    }

    /// <summary>
    /// A slice and a variant are structs -- one is a pointer and a length, the
    /// other a tag and a payload -- and mangle as the structs they are.
    /// </summary>
    [Fact]
    public void ASliceAndAVariantAreStructs()
    {
        Assert.Contains("S15Standard_int___", Mangled("TakeSlice"));
        Assert.Contains("S8Test_Var", Mangled("TakeVariant"));
    }

    // ------------------------------------------------------- what must differ

    /// <summary>
    /// No two of those signatures may produce the same symbol.
    ///
    /// This is the check that was missing. Two type kinds had no code of their
    /// own and both fell through to the same fallback, so the compiler emitted
    /// two functions under one name and left LLVM to object to the
    /// redefinition -- or, at a call, to pick whichever it saw first.
    /// </summary>
    [Fact]
    public void NoTwoSignaturesShareASymbol()
    {
        var collisions = Takers()
            .GroupBy(Mangler.Mangle)
            .Where(g => g.Count() > 1)
            .Select(g => g.Key + ": " + string.Join(" and ", g.Select(f => f.Name)))
            .ToList();

        Assert.Empty(collisions);
    }

    /// <summary>
    /// And no parameter mangles to nothing. <c>v</c> is void, so a signature
    /// that spells one with it is a signature the symbol does not mention --
    /// which is exactly how the two missing codes hid.
    /// </summary>
    [Fact]
    public void OnlyNothingManglesToNothing()
    {
        foreach (var function in Takers())
        {
            bool takesNothing = function.Parameters.Count == 0;
            bool spelledAsVoid = Mangler.Mangle(function)
                .Contains("vE", StringComparison.Ordinal);

            Assert.Equal(takesNothing, spelledAsVoid);
        }
    }

    // ------------------------------------------------------------- generics

    /// <summary>
    /// An instantiation carries its type arguments, so the methods of
    /// <c>Box&lt;int&gt;</c> and <c>Box&lt;long&gt;</c> have different symbols
    /// even where their parameters alone would not tell them apart.
    /// </summary>
    [Fact]
    public void InstantiationsOfAGenericDiffer()
    {
        var program = Front.BindModule(
            """
            public class Box<T> { T value; public void Set(T v) { value = v; } }
            public void F()
            {
                var a = new Box<int>();
                var b = new Box<long>();
                a.Set(1);
                b.Set(1);
            }
            """, out var diagnostics);

        Assert.Empty(Front.Codes(diagnostics));

        var setters = program.Functions
            .Select(f => f.Symbol)
            .Where(f => f.Name == "Set" && f.ModuleName == "Test")
            .Select(Mangler.Mangle)
            .Distinct()
            .ToList();

        Assert.Equal(2, setters.Count);
    }

    // ---------------------------------------------------- symbol-safe names

    /// <summary>
    /// A generic's simple name reaches the mangler as <c>Box&lt;int&gt;</c>,
    /// which no linker symbol may contain, so everything that is not
    /// alphanumeric becomes an underscore.
    /// </summary>
    [Theory]
    [InlineData("Box<int>", "Box_int_")]
    [InlineData("App.Thing", "App_Thing")]
    [InlineData("Plain", "Plain")]
    public void QualifiedNamesAreMadeSymbolSafe(string name, string expected) =>
        Assert.Equal(expected, Mangler.SymbolSafe(name));

    [Fact]
    public void ASymbolSafeNameIsAlwaysASymbol() =>
        Assert.All(
            new[] { "Box<int>", "A.B.C", "List<Map<int, String>>", "x" },
            name => Assert.All(Mangler.SymbolSafe(name),
                               c => Assert.True(char.IsLetterOrDigit(c) || c == '_')));

    // ------------------------------------------------------------------ C++

    /// <summary>
    /// The two C++ schemes agree on nothing, which is why <c>--abi</c> exists.
    /// These are the examples the ABI notes give, so the document and the
    /// compiler cannot drift apart quietly.
    /// </summary>
    [Theory]
    [InlineData("int add(int a, int b);", CppAbi.Itanium, "add", "_Z3addii")]
    [InlineData("int add(int a, int b);", CppAbi.Microsoft, "add", "?add@@YAHHH@Z")]
    [InlineData("void nothing();", CppAbi.Itanium, "nothing", "_Z7nothingv")]
    [InlineData("void nothing();", CppAbi.Microsoft, "nothing", "?nothing@@YAXXZ")]
    [InlineData("int deref(int* a, int* b);", CppAbi.Itanium, "deref", "_Z5derefPiS_")]
    [InlineData("int deref(int* a, int* b);", CppAbi.Microsoft, "deref", "?deref@@YAHPEAH0@Z")]
    public void CppManglingFollowsTheNamedScheme(
        string declaration, CppAbi abi, string name, string expected)
    {
        var program = Front.BindModule(
            "public extern \"C++\" " + declaration, out var diagnostics, abi);

        Assert.Empty(Front.Codes(diagnostics));

        var function = program.Modules.SelectMany(m => m.Functions)
            .First(f => f.ModuleName == "Test" && f.Name == name);

        Assert.Equal(expected, function.ForeignName);
    }
}
