// SPDX-License-Identifier: 0BSD
//
// The project reader, on files that are awkward on purpose.
//
//   stainless run ide/tests/projecttest.sl ide/src/Project
//
// This is the second reader of `stainless.json`, and the risk a second reader
// carries is that it quietly accepts what the first one refuses. So most of
// what is checked here is the refusing: a field that is not a field, a typo
// near one, a value of the wrong shape, a format from the future. The reading
// is the easy half and the suite the compiler already has covers the writing
// side of the same format.
module Ide.Tests;

import Standard.Console;
import Standard.Text;
import Ide.Project;

class Harness
{
    public nuint Failures;

    public Harness() => Failures = 0u;

    public void Check(String what, bool passed)
    {
        Console.WriteLine((passed ? "  ok   " : "  FAIL ") + what);
        if (!passed)
            Failures++;
    }

    /// A check that shows what it got when it fails, which is most of what
    /// makes a failing string comparison worth reading.
    public void Same(String what, String expected, String actual)
    {
        bool passed = expected == actual;
        Console.WriteLine((passed ? "  ok   " : "  FAIL ") + what);
        if (!passed)
        {
            Console.WriteLine("         expected: " + expected);
            Console.WriteLine("         actual:   " + actual);
            Failures++;
        }
    }
}

int Main()
{
    var harness = new Harness();

    Reads(harness);
    Refuses(harness);
    Writes(harness);
    Finds(harness);
    Platforms(harness);

    Console.WriteLine(harness.Failures == 0u
                      ? "all checks passed"
                      : "checks FAILED");
    return harness.Failures == 0u ? 0 : 1;
}

void Reads(Harness harness)
{
    Console.WriteLine("reading");

    // Every field, so that one the reader forgot shows up as a default rather
    // than as nothing at all.
    String whole = "{"
        + "\"name\": \"app\","
        + "\"version\": \"1.2.3\","
        + "\"kind\": \"library\","
        + "\"sources\": [\"src\", \"extra\"],"
        + "\"output\": \"build/app.dll\","
        + "\"buildDirectory\": \"out\","
        + "\"objectDirectory\": \"tmp\","
        + "\"header\": \"build/app.h\","
        + "\"libraries\": [\"user32\", \"gdi32\"],"
        + "\"defines\": [\"FANCY\"],"
        + "\"optimize\": 0,"
        + "\"debug\": true,"
        + "\"abi\": \"itanium\","
        + "\"runtime\": \"shared\","
        + "\"dependencies\": {"
        + "  \"shapes\": { \"path\": \"../shapes\", \"version\": \"^1.0\" },"
        + "  \"json\": { \"git\": \"https://example/json.git\", \"tag\": \"v2.1.0\" }"
        + "}}";

    var read = Project.ParseProjectFile(whole, "whole.json");
    harness.Check("a whole project reads", read.Ok);
    if (!read.Ok)
    {
        Console.WriteLine("         " + read.Error);
        return;
    }

    var project = read.Value;
    harness.Same("name", "app", project.Name);
    harness.Same("version", "1.2.3", project.Version);
    harness.Same("kind", "library", project.Kind);
    harness.Check("it knows it is a library", project.IsLibrary);

    harness.Check("sources", project.Sources.Length == 2u
                             && project.Sources[0u] == "src"
                             && project.Sources[1u] == "extra");
    harness.Same("output", "build/app.dll", project.Output);
    harness.Same("buildDirectory", "out", project.BuildDirectory);
    harness.Same("objectDirectory", "tmp", project.ObjectDirectory);
    harness.Same("header", "build/app.h", project.Header);

    harness.Check("libraries", project.Libraries.Length == 2u
                               && project.Libraries[1u] == "gdi32");
    harness.Check("defines", project.Defines.Length == 1u
                             && project.Defines[0u] == "FANCY");

    harness.Check("optimize", project.Optimize == 0);
    harness.Check("debug", project.Debug);
    harness.Same("abi", "itanium", project.Abi);
    harness.Same("runtime", "shared", project.Runtime);

    // The arrays are the half that reflection could not fill until the runtime
    // learned to make one, so they are worth their own line: a reader that
    // silently left `sources` at its default would look exactly like a reader
    // that worked.
    harness.Check("two dependencies", project.Dependencies.Count == 2u);
    if (project.Dependencies.Count == 2u)
    {
        var shapes = project.Dependencies[0u];
        harness.Same("a dependency keeps its name", "shapes", shapes.Name);
        harness.Check("and knows it is a path", shapes.IsPath && !shapes.IsGit);
        harness.Same("and reads as its directory", "../shapes", shapes.ToDisplayText());
        harness.Same("with a version", "^1.0", shapes.Version);

        var json = project.Dependencies[1u];
        harness.Check("a git dependency knows it", json.IsGit && !json.IsPath);
        harness.Same("and reads as its repository and tag",
                     "https://example/json.git#v2.1.0", json.ToDisplayText());
    }

    // What a starter file actually looks like: four fields, everything else
    // defaulted. `stainless init` writes exactly this.
    var starter = Project.ParseProjectFile(
        "{\"name\":\"hello\",\"version\":\"0.1.0\",\"kind\":\"executable\","
        + "\"sources\":[\"src\"]}", "starter.json");
    harness.Check("a starter file reads", starter.Ok);
    if (starter.Ok)
    {
        var made = starter.Value;
        harness.Check("and takes the defaults for the rest",
                      made.BuildDirectory == "build" && made.ObjectDirectory == "obj"
                      && made.Optimize == 2 && !made.Debug
                      && made.Dependencies.Count == 0u);
    }
}

