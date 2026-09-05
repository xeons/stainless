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
/// The lexer, asked about one piece of text at a time.
///
/// Most of what is here cannot be reached from an end-to-end case: a program
/// that runs proves its literals were decoded consistently, not that they were
/// decoded correctly, and it proves nothing at all about a span.
/// </summary>
public class LexerTests
{
    // ------------------------------------------------------------- keywords

    /// <summary>
    /// Every keyword lexes to the kind that spells it.
    ///
    /// This is the test that was missing when <c>char16</c> was added. The
    /// keyword table is built by asking each token kind for its fixed text and
    /// keeping the ones shaped like a word, and the shape test was
    /// letters-only -- so <c>char16</c> silently was not a keyword, and the
    /// error you got was that no type of that name existed.
    /// </summary>
    [Fact]
    public void EveryKeywordLexesToItsOwnKind()
    {
        foreach (var (text, kind) in TokenKindExtensions.Keywords)
            Assert.Equal([kind], Front.Kinds(text));
    }

    /// <summary>
    /// And every word-shaped token kind is in the table.
    ///
    /// The other half of the same bug: a kind whose text the table's filter
    /// rejects lexes as an identifier, and nothing else notices.
    /// </summary>
    [Fact]
    public void EveryWordShapedKindIsAKeyword()
    {
        var missing = Enum.GetValues<TokenKind>()
            .Where(k => k != TokenKind.EndOfFile &&
                        k.FixedText() is { Length: > 0 } text &&
                        char.IsLetter(text[0]) &&
                        text.All(c => char.IsLetterOrDigit(c) || c == '_') &&
                        !TokenKindExtensions.Keywords.ContainsKey(text))
            .ToList();

        Assert.Empty(missing);
    }

    [Theory]
    [InlineData("charm")]
    [InlineData("classy")]
    [InlineData("ints")]
    [InlineData("char16s")]
    [InlineData("_class")]
    public void AWordThatMerelyStartsWithAKeywordIsAName(string source) =>
        Assert.Equal([TokenKind.Identifier], Front.Kinds(source));

    // ---------------------------------------------------------- punctuation

    /// <summary>
    /// Every fixed-text operator lexes to itself, which is what proves the
    /// longest-match order is right: if <c>&gt;&gt;</c> were tried before
    /// <c>&gt;&gt;=</c> this would produce two tokens instead of one.
    /// </summary>
    [Fact]
    public void EveryOperatorLexesToItsOwnKind()
    {
        foreach (var kind in Enum.GetValues<TokenKind>())
        {
            if (kind.FixedText() is not { Length: > 0 } text) continue;
            if (char.IsLetter(text[0])) continue;
            if (kind == TokenKind.EndOfFile) continue;

            Assert.Equal([kind], Front.Kinds(text));
        }
    }

    [Theory]
    [InlineData(">", new[] { TokenKind.Greater })]
    [InlineData(">=", new[] { TokenKind.GreaterEquals })]
    [InlineData(">>", new[] { TokenKind.GreaterGreater })]
    [InlineData(">>=", new[] { TokenKind.GreaterGreaterEquals })]
    [InlineData("> >", new[] { TokenKind.Greater, TokenKind.Greater })]
    [InlineData("=>", new[] { TokenKind.EqualsGreater })]
    [InlineData("->", new[] { TokenKind.MinusGreater })]
    [InlineData("==", new[] { TokenKind.EqualsEquals })]
    [InlineData("!=", new[] { TokenKind.BangEquals })]
    public void LongestMatchWins(string source, TokenKind[] expected) =>
        Assert.Equal(expected, Front.Kinds(source));

    // ------------------------------------------------------ integer literals

    [Theory]
    [InlineData("0", 0UL)]
    [InlineData("42", 42UL)]
    [InlineData("0x1F", 31UL)]
    [InlineData("0X1f", 31UL)]
    [InlineData("0b1010", 10UL)]
    [InlineData("0B1010", 10UL)]
    [InlineData("1_000_000", 1000000UL)]
    [InlineData("0xFF_FF", 65535UL)]
    [InlineData("18446744073709551615", ulong.MaxValue)]
    [InlineData("0xFFFFFFFFFFFFFFFF", ulong.MaxValue)]
    public void IntegerLiteralsDecode(string source, ulong expected)
    {
        var tokens = Front.Tokens(source, out var diagnostics);
        Assert.Empty(Front.Codes(diagnostics));
        Assert.Equal(TokenKind.IntLiteral, tokens[0].Kind);
        Assert.Equal(expected, tokens[0].Value);
    }

