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

    public void Error(string code, SourceSpan span, string message) =>
        _items.Add(new Diagnostic(Severity.Error, code, message, span));
    public void Warning(string code, SourceSpan span, string message) =>
        _items.Add(new Diagnostic(Severity.Warning, code, message, span));

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
