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

// `stainless.json`, read and written by a program written in Stainless.
//
// The compiler has read this format since it existed and the IDE never did: it
// shelled `stainless run <one file>`, which cannot build a program of two.
// This is the other reader, and its existence is the point of the format being
// JSON at all. `Driver/ProjectFile.cs` says so in as many words -- the compiler
// has a parser in the framework it is written in and the standard library has
// another, "so a program written in this language can read its own project
// file without anything new being written". Nothing new is written here.
//
// **Two readers of one format will drift**, and the way they drift is that one
// of them quietly accepts what the other refuses. So the field list below is
// the C# record's field for field, and the unknown-field rule is the same rule
// with the same courtesy: name the typo, and say what was probably meant.
//
// The two are held together by asserting the same sentence from both sides:
// `PackageTests.cs` checks that the compiler answers "did you mean 'optimize'"
// for a file that says `optimise`, and `ide/tests/projecttest.sl` checks that
// this does. Either one drifting fails its own test, which is weaker than one
// test over both readers and is what is available without a harness that can
// run a Stainless program and a C# one against the same fixture.
module Ide.Project;

import Standard.Collections;
import Standard.File;
import Standard.IO;
import Standard.Json;
import Standard.Path;
import Standard.Reflection;
import Standard.Text;

/// Where a dependency comes from, and which versions will do.
///
/// Exactly one of `Path` and `Git` is set, which the compiler checks and this
/// does not: an editor showing a project it cannot build is more useful than
/// an editor that refuses to show it. What is displayed is what the file says.
[Reflect]
public class Dependency
{
    /// What this project calls the package, which is the name on the left of
    /// the entry rather than anything inside it.
    public String Name;

    [JsonName("path")]         public String Path;
    [JsonName("git")]          public String Git;
    [JsonName("tag")]          public String Tag;
    [JsonName("branch")]       public String Branch;
    [JsonName("rev")]          public String Rev;
    [JsonName("subdirectory")] public String Subdirectory;
    [JsonName("version")]      public String Version;

    /// `"source"` or `"shared"`; empty means the default, which is source.
    [JsonName("link")] public String Link;

    public Dependency()
    {
        Name = "";
        Path = "";
        Git = "";
        Tag = "";
        Branch = "";
        Rev = "";
        Subdirectory = "";
        Version = "";
        Link = "";
    }

    public bool IsPath => Path != "";
    public bool IsGit => Git != "";

    /// How it reads in a tree: the directory, or the repository and what pins
    /// it. The same spelling `Dependency.ToString` uses on the compiler side.
    public String Describe()
    {
        if (IsPath)
            return Path;

        String pin = "";
        if (Tag != "")
            pin = "#" + Tag;
        else if (Rev != "")
            pin = "@" + Rev;
        else if (Branch != "")
            pin = ":" + Branch;

        String inside = Subdirectory == "" ? "" : "/" + Subdirectory;
        return Git + pin + inside;
    }
}

/// What one platform adds to a project.
///
/// Three lists and nothing else, which is the compiler's shape: `optimize`,
/// `abi` and `runtime` are answers about how a program is built rather than
/// about what it is made of, and a project wanting one of them per platform is
/// asking for two builds rather than one file.
[Reflect]
public class PlatformOverlay
{
    [JsonName("sources")]   public String[] Sources;
    [JsonName("libraries")] public String[] Libraries;
    [JsonName("defines")]   public String[] Defines;

    public PlatformOverlay()
    {
        Sources = [];
        Libraries = [];
        Defines = [];
    }

    public bool IsEmpty =>
        Sources.Length == 0u && Libraries.Length == 0u && Defines.Length == 0u;
}

/// A project, as the file says it is.
///
/// **`ProjectFile` rather than `Project`**, which is what it is called on the
/// compiler's side and is also the only spelling available: this module's last
/// segment is `Project`, so a class of that name could not be told from the
/// module qualifier that reaches its own functions.
///
/// **Every path is relative to the file's own directory**, never to the
/// working directory, which is what makes a build mean the same thing from
/// anywhere. `Resolve` is the only thing that should turn one into a real
/// path.
[Reflect]
public class ProjectFile
{
    [JsonName("format")]          public int Format;
    [JsonName("name")]            public String Name;
    [JsonName("version")]         public String Version;

    /// `"executable"` or `"library"`.
    [JsonName("kind")]            public String Kind;

