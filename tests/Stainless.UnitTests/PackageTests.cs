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
using Stainless.Driver;
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// Versions, the ranges that accept them, and the digests that check what a
/// version only promises.
///
/// These are worth testing the way the mangler is: both sides of every
/// comparison are ours, so a rule that is wrong in a consistent way agrees with
/// itself perfectly and is still wrong. The caret's behaviour below 1.0 and the
/// prerelease rule are the two that every package manager has had to fix at
/// least once.
/// </summary>
public class VersionTests
{
    [Theory]
    [InlineData("1.2.3", 1, 2, 3)]
    [InlineData("0.0.1", 0, 0, 1)]
    [InlineData("10.20.30", 10, 20, 30)]
    public void ReadsThreeNumbers(string text, int major, int minor, int patch)
    {
        var version = SemanticVersion.Parse(text);

        Assert.Equal(major, version.Major);
        Assert.Equal(minor, version.Minor);
        Assert.Equal(patch, version.Patch);
        Assert.Equal(text, version.ToString());
    }

    [Theory]
    [InlineData("1.2")]
    [InlineData("1.2.3.4")]
    [InlineData("1.2.x")]
    [InlineData("")]
    [InlineData("v1.2.3")]
    public void RefusesWhatIsNotAVersion(string text) =>
        Assert.False(SemanticVersion.TryParse(text, out _, out _));

    [Fact]
    public void ReadsAPreReleaseAndItsBuild()
    {
        var version = SemanticVersion.Parse("1.0.0-alpha.1+build.5");

        Assert.Equal(["alpha", "1"], version.PreRelease);
        Assert.Equal("build.5", version.Build);
        Assert.True(version.IsPreRelease);
        Assert.Equal("1.0.0-alpha.1+build.5", version.ToString());
    }

    [Theory]
    [InlineData("1.0.0", "2.0.0")]
    [InlineData("1.0.0", "1.1.0")]
    [InlineData("1.0.0", "1.0.1")]
    // A prerelease is older than the release it leads to, which is the one
    // ordering rule about it that surprises people.
    [InlineData("1.0.0-alpha", "1.0.0")]
    [InlineData("1.0.0-alpha", "1.0.0-beta")]
    [InlineData("1.0.0-alpha", "1.0.0-alpha.1")]
    // Numeric identifiers compare as numbers, so 9 is below 10 rather than above.
    [InlineData("1.0.0-alpha.9", "1.0.0-alpha.10")]
    // ... and rank below alphabetic ones.
    [InlineData("1.0.0-1", "1.0.0-alpha")]
    public void OrdersVersions(string lower, string higher)
    {
        var a = SemanticVersion.Parse(lower);
        var b = SemanticVersion.Parse(higher);

        Assert.True(a < b, $"{a} should be below {b}");
        Assert.True(b > a);
        Assert.NotEqual(a, b);
    }

    /// <summary>Build metadata has no bearing on which version is newer.</summary>
    [Fact]
    public void IgnoresBuildMetadataWhenComparing() =>
        Assert.Equal(SemanticVersion.Parse("1.0.0+a"), SemanticVersion.Parse("1.0.0+b"));