void Refuses(Harness harness)
{
    Console.WriteLine("refusing");

    // The whole reason the format refuses an unknown field rather than
    // ignoring it: a typo that silently does nothing is the failure a readable
    // project file exists to prevent.
    var typo = Project.ParseProjectFile("{\"name\":\"a\",\"optimise\":2}", "p.json");
    harness.Check("a near miss is refused", typo.Fail);
    if (typo.Fail)
    {
        harness.Check("and names what was probably meant",
                      typo.Error.Contains("did you mean 'optimize'"));
    }

    var stranger = Project.ParseProjectFile("{\"name\":\"a\",\"wibble\":2}", "p.json");
    harness.Check("a name near nothing is refused", stranger.Fail);
    if (stranger.Fail)
    {
        harness.Check("and lists the fields instead of guessing",
                      stranger.Error.Contains("The fields are:")
                      && stranger.Error.Contains("dependencies"));
    }

    var inside = Project.ParseProjectFile(
        "{\"name\":\"a\",\"dependencies\":{\"x\":{\"pat\":\"../x\"}}}", "p.json");
    harness.Check("an unknown field inside a dependency is refused too", inside.Fail);
    if (inside.Fail)
        harness.Check("and says it is a dependency", inside.Error.Contains("a dependency"));

    var notObject = Project.ParseProjectFile("[1, 2]", "p.json");
    harness.Check("a document that is not an object is refused", notObject.Fail);

    var broken = Project.ParseProjectFile("{", "p.json");
    harness.Check("text that is not JSON is refused", broken.Fail);

    var future = Project.ParseProjectFile("{\"name\":\"a\",\"format\":99}", "p.json");
    harness.Check("a format from the future is refused", future.Fail);
    if (future.Fail)
        harness.Check("and says which", future.Error.Contains("format 99"));
}

