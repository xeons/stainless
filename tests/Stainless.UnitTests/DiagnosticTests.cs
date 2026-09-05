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

using System.Text.RegularExpressions;
using Stainless.Source;
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// The diagnostic codes as a set, and the bag that carries them.
///
/// Most of this is bookkeeping that used to be done by hand once a session:
/// whether a code the documentation names still exists, whether anything still
/// tests it, whether a retired one crept back. None of it is expensive; it was
/// only ever expensive to remember to do.
/// </summary>
public partial class DiagnosticTests
{
    [GeneratedRegex(@"SL\d{4}")]
    private static partial Regex CodePattern { get; }

    /// <summary>The repository, found by walking up from the test assembly.</summary>
    private static readonly string Root = FindRoot();

    private static string FindRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            if (Directory.Exists(Path.Combine(directory.FullName, "tests", "cases")))
                return directory.FullName;
            directory = directory.Parent;
        }

        throw new InvalidOperationException("could not find the repository from " +
                                            AppContext.BaseDirectory);
    }

    private static IEnumerable<string> Files(string relative, string pattern) =>
        Directory.EnumerateFiles(Path.Combine(Root, relative), pattern,
                                 SearchOption.AllDirectories);

    private static SortedSet<string> CodesIn(IEnumerable<string> paths, string pattern)
    {
        var found = new SortedSet<string>(StringComparer.Ordinal);
        foreach (string path in paths)
            foreach (Match match in Regex.Matches(File.ReadAllText(path), pattern))
                found.Add(match.Groups[1].Value);
        return found;
    }

    /// <summary>
    /// Every code the compiler can report, as a quoted literal.
    ///
    /// Diagnostics.cs is left out because the only codes in it are the retired
    /// ones, listed there precisely so that bringing one back is caught.
    /// Counting that list as live would make the check assert against itself.
    /// </summary>
    private static readonly SortedSet<string> Emitted = CodesIn(
        Files("src", "*.cs")
            .Where(p => !p.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}"))
            .Where(p => Path.GetFileName(p) != "Diagnostics.cs"),
        "\"(SL\\d{4})\"");

    /// <summary>Every code the documentation names.</summary>
    private static readonly SortedSet<string> Documented = CodesIn(
        Files("docs", "*.md").Append(Path.Combine(Root, "README.md")),
        @"\b(SL\d{4})\b");

    /// <summary>Every code an end-to-end case pins.</summary>
    private static readonly SortedSet<string> Pinned = CodesIn(
        Directory.EnumerateFiles(Path.Combine(Root, "tests", "cases"), "errors.txt",
                                 SearchOption.AllDirectories)
            .Concat(Directory.EnumerateFiles(Path.Combine(Root, "tests", "cases"), "warnings.txt",
                                             SearchOption.AllDirectories)),
        @"\b(SL\d{4})\b");

    // -------------------------------------------------------------- the set

    [Fact]
    public void TheCompilerHasCodesToReport() => Assert.NotEmpty(Emitted);

    /// <summary>
    /// Everything the documentation promises still exists.
    ///
    /// A code that was renamed while the prose kept the old number is a
    /// documentation bug nothing else notices, because the compiler is happy
    /// and so is every test.
    /// </summary>
    [Fact]
    public void EveryDocumentedCodeExists() =>
        Assert.Empty(Documented.Except(Emitted));

    /// <summary>
    /// And something still tests it. A documented code no case pins is a claim
    /// about behaviour with nothing behind it.
    /// </summary>
    [Fact]
    public void EveryDocumentedCodeIsPinnedByACase() =>
        Assert.Empty(Documented.Except(Pinned));

    /// <summary>
    /// Every code a case pins still exists. The harness would fail loudly on a
    /// code that was never reported, but only for the case that names it, and
    /// only when that case is run on a platform it applies to.
    /// </summary>
    [Fact]
    public void EveryPinnedCodeExists() =>
        Assert.Empty(Pinned.Except(Emitted));

    /// <summary>
    /// A retired code stays retired. There is a debug assertion for this at the
    /// point of reporting, which fires only if the code is actually reached;
    /// this catches it at the point of writing.
    /// </summary>
    [Fact]
    public void NoRetiredCodeIsEmittedAgain() =>
        Assert.Empty(Emitted.Intersect(RetiredDiagnostics.Codes));

    [Fact]
    public void NoRetiredCodeIsStillDocumentedAsLive() =>
        Assert.Empty(Documented.Intersect(RetiredDiagnostics.Codes));

    [Fact]
    public void EveryCodeIsWellFormed() =>
        Assert.All(Emitted, code => Assert.Matches(CodePattern, code));

    // ------------------------------------------------------------ the record

    [Fact]
    public void AnErrorIsAnError()
    {
        var bag = new DiagnosticBag();
        bag.Error("SL0001", default, "something");

        Assert.True(bag.HasErrors);
        Assert.Equal(1, bag.ErrorCount);
        Assert.Equal(Severity.Error, bag.Items[0].Severity);
    }

    [Fact]
    public void AWarningIsNotAnError()
    {
        var bag = new DiagnosticBag();
        bag.Warning("SL0002", default, "something");

        Assert.False(bag.HasErrors);
        Assert.Equal(0, bag.ErrorCount);
    }

    /// <summary>
    /// Errors come before warnings, then file, then position -- so a build's
    /// output reads top to bottom rather than in the order the passes happened
    /// to run.
    /// </summary>
    [Fact]
    public void SortingPutsErrorsFirstThenPosition()
    {
        var file = Front.Text("0123456789");
        var bag = new DiagnosticBag();

        bag.Warning("SL0002", new SourceSpan(file, 1, 2), "early warning");
        bag.Error("SL0001", new SourceSpan(file, 5, 6), "late error");
        bag.Error("SL0003", new SourceSpan(file, 3, 4), "early error");

        Assert.Equal(["SL0003", "SL0001", "SL0002"],
                     bag.Sorted().Select(d => d.Code));
    }

    /// <summary>
    /// A diagnostic about something with no source of its own -- a type read
    /// back from a library's metadata -- has no file, and must sort rather than
    /// bring the compiler down.
    /// </summary>
    [Fact]
    public void SortingSurvivesADiagnosticWithNoFile()
    {
        var bag = new DiagnosticBag();
        bag.Error("SL0001", new SourceSpan(Front.Text("x"), 0, 1), "somewhere");
        bag.Error("SL0002", default, "nowhere");

        Assert.Equal(2, bag.Sorted().Count());
    }

    [Fact]
    public void AddRangeKeepsBothBags()
    {
        var first = new DiagnosticBag();
        var second = new DiagnosticBag();
        first.Error("SL0001", default, "a");
        second.Warning("SL0002", default, "b");
        first.AddRange(second);

        Assert.Equal(["SL0001", "SL0002"], first.Items.Select(d => d.Code));
    }

    // ------------------------------------------------------------ rendering

    /// <summary>
    /// The caret goes under the span. Every diagnostic in the compiler relies
    /// on this and no end-to-end case reads it, because the harness matches
    /// codes rather than output.
    /// </summary>
    [Fact]
    public void TheCaretSitsUnderTheSpan()
    {
        var file = Front.Text("int x = value;");
        var diagnostic = new Diagnostic(
            Severity.Error, "SL0001", "no such thing", new SourceSpan(file, 8, 13));

        string[] lines = diagnostic.Render(color: false).Split('\n');
        string source = lines.First(l => l.Contains("int x"));
        string carets = lines.First(l => l.Contains('^'));

        Assert.Equal(source.IndexOf("value", StringComparison.Ordinal),
                     carets.IndexOf('^'));
        Assert.Equal(5, carets.Count(c => c == '^'));
    }

    [Fact]
    public void RenderingNamesTheFileLineAndColumn()
    {
        var file = Front.Text("one\ntwo\nthree");
        var diagnostic = new Diagnostic(
            Severity.Error, "SL0001", "message", new SourceSpan(file, 8, 13));

        Assert.Contains($"{Front.TestFile}:3:1", diagnostic.Render(color: false));
    }

    [Fact]
    public void RenderingSurvivesADiagnosticWithNoFile()
    {
        var diagnostic = new Diagnostic(Severity.Error, "SL0001", "message", default);
        Assert.Contains("message", diagnostic.Render(color: false));
    }

    /// <summary>
    /// A span that runs past the end of its first line is clamped rather than
    /// drawing carets over nothing -- which a multi-line expression does every
    /// time it is reported.
    /// </summary>
    [Fact]
    public void CaretsAreClampedToTheFirstLine()
    {
        var file = Front.Text("abc\ndefghij");
        var diagnostic = new Diagnostic(
            Severity.Error, "SL0001", "message", new SourceSpan(file, 0, 9));

        string carets = diagnostic.Render(color: false).Split('\n').First(l => l.Contains('^'));
        Assert.Equal(3, carets.Count(c => c == '^'));
    }
}