    [JsonName("sources")]         public String[] Sources;
    [JsonName("output")]          public String Output;
    [JsonName("buildDirectory")]  public String BuildDirectory;
    [JsonName("objectDirectory")] public String ObjectDirectory;
    [JsonName("header")]          public String Header;
    [JsonName("libraries")]       public String[] Libraries;
    [JsonName("defines")]         public String[] Defines;
    [JsonName("optimize")]        public int Optimize;
    [JsonName("debug")]           public bool Debug;

    /// `"microsoft"` or `"itanium"`; empty is the host's.
    [JsonName("abi")]             public String Abi;

    /// `"shared"` or `"static"`; empty lets the build decide.
    [JsonName("runtime")]         public String Runtime;

    /// What Windows, Linux and macOS each add.
    ///
    /// **Not reflected, for the reason `Dependencies` is not**: filling one
    /// means making a `PlatformOverlay`, and there is no way to ask a `Type`
    /// for an instance. Read by hand beside the dependency map.
    ///
    /// Empty rather than null, so a caller never has to ask which -- a project
    /// naming no Windows section and one naming an empty Windows section mean
    /// the same thing, and there is nothing a reader could do with the
    /// difference.
    [JsonIgnore] public PlatformOverlay Windows;
    [JsonIgnore] public PlatformOverlay Linux;
    [JsonIgnore] public PlatformOverlay Macos;

    /// What it depends on, by name.
    ///
    /// **Not reflected, and filled by hand.** Every other field above is
    /// `Populate`'s to fill, including the arrays. This one is a map of
    /// objects, and filling it means making a `Dependency` per key -- and
    /// there is no way to ask a `Type` for an instance, so nothing here could
    /// make one. It is thirty lines of walking a `JsonObject` rather than a
    /// reason to give up on reflection for the other fourteen fields.
    [JsonIgnore] public List<Dependency> Dependencies;

    /// The directory the file was read from. Not part of the document.
    [JsonIgnore] public String Directory;

    public ProjectFile()
    {
        Format = 1;
        Name = "";
        Version = "0.1.0";
        Kind = "executable";
        Sources = ["src"];
        Output = "";
        BuildDirectory = "build";
        ObjectDirectory = "obj";
        Header = "";
        Libraries = [];
        Defines = [];
        Optimize = 2;
        Debug = false;
        Abi = "";
        Runtime = "";
        Dependencies = new List<Dependency>();
        Windows = new PlatformOverlay();
        Linux = new PlatformOverlay();
        Macos = new PlatformOverlay();
        Directory = ".";
    }

    public bool IsLibrary => Kind == "library";

    /// The file itself, for a message that can name it.
    public String FilePath => Combine(Directory, FileName);

    /// A path written in the file, against the file's own directory.
    public String Resolve(String path) => Combine(Directory, path);

    /// The overlay for a platform. `"windows"`, `"linux"` or `"macos"`;
    /// anything else answers an empty one.
    public PlatformOverlay OverlayFor(String platform)
    {
        if (platform == "windows")
            return Windows;
        if (platform == "linux")
            return Linux;
        if (platform == "macos")
            return Macos;
        return new PlatformOverlay();
    }

    /// What is compiled for a platform: the base list, then that platform's.
    ///
    /// The overlay adds and never replaces, which is what the case actually
    /// looks like -- a program is mostly the same everywhere and needs one
    /// binding directory more on each -- and it means this list can be read
    /// without checking three overlays for a removal.
    public String[] SourcesFor(String platform) => Both(Sources, OverlayFor(platform).Sources);

    public String[] LibrariesFor(String platform) => Both(Libraries, OverlayFor(platform).Libraries);

    public String[] DefinesFor(String platform) => Both(Defines, OverlayFor(platform).Defines);

    /// The platform this program was built for, which is the one whose overlay
    /// a window showing "what will be compiled" should show.
    public static String ThisPlatform
    {
        get
        {
            #if WINDOWS
            return "windows";
            #elif MACOS
            return "macos";
            #else
            return "linux";
            #endif
        }
    }

    /// Where the built binary lands.
    ///
    /// Mirrors `ProjectFile.OutputPath` in the compiler's driver. The two MUST
    /// agree: this is what the debugger launches, and a debugger launching a
    /// different file from the one just built finds stale code.
    public String OutputPath()
    {
        if (Output.ByteLength() != 0u)
            return Resolve(Output);

        String name = IsLibrary ? SharedLibraryFileName(Name)
                                : Name + ExecutableExtension;
        return Combine(Resolve(BuildDirectory), name);
    }