void Writes(Harness harness)
{
    Console.WriteLine("writing");

    // A file full of defaults reads as though all of it matters, and the first
    // edit is somebody deleting lines to find out which -- so a written file
    // carries what a project cannot do without and what differs, and nothing
    // else. This is the compiler's `WriteStarter` argument applied to a
    // rewrite.
    var fresh = new ProjectFile();
    fresh.Name = "hello";
    String written = Project.SerializeProjectFile(fresh);

    harness.Check("a default project writes its four fields",
                  written.Contains("\"name\": \"hello\"")
                  && written.Contains("\"version\"")
                  && written.Contains("\"kind\"")
                  && written.Contains("\"sources\""));
    harness.Check("and none of the defaults",
                  !written.Contains("buildDirectory")
                  && !written.Contains("objectDirectory")
                  && !written.Contains("optimize")
                  && !written.Contains("debug")
                  && !written.Contains("dependencies"));

    // What is written must read back as what was written, which is the only
    // check that catches a writer and a reader disagreeing about a name.
    var changed = new ProjectFile();
    changed.Name = "app";
    changed.Version = "2.0.0";
    changed.Kind = "library";
    changed.Sources = ["lib", "shared"];
    changed.Optimize = 0;
    changed.Debug = true;
    changed.Libraries = ["m"];
    changed.Defines = ["UNIX"];
    changed.Header = "build/app.h";

    var dependency = new Dependency();
    dependency.Name = "shapes";
    dependency.Path = "../shapes";
    changed.Dependencies.Add(dependency);

    var back = Project.ParseProjectFile(Project.SerializeProjectFile(changed), "round.json");
    harness.Check("a written project reads back", back.Ok);
    if (back.Ok)
    {
        var again = back.Value;
        harness.Same("round-tripped name", "app", again.Name);
        harness.Same("round-tripped kind", "library", again.Kind);
        harness.Check("round-tripped sources",
                      again.Sources.Length == 2u && again.Sources[1u] == "shared");
        harness.Check("round-tripped build settings",
                      again.Optimize == 0 && again.Debug
                      && again.Libraries.Length == 1u && again.Defines.Length == 1u);
        harness.Same("round-tripped header", "build/app.h", again.Header);
        harness.Check("round-tripped dependency",
                      again.Dependencies.Count == 1u
                      && again.Dependencies[0u].Name == "shapes"
                      && again.Dependencies[0u].Path == "../shapes");
    }
}

void Finds(Harness harness)
{
    Console.WriteLine("finding");

    // Everything above parses text. This is the only part that touches a real
    // file, and it is the part the window actually calls: a file is opened,
    // and the project it belongs to is found by walking up from it.
    //
    // The path is relative to the repository root, which is where the test is
    // run from -- and `FindProjectFile` does not make a path absolute, so this
    // also shows what that limit does and does not stop.
    String found = Project.FindProjectFile("ide/tests/fixture/src");
    harness.Check("a project is found from a file beside it", found != "");

    if (found == "")
        return;

    var read = Project.ReadProjectFile(found);
    harness.Check("and reads", read.Ok);
    if (!read.Ok)
    {
        Console.WriteLine("         " + read.Error);
        return;
    }

    var project = read.Value;
    harness.Same("with the name the file gives", "fixture", project.Name);
    harness.Check("and one source root",
                  project.Sources.Length == 1u && project.Sources[0u] == "src");

    // The directory is what every relative path in the file is measured
    // against, so a project read from a path is useless without it.
    harness.Check("and knows where it was read from", project.Directory != ".");
    harness.Check("so a source root resolves under it",
                  project.ResolvePath("src").Contains("fixture"));

    harness.Check("and a directory with no project above it finds none",
                  Project.FindProjectFile("stainless-nowhere-at-all") == "");
}