    [Theory]
    // A bare version is a caret, which is Cargo's reading rather than npm's.
    [InlineData("1.2.0", "1.2.0", true)]
    [InlineData("1.2.0", "1.9.9", true)]
    [InlineData("1.2.0", "2.0.0", false)]
    [InlineData("1.2.0", "1.1.0", false)]
    [InlineData("^1.2.0", "1.9.9", true)]
    // Below 1.0 the minor does the major's job.
    [InlineData("^0.2.3", "0.2.9", true)]
    [InlineData("^0.2.3", "0.3.0", false)]
    [InlineData("^0.0.3", "0.0.3", true)]
    [InlineData("^0.0.3", "0.0.4", false)]
    // The tilde keeps the minor whatever the numbers are.
    [InlineData("~1.2.3", "1.2.9", true)]
    [InlineData("~1.2.3", "1.3.0", false)]
    [InlineData("~1.2", "1.2.9", true)]
    [InlineData("~1", "1.9.0", true)]
    [InlineData("~1", "2.0.0", false)]
    // An equals is the way to pin.
    [InlineData("=1.2.0", "1.2.0", true)]
    [InlineData("=1.2.0", "1.2.1", false)]
    [InlineData(">=1.2, <2.0", "1.9.0", true)]
    [InlineData(">=1.2, <2.0", "2.0.0", false)]
    [InlineData("*", "99.0.0", true)]
    // A partial bound fills the missing numbers with zero.
    [InlineData("^1", "1.5.0", true)]
    [InlineData("^1", "0.9.0", false)]
    public void AcceptsWhatItShould(string requirement, string version, bool accepted)
    {
        Assert.True(VersionRequirement.TryParse(requirement, out var parsed, out string error), error);
        Assert.Equal(accepted, parsed!.Accepts(SemanticVersion.Parse(version)));
    }

    /// <summary>
    /// The rule that keeps '^1.0.0' from quietly taking '2.0.0-alpha', which
    /// compares below 2.0.0 and is not what anybody means by the range.
    /// </summary>
    [Fact]
    public void DoesNotTakeAPreReleaseThatWasNotAskedFor()
    {
        Assert.True(VersionRequirement.TryParse("^1.0.0", out var range, out _));

        Assert.False(range!.Accepts(SemanticVersion.Parse("2.0.0-alpha")));
        Assert.False(range.Accepts(SemanticVersion.Parse("1.5.0-beta")));
        Assert.True(range.Accepts(SemanticVersion.Parse("1.5.0")));
    }

    [Fact]
    public void TakesAPreReleaseThatWasAskedFor()
    {
        Assert.True(VersionRequirement.TryParse(">=1.0.0-alpha, <2.0.0", out var range, out _));

        Assert.True(range!.Accepts(SemanticVersion.Parse("1.0.0-alpha.2")));
        Assert.True(range.Accepts(SemanticVersion.Parse("1.4.0")));
    }

    [Theory]
    [InlineData("")]
    [InlineData("~>1.2")]
    [InlineData("1.x")]
    public void RefusesWhatIsNotARequirement(string text) =>
        Assert.False(VersionRequirement.TryParse(text, out _, out _));
}

/// <summary>
/// The fingerprint that makes a version claim checkable.
///
/// What matters here is not that it hashes -- anything hashes -- but *what it
/// is a hash of*: it has to move when a layout moves and hold still when
/// nothing a consumer can observe has.
/// </summary>
public class DigestTests
{
    private static ModuleMetadata Metadata(params MetadataType[] types) =>
        new ModuleMetadata
        {
            Library = "test.dll",
            Package = "test",
            PackageVersion = "1.0.0",
            Types = [.. types],
            Functions = [],
        }.Sealed();

    private static MetadataType Point(params MetadataField[] fields) => new()
    {
        Kind = MetadataKind.Struct,
        Module = "M",
        Name = "Point",
        Size = fields.Length * 4,
        Alignment = 4,
        Fields = [.. fields],
    };

    private static MetadataField Field(string name, int offset) => new()
    {
        Name = name,
        Type = "int",
        Offset = offset,
        IsPublic = true,
    };

    [Fact]
    public void IsStableAcrossTwoDescriptionsOfOneThing() =>
        Assert.Equal(
            Metadata(Point(Field("X", 0), Field("Y", 4))).AbiDigest,
            Metadata(Point(Field("X", 0), Field("Y", 4))).AbiDigest);

    /// <summary>
    /// The failure the whole mechanism exists for: a field inserted in the
    /// middle, with the same name, the same count and the same size.
    /// </summary>
    [Fact]
    public void MovesWhenAnOffsetMoves() =>
        Assert.NotEqual(
            Metadata(Point(Field("X", 0), Field("Y", 4))).AbiDigest,
            Metadata(Point(Field("X", 0), Field("Y", 8))).AbiDigest);

