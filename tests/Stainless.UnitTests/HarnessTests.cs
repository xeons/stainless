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

using Stainless.Binding;
using Stainless.Tests;
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// Which end-to-end cases a host runs, asked as hosts this machine is not.
/// The cases are the tree's own, so a new one is covered as it lands.
/// </summary>
public class HarnessTests
{
    private static string Case(string name) => Path.Combine(Repository.Root, "tests", "cases", name);

    public static TheoryData<string> Hosts() =>
        new(TargetPlatform.X64Windows.Name, TargetPlatform.Arm64Windows.Name,
            TargetPlatform.X64Linux.Name, TargetPlatform.Arm64Linux.Name,
            TargetPlatform.Arm64MacOS.Name, TargetPlatform.X64MacOS.Name);

    private static TargetPlatform FindHost(string name) => TargetPlatform.Parse(name)!;

    [Theory]
    [MemberData(nameof(Hosts))]
    public void EveryCaseIsDecidedOnEveryHost(string host)
    {
        foreach (string directory in Directory.EnumerateDirectories(Path.Combine(Repository.Root, "tests", "cases")))
            CaseSelection.FindSkipReason(directory, FindHost(host));
    }

    [Fact]
    public void X86IsSkippedOnAMacWithAReason()
    {
        Assert.Equal("no x86 target on macos",
                     CaseSelection.FindSkipReason(Case("x86-abi"), TargetPlatform.Arm64MacOS));
        Assert.Equal("no x86 target on macos",
                     CaseSelection.FindSkipReason(Case("x86-abi"), TargetPlatform.X64MacOS));
    }

    [Fact]
    public void X86RunsWhereX64Does()
    {
        Assert.Null(CaseSelection.FindSkipReason(Case("x86-abi"), TargetPlatform.X64Windows));
        Assert.Null(CaseSelection.FindSkipReason(Case("x86-abi"), TargetPlatform.X64Linux));
        Assert.Equal("x86-linux cannot run on arm64-linux",
                     CaseSelection.FindSkipReason(Case("x86-abi"), TargetPlatform.Arm64Linux));
    }

    [Fact]
    public void AnAssembleOnlyCaseRunsOnAMac()
    {
        Assert.Null(CaseSelection.FindSkipReason(Case("arm64-abi"), TargetPlatform.Arm64MacOS));
        Assert.Null(CaseSelection.FindSkipReason(Case("embed-x64-linux"), TargetPlatform.Arm64MacOS));
        Assert.Null(CaseSelection.FindSkipReason(Case("arm64-abi-windows"), TargetPlatform.X64Linux));
    }

    [Fact]
    public void AnErrorsCaseForAnotherArchitectureRunsOnAMac() =>
        Assert.Null(CaseSelection.FindSkipReason(Case("err-asm-kind"), TargetPlatform.Arm64MacOS));

    [Fact]
    public void PlatformIsAskedBeforeTarget() =>
        Assert.Equal("windows only",
                     CaseSelection.FindSkipReason(Case("x86-win32-layout"), TargetPlatform.Arm64MacOS));

    [Fact]
    public void IntelOnAppleSiliconAndAnotherSystemDoNotRun()
    {
        Assert.False(CaseSelection.CanRun(TargetPlatform.Arm64MacOS, TargetPlatform.X64MacOS));
        Assert.False(CaseSelection.CanRun(TargetPlatform.Arm64MacOS, TargetPlatform.Arm64Linux));
        Assert.False(CaseSelection.CanRun(TargetPlatform.X64Linux, TargetPlatform.X64Windows));
        Assert.True(CaseSelection.CanRun(TargetPlatform.X64MacOS, TargetPlatform.X64MacOS));
        Assert.True(CaseSelection.CanRun(TargetPlatform.Arm64Windows, TargetPlatform.X86Windows));
    }

    [Fact]
    public void ARunCaseForAnotherSystemIsSkipped()
    {
        string directory = Directory.CreateTempSubdirectory("stainless-harness-").FullName;
        try
        {
            File.WriteAllText(Path.Combine(directory, "target.txt"), "x64-linux");
            File.WriteAllText(Path.Combine(directory, "expected.txt"), "");
            Assert.Equal("x64-linux cannot run on arm64-macos",
                         CaseSelection.FindSkipReason(directory, TargetPlatform.Arm64MacOS));
            Assert.Null(CaseSelection.FindSkipReason(directory, TargetPlatform.X64Linux));
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public void TheConsumerFindsItsLibraryBesideIt()
    {
        Assert.Null(CaseSelection.FormatConsumerRunPath(TargetOS.Windows));
        Assert.Equal("-Wl,-rpath,$ORIGIN", CaseSelection.FormatConsumerRunPath(TargetOS.Linux));
        Assert.Equal("-Wl,-rpath,@loader_path", CaseSelection.FormatConsumerRunPath(TargetOS.MacOS));
    }

    [Theory]
    [InlineData("io", TargetOS.MacOS, "expected.macos.txt")]
    [InlineData("io", TargetOS.Linux, "expected.linux.txt")]
    [InlineData("io", TargetOS.Windows, "expected.txt")]
    [InlineData("path-same", TargetOS.MacOS, "expected.linux.txt")]
    [InlineData("path-same", TargetOS.Windows, "expected.txt")]
    [InlineData("files-path-edges", TargetOS.MacOS, "expected.txt")]
    [InlineData("files-path-edges", TargetOS.Windows, "expected.windows.txt")]
    [InlineData("hello", TargetOS.MacOS, "expected.txt")]
    public void TheMostSpecificExpectationWins(string name, TargetOS host, string expected) =>
        Assert.Equal(Path.Combine(Case(name), expected),
                     CaseSelection.FindExpectedOutputPath(Case(name), host));

    [Fact]
    public void LinuxDoesNotTakeTheMacExpectation()
    {
        string directory = Directory.CreateTempSubdirectory("stainless-harness-").FullName;
        try
        {
            File.WriteAllText(Path.Combine(directory, "expected.txt"), "");
            File.WriteAllText(Path.Combine(directory, "expected.macos.txt"), "");
            Assert.Equal(Path.Combine(directory, "expected.txt"),
                         CaseSelection.FindExpectedOutputPath(directory, TargetOS.Linux));
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }
}
