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

using System.Text;

namespace Stainless.Source;

public enum Severity { Error, Warning, Note }

/// <summary>
/// Codes that were used once and are not to be used again.
///
/// A code is a handle for a rule, so a rule has exactly one and a code means
/// exactly one thing. These were second handles for a rule that already had
/// one: each produced a message a reader could not tell from the surviving
/// code's, which makes it a duplicate rather than a distinction. They are
/// listed rather than reused, because a number that meant something else in an
/// older build should not quietly come to mean this.
///
///   SL0214, SL0321  -> SL0201   'X' is already declared in module 'Y'
///   SL0386          -> SL0205   'X' already declares a member named 'Y'
///   SL0251          -> SL0247   'X' has no member named 'Y'
///   SL0237          -> SL0234   operator 'X' cannot be applied to these
///   SL0256          -> SL0255   'X' has no method named 'Y'
///   SL0259          -> SL0252   no function named 'X' is in scope
///   SL0261          -> SL0260   'X' takes N arguments, but M were given
///   SL0311, SL0485  -> SL0310   there is no array of 'void'
///
/// The numbering has always had gaps -- the ranges are banded by pass -- so
/// these leave no hole worth closing.
/// </summary>
public static class RetiredDiagnostics
{
    public static readonly IReadOnlySet<string> Codes = new HashSet<string>(StringComparer.Ordinal)
    {
        "SL0214", "SL0237", "SL0251", "SL0256", "SL0259",
        "SL0261", "SL0311", "SL0321", "SL0386", "SL0485",
    };
}

public sealed record Diagnostic(Severity Severity, string Code, string Message, SourceSpan Span)
{
    /// <summary>Renders a diagnostic with a source excerpt and a caret run under the span.</summary>
    public string Render(bool color = true)
    {
        string sevText = Severity switch
        {
            Severity.Error => "error",
            Severity.Warning => "warning",
            _ => "note"
        };
        string sevColor = Severity switch
        {
            Severity.Error => "\u001b[1;31m",
            Severity.Warning => "\u001b[1;33m",
            _ => "\u001b[1;36m"
        };
        const string bold = "\u001b[1m", dim = "\u001b[2m", reset = "\u001b[0m";
        string C(string code) => color ? code : "";

        var sb = new StringBuilder();
        sb.Append($"{C(sevColor)}{sevText}[{Code}]{C(reset)}{C(bold)}: {Message}{C(reset)}\n");

        // Something with no source of its own -- a type read back from a
        // library's metadata, say -- has no file to excerpt, and the message is
        // the whole of what can be said about it.
        if (Span.File is null) return sb.ToString();

        var (line, col) = Span.File.GetLineColumn(Span.Start);

        string lineNo = line.ToString();
        string pad = new(' ', lineNo.Length);
        sb.Append($"{pad}{C(dim)}--> {C(reset)}{Span.File.Path}:{line}:{col}\n");

        string src = Span.File.GetLine(line).Replace("\t", "    ");
        sb.Append($"{pad} {C(dim)}|{C(reset)}\n");
        sb.Append($"{lineNo} {C(dim)}|{C(reset)} {src}\n");

        // Caret run, clamped to the remainder of the first line of the span.
        int caretLen = Math.Max(1, Math.Min(Span.Length, Math.Max(1, src.Length - (col - 1))));
        sb.Append($"{pad} {C(dim)}|{C(reset)} {new string(' ', Math.Max(0, col - 1))}");
        sb.Append($"{C(sevColor)}{new string('^', caretLen)}{C(reset)}\n");
        return sb.ToString();
    }
}

public sealed class DiagnosticBag
{
    private readonly List<Diagnostic> _items = [];
    public IReadOnlyList<Diagnostic> Items => _items;
    public bool HasErrors => _items.Any(d => d.Severity == Severity.Error);
    public int ErrorCount => _items.Count(d => d.Severity == Severity.Error);

    private int _muted;

    /// <summary>
    /// Drops everything reported until the result is disposed.
    ///
    /// For asking a question the answer to which may be "that does not work" --
    /// binding a lambda's body to find out what it produces, before anything has
    /// decided that this is the lambda's real target. A complaint from a trial
    /// like that is not about the program: either the trial is discarded, or the
    /// real bind happens afterwards and reports properly.
    ///
    /// Nested, so a trial inside a trial does not un-mute the outer one.
    /// </summary>
    public Mute Muted() => new(this);

    public readonly struct Mute : IDisposable
    {
        private readonly DiagnosticBag _bag;

        internal Mute(DiagnosticBag bag)
        {
            _bag = bag;
            bag._muted += 1;
        }

        public void Dispose() => _bag._muted -= 1;
    }

    public void Error(string code, SourceSpan span, string message)
    {
        Fresh(code);
        if (_muted > 0) return;
        _items.Add(new Diagnostic(Severity.Error, code, message, span));
    }

    public void Warning(string code, SourceSpan span, string message)
    {
        Fresh(code);
        if (_muted > 0) return;
        _items.Add(new Diagnostic(Severity.Warning, code, message, span));
    }

    /// <summary>
    /// Catches a retired code being brought back. It is a debug assertion
    /// because a released compiler should not pay for it, and the whole test
    /// suite runs against a debug build -- so anything that reintroduces one
    /// fails there rather than shipping.
    /// </summary>
    [System.Diagnostics.Conditional("DEBUG")]
    private static void Fresh(string code) =>
        System.Diagnostics.Debug.Assert(
            !RetiredDiagnostics.Codes.Contains(code),
            $"{code} was retired; see RetiredDiagnostics for what replaced it");

    public void AddRange(DiagnosticBag other) => _items.AddRange(other._items);

    /// <summary>
    /// Errors first, then by file and position, so output reads top-to-bottom.
    ///
    /// A diagnostic about something with no source of its own -- a type read
    /// back from a library's metadata, say -- has no file, and sorts before the
    /// ones that do rather than bringing the compiler down.
    /// </summary>
    public IEnumerable<Diagnostic> Sorted() => _items
        .OrderBy(d => d.Severity)
        .ThenBy(d => d.Span.File?.Path ?? "", StringComparer.Ordinal)
        .ThenBy(d => d.Span.Start);
}
