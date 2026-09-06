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

using System.Linq;
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// <c>static</c> on a method: a member of the type rather than of a value.
///
/// The end-to-end case proves the calls come out right. These are the rules
/// around them -- most of which are refusals, and so produce no output to
/// compare -- plus the two facts about the emitted code that make a static
/// method genuinely receiverless rather than one with an ignored receiver.
/// </summary>
public class StaticMethodTests
{
    private const string Box = """
        public class Box {
            int value;
            public Box() { value = 1; }
            public int Read() { return value; }
            public static Box Make() { return new Box(); }
            public static int Twice(Box of) { return of.Read() * 2; }
        }
        """;

    private static string[] With(string body) =>
        Front.ModuleCodes(Box + "\nint Main() {\n" + body + "\n    return 0;\n}");

    // ------------------------------------------------------------- accepted

    [Theory]
    [InlineData("var b = Box.Make();")]
    [InlineData("var b = Box.Make(); int n = Box.Twice(b);")]
    [InlineData("int n = Box.Twice(Box.Make());")]
    [InlineData("var b = Box.Make(); int n = b.Read();")]
    public void AStaticMethodIsCalledOnItsType(string body) => Assert.Empty(With(body));

    /// <summary>
    /// A struct has no constructors at all, so this is the only way to build
    /// one in a single expression.
    /// </summary>
    [Fact]
    public void AStructMayHaveOne() => Assert.Empty(Front.ModuleCodes("""
        public struct Point {
            public int X;
            public static Point At(int x) { Point p; p.X = x; return p; }
        }
        int Main() { return Point.At(3).X; }
        """));

    /// <summary>
    /// The point of the whole thing: a factory inside the type can use a
    /// constructor nothing outside it can, which is what makes the failing
    /// path closed off rather than merely discouraged.
    /// </summary>
    [Fact]
    public void ItReachesAPrivateConstructor() => Assert.Empty(Front.ModuleCodes("""
        public class Small {
            int value;
            Small(int v) { value = v; }
            public static Small Of(int v) { return new Small(v); }
        }
        int Main() { var s = Small.Of(1); return 0; }
        """));

    /// <summary>
    /// Static and instance members share one name space, so a name may be
    /// both -- as long as the parameters differ, which is the ordinary
    /// overloading rule.
    /// </summary>
    [Fact]
    public void ItOverloadsAnInstanceMethod() => Assert.Empty(Front.ModuleCodes("""
        public struct Span {
            public int Start;
            public int Length() { return Start; }
            public static int Length(Span of) { return of.Start; }
        }
        int Main() { Span s; s.Start = 1; return s.Length() + Span.Length(s); }
        """));

    /// <summary>An overload differing only by `static` is still a collision.</summary>
    [Fact]
    public void ItDoesNotOverloadOnStaticAlone() => Assert.Contains("SL0211",
        Front.ModuleCodes("""
            public class C {
                public int Read() { return 1; }
                public static int Read() { return 2; }
            }
            int Main() { return 0; }
            """));

    // ------------------------------------------------------------- refusals

    /// <summary>There is no receiver, so there is nothing for `this` to name.</summary>
    [Fact]
    public void ThisIsRefused() => Assert.Contains("SL0228", Front.ModuleCodes("""
        public class C { int v; public C() { v = 1; } public static int Get() { return this.v; } }
        int Main() { return 0; }
        """));

    /// <summary>And nothing for an unqualified field or method to be read through.</summary>
    [Theory]
    [InlineData("return v;")]
    [InlineData("return Read();")]
    public void AnInstanceMemberIsRefused(string body) => Assert.Contains("SL0576",
        Front.ModuleCodes("""
            public class C {
                int v;
                public C() { v = 1; }
                public int Read() { return v; }
                public static int Get() { BODY }
            }
            int Main() { return 0; }
            """.Replace("BODY", body)));

    /// <summary>
    /// Reached the wrong way round, in both directions. Each says which way is
    /// right, because the fix is a spelling and the reader may not know it.
    /// </summary>
    [Theory]
    [InlineData("var b = Box.Make(); var c = b.Make();")]
    [InlineData("int n = Box.Read();")]
    public void TheWrongReceiverIsRefused(string body) =>
        Assert.Contains("SL0576", With(body));

    /// <summary>
    /// Dispatch chooses a body from the object a call arrives on. A static
    /// method has no object, so every word about dispatch contradicts it.
    /// </summary>
    [Theory]
    [InlineData("virtual")]
    [InlineData("abstract")]
    [InlineData("override")]
    public void ADispatchWordIsRefused(string word) => Assert.Contains("SL0575",
        Front.ModuleCodes(
            "public class C { public " + word + " static int Get() { return 1; } }\n" +
            "int Main() { return 0; }"));

