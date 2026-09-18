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

using System.Text.Json;
using Stainless.Source;
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// A diagnostic as a tool reads it.
///
/// The IDE read the rendered form and took it apart again -- a line was an
/// error because it began with "error", and the place came from counting colons
/// from the right of the arrow line so a Windows drive letter would survive.
/// This is what replaces that, so what it has to guarantee is written down:
/// every line is valid JSON on its own, the fields are the ones an editor needs
/// to put a squiggle somewhere, and nothing in a message can break the line.
/// </summary>
public class DiagnosticJsonTests
{
    private static SourceText Source(string text) => new("test.sl", text);

    private static JsonElement Parse(Diagnostic diagnostic) =>
        JsonDocument.Parse(diagnostic.RenderJson()).RootElement;

    [Fact]
    public void CarriesWhatAnEditorNeedsToUnderlineSomething()
    {
        var file = Source("int x = 1;\nint y = 2;\n");
        var diagnostic = new Diagnostic(
            Severity.Error, "SL0265", "cannot convert 'String' to 'int'",
            new SourceSpan(file, 15, 18));

        var json = Parse(diagnostic);

        Assert.Equal("error", json.GetProperty("severity").GetString());
        Assert.Equal("SL0265", json.GetProperty("code").GetString());
        Assert.Equal("cannot convert 'String' to 'int'", json.GetProperty("message").GetString());
        Assert.Equal("test.sl", json.GetProperty("file").GetString());
        Assert.Equal(2, json.GetProperty("line").GetInt32());
        Assert.Equal(5, json.GetProperty("column").GetInt32());
        Assert.Equal(3, json.GetProperty("length").GetInt32());
    }

    /// <summary>
    /// The line and column have to agree with the rendered form, or a build
    /// looked at two ways points at two places.
    /// </summary>
    [Fact]
    public void AgreesWithTheRenderedForm()
    {
        var file = Source("alpha\nbeta gamma\n");
        var diagnostic = new Diagnostic(
            Severity.Warning, "SL0222", "this expression has no effect",
            new SourceSpan(file, 11, 16));

        var json = Parse(diagnostic);
        string rendered = diagnostic.Render(color: false);

        Assert.Contains(
            $"test.sl:{json.GetProperty("line").GetInt32()}:{json.GetProperty("column").GetInt32()}",
            rendered);
    }

    [Theory]
    [InlineData(Severity.Error, "error")]
    [InlineData(Severity.Warning, "warning")]
    [InlineData(Severity.Note, "note")]
    public void NamesEverySeverity(Severity severity, string expected)
    {
        var diagnostic = new Diagnostic(severity, "SL0001", "something", default);
        Assert.Equal(expected, Parse(diagnostic).GetProperty("severity").GetString());
    }

    /// <summary>
    /// Something read back from a library's metadata has no source of its own.
    /// It says so by leaving the place out, rather than by naming a file
    /// nothing could open.
    /// </summary>
    [Fact]
    public void LeavesThePlaceOutWhenThereIsNoFile()
    {
        var json = Parse(new Diagnostic(Severity.Error, "SL0999", "no source here", default));

        Assert.Equal("no source here", json.GetProperty("message").GetString());
        Assert.False(json.TryGetProperty("file", out _));
        Assert.False(json.TryGetProperty("line", out _));
    }

    /// <summary>
    /// The case that decides whether this is usable at all on Windows: a path
    /// is full of backslashes, and one unescaped makes the line invalid JSON --
    /// or worse, valid and wrong.
    /// </summary>
    [Fact]
    public void EscapesAWindowsPath()
    {
        var file = new SourceText(@"C:\Users\b\src\main.sl", "x\n");
        var json = Parse(new Diagnostic(
            Severity.Error, "SL0001", "something", new SourceSpan(file, 0, 1)));

        Assert.Equal(@"C:\Users\b\src\main.sl", json.GetProperty("file").GetString());
    }

    /// <summary>
    /// A message quotes source text, and source text contains quotes, newlines
    /// and -- the one that is easy to forget -- tabs, which are a control
    /// character and not merely awkward.
    /// </summary>
    [Fact]
    public void EscapesWhateverAMessageCarries()
    {
        string awkward = "a \"quoted\" thing\nwith a tab\there and a \\ too";
        var json = Parse(new Diagnostic(Severity.Error, "SL0001", awkward, default));

        Assert.Equal(awkward, json.GetProperty("message").GetString());
    }

    /// <summary>
    /// One object per line, so a reader can act on each as it arrives and a
    /// build that dies part-way still leaves what it managed to say readable.
    /// A single object that spanned lines would make both untrue.
    /// </summary>
    [Fact]
    public void IsOneLine()
    {
        var file = Source("int x = 1;\n");
        string rendered = new Diagnostic(
            Severity.Error, "SL0265", "a\nmessage\nwith\nnewlines",
            new SourceSpan(file, 0, 3)).RenderJson();

        Assert.DoesNotContain('\n', rendered);
        Assert.DoesNotContain('\r', rendered);
    }
}
