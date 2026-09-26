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
    /// The <c>///</c> lines collected since the last token, one per entry with
    /// the marker stripped. Handed to the next token and then cleared.
    /// </summary>
    private readonly List<string> _documentation = [];

    /// <summary>
    /// Where the run being collected starts and ends in the source, so that a
    /// <c>@tag</c> inside it can be reported where it was written rather than
    /// against the declaration below it.
    /// </summary>
    private int _documentationStart = -1;
    private int _documentationEnd = -1;

    /// <summary>
    /// Line breaks seen since the last <c>///</c> line. A run is contiguous, so
    /// two of these -- a blank line -- ends the run and the block belongs to
    /// nothing. One is the ordinary case: the newline that ended the last
    /// documentation line.
    /// </summary>
    private int _breaksSinceDoc;

    /// <summary>
    /// Libraries this file asked to link, from <c>#pragma comment(lib, "...")</c>.
    /// They reach the driver through the compilation unit, and from there the
    /// linker, exactly as a <c>-l</c> on the command line would.
    /// </summary>
    public List<string> Libraries { get; } = [];

    /// <summary>
    /// How many interpolation holes are open around the current position.
    ///
    /// A hole is lexed by recursing into the ordinary token loop, and a string
    /// in it may have holes of its own, so <c>$"{$"{$"{...</c> is the one
    /// construct that makes the lexer recurse. It is bounded by the same limit
    /// as the parser's nesting, for the same reason: see <see cref="Source.Recursion"/>.
    /// </summary>
    private int _holeDepth;

    /// <summary>
    /// True once the hole limit has been reported. Everything after that point
    /// is abandoned, so the parser is told not to add its own complaints about
    /// the tokens that are missing as a result.
    /// </summary>
    public bool TooDeep { get; private set; }

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

        // The '#endif' of a group open when the hole limit abandoned the text
        // was in the part that was never read.
        if (!TooDeep)
        {
            foreach (var open in _conditions)
                diagnostics.Error("SL0454", new SourceSpan(source, open.Start, open.Start + 3),
                    "this '#if' is never closed; add '#endif'");
        }

        return tokens;
    }

    private Token Next()
    {
        SkipTrivia();

        // Taken before the token is lexed and applied after, so that every path
        // out of Lex carries it without each one having to remember to.
        var documentation = TakeDocumentation();

        var token = _asm is AsmPosition.AfterWord or AsmPosition.AfterOperands &&
                    _pos < _text.Length && Current == '{'
            ? LexAsmBody(_pos)
            : Lex();

        FollowAsm(token);
        return documentation is not { } block
            ? token
            : token with { Documentation = block.Text, DocumentationSpan = block.Span };
    }

    // ============================================================ asm

    /// <summary>Where the lexer is relative to the last <c>asm</c> it read.</summary>
    private enum AsmPosition
    {
        /// <summary>Nowhere near one: a <c>{</c> is punctuation.</summary>
        None,

        /// <summary>Straight after the word, where either the operands or the body may start.</summary>
        AfterWord,

        /// <summary>Inside the parenthesised operands, which are ordinary tokens.</summary>
        InOperands,

        /// <summary>After the operands' closing parenthesis, where only the body may start.</summary>
        AfterOperands,
    }

    private AsmPosition _asm;

    /// <summary>
    /// Where the <c>asm</c> body that ran to the end of the file began, or null.
    /// The parser reads it to stay quiet about the constructs left open, which
    /// is all of them and all for the one reason already reported.
    /// </summary>
    public int? UnterminatedAsm { get; private set; }

    /// <summary>How many parentheses are open inside an <c>asm</c> statement's operands.</summary>
    private int _asmParentheses;

    /// <summary>
    /// Keeps track of whether the next <c>{</c> opens an assembly body.
    ///
    /// <para>
    /// This has to be the lexer's question rather than the parser's, because
    /// the body is not tokens: <c>mov rax, [rcx + 8] # load</c> is not
    /// Stainless, and a <c>#</c> in it is not even a character this language
    /// has. The whole file is tokenized before the parser runs, so by the time
    /// the parser could say "a body goes here" the text would already have been
    /// cut into the wrong pieces.
    /// </para>
    ///
    /// <para>
    /// So the shape is recognised here instead: the word, then optionally a
    /// parenthesised list lexed as ordinary tokens with its depth counted, then
    /// a <c>{</c>. Anything else leaves the lexer as it was, and the parser
    /// says what is missing. A <c>{</c>, <c>}</c> or <c>;</c> inside the
    /// operands gives up on the statement as well, so a <c>(</c> that is never
    /// closed cannot turn the rest of the file into assembly.
    /// </para>
    ///
    /// <para>
    /// It is why <c>asm</c> is a keyword and not a contextual word. The lexer
    /// cannot see statement position, so a method named <c>asm</c> would have
    /// its body read as assembly — <c>void asm(int x) { ... }</c> is exactly
    /// the shape above. No source in this repository used the word as a name.
    /// </para>
    /// </summary>
    private void FollowAsm(Token token)
    {
        switch (_asm)
        {
            case AsmPosition.None:
                if (token.Kind == TokenKind.AsmKeyword)
                    _asm = AsmPosition.AfterWord;
                return;

            case AsmPosition.AfterWord when token.Kind == TokenKind.OpenParen:
                _asm = AsmPosition.InOperands;
                _asmParentheses = 1;
                return;

            case AsmPosition.InOperands:
                switch (token.Kind)
                {
                    case TokenKind.OpenParen:
                        _asmParentheses++;
                        return;

                    case TokenKind.CloseParen:
                        if (--_asmParentheses == 0)
                            _asm = AsmPosition.AfterOperands;
                        return;

                    case TokenKind.OpenBrace or TokenKind.CloseBrace or TokenKind.Semicolon
                        or TokenKind.EndOfFile:
                        _asm = AsmPosition.None;
                        return;

                    default:
                        return;
                }

            default:
                // The body itself, or whatever stood where one should have.
                _asm = token.Kind == TokenKind.AsmKeyword ? AsmPosition.AfterWord : AsmPosition.None;
                return;
        }
    }

    /// <summary>
    /// The text between an <c>asm</c> statement's braces, as one token whose
    /// value is that text exactly as written — line breaks, indentation and
    /// comments included — and whose span runs from the <c>{</c> to the
    /// <c>}</c>.
    ///
    /// <para>
    /// Braces are counted wherever they are, comments included, so a block may
    /// hold one only with its partner: AVX-512's <c>{k1}</c> is fine, and a
    /// comment reading <c>// }</c> ends the block. Recognising comments here
    /// would mean knowing which syntax the target's assembler has — <c>#</c>
    /// starts one on x86 and is an immediate on ARM — and a rule that changed
    /// with <c>--target</c> would make the same file lex differently on two
    /// machines.
    /// </para>
    ///
    /// <para>
    /// Nothing inside is read as a directive either. The text is the
    /// assembler's, and a line beginning <c>#if</c> in it is an x86 comment
    /// rather than a condition; <c>#if</c> goes around the whole statement.
    /// </para>
    /// </summary>
    private Token LexAsmBody(int start)
    {
        _pos++;                                             // the '{'
        int depth = 1;

        while (_pos < _text.Length)
        {
            char c = _text[_pos++];
            if (c == '{')
            {
                depth++;
            }
            else if (c == '}' && --depth == 0)
            {
                string text = _text[(start + 1)..(_pos - 1)];
                return new Token(TokenKind.AsmBody, SpanFrom(start), _text[start.._pos], text);
            }
        }

        // The rest of the file was taken, which is the only reading a missing
        // brace allows; what follows is reported once, here, rather than as a
        // stream of complaints about declarations that were never lexed.
        UnterminatedAsm = start;
        diagnostics.Error("SL0713", new SourceSpan(source, start, start + 1),
            "this 'asm' block is never closed; its '}' is missing, so the rest of the file " +
            "was read as assembly. Braces inside the block are counted, comments included");

        return new Token(TokenKind.AsmBody, SpanFrom(start), _text[start.._pos], _text[(start + 1).._pos]);
    }

    private Token Lex()
    {
        int start = _pos;

        if (_pos >= _text.Length)
            return new Token(TokenKind.EndOfFile, SpanFrom(start), "");

        _sawToken = true;
        char c = Current;
        if (char.IsLetter(c) || c == '_') return LexIdentifierOrKeyword(start);
        if (c == '@' && (char.IsLetter(Peek(1)) || Peek(1) == '_')) return LexVerbatimIdentifier(start);
        if (char.IsAsciiDigit(c)) return LexNumber(start);
        if (c is '"' or '$' or '@' && LexStringLiteral(start) is { } text) return text;
        if (c == '\'') return LexChar(start);
        return LexPunctuation(start);
    }

    /// <summary>
    /// <c>@class</c>: a keyword used as a name, as in C#. The token is an
    /// identifier whose text is the name without the <c>@</c>, so the symbol,
    /// its mangled name and anything exported under it are the bare word.
    /// </summary>
    private Token LexVerbatimIdentifier(int start)
    {
        _pos++;                                             // the '@'
        int nameStart = _pos;
        while (_pos < _text.Length && (char.IsLetterOrDigit(Current) || Current == '_')) _pos++;
        return new Token(TokenKind.Identifier, SpanFrom(start), _text[nameStart.._pos])
        {
            IsVerbatim = true,
        };
    }

    /// <summary>
    /// The documentation collected since the last token, or null. Clears it, so
    /// a block reaches exactly one token.
    /// </summary>
    private (string Text, SourceSpan Span)? TakeDocumentation()
    {
        if (_documentation.Count == 0) return null;

        string text = string.Join("\n", _documentation);
        var span = new SourceSpan(source, _documentationStart, _documentationEnd);

        _documentation.Clear();
        _documentationStart = -1;
        _documentationEnd = -1;
        return (text, span);
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
            if (char.IsWhiteSpace(c))
            {
                // A blank line between a block and what follows breaks the run,
                // so the block is documentation of nothing and is dropped.
                if (c == '\n' && ++_breaksSinceDoc > 1) _documentation.Clear();
                _pos++;
                continue;
            }

            if (c == '/' && Peek(1) == '/')
            {
                // Three slashes and not four: '////' is a rule of slashes
                // somebody drew, and reading it as prose would put a line of
                // punctuation in the middle of a description.
                bool isDoc = Peek(2) == '/' && Peek(3) != '/';

                int lineStart = _pos;
                int from = _pos + (isDoc ? 3 : 2);
                while (_pos < _text.Length && Current != '\n') _pos++;

                if (isDoc)
                {
                    if (_documentation.Count == 0) _documentationStart = lineStart;
                    _documentationEnd = _pos;

                    // One leading space is the marker's, not the text's, so
                    // '/// x' is "x" and '///     x' keeps its indent.
                    string line = _text[from.._pos].TrimEnd('\r');
                    if (line.StartsWith(' ')) line = line[1..];

                    _documentation.Add(line);
                    _breaksSinceDoc = 0;
                }
                else
                {
                    // An ordinary comment between a block and a declaration
                    // separates the two, so the block documents nothing.
                    _documentation.Clear();
                }
                continue;
            }

            if (c == '/' && Peek(1) == '*')
            {
                _documentation.Clear();
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
        // `f` makes a `float` and `d` a `double`, as in C#. A hex literal
        // cannot reach here with either, since both are digits there; a binary
        // one can, and has no floating-point form to be given.
        //
        // Anything else is reported rather than ignored. The whole point of a
        // suffix is to say something the digits cannot, so one that is not a
        // suffix is a typo that would otherwise mean whatever the digits meant.
        string suffixText = suffix.ToString();
        bool isSingle = false;

        if (suffixText is not ("" or "u" or "l" or "ul" or "lu" or "f" or "d"))
            diagnostics.Error("SL0004", SpanFrom(start),
                $"'{suffixText}' is not a suffix a number can take; they are 'u', 'l', 'ul', " +
                "'f' for a float and 'd' for a double");
        else if (suffixText is "f" or "d")
        {
            if (radix == 10) { isFloat = true; isSingle = suffixText == "f"; }
            else
                diagnostics.Error("SL0004", SpanFrom(start),
                    $"a binary literal is an integer, so it cannot take the '{suffixText}' " +
                    "suffix of a floating-point one");
        }

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
            // A `float` literal is parsed as one rather than as a rounded
            // double, so the value is the nearest float to what was written.
            if (isSingle)
            {
                if (!float.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out float f))
                {
                    diagnostics.Error("SL0004", span, $"{raw} is not a valid floating-point literal");
                    f = 0;
                }
                return new Token(TokenKind.FloatLiteral, span, text, f);
            }

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

    // ============================================================ strings

    /// <summary>What a string's body is written in, which decides what a backslash and a line break mean.</summary>
    private enum Quoting
    {
        /// <summary><c>"..."</c>: escapes, and one line.</summary>
        Regular,

        /// <summary><c>@"..."</c>: no escapes, <c>""</c> for a quote, and any number of lines.</summary>
        Verbatim,

        /// <summary><c>"""..."""</c>: nothing is special but a run of quotes as long as the opening one.</summary>
        Raw,
    }

    /// <summary>
    /// Any string literal starting here, or null when the <c>$</c> or <c>@</c>
    /// here starts none.
    ///
    /// The forms are C#'s: <c>"..."</c>, <c>@"..."</c> and <c>"""..."""</c>,
    /// each with a <c>$</c> for holes, and each but the interpolated ones with
    /// a <c>u8</c> after it for bytes rather than a String.
    /// </summary>
    private Token? LexStringLiteral(int start)
    {
        int dollars = 0;
        while (Peek(dollars) == '$') dollars++;

        int at = dollars;
        bool verbatim = false;
        if (dollars == 0 && Peek(0) == '@' && Peek(1) == '$')
        {
            // `@$"..."`, which C# accepts as well as `$@"..."`.
            verbatim = true;
            dollars = 1;
            at = 2;
        }
        else if (Peek(at) == '@')
        {
            verbatim = true;
            at++;
        }

        if (Peek(at) != '"') return null;

        int quotes = 0;
        while (Peek(at + quotes) == '"') quotes++;

        Token token;
        if (!verbatim && quotes >= 3)
        {
            token = LexRawString(start, at, dollars);
        }
        else
        {
            if (dollars > 1)
                diagnostics.Error("SL0751", new SourceSpan(source, start, start + at),
                    "more than one '$' sets how many braces open a hole, and only a raw string " +
                    "has holes that need it; write one '$', or open the string with '\"\"\"'");

            token = LexQuotedString(start, at, verbatim ? Quoting.Verbatim : Quoting.Regular, dollars > 0);
        }

        return WithUtf8Suffix(start, token);
    }

    /// <summary>
    /// <c>"..."u8</c>: the literal's bytes. The suffix is part of the token, as
    /// a number's is, so nothing can come between the two.
    /// </summary>
    private Token WithUtf8Suffix(int start, Token token)
    {
        if (Current is not ('u' or 'U') || Peek(1) != '8' ||
            char.IsLetterOrDigit(Peek(2)) || Peek(2) == '_')
            return token;

        _pos += 2;
        if (token.Kind == TokenKind.InterpolatedString)
        {
            diagnostics.Error("SL0752", SpanFrom(start),
                "an interpolated string is built when it runs, and 'u8' names bytes that are " +
                "fixed when it compiles; build the String and call 'ToBytes()' on it");
            return token with { Span = SpanFrom(start), Text = _text[start.._pos] };
        }

        return new Token(TokenKind.Utf8StringLiteral, SpanFrom(start), _text[start.._pos], token.Value);
    }

    /// <summary>
    /// <c>"..."</c> and <c>@"..."</c>, with or without holes.
    ///
    /// The holes are lexed here, in place, rather than by a second lexer over a
    /// substring: this one is already walking the text, so every token inside a
    /// hole gets its real position for free and a diagnostic about one points at
    /// the source rather than at a copy of it.
    ///
    /// An interpolated string's token carries the pieces as its value -- literal
    /// text and, for each hole, the tokens it lexed -- and the parser turns each
    /// of those into an expression. Nothing about what a hole may contain is
    /// decided here.
    /// </summary>
    private Token LexQuotedString(int start, int prefix, Quoting quoting, bool interpolated)
    {
        _pos = start + prefix + 1;                          // the prefix and the quote

        bool verbatim = quoting == Quoting.Verbatim;
        var segments = new List<InterpolationSegment>();
        var literal = new StringBuilder();

        while (true)
        {
            if (_pos >= _text.Length || (!verbatim && Current == '\n'))
            {
                if (!TooDeep)
                    diagnostics.Error("SL0006", SpanFrom(start), "unterminated string literal");
                break;
            }

            char c = Current;
            if (c == '"')
            {
                if (verbatim && Peek(1) == '"')
                {
                    literal.Append('"');
                    _pos += 2;
                    continue;
                }

                _pos++;
                break;
            }

            // `{{` and `}}` are how a brace is written, as in C#. A lone `}` is
            // a mistake rather than a literal, because it is far more often the
            // end of a hole that was never opened.
            if (interpolated && c is '{' or '}')
            {
                if (Peek(1) == c)
                {
                    literal.Append(c);
                    _pos += 2;
                    continue;
                }

                if (c == '}')
                {
                    diagnostics.Error("SL0554", SpanFrom(_pos),
                        "a '}' inside an interpolated string closes nothing; write '}}' for a " +
                        "literal brace");
                    _pos++;
                    continue;
                }

                FlushLiteral(literal, segments);
                segments.Add(LexHole(start, 1, quoting));
                continue;
            }

            // A line break is one '\n' however the file was saved, so the
            // same source gives the same String on every checkout.
            if (verbatim && c == '\r' && Peek(1) == '\n')
            {
                _pos++;
                continue;
            }

            if (!verbatim && c == '\\')
            {
                literal.Append(char.ConvertFromUtf32(ReadEscape()));
                continue;
            }

            literal.Append(c);
            _pos++;
        }

        if (!interpolated)
            return new Token(TokenKind.StringLiteral, SpanFrom(start), _text[start.._pos], literal.ToString());

        FlushLiteral(literal, segments);
        return new Token(TokenKind.InterpolatedString, SpanFrom(start), _text[start.._pos], segments);
    }

    private static void FlushLiteral(StringBuilder literal, List<InterpolationSegment> segments)
    {
        if (literal.Length == 0) return;
        segments.Add(InterpolationSegment.Text(literal.ToString()));
        literal.Clear();
    }

    /// <summary>How many of <paramref name="c"/> stand in a row from the current position.</summary>
    private int CountRun(char c)
    {
        int run = 0;
        while (_pos + run < _text.Length && _text[_pos + run] == c) run++;
        return run;
    }

    /// <summary>
    /// Literal text of a raw string, with where in the source each character
    /// came from -- which is what lets a complaint about one line's
    /// indentation point at that line.
    /// </summary>
    private sealed class RawText
    {
        public readonly StringBuilder Text = new();
        public readonly List<int> Positions = [];

        public void Append(char c, int position)
        {
            Text.Append(c);
            Positions.Add(position);
        }

        public void Remove(int from, int count)
        {
            Text.Remove(from, count);
            Positions.RemoveRange(from, count);
        }
    }

    /// <summary>
    /// <c>"""..."""</c>, and with one or more <c>$</c> in front of it.
    ///
    /// The opening run of quotes is the delimiter, however long, and only a run
    /// exactly that long closes it, so content may hold any shorter run. The
    /// number of <c>$</c> is how many braces open a hole in the same way: a
    /// shorter run of braces is text.
    ///
    /// On one line the content is what stands between the quotes. Across
    /// several, the lines holding the quotes are not content, and the closing
    /// line's indentation is taken off every line -- see <see cref="TrimRawLines"/>.
    /// </summary>
    private Token LexRawString(int start, int prefix, int dollars)
    {
        _pos = start + prefix;
        int quotes = CountRun('"');
        _pos += quotes;

        var pieces = new List<(RawText? Text, InterpolationSegment? Hole)>();
        var text = new RawText();
        bool closed = false;
        bool multiLine = false;

        while (_pos < _text.Length)
        {
            char c = Current;
            if (c == '"')
            {
                int run = CountRun('"');
                if (run < quotes)
                {
                    for (int i = 0; i < run; i++) text.Append('"', _pos + i);
                    _pos += run;
                    continue;
                }

                if (run > quotes)
                    diagnostics.Error("SL0749", new SourceSpan(source, _pos, _pos + run),
                        $"this raw string opens with {quotes} quotes, so {run} in a row cannot be " +
                        $"part of it; open and close it with {run + 1}");

                _pos += run;
                closed = true;
                break;
            }

            if (c == '\r' && Peek(1) == '\n')
            {
                _pos++;
                continue;
            }

            if (c == '\n') multiLine = true;

            if (dollars > 0 && c is '{' or '}')
            {
                int run = CountRun(c);
                if (run < dollars)
                {
                    for (int i = 0; i < run; i++) text.Append(c, _pos + i);
                    _pos += run;
                    continue;
                }

                if (c == '}')
                {
                    diagnostics.Error("SL0750", new SourceSpan(source, _pos, _pos + run),
                        $"with {dollars} '$', {dollars} braces belong to a hole, so these {run} " +
                        "'}' close one that was never opened; start the string with " +
                        $"{run + 1} '$' to write them as text");
                    _pos += run;
                    continue;
                }

                // The last `dollars` of the run open the hole and the rest are
                // text, so a run is text and a hole at once only while the
                // text part is shorter than an opening.
                if (run >= 2 * dollars)
                    diagnostics.Error("SL0750", new SourceSpan(source, _pos, _pos + run),
                        $"with {dollars} '$', the last {dollars} of these {run} '{{' open a " +
                        $"hole and the rest are text, which only a run shorter than {dollars} " +
                        $"can be; start the string with {run / 2 + 1} '$'");

                int literalBraces = run - dollars;
                for (int i = 0; i < literalBraces; i++) text.Append('{', _pos + i);
                _pos += literalBraces;

                pieces.Add((text, null));
                text = new RawText();
                pieces.Add((null, LexHole(start, dollars, Quoting.Raw)));
                continue;
            }

            text.Append(c, _pos);
            _pos++;
        }

        pieces.Add((text, null));

        if (!closed && !TooDeep)
            diagnostics.Error("SL0006", SpanFrom(start),
                $"unterminated raw string literal; it ends at a run of {quotes} quotes");

        if (closed && multiLine) TrimRawLines(pieces, start);

        if (dollars == 0)
            return new Token(TokenKind.StringLiteral, SpanFrom(start), _text[start.._pos],
                             pieces[0].Text!.Text.ToString());

        var segments = new List<InterpolationSegment>();
        foreach (var (literal, hole) in pieces)
        {
            if (hole is not null) segments.Add(hole);
            else if (literal!.Text.Length > 0) segments.Add(InterpolationSegment.Text(literal.Text.ToString()));
        }

        return new Token(TokenKind.InterpolatedString, SpanFrom(start), _text[start.._pos], segments);
    }

    /// <summary>
    /// A raw string across lines, reduced to its content, as C# does it.
    ///
    /// The opening quotes MUST end their line and the closing ones MUST start
    /// theirs, after nothing but whitespace. That whitespace is the string's
    /// indentation: every line of content MUST begin with exactly it, and it is
    /// taken off, so the literal can be indented with the code around it
    /// without the indentation becoming text. A line of nothing but whitespace
    /// is exempt, and is empty.
    /// </summary>
    private void TrimRawLines(List<(RawText? Text, InterpolationSegment? Hole)> pieces, int start)
    {
        // Text and holes alternate, and both ends are text, possibly empty.
        var first = pieces[0].Text!;
        var last = pieces[^1].Text!;

        string opening = first.Text.ToString();
        int firstBreak = opening.IndexOf('\n');
        if (firstBreak < 0 || !IsBlank(opening, 0, firstBreak))
        {
            int at = first.Positions.Count > 0 ? first.Positions[0] : start;
            diagnostics.Error("SL0746", new SourceSpan(source, at, at + 1),
                "a raw string that spans lines starts on the line after its opening quotes, " +
                "and nothing but whitespace may follow them");
            return;
        }

        first.Remove(0, firstBreak + 1);

        string closing = last.Text.ToString();
        int lastBreak = closing.LastIndexOf('\n');
        if (lastBreak < 0 || !IsBlank(closing, lastBreak + 1, closing.Length))
        {
            bool empty = pieces.Count == 1 && IsBlank(closing, 0, closing.Length);
            diagnostics.Error("SL0747", new SourceSpan(source, _pos - 1, _pos),
                empty
                    ? "a raw string that spans lines needs a line of content between its quotes"
                    : "the closing quotes of a raw string that spans lines stand on a line of " +
                      "their own, after nothing but whitespace");
            return;
        }

        string indent = closing[(lastBreak + 1)..];
        last.Remove(lastBreak, closing.Length - lastBreak);

        bool reported = false;
        for (int p = 0; p < pieces.Count; p++)
        {
            if (pieces[p].Text is not { } piece) continue;

            string body = piece.Text.ToString();
            var trimmed = new StringBuilder();
            int lineBegin = 0;

            for (int line = 0; ; line++)
            {
                int lineEnd = body.IndexOf('\n', lineBegin);
                bool broken = lineEnd >= 0;
                if (!broken) lineEnd = body.Length;

                // Only the first piece starts on a line of its own; the others
                // start after a hole, partway along one.
                bool atLineStart = line > 0 || p == 0;
                bool wholeLine = broken || p == pieces.Count - 1;
                string content = body[lineBegin..lineEnd];

                if (!atLineStart)
                {
                    trimmed.Append(content);
                }
                else if (content.StartsWith(indent, StringComparison.Ordinal))
                {
                    trimmed.Append(content, indent.Length, content.Length - indent.Length);
                }
                else if (wholeLine && IsBlank(content, 0, content.Length))
                {
                    // Shorter than the indentation, or other whitespace: empty.
                }
                else
                {
                    trimmed.Append(content);
                    if (!reported)
                    {
                        reported = true;
                        int at = lineBegin < piece.Positions.Count ? piece.Positions[lineBegin] : start;
                        diagnostics.Error("SL0748", new SourceSpan(source, at, at + 1),
                            "this line of a raw string does not start with the whitespace its " +
                            "closing quotes are indented by, which is taken off every line; " +
                            "indent it at least as far, with the same characters");
                    }
                }

                if (!broken) break;
                trimmed.Append('\n');
                lineBegin = lineEnd + 1;
            }

            piece.Text.Clear().Append(trimmed);
        }
    }

    private static bool IsBlank(string text, int from, int to)
    {
        for (int i = from; i < to; i++)
        {
            if (text[i] is not (' ' or '\t' or '\r' or '\v' or '\f')) return false;
        }

        return true;
    }

    /// <summary>
    /// The tokens between one hole's braces.
    ///
    /// Depth is counted so that a hole may contain braces of its own, and the
    /// ordinary token loop does the reading -- so a string inside a hole is
    /// lexed as a string, and a `}` inside one does not end the hole.
    /// </summary>
    private InterpolationSegment LexHole(int outerStart, int braces, Quoting quoting)
    {
        int openedAt = _pos;

        if (_holeDepth == Source.Recursion.MaxDepth)
        {
            if (!TooDeep)
            {
                TooDeep = true;
                diagnostics.Error("SL0108", new SourceSpan(source, openedAt, openedAt + 1),
                    $"this is nested more than {Source.Recursion.MaxDepth} levels deep, which " +
                    "is past what can be compiled; the usual cause is generated source, and " +
                    "the fix is to give the inner part a name of its own");
            }

            // As the parser does: nothing after this can be read usefully, and
            // going to the end lets every open string close without a message
            // of its own about being unterminated.
            _pos = _text.Length;
            return InterpolationSegment.Hole([new Token(TokenKind.EndOfFile, SpanFrom(_pos), "")]);
        }

        _holeDepth++;
        try { return LexHoleCore(outerStart, openedAt, braces, quoting); }
        finally { _holeDepth--; }
    }

    /// <summary>
    /// The hole's code, then its format if a <c>:</c> outside any bracket
    /// starts one.
    ///
    /// The <c>:</c> is found here rather than by the parser because what
    /// follows it is not code: <c>{when:yyyy-MM-dd}</c> would not lex. That is
    /// C#'s rule and its cost is C#'s too -- a <c>?:</c> in a hole has to be
    /// parenthesised, since its <c>:</c> would start the format.
    /// </summary>
    private InterpolationSegment LexHoleCore(int outerStart, int openedAt, int braces, Quoting quoting)
    {
        _pos += braces;

        var tokens = new List<Token>();
        int depth = 1;
        int grouping = 0;
        string? format = null;
        SourceSpan? formatSpan = null;

        while (true)
        {
            SkipTrivia();

            if (_pos >= _text.Length)
            {
                if (!TooDeep)
                    diagnostics.Error("SL0006", SpanFrom(outerStart), "unterminated string literal");
                break;
            }

            if (Current == '}' && depth == 1)
            {
                CloseHole(braces);
                break;
            }

            if (Current == ':' && depth == 1 && grouping == 0)
            {
                (format, formatSpan) = LexFormat(outerStart, quoting);
                if (Current == '}') CloseHole(braces);
                break;
            }

            if (Current == '{') depth++;
            else if (Current == '}') depth--;

            var token = Next();
            if (token.Kind == TokenKind.EndOfFile) break;

            switch (token.Kind)
            {
                case TokenKind.OpenParen or TokenKind.OpenBracket:
                    grouping++;
                    break;

                case TokenKind.CloseParen or TokenKind.CloseBracket when grouping > 0:
                    grouping--;
                    break;
            }

            tokens.Add(token);
        }

        if (tokens.Count == 0 && !TooDeep)
            diagnostics.Error("SL0555", SpanFrom(openedAt),
                "this interpolation is empty; '{}' has no value to write");

        tokens.Add(new Token(TokenKind.EndOfFile, SpanFrom(_pos), ""));
        return InterpolationSegment.Hole(tokens, format, formatSpan);
    }

    /// <summary>
    /// The text after a hole's <c>:</c>, up to the brace that ends the hole.
    /// It is one line, and in a quoted string it cannot hold the quote.
    /// </summary>
    private (string Format, SourceSpan Span) LexFormat(int outerStart, Quoting quoting)
    {
        int from = ++_pos;                                  // past the ':'
        while (_pos < _text.Length && Current is not ('}' or '\n') &&
               !(quoting != Quoting.Raw && Current == '"'))
            _pos++;

        if (Current != '}' && !TooDeep)
            diagnostics.Error("SL0006", SpanFrom(outerStart),
                "unterminated string literal; a hole's format runs to the '}' that closes it");

        return (_text[from.._pos].TrimEnd('\r'), new SourceSpan(source, from, _pos));
    }

    /// <summary>
    /// The braces that end a hole: as many as opened it. Only a raw string
    /// with more than one <c>$</c> asks for more than one.
    /// </summary>
    private void CloseHole(int braces)
    {
        int run = CountRun('}');
        if (run >= braces)
        {
            _pos += braces;
            return;
        }

        diagnostics.Error("SL0750", new SourceSpan(source, _pos, _pos + run),
            $"this hole was opened with {braces} braces and is closed with {run}; a hole " +
            "closes with as many as opened it");
        _pos += run;
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
        else if (_pos < _text.Length)
            // A character literal is exactly one scalar, and none is not one.
            // Taken quietly it became a zero: something that compiles, runs,
            // and holds a value nobody wrote.
            diagnostics.Error("SL0010", SpanFrom(start),
                "a character literal holds one scalar, and this one is empty; write '\\0' for " +
                "the zero character, or \"\" for an empty string");

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
                // `\x` is a byte, written in one digit or two as in C. The
                // other two name a scalar and are fixed width, so a short one
                // is a mistake rather than a smaller number: `\u12` took the
                // two digits it found, made U+0012, and said nothing about the
                // four that were meant.
                if (count == 0)
                    diagnostics.Error("SL0008", SpanFrom(start),
                        $"escape \\{c} needs at least one hex digit");
                else if (c != 'x' && count < want)
                    diagnostics.Error("SL0008", SpanFrom(start),
                        $"escape \\{c} takes exactly {want} hex digits and this one has {count}; " +
                        "'\\u' names a scalar up to U+FFFF and '\\U' one above it");

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
