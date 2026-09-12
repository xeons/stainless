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

using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace Stainless.Driver;

/// <summary>
/// A project, as a file rather than as a command line.
///
/// The command line has said everything a build needs since the beginning, and
/// for one file it is the shorter way to say it. What it cannot do is be *read*:
/// a tool that wants to know what this program is made of -- an editor, a
/// language server, the package resolver below -- can only run a build and watch
/// what happens. That is the whole reason this exists and the reason it is a
/// document rather than a script. A Makefile would build the program perfectly
/// well and answer no questions about it.
///
/// JSON because both sides can already read it: the compiler has one parser in
/// the framework and the standard library has another in Stainless, so a
/// program written in this language can read its own project file without
/// anything new being written. A nicer syntax would cost two parsers for ever.
///
/// Every path in here is relative to the file's own directory, never to the
/// working directory, so a build means the same thing from anywhere.
/// </summary>
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record ProjectFile
{
    public const string FileName = "stainless.json";

    /// <summary>
    /// Bumped when a field changes meaning rather than when one is added, since
    /// an older compiler reading a newer file already refuses what it does not
    /// recognise. Absent means 1, so the first version of the format never had
    /// to write it.
    /// </summary>
    public const int CurrentVersion = 1;

    public int Format { get; init; } = CurrentVersion;

    /// <summary>
    /// What this package is called. It names the package in a dependency, in
    /// the lock file and in the cache, so it is restricted to what is safe in
    /// all three.
    /// </summary>
    public required string Name { get; init; }

    /// <summary>
    /// The version this package publishes itself as. Required, because a
    /// dependency that cannot say what it is cannot be depended on.
    /// </summary>
    public required string Version { get; init; }

    public ProjectKind Kind { get; init; } = ProjectKind.Executable;

    /// <summary>
    /// What to compile: .sl files and directories, and any C source or object
    /// file that belongs to the same program. Exactly what the command line
    /// accepts as a path, because it is handed to the same expander.
    /// </summary>
    public List<string> Sources { get; init; } = ["src"];

    /// <summary>Where the binary goes. Null puts it under <see cref="BuildDirectory"/>.</summary>
    public string? Output { get; init; }

    /// <summary>Where built binaries and the metadata of a library go.</summary>
    public string BuildDirectory { get; init; } = "build";

    /// <summary>Where intermediates go, matching <c>--obj</c>.</summary>
    public string ObjectDirectory { get; init; } = "obj";

    /// <summary>A C header for the exported surface, if this package wants one.</summary>
    public string? Header { get; init; }

    /// <summary>
    /// What this package depends on, by name.
    ///
    /// The name on the left is what this project calls it, and it has to match
    /// the dependency's own <see cref="Name"/> -- two names for one package is
    /// how a lock file starts lying.
    /// </summary>
    public Dictionary<string, Dependency> Dependencies { get; init; } =
        new(StringComparer.Ordinal);

    /// <summary>Libraries the linker finds by name, matching <c>-l</c>.</summary>
    public List<string> Libraries { get; init; } = [];

    /// <summary>Symbols <c>#if</c> can test, matching <c>-D</c>.</summary>
    public List<string> Defines { get; init; } = [];

    public int Optimize { get; init; } = 2;
    public bool Debug { get; init; }

    /// <summary>"microsoft" or "itanium"; null is the host's.</summary>
    public string? Abi { get; init; }

    /// <summary>"shared" or "static"; null lets the build decide as it always did.</summary>
    public string? Runtime { get; init; }

    // --------------------------------------------------------------- derived

    /// <summary>The directory the file was read from. Not serialized.</summary>
    [JsonIgnore] public string Directory { get; init; } = ".";

    /// <summary>The file itself, for a diagnostic that can name it.</summary>
    [JsonIgnore] public string Path => System.IO.Path.Combine(Directory, FileName);

    [JsonIgnore] public bool IsLibrary => Kind == ProjectKind.Library;

    /// <summary>Resolves a path written in the file against the file's own directory.</summary>
    public string Resolve(string path) =>
        System.IO.Path.GetFullPath(System.IO.Path.Combine(Directory, path));

    /// <summary>
    /// Where this package's binary lands: what <c>output</c> said, or the
    /// package name under the build directory with the platform's extension.
    /// </summary>
    public string OutputPath()
    {
        if (Output is not null) return Resolve(Output);

        string extension = IsLibrary
            ? Toolchain.SharedLibraryExtension
            : Toolchain.ExecutableExtension;

        return System.IO.Path.Combine(Resolve(BuildDirectory), Name + extension);
    }

    /// <summary>
    /// Where a library's metadata lands. Named after the binary rather than
    /// after the package, so the two are obviously a pair on disk.
    /// </summary>
    public string MetadataPath() =>
        System.IO.Path.ChangeExtension(OutputPath(), ".slmod");

    /// <summary>The parsed version, which <see cref="Validate"/> has already checked.</summary>
    public SemanticVersion SemanticVersion() => Driver.SemanticVersion.Parse(Version);

    // --------------------------------------------------------------- reading

    private static readonly JsonSerializerOptions Format_ = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    /// <summary>
    /// Walks up from a directory looking for a project file, the way every tool
    /// that has one does. A build from three directories down is still that
    /// project's build.
    /// </summary>
    public static string? Find(string startingAt)
    {
        var directory = new DirectoryInfo(System.IO.Path.GetFullPath(startingAt));

        while (directory is not null)
        {
            string candidate = System.IO.Path.Combine(directory.FullName, FileName);
            if (File.Exists(candidate)) return candidate;
            directory = directory.Parent;
        }

        return null;
    }

    /// <summary>Reads a project file, or explains why it could not be read.</summary>
    public static ProjectFile? Read(string path, out string error)
    {
        error = "";

        try
        {
            string text = File.ReadAllText(path);
            var project = JsonSerializer.Deserialize<ProjectFile>(text, Format_);

            if (project is null)
            {
                error = $"'{path}' is empty";
                return null;
            }

            project = project with
            {
                Directory = System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(path)) ?? ".",
            };

            if (project.Format > CurrentVersion)
            {
                error = $"'{path}' is format {project.Format}, and this compiler reads " +
                        $"{CurrentVersion}. Upgrade the compiler, or lower 'format' if the file " +
                        "does not actually use anything newer";
                return null;
            }

            if (!project.Validate(path, out error)) return null;

            return project;
        }
        catch (JsonException e)
        {
            error = $"could not read '{path}': {Explain(e)}";
            return null;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            error = $"could not read '{path}': {e.Message}";
            return null;
        }
    }

    /// <summary>
    /// Turns the framework's complaint into one about a project file.
    ///
    /// An unknown field is refused rather than ignored, and that choice is only
    /// worth making if the refusal is useful: a typo that does nothing is the
    /// failure this exists to prevent, so the message has to name the typo and,
    /// where it can, what was probably meant. The stock message names a .NET
    /// member and a namespace, neither of which is anything the reader wrote.
    /// </summary>
    private static string Explain(JsonException e)
    {
        var unmapped = System.Text.RegularExpressions.Regex.Match(
            e.Message ?? "",
            @"The JSON property '([^']+)' could not be mapped to any \.NET member contained in " +
            @"type '(?:[\w.]*\.)?(\w+)'");

        if (!unmapped.Success) return e.Message ?? "the file is not valid JSON";

        string wrote = unmapped.Groups[1].Value;
        string where = unmapped.Groups[2].Value == nameof(Dependency)
            ? "a dependency"
            : "a project file";

        var known = Fields(unmapped.Groups[2].Value == nameof(Dependency)
            ? typeof(Dependency)
            : typeof(ProjectFile));

        string? meant = Nearest(wrote, known);

        return $"'{wrote}' is not a field of {where}" +
               (meant is null
                   ? $". The fields are: {string.Join(", ", known)}"
                   : $"; did you mean '{meant}'?");
    }

    /// <summary>The field names as they are spelled in the file.</summary>
    private static List<string> Fields(Type type) =>
        type.GetProperties()
            .Where(p => p.GetCustomAttributes(typeof(JsonIgnoreAttribute), true).Length == 0)
            .Select(p => JsonNamingPolicy.CamelCase.ConvertName(p.Name))
            .OrderBy(n => n, StringComparer.Ordinal)
            .ToList();

    /// <summary>
    /// The closest field name, if one is close enough to be worth suggesting.
    /// Two edits on a short name is a typo; four is a different word, and
    /// guessing at that point is worse than listing what there is.
    /// </summary>
    private static string? Nearest(string wrote, IEnumerable<string> known)
    {
        string? best = null;
        int closest = int.MaxValue;

        foreach (string candidate in known)
        {
            int distance = Distance(wrote.ToLowerInvariant(), candidate.ToLowerInvariant());
            if (distance >= closest) continue;

            closest = distance;
            best = candidate;
        }

        return closest <= Math.Max(2, wrote.Length / 3) ? best : null;
    }

    private static int Distance(string from, string to)
    {
        var row = new int[to.Length + 1];
        for (int j = 0; j <= to.Length; j++) row[j] = j;

        for (int i = 1; i <= from.Length; i++)
        {
            int diagonal = row[0];
            row[0] = i;

            for (int j = 1; j <= to.Length; j++)
            {
                int above = row[j];
                row[j] = Math.Min(
                    Math.Min(row[j] + 1, row[j - 1] + 1),
                    diagonal + (from[i - 1] == to[j - 1] ? 0 : 1));
                diagonal = above;
            }
        }

        return row[to.Length];
    }

    public string ToJson() => JsonSerializer.Serialize(this, Format_);

    public void Write(string path) => File.WriteAllText(path, ToJson() + Environment.NewLine);

    /// <summary>
    /// Writes the four fields a new project actually has to state, and leaves
    /// every default out.
    ///
    /// A generated file full of defaults teaches the wrong thing: it reads as
    /// though all of it matters, and the first edit is somebody deleting lines
    /// to find out which. What is here is what a project cannot do without --
    /// what it is called, what it is, and where its source is.
    /// </summary>
    public void WriteStarter(string path)
    {
        var starter = new JsonObject
        {
            ["name"] = Name,
            ["version"] = Version,
            ["kind"] = Kind.ToString().ToLowerInvariant(),
            ["sources"] = new JsonArray(Sources.Select(s => (JsonNode)s!).ToArray()),
        };

        File.WriteAllText(path, starter.ToJsonString(Format_) + Environment.NewLine);
    }

    // ------------------------------------------------------------ validation

    /// <summary>
    /// Everything that has to be true before a build can start, checked here
    /// rather than as it is reached, so a file with three mistakes in it reports
    /// the first one against the file rather than failing halfway through a
    /// dependency graph.
    /// </summary>
    public bool Validate(string path, out string error)
    {
        error = "";

        if (!IsValidName(Name))
        {
            error = $"'{path}' has the name '{Name}'; a package name is one or more letters, " +
                    "digits, '_', '-' or '.', because it is also a directory in the package cache";
            return false;
        }

        if (!Driver.SemanticVersion.TryParse(Version, out _, out string versionError))
        {
            error = $"'{path}': {versionError}";
            return false;
        }

        if (Sources.Count == 0)
        {
            error = $"'{path}' lists no sources; 'sources' names the files and directories that " +
                    "make up this package";
            return false;
        }

        if (Optimize is < 0 or > 3)
        {
            error = $"'{path}' asks for -O{Optimize}; the levels are 0 to 3";
            return false;
        }

        if (Abi is not null && ParseAbi(Abi) is null)
        {
            error = $"'{path}' names the ABI '{Abi}'; it is 'microsoft' or 'itanium'";
            return false;
        }

        if (Runtime is not null and not "shared" and not "static")
        {
            error = $"'{path}' names the runtime '{Runtime}'; it is 'shared' or 'static'";
            return false;
        }

        foreach (var (name, dependency) in Dependencies)
        {
            if (!IsValidName(name))
            {
                error = $"'{path}' depends on '{name}'; a package name is one or more letters, " +
                        "digits, '_', '-' or '.'";
                return false;
            }

            if (!dependency.Validate(name, path, out error)) return false;
        }

        return true;
    }

    /// <summary>
    /// What may be a package name. Deliberately narrower than what JSON allows:
    /// the name becomes a directory in the cache and a key in the lock file, and
    /// a name that means one thing on Windows and another on Linux would make a
    /// lock file stop being a lock.
    /// </summary>
    public static bool IsValidName(string name) =>
        name.Length > 0 &&
        name.All(c => char.IsAsciiLetterOrDigit(c) || c is '_' or '-' or '.') &&
        name is not "." and not "..";

    public static Binding.CppAbi? ParseAbi(string name) => name.ToLowerInvariant() switch
    {
        "microsoft" or "msvc" => Binding.CppAbi.Microsoft,
        "itanium" or "gnu" or "gcc" => Binding.CppAbi.Itanium,
        _ => null,
    };
}

