// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This file is part of the Stainless compiler. It is free software: you
// can redistribute it and/or modify it under the terms of the GNU General
// Public License as published by the Free Software Foundation, either
// version 3 of the License, or (at your option) any later version.
//
// It is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

using Stainless.Driver;
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// What scanning a directory takes in, and what it leaves out.
/// </summary>
/// <remarks>
/// <para>
/// A project whose <c>sources</c> is <c>"."</c> scans its own output, so what
/// a previous build wrote must not come back as input. A <c>-g</c> build
/// writes the standard library into <c>obj/stdlib/</c>, and compiling that a
/// second time declares every module of <c>Standard</c> twice.
/// </para>
/// <para>
/// The directories left out are the ones the project names. Guessing by name
/// is what these also pin against: <c>ide/src/Build/</c> is a module of the
/// IDE's, and a rule that read a directory called <c>Build</c> as output would
/// drop it.
/// </para>
/// </remarks>
public class SourceScanTests : IDisposable
{
    private readonly string _root = Path.Combine(
        Path.GetTempPath(), "stainless-scan-" + Guid.NewGuid().ToString("n"));

    public SourceScanTests() => Directory.CreateDirectory(_root);

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
        GC.SuppressFinalize(this);
    }

    private void Write(string relative, string text = "module X;\n")
    {
        string path = Path.Combine(_root, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, text);
    }

    private string At(string relative) => Path.Combine(_root, relative);

    private IReadOnlyList<string> Scan(params string[] excluded) =>
        Compilation.CollectSourceFiles([_root], excluded.Select(At).ToList())
            .Sources
            .Select(p => Path.GetRelativePath(_root, p).Replace('\\', '/'))
            .OrderBy(p => p, StringComparer.Ordinal)
            .ToList();

    [Fact]
    public void AnOrdinarySourceIsTakenIn()
    {
        Write("main.sl");
        Write("src/other.sl");

        Assert.Equal(["main.sl", "src/other.sl"], Scan());
    }

    /// <summary>
    /// An excluded directory goes, however deep the file sits inside it. The
    /// stdlib a <c>-g</c> build writes is two levels down.
    /// </summary>
    [Theory]
    [InlineData("obj/stale.sl")]
    [InlineData("obj/stdlib/Text.sl")]
    [InlineData("obj/x64/stdlib/Text.sl")]
    public void WhatAPreviousBuildWroteIsLeftOut(string artifact)
    {
        Write("main.sl");
        Write(artifact);

        Assert.Equal(["main.sl"], Scan("obj"));
    }

    [Fact]
    public void EveryNamedDirectoryIsLeftOut()
    {
        Write("main.sl");
        Write("obj/stdlib/Text.sl");
        Write("build/copy.sl");

        Assert.Equal(["main.sl"], Scan("obj", "build"));
    }

    /// <summary>
    /// The rule is what the project named, not what a directory is called.
    /// <c>ide/src/Build/Diagnostics.sl</c> declares <c>Ide.Build</c>.
    /// </summary>
    [Fact]
    public void ADirectoryCalledBuildIsStillCompiled()
    {
        Write("main.sl");
        Write("Build/Diagnostics.sl");
        Write("bin/Reader.sl");
        Write("obj/Writer.sl");

        Assert.Equal(["Build/Diagnostics.sl", "bin/Reader.sl", "main.sl",
                      "obj/Writer.sl"],
                     Scan());
    }

    /// <summary>
    /// A name that merely begins with an excluded directory's is not inside it.
    /// </summary>
    [Fact]
    public void ASiblingWithALongerNameIsNotInside()
    {
        Write("obj/stale.sl");
        Write("objects/kept.sl");

        Assert.Equal(["objects/kept.sl"], Scan("obj"));
    }

    /// <summary>
    /// A path somebody typed is not a guess, so it is taken as given.
    /// </summary>
    [Fact]
    public void ANamedFileUnderAnExcludedDirectoryIsStillCompiled()
    {
        Write("obj/named.sl");

        var found = Compilation.CollectSourceFiles(
            [At(Path.Combine("obj", "named.sl"))], [At("obj")]).Sources;
        Assert.Single(found);
    }

    /// <summary>
    /// C and .rc files beside the sources still go by the older name rule,
    /// which is what keeps a stale object out of the next link.
    /// </summary>
    [Fact]
    public void ANativeSourceUnderObjIsLeftOutByName()
    {
        Write("main.sl");
        Write("helper.c", "int helper(void) { return 0; }\n");
        Write("obj/stale.c", "int stale(void) { return 0; }\n");

        var found = Compilation.CollectSourceFiles([_root]).NativeInputs
            .Select(p => Path.GetRelativePath(_root, p).Replace('\\', '/'))
            .ToList();

        Assert.Equal(["helper.c"], found);
    }
}
