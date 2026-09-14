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
/// Turning what a project asked for into exactly what will be built.
///
/// Only path dependencies are exercised here, deliberately: a git one is the
/// same walk with a clone in front of it, and a test suite that needs a network
/// to run is a test suite that stops being run. What is worth pinning down is
/// the graph -- the order it comes out in, and the four ways it can be
/// impossible.
/// </summary>
public class ResolverTests : IDisposable
{
    private readonly string _root = Path.Combine(
        Path.GetTempPath(), "stainless-resolver", Path.GetRandomFileName());

    public ResolverTests() => Directory.CreateDirectory(_root);

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); }
        catch (IOException) { /* a temp directory left behind is not a failure */ }

        GC.SuppressFinalize(this);
    }

    /// <summary>
    /// Writes a package with a project file and one source file, and returns
    /// the project.
    /// </summary>
    private ProjectFile Package(
        string name, string version, string kind = "library", string dependencies = "{}")
    {
        string directory = Path.Combine(_root, name);
        Directory.CreateDirectory(Path.Combine(directory, "src"));

        File.WriteAllText(
            Path.Combine(directory, "src", name + ".sl"),
            $"module {name};\npublic int Answer() {{ return 42; }}\n");

        string path = Path.Combine(directory, ProjectFile.FileName);

        File.WriteAllText(path, $$"""
            {
              "name": "{{name}}",
              "version": "{{version}}",
              "kind": "{{kind}}",
              "sources": ["src"],
              "dependencies": {{dependencies}}
            }
            """);

        var project = ProjectFile.Read(path, out string error);
        Assert.True(project is not null, error);
        return project!;
    }

    private static Resolution Resolve(ProjectFile root) =>
        new PackageResolver(cacheDirectory: Path.GetTempPath()).Resolve(root);

    [Fact]
    public void ResolvesNothingForAProjectWithNoDependencies()
    {
        var resolution = Resolve(Package("alone", "1.0.0", kind: "executable"));

        Assert.True(resolution.Success, resolution.Error);
        Assert.Empty(resolution.Order);
    }

    [Fact]
    public void FindsAPathDependency()
    {
        Package("geometry", "1.2.0");

        var resolution = Resolve(Package(
            "app", "0.1.0", "executable",
            """{ "geometry": { "path": "../geometry", "version": "^1.2" } }"""));

        Assert.True(resolution.Success, resolution.Error);
        var geometry = Assert.Single(resolution.Order);

        Assert.Equal("geometry", geometry.Name);
        Assert.Equal("1.2.0", geometry.Project.Version);
        Assert.Equal("path:../geometry", geometry.Source);
        Assert.Equal(DependencyLink.Source, geometry.Link);
        Assert.NotEqual("", geometry.SourceDigest);
    }

    /// <summary>
    /// Dependencies come out before whatever needs them, which is what lets the
    /// builder walk the list once and never wait.
    /// </summary>
    [Fact]
    public void OrdersDependenciesBeforeTheirDependents()
    {
        Package("bottom", "1.0.0");
        Package("middle", "1.0.0", dependencies: """{ "bottom": { "path": "../bottom" } }""");

        var resolution = Resolve(Package(
            "app", "0.1.0", "executable",
            """{ "middle": { "path": "../middle" } }"""));

        Assert.True(resolution.Success, resolution.Error);
        Assert.Equal(["bottom", "middle"], resolution.Order.Select(p => p.Name));
    }

    /// <summary>One package needed twice is one package, not two.</summary>
    [Fact]
    public void SharesAPackageTwoThingsNeed()
    {
        Package("shared", "1.0.0");
        Package("left", "1.0.0", dependencies: """{ "shared": { "path": "../shared" } }""");
        Package("right", "1.0.0", dependencies: """{ "shared": { "path": "../shared" } }""");

        var resolution = Resolve(Package(
            "app", "0.1.0", "executable",
            """{ "left": { "path": "../left" }, "right": { "path": "../right" } }"""));

        Assert.True(resolution.Success, resolution.Error);
        Assert.Equal(["shared", "left", "right"], resolution.Order.Select(p => p.Name));
        Assert.Single(resolution.Order, p => p.Name == "shared");
    }

    [Fact]
    public void RefusesAVersionNobodyAskedFor()
    {
        Package("geometry", "2.0.0");

        var resolution = Resolve(Package(
            "app", "0.1.0", "executable",
            """{ "geometry": { "path": "../geometry", "version": "^1.2" } }"""));

        Assert.False(resolution.Success);
        Assert.Contains("needs 'geometry' ^1.2", resolution.Error);
        Assert.Contains("2.0.0", resolution.Error);
    }

    /// <summary>
    /// The interesting conflict is not two versions but two requirements that
    /// cannot both be met by the one copy there is.
    /// </summary>
    [Fact]
    public void RefusesTwoRequirementsThatCannotAgree()
    {
        Package("shared", "2.0.0");
        Package("left", "1.0.0",
            dependencies: """{ "shared": { "path": "../shared", "version": "^2.0" } }""");
        Package("right", "1.0.0",
            dependencies: """{ "shared": { "path": "../shared", "version": "^1.0" } }""");

        var resolution = Resolve(Package(
            "app", "0.1.0", "executable",
            """{ "left": { "path": "../left" }, "right": { "path": "../right" } }"""));

        Assert.False(resolution.Success);
        Assert.Contains("no registry", resolution.Error);
    }

    /// <summary>
    /// Two sources for one name would be two copies of a package: two layouts
    /// and two sets of reference counts under one name.
    /// </summary>
    [Fact]
    public void RefusesOnePackageFromTwoPlaces()
    {
        Package("shared", "1.0.0");
        Directory.CreateDirectory(Path.Combine(_root, "elsewhere"));
        Package("left", "1.0.0", dependencies: """{ "shared": { "path": "../shared" } }""");
        Package("right", "1.0.0",
            dependencies: """{ "shared": { "git": "https://example.invalid/shared.git" } }""");

        var resolution = Resolve(Package(
            "app", "0.1.0", "executable",
            """{ "left": { "path": "../left" }, "right": { "path": "../right" } }"""));

        Assert.False(resolution.Success);
        Assert.Contains("needed from two places", resolution.Error);
    }

    /// <summary>
    /// Linking one package both ways would compile its code into the program
    /// and load another copy of it beside the program.
    /// </summary>
    [Fact]
    public void RefusesOnePackageLinkedTwoWays()
    {
        Package("shared", "1.0.0");
        Package("left", "1.0.0",
            dependencies: """{ "shared": { "path": "../shared", "link": "shared" } }""");
        Package("right", "1.0.0",
            dependencies: """{ "shared": { "path": "../shared", "link": "source" } }""");

        var resolution = Resolve(Package(
            "app", "0.1.0", "executable",
            """{ "left": { "path": "../left" }, "right": { "path": "../right" } }"""));

        Assert.False(resolution.Success);
        Assert.Contains("linked two ways", resolution.Error);
    }

    [Fact]
    public void RefusesACycle()
    {
        Package("a", "1.0.0", dependencies: """{ "b": { "path": "../b" } }""");
        Package("b", "1.0.0", dependencies: """{ "a": { "path": "../a" } }""");

        var resolution = Resolve(Package(
            "app", "0.1.0", "executable", """{ "a": { "path": "../a" } }"""));

        Assert.False(resolution.Success);
        Assert.Contains("cycle", resolution.Error);
    }

    /// <summary>
    /// An executable has a Main and no surface to bind against, so nothing can
    /// be built on top of one.
    /// </summary>
    [Fact]
    public void RefusesToDependOnAnExecutable()
    {
        Package("tool", "1.0.0", kind: "executable");

        var resolution = Resolve(Package(
            "app", "0.1.0", "executable", """{ "tool": { "path": "../tool" } }"""));

        Assert.False(resolution.Success);
        Assert.Contains("cannot be depended on", resolution.Error);
    }

    /// <summary>Two names for one package is how a lock file starts lying.</summary>
    [Fact]
    public void RefusesADependencyCalledSomethingElse()
    {
        Package("geometry", "1.0.0");

        var resolution = Resolve(Package(
            "app", "0.1.0", "executable", """{ "geo": { "path": "../geometry" } }"""));

        Assert.False(resolution.Success);
        Assert.Contains("calls it 'geometry'", resolution.Error);
    }

    [Fact]
    public void SaysSoWhenThereIsNoDirectory()
    {
        var resolution = Resolve(Package(
            "app", "0.1.0", "executable", """{ "missing": { "path": "../missing" } }"""));

        Assert.False(resolution.Success);
        Assert.Contains("no directory there", resolution.Error);
    }

    [Fact]
    public void SaysSoWhenTheDirectoryIsNotAPackage()
    {
        Directory.CreateDirectory(Path.Combine(_root, "loose"));
        File.WriteAllText(Path.Combine(_root, "loose", "Thing.sl"), "module Thing;\n");

        var resolution = Resolve(Package(
            "app", "0.1.0", "executable", """{ "loose": { "path": "../loose" } }"""));

        Assert.False(resolution.Success);
        Assert.Contains(ProjectFile.FileName, resolution.Error);
    }

    /// <summary>
    /// What resolution produces for the next build to believe, rather than
    /// resolve again.
    /// </summary>
    [Fact]
    public void WritesWhatItDecidedIntoALock()
    {
        Package("geometry", "1.2.0");

        var resolution = Resolve(Package(
            "app", "0.1.0", "executable", """{ "geometry": { "path": "../geometry" } }"""));

        Assert.True(resolution.Success, resolution.Error);

        var locked = resolution.Lock;
        Assert.NotNull(locked);
        Assert.Equal("app", locked.Root);

        var geometry = Assert.Single(locked.Packages);
        Assert.Equal("geometry", geometry.Name);
        Assert.Equal("1.2.0", geometry.Version);
        Assert.Null(geometry.Revision);

        // The ABI digest comes from a build, and resolving is not one.
        Assert.Null(geometry.AbiDigest);
    }

    /// <summary>
    /// A lock file round-trips: what was written is what comes back, which is
    /// the whole basis of a build being reproducible from it.
    /// </summary>
    [Fact]
    public void ReadsBackWhatItWrote()
    {
        Package("geometry", "1.2.0");

        var resolution = Resolve(Package(
            "app", "0.1.0", "executable", """{ "geometry": { "path": "../geometry" } }"""));

        string path = Path.Combine(_root, PackageLock.FileName);
        resolution.Lock!.Write(path);

        var read = PackageLock.Read(path, out string error);
        Assert.True(read is not null, error);

        Assert.Equal(resolution.Lock.Root, read!.Root);
        Assert.Equal(
            resolution.Lock.Packages[0].SourceDigest, read.Packages[0].SourceDigest);
    }

    /// <summary>
    /// The source digest is what makes a lock a lock for a dependency with no
    /// commit and no release: it moves when the files do.
    /// </summary>
    [Fact]
    public void NoticesThatAPathDependencyChanged()
    {
        var geometry = Package("geometry", "1.2.0");

        var app = Package(
            "app", "0.1.0", "executable", """{ "geometry": { "path": "../geometry" } }""");

        string before = Resolve(app).Order[0].SourceDigest;

        File.AppendAllText(
            Path.Combine(geometry.Directory, "src", "geometry.sl"),
            "\npublic int More() { return 1; }\n");

        Assert.NotEqual(before, Resolve(app).Order[0].SourceDigest);
    }

    /// <summary>
    /// What a build writes must not move it, or every first build would look
    /// like a change to the source that was resolved.
    /// </summary>
    [Fact]
    public void IgnoresWhatABuildLeavesBehind()
    {
        var geometry = Package("geometry", "1.2.0");

        var app = Package(
            "app", "0.1.0", "executable", """{ "geometry": { "path": "../geometry" } }""");

        string before = Resolve(app).Order[0].SourceDigest;

        Directory.CreateDirectory(Path.Combine(geometry.Directory, "obj"));
        File.WriteAllText(Path.Combine(geometry.Directory, "obj", "geometry.ll"), "; ir");
        Directory.CreateDirectory(Path.Combine(geometry.Directory, "build"));
        File.WriteAllText(Path.Combine(geometry.Directory, "build", "geometry.dll"), "MZ");

        Assert.Equal(before, Resolve(app).Order[0].SourceDigest);
    }
}
