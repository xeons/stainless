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

using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// The binder: which code it reports, and where it points.
///
/// An <c>errors.txt</c> case says a code was reported somewhere in the
/// program. These say it was reported about the right piece of text, which is
/// the difference between a diagnostic that helps and one that merely fires.
/// </summary>
public class BinderTests
{
    /// <summary>
    /// The one code a function body reports, together with the source it
    /// underlines.
    /// </summary>
    private static (string Code, string Underlined) One(string body)
    {
        string source = "module Test;\nint Main()\n{\n" + body + "\n    return 0;\n}";
        Front.BindBody(body, out var diagnostics);
        var diagnostic = Front.Only(diagnostics);
        return (diagnostic.Code, Front.Underlined(source, diagnostic));
    }

    /// <summary>The same, for a whole module body.</summary>
    private static (string Code, string Underlined) OneInModule(string body)
    {
        string source = "module Test;\n" + body;
        Front.BindModule(body, out var diagnostics);
        var diagnostic = Front.Only(diagnostics);
        return (diagnostic.Code, Front.Underlined(source, diagnostic));
    }

    // ------------------------------------------------------------- clean

    [Theory]
    [InlineData("int x = 1;")]
    [InlineData("int i = 1; long l = i;")]
    [InlineData("char c = 'a';")]
    [InlineData("char16 c = 'a';")]
    [InlineData("char32 c = 'a';")]
    [InlineData("int[] a = [1, 2, 3];")]
    [InlineData("int[3] a = [1, 2, 3];")]
    [InlineData("var a = [1, 2, 3];")]
    [InlineData("String s = \"hi\";")]
    [InlineData("var s = \"a\" + \"b\";")]
    [InlineData("bool b = 1 < 2 && 3 > 2;")]
    public void SomethingCorrectReportsNothing(string body) =>
        Assert.Empty(Front.BodyCodes(body));

    // ------------------------------------------------------ where it points

    /// <summary>
    /// A type mismatch underlines the value, not the declaration: the
    /// declaration is what the programmer meant and the value is what went
    /// wrong.
    /// </summary>
    [Fact]
    public void AMismatchUnderlinesTheValue() =>
        Assert.Equal(("SL0265", "\"s\""), One("int x = \"s\";"));

    [Fact]
    public void ALiteralTooLargeForItsTypeUnderlinesTheLiteral() =>
        Assert.Equal(("SL0265", "300"), One("byte b = 300;"));

    /// <summary>
    /// A narrowing conversion underlines the value being narrowed, which is
    /// where the cast would have to go.
    /// </summary>
    [Theory]
    [InlineData("long l = 1; int i = l;", "l")]
    [InlineData("float f = 1; int i = f;", "f")]
    public void ANarrowingConversionUnderlinesTheSource(string body, string underlined) =>
        Assert.Equal(("SL0265", underlined), One(body));

    [Fact]
    public void AnUnknownFunctionUnderlinesItsName() =>
        Assert.Equal(("SL0252", "nope"), One("nope();"));

    [Fact]
    public void AnUnknownNameUnderlinesItself() =>
        Assert.Equal(("SL0229", "nope"), One("int x = nope;"));

    [Fact]
    public void WritingAConstUnderlinesTheTarget() =>
        Assert.Equal(("SL0240", "y"), One("const int y = 0; y = 1;"));

    /// <summary>
    /// A redeclaration underlines the second one, since the first was fine
    /// until the second arrived.
    /// </summary>
    [Fact]
    public void ARedeclarationUnderlinesTheSecond() =>
        Assert.Equal(("SL0218", "int x = 2;"), One("int x = 1; int x = 2;"));

    [Fact]
    public void ANonBooleanConditionUnderlinesTheCondition() =>
        Assert.Equal(("SL0227", "1"), One("if (1) { }"));

    [Fact]
    public void DivisionByAConstantZeroUnderlinesTheWholeExpression() =>
        Assert.Equal(("SL0415", "1 / 0"), One("int i = 1 / 0;"));

