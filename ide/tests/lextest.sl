// SPDX-License-Identifier: 0BSD
//
// What the scanner does to lines that are awkward on purpose.
//
//   stainless run ide/tests/lextest.sl ide/src/Lang
//
// Every case here is a line that a line-at-a-time lexer gets wrong in some
// particular way if it is written carelessly, and the comment on each says
// which way.
module Ide.Tests;

import Standard.Console;
import Standard.Text;
import Standard.Collections;
import Ide.Lang;

/// The checks and the count of what failed.
///
/// A class because a module cannot hold a mutable variable -- only `const` --
/// which is the rule that keeps a program's state somewhere a reader can find
/// it rather than scattered across files that happen to share a module.
public class Harness
{
    Scanner _scanner;
    int _failures;

    public Harness()
    {
        _scanner = new Scanner();
        _failures = 0;
    }

    public int Failures => _failures;

    /// Lexes one line and checks the kinds it produced, ignoring whitespace --
    /// which is in the stream so a painter can walk it, and is noise here.
    public void Check(String what, String line, TokenKind[] expected)
    {
        var tokens = new List<Token>();
        _scanner.ScanLine(line, ScanState.Normal, tokens);

        var kinds = new List<TokenKind>();
        foreach (var token in tokens)
        {
            if (token.Kind != TokenKind.Whitespace)
                kinds.Add(token.Kind);
        }

        bool ok = kinds.Count == expected.Length;
        if (ok)
        {
            for (nuint i = 0u; i < expected.Length; i++)
            {
                if (kinds[i] != expected[i])
                    ok = false;
            }
        }

        if (ok)
        {
            Console.WriteLine("  ok    " + what);
            return;
        }

        _failures++;
        Console.WriteLine("  FAIL  " + what);
        Console.WriteLine("        line: " + line);
        Console.Write("        got:  ");
        foreach (var token in tokens)
        {
            if (token.Kind == TokenKind.Whitespace)
                continue;
            Console.Write(Name(token.Kind) + "('"
                          + line.Substring(token.Start, token.Length) + "') ");
        }
        Console.WriteLine("");
    }

    /// Checks that the tokens cover every byte of the line with no gap and no
    /// overlap. A painter walks them end to end, so a gap is a run of text that
    /// never gets drawn.
    public void CheckTiling(String what, String line)
    {
        var tokens = new List<Token>();
        _scanner.ScanLine(line, ScanState.Normal, tokens);

        nuint at = 0u;
        foreach (var token in tokens)
        {
            if (token.Start != at)
            {
                Failed(what + ": a token starts at " + Standard.Text.FromInteger(token.Start)
                     + " where " + Standard.Text.FromInteger(at) + " was expected");
                return;
            }
            at = token.End;
        }
        if (at != line.ByteLength())
        {
            Failed(what + ": the tokens stop at " + Standard.Text.FromInteger(at)
                 + " of " + Standard.Text.FromInteger(line.ByteLength()));
            return;
        }
        Console.WriteLine("  ok    " + what);
    }

    /// Checks what a line leaves open for the next one.
    public void CheckState(String what, String line, ScanState entry, ScanState expected)
    {
        var tokens = new List<Token>();
        var after = _scanner.ScanLine(line, entry, tokens);
        if (after != expected)
        {
            Failed(what);
            return;
        }
        Console.WriteLine("  ok    " + what);
    }

    /// Not `Fail`. An unqualified `Fail(x)` is the `Result` variant's own case
    /// constructor, which builds a value and discards it -- so the count never
    /// moved and every check passed. SL0222 is what caught it.
    public void Failed(String why)
    {
        _failures++;
        Console.WriteLine("  FAIL  " + why);
    }

    String Name(TokenKind kind)
    {
        if (kind == TokenKind.Whitespace)
            return "space";
        if (kind == TokenKind.Comment)
            return "comment";
        if (kind == TokenKind.DocComment)
            return "doc";
        if (kind == TokenKind.BlockComment)
            return "block";
        if (kind == TokenKind.Keyword)
            return "keyword";
        if (kind == TokenKind.ContextualKeyword)
            return "soft";
        if (kind == TokenKind.TypeName)
            return "type";
        if (kind == TokenKind.Identifier)
            return "name";
        if (kind == TokenKind.Number)
            return "number";
        if (kind == TokenKind.Text)
            return "text";
        if (kind == TokenKind.Character)
            return "char";
        if (kind == TokenKind.Directive)
            return "directive";
        if (kind == TokenKind.Attribute)
            return "attribute";
        if (kind == TokenKind.Operator)
            return "operator";
        if (kind == TokenKind.Bracket)
            return "bracket";
        return "unknown";
    }
}

