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

using Stainless.Emit;
using Stainless.Syntax;
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// <c>///</c> blocks: that the lexer collects them, that the parser puts each on
/// the declaration it was written above, and that the writer turns them into a
/// page.
///
/// Every one of these is invisible to an end-to-end case. A comment generates no
/// code, so a program that runs proves nothing at all about which declaration a
/// block landed on -- which is exactly the mistake to expect here.
/// </summary>
public class DocumentationTests
{
    // ------------------------------------------------------------- the lexer

    /// <summary>A block reaches the token below it and not the one after.</summary>
    [Fact]
    public void BlockAttachesToTheFollowingToken()
    {
        var tokens = Front.Tokens("/// what it is\npublic int x;");

        Assert.Equal("what it is", tokens[0].Documentation);
        Assert.Null(tokens[1].Documentation);
    }

    /// <summary>Consecutive lines are one block, joined in order.</summary>
    [Fact]
    public void ConsecutiveLinesJoin()
    {
        var tokens = Front.Tokens("/// one\n/// two\n/// three\nx");

        Assert.Equal("one\ntwo\nthree", tokens[0].Documentation);
    }

    /// <summary>
    /// A blank <c>///</c> is a blank line of the block, which is what makes a
    /// block more than one paragraph.
    /// </summary>
    [Fact]
    public void EmptyMarkerIsABlankLine()
    {
        var tokens = Front.Tokens("/// one\n///\n/// two\nx");

        Assert.Equal("one\n\ntwo", tokens[0].Documentation);
    }

    /// <summary>One space after the marker is the marker's; the rest is text.</summary>
    [Fact]
    public void OneLeadingSpaceIsStripped()
    {
        var tokens = Front.Tokens("///     var x = 1;\nx");

        Assert.Equal("    var x = 1;", tokens[0].Documentation);
    }

    /// <summary>An ordinary comment is not documentation.</summary>
    [Fact]
    public void TwoSlashesAreNotABlock()
    {
        var tokens = Front.Tokens("// just a note\nx");

        Assert.Null(tokens[0].Documentation);
    }

    /// <summary>
    /// Nor are four. A row of slashes is a rule somebody drew, and reading it
    /// as prose would put a line of punctuation in the middle of a description.
    /// </summary>
    [Fact]
    public void FourSlashesAreNotABlock()
    {
        var tokens = Front.Tokens("//// ------------\nx");

        Assert.Null(tokens[0].Documentation);
    }

    /// <summary>
    /// A plain comment between a block and its declaration separates the two,
    /// so the block documents nothing.
    ///
    /// This is the rule that decides where a note about the implementation is
    /// written: above the block, not between it and the declaration.
    /// </summary>
    [Fact]
    public void AnOrdinaryCommentBreaksTheRun()
    {
        var tokens = Front.Tokens("/// what it is\n// how it does it\nx");

        Assert.Null(tokens[0].Documentation);
    }

    /// <summary>A blank line breaks it too.</summary>
    [Fact]
    public void ABlankLineBreaksTheRun()
    {
        var tokens = Front.Tokens("/// about nothing\n\nx");

        Assert.Null(tokens[0].Documentation);
    }

    /// <summary>A single line break does not, since that is every block.</summary>
    [Fact]
    public void OneLineBreakDoesNotBreakTheRun()
    {
        var tokens = Front.Tokens("/// about x\nx");

        Assert.Equal("about x", tokens[0].Documentation);
    }

    // ------------------------------------------------------------ the parser

    /// <summary>A block above a function lands on that function.</summary>
    [Fact]
    public void FunctionCarriesItsBlock()
    {
        var unit = Front.Parse("module M;\n/// what it answers\npublic int F() { return 0; }");

        var function = Assert.IsType<FunctionDeclSyntax>(unit.Declarations[0]);
        Assert.Equal("what it answers", function.Documentation);
    }

    /// <summary>
    /// A block above an attribute belongs to the declaration the attribute is
    /// on, not to nothing. The attribute is part of the declaration, so the
    /// block is still contiguous with it.
    /// </summary>
    [Fact]
    public void BlockSurvivesAnAttribute()
    {
        var unit = Front.Parse("module M;\n/// the set\n[Flags]\npublic enum E { A = 1, }");

        var declared = Assert.IsType<EnumDeclSyntax>(unit.Declarations[0]);
        Assert.Equal("the set", declared.Documentation);
    }

    /// <summary>Each member of a type gets its own.</summary>
    [Fact]
    public void MembersCarryTheirOwnBlocks()
    {
        var unit = Front.Parse("""
            module M;
            /// the type
            public class C {
                /// the first
                public int A() { return 0; }
                /// the second
                public int B() { return 1; }
            }
            """);

        var type = Assert.IsType<TypeDeclSyntax>(unit.Declarations[0]);
        Assert.Equal("the type", type.Documentation);

        Assert.Equal(
            ["the first", "the second"],
            type.Members.OfType<FunctionDeclSyntax>().Select(m => m.Documentation));
    }

    /// <summary>An enum case gets one, which a trailing comment could not be.</summary>
    [Fact]
    public void EnumCasesCarryBlocks()
    {
        var unit = Front.Parse("""
            module M;
            public enum E {
                /// nothing went wrong
                None,
                /// something did
                Failed,
            }
            """);

        var declared = Assert.IsType<EnumDeclSyntax>(unit.Declarations[0]);

        Assert.Equal(
            ["nothing went wrong", "something did"],
            declared.Members.Select(m => m.Documentation));
    }