    [Fact]
    public void MovesWhenAFieldIsAdded() =>
        Assert.NotEqual(
            Metadata(Point(Field("X", 0))).AbiDigest,
            Metadata(Point(Field("X", 0), Field("Y", 4))).AbiDigest);

    /// <summary>
    /// A public field's name is how it is read, so renaming one is a change to
    /// the surface even though no machine code moves.
    /// </summary>
    [Fact]
    public void MovesWhenAFieldIsRenamed() =>
        Assert.NotEqual(
            Metadata(Point(Field("X", 0))).AbiDigest,
            Metadata(Point(Field("Renamed", 0))).AbiDigest);

    /// <summary>
    /// Two files listing one type's fields in a different order describe the
    /// same layout, because the offsets say so. The digest must agree.
    /// </summary>
    [Fact]
    public void HoldsStillWhenOnlyTheOrderOfDescriptionChanges() =>
        Assert.Equal(
            Metadata(Point(Field("X", 0), Field("Y", 4))).AbiDigest,
            Metadata(Point(Field("Y", 4), Field("X", 0))).AbiDigest);

    /// <summary>
    /// Renaming the file a library is built into changes nothing about how the
    /// code in it is called.
    /// </summary>
    [Fact]
    public void HoldsStillWhenTheLibraryIsRenamed()
    {
        var one = Metadata(Point(Field("X", 0)));
        var two = (one with { Library = "renamed.dll" }).Sealed();

        Assert.Equal(one.AbiDigest, two.AbiDigest);
    }

    [Fact]
    public void NamesTheTypeThatMoved()
    {
        var before = Metadata(Point(Field("X", 0), Field("Y", 4)));
        var after = Metadata(Point(Field("X", 0), Field("Y", 8)));

        Assert.NotEqual(before.Types[0].Digest, after.Types[0].Digest);
    }

    /// <summary>
    /// Metadata is readable JSON, which makes it editable JSON. Editing one is
    /// how a consumer compiles against a layout the library does not have.
    /// </summary>
    [Fact]
    public void NoticesAnEditedFile()
    {
        var metadata = Metadata(Point(Field("X", 0)));
        Assert.True(metadata.DigestMatches());

        var edited = metadata with
        {
            Types = [Point(Field("X", 4))],
        };

        Assert.False(edited.DigestMatches());
    }
}

/// <summary>
/// The record of why a dependency did not need rebuilding.
///
/// This is the only thing in the compiler that decides not to do work, so it is
/// the only thing that can be wrong without anything saying so: a build skipped
/// when it should not have been links perfectly against stale code. Every way
/// of failing to read one has to mean "build it".
/// </summary>
public class BuildStampTests
{
    private static string Temp()
    {
        string directory = Path.Combine(
            Path.GetTempPath(), "stainless-stamp", Path.GetRandomFileName());

        Directory.CreateDirectory(directory);
        return Path.Combine(directory, BuildStamp.FileName);
    }

    [Fact]
    public void ReadsBackWhatItWrote()
    {
        string path = Temp();
        new BuildStamp { Inputs = "abc", AbiDigest = "def" }.Write(path);

        var stamp = BuildStamp.Read(path);

        Assert.NotNull(stamp);
        Assert.Equal("abc", stamp.Inputs);
        Assert.Equal("def", stamp.AbiDigest);
    }

    [Fact]
    public void IsNothingWhenThereIsNoFile() =>
        Assert.Null(BuildStamp.Read(Temp()));

    /// <summary>
    /// A half-written or hand-edited stamp says nothing about what is on disk,
    /// and the safe reading of "says nothing" is "build it".
    /// </summary>
    [Fact]
    public void IsNothingWhenTheFileIsNotOne()
    {
        string path = Temp();
        File.WriteAllText(path, "{ this is not json");

        Assert.Null(BuildStamp.Read(path));
    }

