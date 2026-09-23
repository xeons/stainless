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

using Stainless.Emit;
using Stainless.Syntax;
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// Reading a <c>///</c> block: the prose that is its summary, and the
/// <c>@tags</c> under it.
/// </summary>
public class DocCommentTests
{
    private static DocComment Read(params string[] lines) =>
        DocComment.Parse(string.Join("\n", lines));

    // -------------------------------------------------------------- the prose

    /// <summary>
    /// The rule every block already in the tree depends on: with no tags, the
    /// whole block is the summary.
    /// </summary>
    [Fact]
    public void ProseWithNoTagsIsAllSummary()
    {
        var read = Read("The whole file as text.", "", "**Reads to the end**, because /proc lies.");

        Assert.Equal(
            "The whole file as text.\n\n**Reads to the end**, because /proc lies.",
            read.Summary);
        Assert.Empty(read.Tags);
    }

    [Fact]
    public void AnEmptyBlockIsEmpty()
    {
        Assert.True(DocComment.Parse("").IsEmpty);
        Assert.True(DocComment.Parse("").Tags.Count == 0);
    }

    /// <summary>
    /// Markdown is prose and is carried through untouched: the generator writes
    /// Markdown, so there is nothing to translate.
    /// </summary>
    [Fact]
    public void MarkdownIsLeftAlone()
    {
        var read = Read(
            "A `List<T>` of them, in order.",
            "",
            "  - `Add` puts one at the end",
            "  - `RemoveAt` takes one out");

        Assert.Contains("`List<T>`", read.Summary);
        Assert.Contains("  - `Add` puts one at the end", read.Summary);
    }

    // --------------------------------------------------------------- the tags

    [Fact]
    public void ATagEndsTheSummary()
    {
        var read = Read("What it answers.", "@returns the number of bytes written");

        Assert.Equal("What it answers.", read.Summary);
        Assert.Equal("the number of bytes written", Assert.Single(read.Tags).Text);
        Assert.Equal(DocTagKind.Returns, read.Tags[0].Kind);
    }

    [Fact]
    public void ATagNamesWhatItIsAbout()
    {
        var read = Read("@param path where to read from");

        var tag = Assert.Single(read.Tags);
        Assert.Equal(DocTagKind.Param, tag.Kind);
        Assert.Equal("path", tag.Name);
        Assert.Equal("where to read from", tag.Text);
    }

    /// <summary>A description runs until the next tag, however many lines it takes.</summary>
    [Fact]
    public void ADescriptionWrapsOntoTheNextLine()
    {
        var read = Read(
            "@param path  where to read from, absolute or relative",
            "             to the working directory",
            "@returns the contents");

        Assert.Equal(2, read.Tags.Count);
        Assert.Equal(
            "where to read from, absolute or relative\nto the working directory",
            read.Tags[0].Text);
        Assert.Equal("the contents", read.Tags[1].Text);
    }

    /// <summary>
    /// An indented <c>@</c> is text. The four-space code samples this tree
    /// already writes are full of lines that start with punctuation, and none
    /// of them is markup.
    /// </summary>
    [Fact]
    public void AnIndentedTagIsText()
    {
        var read = Read("Reads one.", "", "    var x = handle@2;", "", "Ordinary prose.");

        Assert.Empty(read.Tags);
        Assert.Contains("    var x = handle@2;", read.Summary);
    }

    [Fact]
    public void AnAddressInProseIsNotATag()
    {
        var read = Read("The decorated name is `_LoadLibraryA@4`, not `_LoadLibraryA`.");

        Assert.Empty(read.Tags);
    }

    [Fact]
    public void EveryTagIsRead()
    {
        var read = Read(
            "One.",
            "@param a first",
            "@typeparam T the element",
            "@returns something",
            "@value what it holds",
            "@remarks aside",
            "@example a sample",
            "@failure IOError.NoSpace the disk filled up",
            "@see File.WriteAllText",
            "@seealso Standard.IO",
            "@inheritdoc Control.OnClick");

        Assert.Equal(
            [
                DocTagKind.Param, DocTagKind.TypeParam, DocTagKind.Returns, DocTagKind.Value,
                DocTagKind.Remarks, DocTagKind.Example, DocTagKind.Failure, DocTagKind.See,
                DocTagKind.SeeAlso, DocTagKind.InheritDoc,
            ],
            read.Tags.Select(t => t.Kind));

        Assert.Equal("IOError.NoSpace", read.FirstOfKind(DocTagKind.Failure)!.Name);
        Assert.Equal("the disk filled up", read.FirstOfKind(DocTagKind.Failure)!.Text);
    }

    /// <summary>
    /// A word that is nearly a tag is an unknown one rather than prose, so the
    /// mistake is reported instead of being silently dropped from the page.
    /// </summary>
    [Theory]
    [InlineData("@summary")]
    [InlineData("@return")]
    [InlineData("@throws")]
    [InlineData("@exception")]
    public void ANearMissIsUnknown(string word)
    {
        var read = Read(word + " something");

        Assert.Equal(DocTagKind.Unknown, Assert.Single(read.Tags).Kind);
        Assert.Equal(word[1..], read.Tags[0].Word);
    }

