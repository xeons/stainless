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

using Stainless.Syntax;
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// <c>$"a {b} c"</c>: what it accepts, what it refuses, and what it emits.
///
/// The end-to-end case proves the answers come out right. These are the
/// refusals -- which produce no output to compare -- and the two shapes worth
/// pinning in the IR, since both are the reason the feature is more than
/// spelling.
/// </summary>
public class InterpolationTests
{
    private static string[] Body(string body) =>
        Front.ModuleCodes("int Main()\n{\n" + body + "\n    return 0;\n}");

    // ------------------------------------------------------------- accepted

    [Theory]
    [InlineData("""String s = $"plain";""")]
    [InlineData("""String s = $"";""")]
    [InlineData("""int n = 1; String s = $"{n}";""")]
    [InlineData("""int n = 1; String s = $"a{n}b{n}c";""")]
    [InlineData("""int n = 1; String s = $"{n}{n}";""")]
    [InlineData("""String w = "x"; String s = $"{w}";""")]
    [InlineData("""long n = 1; nuint u = 1u; String s = $"{n}{u}";""")]
    [InlineData("""double d = 1.0; bool b = true; String s = $"{d}{b}";""")]
    [InlineData("""char32 c = 'x'; String s = $"{c}";""")]
    [InlineData("""int n = 1; String s = $"{n + 1}";""")]
    [InlineData("""String w = "x"; String s = $"{w.ToUpperAscii()}";""")]
    [InlineData("""int n = 1; String s = $"{(n > 0 ? "y" : "n")}";""")]
    [InlineData("""String s = $"{{literal}}";""")]
    [InlineData("""int n = 1; String s = $"{$"{n}"}";""")]
    [InlineData("""String s = $"{"inner {brace}"}";""")]
    public void AnInterpolationBinds(string body) => Assert.Empty(Body(body));

    // ------------------------------------------------------------- refused

    /// <summary>
    /// A code unit is not a character, and the language keeps that distinction
    /// everywhere else (SLT0056). Writing one as a character would cross it
    /// quietly, so the cast that says which is meant is required here too.
    /// </summary>
    [Theory]
    [InlineData("""char c = 'x'; String s = $"{c}";""")]
    [InlineData("""char16 c = 'x'; String s = $"{c}";""")]
    public void ACodeUnitNeedsToSayWhichItMeans(string body) =>
        Assert.Contains("SLT0062", Body(body));

    /// <summary>An enum writes its member's name, and takes no format.</summary>
    [Theory]
    [InlineData("""String s = $"{Level.High}";""", new string[0])]
    [InlineData("""String s = Level.High.ToText();""", new string[0])]
    [InlineData("""String s = $"{Level.High:X}";""", new[] { "SLT0074" })]
    [InlineData("""String s = Level.High.ToText("G");""", new[] { "SLT0014" })]
    public void AnEnumWritesItsName(string body, string[] codes) =>
        Assert.Equal(codes, Front.ModuleCodes(
            "public enum Level { Low, High }\nint Main() { " + body + " return 0; }"));

    /// <summary>
    /// And anything with no text at all. There is no universal ToString, and
    /// inventing one to make this work would be a far larger decision than a
    /// formatting syntax.
    /// </summary>
    [Theory]
    [InlineData("""public class C { } int Main() { var c = new C(); String s = $"{c}"; return 0; }""")]
    [InlineData("""int Main() { int[] a = [1]; String s = $"{a}"; return 0; }""")]
    [InlineData("""void V() { } int Main() { String s = $"{V()}"; return 0; }""")]
    public void SomethingWithNoTextIsRefused(string source) =>
        Assert.Contains("SLT0062", Front.ModuleCodes(source));

    /// <summary>An empty hole names no value.</summary>
    [Fact]
    public void AnEmptyHoleIsRefused() => Assert.Contains("SLP0033", Body("""String s = $"{}";"""));

    /// <summary>A lone closing brace closes nothing; `}}` is the literal.</summary>
    [Fact]
    public void ALoneClosingBraceIsRefused() =>
        Assert.Contains("SLP0032", Body("""String s = $"a } b";"""));