void Platforms(Harness harness)
{
    Console.WriteLine("platforms");

    // The case a flat `sources` cannot state, and the reason every Forms
    // program in this tree was built by a shell script instead of by its own
    // project file.
    String text = "{"
        + "\"name\": \"app\", \"version\": \"1.0.0\","
        + "\"sources\": [\"src\"], \"libraries\": [\"m\"], \"defines\": [\"SHARED\"],"
        + "\"windows\": { \"sources\": [\"bindings/win32\"],"
        + "              \"libraries\": [\"user32\"], \"defines\": [\"WIN\"] },"
        + "\"linux\":   { \"sources\": [\"bindings/gtk\"],"
        + "              \"libraries\": [\":libgtk-3.so.0\"] }"
        + "}";

    var read = Project.ParseProjectFile(text, "p.json");
    harness.Check("a project with platform sections reads", read.Ok);
    if (!read.Ok)
    {
        Console.WriteLine("         " + read.Error);
        return;
    }

    var project = read.Value;

    var windows = project.GetSourcesFor("windows");
    harness.Check("windows adds to the sources",
                  windows.Length == 2u && windows[0u] == "src"
                  && windows[1u] == "bindings/win32");

    var linux = project.GetSourcesFor("linux");
    harness.Check("and linux adds its own",
                  linux.Length == 2u && linux[1u] == "bindings/gtk");

    harness.Check("libraries the same way",
                  project.GetLibrariesFor("windows").Length == 2u
                  && project.GetLibrariesFor("linux")[1u] == ":libgtk-3.so.0");

    // Adding and not replacing is the whole rule: a platform naming no defines
    // keeps the base one rather than clearing it.
    harness.Check("an overlay adds rather than replaces",
                  project.GetDefinesFor("windows").Length == 2u
                  && project.GetDefinesFor("linux").Length == 1u
                  && project.GetDefinesFor("linux")[0u] == "SHARED");

    harness.Check("a platform named by nothing adds nothing",
                  project.GetSourcesFor("macos").Length == 1u);

    // A typo inside a section is refused like one anywhere else. This is the
    // half a second reader is most likely to quietly accept.
    var typo = Project.ParseProjectFile(
        "{\"name\":\"a\",\"windows\":{\"libaries\":[\"user32\"]}}", "p.json");
    harness.Check("a typo inside a section is refused", typo.Fail);
    if (typo.Fail)
    {
        harness.Check("and named as a platform section",
                      typo.Error.Contains("a platform section")
                      && typo.Error.Contains("did you mean 'libraries'"));
    }

    var wrong = Project.ParseProjectFile("{\"name\":\"a\",\"windows\":[1]}", "p.json");
    harness.Check("a section that is not an object is refused", wrong.Fail);

    // Round-tripping, so the writer and the reader cannot disagree about a name.
    var back = Project.ParseProjectFile(Project.SerializeProjectFile(project), "round.json");
    harness.Check("platform sections round-trip", back.Ok);
    if (back.Ok)
    {
        harness.Check("with what they added still there",
                      back.Value.GetSourcesFor("windows").Length == 2u
                      && back.Value.GetLibrariesFor("linux").Length == 2u
                      && back.Value.GetDefinesFor("windows").Length == 2u);
    }

    // And the real file this whole feature exists for.
    var mine = Project.ReadProjectFile("ide/stainless.json");
    harness.Check("the IDE's own project reads", mine.Ok);
    if (mine.Ok)
    {
        // **By what is in them rather than by how many there are.** This
        // counted four sources per platform and broke the day the IDE gained
        // a resource script of its own, which is the test being about the
        // wrong thing rather than the change being wrong: what the overlay
        // exists to do is add the right binding directory, and a count says
        // nothing about which one arrived.
        harness.Check("and names the Windows bindings",
                      Names(mine.Value.GetSourcesFor("windows"), "../bindings/win32"));
        harness.Check("and the GTK ones on Linux",
                      Names(mine.Value.GetSourcesFor("linux"), "../bindings/gtk"));

        // Neither platform's list may carry the other's, which is the half a
        // merge can get wrong without anything else noticing.
        harness.Check("and neither carries the other's",
                      !Names(mine.Value.GetSourcesFor("windows"), "../bindings/gtk")
                      && !Names(mine.Value.GetSourcesFor("linux"), "../bindings/win32"));
    }
}

/// Whether a list holds exactly this entry.
bool Names(String[] all, String wanted)
{
    foreach (var one in all)
    {
        if (one == wanted)
            return true;
    }
    return false;
}