    /// <summary>
    /// A stamp from a format this compiler does not know describes inputs it
    /// cannot compare, so it cannot be believed.
    /// </summary>
    [Fact]
    public void IsNothingWhenTheFormatIsFromElsewhere()
    {
        string path = Temp();
        File.WriteAllText(path, """{ "format": 99, "inputs": "abc", "abiDigest": "def" }""");

        Assert.Null(BuildStamp.Read(path));
    }

    /// <summary>
    /// Failing to write one costs a rebuild next time, which is what happens
    /// with no stamp at all. Failing the build over it would turn a slow build
    /// into no build.
    /// </summary>
    [Fact]
    public void SaysNothingWhenItCannotBeWritten()
    {
        string path = Path.Combine(Temp(), "not-a-directory", BuildStamp.FileName);
        File.WriteAllText(Path.GetDirectoryName(Path.GetDirectoryName(path))!, "");

        new BuildStamp { Inputs = "a", AbiDigest = "b" }.Write(path);
    }
}

/// <summary>
/// The project file, which is the most user-visible surface after the language
/// itself and the one where a silent misreading costs the most.
/// </summary>
public class ProjectFileTests
{
    private static string Write(string json)
    {
        string directory = Path.Combine(
            Path.GetTempPath(), "stainless-tests", Path.GetRandomFileName());

        Directory.CreateDirectory(directory);

        string path = Path.Combine(directory, ProjectFile.FileName);
        File.WriteAllText(path, json);
        return path;
    }

    [Fact]
    public void ReadsAMinimalProject()
    {
        var project = ProjectFile.Read(Write("""
            { "name": "app", "version": "1.0.0", "sources": ["src"] }
            """), out string error);

        Assert.Null(error is "" ? null : error);
        Assert.NotNull(project);
        Assert.Equal("app", project.Name);
        Assert.Equal(ProjectKind.Executable, project.Kind);
        Assert.Equal(["src"], project.Sources);
    }

    /// <summary>
    /// A cross-platform program is the case one flat list of sources cannot
    /// state, and the reason every Forms program in this tree was built by a
    /// shell script rather than by its own project file.
    /// </summary>
    [Fact]
    public void APlatformSectionAddsToTheBaseLists()
    {
        var project = ProjectFile.Read(Write("""
            {
              "name": "app", "version": "1.0.0",
              "sources": ["src"], "libraries": ["m"], "defines": ["SHARED"],
              "windows": {
                "sources": ["bindings/win32"], "libraries": ["user32"],
                "defines": ["WIN"]
              },
              "linux": {
                "sources": ["bindings/gtk"], "libraries": [":libgtk-3.so.0"]
              }
            }
            """), out string error);

        Assert.Null(error is "" ? null : error);
        Assert.NotNull(project);

        Assert.Equal(["src", "bindings/win32"], project.SourcesFor(TargetPlatform.X64Windows));
        Assert.Equal(["m", "user32"], project.LibrariesFor(TargetPlatform.X64Windows));
        Assert.Equal(["SHARED", "WIN"], project.DefinesFor(TargetPlatform.X64Windows));

        Assert.Equal(["src", "bindings/gtk"], project.SourcesFor(TargetPlatform.X64Linux));
        Assert.Equal(["m", ":libgtk-3.so.0"], project.LibrariesFor(TargetPlatform.X64Linux));

        // The overlay adds; it does not replace. A Linux build keeps the base
        // define and gains nothing, because that overlay names none.
        Assert.Equal(["SHARED"], project.DefinesFor(TargetPlatform.X64Linux));
    }

    /// <summary>
    /// A project naming no platform section answers the base lists themselves,
    /// which is the common case and should allocate nothing.
    /// </summary>
    [Fact]
    public void NoPlatformSectionLeavesTheListsAlone()
    {
        var project = ProjectFile.Read(Write("""
            { "name": "app", "version": "1.0.0", "sources": ["src"] }
            """), out _);

        Assert.NotNull(project);
        Assert.Same(project.Sources, project.SourcesFor(TargetPlatform.X64Windows));
        Assert.Same(project.Sources, project.SourcesFor(TargetPlatform.X64Linux));
    }

