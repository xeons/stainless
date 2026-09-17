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

// Stainless, lexed one line at a time.
//
// **Not the compiler's lexer, and deliberately not.** That one reads a whole
// file, reports errors, resolves `#if`, collects documentation and produces
// tokens a parser can consume. An editor wants none of that. It wants to know
// what colour the bytes on *one* line are, thirty times a second, while the
// text underneath it is half-written and frequently not valid at all.
//
// So this is a different tool with a different contract:
//
//   - **A line at a time, with the state carried between them.** What a line
//     means depends on the one above it only through whether a block comment
//     or a string was left open, which is one small value. Editing line 400 of
//     a 4000-line file rescans line 400, and stops there the moment the state
//     coming out matches what it was before.
//   - **Nothing is ever an error.** An unterminated string is a string that
//     reaches the end of the line, a stray byte is one `Unknown` token. A lexer
//     that refused half-typed input would be a lexer that refused everything,
//     because everything is half-typed while it is being typed.
//   - **Positions are byte offsets**, as everywhere a `String` is involved
//     here, and every offset this produces lands on a character boundary.
module Ide.Lang;

import Standard.Text;
import Standard.Collections;

// =================================================================== tokens

/// What a run of bytes is, to the degree one line can say.
///
/// **Coarser than the compiler's `TokenKind`**, because this exists to choose a
/// colour rather than to build a tree: every operator is one kind here, where
/// the parser needs to tell `+` from `+=`. Finer in one direction, though --
/// `DocComment` is separate from `Comment`, and `TypeName` from `Identifier`,
/// because those are distinctions a reader wants and a parser does not.
public enum TokenKind
{
    /// Spaces and tabs. Produced rather than skipped, so that the tokens of a
    /// line tile it exactly and a painter can walk them without tracking gaps.
    Whitespace,
    /// `// like this`, to the end of the line.
    Comment,
    /// `/// like this`, which is documentation, and worth its own colour.
    DocComment,
    /// `/* ... */`, which may not end on the line it began.
    BlockComment,
    /// A reserved word.
    Keyword,
    /// A word that is a keyword only where the parser is already expecting one
    /// -- `event`, `closure`, `get`, `set`, `value`. An ordinary identifier
    /// anywhere else, and the editor colours it as a keyword anyway, which is
    /// what every editor does with these and what a reader expects.
    ContextualKeyword,
    /// A built-in type name: `int`, `double`, `String`.
    TypeName,
    /// Anything else that is a word.
    Identifier,
    /// A number, with whatever prefix and suffix it carried.
    Number,
    /// `"text"`, or the text part of `$"text {hole}"`.
    Text,
    /// `'c'`.
    Character,
    /// `#if` and its relatives, which are only directives at the start of a
    /// line.
    Directive,
    /// `[Guid("...")]` -- the brackets and the name, not what is inside.
    Attribute,
    /// One or more bytes of punctuation that mean something: `+`, `=>`, `::`.
    Operator,
    /// `(`, `)`, `{`, `}`, `[`, `]`, `;`, `,` -- punctuation that groups or
    /// separates rather than computing. Apart from `Operator` because bracket
    /// matching needs to find these and nothing else.
    Bracket,
    /// A byte that is none of the above. Never an error, because an editor has
    /// no one to report an error to.
    Unknown,
}

/// One run of bytes on one line.
///
/// A struct, and small on purpose: a file of any size is a great many of these,
/// and they are rebuilt whenever a line changes.
public struct Token
{
    public TokenKind Kind;
    /// Byte offset from the start of the line.
    public nuint Start;
    public nuint Length;

    public nuint End => Start + Length;

    public static Token Of(TokenKind kind, nuint start, nuint length)
    {
        Token token;
        token.Kind = kind;
        token.Start = start;
        token.Length = length;
        return token;
    }
}

