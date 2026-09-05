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
    /// everywhere else (SL0527). Writing one as a character would cross it
    /// quietly, so the cast that says which is meant is required here too.
    /// </summary>
    [Theory]
    [InlineData("""char c = 'x'; String s = $"{c}";""")]
    [InlineData("""char16 c = 'x'; String s = $"{c}";""")]
    public void ACodeUnitNeedsToSayWhichItMeans(string body) =>
        Assert.Contains("SL0557", Body(body));

    /// <summary>
    /// An enum would have to write its number, since nothing records a
    /// member's name. Saying so beats printing a 1 nobody asked for.
    /// </summary>
    [Fact]
    public void AnEnumIsRefusedWithItsReason() =>
        Assert.Contains("SL0557", Front.ModuleCodes("""
            public enum Level { Low, High }
            int Main() { String s = $"{Level.High}"; return 0; }
            """));

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
        Assert.Contains("SL0557", Front.ModuleCodes(source));

    /// <summary>An empty hole names no value.</summary>
    [Fact]
    public void AnEmptyHoleIsRefused() => Assert.Contains("SL0555", Body("""String s = $"{}";"""));

    /// <summary>A lone closing brace closes nothing; `}}` is the literal.</summary>
    [Fact]
    public void ALoneClosingBraceIsRefused() =>
        Assert.Contains("SL0554", Body("""String s = $"a } b";"""));

    /// <summary>
    /// A hole holds one expression. Two would mean the second was silently
    /// dropped, which is worse than saying so.
    /// </summary>
    [Fact]
    public void TwoExpressionsInOneHoleAreRefused() =>
        Assert.Contains("SL0556", Body("""int a = 1; int b = 2; String s = $"{a b}";"""));

    /// <summary>An unterminated one is the same error a plain literal gets.</summary>
    [Fact]
    public void AnUnterminatedInterpolationIsRefused() =>
        Assert.Contains("SL0006", Body("""String s = $"unfinished;"""));

    // ---------------------------------------------------------------- lexing

    /// <summary>
    /// The `$` is only special before a quote, so a `$` anywhere else is still
    /// the error it was and nothing has been quietly given a meaning.
    /// </summary>
    [Fact]
    public void ADollarAloneIsStillAnError()
    {
        Front.Tokens("module Test;\nint Main() { int $ = 1; return 0; }", out var diagnostics);
        Assert.Contains("SL0001", Front.Codes(diagnostics));
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
