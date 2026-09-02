using System.Globalization;
using System.Text;
using Stainless.Source;

namespace Stainless.Syntax;

/// <summary>
/// Turns source text into a token stream. There is no preprocessor: what the
/// lexer sees is exactly what the programmer wrote.
/// </summary>
public sealed class Lexer(SourceText source, DiagnosticBag diagnostics)
{
    private readonly string _text = source.Text;
    private int _pos;

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
        return tokens;
    }

    private Token Next()
    {
        SkipTrivia();
        int start = _pos;

        if (_pos >= _text.Length)
            return new Token(TokenKind.EndOfFile, SpanFrom(start), "");

        char c = Current;
        if (char.IsLetter(c) || c == '_') return LexIdentifierOrKeyword(start);
        if (char.IsAsciiDigit(c)) return LexNumber(start);
        if (c == '"') return LexString(start);
        if (c == '\'') return LexChar(start);
        return LexPunctuation(start);
    }

    private void SkipTrivia()
    {
        while (_pos < _text.Length)
        {
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
            sb.Append(Current == '\\' ? ReadEscape() : _text[_pos++]);
        }
        return new Token(TokenKind.StringLiteral, SpanFrom(start), _text[start.._pos], sb.ToString());
    }

    private Token LexChar(int start)
    {
        _pos++;                                             // opening quote
        char value = '\0';
        if (_pos < _text.Length && Current != '\'')
            value = Current == '\\' ? ReadEscape() : _text[_pos++];

        if (_pos < _text.Length && Current == '\'') _pos++;
        else diagnostics.Error("SL0007", SpanFrom(start), "unterminated character literal");

        return new Token(TokenKind.CharLiteral, SpanFrom(start), _text[start.._pos], value);
    }

    private char ReadEscape()
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
            {
                int want = c == 'x' ? 2 : 4;
                int value = 0, count = 0;
                while (count < want && _pos < _text.Length && char.IsAsciiHexDigit(Current))
                {
                    value = value * 16 + HexValue(Current);
                    _pos++;
                    count++;
                }
                if (count == 0)
                    diagnostics.Error("SL0008", SpanFrom(start), $"escape \\{c} needs at least one hex digit");
                return (char)value;
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