/// What one line leaves open for the next.
///
/// **The whole of the dependency between lines.** Everything else a line means
/// is decided within it, which is what makes rescanning one line enough: if the
/// state coming out of a line is what it was before the edit, no line below it
/// can have changed and the editor stops there.
public enum ScanState
{
    /// Nothing is open. The ordinary case, and what a file starts in.
    Normal,
    /// A `/*` is open and has not been closed.
    InBlockComment,
}

// ================================================================== scanner

/// Turns one line into tokens.
///
/// Holds the keyword tables, so one of these is made per editor rather than per
/// line. They are instance fields rather than statics because a static holding
/// a `Dictionary` is shared mutable state the compiler is right to warn about,
/// and because a scanner is a thing an editor owns anyway.
public class Scanner
{
    Dictionary<String, bool> _keywords;
    Dictionary<String, bool> _contextual;
    Dictionary<String, bool> _primitives;

    public Scanner()
    {
        _keywords = new Dictionary<String, bool>();
        _contextual = new Dictionary<String, bool>();
        _primitives = new Dictionary<String, bool>();
        Fill();
    }

    /// The reserved words, taken from the compiler's own table.
    ///
    /// **Written out rather than read from anywhere.** The compiler is a C#
    /// program and its keyword list is a C# enum, so there is no file for this
    /// to load; what keeps the two together is the test that lexes a sample and
    /// checks every word the compiler calls a keyword arrives as one here.
    void Fill()
    {
        String[] reserved = [
            "abstract", "alignof", "as", "asm", "attribute", "base", "break", "case",
            "class", "com", "const", "continue", "default", "delegate", "do",
            "else", "embed", "enum", "export", "extern", "false", "for", "foreach",
            "goto", "if", "iidof", "import", "in", "interface", "is", "module",
            "nameof", "new", "null", "offsetof", "operator", "override",
            "parallel", "private", "protected", "public", "readonly", "ref",
            "return", "sealed", "sizeof", "spawn", "static", "struct",
            "switch", "this", "threadsafe", "true", "try", "typeof", "union",
            "using", "var", "variant", "virtual", "weak", "where", "while",
        ];
        foreach (var word in reserved)
            _keywords.Set(word, true);

        // Keywords only where one is already expected, and ordinary
        // identifiers everywhere else. Coloured as keywords regardless, which
        // is what C# editors do with `value` and `yield` for the same reason:
        // a reader recognises the word, and telling them apart would need the
        // parser this does not have.
        String[] soft = ["closure", "event", "get", "set", "value"];
        foreach (var word in soft)
            _contextual.Set(word, true);

        // The built-in types. `Keyword` in the compiler's table -- these are
        // reserved words -- but a separate colour here, because a type is the
        // thing a reader is most often scanning for.
        String[] built = [
            "bool", "byte", "char", "char16", "char32", "double", "float",
            "int", "long", "nint", "nuint", "sbyte", "short", "uint", "ulong",
            "ushort", "void",
        ];
        foreach (var word in built)
            _primitives.Set(word, true);
    }