int Main()
{
    var t = new Harness();
    Console.WriteLine("the scanner");

    t.Check("a declaration",
            "public int Count;",
            [TokenKind.Keyword, TokenKind.TypeName, TokenKind.TypeName, TokenKind.Bracket]);

    t.Check("a call",
            "puts(text);",
            [TokenKind.Identifier, TokenKind.Bracket, TokenKind.Identifier,
             TokenKind.Bracket, TokenKind.Bracket]);

    // Three slashes is documentation and two is a note. Four is a ruled line,
    // which the compiler treats as an ordinary comment, so this does too.
    t.Check("a note",        "// a note",        [TokenKind.Comment]);
    t.Check("documentation", "/// what it is",   [TokenKind.DocComment]);
    t.Check("a rule",        "//// ---------",   [TokenKind.Comment]);

    // A `//` inside a string is not a comment. The lexer that gets this wrong
    // is the one that searches the line for `//` before tokenising it.
    t.Check("a slash in a string",
            "var url = \"http://example\";",
            [TokenKind.Keyword, TokenKind.Identifier, TokenKind.Operator,
             TokenKind.Text, TokenKind.Bracket]);

    // And a quote inside a comment does not open a string.
    t.Check("a quote in a comment",
            "int x; // it's fine",
            [TokenKind.TypeName, TokenKind.Identifier, TokenKind.Bracket, TokenKind.Comment]);

    // An escaped quote does not close the string.
    t.Check("an escaped quote", "\"a \\\" b\"", [TokenKind.Text]);

    // Unterminated, which is what every string looks like while it is typed.
    t.Check("an unfinished string", "\"open", [TokenKind.Text]);

    // The holes of an interpolated string are code.
    t.Check("interpolation",
            "$\"n = {Count(xs)}\"",
            [TokenKind.Text, TokenKind.Text, TokenKind.TypeName, TokenKind.Bracket,
             TokenKind.Identifier, TokenKind.Bracket, TokenKind.Text]);

    t.Check("a directive", "#if WINDOWS", [TokenKind.Directive]);

    // `#` is a directive only at the start of a line.
    t.Check("a hash elsewhere",
            "int x = a # b;",
            [TokenKind.TypeName, TokenKind.Identifier, TokenKind.Operator,
             TokenKind.Identifier, TokenKind.Operator, TokenKind.Identifier,
             TokenKind.Bracket]);

    t.Check("numbers",
            "0xFFu 1_000 3.14e-2",
            [TokenKind.Number, TokenKind.Number, TokenKind.Number]);

    // A range is two numbers and an operator, not one number with two points.
    t.Check("a range",
            "xs[1..2]",
            [TokenKind.Identifier, TokenKind.Bracket, TokenKind.Number,
             TokenKind.Operator, TokenKind.Number, TokenKind.Bracket]);

    t.Check("a character",         "'a'",   [TokenKind.Character]);
    t.Check("an escaped character", "'\\''", [TokenKind.Character]);

    t.Check("contextual words",
            "public event EventHandler Click;",
            [TokenKind.Keyword, TokenKind.ContextualKeyword, TokenKind.TypeName,
             TokenKind.TypeName, TokenKind.Bracket]);

    // Every byte of the line must be covered, whatever is on it.
    t.CheckTiling("tiling: code",    "public int Count = 1;");
    t.CheckTiling("tiling: string",  "var s = \"a {b} c\";");
    t.CheckTiling("tiling: comment", "  // trailing");
    t.CheckTiling("tiling: empty",   "");

    // A block comment is the whole of what one line tells the next.
    t.CheckState("an open block comment carries",
                 "int x; /* opened", ScanState.Normal, ScanState.InBlockComment);
    t.CheckState("a closed block comment clears",
                 " still */ int y;", ScanState.InBlockComment, ScanState.Normal);
    t.CheckState("a whole block comment leaves nothing open",
                 "int /* both */ x;", ScanState.Normal, ScanState.Normal);

    Console.WriteLine("");
    if (t.Failures == 0)
    {
        Console.WriteLine("all checks passed");
        return 0;
    }
    Console.WriteLine(Standard.Text.FromInteger(t.Failures) + " FAILED");
    return 1;
}
