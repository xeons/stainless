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

using Stainless.Driver;
using Stainless.Source;
using Stainless.Syntax;

namespace Stainless.Fuzz;

/// <summary>
/// Breaks Stainless source a token at a time.
///
/// Characters are the wrong unit: nearly every byte flip is a lexer error, and
/// the lexer is the least interesting thing to test. Tokens keep most mutants
/// lexable, and the mutations that swap an identifier for another from the
/// same file keep many of them parsing too -- which is what gets a mutant as far
/// as the binder, where the harder bugs are.
/// </summary>
internal sealed class Mutator
{
    private static readonly HashSet<string> s_symbols = Compilation.PlatformSymbols([]);

    /// <summary>The literals, keywords and shapes that tend to find the edges.</summary>
    private static readonly string[] s_interesting =
    [
        "0", "-1", "1", "255", "256", "2147483647", "-2147483648", "9223372036854775807",
        "18446744073709551615", "99999999999999999999999", "1e308", "1e999", "0.0", "0x", "0b",
        "\"\"", "\"\\u{10FFFF}\"", "'\\0'", "''", "null", "default", "true", "this", "base",
        "void", "var", "int", "String", "byte*", "void*", "int[]", "int[..]", "List<int>",
        "Result<int, String>", "T", "?", "!", "...", "..", "=>", "::", "@", "#", "$\"{", "}", "{",
        "(", ")", "[", "]", "<", ">", ";", ",", ".", "new", "ref", "out", "in", "spawn", "try",
        "yield", "fixed", "sizeof", "typeof", "nameof", "is", "as", "switch", "case", "when",
        "where", "operator", "implicit", "const", "static", "override", "virtual", "partial",
        "extern \"C\"", "export \"C\"", "#if", "#else", "#endif", "///", "/*", "*/", "\\",

        // An asm statement's shapes: the body is lexed as raw text, so a stray
        // brace, a missing one and an operand list left open are all edges.
        "asm", "asm {", "asm { nop }", "asm (", "asm (out rax = x) {", "inout", "rax", "xmm0",
        "x30", "rsp", "in rcx =", "out eax =",
    ];

    private static readonly string[] s_brackets = ["()", "[]", "{}", "<>"];

    private readonly Random _random;
    private readonly IReadOnlyList<string> _corpus;
    private readonly List<string> _identifiers;
    private readonly List<string> _others;

    public Mutator(Random random, IReadOnlyList<string> corpus)
    {
        _random = random;
        _corpus = corpus;
        _identifiers = Pool(corpus, identifiers: true);
        _others = Pool(corpus, identifiers: false);
    }

    private static List<string> Pool(IReadOnlyList<string> texts, bool identifiers)
    {
        var pool = new HashSet<string>();
        foreach (string text in texts)
        {
            foreach (var token in Lex(text))
            {
                if ((token.Kind == TokenKind.Identifier) == identifiers && token.Text.Length is > 0 and < 80)
                    pool.Add(token.Text);
            }
        }

        return pool.ToList();
    }

    /// <summary>
    /// The tokens of a text, or none if the lexer cannot manage it -- which is
    /// itself a finding, but one the pipeline reports, not this.
    /// </summary>
    public static IReadOnlyList<Token> Lex(string text)
    {
        try
        {
            return new Lexer(new SourceText("<mutate>", text), new DiagnosticBag(), s_symbols)
                .Tokenize()
                .Where(t => t.Kind != TokenKind.EndOfFile && t.Span.Start < t.Span.End && t.Span.End <= text.Length)
                .ToList();
        }
        catch (Exception)
        {
            return [];
        }
    }

    /// <summary>One to four mutations, most often one.</summary>
    public string Mutate(string text)
    {
        int count = _random.Next(4) == 0 ? 1 + _random.Next(4) : 1;
        for (int i = 0; i < count; i++)
            text = MutateOnce(text);

        return text;
    }

    private T Pick<T>(IReadOnlyList<T> list) => list[_random.Next(list.Count)];

    private string MutateOnce(string text)
    {
        var tokens = Lex(text);
        if (tokens.Count < 2 || _random.Next(50) == 0)
            return Characters(text);

        int first = _random.Next(tokens.Count);
        int length = Math.Min(1 + _random.Next(_random.Next(2) == 0 ? 2 : 12), tokens.Count - first);
        int start = tokens[first].Span.Start;
        int end = tokens[first + length - 1].Span.End;

        switch (_random.Next(12))
        {
            case 0:
                return text.Remove(start, end - start);

            case 1:
                return text.Insert(end, " " + text[start..end]);

            case 2:
                return Swap(text, tokens[first], Pick(tokens));

            case 3:
            case 4:
            {
                // An identifier for another: the one mutation likely to still parse.
                var names = tokens.Where(t => t.Kind == TokenKind.Identifier).ToList();
                if (names.Count == 0)
                    return text;

                string with = _random.Next(4) == 0 ? Pick(_identifiers) : Pick(names).Text;
                return Replace(text, Pick(names), with);
            }

            case 5:
            {
                var target = tokens[first];
                if (target.Kind == TokenKind.Identifier)
                    return text;

                var alike = tokens.Where(t => t.Kind == target.Kind).ToList();
                return Replace(text, target, _random.Next(3) == 0 ? Pick(_others) : Pick(alike).Text);
            }

            case 6:
                return Replace(text, tokens[first], Pick(s_interesting));

            case 7:
                return text.Insert(start, Pick(s_interesting) + " ");

            case 8:
            {
                var lines = Pick(_corpus).Split('\n');
                int from = _random.Next(lines.Length);
                int take = 1 + _random.Next(Math.Min(20, lines.Length - from));
                return text.Insert(start, "\n" + string.Join('\n', lines.Skip(from).Take(take)) + "\n");
            }

            case 9:
            {
                // Size and repetition, sometimes far past anything written by hand.
                int times = _random.Next(3) == 0 ? 600 : 2 + _random.Next(30);
                return text.Insert(end, string.Concat(Enumerable.Repeat(" " + text[start..end], times)));
            }

            case 10:
            {
                // Depth, sometimes past Recursion.MaxDepth, which must be a diagnostic.
                string pair = Pick(s_brackets);
                int depth = _random.Next(3) == 0 ? 700 : 1 + _random.Next(5);
                return text[..start] + new string(pair[0], depth) + text[start..end] + new string(pair[1], depth) + text[end..];
            }

            default:
                return text[..(_random.Next(2) == 0 ? start : end)];
        }
    }

    private static string Swap(string text, Token a, Token b)
    {
        if (a.Span.Start > b.Span.Start)
            (a, b) = (b, a);
        if (a.Span.End > b.Span.Start)
            return text;

        return text[..a.Span.Start] + b.Text + text[a.Span.End..b.Span.Start] + a.Text + text[b.Span.End..];
    }

    private static string Replace(string text, Token token, string with) =>
        text[..token.Span.Start] + with + text[token.Span.End..];

    private string Characters(string text)
    {
        if (text.Length == 0)
            return "x";

        int at = _random.Next(text.Length);
        return _random.Next(3) switch
        {
            0 => text.Remove(at, 1),
            1 => text.Insert(at, ((char)_random.Next(1, 128)).ToString()),
            _ => text.Insert(at, char.ConvertFromUtf32(_random.Next(4) == 0 ? 0xFFFD : _random.Next(0x80, 0x3000))),
        };
    }
}