    /// <summary>And so does a variant's case.</summary>
    [Fact]
    public void VariantCasesCarryBlocks()
    {
        var unit = Front.Parse("""
            module M;
            public variant V {
                /// there is none
                Empty;
                /// there is one
                Full(int Value);
            }
            """);

        var declared = Assert.IsType<TypeDeclSyntax>(unit.Declarations[0]);

        Assert.Equal(
            ["there is none", "there is one"],
            declared.Cases.Select(c => c.Documentation));
    }

    /// <summary>A block above <c>module</c> is the module's, not the first
    /// declaration's.</summary>
    [Fact]
    public void ModuleCarriesItsBlock()
    {
        var unit = Front.Parse("/// what this module is for\nmodule M;\npublic int F() { return 0; }");

        Assert.Equal("what this module is for", unit.Documentation);
        Assert.Null(unit.Declarations[0].Documentation);
    }

    /// <summary>
    /// With no module clause the block belongs to whatever the first token
    /// declares -- there is no module for it to be about.
    /// </summary>
    [Fact]
    public void NoModuleClauseLeavesTheBlockOnTheDeclaration()
    {
        var unit = Front.Parse("/// about the function\npublic int F() { return 0; }");

        Assert.Null(unit.Documentation);
        Assert.Equal("about the function", unit.Declarations[0].Documentation);
    }

    // ------------------------------------------------------------ the writer

    /// <summary>The prose and the written signature both reach the page.</summary>
    [Fact]
    public void PageCarriesSignatureAndProse()
    {
        string page = Page("""
            /// The module.
            module M;
            /// What it answers.
            public int Twice(int value) { return value * 2; }
            """);

        Assert.Contains("# M", page);
        Assert.Contains("The module.", page);
        Assert.Contains("int Twice(int value)", page);
        Assert.Contains("What it answers.", page);
    }

    /// <summary>
    /// A generic reaches the page, which is the whole reason the writer reads
    /// syntax rather than bound symbols: a template that nothing instantiated
    /// has no symbol to walk.
    /// </summary>
    [Fact]
    public void GenericsReachThePage()
    {
        string page = Page("""
            module M;
            /// A box.
            public class Box<T> {
                /// What is in it.
                public T Get() { return default(T); }
            }
            """);

        Assert.Contains("class Box<T>", page);
        Assert.Contains("A box.", page);
        Assert.Contains("T Get()", page);
    }

    /// <summary>
    /// A member with no block says so rather than being left blank. Silence and
    /// "this needs no explanation" look identical on a page, and they are not
    /// the same thing.
    /// </summary>
    [Fact]
    public void AMissingBlockIsSaid()
    {
        string page = Page("module M;\npublic int F() { return 0; }");

        Assert.Contains("No documentation", page);
    }

    /// <summary>Anything not public is not a reference page's business.</summary>
    [Fact]
    public void PrivateDeclarationsAreLeftOut()
    {
        string page = Page("""
            module M;
            /// Said out loud.
            public int Public() { return 0; }
            /// Kept to itself.
            int Hidden() { return 0; }
            """);

        Assert.Contains("Public", page);
        Assert.DoesNotContain("Hidden", page);
    }

    /// <summary>
    /// An interface's members are its contract, so they are documented whether
    /// or not the word <c>public</c> is written -- which it never is.
    /// </summary>
    [Fact]
    public void InterfaceMembersAreDocumented()
    {
        string page = Page("""
            module M;
            /// Something readable.
            public interface IReadable {
                /// How many there are.
                nuint Count();
            }
            """);

        Assert.Contains("nuint Count()", page);
        Assert.Contains("How many there are.", page);
    }

    /// <summary>One page per module, plus an index naming them.</summary>
    [Fact]
    public void AnIndexNamesEveryModule()
    {
        string directory = Directory.CreateTempSubdirectory("stainless-doc").FullName;
        try
        {
            DocWriter.Write(
                [Front.Parse("/// The first.\nmodule A;\npublic int F() { return 0; }"),
                 Front.Parse("/// The second.\nmodule B;\npublic int G() { return 0; }")],
                directory);

            string index = File.ReadAllText(Path.Combine(directory, "index.md"));

            Assert.Contains("[A](A.md)", index);
            Assert.Contains("[B](B.md)", index);
            Assert.Contains("The first.", index);
            Assert.Contains("The second.", index);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>A module split over two files is one page.</summary>
    [Fact]
    public void OneModuleInTwoFilesIsOnePage()
    {
        string directory = Directory.CreateTempSubdirectory("stainless-doc").FullName;
        try
        {
            var written = DocWriter.Write(
                [Front.Parse("module M;\n/// The first half.\npublic int F() { return 0; }"),
                 Front.Parse("module M;\n/// The second half.\npublic int G() { return 0; }")],
                directory);

            // The page and the index, and nothing else.
            Assert.Equal(2, written.Count);

            string page = File.ReadAllText(Path.Combine(directory, "M.md"));
            Assert.Contains("The first half.", page);
            Assert.Contains("The second half.", page);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>The one module's page, as text.</summary>
    private static string Page(string source)
    {
        string directory = Directory.CreateTempSubdirectory("stainless-doc").FullName;
        try
        {
            var written = DocWriter.Write([Front.Parse(source)], directory);

            // The index is last, so the page before it is the module's.
            return File.ReadAllText(written[0]);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }
}