    #if WINDOWS
    static String ExecutableExtension => ".exe";
    static String SharedLibraryFileName(String name) => name + ".dll";
    #elif MACOS
    static String ExecutableExtension => "";
    static String SharedLibraryFileName(String name) => "lib" + name + ".dylib";
    #else
    static String ExecutableExtension => "";
    static String SharedLibraryFileName(String name) => "lib" + name + ".so";
    #endif

    String[] Both(String[] shared, String[] extra)
    {
        if (extra.Length == 0u)
            return shared;

        var answer = new String[shared.Length + extra.Length];
        for (nuint i = 0u; i < shared.Length; i++)
            answer[i] = shared[i];
        for (nuint i = 0u; i < extra.Length; i++)
            answer[shared.Length + i] = extra[i];
        return answer;
    }
}

/// What the file is called, wherever it is.
public static readonly String FileName = "stainless.json";

/// The newest format this understands. Bumped when a field changes meaning
/// rather than when one is added, which is the compiler's rule and has to be
/// the same rule or the two disagree about the same file.
public const int CurrentFormat = 1;

// --------------------------------------------------------------- finding one

/// Walks up from a directory looking for a project file, the way every tool
/// that has one does. A file three directories down still belongs to the
/// project above it.
///
/// Empty when there is none.
///
/// **`startingAt` is taken as given and is not made absolute**, because there
/// is nothing in the standard library that makes a path absolute, and
/// inventing one here would be the wrong home for it. A relative path
/// therefore stops climbing where its own spelling runs out. Everything that
/// calls this has an absolute path already -- a file chooser's answer, or a
/// command line the shell expanded -- so the limit is stated rather than
/// worked around.
public String Find(String startingAt)
{
    String directory = startingAt;

    while (directory != "")
    {
        String candidate = Combine(directory, FileName);
        if (File.Exists(candidate))
            return candidate;

        String parent = Path.DirectoryName(directory);
        if (parent == directory || parent == "")
            return "";
        directory = parent;
    }

    return "";
}

// --------------------------------------------------------------- reading one

/// Reads a project file, or says why it could not be read.
///
/// The failures are the compiler's, phrased the compiler's way, because a
/// reader seeing two different complaints about one file learns that one of
/// the two tools is wrong about it.
public Result<ProjectFile, String> Read(String path)
{
    var read = File.ReadAllText(path);
    if (!read.Ok)
        return Fail("could not read '" + path + "'");

    return Parse(read.Value, path);
}

/// The same, from text already in hand -- which is what the editor has when
/// the file is open and unsaved.
public Result<ProjectFile, String> Parse(String text, String path)
{
    var parsed = Json.Parse(text);
    if (!parsed.Ok)
        return Fail("could not read '" + path + "': " + Json.Describe(parsed.Error));

    var document = parsed.Value;
    if (!document.Object)
        return Fail("'" + path + "': a project file is an object, { ... }, and this is not one");

    var members = document.Members;

    // Before anything is read, so a file with a typo in it is refused rather
    // than half-loaded. A field that silently did nothing is the failure a
    // readable project file exists to prevent.
    var unknown = FirstUnknown(members, KnownFields(), "a project file", path);
    if (unknown != "")
        return Fail(unknown);

    var project = new ProjectFile();
    var failed = Json.PopulateFrom(project, document);
    if (failed != JsonError.None)
        return Fail("'" + path + "': " + Json.Describe(failed));

    // The three lists are read by hand, and the reason is a rule rather than an
    // omission. `Populate` fills an array *in place*: the length is the one the
    // constructor chose, and a document with more elements than that fills what
    // fits and stops. That is right for reading into an object a program made,
    // and it is wrong here, where the document *is* the data and `sources`
    // means exactly the paths it lists. The constructor has to supply defaults
    // -- a project with no `libraries` key has an empty list, not a null one --
    // so the field is never the null that would let `Populate` size it.
    var sources = ReadTextArray(members, "sources", path);
    if (!sources.Ok)
        return Fail(sources.Error);
    if (members.Has("sources"))
        project.Sources = sources.Value;

    var libraries = ReadTextArray(members, "libraries", path);
    if (!libraries.Ok)
        return Fail(libraries.Error);
    project.Libraries = libraries.Value;

    var defines = ReadTextArray(members, "defines", path);
    if (!defines.Ok)
        return Fail(defines.Error);
    project.Defines = defines.Value;

    var windows = ReadOverlay(members, "windows", path);
    if (!windows.Ok)
        return Fail(windows.Error);
    project.Windows = windows.Value;

    var linux = ReadOverlay(members, "linux", path);
    if (!linux.Ok)
        return Fail(linux.Error);
    project.Linux = linux.Value;

    var macos = ReadOverlay(members, "macos", path);
    if (!macos.Ok)
        return Fail(macos.Error);
    project.Macos = macos.Value;

    var dependencies = ReadDependencies(members, path);
    if (!dependencies.Ok)
        return Fail(dependencies.Error);
    project.Dependencies = dependencies.Value;

    project.Directory = Path.DirectoryName(path);

    if (project.Format > CurrentFormat)
    {
        return Fail("'" + path + "' is format " + Text.FromInteger((long)project.Format)
                    + ", and this reads " + Text.FromInteger((long)CurrentFormat)
                    + ". Upgrade, or lower 'format' if the file does not actually use "
                    + "anything newer");
    }

    return Ok(project);
}