    /// <summary>
    /// A suffix is lexed and does not change the value. What the suffix means
    /// is the binder's business; the lexer's job is only to not choke on it.
    /// </summary>
    [Theory]
    [InlineData("1u")]
    [InlineData("1U")]
    [InlineData("1l")]
    [InlineData("1L")]
    [InlineData("1ul")]
    [InlineData("1UL")]
    public void AnIntegerSuffixIsPartOfTheLiteral(string source)
    {
        var tokens = Front.Tokens(source);
        Assert.Equal(TokenKind.IntLiteral, tokens[0].Kind);
        Assert.Equal(1UL, tokens[0].Value);
        Assert.Equal(TokenKind.EndOfFile, tokens[1].Kind);
    }

    // -------------------------------------------------------- float literals

    [Theory]
    [InlineData("1.5", 1.5)]
    [InlineData("0.0", 0.0)]
    [InlineData("1e3", 1000.0)]
    [InlineData("1E3", 1000.0)]
    [InlineData("1e-3", 0.001)]
    [InlineData("1.5e2", 150.0)]
    [InlineData("1.5f", 1.5)]
    [InlineData("1.5d", 1.5)]
    public void FloatLiteralsDecode(string source, double expected)
    {
        var tokens = Front.Tokens(source, out var diagnostics);
        Assert.Empty(Front.Codes(diagnostics));
        Assert.Equal(TokenKind.FloatLiteral, tokens[0].Kind);
        Assert.Equal(expected, (double)tokens[0].Value!, 12);
    }

    /// <summary>
    /// A C-style <c>...</c> is three Dot tokens rather than a token of its own,
    /// which is what the variadic parameter rule is written against.
    /// </summary>
    [Fact]
    public void EllipsisIsThreeDots() =>
        Assert.Equal(
            [TokenKind.Dot, TokenKind.Dot, TokenKind.Dot],
            Front.Kinds("..."));

    // -------------------------------------------------------- character literals

    /// <summary>
    /// A character literal is one Unicode scalar carried as an <c>int</c>, not
    /// a UTF-8 byte and not a UTF-16 unit. Which of the three types it settles
    /// into is decided later, by what it is being assigned to.
    /// </summary>
    [Theory]
    [InlineData("'a'", 97)]
    [InlineData("'0'", 48)]
    [InlineData("' '", 32)]
    [InlineData("'é'", 0xE9)]
    [InlineData("'€'", 0x20AC)]
    public void CharacterLiteralsAreScalars(string source, int expected) =>
        Assert.Equal(expected, Front.Tokens(source)[0].Value);

    /// <summary>
    /// A character written outside the basic plane arrives as a surrogate pair
    /// in the C# source the lexer is reading, and must come out as the one
    /// scalar it spells rather than as the first half of it.
    /// </summary>
    [Fact]
    public void ASurrogatePairIsOneScalar()
    {
        var tokens = Front.Tokens("'\U0001F600'", out var diagnostics);
        Assert.Empty(Front.Codes(diagnostics));
        Assert.Equal(0x1F600, tokens[0].Value);
    }

    [Theory]
    [InlineData(@"'\n'", 10)]
    [InlineData(@"'\r'", 13)]
    [InlineData(@"'\t'", 9)]
    [InlineData(@"'\0'", 0)]
    [InlineData(@"'\\'", 92)]
    [InlineData(@"'\''", 39)]
    [InlineData(@"'\x41'", 65)]
    [InlineData(@"'é'", 0xE9)]
    [InlineData(@"'\U0001F600'", 0x1F600)]
    public void EscapesDecode(string source, int expected)
    {
        var tokens = Front.Tokens(source, out var diagnostics);
        Assert.Empty(Front.Codes(diagnostics));
        Assert.Equal(expected, tokens[0].Value);
    }