    /// <summary>`protected` is about what a derived object reaches through itself.</summary>
    [Fact]
    public void ProtectedIsRefused() => Assert.Contains("SL0575", Front.ModuleCodes("""
        public class C { protected static int Get() { return 1; } }
        int Main() { return 0; }
        """));

    /// <summary>An interface promises what an object can do.</summary>
    [Fact]
    public void AnInterfaceMemberIsRefused() => Assert.Contains("SL0574", Front.ModuleCodes("""
        public interface I { static int Get(); }
        int Main() { return 0; }
        """));

    /// <summary>
    /// And so a static method cannot be what satisfies an interface, even
    /// when the signature would otherwise line up.
    /// </summary>
    [Fact]
    public void ItDoesNotImplementAnInterface() => Assert.NotEmpty(Front.ModuleCodes("""
        public interface I { int Get(); }
        public class C : I { public static int Get() { return 1; } }
        int Main() { return 0; }
        """));

    /// <summary>At module scope the word says nothing that was not already true.</summary>
    [Fact]
    public void AModuleLevelFunctionIsRefused() =>
        Assert.Contains("SL0573", Front.ModuleCodes("static int Free() { return 1; }\nint Main() { return 0; }"));

    /// <summary>A module is what this language has instead of a static class.</summary>
    [Theory]
    [InlineData("public static class C { }")]
    [InlineData("public static struct S { }")]
    [InlineData("public static interface I { }")]
    [InlineData("public static enum E { A }")]
    public void AStaticTypeIsRefused(string declaration) =>
        Assert.Contains("SL0578", Front.ModuleCodes(declaration + "\nint Main() { return 0; }"));

    /// <summary>Storage still has to be readonly; nothing would synchronize it.</summary>
    [Fact]
    public void MutableStorageIsStillRefused() =>
        Assert.Contains("SL0376", Front.ModuleCodes("static int Count = 0;\nint Main() { return 0; }"));

    /// <summary>
    /// And storage inside a type is refused outright rather than silently
    /// dropped, which is what happened before a static member could be
    /// anything else.
    /// </summary>
    [Fact]
    public void StorageInATypeIsRefused() => Assert.Contains("SL0577", Front.ModuleCodes("""
        public class C { static readonly int Shared = 3; }
        int Main() { return 0; }
        """));

    // ---------------------------------------------------------------- order

    /// <summary>
    /// The modifiers may be written in any order, as C#'s may. `static` became
    /// an ordinary modifier for this: it used to be a token the declaration
    /// parser looked for in one place.
    /// </summary>
    [Theory]
    [InlineData("public static int Get() { return 1; }")]
    [InlineData("static public int Get() { return 1; }")]
    public void TheOrderOfTheWordsDoesNotMatter(string declaration) =>
        Assert.Empty(Front.ModuleCodes(
            "public class C { " + declaration + " }\nint Main() { return C.Get(); }"));

    // ------------------------------------------------------------ emission

    /// <summary>
    /// No receiver reaches the callee. A static method that took one and
    /// ignored it would read the first argument as an object.
    /// </summary>
    [Fact]
    public void ItTakesNoReceiver()
    {
        string ir = Front.ModuleIr("""
            public class C {
                public C() { }
                public static int Twice(int n) { return n * 2; }
            }
            int Main() { return C.Twice(21); }
            """);

        Assert.Contains("i32 21)", Front.Function(ir, "Main"));
        Assert.DoesNotContain("ptr %this", Front.Function(ir, "Twice"));
    }

    /// <summary>
    /// A static and an instance method of one name mangle apart, because the
    /// receiver was never part of the name and the parameters differ.
    /// </summary>
    [Fact]
    public void TheTwoKindsMangleApart()
    {
        string ir = Front.ModuleIr("""
            public class C {
                int v;
                public C() { v = 1; }
                public int Read() { return v; }
                public static int Read(C of) { return of.Read(); }
            }
            int Main() { var c = new C(); return c.Read() + C.Read(c); }
            """);

        var defined = System.Text.RegularExpressions.Regex
            .Matches(ir, @"^define [^@]*@(\S+)\(", System.Text.RegularExpressions.RegexOptions.Multiline)
            .Select(m => m.Groups[1].Value)
            .Where(name => name.Contains("1C4Read"))
            .Distinct()
            .ToList();

        Assert.Equal(2, defined.Count);
    }
}