    [Fact]
    public void RefusesAFieldAPlatformSectionDoesNotHave()
    {
        ProjectFile.Read(Write("""
            {
              "name": "app", "version": "1.0.0",
              "windows": { "libaries": ["user32"] }
            }
            """), out string error);

        Assert.Contains("is not a field of a platform section", error);
        Assert.Contains("did you mean 'libraries'", error);
    }

    /// <summary>
    /// <c>#if</c> sees the platform being built <i>for</i>.
    ///
    /// The architecture was made to follow the target years before the
    /// operating system was, on the argument that a target did not change which
    /// platform the standard library binds to -- and the standard library
    /// chooses its platform with these very symbols, so it did.
    /// </summary>
    [Fact]
    public void TheSymbolsFollowTheTarget()
    {
        var windows = Compilation.PlatformSymbols([], TargetPlatform.X64Windows);
        Assert.Contains("WINDOWS", windows);
        Assert.DoesNotContain("UNIX", windows);
        Assert.DoesNotContain("LINUX", windows);
        Assert.Contains("X64", windows);

        var linux = Compilation.PlatformSymbols([], TargetPlatform.X64Linux);
        Assert.Contains("LINUX", linux);
        Assert.Contains("UNIX", linux);
        Assert.DoesNotContain("WINDOWS", linux);

        var small = Compilation.PlatformSymbols([], TargetPlatform.X86Linux);
        Assert.Contains("X86", small);
        Assert.Contains("UNIX", small);
        Assert.DoesNotContain("X64", small);
    }

    /// <summary>
    /// With no target named the host still answers, and it has to: there is no
    /// macOS or FreeBSD triple, so deriving the symbols from
    /// <see cref="TargetPlatform.Host"/> would take <c>MACOS</c> away from a
    /// machine that has it.
    /// </summary>
    [Fact]
    public void WithNoTargetTheHostStillAnswers()
    {
        var symbols = Compilation.PlatformSymbols([]);

        Assert.Equal(OperatingSystem.IsWindows(), symbols.Contains("WINDOWS"));
        Assert.Equal(OperatingSystem.IsMacOS(), symbols.Contains("MACOS"));
        Assert.Equal(!OperatingSystem.IsWindows(), symbols.Contains("UNIX"));
    }

    /// <summary>
    /// The reason unknown fields are refused rather than ignored: a typo that
    /// does nothing is a build that silently is not the one that was asked for.
    /// </summary>
    [Fact]
    public void RefusesAFieldItDoesNotKnow()
    {
        var project = ProjectFile.Read(Write("""
            { "name": "app", "version": "1.0.0", "optimise": 3 }
            """), out string error);

        Assert.Null(project);
        Assert.Contains("'optimise' is not a field", error);
        Assert.Contains("did you mean 'optimize'", error);
    }

    [Fact]
    public void ListsTheFieldsWhenNothingIsClose()
    {
        ProjectFile.Read(Write("""
            { "name": "app", "version": "1.0.0", "frobnicate": 3 }
            """), out string error);

        Assert.Contains("The fields are:", error);
        Assert.Contains("sources", error);
    }

    [Theory]
    [InlineData("""{ "name": "app", "version": "one" }""", "not a version")]
    [InlineData("""{ "name": "a b", "version": "1.0.0" }""", "package name")]
    [InlineData("""{ "name": "app", "version": "1.0.0", "sources": [] }""", "lists no sources")]
    [InlineData("""{ "name": "app", "version": "1.0.0", "optimize": 9 }""", "levels are 0 to 3")]
    [InlineData("""{ "name": "app", "version": "1.0.0", "abi": "sunpro" }""", "'microsoft' or 'itanium'")]
    public void RefusesWhatCannotBeBuilt(string json, string expected)
    {
        Assert.Null(ProjectFile.Read(Write(json), out string error));
        Assert.Contains(expected, error);
    }

