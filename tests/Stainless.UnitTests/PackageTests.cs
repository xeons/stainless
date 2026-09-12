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