    [Fact]
    public void UsingAVoidCallAsAValueUnderlinesTheCall() =>
        Assert.Equal(("SL0265", "F()"),
                     OneInModule("public void F() { }\npublic int G() { return F(); }"));

    // ----------------------------------------------------------- code units

    /// <summary>
    /// The three character types are three encodings, not three widths, so
    /// none of them becomes another on its own.
    /// </summary>
    [Fact]
    public void OneEncodingDoesNotBecomeAnother() =>
        Assert.Equal(("SL0527", "a"), One("char16 a = 'a'; char b = a;"));

    /// <summary>
    /// A literal takes the narrowest of the three that holds it whole, so a
    /// scalar that does not fit in one UTF-8 byte is not a <c>char</c>.
    /// </summary>
    [Fact]
    public void ALiteralThatDoesNotFitIsRejected() =>
        Assert.Equal("SL0527", One("char c = '\U0001F600';").Code);

    [Theory]
    [InlineData("char c = 'a';")]
    [InlineData("char16 c = 'a';")]
    [InlineData("char32 c = 'a';")]
    [InlineData("char16 c = '€';")]
    [InlineData("char32 c = '\U0001F600';")]
    public void ALiteralSettlesIntoAnyEncodingThatHoldsIt(string body) =>
        Assert.Empty(Front.BodyCodes(body));

    // -------------------------------------------------------- array literals

    [Fact]
    public void AnArrayLiteralOfTheWrongLengthUnderlinesTheLiteral() =>
        Assert.Equal(("SL0547", "[1, 2, 3]"), One("int[2] a = [1, 2, 3];"));

    /// <summary>
    /// An empty literal with nothing to settle against has no element type to
    /// find, and says so rather than guessing one.
    /// </summary>
    [Fact]
    public void AnEmptyArrayLiteralWithNoTargetIsRejected() =>
        Assert.Equal(("SL0548", "[]"), One("var a = [];"));

    /// <summary>
    /// When the elements decide, they have to agree; the odd one out is what
    /// gets underlined.
    /// </summary>
    [Fact]
    public void ElementsThatDisagreeUnderlineTheOddOneOut() =>
        Assert.Equal(("SL0549", "\"two\""), One("var a = [1, \"two\"];"));

    // ---------------------------------------------------------- narrowing

    /// <summary>The shapes a fact survives, and the ones it does not.</summary>
    private static string[] Narrowing(string body) =>
        Front.ModuleCodes("public class C { public int V; }\nint Main()\n{\n    " +
                          body + "\n    return 0;\n}");

    [Fact]
    public void AnOptionalCannotBeReachedThroughUnchecked() =>
        Assert.Equal(["SL0248"], Narrowing("C? c = null; int n = c.V;"));

    [Theory]
    [InlineData("C? c = null; if (c != null) { int n = c.V; }")]
    [InlineData("C? c = null; if (c == null) { return 0; } int n = c.V;")]
    [InlineData("C? c = null; if (c != null && c.V > 0) { }")]
    [InlineData("C? c = null; if (!(c == null)) { int n = c.V; }")]
    [InlineData("C? c = null; int n = c != null ? c.V : 0;")]
    [InlineData("C? c = null; if (c == null || c.V > 0) { }")]
    public void ACheckNarrowsAnOptional(string body) => Assert.Empty(Narrowing(body));

    /// <summary>
    /// An assignment takes the proof away: what was checked is not what is
    /// there any more.
    /// </summary>
    [Fact]
    public void AnAssignmentForgetsTheFact() =>
        Assert.Equal(["SL0248"],
                     Narrowing("C? c = null; if (c != null) { c = null; int n = c.V; }"));