/// A list of strings, or an empty one when the document does not mention it.
///
/// Refuses an element that is not a string rather than skipping it: a
/// `libraries` entry that was a number is a mistake about the file, and a
/// build missing one library it was told about is the kind of failure that
/// gets blamed on the linker.
Result<String[], String> ReadTextArray(JsonObject members, String name, String path)
{
    if (members.IndexOf(name) is Some at)
    {
        var value = members.ValueAt(at.Value);
        if (!value.Array)
            return Fail("'" + path + "': '" + name + "' is a list, [ ... ]");

        var items = value.Items;
        var answer = new String[items.Count];

        for (nuint i = 0u; i < items.Count; i++)
        {
            var item = items[i];
            if (!item.Text)
                return Fail("'" + path + "': every entry in '" + name + "' is a string");
            answer[i] = item.Value;
        }

        return Ok(answer);
    }

    return Ok([]);
}

/// One platform's section, or an empty one when the file names none.
Result<PlatformOverlay, String> ReadOverlay(JsonObject members, String platform, String path)
{
    var made = new PlatformOverlay();

    if (members.IndexOf(platform) is Some at)
    {
        var value = members.ValueAt(at.Value);
        if (!value.Object)
        {
            return Fail("'" + path + "': '" + platform + "' is an object of what that "
                        + "platform adds, as in { \"libraries\": [\"user32\"] }");
        }

        var inside = value.Members;
        var unknown = FirstUnknown(inside, KnownOverlayFields(), "a platform section", path);
        if (unknown != "")
            return Fail(unknown);

        var sources = ReadTextArray(inside, "sources", path);
        if (!sources.Ok)
            return Fail(sources.Error);
        made.Sources = sources.Value;

        var libraries = ReadTextArray(inside, "libraries", path);
        if (!libraries.Ok)
            return Fail(libraries.Error);
        made.Libraries = libraries.Value;

        var defines = ReadTextArray(inside, "defines", path);
        if (!defines.Ok)
            return Fail(defines.Error);
        made.Defines = defines.Value;
    }

    return Ok(made);
}

/// The dependency map, which reflection cannot fill.
Result<List<Dependency>, String> ReadDependencies(JsonObject members, String path)
{
    var answer = new List<Dependency>();

    if (members.IndexOf("dependencies") is Some at)
    {
        var value = members.ValueAt(at.Value);
        if (!value.Object)
        {
            return Fail("'" + path + "': 'dependencies' is an object of names, "
                        + "{ \"name\": ... }");
        }

        var listed = value.Members;
        for (nuint i = 0u; i < listed.Count; i++)
        {
            String name = listed.NameAt(i);
            var entry = listed.ValueAt(i);

            if (!entry.Object)
            {
                return Fail("'" + path + "': the dependency '" + name + "' says where it "
                            + "comes from, as in { \"path\": \"../" + name + "\" }");
            }

            var unknown = FirstUnknown(entry.Members, KnownDependencyFields(),
                                       "a dependency", path);
            if (unknown != "")
                return Fail(unknown);

            var made = new Dependency();
            Json.PopulateFrom(made, entry);
            made.Name = name;
            answer.Add(made);
        }
    }

    return Ok(answer);
}

// ------------------------------------------------------- refusing a bad field