    /// Lexes one line, appending to `into`, and answers what it leaves open.
    ///
    /// `into` is cleared first. The tokens tile the line exactly -- every byte
    /// belongs to one -- so a painter can walk them end to end without checking
    /// for gaps, and a lookup by column is a scan rather than a search.
    public ScanState ScanLine(String line, ScanState entry, List<Token> into)
    {
        into.Clear();

        nuint size = line.ByteLength();
        nuint at = 0u;
        var state = entry;

        // A line that arrives inside a block comment is one until the `*/`.
        if (state == ScanState.InBlockComment)
        {
            nuint close = FindBlockEnd(line, 0u);
            if (close == NotClosed)
            {
                if (size > 0u)
                    into.Add(Token.Of(TokenKind.BlockComment, 0u, size));
                return ScanState.InBlockComment;
            }
            into.Add(Token.Of(TokenKind.BlockComment, 0u, close));
            at = close;
            state = ScanState.Normal;
        }

        // A directive is one only at the start of a line, so the test is made
        // once here rather than at every `#`.
        if (at == 0u)
        {
            nuint first = SkipSpaces(line, 0u);
            if (first < size && line.ByteAt(first) == (byte)'#')
            {
                if (first > 0u)
                    into.Add(Token.Of(TokenKind.Whitespace, 0u, first));
                into.Add(Token.Of(TokenKind.Directive, first, size - first));
                return state;
            }
        }

        while (at < size)
        {
            byte c = line.ByteAt(at);

            if (c == (byte)' ' || c == (byte)'\t')
            {
                nuint run = SkipSpaces(line, at);
                into.Add(Token.Of(TokenKind.Whitespace, at, run - at));
                at = run;
                continue;
            }

            if (c == (byte)'/' && at + 1u < size)
            {
                byte next = line.ByteAt(at + 1u);
                if (next == (byte)'/')
                {
                    // `///` is documentation; `//` is a note. Three slashes and
                    // not four: `////` is a ruled line, and the compiler treats
                    // it as an ordinary comment.
                    bool doc = at + 2u < size && line.ByteAt(at + 2u) == (byte)'/'
                            && !(at + 3u < size && line.ByteAt(at + 3u) == (byte)'/');
                    into.Add(Token.Of(doc ? TokenKind.DocComment : TokenKind.Comment,
                                      at, size - at));
                    return state;
                }
                if (next == (byte)'*')
                {
                    nuint close = FindBlockEnd(line, at + 2u);
                    if (close == NotClosed)
                    {
                        into.Add(Token.Of(TokenKind.BlockComment, at, size - at));
                        return ScanState.InBlockComment;
                    }
                    into.Add(Token.Of(TokenKind.BlockComment, at, close - at));
                    at = close;
                    continue;
                }
            }

            if (c == (byte)'"')
            {
                at = ScanText(line, at, into);
                continue;
            }

            if (c == (byte)'$' && at + 1u < size && line.ByteAt(at + 1u) == (byte)'"')
            {
                // The `$` belongs to the string, and what is inside the holes is
                // lexed as ordinary code by `ScanText`.
                into.Add(Token.Of(TokenKind.Text, at, 1u));
                at = ScanText(line, at + 1u, into);
                continue;
            }

            if (c == (byte)'\'')
            {
                at = ScanCharacter(line, at, into);
                continue;
            }

            if (IsDigit(c))
            {
                at = ScanNumber(line, at, into);
                continue;
            }

            if (IsWordStart(c))
            {
                at = ScanWord(line, at, into);
                continue;
            }

            if (IsBracket(c))
            {
                into.Add(Token.Of(TokenKind.Bracket, at, 1u));
                at++;
                continue;
            }

            if (IsOperator(c))
            {
                nuint run = at;
                while (run < size && IsOperator(line.ByteAt(run)))
                    run++;
                into.Add(Token.Of(TokenKind.Operator, at, run - at));
                at = run;
                continue;
            }

            // Anything else: one byte, unknown, and on with the line. A
            // multi-byte character lands here as its lead byte followed by its
            // continuations, which is ugly and harmless -- nothing colours
            // `Unknown` differently, and a stray non-ASCII byte in code is
            // already a mistake the compiler will name.
            into.Add(Token.Of(TokenKind.Unknown, at, 1u));
            at++;
        }

        return state;
    }

    // ------------------------------------------------------------ the parts

    /// A word, and which of the three kinds of word it is.
    nuint ScanWord(String line, nuint at, List<Token> into)
    {
        nuint size = line.ByteLength();
        nuint run = at;
        while (run < size && IsWordPart(line.ByteAt(run)))
            run++;

        String word = line.Substring(at, run - at);
        var kind = TokenKind.Identifier;
        if (_primitives.ContainsKey(word))
        {
            kind = TokenKind.TypeName;
        }
        else if (_keywords.ContainsKey(word))
        {
            kind = TokenKind.Keyword;
        }
        else if (_contextual.ContainsKey(word))
        {
            kind = TokenKind.ContextualKeyword;
        }
        else if (LooksLikeAType(word))
        {
            kind = TokenKind.TypeName;
        }

        into.Add(Token.Of(kind, at, run - at));
        return run;
    }

