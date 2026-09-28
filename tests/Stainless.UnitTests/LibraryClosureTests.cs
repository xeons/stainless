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
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// Which standard-library modules a program reaches: by import, by a qualified
/// name, through an interpolation's hole, through <c>typeof</c>, and onward
/// from a module that was itself reached.
/// </summary>
public class LibraryClosureTests
{
    private static LexedSource Lexed(string text) =>
        LexedSource.Of(new SourceText("test.sl", text), new DiagnosticBag());

    private static readonly LexedSource[] s_library =
    [
        Lexed("module Standard; public struct Unit { }"),
        Lexed("module Standard.Text; import Standard.Limits;"),
        Lexed("module Standard.Limits;"),
        Lexed("module Standard.Collections;"),
        Lexed("module Standard.Bits;"),
        Lexed("module Standard.Com;"),
        Lexed("module Standard.Net; import Standard.IO;"),
        Lexed("module Standard.IO;"),
        Lexed("module Standard.Json;"),
        Lexed("module Standard.Reflection;"),
        Lexed("module Standard.Math;"),
    ];

    private static string[] Reached(string program) =>
        LibraryClosure.ReachedFiles(s_library, [Lexed(program)])
            .Select(f => f.ModuleName)
            .Order(StringComparer.Ordinal)
            .ToArray();

    [Fact]
    public void AProgramNamingNothingGetsTheRootsAndWhatTheyImport() =>
        Assert.Equal(
            ["Standard", "Standard.Bits", "Standard.Collections", "Standard.Com",
             "Standard.Limits", "Standard.Text"],
            Reached("module App; int Main() { return 0; }"));

    [Fact]
    public void AnImportIsFollowedThroughTheModuleItReaches()
    {
        var reached = Reached("module App; import Standard.Net;");
        Assert.Contains("Standard.Net", reached);
        Assert.Contains("Standard.IO", reached);
        Assert.DoesNotContain("Standard.Json", reached);
    }

    [Fact]
    public void AQualifiedNameReachesAModuleWithoutAnImport() =>
        Assert.Contains("Standard.Json", Reached("module App; void F() { Standard.Json.Parse(\"1\"); }"));

    [Fact]
    public void ANameInsideAnInterpolationReachesItsModule() =>
        Assert.Contains("Standard.Math", Reached("module App; void F() { var s = $\"{Standard.Math.Max(1, 2)}\"; }"));

    [Fact]
    public void TypeofReachesReflection() =>
        Assert.Contains("Standard.Reflection", Reached("module App; void F() { var t = typeof(App); }"));

    [Fact]
    public void AModuleNamedOnlyInACommentIsNotReached() =>
        Assert.DoesNotContain("Standard.Json", Reached("module App; // Standard.Json.Parse\n"));

    /// <summary>
    /// A documentation link from a reached module into one the program never
    /// reaches is not a mistake in the library, and a program MUST NOT be
    /// warned about it. `Standard.Bits` is a root and links to `Standard.Math`.
    /// </summary>
    [Theory]
    [InlineData("module App; int Main() { return 0; }")]
    [InlineData("module App; import Standard.Math; int Main() { return (int)Math.Abs(-1); }")]
    public void TheLibraryWarnsAboutNothingWhateverTheProgramReaches(string program)
    {
        string directory = Path.Combine(Path.GetTempPath(), "stainless-closure-warnings",
            Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        string source = Path.Combine(directory, "app.sl");
        File.WriteAllText(source, program);

        var result = new Compilation().Compile(new CompilationOptions
        {
            SourcePaths = [source],
            OutputPath = Path.Combine(directory, "app.ll"),
            IntermediateDirectory = directory,
            EmitIrOnly = true,
        });

        Assert.Empty(result.Diagnostics
            .Where(d => d.Span.File is not null && d.Span.File.Path.StartsWith("<standard>"))
            .Select(d => d.Render(color: false)));
    }

    [Fact]
    public void TheScanReadsTheModuleAndItsImports()
    {
        var file = Lexed("module Shop.Orders; import Standard.IO; import Standard.Net as Net;");
        Assert.Equal("Shop.Orders", file.ModuleName);
        Assert.Equal(["Standard.IO", "Standard.Net"], file.Imports);
    }
}