    [Fact]
    public void TwoParametersAreTwoTags()
    {
        var read = Read("@param a first", "@param b second");

        Assert.Equal(["a", "b"], read.OfKind(DocTagKind.Param).Select(t => t.Name));
    }

    /// <summary>
    /// An example is kept exactly as written: its indentation is what makes it
    /// a Markdown code block, and taking the alignment off would leave prose.
    /// </summary>
    [Fact]
    public void AnExampleKeepsItsIndent()
    {
        var read = Read("@example", "    var text = ReadText(path);");

        Assert.Equal("    var text = ReadText(path);", Assert.Single(read.Tags).Text);
    }

    // ------------------------------------------------------------- the pages

    /// <summary>
    /// A block with no tags renders as it did before there were any, which is
    /// what every block already in the tree depends on.
    /// </summary>
    [Fact]
    public void AnUntaggedBlockIsAllProse()
    {
        string page = Page("""
            module M;
            /// The whole file as text.
            ///
            /// **Reads to the end**, because /proc reports zero.
            public int F() { return 0; }
            """);

        Assert.Contains("The whole file as text.", page);
        Assert.Contains("**Reads to the end**, because /proc reports zero.", page);
        Assert.DoesNotContain("**Parameters**", page);
    }

    [Fact]
    public void TagsBecomeSections()
    {
        string page = Page("""
            module M;
            /// Reads one.
            ///
            /// @param path where to read from
            /// @param trim whether to strip whitespace
            /// @returns the contents
            public int F(int path, int trim) { return 0; }
            """);

        Assert.Contains("**Parameters**", page);
        Assert.Contains("- `path` — where to read from", page);
        Assert.Contains("- `trim` — whether to strip whitespace", page);
        Assert.Contains("**Returns** &nbsp; the contents", page);
    }

    /// <summary>
    /// A failure names a case of the error type, and the page links to where
    /// that case is documented.
    /// </summary>
    [Fact]
    public void AFailureLinksToItsCase()
    {
        string page = Page("""
            module M;
            /// What went wrong.
            public enum E {
                /// Nothing there.
                Missing,
            }
            /// Reads one.
            ///
            /// @failure E.Missing there is no file
            public int F() { return 0; }
            """);

        Assert.Contains("**Fails with**", page);
        Assert.Contains("[E.Missing](#missing-case) — there is no file", page);
    }

    [Fact]
    public void AnExampleStaysACodeBlockOnThePage()
    {
        string page = Page("""
            module M;
            /// Reads one.
            ///
            /// @example
            ///     var text = F();
            public int F() { return 0; }
            """);

        Assert.Contains("**Example**", page);
        Assert.Contains("    var text = F();", page);
    }

    [Fact]
    public void ASeeAlsoLinksWhereItCan()
    {
        string page = Page("""
            module M;
            /// One.
            public int F() { return 0; }
            /// Two.
            ///
            /// @see F
            /// @seealso Elsewhere.Thing
            public int G() { return 0; }
            """);

        Assert.Contains("[F](#f-function)", page);

        // Nothing in this run documents it, so it stays as it was written
        // rather than becoming a link to nowhere.
        Assert.Contains("`Elsewhere.Thing`", page);
    }

    /// <summary>
    /// A bare <c>@inheritdoc</c> takes the block from the member it overrides,
    /// and what the override adds is written after it.
    /// </summary>
    [Fact]
    public void InheritDocTakesTheBaseBlock()
    {
        string page = Page("""
            module M;
            /// Something drawable.
            public class Shape {
                /// Draws it.
                ///
                /// @param surface where to draw
                public virtual void Draw(int surface) { }
            }
            /// A round one.
            public class Circle : Shape {
                /// @inheritdoc
                ///
                /// One stroke, and no corners.
                public override void Draw(int surface) { }
            }
            """);

        Assert.Contains("- `surface` — where to draw", page);
        Assert.Contains("One stroke, and no corners.", page);
    }

    [Fact]
    public void InheritDocFollowsAName()
    {
        string page = Page("""
            module M;
            /// Something drawable.
            public class Shape {
                /// Draws it.
                public virtual void Draw() { }
            }
            /// A square one.
            public class Square : Shape {
                /// @inheritdoc Shape.Draw
                public override void Draw() { }
            }
            """);

        // Once where it was written, and once where it was inherited.
        Assert.Equal(2, page.Split("Draws it.").Length - 1);
    }

    /// <summary>The page one module's source produces.</summary>
    private static string Page(string source)
    {
        string directory = Directory.CreateTempSubdirectory("stainless-doc").FullName;
        try
        {
            return File.ReadAllText(DocWriter.Write([Front.Parse(source)], directory)[0]);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }
}