    /// <summary>
    /// JSON `null` lands in a property whatever its type says, and the
    /// deserializer does not count it as missing. Each of these was a
    /// NullReferenceException with a stack trace before it was a message.
    /// </summary>
    [Theory]
    [InlineData("""{ "name": null, "version": "1.0.0" }""", "has the name 'null'")]
    [InlineData("""{ "name": "app", "version": null }""", "'version' is null")]
    [InlineData("""{ "name": "app", "version": "1.0.0", "sources": null }""", "lists no sources")]
    [InlineData("""{ "name": "app", "version": "1.0.0", "sources": [""] }""", "lists no sources")]
    [InlineData("""{ "name": "app", "version": "1.0.0", "dependencies": null }""", "'dependencies' is null")]
    [InlineData("""{ "name": "app", "version": "1.0.0", "dependencies": { "geo": null } }""", "'geo' is null")]
    [InlineData("""{ "name": "app", "version": "1.0.0", "libraries": null }""", "'libraries'")]
    [InlineData("""{ "name": "app", "version": "1.0.0", "libraries": [""] }""", "one of them is empty")]
    [InlineData("""{ "name": "app", "version": "1.0.0", "defines": null }""", "not a symbol")]
    [InlineData("""{ "name": "app", "version": "1.0.0", "defines": ["9x"] }""", "'9x' is not a symbol")]
    [InlineData("""{ "name": "app", "version": "1.0.0", "output": "" }""", "'output' is empty")]
    [InlineData("""{ "name": "app", "version": "1.0.0", "buildDirectory": " " }""", "'buildDirectory' is empty")]
    public void RefusesANullOrEmptyFieldWithAMessage(string json, string expected)
    {
        Assert.Null(ProjectFile.Read(Write(json), out string error));
        Assert.Contains(expected, error);
    }

    /// <summary>
    /// A value of the wrong shape is named by its field and what it takes,
    /// not by the .NET type the framework could not make.
    /// </summary>
    [Theory]
    [InlineData("""{ "name": "app", "version": "1.0.0", "kind": "dll" }""", "'kind' takes 'executable' or 'library'")]
    [InlineData("""{ "name": "app", "version": "1.0.0", "optimize": "two" }""", "'optimize' takes a number")]
    [InlineData("""{ "name": "app", "version": "1.0.0", "debug": "yes" }""", "'debug' takes true or false")]
    [InlineData("""{ "name": "app", "version": "1.0.0", "sources": "src" }""", "'sources' takes a list")]
    [InlineData("""{ "name": "app", "version": "1.0.0", "dependencies": [] }""", "'dependencies' takes an object of names")]
    [InlineData("""{ "name": "app", "version": "1.0.0", "dependencies": { "geo": "^1" } }""", "'dependencies.geo' takes an object")]
    [InlineData("""{ "name": "app", "version": "1.0.0", "dependencies": { "geo": { "path": ".", "link": "dynamic" } } }""", "'dependencies.geo.link' takes 'source' or 'shared'")]
    [InlineData("""[]""", "a project file is an object")]
    public void NamesTheFieldWhenAValueHasTheWrongShape(string json, string expected)
    {
        Assert.Null(ProjectFile.Read(Write(json), out string error));
        Assert.Contains(expected, error);
        Assert.DoesNotContain("System.", error);
    }

    [Theory]
    [InlineData("DEBUG", true)]
    [InlineData("_x1", true)]
    [InlineData("Ünïcode", true)]
    [InlineData("9x", false)]
    [InlineData("a b", false)]
    [InlineData("", false)]
    [InlineData("A=1", false)]
    public void ADefineIsSpelledLikeAnIdentifier(string define, bool valid) =>
        Assert.Equal(valid, ProjectFile.IsValidDefine(define));