    /// Whether a word is probably a type, on the evidence one line offers.
    ///
    /// **A convention, not an answer.** Knowing what `Foo` is needs the binder,
    /// and this has one line. What it has instead is the convention the whole
    /// of this codebase follows and C# before it: a type is `PascalCase` and
    /// nothing else is. It is wrong about a `public static` field and about a
    /// method called from nowhere, and both are wrong in the harmless
    /// direction -- a colour, not a diagnostic.
    ///
    /// This is the line the compiler service is on the other side of. When one
    /// exists, what it answers replaces this and the rule stays as the fallback
    /// for a file that has not been analysed yet.
    bool LooksLikeAType(String word)
    {
        if (word.ByteLength() < 2u)
            return false;
        byte first = word.ByteAt(0u);
        // `HWND` and `IO` are types; `MAX` may not be, but a word in capitals
        // is a constant either way, and the two want the same colour far more
        // often than they want different ones.
        return first >= (byte)'A' && first <= (byte)'Z';
    }

    /// A string literal, from its opening quote to its closing one or the end
    /// of the line -- whichever comes first, because an unterminated string is
    /// what every string looks like while it is being typed.
    ///
    /// **The holes of an interpolated string are lexed as code**, which is what
    /// makes `$"total: {Count(items)}"` read as the call it contains rather
    /// than as one undifferentiated run of text.
    nuint ScanText(String line, nuint at, List<Token> into)
    {
        nuint size = line.ByteLength();
        nuint run = at + 1u;
        nuint textStart = at;

        while (run < size)
        {
            byte c = line.ByteAt(run);

            if (c == (byte)'\\' && run + 1u < size)
            {
                run += 2u;
                continue;
            }

            if (c == (byte)'{')
            {
                // A doubled brace is one literal brace, not a hole.
                if (run + 1u < size && line.ByteAt(run + 1u) == (byte)'{')
                {
                    run += 2u;
                    continue;
                }
                into.Add(Token.Of(TokenKind.Text, textStart, run - textStart + 1u));
                run = ScanHole(line, run + 1u, into);
                textStart = run;
                continue;
            }

            if (c == (byte)'"')
            {
                into.Add(Token.Of(TokenKind.Text, textStart, run - textStart + 1u));
                return run + 1u;
            }

            run++;
        }

        if (run > textStart)
            into.Add(Token.Of(TokenKind.Text, textStart, run - textStart));
        return run;
    }

    /// What is between `{` and the `}` that closes it, lexed as code.
    ///
    /// The closing brace is left for the string to take, so that the braces are
    /// coloured as the string they belong to rather than as the code between
    /// them. A hole that is never closed simply runs to the end of the line.
    nuint ScanHole(String line, nuint at, List<Token> into)
    {
        nuint size = line.ByteLength();
        nuint run = at;
        nuint depth = 1u;

        while (run < size)
        {
            byte c = line.ByteAt(run);
            if (c == (byte)'{')
            {
                depth++;
            }
            else if (c == (byte)'}')
            {
                depth--;
                if (depth == 0u)
                    break;
            }
            run++;
        }

        // Lexed as its own little line, and the offsets shifted back on to this
        // one. Recursive, which a hole containing a string makes necessary and
        // which terminates because the inner text is strictly shorter.
        if (run > at)
        {
            var inner = new List<Token>();
            ScanLine(line.Substring(at, run - at), ScanState.Normal, inner);
            foreach (var token in inner)
            {
                into.Add(Token.Of(token.Kind, at + token.Start, token.Length));
            }
        }
        return run;
    }