/// The first member of `members` that `known` does not name, phrased the way
/// the compiler phrases it -- or empty when every one of them is known.
String FirstUnknown(JsonObject members, List<String> known, String kind, String path)
{
    for (nuint i = 0u; i < members.Count; i++)
    {
        String wrote = members.NameAt(i);
        if (Names(known, wrote))
            continue;

        String meant = Nearest(wrote, known);
        if (meant == "")
        {
            return "'" + path + "': '" + wrote + "' is not a field of " + kind
                   + ". The fields are: " + Join(known);
        }

        return "'" + path + "': '" + wrote + "' is not a field of " + kind
               + "; did you mean '" + meant + "'?";
    }

    return "";
}

bool Names(List<String> known, String wanted)
{
    for (nuint i = 0u; i < known.Count; i++)
    {
        if (known[i] == wanted)
            return true;
    }
    return false;
}

String Join(List<String> names)
{
    var built = new StringBuilder();
    for (nuint i = 0u; i < names.Count; i++)
    {
        if (i > 0u)
            built.Append(", ");
        built.Append(names[i]);
    }
    return built.ToText();
}

/// The closest known name, if one is close enough to be worth suggesting.
///
/// Two edits on a short name is a typo; four is a different word, and guessing
/// at that point is worse than listing what there is. The same threshold the
/// compiler uses, so the two suggest the same thing about the same mistake.
String Nearest(String wrote, List<String> known)
{
    String best = "";
    nuint closest = 0xFFFFFFFFu;
    var lowered = wrote.ToLowerAscii();

    for (nuint i = 0u; i < known.Count; i++)
    {
        nuint distance = Distance(lowered, known[i].ToLowerAscii());
        if (distance >= closest)
            continue;
        closest = distance;
        best = known[i];
    }

    nuint allowed = wrote.ByteLength() / 3u;
    if (allowed < 2u)
        allowed = 2u;

    return closest <= allowed ? best : "";
}

/// Levenshtein distance, one row at a time.
nuint Distance(String from, String to)
{
    nuint wide = to.ByteLength();
    var row = new nuint[wide + 1u];
    for (nuint j = 0u; j <= wide; j++)
        row[j] = j;

    nuint high = from.ByteLength();
    for (nuint i = 1u; i <= high; i++)
    {
        nuint diagonal = row[0u];
        row[0u] = i;

        for (nuint j = 1u; j <= wide; j++)
        {
            nuint above = row[j];
            nuint insert = row[j] + 1u;
            nuint remove = row[j - 1u] + 1u;
            nuint replace = diagonal + (from.ByteAt(i - 1u) == to.ByteAt(j - 1u) ? 0u : 1u);

            nuint least = insert < remove ? insert : remove;
            row[j] = least < replace ? least : replace;
            diagonal = above;
        }
    }

    return row[wide];
}

/// The field names as the file spells them, read off the type rather than
/// written out again -- so a field added above is refused-or-accepted without
/// this list being the thing that was forgotten.
List<String> KnownFields()
{
    var type = typeof(ProjectFile);
    var names = new List<String>();

    for (nuint i = 0u; i < type.FieldCount; i++)
    {
        var field = type.FieldAt(i);
        if (field.Has("JsonIgnore"))
            continue;
        names.Add(field.Has("JsonName") ? field.Get("JsonName").AsText(0u) : field.Name);
    }

    // The four the type does not carry, because reflection cannot fill any of
    // them: each is an object, and making one takes a constructor no `Type`
    // can be asked for.
    names.Add("dependencies");
    names.Add("windows");
    names.Add("linux");
    names.Add("macos");
    return names;
}

List<String> KnownOverlayFields()
{
    var names = new List<String>();
    names.Add("sources");
    names.Add("libraries");
    names.Add("defines");
    return names;
}

List<String> KnownDependencyFields()
{
    var type = typeof(Dependency);
    var names = new List<String>();

    for (nuint i = 0u; i < type.FieldCount; i++)
    {
        var field = type.FieldAt(i);
        if (field.Has("JsonIgnore") || field.Name == "Name")
            continue;
        names.Add(field.Has("JsonName") ? field.Get("JsonName").AsText(0u) : field.Name);
    }

    return names;
}

// --------------------------------------------------------------- writing one

