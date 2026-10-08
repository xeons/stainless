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

    /// <summary>
    /// A <c>params</c> call is resolved as C# resolves one: the declared form
    /// is better than the expanded one where the arguments convert as well
    /// either way, and otherwise the better conversion wins.
    /// </summary>
    [Theory]
    [InlineData("int F(int a) => 1;\nint F(params int[] a) => 2;\nint G() => F(1);")]
    [InlineData("int F(int[] a) => 1;\nint F(params int[][] a) => 2;\nint G(int[] x) => F(x);")]
    [InlineData("int F(params int[] a) => 1;\nint F(params long[] a) => 2;\nint G() => F(1, 2);")]
    [InlineData("int F(params Span<int> a) => 1;\nint G() => F();")]
    [InlineData("int F(int a, params int[] b) => 1;\nint G() => F(b: [1], a: 2);")]
    public void AParamsCallResolvesWithoutAmbiguity(string module) =>
        Assert.Empty(Front.ModuleCodes(module));

    [Theory]
    [InlineData("int F(params int[] a, int b) => 1;")]
    [InlineData("int F(params int a) => 1;")]
    [InlineData("int F(out params int[] a) { a = []; return 1; }")]
    [InlineData("public delegate int D(params int[] a);")]
    public void AMisplacedParamsIsRefused(string module) =>
        Assert.Contains("SLC0101", Front.ModuleCodes(module));

    /// <summary>
    /// Storage that may not be written may not be lent by 'ref' or 'out'
    /// either, through a field of it as much as whole.
    /// </summary>
    [Theory]
    [InlineData("void Bump(ref double d) { }\nvoid F(in P p) => Bump(ref p.X);")]
    [InlineData("void Fill(out double d) { d = 0.0; }\nvoid F(in P p) => Fill(out p.X);")]
    [InlineData("static readonly P s_p = new P(1.0);\nvoid Bump(ref double d) { }\nvoid F() => Bump(ref s_p.X);")]
    [InlineData("void Bump(ref double d) { }\nvoid F(ReadOnlySpan<P> ps) => Bump(ref ps[0].X);")]
    public void AReadOnlyPlaceIsNotLentThroughAField(string module) =>
        Assert.Equal(["SLT0042"], Front.ModuleCodes(
            "public struct P { public double X; public P(double x) { X = x; } }\n" + module));

    /// <summary>
    /// Generic overloads that both fit are ranked as any overloads are, and a
    /// tie is still an ambiguity.
    /// </summary>
    [Theory]
    [InlineData("int Pick<T>(Span<T> s) => 1;\nint Pick<T>(ReadOnlySpan<T> s) => 2;\nint F(Span<int> s) => Pick(s);", new string[0])]
    [InlineData("int Pick<T>(Span<T> s) => 1;\nint Pick<T>(ReadOnlySpan<T> s) => 2;\nint F(int[] a) => Pick(a);", new string[0])]
    [InlineData("int Pick<T>(T a, int b) => 1;\nint Pick<T>(int a, T b) => 2;\nint F() => Pick(1, 2);", new[] { "SLG0011" })]
    public void GenericOverloadsAreRanked(string module, string[] expected) =>
        Assert.Equal(expected, Front.ModuleCodes(module));

    /// <summary>
    /// A generic type or delegate is declared once per number of type
    /// parameters, as C#'s <c>Func</c> and <c>Action</c> are.
    /// </summary>
    [Theory]
    [InlineData("public closure R Maker<R>();\npublic closure R Maker<T, R>(T value);\nint F(Maker<int> a, Maker<int, int> b) => a() + b(1);", new string[0])]
    [InlineData("public struct Box<T> { public T A; }\npublic struct Box<T, U> { public T A; public U B; }\nint F(Box<int> a, Box<int, long> b) => a.A;", new string[0])]
    [InlineData("public struct Box<T> { public T A; }\npublic struct Box<U> { public U A; }", new[] { "SLN0001" })]
    [InlineData("public struct Pair { public int A; }\npublic struct Pair<T> { public T A; }\nint F(Pair a, Pair<int> b) => a.A + b.A;", new string[0])]
    [InlineData("public struct Box<T> { public T A; }\nint F(Box<int, int> b) => 0;", new[] { "SLG0003" })]
    public void AGenericNameIsDeclaredOncePerArity(string module, string[] expected) =>
        Assert.Equal(expected, Front.ModuleCodes(module));

    /// <summary>
    /// A lambda fits a delegate whose result its body's converts to, and
    /// between two it fits, the one whose result it produces is chosen.
    /// </summary>
    [Theory]
    [InlineData("int Pick<T>(T x, Func<T, int> f) => 1;\nint Pick<T>(T x, Func<T, double> f) => 2;\nint G() => Pick(1, (n) => n + 1);", new string[0])]
    [InlineData("int Pick<T>(T x, Func<T, int> f) => 1;\nint Pick<T>(T x, Func<T, double> f) => 2;\nint G() => Pick(1, (n) => 0.5);", new string[0])]
    [InlineData("int Pick(Func<int, int> f) => 1;\nint G() => Pick((n) => 0.5);", new[] { "SLT0015" })]
    public void ALambdaIsRankedByWhatItReturns(string module, string[] expected) =>
        Assert.Equal(expected, Front.ModuleCodes(module));

    /// <summary>A conditional of two variant cases takes the type it is going to.</summary>
    [Fact]
    public void AConditionalOfTwoCasesIsTargetTyped() =>
        Assert.Empty(Front.ModuleCodes(
            "public enum Why { Bad }\nResult<int, Why> Check(bool good) => good ? Ok(1) : Fail(Why.Bad);"));

    /// <summary>An array literal's elements say what a generic parameter is.</summary>
    [Theory]
    [InlineData("T First<T>(ReadOnlySpan<T> items) => items[0];\nint G() => First([1, 2, 3]);", new string[0])]
    [InlineData("nuint Count<T>(T[] items) => items.Length;\nnuint G() => Count([\"a\", \"b\"]);", new string[0])]
    public void AnArrayLiteralInfersItsElementType(string module, string[] expected) =>
        Assert.Equal(expected, Front.ModuleCodes(module));

    /// <summary>
    /// A struct keeps the promise an interface makes, and is still never a
    /// reference to one.
    /// </summary>
    [Theory]
    [InlineData("public interface IArea { double Area(); }\npublic struct Sq : IArea { public double S; public double Area() => S * S; }\ndouble M<T>(T shape) where T : IArea => shape.Area();\ndouble G(Sq s) => M(s);", new string[0])]
    [InlineData("public interface IArea { double Area(); }\npublic struct Sq : IArea { public double S; public double Area() => S * S; }\nIArea G(Sq s) => s;", new[] { "SLC0010" })]
    [InlineData("public interface IArea { double Area(); }\npublic struct Sq : IArea { public double S; }", new[] { "SLC0013" })]
    [InlineData("public interface IArea { double Area(); }\npublic struct Sq : IArea { public double S; double Area() => S; }", new[] { "SLC0014" })]
    public void AStructImplementsAnInterfaceWithoutBecomingOne(string module, string[] expected) =>
        Assert.Equal(expected, Front.ModuleCodes(module));

    [Theory]
    [InlineData("bool F(int[] a, int[] b) => a == b;", new string[0])]
    [InlineData("bool F(int[] a, int[] b) => a != b;", new string[0])]
    [InlineData("bool F(int[] a, long[] b) => a == b;", new[] { "SLT0006" })]
    public void ArraysCompareByIdentity(string module, string[] expected) =>
        Assert.Equal(expected, Front.ModuleCodes(module));

    // ------------------------------------------------------ where it points

    /// <summary>
    /// A type mismatch underlines the value, not the declaration: the
    /// declaration is what the programmer meant and the value is what went
    /// wrong.
    /// </summary>
    [Fact]
    public void AMismatchUnderlinesTheValue() =>
        Assert.Equal(("SLT0018", "\"s\""), One("int x = \"s\";"));

    /// <summary>
    /// A literal outside its type's range is that rather than a conversion
    /// that needs a cast, and it says so under its own code. The distinction
    /// earns its place: the value is wrong, and no cast makes 300 a byte.
    /// </summary>
    [Theory]
    [InlineData("byte b = 300;", "300")]
    [InlineData("sbyte s = -129;", "-129")]
    [InlineData("int i = 5000000000;", "5000000000")]
    [InlineData("long l = 9223372036854775808;", "9223372036854775808")]
    public void ALiteralTooLargeForItsTypeUnderlinesTheLiteral(string body, string underlined) =>
        Assert.Equal(("SLT0019", underlined), One(body));

    /// <summary>
    /// A literal is the narrowest of int, uint, long and ulong that holds it,
    /// as in C#, so each of these needs no cast. Everything used to start out
    /// an int, and a value past its range was cut to 32 bits on the way out.
    /// </summary>
    [Theory]
    [InlineData("int i = 2147483647;")]
    [InlineData("uint u = 4294967295;")]
    [InlineData("long l = 9223372036854775807;")]
    [InlineData("ulong ul = 18446744073709551615;")]
    [InlineData("nuint n = 5000000000;")]
    [InlineData("double d = 5000000000;")]
    [InlineData("float f = 5000000000;")]
    public void ALiteralAdoptsATypeThatHoldsIt(string body) =>
        Assert.Empty(Front.BodyCodes(body));

    /// <summary>
    /// And a bit pattern past an int meets one as the wider type, which is
    /// what makes a mask written the way a C header writes it mean what it
    /// says rather than what truncation happened to leave.
    /// </summary>
    [Fact]
    public void ABitPatternWidensTheOperationRatherThanBeingCut() =>
        Assert.Empty(Front.BodyCodes("int flags = 1; var masked = flags & 0xFFFF0000;"));

    /// <summary>
    /// A narrowing conversion underlines the value being narrowed, which is
    /// where the cast would have to go.
    /// </summary>
    [Theory]
    [InlineData("long l = 1; int i = l;", "l")]
    [InlineData("float f = 1; int i = f;", "f")]
    public void ANarrowingConversionUnderlinesTheSource(string body, string underlined) =>
        Assert.Equal(("SLT0018", underlined), One(body));

    /// <summary>
    /// An argument that did not bind is reported once. It matches every
    /// overload and none, so overload resolution used to add "the call is
    /// ambiguous" on top -- a second message about the first one's
    /// consequence, printed above it.
    /// </summary>
    [Fact]
    public void AnArgumentThatDidNotBindDoesNotAlsoReportAmbiguity() =>
        Assert.Equal(
            ["SLN0013"],
            Front.ModuleCodes("""
                String Pick(long n) { return "l"; }
                String Pick(nuint n) { return "n"; }
                String Use(String s) { return Pick(s.Nonexistent); }
                """));

    [Fact]
    public void AnUnknownFunctionUnderlinesItsName() =>
        Assert.Equal(("SLN0011", "nope"), One("nope();"));

    [Fact]
    public void AnUnknownNameUnderlinesItself() =>
        Assert.Equal(("SLN0011", "nope"), One("int x = nope;"));

    [Fact]
    public void WritingAConstUnderlinesTheTarget() =>
        Assert.Equal(("SLT0008", "y"), One("const int y = 0; y = 1;"));

    /// <summary>
    /// A redeclaration underlines the second one, since the first was fine
    /// until the second arrived.
    /// </summary>
    [Fact]
    public void ARedeclarationUnderlinesTheSecond() =>
        Assert.Equal(("SLN0008", "int x = 2;"), One("int x = 1; int x = 2;"));

    /// <summary>
    /// Two constructors of one signature are one symbol, and were both emitted
    /// under it. Constructors overload by their parameters, as methods do.
    /// </summary>
    [Theory]
    [InlineData("public class C { public C() { } public C() { } }")]
    [InlineData("public struct S { public S(int a) { } public S(int b) { } }")]
    public void TwoConstructorsOfOneSignatureAreRefused(string declarations) =>
        Assert.Equal(["SLN0006"], Front.ModuleCodes(declarations));

    [Fact]
    public void AConstructorOverloadedByItsParametersIsFine() =>
        Assert.Empty(Front.ModuleCodes("public class C { public C() { } public C(int a) { } }"));

    [Fact]
    public void ANonBooleanConditionUnderlinesTheCondition() =>
        Assert.Equal(("SLT0003", "1"), One("if (1) { }"));

    [Fact]
    public void DivisionByAConstantZeroUnderlinesTheWholeExpression() =>
        Assert.Equal(("SLT0040", "1 / 0"), One("int i = 1 / 0;"));

    [Fact]
    public void UsingAVoidCallAsAValueUnderlinesTheCall() =>
        Assert.Equal(("SLT0018", "F()"),
                     OneInModule("public void F() { }\npublic int G() { return F(); }"));

    // ----------------------------------------------------------- code units

    /// <summary>
    /// The three character types are three encodings, not three widths, so
    /// none of them becomes another on its own.
    /// </summary>
    [Fact]
    public void OneEncodingDoesNotBecomeAnother() =>
        Assert.Equal(("SLT0056", "a"), One("char16 a = 'a'; char b = a;"));

    /// <summary>
    /// A literal takes the narrowest of the three that holds it whole, so a
    /// scalar that does not fit in one UTF-8 byte is not a <c>char</c>.
    /// </summary>
    [Fact]
    public void ALiteralThatDoesNotFitIsRejected() =>
        Assert.Equal("SLT0056", One("char c = '\U0001F600';").Code);

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
        Assert.Equal(("SLT0058", "[1, 2, 3]"), One("int[2] a = [1, 2, 3];"));

    /// <summary>
    /// An empty literal with nothing to settle against has no element type to
    /// find, and says so rather than guessing one.
    /// </summary>
    [Fact]
    public void AnEmptyArrayLiteralWithNoTargetIsRejected() =>
        Assert.Equal(("SLT0059", "[]"), One("var a = [];"));

    /// <summary>
    /// When the elements decide, they have to agree; the odd one out is what
    /// gets underlined.
    /// </summary>
    [Fact]
    public void ElementsThatDisagreeUnderlineTheOddOneOut() =>
        Assert.Equal(("SLT0060", "\"two\""), One("var a = [1, \"two\"];"));

    // ---------------------------------------------------------- narrowing

    /// <summary>The shapes a fact survives, and the ones it does not.</summary>
    private static string[] Narrowing(string body) =>
        Front.ModuleCodes("public class C { public int V; }\nint Main()\n{\n    " +
                          body + "\n    return 0;\n}");

    [Fact]
    public void AnOptionalCannotBeReachedThroughUnchecked() =>
        Assert.Equal(["SLO0001"], Narrowing("C? c = null; int n = c.V;"));

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
        Assert.Equal(["SLO0001"],
                     Narrowing("C? c = null; if (c != null) { c = null; int n = c.V; }"));

    /// <summary>
    /// A weak reference is never narrowed. It may die between the check and
    /// the use, and no amount of flow analysis can see that happen.
    /// </summary>
    [Fact]
    public void AWeakReferenceIsNeverNarrowed() =>
        Assert.Equal(["SLO0026"],
                     Narrowing("weak C? c = null; if (c != null) { int n = c.V; }"));

    // ------------------------------------------------------- declarations

    /// <summary>
    /// A redeclared name underlines the second one. Not a type: a type may now
    /// be declared more than once inside its own module, and the second
    /// declaration adds to the first rather than colliding with it.
    /// </summary>
    [Fact]
    public void ADuplicateNameUnderlinesTheSecond() =>
        Assert.Equal(("SLN0001", "public const int X = 2;"),
                     OneInModule("public const int X = 1;\npublic const int X = 2;"));

    /// <summary>
    /// A class that claims an interface must supply it, and the diagnostic
    /// points at the interface it failed to supply rather than at the class.
    /// </summary>
    [Fact]
    public void AnUnimplementedInterfaceUnderlinesTheInterface() =>
        Assert.Equal(("SLC0013", "I"),
                     OneInModule("interface I { int F(); }\nclass C : I { }"));

    /// <summary>
    /// A com interface needs a <c>[Guid]</c> -- there is nothing to ask
    /// <c>QueryInterface</c> for without one -- and must derive from
    /// something, since a vtable that does not begin with IUnknown is not COM.
    /// </summary>
    [Fact]
    public void ABareComInterfaceIsRejectedTwice() =>
        Assert.Equal(["SLI0028", "SLI0031"], Front.ModuleCodes("com interface IThing { }"));

    /// <summary>
    /// A CLSID on a com class is accepted: it is what lets something ask for
    /// the class rather than be handed one of its objects.
    /// </summary>
    [Fact]
    public void AComClassMayCarryAClsid() =>
        Assert.Empty(Front.ModuleCodes(
            "[Guid(\"9d2f5f7a-1c64-4a3b-8f0e-7d5a2c9b4e10\")] com interface I { int F(); }\n" +
            "[Guid(\"5a1c8e30-2b47-4d16-a9f3-c04e7b81d629\")] com class C : I {\n" +
            "  public int F() { return 0; }\n}"));

    /// <summary>
    /// A class factory has no arguments to pass, so a class that can be asked
    /// for needs a constructor taking none.
    /// </summary>
    [Fact]
    public void AnActivatableClassNeedsAnEmptyConstructor() =>
        Assert.Contains("SLI0035", Front.ModuleCodes(
            "[Guid(\"9d2f5f7a-1c64-4a3b-8f0e-7d5a2c9b4e10\")] com interface I { int F(); }\n" +
            "[Guid(\"5a1c8e30-2b47-4d16-a9f3-c04e7b81d629\")] com class C : I {\n" +
            "  int n;\n  public C(int start) { n = start; }\n" +
            "  public int F() { return n; }\n}"));

    /// <summary>
    /// Declaring no constructor at all is not the same as declaring only ones
    /// that take arguments: the fields are the zeroes the allocator wrote.
    /// </summary>
    [Fact]
    public void AnActivatableClassNeedsNoConstructorAtAll() =>
        Assert.Empty(Front.ModuleCodes(
            "[Guid(\"9d2f5f7a-1c64-4a3b-8f0e-7d5a2c9b4e10\")] com interface I { int F(); }\n" +
            "[Guid(\"5a1c8e30-2b47-4d16-a9f3-c04e7b81d629\")] com class C : I {\n" +
            "  public int F() { return 0; }\n}"));

    /// <summary>
    /// A GUID still means nothing on an ordinary class: it has no vtable for
    /// anything to reach it through.
    /// </summary>
    [Fact]
    public void APlainClassStillRefusesAGuid() =>
        Assert.Contains("SLC0096", Front.ModuleCodes(
            "[Guid(\"5a1c8e30-2b47-4d16-a9f3-c04e7b81d629\")] class C { }"));

    /// <summary>
    /// A <c>[NoUnknown]</c> vtable has no QueryInterface and no IID, so every
    /// spelling of the question is refused where it is written, from either
    /// side. It used to reach the emitter, which wrote a call against an IID
    /// nothing defined, and the build ended in "this is a compiler bug".
    /// </summary>
    [Theory]
    [InlineData("bool r = a is IB;", "SLF0020")]
    [InlineData("bool r = c is IA;", "SLF0020")]
    [InlineData("bool r = a is IC;", "SLF0020")]
    [InlineData("int r = a switch { IB => 1, _ => 0 };", "SLF0020")]
    [InlineData("int r = c switch { IA => 1, _ => 0 };", "SLF0020")]
    [InlineData("var r = (IB)a;", "SLT0011")]
    [InlineData("var r = a as IB;", "SLT0070")]
    public void ANoUnknownInterfaceCannotBeAskedWhatItIs(string statement, string code) =>
        Assert.Equal([code], Front.ModuleCodes(
            "[NoUnknown] com interface IA { void A(); }\n" +
            "[NoUnknown] com interface IB { void B(); }\n" +
            "[Guid(\"9d2f5f7a-1c64-4a3b-8f0e-7d5a2c9b4e10\")] com interface IC { void C(); }\n" +
            "void F()\n{\n    var a = (IA)(byte*)null;\n    var c = (IC)(byte*)null;\n    " +
            statement + "\n}"));

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

    /// <summary>
    /// The compiler's version is a constant every program can name, qualified
    /// or not, and it is a String.
    /// </summary>
    [Fact]
    public void TheCompilerVersionIsAStringConstant() =>
        Assert.Empty(Front.ModuleCodes(
            "public String Built() => Standard.CompilerVersion;\n" +
            "public String Again() => CompilerVersion;"));

    // ---------------------------------------------- a name inside a type

    /// <summary>
    /// A bare call inside a type means that type's member, even when a module
    /// in scope has a function of the same name.
    ///
    /// It used not to: module functions were resolved first, and
    /// `Standard.Text` is imported into every module whether a program asks or
    /// not -- so adding a `Join` to the standard library was enough to capture
    /// `TaskScope`'s call to its own `Join()`.
    /// </summary>
    [Fact]
    public void AMemberWinsOverAModuleFunctionOfTheSameName() =>
        Assert.Empty(Front.ModuleCodes(
            """
            public int Helper(int a, int b) { return a + b; }
            public class C {
                public int Helper() { return 7; }
                public int Use() { return Helper(); }
            }
            """));

    /// <summary>
    /// And a module-level function still finds the module-level one, because
    /// there is no receiver for a member to be found on.
    /// </summary>
    [Fact]
    public void AModuleFunctionStillReachesItsOwnKind() =>
        Assert.Empty(Front.ModuleCodes(
            """
            public int Helper(int a, int b) { return a + b; }
            public class C { public int Helper() { return 7; } }
            public int Use() { return Helper(1, 2); }
            """));

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

    // ------------------------------------------ what a reported error leaves

    /// <summary>
    /// An override of an undefined base, overridden again further down.
    ///
    /// The first override matched nothing and was left with no slot, and the
    /// class deriving from it then matched that method and wrote its own into
    /// slot -1 of the dispatch table.
    /// </summary>
    [Fact]
    public void AnOverrideThatOverridesNothingCanStillBeOverridden()
    {
        var codes = Front.ModuleCodes(
            """
            public class Dog : Animal
            {
                public Dog() { }
                public override String Speak() => "woof";
            }

            public class Puppy : Dog
            {
                public override String Speak() => "yip";
            }
            """);

        Assert.Contains("SLN0017", codes);
        Assert.Contains("SLC0039", codes);
    }

    /// <summary>
    /// The same for each other way an override can fail: each is reported
    /// once, at the class that wrote it, and the class below is not also
    /// blamed for overriding something that is still a dispatched method.
    /// </summary>
    [Theory]
    [InlineData("public String Speak() => \"?\";", "SLC0040")]
    [InlineData("public virtual int Speak() => 0;", "SLC0042")]
    public void AnOverrideThatFailsLeavesADispatchedMethod(string inBase, string code)
    {
        var codes = Front.ModuleCodes(
            $$"""
            public class Animal { {{inBase}} }
            public class Dog : Animal { public override String Speak() => "woof"; }
            public class Puppy : Dog { public override String Speak() => "yip"; }
            """);

        Assert.Equal([code], codes);
    }

    /// <summary>
    /// A generic call with more arguments than any template of its name has
    /// parameters.
    ///
    /// The first template is tried anyway, so that there is something to report
    /// against, and checking whether it accepted the arguments read a parameter
    /// for each argument -- past the end of the list.
    /// </summary>
    [Theory]
    [InlineData(
        "T Middle<T>(T a) => a;\nint Main() { return Middle(1, 2); }")]
    [InlineData(
        "class Util { public T Middle<T>(T a) => a; }\n" +
        "int Main() { var util = new Util(); return util.Middle(1, 2); }")]
    [InlineData(
        "import Standard.Collections;\n" +
        "int Main() { int[] numbers = [3]; return FirstOrDefault(numbers, n => n > 1, 99, 1); }")]
    public void AGenericCallWithTooManyArgumentsIsAnArityError(string body)
    {
        Front.Bind("module Test;\n" + body, out var diagnostics);
        Assert.Contains("SLT0014", Front.Codes(diagnostics));
    }

    /// <summary>
    /// A module-level function written 'static', which reads a name.
    ///
    /// The word is refused, and the function used to keep it anyway: a static
    /// function looking up a bare name asks its type for an instance member of
    /// that name, and this one has no type. The generic form never reported the
    /// word at all.
    /// </summary>
    [Theory]
    [InlineData("static int Free() { return Read; }")]
    [InlineData("static int Free<T>(T value) { return Read; }\nint Use() { return Free(1); }")]
    public void AStaticModuleFunctionIsAnOrdinaryOneOnceReported(string body)
    {
        var codes = Front.ModuleCodes("class Box { }\n" + body);

        Assert.Contains("SLC0123", codes);
        Assert.Contains("SLN0011", codes);
    }

    /// <summary>
    /// A struct that contains itself, by every route to it, with something
    /// that walks its fields after layout.
    ///
    /// SLC0006 was reported and the cycle left in place, so the first of those
    /// walks recursed until the process died of a stack overflow. The cut in
    /// layout answers most of it; the walks carry their own guard for the rest,
    /// because a cycle layout did not see is still a cycle to them.
    /// </summary>
    [Theory]
    [InlineData("struct S { S self; }")]
    [InlineData("struct S { T other; }\nstruct T { S back; }")]
    [InlineData("struct S { S[2] pair; }")]
    [InlineData("struct S { int bits : 3; S self; }")]
    [InlineData("union S { int n; S self; }")]
    [InlineData("variant S { Leaf; Node(S inner); }")]
    [InlineData("struct S { (S, int) pair; }")]
    [InlineData("struct S { (int, (S, byte)) nested; }")]
    public void AStructThatContainsItselfIsReportedAndSurvived(string declaration) =>
        Assert.Contains("SLC0006", Front.ModuleCodes(WalkedEveryWay(declaration)));

    /// <summary>
    /// A tuple of ordinary structs is laid out by the C rules like any other
    /// struct, which is what the cycle check above must not cost: the tuple was
    /// laid out where it was interned, and moving that into the layout pass is
    /// what let the cycle be seen at all.
    /// </summary>
    [Fact]
    public void ATupleIsLaidOutByTheCRules()
    {
        var holder = Front.Struct(
            "public struct Point { public int X; public int Y; }\n" +
            "public struct Holder { public (Point, int) Pair; public byte Tag; }",
            "Holder");

        Assert.Equal(16, holder.Size);
        Assert.Equal(12, holder.Fields.Single(f => f.Name == "Tag").Offset);
    }

    /// <summary>
    /// The declaration, and one of everything that walks a struct's fields
    /// after layout: a union that asks whether it holds a reference, a C
    /// signature that asks the same, a variant case, a thread.
    /// </summary>
    private static string WalkedEveryWay(string declaration) =>
        declaration + "\n" +
        """
        union U { int n; S s; }
        extern "C" void consume(S s);
        export "C" S produce() { S s; return s; }
        variant V { None; Some(S s); }
        void Send(S s) { var worker = go () => { S copy = s; }; }
        """;

    /// <summary>
    /// Every diagnostic's span runs forwards.
    ///
    /// Each of these reported one that ended a character before it began: a
    /// node the parser built having consumed no token of its own takes its
    /// start from the token it stopped at and its end from the one before.
    /// </summary>
    [Theory]
    [InlineData("struct Point { } class Plain { }\nint Main() { new Plain { 1, }; return 0; }")]
    [InlineData(
        "variant Shape { Circle(double Radius); }\n" +
        "double Area(Shape shape) { return shape switch { Circle(((c))) => Radius }; }\n" +
        "int Main() { return 0; }")]
    [InlineData(
        "struct Point { int X; } class Holder<T> where T : Point { T item; }\n" +
        "int Main()\n{\n    Holder<Point\n> h;\n    return 0;\n}")]
    public void EverySpanRunsForwards(string body)
    {
        Front.Bind("module Test;\n" + body, out var diagnostics);

        Assert.NotEmpty(Front.Codes(diagnostics));
        foreach (var diagnostic in diagnostics.Items.Where(d => d.Span.File?.Path == Front.TestFile))
            Assert.True(diagnostic.Span.Start <= diagnostic.Span.End,
                $"{diagnostic.Code} runs from {diagnostic.Span.Start} back to {diagnostic.Span.End}");
    }

    // ------------------------------------------------------------------ asm

    /// <summary>
    /// Runs a test with the ambient target set, and puts it back. The register
    /// tables are the target's, so every question here is asked of a named one
    /// rather than of whatever machine the tests happen to run on.
    /// </summary>
    private static void Under(TargetPlatform target, Action body)
    {
        var before = TargetPlatform.Current;
        TargetPlatform.Current = target;
        try { body(); }
        finally { TargetPlatform.Current = before; }
    }

    [Theory]
    [InlineData("long r = 0; asm (in rcx = 1, out rax = r) { nop }")]
    [InlineData("long r = 0; asm (inout RAX = r) { nop }")]
    [InlineData("int r = 0; asm (in cl = 200, out eax = r) { nop }")]
    [InlineData("short s = -2; long r = 0; asm (in rcx = s, out rdx = r) { nop }")]
    [InlineData("bool b = false; asm (out al = b) { nop }")]
    [InlineData("char c = 'a'; asm (inout al = c) { nop }")]
    [InlineData("int* p = null; asm (in rsi = p) { nop }")]
    [InlineData("double d = 1.0; float f = 1.0f; asm (inout xmm0 = d, inout xmm15 = f) { nop }")]
    [InlineData("double d = 0.0; asm (in xmm1 = 3, out xmm0 = d) { nop }")]
    [InlineData("int r = 0; asm (in r15 = 1, out r8d = r) { nop }")]
    [InlineData("asm { nop }")]
    public void AnX64AsmStatementThatFitsReportsNothing(string body) =>
        Under(TargetPlatform.X64Windows, () => Assert.Empty(Front.BodyCodes(body)));

    [Theory]
    [InlineData("long r = 0; asm (in x0 = 1, inout x30 = r) { nop }")]
    [InlineData("int r = 0; asm (in lr = 1, out w9 = r) { nop }")]
    [InlineData("double d = 0.0; float f = 0.0f; asm (inout v0 = d, inout s1 = f, inout d2 = f) { nop }")]
    [InlineData("long r = 0; asm (in x18 = 1, out x0 = r) { nop }")]
    public void AnArm64AsmStatementThatFitsReportsNothing(string body) =>
        Under(TargetPlatform.Arm64Linux, () => Assert.Empty(Front.BodyCodes(body)));

    [Theory]
    [InlineData("int r = 0; asm (out ebx = r) { nop }")]
    [InlineData("short r = 0; asm (in al = 1, out si = r) { nop }")]
    [InlineData("double d = 0.0; asm (inout xmm7 = d) { nop }")]
    public void AnX86AsmStatementThatFitsReportsNothing(string body) =>
        Under(TargetPlatform.X86Windows, () => Assert.Empty(Front.BodyCodes(body)));

    /// <summary>
    /// A register name is looked up in the target's table, so another
    /// architecture's name is unknown and the message says which one was being
    /// built for.
    /// </summary>
    [Theory]
    [InlineData("X64Windows", "x0", "x64")]
    [InlineData("X64Windows", "ah", "x64")]
    [InlineData("X86Windows", "rax", "x86")]
    [InlineData("X86Windows", "sil", "x86")]
    [InlineData("X86Windows", "xmm8", "x86")]
    [InlineData("Arm64Linux", "rax", "arm64")]
    [InlineData("Arm64Linux", "x31", "arm64")]
    public void AnUnknownRegisterNamesTheArchitecture(string target, string register, string architecture)
    {
        var platform = (TargetPlatform)typeof(TargetPlatform).GetField(target)!.GetValue(null)!;

        Under(platform, () =>
        {
            Front.BindBody($"long r = 0; asm (out {register} = r) {{ nop }}", out var diagnostics);
            var diagnostic = Front.Only(diagnostics);

            Assert.Equal("SLI0041", diagnostic.Code);
            Assert.Contains($"on {architecture}", diagnostic.Message);
        });
    }

    [Theory]
    [InlineData("X64Windows", "rsp")]
    [InlineData("X64Windows", "spl")]
    [InlineData("X64Windows", "rbp")]
    [InlineData("X64Windows", "ebp")]
    [InlineData("X86Windows", "esp")]
    [InlineData("X86Linux", "ebp")]
    [InlineData("Arm64Linux", "sp")]
    [InlineData("Arm64Linux", "x29")]
    [InlineData("Arm64Linux", "fp")]
    [InlineData("Arm64Windows", "x18")]
    [InlineData("Arm64Windows", "w18")]
    [InlineData("Arm64MacOS", "x18")]
    [InlineData("Arm64MacOS", "w18")]
    public void AStackFrameOrReservedRegisterIsNotAnOperand(string target, string register)
    {
        var platform = (TargetPlatform)typeof(TargetPlatform).GetField(target)!.GetValue(null)!;

        Under(platform, () =>
            Assert.Equal(["SLI0042"],
                         Front.BodyCodes($"long r = 0; asm (in {register} = r) {{ nop }}")));
    }

    /// <summary>
    /// Two names for one register are one register, and a register holds one
    /// value going in and one coming out: two of either, or <c>inout</c> beside
    /// anything, is named twice.
    /// </summary>
    [Theory]
    [InlineData("in al = a, in RAX = b")]
    [InlineData("out rax = a, out eax = b")]
    [InlineData("inout rcx = a, out cx = b")]
    [InlineData("in rcx = a, inout ecx = b")]
    [InlineData("in rdx = a, out rdx = b, in dl = a")]
    public void ARegisterNamedTwiceIsReported(string operands) =>
        Under(TargetPlatform.X64Linux, () =>
        {
            Front.BindBody($"byte a = 0; byte b = 0; asm ({operands}) {{ nop }}", out var diagnostics);
            Assert.Equal("SLI0043", Front.Only(diagnostics).Code);
        });

    /// <summary>
    /// One <c>in</c> and one <c>out</c> on a register is <c>inout</c> with its
    /// two places different, whichever is written first and whatever names
    /// they use.
    /// </summary>
    [Theory]
    [InlineData("in rax = a, out rax = b")]
    [InlineData("out eax = b, in rax = a")]
    [InlineData("in al = a, out AL = b")]
    public void OneInAndOneOutMayShareARegister(string operands) =>
        Under(TargetPlatform.X64Linux, () =>
            Assert.Empty(Front.BodyCodes($"byte a = 0; byte b = 0; asm ({operands}) {{ nop }}")));

    [Theory]
    [InlineData("String s = \"x\"; asm (in rcx = s) { nop }")]
    [InlineData("var a = new int[1]; asm (in rcx = a) { nop }")]
    [InlineData("Pair p; asm (in rcx = p) { nop }")]
    [InlineData("Holder? o = null; asm (in rcx = o) { nop }")]
    public void ACountedOrCompoundValueCannotTravelInARegister(string body) =>
        Under(TargetPlatform.X64Windows, () =>
        {
            Front.BindModule("public struct Pair { public int A; public int B; }\n" +
                             "public class Holder { }\n" +
                             "void F()\n{\n" + body + "\n}", out var diagnostics);
            Assert.Equal(["SLI0044"], Front.Codes(diagnostics));
        });

    [Theory]
    [InlineData("long v = 0; asm (in eax = v) { nop }")]
    [InlineData("int v = 0; asm (out ax = v) { nop }")]
    [InlineData("asm (in al = 256) { nop }")]
    [InlineData("int* p = null; asm (in ecx = p) { nop }")]
    public void AValueWiderThanItsRegisterIsReported(string body) =>
        Under(TargetPlatform.X64Windows, () => Assert.Equal(["SLI0045"], Front.BodyCodes(body)));

    [Theory]
    [InlineData("double d = 0.0; asm (in s0 = d) { nop }")]
    [InlineData("asm (in s0 = 1.5) { nop }")]
    [InlineData("long v = 0; asm (in w0 = v) { nop }")]
    public void AValueWiderThanAnArm64RegisterIsReported(string body) =>
        Under(TargetPlatform.Arm64Linux, () => Assert.Equal(["SLI0045"], Front.BodyCodes(body)));

    [Theory]
    [InlineData("double d = 0.0; asm (in rax = d) { nop }")]
    [InlineData("float f = 0.0f; asm (out rax = f) { nop }")]
    [InlineData("long v = 0; asm (in xmm0 = v) { nop }")]
    [InlineData("bool b = false; asm (out xmm3 = b) { nop }")]
    public void AValueInTheWrongKindOfRegisterIsReported(string body) =>
        Under(TargetPlatform.X64Windows, () => Assert.Equal(["SLI0046"], Front.BodyCodes(body)));

    /// <summary>
    /// An output needs a place with an address: the checks an assignment makes,
    /// and a bit-field refused because it has none.
    /// </summary>
    [Theory]
    [InlineData("asm (out rax = 5) { nop }", "SLT0008")]
    [InlineData("const long c = 1; asm (inout rax = c) { nop }", "SLT0008")]
    [InlineData("Bits b; asm (out eax = b.Flag) { nop }", "SLI0047")]
    public void AnAsmOutputNeedsAPlaceWithAnAddress(string body, string code) =>
        Under(TargetPlatform.X64Windows, () =>
        {
            Front.BindModule("public struct Bits { public uint Flag : 3; }\n" +
                             "void F()\n{\n" + body + "\n}", out var diagnostics);
            Assert.Equal([code], Front.Codes(diagnostics));
        });

    [Fact]
    public void AnInParameterIsNotAnAsmOutput() =>
        Under(TargetPlatform.X64Windows, () =>
            Assert.Equal(["SLT0046"], Front.ModuleCodes(
                "void F(in long v)\n{\n    asm (out rax = v) { nop }\n}")));

    /// <summary>
    /// An <c>out</c> parameter written only by a block is written: nothing in
    /// the language leaves a block except by running off its end.
    /// </summary>
    [Fact]
    public void AnAsmOutputWritesAnOutParameter() =>
        Under(TargetPlatform.X64Windows, () =>
            Assert.Empty(Front.ModuleCodes(
                "void F(out long low, out int high)\n{\n" +
                "    asm (out rax = low, out edx = high) { rdtsc }\n}")));

    /// <summary>
    /// And a block whose operand was refused is taken to have written
    /// everything, so the one mistake is not reported twice.
    /// </summary>
    [Fact]
    public void ARefusedAsmOutputIsNotAlsoAnUnwrittenOut() =>
        Under(TargetPlatform.X64Windows, () =>
            Assert.Equal(["SLI0041"], Front.ModuleCodes(
                "void F(out long low)\n{\n    asm (out x0 = low) { nop }\n}")));

    /// <summary>
    /// An output to a variable outside a <c>for parallel</c> body is the same
    /// race an assignment to it is, and is refused the same way.
    /// </summary>
    [Fact]
    public void AnAsmOutputOutsideAParallelLoopIsARace() =>
        Under(TargetPlatform.X64Windows, () =>
            Assert.Equal(["SLO0012"], Front.BodyCodes(
                "long total = 0;\nfor parallel (int i = 0; i < 4; i++)\n" +
                "{\n    asm (inout rax = total) { add rax, 1 }\n}")));

    /// <summary>
    /// Every operand's register joins the clobbers after the volatile set, once,
    /// by the name of the whole register; the flags come last.
    /// </summary>
    [Fact]
    public void ClobbersAreTheVolatileSetThenTheOperandsThenTheFlags()
    {
        var target = TargetPlatform.X64Windows;
        var clobbers = AsmRegisters.Clobbers(target,
        [
            AsmRegisters.Find(target, "ebx")!,
            AsmRegisters.Find(target, "rax")!,
            AsmRegisters.Find(target, "bl")!,
        ]);

        Assert.Equal(
            ["rax", "rcx", "rdx", "r8", "r9", "r10", "r11",
             "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5",
             "rbx", "dirflag", "fpsr", "flags"],
            clobbers);
    }

    // --------------------------------------------------------- reachability

    /// <summary>
    /// A function whose end nothing reaches needs no return there, however
    /// the loop or the jumps in front of it are written.
    /// </summary>
    [Theory]
    [InlineData("int F() { do { return 1; } while (true); }")]
    [InlineData("int F(bool b) { do { if (b) return 1; } while (true); }")]
    [InlineData("int F() { while (true) { } }")]
    [InlineData("int F() { for (;;) { } }")]
    [InlineData("int F(int n) { again: n++; if (n < 3) goto again; return n; }")]
    [InlineData("int F(int n) { top: n++; goto top; }")]
    [InlineData("int F(int n) { while (true) { if (n > 3) goto done; n++; } done: return n; }")]
    [InlineData("int F(int n) { switch (n) { case 1: goto case 2; case 2: return 2; default: goto case 1; } }")]
    [InlineData("int F(int n) { { again: n++; if (n < 3) goto again; } return n; }")]
    public void AnEndNothingReachesNeedsNoReturn(string module) =>
        Assert.Empty(Front.ModuleCodes(module));

    [Theory]
    [InlineData("int F(bool b) { do { if (b) break; return 1; } while (true); }")]
    [InlineData("int F(bool b) { do { if (b) continue; return 1; } while (b); }")]
    [InlineData("int F(int n) { while (true) { if (n > 3) goto done; n++; } done: n++; }")]
    [InlineData("int F(int n) { for (;;) { break; } }")]
    [InlineData("int F(int n) { if (n > 0) goto done; return 1; done: n++; }")]
    public void AnEndSomethingReachesNeedsAReturn(string module) =>
        Assert.Equal(["SLF0001"], Front.ModuleCodes(module));

    /// <summary>A section that ends in a jump does not fall through.</summary>
    [Theory]
    [InlineData("void F(int n) { switch (n) { case 1: n++; goto case 2; case 2: break; } }")]
    [InlineData("void F(int n) { switch (n) { case 1: goto default; default: break; } }")]
    [InlineData("void F(int n) { switch (n) { case 1: goto done; default: break; } done: n++; }")]
    [InlineData("void F(int n) { switch (n) { case 1: while (true) { } } }")]
    public void ASectionEndingInAJumpDoesNotFallThrough(string module) =>
        Assert.Empty(Front.ModuleCodes(module));

    /// <summary>
    /// A jump may leave blocks but not enter one, and the error says which
    /// rather than that there is no such label.
    /// </summary>
    [Theory]
    [InlineData("void F(bool b) { if (b) { inner: return; } goto inner; }")]
    [InlineData("void F() { { goto other; } { other: return; } }")]
    [InlineData("void F(int n) { goto inside; switch (n) { case 1: inside: break; } }")]
    public void AJumpIntoABlockIsRefusedAsOne(string module) =>
        Assert.Equal(["SLF0029"], Front.ModuleCodes(module));

    [Theory]
    [InlineData("void F() { goto case 1; }", "SLF0045")]
    [InlineData("void F() { goto default; }", "SLF0045")]
    [InlineData("void F(int n) { switch (n) { case 1: goto case 2; } }", "SLF0046")]
    [InlineData("void F(int n) { switch (n) { case 1: goto default; } }", "SLF0046")]
    [InlineData("void F(int n) { switch (n) { case 1: goto case n; } }", "SLF0049")]
    [InlineData("void F(int n) { switch (n) { case 1: Func<int, int> f = x => { goto case 1; }; break; } }", "SLF0045")]
    public void GotoCaseNamesASectionOfTheSwitchItIsIn(string module, string code) =>
        Assert.Equal([code], Front.ModuleCodes(module));

    /// <summary>A label in a lambda belongs to the lambda, so each may use the same name.</summary>
    [Fact]
    public void ALambdaHasLabelsOfItsOwn() =>
        Assert.Empty(Front.ModuleCodes("""
            int F(int n)
            {
                Func<int, int> f = x => { again: x++; if (x < 3) goto again; return x; };
            again:
                n++;
                if (n < 3) goto again;
                return f(n);
            }
            """));

    /// <summary>
    /// Too deep is reported by the bind that counts. A trial bind before it
    /// reports into a muted bag, and the bind after it MUST still say why the
    /// expression is an error.
    /// </summary>
    [Fact]
    public void NestingTooDeepIsReportedAfterATrialBind()
    {
        string chain = string.Concat(Enumerable.Repeat(".Changed", 600));
        string[] codes = Source.Recursion.OnADeepStack(() => Front.ModuleCodes(
            "public closure void Handler(int x);\n" +
            "public class Source { public event Handler Changed; }\n" +
            "void On(int x) { }\n" +
            "void F(Source s) { s" + chain + " += On; }"));
        Assert.Contains("SLP0016", codes);
    }

    /// <summary>
    /// A value with no type of its own, standing as a statement, is dropped
    /// with a warning: what it was built from is evaluated, and it is not.
    /// </summary>
    [Theory]
    [InlineData("Fail(1);")]
    [InlineData("(int x) => x;")]
    [InlineData("Main;")]
    [InlineData("[1, 2];")]
    [InlineData("null;")]
    public void AnUnsettledValueAsAStatementIsDropped(string statement)
    {
        var program = Front.BindBody(statement, out var diagnostics);
        Assert.Equal(["SLL0001"], Front.Codes(diagnostics));
        Front.Verified(new Stainless.Emit.LlvmEmitter(forSharedLibrary: true).Emit(Stainless.Lowering.Lowerer.Lower(program)));
    }

    /// <summary>
    /// A `try` standing as a statement returns on a failure, which is an
    /// effect whatever the value it drops.
    /// </summary>
    [Fact]
    public void ATryAsAStatementHasAnEffect() =>
        Assert.DoesNotContain("SLL0001", Front.ModuleCodes(
            "Result<int, int> Step() => Ok(1);\n" +
            "Result<bool, int> Run() { try Step(); return Ok(true); }"));

    /// <summary>The body of a lambda whose target returns nothing drops an unsettled value the same way.</summary>
    [Theory]
    [InlineData("() => (int x) => x")]
    [InlineData("() => [1, 2]")]
    public void AnUnsettledLambdaBodyIsDropped(string lambda) =>
        Assert.Contains("define", Front.ModuleIr(
            "public closure void Act();\nvoid F() { Act act = " + lambda + "; act(); }"));

    /// <summary>A label's name is the program's, and a block name MUST be one LLVM reads.</summary>
    [Fact]
    public void ALabelNamedOutsideAsciiIsABlockLlvmReads() =>
        Assert.Contains("label.caf_u00E9", Front.ModuleIr(
            "void F(int n) { café: n++; if (n < 3) goto café; }"));

    [Fact]
    public void AnyPointerConvertsToVoidAndBytePointersAndNoOtherWithoutACast()
    {
        Assert.Empty(Front.ModuleCodes("public void Take(void* p) { }\npublic void Use(int* x) => Take(x);"));
        Assert.Empty(Front.ModuleCodes("public void Take(byte* p) { }\npublic void Use(int* x) => Take(x);"));
        Assert.NotEmpty(Front.ModuleCodes("public void Take(long* p) { }\npublic void Use(int* x) => Take(x);"));
        Assert.Empty(Front.ModuleCodes("public void Take(long* p) { }\npublic void Use(int* x) => Take((long*)x);"));
    }
}
