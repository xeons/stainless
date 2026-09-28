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

using System.Text;
using System.Text.RegularExpressions;
using Stainless.Source;

namespace Stainless.Syntax;

/// <summary>
/// A file lexed and not yet parsed, with what its tokens say about the modules
/// it reaches.
///
/// Lexing costs about a third of parsing, so the standard library is lexed
/// whole and parsed only where a program reaches it. The tokens are handed to
/// the parser as they are; nothing is lexed twice.
/// </summary>
public sealed class LexedSource
{
    /// <summary>A dotted name inside an interpolated string, whose holes are lexed later.</summary>
    private static readonly Regex s_dottedName =
        new(@"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+", RegexOptions.CultureInvariant);

    private LexedSource(SourceText source, Lexer lexer, List<Token> tokens)
    {
        Source = source;
        Lexer = lexer;
        Tokens = tokens;
        Scan();
    }

    public SourceText Source { get; }
    public Lexer Lexer { get; }
    public List<Token> Tokens { get; }

    /// <summary>What <c>module X;</c> names, or empty when the file has none.</summary>
    public string ModuleName { get; private set; } = "";

    /// <summary>The modules the file imports.</summary>
    public List<string> Imports { get; } = [];

    /// <summary>
    /// Every dotted name the file spells, with each of its prefixes:
    /// <c>Standard.Text.FromInteger</c> also gives <c>Standard.Text</c>. A
    /// qualified name reaches a module without importing it, so this is what
    /// finds the modules a file uses beyond its imports.
    /// </summary>
    public HashSet<string> NamePaths { get; } = new(StringComparer.Ordinal);

    /// <summary>Whether the file writes <c>typeof</c> or <c>Reflect</c>, both of which live in Standard.Reflection.</summary>
    public bool MentionsReflection { get; private set; }

    public static LexedSource Of(
        SourceText source, DiagnosticBag diagnostics, IReadOnlyCollection<string>? symbols = null)
    {
        var lexer = new Lexer(source, diagnostics, symbols);
        return new LexedSource(source, lexer, lexer.Tokenize());
    }

    public CompilationUnitSyntax Parse(DiagnosticBag diagnostics) =>
        new Parser(this, diagnostics).ParseCompilationUnit();

    private void Scan()
    {
        for (int i = 0; i < Tokens.Count; i++)
        {
            var token = Tokens[i];
            switch (token.Kind)
            {
                case TokenKind.ModuleKeyword:
                    ModuleName = ChainAt(i + 1, out i);
                    break;

                case TokenKind.ImportKeyword:
                    Imports.Add(ChainAt(i + 1, out i));
                    break;

                case TokenKind.TypeofKeyword:
                    MentionsReflection = true;
                    break;

                case TokenKind.InterpolatedString:
                    foreach (Match match in s_dottedName.Matches(token.Text))
                        AddPrefixes(match.Value);
                    break;

                case TokenKind.Identifier:
                    if (token.Text == "Reflect") MentionsReflection = true;
                    AddPrefixes(ChainAt(i, out i));
                    break;
            }
        }
    }

    /// <summary>The dotted name starting at <paramref name="start"/>, and the index of its last token.</summary>
    private string ChainAt(int start, out int last)
    {
        last = start;
        if (start >= Tokens.Count || Tokens[start].Kind != TokenKind.Identifier) return "";

        var chain = new StringBuilder(Tokens[start].Text);
        while (last + 2 < Tokens.Count
               && Tokens[last + 1].Kind == TokenKind.Dot
               && Tokens[last + 2].Kind == TokenKind.Identifier)
        {
            chain.Append('.').Append(Tokens[last + 2].Text);
            last += 2;
        }

        return chain.ToString();
    }

    private void AddPrefixes(string chain)
    {
        for (int dot = chain.IndexOf('.'); dot >= 0; dot = chain.IndexOf('.', dot + 1))
            NamePaths.Add(chain[..dot]);
        NamePaths.Add(chain);
    }
}