    [Theory]
    [InlineData("""{ "geo": {} }""", "neither 'path' nor 'git'")]
    [InlineData("""{ "geo": { "path": "../g", "git": "u" } }""", "both 'path' and 'git'")]
    [InlineData("""{ "geo": { "path": "../g", "tag": "v1" } }""", "nothing to select")]
    [InlineData("""{ "geo": { "git": "u", "tag": "v1", "rev": "abc" } }""", "more than one")]
    [InlineData("""{ "geo": { "path": "../g", "version": "~>1" } }""", "not a requirement")]
    public void RefusesADependencyThatCannotBeFetched(string dependencies, string expected)
    {
        Assert.Null(ProjectFile.Read(Write($$"""
            { "name": "app", "version": "1.0.0", "dependencies": {{dependencies}} }
            """), out string error));

        Assert.Contains(expected, error);
    }

    /// <summary>
    /// A path in a project file is relative to the file, never to wherever the
    /// build happened to be started -- which is what makes a build from three
    /// directories down the same build.
    /// </summary>
    [Fact]
    public void ResolvesPathsAgainstItself()
    {
        string path = Write("""
            { "name": "app", "version": "1.0.0", "sources": ["src"] }
            """);

        var project = ProjectFile.Read(path, out _)!;
        string directory = Path.GetDirectoryName(path)!;

        Assert.Equal(Path.Combine(directory, "src"), project.Resolve("src"));
        Assert.Equal(
            Path.Combine(directory, "build", "app" + Toolchain.ExecutableExtension),
            project.OutputPath());
    }

    /// <summary>
    /// A generated library name is the platform's: 'libshapes.so' where that is
    /// what makes a library findable, 'shapes.dll' where it is not. Its metadata
    /// is named after the package either way, because 'libshapes.slmod'
    /// describes nothing.
    /// </summary>
    [Fact]
    public void NamesALibraryTheWayThePlatformDoes()
    {
        string path = Write("""
            { "name": "shapes", "version": "1.0.0", "kind": "library" }
            """);

        var project = ProjectFile.Read(path, out _)!;
        string build = Path.Combine(Path.GetDirectoryName(path)!, "build");

        Assert.Equal(
            Path.Combine(build, Toolchain.SharedLibraryFileName("shapes")),
            project.OutputPath());

        Assert.Equal(Path.Combine(build, "shapes.slmod"), project.MetadataPath());

        Assert.Equal(
            OperatingSystem.IsWindows() ? "shapes.dll" : "libshapes" + Toolchain.SharedLibraryExtension,
            Path.GetFileName(project.OutputPath()));
    }

    /// <summary>Metadata follows the binary when '-o' moves it.</summary>
    [Fact]
    public void KeepsMetadataBesideWhereverTheLibraryWent()
    {
        string path = Write("""
            { "name": "shapes", "version": "1.0.0", "kind": "library", "output": "out/x.dll" }
            """);

        var project = ProjectFile.Read(path, out _)!;

        Assert.Equal(
            Path.Combine(Path.GetDirectoryName(project.OutputPath())!, "shapes.slmod"),
            project.MetadataPath());
    }

    [Fact]
    public void FindsAProjectFromBelowIt()
    {
        string path = Write("""
            { "name": "app", "version": "1.0.0" }
            """);

        string deep = Path.Combine(Path.GetDirectoryName(path)!, "src", "deep");
        Directory.CreateDirectory(deep);

        Assert.Equal(path, ProjectFile.Find(deep));
    }

    /// <summary>
    /// A starter file states what a project cannot do without and nothing else.
    /// A generated file full of defaults reads as though all of it matters.
    /// </summary>
    [Fact]
    public void WritesAStarterWithNoDefaultsInIt()
    {
        string path = Write("{}");

        new ProjectFile { Name = "app", Version = "0.1.0", Sources = ["src"] }
            .WriteStarter(path);

        string written = File.ReadAllText(path);

        Assert.Contains("\"name\": \"app\"", written);
        Assert.DoesNotContain("objectDirectory", written);
        Assert.DoesNotContain("dependencies", written);

        Assert.NotNull(ProjectFile.Read(path, out _));
    }
}

