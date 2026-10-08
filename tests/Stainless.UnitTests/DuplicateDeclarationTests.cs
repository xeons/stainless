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

using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// Declaring a type more than once: what a second declaration may add, and
/// what two declarations of one name are when they may not both stand.
///
/// A class of its own rather than part of <see cref="BinderTests"/>, because
/// the runner takes one class at a time on a thread and the every-pair theory
/// here is half of what that class would hold. The theory itself is spread
/// over <see cref="KindPairShards"/> classes for the same reason.
/// </summary>
public class DuplicateDeclarationTests
{
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
    /// A class takes fields from any declaration, which is what lets a form
    /// designer's generated half hold the controls.
    /// </summary>
    [Fact]
    public void ASecondDeclarationOfAClassMayAddAField() =>
        Assert.Empty(Front.ModuleCodes(
            "public class C { public int A; }" +
            "\npublic class C { public int B; }"));

    /// <summary>A struct does not: its layout is C's.</summary>
    [Fact]
    public void ASecondDeclarationOfAStructMayNotAddAField() =>
        Assert.Equal(["SLC0063"], Front.ModuleCodes(
            "public struct S { public int A; }" +
            "\npublic struct S { public int B; }"));

    /// <summary>A class takes its base list from whichever declaration has one.</summary>
    [Fact]
    public void ASecondDeclarationOfAClassMayNameABase() =>
        Assert.Empty(Front.ModuleCodes(
            """
            public interface I { void F(); }
            public class C { public void F() { } }
            public class C : I { }
            public void Use() { I i = new C(); i.F(); }
            """));

    /// <summary>But from one of them: two would be two answers to one question.</summary>
    [Fact]
    public void TwoDeclarationsMayNotBothNameABase() =>
        Assert.Equal(["SLC0063"], Front.ModuleCodes(
            """
            public interface I { void F(); }
            public interface J { void G(); }
            public class C : I { public void F() { } }
            public class C : J { public void G() { } }
            """));

    /// <summary>And every declaration must agree about what it is.</summary>
    [Fact]
    public void EveryDeclarationMustAgreeAboutTheKind() =>
        Assert.Equal(["SLC0062"], Front.ModuleCodes(
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

    public const int KindPairShards = 3;

    /// <summary>Every pair of kinds: every <paramref name="of"/>th one from <paramref name="shard"/>.</summary>
    public static TheoryData<string, string> DeclarationKindPairs(int shard, int of)
    {
        var data = new TheoryData<string, string>();
        int index = 0;
        foreach (var first in s_declarationKinds)
            foreach (var second in s_declarationKinds)
            {
                if (index++ % of == shard)
                    data.Add(first.Kind, second.Kind);
            }
        return data;
    }

    /// <summary>Every shard together is every pair.</summary>
    [Fact]
    public void TheShardsCoverEveryPair()
    {
        int total = 0;
        for (int shard = 0; shard < KindPairShards; shard++)
            total += DeclarationKindPairs(shard, KindPairShards).Count;
        Assert.Equal(s_declarationKinds.Length * s_declarationKinds.Length, total);
    }

    /// <summary>
    /// Two declarations of one name and arity, of every pair of kinds, in one
    /// file and in two: one of them loses, is reported, and nothing after pass
    /// 2 goes looking for a symbol it never made.
    ///
    /// Each later pass used to find a declaration's type by its name, which is
    /// the winner's -- so a delegate losing to a struct was cast to a delegate,
    /// and an enum losing to a generic variant was looked up where only the
    /// template was. Tried in both files because pass 2 takes a file's classes
    /// before its delegates and its delegates before its enums, and the order
    /// two declarations meet in is what decided which one crashed.
    /// </summary>
    public static void CheckKindPair(string first, string second)
    {
        string firstSource = s_declarationKinds.Single(k => k.Kind == first).Source.Replace("$", "N");
        string secondSource = s_declarationKinds.Single(k => k.Kind == second).Source.Replace("$", "N");

        // Two pairings are not duplicates: a type declared twice in its own
        // module, which is a later part adding behaviour to the first, and a
        // generic beside a type of another arity, as `Action<T>` is beside
        // `Action`.
        string[] parts = ["class", "struct", "union", "variant", "interface", "com", "attribute"];
        bool addsToTheFirst = first == second && parts.Contains(first);
        bool anotherArity = first.StartsWith("generic") != second.StartsWith("generic");

        string[] reported = ["SLN0001", "SLC0062", "SLC0063", "SLC0090"];

        foreach (var codes in new[]
                 {
                     Front.ModuleCodes(firstSource + "\n" + secondSource),
                     Front.FilesCodes(firstSource, secondSource),
                 })
        {
            if (anotherArity)
                Assert.DoesNotContain(codes, reported.Contains);
            else if (!addsToTheFirst)
                Assert.Contains(codes, reported.Contains);
        }
    }

    /// <summary>
    /// A generic is a template rather than a type, and two of them are still
    /// the ordinary duplicate.
    /// </summary>
    [Fact]
    public void TwoGenericTemplatesAreStillADuplicate() =>
        Assert.Equal(["SLN0001"], Front.ModuleCodes(
            "public class Box<T> { T v; }" +
            "\npublic class Box<T> { T w; }"));
}

public class DuplicateKindPairsFirst
{
    [Theory]
    [MemberData(nameof(DuplicateDeclarationTests.DeclarationKindPairs), 0,
                DuplicateDeclarationTests.KindPairShards, MemberType = typeof(DuplicateDeclarationTests))]
    public void TwoTypesOfOneNameAreADuplicateWhateverTheirKinds(string first, string second) =>
        DuplicateDeclarationTests.CheckKindPair(first, second);
}

public class DuplicateKindPairsSecond
{
    [Theory]
    [MemberData(nameof(DuplicateDeclarationTests.DeclarationKindPairs), 1,
                DuplicateDeclarationTests.KindPairShards, MemberType = typeof(DuplicateDeclarationTests))]
    public void TwoTypesOfOneNameAreADuplicateWhateverTheirKinds(string first, string second) =>
        DuplicateDeclarationTests.CheckKindPair(first, second);
}

public class DuplicateKindPairsThird
{
    [Theory]
    [MemberData(nameof(DuplicateDeclarationTests.DeclarationKindPairs), 2,
                DuplicateDeclarationTests.KindPairShards, MemberType = typeof(DuplicateDeclarationTests))]
    public void TwoTypesOfOneNameAreADuplicateWhateverTheirKinds(string first, string second) =>
        DuplicateDeclarationTests.CheckKindPair(first, second);
}