/// The project as a document, carrying **only what differs from a default**.
///
/// `ProjectFile.WriteStarter` makes the argument and it holds for a rewrite as
/// much as for a new file: a generated file full of defaults reads as though
/// all of it matters, and the first edit is somebody deleting lines to find out
/// which. What a project cannot do without is what it is called, what it is,
/// and where its source is.
public String ToJson(ProjectFile project)
{
    // The object is built and then wrapped, rather than made and reached
    // into: a variant's payload is not readable until something has
    // established which case it is (SL0286), and `NewObject` answers a
    // `JsonValue` that this would have to narrow first. Building the
    // `JsonObject` itself skips the question.
    var members = new JsonObject();
    var fresh = new ProjectFile();

    if (project.Format != fresh.Format)
        members.Add("format", Json.NumberOf((long)project.Format));

    members.Add("name", JsonValue.Text(project.Name));
    members.Add("version", JsonValue.Text(project.Version));
    members.Add("kind", JsonValue.Text(project.Kind));
    members.Add("sources", TextArray(project.Sources));

    AddText(members, "output", project.Output, fresh.Output);
    AddText(members, "buildDirectory", project.BuildDirectory, fresh.BuildDirectory);
    AddText(members, "objectDirectory", project.ObjectDirectory, fresh.ObjectDirectory);
    AddText(members, "header", project.Header, fresh.Header);

    if (project.Dependencies.Count > 0u)
        members.Add("dependencies", DependencyObject(project.Dependencies));

    AddOverlay(members, "windows", project.Windows);
    AddOverlay(members, "linux", project.Linux);
    AddOverlay(members, "macos", project.Macos);

    if (project.Libraries.Length > 0u)
        members.Add("libraries", TextArray(project.Libraries));
    if (project.Defines.Length > 0u)
        members.Add("defines", TextArray(project.Defines));

    if (project.Optimize != fresh.Optimize)
        members.Add("optimize", Json.NumberOf((long)project.Optimize));
    if (project.Debug != fresh.Debug)
        members.Add("debug", JsonValue.Bool(project.Debug));

    AddText(members, "abi", project.Abi, fresh.Abi);
    AddText(members, "runtime", project.Runtime, fresh.Runtime);

    return Json.WriteIndented(JsonValue.Object(members));
}

/// Writes the project back where it came from.
public Result<bool, String> Write(ProjectFile project, String path)
{
    var failed = File.WriteAllText(path, ToJson(project) + "\n");
    if (failed != IOError.None)
        return Fail("could not write '" + path + "'");
    return Ok(true);
}

void AddText(JsonObject members, String name, String value, String fallback)
{
    if (value == fallback || value == "")
        return;
    members.Add(name, JsonValue.Text(value));
}

void AddOverlay(JsonObject members, String name, PlatformOverlay overlay)
{
    if (overlay.IsEmpty)
        return;

    var inside = new JsonObject();
    if (overlay.Sources.Length > 0u)
        inside.Add("sources", TextArray(overlay.Sources));
    if (overlay.Libraries.Length > 0u)
        inside.Add("libraries", TextArray(overlay.Libraries));
    if (overlay.Defines.Length > 0u)
        inside.Add("defines", TextArray(overlay.Defines));

    members.Add(name, JsonValue.Object(inside));
}

JsonValue TextArray(String[] values)
{
    var items = new List<JsonValue>();
    for (nuint i = 0u; i < values.Length; i++)
        items.Add(JsonValue.Text(values[i]));
    return JsonValue.Array(items);
}

JsonValue DependencyObject(List<Dependency> dependencies)
{
    var members = new JsonObject();

    for (nuint i = 0u; i < dependencies.Count; i++)
    {
        var dependency = dependencies[i];
        var inside = new JsonObject();

        AddText(inside, "path", dependency.Path, "");
        AddText(inside, "git", dependency.Git, "");
        AddText(inside, "tag", dependency.Tag, "");
        AddText(inside, "branch", dependency.Branch, "");
        AddText(inside, "rev", dependency.Rev, "");
        AddText(inside, "subdirectory", dependency.Subdirectory, "");
        AddText(inside, "version", dependency.Version, "");
        AddText(inside, "link", dependency.Link, "");

        members.Add(dependency.Name, JsonValue.Object(inside));
    }

    return JsonValue.Object(members);
}

// ------------------------------------------------------------------- paths

/// Joins two path pieces with the platform's separator, without pulling in a
/// dependency on how `Standard.Path` spells a combine that does not exist.
String Combine(String directory, String name)
{
    if (directory == "" || directory == ".")
        return name;
    return Path.Join(directory, name);
}
