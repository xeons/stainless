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
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// Where a build with no <c>-o</c> leaves its program and its <c>obj</c>: the
/// directory its sources share.
/// </summary>
public class OutputPathTests
{
    private static string Under(params string[] names) =>
        Path.Combine([Path.GetTempPath(), "stainless-output", .. names]);

    [Fact]
    public void SourcesInOneDirectoryShareIt()
    {
        string shared = Compilation.CommonDirectory([Under("app", "a.sl"), Under("app", "b.sl")]);
        Assert.Equal(Under("app"), shared);
    }

    [Fact]
    public void ADirectoryIsSharedByWholeNamesOnly()
    {
        string shared = Compilation.CommonDirectory([Under("forms", "a.sl"), Under("formsrc", "b.sl")]);
        Assert.Equal(Under(), shared);
    }

    [Fact]
    public void AnOutputThatIsADirectoryIsRefusedByName()
    {
        string directory = Under("collide", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path.Combine(directory, "tests"));
        string source = Path.Combine(directory, "main.sl");
        File.WriteAllText(source, "module Tests; int Main() => 0;");

        var result = new Compilation().Compile(new CompilationOptions
        {
            SourcePaths = [source],
            OutputPath = Path.Combine(directory, "tests"),
            IntermediateDirectory = directory,
            EmitIrOnly = true,
        });

        Assert.False(result.Success);
        Assert.Contains("which is a directory", result.DriverError);
    }

    [Fact]
    public void SourcesSharingOnlyTheRootBuildInTheCurrentDirectory()
    {
        string root = Path.GetPathRoot(Path.GetTempPath())!;
        string shared = Compilation.CommonDirectory(
            [Path.Combine(root, "a", "a.sl"), Path.Combine(root, "c", "b.sl")]);
        Assert.Equal(Directory.GetCurrentDirectory(), shared);
    }
}