    /// <summary>
    /// A lone surrogate is not a scalar and cannot be encoded, so it is
    /// rejected and replaced rather than carried into a String that claims to
    /// be valid UTF-8.
    /// </summary>
    [Theory]
    [InlineData(@"'\ud800'")]
    [InlineData(@"'\udfff'")]
    [InlineData(@"'\U00110000'")]
    public void ANonScalarEscapeIsRejected(string source)
    {
        var tokens = Front.Tokens(source, out var diagnostics);
        Assert.Equal(["SL0526"], Front.Codes(diagnostics));
        Assert.Equal(0xFFFD, tokens[0].Value);
    }

    // ---------------------------------------------------------- string literals

    [Theory]
    [InlineData("\"\"", "")]
    [InlineData("\"hi\"", "hi")]
    [InlineData(@"""a\nb""", "a\nb")]
    [InlineData(@"""a\""b""", "a\"b")]
    [InlineData(@"""é""", "é")]
    [InlineData(@"""\U0001F600""", "\U0001F600")]
    public void StringLiteralsDecode(string source, string expected)
    {
        var tokens = Front.Tokens(source, out var diagnostics);
        Assert.Empty(Front.Codes(diagnostics));
        Assert.Equal(expected, tokens[0].Value);
    }

    // ------------------------------------------------------------ trivia

    [Fact]
    public void LineCommentsAreSkipped() =>
        Assert.Equal([TokenKind.IntLiteral], Front.Kinds("// nothing here\n1"));

    [Fact]
    public void BlockCommentsAreSkipped() =>
        Assert.Equal([TokenKind.IntLiteral], Front.Kinds("/* nothing\n here */ 1"));

    [Fact]
    public void AnEmptySourceIsJustEndOfFile() =>
        Assert.Equal([TokenKind.EndOfFile], Front.Tokens("").Select(t => t.Kind));

    // -------------------------------------------------------------- spans

    /// <summary>
    /// A token's span covers exactly its own text. Nothing end-to-end checks
    /// this, and every caret in every diagnostic depends on it.
    /// </summary>
    [Fact]
    public void ATokenSpanCoversItsOwnText()
    {
        const string source = "int  x = 42;";
        foreach (var token in Front.Tokens(source))
        {
            if (token.Kind == TokenKind.EndOfFile) continue;
            Assert.Equal(token.Text, source[token.Span.Start..token.Span.End]);
        }
    }

    [Fact]
    public void ASpanSkipsThePrecedingTrivia()
    {
        var tokens = Front.Tokens("  // a comment\n  42");
        Assert.Equal(TokenKind.IntLiteral, tokens[0].Kind);
        Assert.Equal(17, tokens[0].Span.Start);
        Assert.Equal(2, tokens[0].Span.Length);
    }

    // ------------------------------------------------------- preprocessor

    [Fact]
    public void AnUndefinedBranchIsSkipped() =>
        Assert.Equal(
            [TokenKind.IntLiteral],
            Front.Kinds("#if NOT_DEFINED\nfloat\n#endif\n1"));

    [Fact]
    public void ADefinedBranchIsTaken() =>
        Assert.Equal(
            [TokenKind.IntKeyword],
            Front.Kinds("#if STAINLESS\nint\n#endif"));

    [Fact]
    public void ElseTakesTheOtherBranch() =>
        Assert.Equal(
            [TokenKind.IntKeyword],
            Front.Kinds("#if NOT_DEFINED\nfloat\n#else\nint\n#endif"));

    /// <summary>
    /// Once a branch of a group has been taken, no later one is -- which is
    /// the whole difference between <c>#elif</c> and a second <c>#if</c>.
    /// </summary>
    [Fact]
    public void ElifAfterATakenBranchStaysShut() =>
        Assert.Equal(
            [TokenKind.IntKeyword],
            Front.Kinds("#if STAINLESS\nint\n#elif STAINLESS\nfloat\n#endif"));

    [Fact]
    public void DefineIsVisibleToALaterIf() =>
        Assert.Equal(
            [TokenKind.IntKeyword],
            Front.Kinds("#define MINE\n#if MINE\nint\n#endif"));

    [Fact]
    public void UndefTakesADefineBack() =>
        Assert.Empty(
            Front.Kinds("#define MINE\n#undef MINE\n#if MINE\nint\n#endif"));
}
