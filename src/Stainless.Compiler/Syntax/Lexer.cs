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

using System.Globalization;
using System.Text;
using Stainless.Source;

namespace Stainless.Syntax;

/// <summary>
/// Turns source text into a token stream.
///
/// The only thing between the text and the tokens is conditional compilation,
/// in the form C# has it: <c>#if</c> and its relatives choose which lines are
/// lexed at all, and <c>#define</c> names a symbol for them to test. There is no
/// macro, no textual substitution and no <c>#include</c> -- a name never stands
/// for anything but itself, and a declaration is still found without a header.
///
/// Text inside a branch that is not taken is skipped a line at a time, and only
/// a directive is looked for in it. So a branch for another platform need not
/// parse, which is the whole point of choosing at this level rather than later.
/// </summary>
public sealed class Lexer(
    SourceText source, DiagnosticBag diagnostics, IReadOnlyCollection<string>? symbols = null)
{
    private readonly string _text = source.Text;
    private int _pos;

    /// <summary>Symbols <c>#if</c> tests: the build's, plus any <c>#define</c>d here.</summary>
    private readonly HashSet<string> _symbols =
        new(symbols ?? [], StringComparer.Ordinal);

    /// <summary>
    /// One entry per open <c>#if</c>: whether this branch is being taken, and
    /// whether any branch of the group already has been. The second is what
    /// makes <c>#elif</c> after a taken branch stay shut.
    /// </summary>
    private readonly List<(bool Active, bool Taken, bool SawElse, int Start)> _conditions = [];

    /// <summary>
    /// True once a real token has been produced. <c>#define</c> and <c>#undef</c>
    /// must come before that, as in C#: a symbol whose meaning changed halfway
    /// down a file would make the lines above and below it disagree.
    /// </summary>
    private bool _sawToken;

    /// <summary>
    /// Libraries this file asked to link, from <c>#pragma comment(lib, "...")</c>.
    /// They reach the driver through the compilation unit, and from there the
    /// linker, exactly as a <c>-l</c> on the command line would.
    /// </summary>
    public List<string> Libraries { get; } = [];

    private bool Skipping => _conditions.Any(c => !c.Active);

    private char Current => Peek(0);
    private char Peek(int offset) => _pos + offset < _text.Length ? _text[_pos + offset] : '\0';
    private SourceSpan SpanFrom(int start) => new(source, start, _pos);

    public List<Token> Tokenize()
    {
        var tokens = new List<Token>();
        while (true)
        {
            var token = Next();
            if (token.Kind != TokenKind.Bad) tokens.Add(token);
            if (token.Kind == TokenKind.EndOfFile) break;
        }

        foreach (var open in _conditions)
            diagnostics.Error("SL0454", new SourceSpan(source, open.Start, open.Start + 3),
                "this '#if' is never closed; add '#endif'");

        return tokens;
    }

    private Token Next()
    {
        SkipTrivia();
        int start = _pos;

        if (_pos >= _text.Length)
            return new Token(TokenKind.EndOfFile, SpanFrom(start), "");

        _sawToken = true;
        char c = Current;
        if (char.IsLetter(c) || c == '_') return LexIdentifierOrKeyword(start);
        if (char.IsAsciiDigit(c)) return LexNumber(start);
        if (c == '"') return LexString(start);
        if (c == '$' && _pos + 1 < _text.Length && _text[_pos + 1] == '"')
            return LexInterpolatedString(start);
        if (c == '\'') return LexChar(start);
        return LexPunctuation(start);
    }

    private void SkipTrivia()
    {
        while (_pos < _text.Length)
        {
            // A directive is only a directive at the start of a line, so a '#'
            // anywhere else is left alone for the punctuation lexer to reject.
            if (Current == '#' && AtLineStart()) { Directive(); continue; }

            // Inside a branch that was not taken, nothing is lexed: the line is
            // consumed whole and only the next directive is looked for. Leading
            // whitespace goes first, because a nested directive is usually
            // indented and swallowing it would unbalance the group.
            if (Skipping)
            {
                while (_pos < _text.Length && (Current == ' ' || Current == '	')) _pos++;
                if (_pos < _text.Length && Current == '#') { Directive(); continue; }
                SkipLine();
                continue;
            }

            char c = Current;
            if (char.IsWhiteSpace(c)) { _pos++; continue; }

            if (c == '/' && Peek(1) == '/')
            {
                while (_pos < _text.Length && Current != '\n') _pos++;
                continue;
            }

            if (c == '/' && Peek(1) == '*')
            {
                int start = _pos;
                _pos += 2;
                int depth = 1;                      // block comments nest, unlike C
                while (_pos < _text.Length && depth > 0)
                {
                    if (Current == '/' && Peek(1) == '*') { depth++; _pos += 2; }
                    else if (Current == '*' && Peek(1) == '/') { depth--; _pos += 2; }
                    else _pos++;
                }
                if (depth > 0)
                    diagnostics.Error("SL0002", SpanFrom(start), "unterminated block comment");
                continue;
            }

            break;
        }
    }

    // ============================================================ directives

    /// <summary>True when only whitespace separates this position from a line break.</summary>
    private bool AtLineStart()
    {
        for (int i = _pos - 1; i >= 0; i--)
        {
            if (_text[i] == '\n') return true;
            if (!char.IsWhiteSpace(_text[i])) return false;
        }
        return true;
    }

    private void SkipLine()
    {
        while (_pos < _text.Length && Current != '\n') _pos++;
        if (_pos < _text.Length) _pos++;
    }

    /// <summary>
    /// One directive, from its <c>#</c> to the end of the line.
    ///
    /// Every one of them is handled even inside a branch that is not being
    /// taken, because the nesting has to stay balanced either way -- but only
    /// <c>#if</c> and its relatives do anything there.
    /// </summary>
    private void Directive()
    {
        int start = _pos;
        _pos++;                                             // the '#'

        while (_pos < _text.Length && (Current == ' ' || Current == '\t')) _pos++;

        int nameStart = _pos;
        while (_pos < _text.Length && char.IsLetter(Current)) _pos++;
        string name = _text[nameStart.._pos];

        int argumentStart = _pos;
        while (_pos < _text.Length && Current != '\n') _pos++;
        string argument = _text[argumentStart.._pos].Trim();
        var span = SpanFrom(start);

        if (_pos < _text.Length) _pos++;                    // the newline

        switch (name)
        {
            case "if":
            {
                bool taken = !Skipping && Evaluate(argument, span);
                _conditions.Add((taken, taken, false, start));
                return;
            }

            case "elif":
            {
                if (!Close(span, "elif")) return;

                var current = _conditions[^1];
                if (current.SawElse)
                {
                    diagnostics.Error("SL0455", span, "'#elif' cannot follow '#else'");
                    return;
                }

                bool outer = _conditions.Count < 2 || _conditions[..^1].All(c => c.Active);
                bool taken = outer && !current.Taken && Evaluate(argument, span);
                _conditions[^1] = (taken, current.Taken || taken, false, current.Start);
                return;
            }

            case "else":
            {
                if (!Close(span, "else")) return;

                var current = _conditions[^1];
                if (current.SawElse)
                {
                    diagnostics.Error("SL0455", span, "this '#if' already has an '#else'");
                    return;
                }

                bool outer = _conditions.Count < 2 || _conditions[..^1].All(c => c.Active);
                _conditions[^1] = (outer && !current.Taken, true, true, current.Start);
                return;
            }

            case "endif":
                if (!Close(span, "endif")) return;
                _conditions.RemoveAt(_conditions.Count - 1);
                return;
        }

        // Everything below means nothing inside a branch that is not taken.
        if (Skipping) return;

        switch (name)
        {
            case "define":
            case "undef":
                if (_sawToken)
                {
                    diagnostics.Error("SL0456", span,
                        $"'#{name}' must come before the first declaration in the file, as in " +
                        "C#; a symbol that changed halfway down would make the lines above and " +
                        "below it disagree");
                    return;
                }

                if (!IsSymbol(argument))
                {
                    diagnostics.Error("SL0457", span,
                        $"'#{name}' takes one name, and '{argument}' is not one");
                    return;
                }

                if (name == "define") _symbols.Add(argument);
                else _symbols.Remove(argument);
                return;

            case "error":
                diagnostics.Error("SL0458", span,
                    argument.Length > 0 ? argument : "'#error'");
                return;

            case "warning":
                diagnostics.Warning("SL0459", span,
                    argument.Length > 0 ? argument : "'#warning'");
                return;

            // Both exist to be folded by an editor and mean nothing here.
            case "region":
            case "endregion":
                return;

            case "pragma":
                Pragma(argument, span);
                return;

            default:
                diagnostics.Error("SL0460", span,
                    $"'#{name}' is not a directive. Stainless has '#if', '#elif', '#else', " +
                    "'#endif', '#define', '#undef', '#error', '#warning', '#region', " +
                    "'#endregion' and '#pragma' -- and no macros, because a name always " +
                    "means itself");
                return;
        }
    }

    /// <summary>
    /// <c>#pragma comment(lib, "user32")</c>: the file names a library it needs,
    /// rather than every program that compiles it repeating <c>-l user32</c>.
    /// This is MSVC's spelling, and it is the only pragma there is.
    /// </summary>
    private void Pragma(string argument, SourceSpan span)
    {
        const string Prefix = "comment(lib,";

        string text = argument.Replace(" ", "").Replace("\t", "");
        if (!text.StartsWith(Prefix, StringComparison.Ordinal) ||
            !text.EndsWith(")", StringComparison.Ordinal))
        {
            diagnostics.Error("SL0483", span,
                "the only pragma is '#pragma comment(lib, \"name\")', which names a " +
                "library to link");
            return;
        }

        string name = text[Prefix.Length..^1];
        if (name.Length < 2 || name[0] != '"' || name[^1] != '"')
        {
            diagnostics.Error("SL0484", span,
                "the library name in '#pragma comment(lib, ...)' must be quoted");
            return;
        }

        name = name[1..^1];

        // MSVC is normally written with the extension and the linker is not, so
        // both spellings are accepted and one of them reaches the command line.
        if (name.EndsWith(".lib", StringComparison.OrdinalIgnoreCase)) name = name[..^4];

        if (name.Length == 0)
        {
            diagnostics.Error("SL0484", span,
                "'#pragma comment(lib, ...)' names no library");
            return;
        }

        if (!Libraries.Contains(name, StringComparer.Ordinal)) Libraries.Add(name);
    }

    /// <summary>Checks that a directive closing a branch has one to close.</summary>
    private bool Close(SourceSpan span, string name)
    {
        if (_conditions.Count > 0) return true;

        diagnostics.Error("SL0461", span, $"'#{name}' has no '#if' to close");
        return false;
    }

    private static bool IsSymbol(string text) =>
        text.Length > 0 &&
        (char.IsLetter(text[0]) || text[0] == '_') &&
        text.All(c => char.IsLetterOrDigit(c) || c == '_');

    // ============================================================ #if expressions

    /// <summary>
    /// Evaluates the condition of an <c>#if</c>.
    ///
    /// The grammar is C#'s and nothing more: a name, <c>true</c>, <c>false</c>,
    /// <c>!</c>, <c>&amp;&amp;</c>, <c>||</c> and parentheses. A name that was
    /// never defined is false, exactly as in C# and in C, so a condition may
    /// test for something this build has never heard of.
    /// </summary>
    private bool Evaluate(string text, SourceSpan span)
    {
        if (text.Length == 0)
        {
            diagnostics.Error("SL0462", span, "this directive needs a condition");
            return false;
        }

        int at = 0;
        bool value = Or(text, ref at, span);

        SkipSpace(text, ref at);
        if (at < text.Length)
            diagnostics.Error("SL0462", span,
                $"'{text[at..]}' is left over after the condition; an '#if' takes names, " +
                "'!', '&&', '||' and parentheses");

        return value;
    }

    private bool Or(string text, ref int at, SourceSpan span)
    {
        bool left = And(text, ref at, span);

        while (true)
        {
            SkipSpace(text, ref at);
            if (!Take(text, ref at, "||")) return left;

            // Both sides are evaluated: an error in the right one is worth
            // reporting even when the left has already decided the answer.
            bool right = And(text, ref at, span);
            left = left || right;
        }
    }

    private bool And(string text, ref int at, SourceSpan span)
    {
        bool left = Unary(text, ref at, span);

        while (true)
        {
            SkipSpace(text, ref at);
            if (!Take(text, ref at, "&&")) return left;

            bool right = Unary(text, ref at, span);
            left = left && right;
        }
    }

    private bool Unary(string text, ref int at, SourceSpan span)
    {
        SkipSpace(text, ref at);

        if (Take(text, ref at, "!")) return !Unary(text, ref at, span);

        if (Take(text, ref at, "("))
        {
            bool inner = Or(text, ref at, span);
            SkipSpace(text, ref at);
            if (!Take(text, ref at, ")"))
                diagnostics.Error("SL0462", span, "a '(' in this condition is never closed");
            return inner;
        }

        int start = at;
        while (at < text.Length && (char.IsLetterOrDigit(text[at]) || text[at] == '_')) at++;

        if (at == start)
        {
            diagnostics.Error("SL0462", span,
                $"expected a name in this condition, found '{text[start..]}'");
            at = text.Length;
            return false;
        }

        string name = text[start..at];
        return name switch
        {
            "true" => true,
            "false" => false,
            _ => _symbols.Contains(name),
        };
    }

    private static void SkipSpace(string text, ref int at)
    {
        while (at < text.Length && char.IsWhiteSpace(text[at])) at++;
    }

    private static bool Take(string text, ref int at, string token)
    {
        SkipSpace(text, ref at);
        if (!text.AsSpan(at).StartsWith(token)) return false;
        at += token.Length;
        return true;
    }

    private Token LexIdentifierOrKeyword(int start)
    {
        while (_pos < _text.Length && (char.IsLetterOrDigit(Current) || Current == '_')) _pos++;
        string text = _text[start.._pos];
        var kind = TokenKindExtensions.Keywords.TryGetValue(text, out var kw)
            ? kw
            : TokenKind.Identifier;
        object? value = kind switch
        {
            TokenKind.TrueKeyword => true,
            TokenKind.FalseKeyword => false,
            _ => null,
        };
        return new Token(kind, SpanFrom(start), text, value);
    }

    private Token LexNumber(int start)
    {
        int radix = 10;
        if (Current == '0' && (Peek(1) == 'x' || Peek(1) == 'X')) { radix = 16; _pos += 2; }
        else if (Current == '0' && (Peek(1) == 'b' || Peek(1) == 'B')) { radix = 2; _pos += 2; }

        var digits = new StringBuilder();
        bool isFloat = false;

        while (_pos < _text.Length)
        {
            char c = Current;
            if (c == '_') { _pos++; continue; }              // digit separators, as in C#
            if (IsDigitInRadix(c, radix)) { digits.Append(c); _pos++; continue; }

            // A '.' joins the number only when a digit follows, which keeps
            // member access on a literal available later.
            if (radix == 10 && c == '.' && !isFloat && char.IsAsciiDigit(Peek(1)))
            {
                isFloat = true;
                digits.Append(c);
                _pos++;
                continue;
            }

            bool exponentFollows = char.IsAsciiDigit(Peek(1))
                || ((Peek(1) == '+' || Peek(1) == '-') && char.IsAsciiDigit(Peek(2)));
            if (radix == 10 && (c == 'e' || c == 'E') && exponentFollows)
            {
                isFloat = true;
                digits.Append(c);
                _pos++;
                if (Current is '+' or '-') { digits.Append(Current); _pos++; }
                continue;
            }

            break;
        }

        var suffix = new StringBuilder();
        while (_pos < _text.Length && "uUlLfFdD".Contains(Current))
        {
            suffix.Append(char.ToLowerInvariant(Current));
            _pos++;
        }
        if (suffix.ToString() is "f" or "d") isFloat = true;

        string raw = digits.ToString();
        var span = SpanFrom(start);
        string text = _text[start.._pos];

        if (raw.Length == 0)
        {
            diagnostics.Error("SL0003", span, "numeric literal has no digits");
            return new Token(TokenKind.IntLiteral, span, text, 0UL);
        }

        if (isFloat)
        {
            if (!double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out double d))
            {
                diagnostics.Error("SL0004", span, $"{raw} is not a valid floating-point literal");
                d = 0;
            }
            return new Token(TokenKind.FloatLiteral, span, text, d);
        }

        try
        {
            ulong value = radix == 10
                ? ulong.Parse(raw, CultureInfo.InvariantCulture)
                : Convert.ToUInt64(raw, radix);
            return new Token(TokenKind.IntLiteral, span, text, value);
        }
        catch (Exception e) when (e is OverflowException or FormatException or ArgumentException)
        {
            diagnostics.Error("SL0005", span, $"integer literal {raw} does not fit in 64 bits");
            return new Token(TokenKind.IntLiteral, span, text, 0UL);
        }
    }

    private static bool IsDigitInRadix(char c, int radix) => radix switch
    {
        2 => c is '0' or '1',
        16 => char.IsAsciiHexDigit(c),
        _ => char.IsAsciiDigit(c),
    };

    private Token LexString(int start)
    {
        _pos++;                                             // opening quote
        var sb = new StringBuilder();
        while (true)
        {
            if (_pos >= _text.Length || Current == '\n')
            {
                diagnostics.Error("SL0006", SpanFrom(start), "unterminated string literal");
                break;
            }
            if (Current == '"') { _pos++; break; }
            if (Current != '\\') { sb.Append(_text[_pos++]); continue; }
            sb.Append(char.ConvertFromUtf32(ReadEscape()));
        }
        return new Token(TokenKind.StringLiteral, SpanFrom(start), _text[start.._pos], sb.ToString());
    }

    /// <summary>
    /// <c>$"a {b} c"</c>.
    ///
    /// The holes are lexed here, in place, rather than by a second lexer over a
    /// substring: this one is already walking the text, so every token inside a
    /// hole gets its real position for free and a diagnostic about one points at
    /// the source rather than at a copy of it.
    ///
    /// The token carries the pieces as its value -- literal text and, for each
    /// hole, the tokens it lexed -- and the parser turns each of those into an
    /// expression. Nothing about what a hole may contain is decided here.
    /// </summary>
    private Token LexInterpolatedString(int start)
    {
        _pos += 2;                                          // the '$' and the quote

        var segments = new List<InterpolationSegment>();
        var literal = new StringBuilder();

        while (true)
        {
            if (_pos >= _text.Length || Current == '\n')
            {
                diagnostics.Error("SL0006", SpanFrom(start), "unterminated string literal");
                break;
            }

            if (Current == '"') { _pos++; break; }

            // `{{` and `}}` are how a brace is written, as in C#. A lone `}` is
            // a mistake rather than a literal, because it is far more often the
            // end of a hole that was never opened.
            if (Current == '{' && _pos + 1 < _text.Length && _text[_pos + 1] == '{')
            {
                literal.Append('{');
                _pos += 2;
                continue;
            }

            if (Current == '}')
            {
                if (_pos + 1 < _text.Length && _text[_pos + 1] == '}')
                {
                    literal.Append('}');
                    _pos += 2;
                    continue;
                }

                diagnostics.Error("SL0554", SpanFrom(_pos),
                    "a '}' inside an interpolated string closes nothing; write '}}' for a " +
                    "literal brace");
                _pos++;
                continue;
            }

            if (Current == '{')
            {
                if (literal.Length > 0)
                {
                    segments.Add(InterpolationSegment.Text(literal.ToString()));
                    literal.Clear();
                }

                segments.Add(LexHole(start));
                continue;
            }

            if (Current != '\\') { literal.Append(_text[_pos++]); continue; }
            literal.Append(char.ConvertFromUtf32(ReadEscape()));
        }

        if (literal.Length > 0) segments.Add(InterpolationSegment.Text(literal.ToString()));

        return new Token(TokenKind.InterpolatedString, SpanFrom(start), _text[start.._pos], segments);
    }

    /// <summary>
    /// The tokens between one hole's braces.
    ///
    /// Depth is counted so that a hole may contain braces of its own, and the
    /// ordinary token loop does the reading -- so a string inside a hole is
    /// lexed as a string, and a `}` inside one does not end the hole.
    /// </summary>
    private InterpolationSegment LexHole(int outerStart)
    {
        int openedAt = _pos;
        _pos++;                                             // the '{'

        var tokens = new List<Token>();
        int depth = 1;

        while (true)
        {
            SkipTrivia();

            if (_pos >= _text.Length)
            {
                diagnostics.Error("SL0006", SpanFrom(outerStart), "unterminated string literal");
                break;
            }

            if (Current == '}')
            {
                depth--;
                if (depth == 0) { _pos++; break; }
            }
            else if (Current == '{')
            {
                depth++;
            }

            var token = Next();
            if (token.Kind == TokenKind.EndOfFile) break;
            tokens.Add(token);
        }

        if (tokens.Count == 0)
            diagnostics.Error("SL0555", SpanFrom(openedAt),
                "this interpolation is empty; '{}' has no value to write");

        tokens.Add(new Token(TokenKind.EndOfFile, SpanFrom(_pos), ""));
        return InterpolationSegment.Hole(tokens);
    }

    /// <summary>
    /// One Unicode scalar between quotes, carried as an int.
    ///
    /// Not one UTF-16 unit: the source is UTF-8 read into UTF-16, so an
    /// astral character arrives as a surrogate pair and taking the first half
    /// would be half a character. Which of char, char16 and char32 the literal
    /// ends up as is the binder's decision, and depends on which can hold the
    /// scalar in a single unit.
    /// </summary>
    private Token LexChar(int start)
    {
        _pos++;                                             // opening quote
        int value = 0;
        if (_pos < _text.Length && Current != '\'')
            value = Current == '\\' ? ReadEscape() : ReadScalar();

        if (_pos < _text.Length && Current == '\'') _pos++;
        else diagnostics.Error("SL0007", SpanFrom(start), "unterminated character literal");

        return new Token(TokenKind.CharLiteral, SpanFrom(start), _text[start.._pos], value);
    }

    /// <summary>One scalar of source text, joining a surrogate pair into one.</summary>
    private int ReadScalar()
    {
        char high = _text[_pos++];
        if (!char.IsHighSurrogate(high) || _pos >= _text.Length ||
            !char.IsLowSurrogate(_text[_pos]))
            return high;

        return char.ConvertToUtf32(high, _text[_pos++]);
    }

    /// <summary>
    /// The scalar an escape sequence stands for.
    ///
    /// <c>\\u</c> takes four hex digits and <c>\\U</c> eight, which is C's
    /// split and the only way to write a scalar above U+FFFF. Anything outside
    /// Unicode, a lone surrogate included, is reported and replaced with
    /// U+FFFD -- the same answer transcoding gives, so a malformed escape and
    /// malformed input mean the same thing downstream.
    /// </summary>
    private int ReadEscape()
    {
        int start = _pos;
        _pos++;                                             // backslash
        if (_pos >= _text.Length) return '\\';

        char c = _text[_pos++];
        switch (c)
        {
            case 'n': return '\n';
            case 't': return '\t';
            case 'r': return '\r';
            case '0': return '\0';
            case 'a': return '\a';
            case 'b': return '\b';
            case 'f': return '\f';
            case 'v': return '\v';
            case '\\': return '\\';
            case '"': return '"';
            case '\'': return '\'';
            case 'x':
            case 'u':
            case 'U':
            {
                int want = c switch { 'x' => 2, 'u' => 4, _ => 8 };
                int value = 0, count = 0;
                while (count < want && _pos < _text.Length && char.IsAsciiHexDigit(Current))
                {
                    value = value * 16 + HexValue(Current);
                    _pos++;
                    count++;
                }
                if (count == 0)
                    diagnostics.Error("SL0008", SpanFrom(start), $"escape \\{c} needs at least one hex digit");

                // \x is a byte and says nothing about Unicode; the other two
                // name a scalar, and there are values in that syntax which are
                // not one.
                if (c != 'x' && (value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF)))
                {
                    diagnostics.Error("SL0526", SpanFrom(start),
                        $"U+{value:X4} is not a Unicode scalar value, so \\{c} cannot name it; " +
                        "scalars stop at U+10FFFF and the surrogate range U+D800 to U+DFFF is " +
                        "reserved for UTF-16 pairs");
                    return 0xFFFD;
                }

                return value;
            }
            default:
                diagnostics.Error("SL0009", SpanFrom(start), $"unrecognized escape sequence \\{c}");
                return c;
        }
    }

    private static int HexValue(char c) =>
        c <= '9' ? c - '0' : (char.ToLowerInvariant(c) - 'a' + 10);

    private Token LexPunctuation(int start)
    {
        // Longest match wins, so '<<=' beats '<<' beats '<'.
        for (int len = MaxPunctuationLength; len >= 1; len--)
        {
            if (start + len > _text.Length) continue;
            if (Punctuation.TryGetValue(_text.Substring(start, len), out var kind))
            {
                _pos = start + len;
                return new Token(kind, SpanFrom(start), _text[start.._pos]);
            }
        }

        _pos++;
        diagnostics.Error("SL0001", SpanFrom(start), $"unexpected character '{_text[start]}'");
        return new Token(TokenKind.Bad, SpanFrom(start), _text[start.._pos]);
    }

    private static readonly Dictionary<string, TokenKind> Punctuation =
        Enum.GetValues<TokenKind>()
            .Select(k => (Kind: k, Text: k.FixedText()))
            .Where(p => p.Text is { Length: > 0 } t && !char.IsLetter(t[0]))
            .ToDictionary(p => p.Text!, p => p.Kind, StringComparer.Ordinal);

    private static readonly int MaxPunctuationLength = Punctuation.Keys.Max(k => k.Length);
}