    /// <summary>
    /// A weak reference is never narrowed. It may die between the check and
    /// the use, and no amount of flow analysis can see that happen.
    /// </summary>
    [Fact]
    public void AWeakReferenceIsNeverNarrowed() =>
        Assert.Equal(["SL0248"],
                     Narrowing("weak C? c = null; if (c != null) { int n = c.V; }"));

    // ------------------------------------------------------- declarations

    [Fact]
    public void ADuplicateTypeUnderlinesTheSecond() =>
        Assert.Equal(("SL0201", "class C { }"), OneInModule("class C { }\nclass C { }"));

    /// <summary>
    /// A class that claims an interface must supply it, and the diagnostic
    /// points at the interface it failed to supply rather than at the class.
    /// </summary>
    [Fact]
    public void AnUnimplementedInterfaceUnderlinesTheInterface() =>
        Assert.Equal(("SL0305", "I"),
                     OneInModule("interface I { int F(); }\nclass C : I { }"));

    /// <summary>
    /// A com interface needs a <c>[Guid]</c> -- there is nothing to ask
    /// <c>QueryInterface</c> for without one -- and must derive from
    /// something, since a vtable that does not begin with IUnknown is not COM.
    /// </summary>
    [Fact]
    public void ABareComInterfaceIsRejectedTwice() =>
        Assert.Equal(["SL0534", "SL0537"], Front.ModuleCodes("com interface IThing { }"));

    /// <summary>
    /// Overloads that differ in a parameter type are fine; this is the
    /// baseline the duplicate case is measured against.
    /// </summary>
    [Fact]
    public void OverloadsThatDifferAreAccepted() =>
        Assert.Empty(Front.ModuleCodes(
            "public int F(int a) { return a; }\npublic int F(long a) { return 0; }"));

    /// <summary>
    /// Private means private to the module, not to the type: every file is
    /// compiled together and a module is the unit that has a boundary.
    /// </summary>
    [Fact]
    public void PrivateIsPrivateToTheModule() =>
        Assert.Empty(Front.ModuleCodes(
            "class C { private int x; }\npublic int G() { var c = new C(); return c.x; }"));

    // ------------------------------------------------------------ the program

    [Fact]
    public void ABoundProgramCollectsWhatItDeclared()
    {
        var program = Front.BindModule(
            """
            public class C { public int V; }
            public struct S { public int A; }
            public interface I { int F(); }
            public int G() { return 0; }
            """, out var diagnostics);

        Assert.Empty(Front.Codes(diagnostics));
        Assert.Contains(program.Classes, c => c.Name == "C");
        Assert.Contains(program.Structs, s => s.Name == "S");
        Assert.Contains(program.Interfaces, i => i.Name == "I");
        Assert.Contains(program.Functions, f => f.Symbol.Name == "G");
    }

    /// <summary>
    /// A generic is monomorphized, so two instantiations are two types and one
    /// instantiation used twice is one.
    /// </summary>
    [Fact]
    public void EachInstantiationIsItsOwnType()
    {
        var program = Front.BindModule(
            """
            public struct Box<T> { public T Value; }
            public int F(Box<int> a, Box<int> b, Box<long> c) { return 0; }
            """, out var diagnostics);

        Assert.Empty(Front.Codes(diagnostics));
        Assert.Equal(2, program.Structs.Count(s => s.Name.StartsWith("Box", StringComparison.Ordinal)));
    }

    /// <summary>An entry point is found, and is the one that was written.</summary>
    [Fact]
    public void TheEntryPointIsFound()
    {
        var program = Front.Bind("module Test;\nint Main() { return 0; }", out var diagnostics);

        Assert.Empty(Front.Codes(diagnostics));
        Assert.NotNull(program.EntryPoint);
        Assert.Equal("Main", program.EntryPoint.Name);
    }

    [Fact]
    public void AProgramWithNoMainIsNotedRatherThanCrashed()
    {
        var program = Front.Bind("module Test;\nint F() { return 0; }", out _);
        Assert.Null(program.EntryPoint);
    }
}