public enum ProjectKind
{
    /// <summary>A program with a Main.</summary>
    Executable,

    /// <summary>A package other packages depend on.</summary>
    Library,
}

/// <summary>
/// Where a dependency comes from, and which versions of it will do.
///
/// Exactly one source has to be named. There is no registry, so there is no
/// shorthand that means one: a dependency says where it is, and the day a
/// registry exists it becomes a third field rather than a change of meaning for
/// the two that are here.
/// </summary>
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record Dependency
{
    /// <summary>A directory holding a project file, relative to this one.</summary>
    public string? Path { get; init; }

    /// <summary>A git repository URL, cloned into the package cache.</summary>
    public string? Git { get; init; }

    /// <summary>
    /// Which commit of that repository: a tag, a branch or a revision. A tag is
    /// the one worth using, because it is the only one of the three that means
    /// the same thing next week.
    /// </summary>
    public string? Tag { get; init; }
    public string? Branch { get; init; }
    public string? Rev { get; init; }

    /// <summary>
    /// A subdirectory inside the repository, for a repository holding more than
    /// one package.
    /// </summary>
    public string? Subdirectory { get; init; }

    /// <summary>
    /// Which versions are acceptable. Null accepts whatever is there, which is
    /// the sensible default for a path dependency and a loose one for a git
    /// dependency pinned by tag.
    /// </summary>
    public string? Version { get; init; }

    /// <summary>
    /// How the dependency joins this program. See <see cref="DependencyLink"/>:
    /// the default compiles its source in, which is the model the language
    /// actually has.
    /// </summary>
    public DependencyLink Link { get; init; } = DependencyLink.Source;

    [JsonIgnore] public bool IsPath => Path is not null;
    [JsonIgnore] public bool IsGit => Git is not null;

    public VersionRequirement Requirement() =>
        Version is null
            ? VersionRequirement.Any
            : VersionRequirement.TryParse(Version, out var requirement, out _)
                ? requirement!
                : VersionRequirement.Any;

    public bool Validate(string name, string path, out string error)
    {
        error = "";

        if (Path is null && Git is null)
        {
            error = $"'{path}': the dependency '{name}' says neither 'path' nor 'git', so there " +
                    "is nowhere to get it from";
            return false;
        }

        if (Path is not null && Git is not null)
        {
            error = $"'{path}': the dependency '{name}' says both 'path' and 'git'; it comes " +
                    "from one place or the other";
            return false;
        }

        if (Path is not null && (Tag ?? Branch ?? Rev) is not null)
        {
            error = $"'{path}': the dependency '{name}' is a path, so 'tag', 'branch' and 'rev' " +
                    "have nothing to select; what is in the directory is what is used";
            return false;
        }

        int pins = (Tag is null ? 0 : 1) + (Branch is null ? 0 : 1) + (Rev is null ? 0 : 1);
        if (pins > 1)
        {
            error = $"'{path}': the dependency '{name}' names more than one of 'tag', 'branch' " +
                    "and 'rev'; a checkout is one commit";
            return false;
        }

        if (Version is not null &&
            !VersionRequirement.TryParse(Version, out _, out string requirementError))
        {
            error = $"'{path}': the dependency '{name}' asks for version '{Version}', which is " +
                    $"not a requirement: {requirementError}";
            return false;
        }

        return true;
    }

    /// <summary>How this dependency is written in a lock file and a diagnostic.</summary>
    public override string ToString()
    {
        if (Path is not null) return Path;

        string pin = Tag is not null ? "#" + Tag
            : Rev is not null ? "@" + Rev
            : Branch is not null ? ":" + Branch
            : "";

        return Git + pin + (Subdirectory is null ? "" : "/" + Subdirectory);
    }
}

/// <summary>
/// The two ways a package can join the program that depends on it.
///
/// <see cref="Source"/> compiles its files in with everything else. That is the
/// model this language already has -- one program, no headers, whole-program
/// binding -- and it is why generics, interfaces and variants work across a
/// source dependency when they cannot cross a binary one. It is the default
/// because it is the one that has no caveats.
///
/// <see cref="Shared"/> builds the package once, as a real shared library, and
/// binds against its metadata. That buys a boundary: the package is compiled
/// separately, ships separately, and can be replaced without rebuilding what
/// uses it. It costs what a boundary costs, which is spelled out in the
/// metadata writer -- generics and interfaces do not cross it -- and it is the
/// only form where the ABI digest has anything to check.
/// </summary>
public enum DependencyLink
{
    Source,
    Shared,
}