    /// <summary>
    /// A hole holds one expression. Two would mean the second was silently
    /// dropped, which is worse than saying so.
    /// </summary>
    [Fact]
    public void TwoExpressionsInOneHoleAreRefused() =>
        Assert.Contains("SLP0034", Body("""int a = 1; int b = 2; String s = $"{a b}";"""));

    /// <summary>An unterminated one is the same error a plain literal gets.</summary>
    [Fact]
    public void AnUnterminatedInterpolationIsRefused() =>
        Assert.Contains("SLP0006", Body("""String s = $"unfinished;"""));

    // ------------------------------------------------- alignment and format

    [Theory]
    [InlineData("""int n = 1; String s = $"{n,5}";""")]
    [InlineData("""int n = 1; String s = $"{n,-5}";""")]
    [InlineData("""int n = 1; String s = $"{n:X8}{n:x}{n:B}{n:D3}{n:N0}{n:F1}{n:E2}{n:G}";""")]
    [InlineData("""byte n = 1; ulong u = 2u; String s = $"{n:X2}{u:N}";""")]
    [InlineData("""double d = 1.5; float f = 2.5f; String s = $"{d:F2}{d:N}{d:e3}{f:G4}";""")]
    [InlineData("""double d = 1.5; String s = $"{d,10:F3}";""")]
    [InlineData("""String w = "x"; bool b = true; String s = $"{w,8}{b,-6}";""")]
    [InlineData("""int n = 1; String s = $"{(n > 0 ? 1 : 2):D2}";""")]
    [InlineData("""int n = 1; String s = $@"{n:X}\";""")]
    [InlineData(""""int n = 1; String s = $$"""{{n:X}} {x}""";"""")]
    public void AnAlignedOrFormattedHoleBinds(string body) => Assert.Empty(Body(body));

    /// <summary>
    /// A number's format is text in the source and its type is known, so a
    /// letter it does not take is refused here rather than when the line runs.
    /// </summary>
    [Theory]
    [InlineData("""int n = 1; String s = $"{n:Q}";""")]
    [InlineData("""int n = 1; String s = $"{n:0.00}";""")]
    [InlineData("""int n = 1; String s = $"{n:X1234}";""")]
    [InlineData("""int n = 1; String s = $"{n:}";""")]
    [InlineData("""double d = 1.0; String s = $"{d:X}";""")]
    [InlineData("""double d = 1.0; String s = $"{d:D2}";""")]
    [InlineData("""String w = "x"; String s = $"{w:X}";""")]
    [InlineData("""bool b = true; String s = $"{b:D}";""")]
    public void AFormatTheTypeDoesNotTakeIsRefused(string body) =>
        Assert.Contains("SLT0074", Body(body));

    [Theory]
    [InlineData("""int n = 1; int w = 4; String s = $"{n,w}";""")]
    [InlineData("""int n = 1; String s = $"{n,1.5}";""")]
    [InlineData("""int n = 1; String s = $"{n,"x"}";""")]
    public void AnAlignmentMustBeAConstantInteger(string body) =>
        Assert.Contains("SLT0075", Body(body));

    /// <summary>
    /// A <c>:</c> at the top of a hole starts its format, so a conditional's
    /// is taken for one. C# asks for the parentheses, and so does this.
    /// </summary>
    [Theory]
    [InlineData("""bool b = true; String s = $"{b ? 1 : 2}";""")]
    [InlineData("""bool b = true; String s = $"{b ? 1 : 2,4}";""")]
    public void AConditionalInAHoleNeedsParentheses(string body)
    {
        var codes = Body(body);
        Assert.Contains("SLP0050", codes);
        Assert.Single(codes);
    }

    /// <summary>
    /// A class that implements <c>IFormattable</c> has text to write, and is
    /// handed the format; one that does not is still refused.
    /// </summary>
    [Fact]
    public void AFormattableClassIsWrittenByItsOwnText() =>
        Assert.Empty(Front.ModuleCodes("""
            public class Money : IFormattable
            {
                public String ToText(String format) => format;
            }
            int Main() { var m = new Money(); String s = $"{m} {m:C} {m,8:long}"; return 0; }
            """));

    /// <summary>The parser leaves the alignment as code and the format as text.</summary>
    [Fact]
    public void AHoleParsesToItsValueAlignmentAndFormat()
    {
        var parsed = Assert.IsType<InterpolatedStringSyntax>(Front.Expression("""$"{x,-5:F2}" """));
        var hole = parsed.Parts.Single(p => p.Value is not null);

        Assert.IsType<NameSyntax>(hole.Value);
        Assert.IsType<UnarySyntax>(hole.Alignment);
        Assert.Equal("F2", hole.Format);
    }

    /// <summary>A constant is as fixed as a literal, so it may be the width.</summary>
    [Fact]
    public void AConstantIsAnAlignment() =>
        Assert.Empty(Front.ModuleCodes("""
            const int Width = -6;
            int Main() { int n = 1; String s = $"{n,Width}"; return 0; }
            """));

    [Fact]
    public void AClassThatIsNotFormattableTakesNoFormat() =>
        Assert.Contains("SLT0062", Front.ModuleCodes("""
            public class C { }
            int Main() { var c = new C(); String s = $"{c:X}"; return 0; }
            """));

    // ------------------------------------------------------------ literals

    /// <summary>
    /// <c>"..."u8</c> is a view of bytes, as C#'s is a <c>ReadOnlySpan</c>, so
    /// it goes where a <c>ReadOnlySpan<byte></c> goes and not where a String does.
    /// </summary>
    [Fact]
    public void AUtf8LiteralIsAByteSlice() =>
        Assert.Empty(Body("""ReadOnlySpan<byte> b = "abc"u8; var c = "x"u8; ReadOnlySpan<byte> d = c; nuint n = b.Length;"""));

    [Fact]
    public void AUtf8LiteralIsNotAString() =>
        Assert.NotEmpty(Body("""String s = "abc"u8;"""));

    /// <summary>
    /// The bytes are one constant, not an allocation: an immortal array in
    /// read-only storage, with a NUL after the counted bytes.
    /// </summary>
    [Fact]
    public void AUtf8LiteralIsStaticData()
    {
        string ir = Front.ModuleIr("""public ReadOnlySpan<byte> Bytes() { return "hé"u8; }""");

        Assert.Contains("= private unnamed_addr constant", ir, StringComparison.Ordinal);
        Assert.Contains("c\"h\\C3\\A9\\00\"", ir, StringComparison.Ordinal);
        Assert.DoesNotContain("sl_array_alloc", Front.TestFunction(ir, "Bytes"), StringComparison.Ordinal);
    }

    /// <summary>
    /// <c>@name</c> is the name, keyword or not, and a contextual word written
    /// with one is never the word.
    /// </summary>
    [Theory]
    [InlineData("""int @class = 1; int @int = @class + 1; String s = $"{@int}";""")]
    [InlineData("""int @checked = 1; int n = @checked;""")]
    [InlineData("""int count = 1; int n = @count;""")]
    public void AVerbatimIdentifierBinds(string body) => Assert.Empty(Body(body));

    [Fact]
    public void AVerbatimIdentifierMangledAsTheBareName()
    {
        string ir = Front.ModuleIr("""public int @class(int @int) { return @int; }""");
        Assert.Contains("5class", ir, StringComparison.Ordinal);
        Assert.DoesNotContain("@class(", ir.Replace("define", ""), StringComparison.Ordinal);
    }

    // ---------------------------------------------------------------- lexing

    /// <summary>
    /// The `$` is only special before a quote, so a `$` anywhere else is still
    /// the error it was and nothing has been quietly given a meaning.
    /// </summary>
    [Fact]
    public void ADollarAloneIsStillAnError()
    {
        Front.Tokens("module Test;\nint Main() { int $ = 1; return 0; }", out var diagnostics);
        Assert.Contains("SLP0001", Front.Codes(diagnostics));
    }

    /// <summary>A hole's tokens carry their real positions in the file.</summary>
    [Fact]
    public void AHolesTokensKeepTheirPlace()
    {
        const string source = """String s = $"ab{cd}";""";
        var token = Front.Tokens("module Test;\nint Main() { " + source + " return 0; }")
            .First(t => t.Kind == TokenKind.InterpolatedString);

        var segments = (IReadOnlyList<InterpolationSegment>)token.Value!;
        var hole = segments.Single(s => s.IsHole);
        var name = hole.Tokens!.First();

        // The identifier `cd` sits where the source has it, not at zero and not
        // at an offset into a copy -- which is what makes a diagnostic about a
        // hole point at the program.
        Assert.Equal("cd", name.Text);
        Assert.Equal(source.IndexOf("cd", StringComparison.Ordinal) + "module Test;\nint Main() { ".Length,
                     name.Span.Start);
    }

    // ----------------------------------------------------------------- emit

    /// <summary>
    /// One allocation, not one per piece.
    ///
    /// This is the whole reason the node exists rather than lowering to a
    /// chain of <c>+</c>: that chain calls <c>sl_string_concat</c> once per
    /// operator and discards every result but the last.
    /// </summary>
    [Fact]
    public void AnInterpolationJoinsOnce()
    {
        // Scoped to the one function: the standard library concatenates all
        // over the place, and every runtime entry point is declared in every
        // module whether or not anything reaches it.
        string body = Front.TestFunction(Front.ModuleIr("""
            public String Written(int a, int b) { return $"x{a}y{b}z"; }
            """), "Written");

        Assert.Contains("call ptr @sl_string_join", body, StringComparison.Ordinal);
        Assert.DoesNotContain("sl_string_concat", body, StringComparison.Ordinal);
    }

    // ---------------------------------------------------------------- depth

    private static string[] ParseCodes(string expression) => Source.Recursion.OnADeepStack(() =>
    {
        Front.Parse("module A;\nint Main() { var s = " + expression + "; return 0; }",
                    out var diagnostics);
        return Front.Codes(diagnostics);
    });

    private static string Nested(string open, string inner, string close, int count) =>
        string.Concat(Enumerable.Repeat(open, count)) + inner +
        string.Concat(Enumerable.Repeat(close, count));

    /// <summary>
    /// A hole is lexed by recursing into the token loop, so a string in a hole
    /// in a string is the one place the lexer recurses, and a hundred thousand
    /// of them overflowed even the compilation's deep stack. It is refused at
    /// the parser's depth limit instead, with the one message and nothing about
    /// the strings left unterminated by giving up.
    /// </summary>
    [Fact]
    public void AnInterpolationNestedTooDeeplyIsRefusedByTheLexer() =>
        Assert.Equal(["SLP0016"], ParseCodes(Nested("$\"{", "1", "}\"", 100_000)));

    /// <summary>
    /// The parser over a hole counts from its parent's depth. Each started from
    /// nothing, so two hundred strings in strings, the innermost holding two
    /// hundred parentheses, was within the limit in every parser and past it
    /// in all of them together.
    /// </summary>
    [Fact]
    public void AHoleCountsTheDepthItIsNestedAt() =>
        Assert.Equal(["SLP0016"],
            ParseCodes(Nested("$\"{", Nested("(", "1", ")", 200), "}\"", 200)));

    /// <summary>
    /// And an interpolation with no holes is a literal, so it costs what one
    /// costs: static bytes, no allocation and no call.
    /// </summary>
    [Fact]
    public void AnInterpolationWithNoHolesIsJustALiteral()
    {
        string ir = Front.ModuleIr("""public String Written() { return $"plain {{text}}"; }""");

        Assert.DoesNotContain("sl_string_join", Front.TestFunction(ir, "Written"),
                              StringComparison.Ordinal);
        Assert.Contains("plain {text}", ir, StringComparison.Ordinal);
    }
}
