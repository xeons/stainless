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

    // ------------------------------------------------------ where it points

    /// <summary>
    /// A type mismatch underlines the value, not the declaration: the
    /// declaration is what the programmer meant and the value is what went
    /// wrong.
    /// </summary>
    [Fact]
    public void AMismatchUnderlinesTheValue() =>
        Assert.Equal(("SL0265", "\"s\""), One("int x = \"s\";"));

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
        Assert.Equal(("SL0266", underlined), One(body));

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
        Assert.Equal(("SL0265", underlined), One(body));

    /// <summary>
    /// An argument that did not bind is reported once. It matches every
    /// overload and none, so overload resolution used to add "the call is
    /// ambiguous" on top -- a second message about the first one's
    /// consequence, printed above it.
    /// </summary>
    [Fact]
    public void AnArgumentThatDidNotBindDoesNotAlsoReportAmbiguity() =>
        Assert.Equal(
            ["SL0247"],
            Front.ModuleCodes("""
                String Pick(long n) { return "l"; }
                String Pick(nuint n) { return "n"; }
                String Use(String s) { return Pick(s.Nonexistent); }
                """));

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

    /// <summary>
    /// A redeclared name underlines the second one. Not a type: a type may now
    /// be declared more than once inside its own module, and the second
    /// declaration adds to the first rather than colliding with it.
    /// </summary>
    [Fact]
    public void ADuplicateNameUnderlinesTheSecond() =>
        Assert.Equal(("SL0201", "public const int X = 2;"),
                     OneInModule("public const int X = 1;\npublic const int X = 2;"));

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
        Assert.Contains("SL0611", Front.ModuleCodes(
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
        Assert.Contains("SL0538", Front.ModuleCodes(
            "[Guid(\"5a1c8e30-2b47-4d16-a9f3-c04e7b81d629\")] class C { }"));

    /// <summary>
    /// A <c>[NoUnknown]</c> vtable has no QueryInterface and no IID, so every
    /// spelling of the question is refused where it is written, from either
    /// side. It used to reach the emitter, which wrote a call against an IID
    /// nothing defined, and the build ended in "this is a compiler bug".
    /// </summary>
    [Theory]
    [InlineData("bool r = a is IB;", "SL0518")]
    [InlineData("bool r = c is IA;", "SL0518")]
    [InlineData("bool r = a is IC;", "SL0518")]
    [InlineData("int r = a switch { IB => 1, _ => 0 };", "SL0619")]
    [InlineData("int r = c switch { IA => 1, _ => 0 };", "SL0619")]
    [InlineData("var r = (IB)a;", "SL0243")]
    [InlineData("var r = a as IB;", "SL0612")]
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

    // ------------------------------------------- declaring a type more than once

    /// <summary>
    /// A type may be declared again inside its own module, and the second
    /// declaration adds to the first.
    /// </summary>
    [Fact]
    public void ASecondDeclarationAddsMembers()
    {
        var program = Front.BindModule(
            """
            public class Shape { public int Sides; }
            public class Shape { public int Corners() { return Sides; } }
            public int Use() { var s = new Shape(); return s.Corners(); }
            """, out var diagnostics);

        Assert.Empty(Front.Codes(diagnostics));
        Assert.Single(program.Classes, c => c.Name == "Shape");
    }

    /// <summary>
    /// Which is what lets the standard library write the rest of `String` in
    /// Stainless: the compiler creates the symbol, and `stdlib/Text.sl`
    /// declares it a second time.
    /// </summary>
    [Fact]
    public void StringHasMembersFromBothItsDeclarations()
    {
        // ByteLength is intrinsic; Trim is written in Stainless.
        Assert.Empty(Front.BodyCodes("var n = \"  x \".Trim().ByteLength();"));
    }

    /// <summary>
    /// A field in a later declaration would move a layout that has already been
    /// settled -- and for an intrinsic, settled by the runtime.
    /// </summary>
    [Fact]
    public void ASecondDeclarationMayNotAddAField() =>
        Assert.Equal(["SL0552"], Front.ModuleCodes(
            "public class C { public int A; }" +
            "\npublic class C { public int B; }"));

    /// <summary>
    /// Nor a base list: pass 5 builds the dispatch tables from the first
    /// declaration, so one arriving later would arrive after they were built.
    /// </summary>
    [Fact]
    public void ASecondDeclarationMayNotNameABase() =>
        Assert.Equal(["SL0551"], Front.ModuleCodes(
            """
            public interface I { void F(); }
            public class C { public void F() { } }
            public class C : I { }
            """));

    /// <summary>And every declaration must agree about what it is.</summary>
    [Fact]
    public void EveryDeclarationMustAgreeAboutTheKind() =>
        Assert.Equal(["SL0550"], Front.ModuleCodes(
            "public class C { }\npublic struct C { }"));

    /// <summary>
    /// Every kind of type a name can be declared as, with <c>$</c> for the
    /// name, and what a second declaration of the same kind may add to it.
    /// </summary>
    private static readonly (string Kind, string Source)[] s_declarationKinds =
    [
        ("class", "class $ { int A; }"),
        ("struct", "struct $ { int A; }"),
        ("opaque", "struct $;"),
        ("union", "union $ { int A; float B; }"),
        ("variant", "variant $ { One; Two(int A); }"),
        ("interface", "interface $ { int F(); }"),
        ("com", "[Guid(\"9d2f5f7a-1c64-4a3b-8f0e-7d5a2c9b4e10\")] com interface $ { int F(); }"),
        ("attribute", "attribute $ { int A; }"),
        ("enum", "enum $ { A, B }"),
        ("delegate", "delegate int $(int x, int y);"),
        ("closure", "closure int $(int x);"),
        ("alias", "using $ = int;"),
        ("generic class", "class $<T> { T A; }"),
        ("generic variant", "variant $<T> { Leaf(T Item); }"),
        ("generic closure", "closure T $<T>(T x);"),
    ];

    public static TheoryData<string, string> DeclarationKindPairs()
    {
        var data = new TheoryData<string, string>();
        foreach (var first in s_declarationKinds)
            foreach (var second in s_declarationKinds)
                data.Add(first.Kind, second.Kind);
        return data;
    }

    /// <summary>
    /// Two declarations of one name, of every pair of kinds, in one file and in
    /// two: one of them loses, is reported, and nothing after pass 2 goes
    /// looking for a symbol it never made.
    ///
    /// Each later pass used to find a declaration's type by its name, which is
    /// the winner's -- so a delegate losing to a struct was cast to a delegate,
    /// and an enum losing to a generic variant was looked up where only the
    /// template was. Tried in both files because pass 2 takes a file's classes
    /// before its delegates and its delegates before its enums, and the order
    /// two declarations meet in is what decided which one crashed.
    /// </summary>
    [Theory]
    [MemberData(nameof(DeclarationKindPairs))]
    public void TwoTypesOfOneNameAreADuplicateWhateverTheirKinds(string first, string second)
    {
        string firstSource = s_declarationKinds.Single(k => k.Kind == first).Source.Replace("$", "N");
        string secondSource = s_declarationKinds.Single(k => k.Kind == second).Source.Replace("$", "N");

        // The one pairing that is not a duplicate: a type declared twice in its
        // own module, which is a later part adding behaviour to the first.
        string[] parts = ["class", "struct", "union", "variant", "interface", "com", "attribute"];
        bool addsToTheFirst = first == second && parts.Contains(first);

        string[] reported = ["SL0201", "SL0550", "SL0551", "SL0552"];

        foreach (var codes in new[]
                 {
                     Front.ModuleCodes(firstSource + "\n" + secondSource),
                     Front.FilesCodes(firstSource, secondSource),
                 })
        {
            if (!addsToTheFirst)
                Assert.Contains(codes, reported.Contains);
        }
    }

    /// <summary>
    /// A generic is a template rather than a type, and two of them are still
    /// the ordinary duplicate.
    /// </summary>
    [Fact]
    public void TwoGenericTemplatesAreStillADuplicate() =>
        Assert.Equal(["SL0201"], Front.ModuleCodes(
            "public class Box<T> { T v; }" +
            "\npublic class Box<T> { T w; }"));

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

        Assert.Contains("SL0276", codes);
        Assert.Contains("SL0499", codes);
    }

    /// <summary>
    /// The same for each other way an override can fail: each is reported
    /// once, at the class that wrote it, and the class below is not also
    /// blamed for overriding something that is still a dispatched method.
    /// </summary>
    [Theory]
    [InlineData("public String Speak() => \"?\";", "SL0500")]
    [InlineData("public virtual int Speak() => 0;", "SL0502")]
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
        Assert.Contains("SL0260", Front.Codes(diagnostics));
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

        Assert.Contains("SL0573", codes);
        Assert.Contains("SL0229", codes);
    }

    /// <summary>
    /// A struct that contains itself, by every route to it, with something
    /// that walks its fields after layout.
    ///
    /// SL0216 was reported and the cycle left in place, so the first of those
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
        Assert.Contains("SL0216", Front.ModuleCodes(WalkedEveryWay(declaration)));

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

            Assert.Equal("SL0716", diagnostic.Code);
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
    public void AStackFrameOrReservedRegisterIsNotAnOperand(string target, string register)
    {
        var platform = (TargetPlatform)typeof(TargetPlatform).GetField(target)!.GetValue(null)!;

        Under(platform, () =>
            Assert.Equal(["SL0717"],
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
            Assert.Equal("SL0718", Front.Only(diagnostics).Code);
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
            Assert.Equal(["SL0719"], Front.Codes(diagnostics));
        });

    [Theory]
    [InlineData("long v = 0; asm (in eax = v) { nop }")]
    [InlineData("int v = 0; asm (out ax = v) { nop }")]
    [InlineData("asm (in al = 256) { nop }")]
    [InlineData("int* p = null; asm (in ecx = p) { nop }")]
    public void AValueWiderThanItsRegisterIsReported(string body) =>
        Under(TargetPlatform.X64Windows, () => Assert.Equal(["SL0720"], Front.BodyCodes(body)));

    [Theory]
    [InlineData("double d = 0.0; asm (in s0 = d) { nop }")]
    [InlineData("asm (in s0 = 1.5) { nop }")]
    [InlineData("long v = 0; asm (in w0 = v) { nop }")]
    public void AValueWiderThanAnArm64RegisterIsReported(string body) =>
        Under(TargetPlatform.Arm64Linux, () => Assert.Equal(["SL0720"], Front.BodyCodes(body)));

    [Theory]
    [InlineData("double d = 0.0; asm (in rax = d) { nop }")]
    [InlineData("float f = 0.0f; asm (out rax = f) { nop }")]
    [InlineData("long v = 0; asm (in xmm0 = v) { nop }")]
    [InlineData("bool b = false; asm (out xmm3 = b) { nop }")]
    public void AValueInTheWrongKindOfRegisterIsReported(string body) =>
        Under(TargetPlatform.X64Windows, () => Assert.Equal(["SL0721"], Front.BodyCodes(body)));

    /// <summary>
    /// An output needs a place with an address: the checks an assignment makes,
    /// and a bit-field refused because it has none.
    /// </summary>
    [Theory]
    [InlineData("asm (out rax = 5) { nop }", "SL0240")]
    [InlineData("const long c = 1; asm (inout rax = c) { nop }", "SL0240")]
    [InlineData("Bits b; asm (out eax = b.Flag) { nop }", "SL0722")]
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
            Assert.Equal(["SL0448"], Front.ModuleCodes(
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
            Assert.Equal(["SL0716"], Front.ModuleCodes(
                "void F(out long low)\n{\n    asm (out x0 = low) { nop }\n}")));

    /// <summary>
    /// An output to a variable outside a <c>for parallel</c> body is the same
    /// race an assignment to it is, and is refused the same way.
    /// </summary>
    [Fact]
    public void AnAsmOutputOutsideAParallelLoopIsARace() =>
        Under(TargetPlatform.X64Windows, () =>
            Assert.Equal(["SL0373"], Front.BodyCodes(
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
}