    /// A character literal. Same shape as a string and a different colour, and
    /// the same tolerance of never being closed.
    nuint ScanCharacter(String line, nuint at, List<Token> into)
    {
        nuint size = line.ByteLength();
        nuint run = at + 1u;
        while (run < size)
        {
            byte c = line.ByteAt(run);
            if (c == (byte)'\\' && run + 1u < size)
            {
                run += 2u;
                continue;
            }
            if (c == (byte)'\'')
            {
                run++;
                break;
            }
            run++;
        }
        into.Add(Token.Of(TokenKind.Character, at, run - at));
        return run;
    }

    /// A number, with whatever prefix and suffix it carried.
    ///
    /// Deliberately loose: `0x1Fu`, `1_000`, `3.14e-2f` and `1.2.3` all come
    /// out as one `Number`. What an editor needs is where the number ends, and
    /// it ends where something that is plainly not part of one begins.
    nuint ScanNumber(String line, nuint at, List<Token> into)
    {
        nuint size = line.ByteLength();
        nuint run = at;

        while (run < size)
        {
            byte c = line.ByteAt(run);
            if (IsWordPart(c) || c == (byte)'.')
            {
                // `1..2` is a range, not a number with two points in it, and
                // `x.Count` after a number is a member access.
                if (c == (byte)'.' && run + 1u < size && !IsDigit(line.ByteAt(run + 1u)))
                {
                    break;
                }
                run++;
                continue;
            }
            // An exponent's sign is part of the number, and only there.
            if ((c == (byte)'+' || c == (byte)'-') && run > at)
            {
                byte previous = line.ByteAt(run - 1u);
                if (previous == (byte)'e' || previous == (byte)'E')
                {
                    run++;
                    continue;
                }
            }
            break;
        }

        into.Add(Token.Of(TokenKind.Number, at, run - at));
        return run;
    }

    // ------------------------------------------------------------ the bytes

    /// Where the `*/` after `from` ends, or `NotClosed`.
    nuint FindBlockEnd(String line, nuint from)
    {
        nuint size = line.ByteLength();
        nuint run = from;
        while (run + 1u < size)
        {
            if (line.ByteAt(run) == (byte)'*' && line.ByteAt(run + 1u) == (byte)'/')
            {
                return run + 2u;
            }
            run++;
        }
        return NotClosed;
    }

    nuint SkipSpaces(String line, nuint from)
    {
        nuint size = line.ByteLength();
        nuint run = from;
        while (run < size)
        {
            byte c = line.ByteAt(run);
            if (c != (byte)' ' && c != (byte)'\t')
                break;
            run++;
        }
        return run;
    }

    bool IsDigit(byte c) => c >= (byte)'0' && c <= (byte)'9';

    bool IsWordStart(byte c)
    {
        return (c >= (byte)'a' && c <= (byte)'z')
            || (c >= (byte)'A' && c <= (byte)'Z')
            || c == (byte)'_'
            // A byte of a multi-byte character. Identifiers may contain them,
            // and treating one as a word byte keeps a name with an accent in it
            // whole rather than splitting it into rubble.
            || c >= 0x80u;
    }

    bool IsWordPart(byte c) => IsWordStart(c) || IsDigit(c);

    bool IsBracket(byte c)
    {
        return c == (byte)'(' || c == (byte)')'
            || c == (byte)'{' || c == (byte)'}'
            || c == (byte)'[' || c == (byte)']'
            || c == (byte)';' || c == (byte)',';
    }

    bool IsOperator(byte c)
    {
        return c == (byte)'+' || c == (byte)'-' || c == (byte)'*' || c == (byte)'/'
            || c == (byte)'%' || c == (byte)'=' || c == (byte)'<' || c == (byte)'>'
            || c == (byte)'!' || c == (byte)'&' || c == (byte)'|' || c == (byte)'^'
            || c == (byte)'~' || c == (byte)'?' || c == (byte)':' || c == (byte)'.'
            || c == (byte)'#' || c == (byte)'@' || c == (byte)'$' || c == (byte)'\\';
    }
}

/// What `FindBlockEnd` answers when there is no `*/` on the line. Not a
/// position, and larger than any line anyone will edit.
const nuint NotClosed = 0xFFFFFFFFFFFFFFFFu;