/// <summary>
/// The spelling a type crosses a library boundary under.
///
/// Both halves are ours, so the only test worth writing is the round trip:
/// what the writer produces, the reader has to accept, and a name only one of
/// them knows is silent on both sides. That is how <c>char16</c> and
/// <c>char32</c> came to be written by a library and unreadable by anything
/// that referenced it -- the reader's list of primitives was a second copy of
/// the type system's, and it was two names short.
/// </summary>
public class MetadataTypeNameTests
{
    /// <summary>
    /// Every primitive there is, taken from the type system rather than
    /// listed here, so a new one fails this until it can cross.
    /// </summary>
    public static TheoryData<string> EveryPrimitive()
    {
        var data = new TheoryData<string>();
        foreach (var primitive in PrimitiveTypeSymbol.All) data.Add(primitive.Name);
        return data;
    }

    [Theory]
    [MemberData(nameof(EveryPrimitive))]
    public void EveryPrimitiveRoundTrips(string name)
    {
        var read = MetadataTypeNames.Read(name, _ => null);

        Assert.NotNull(read);
        Assert.Equal(name, MetadataTypeNames.Write(read));
    }

    /// <summary>
    /// A wrapper round-trips whatever it wraps, and the reader has to accept
    /// every shape the writer can produce. A slice and a tuple are named types
    /// the binder interns, so they are built through the factories a real
    /// compilation passes; here they are stood in for by their element.
    /// </summary>
    [Theory]
    [InlineData("int*")]
    [InlineData("byte**")]
    [InlineData("int[]")]
    [InlineData("char16[]")]
    [InlineData("int[][]")]
    [InlineData("int[4]")]
    [InlineData("double[16]")]
    [InlineData("nuint?")]
    [InlineData("char32*")]
    public void EveryWrapperRoundTrips(string name)
    {
        var read = MetadataTypeNames.Read(name, _ => null);

        Assert.NotNull(read);
        Assert.Equal(name, MetadataTypeNames.Write(read));
    }

    /// <summary>
    /// A name that mentions nothing a consumer could resolve is refused rather
    /// than guessed at, which is what turns it into a diagnostic where the
    /// library is built instead of a puzzle where it is used.
    /// </summary>
    [Theory]
    [InlineData("Lib.Point")]
    [InlineData("Lib.Point[]")]
    [InlineData("Lib.Point?")]
    [InlineData("weak Lib.Point?")]
    [InlineData("Lib.Point[:]")]
    [InlineData("(int, Lib.Point)")]
    public void RefusesANameNothingKnows(string name) =>
        Assert.Null(MetadataTypeNames.Read(name, _ => null));

    /// <summary>
    /// What the writer checks before it describes a surface: the named types a
    /// written name is built out of, with the primitives left out because every
    /// program already has those.
    /// </summary>
    [Theory]
    [InlineData("int", new string[0])]
    [InlineData("char16[]", new string[0])]
    [InlineData("int[:]", new string[0])]
    [InlineData("Lib.Point", new[] { "Lib.Point" })]
    [InlineData("Lib.Point[:]", new[] { "Lib.Point" })]
    [InlineData("weak Lib.Node?", new[] { "Lib.Node" })]
    [InlineData("(int, Lib.Point)", new[] { "Lib.Point" })]
    [InlineData("(Lib.A, Lib.B[])", new[] { "Lib.A", "Lib.B" })]
    public void NamesWhatAConsumerWouldHaveToResolve(string written, string[] expected) =>
        Assert.Equal(expected, MetadataTypeNames.LeafNames(written));

    /// <summary>
    /// A tuple's own commas are what it is split at, and an element may be a
    /// tuple itself.
    /// </summary>
    [Fact]
    public void SplitsANestedTupleAtItsOwnCommas() =>
        Assert.Equal(
            ["Lib.A", "Lib.B", "Lib.C"],
            MetadataTypeNames.LeafNames("((Lib.A, Lib.B), Lib.C)"));
}
