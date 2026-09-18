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

    var read = Project.Parse(whole, "whole.json");
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
        var shapes = project.Dependencies.At(0u);
        harness.Same("a dependency keeps its name", "shapes", shapes.Name);
        harness.Check("and knows it is a path", shapes.IsPath && !shapes.IsGit);
        harness.Same("and reads as its directory", "../shapes", shapes.Describe());
        harness.Same("with a version", "^1.0", shapes.Version);

        var json = project.Dependencies.At(1u);
        harness.Check("a git dependency knows it", json.IsGit && !json.IsPath);
        harness.Same("and reads as its repository and tag",
                     "https://example/json.git#v2.1.0", json.Describe());
    }

    // What a starter file actually looks like: four fields, everything else
    // defaulted. `stainless init` writes exactly this.
    var starter = Project.Parse(
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
    var typo = Project.Parse("{\"name\":\"a\",\"optimise\":2}", "p.json");
    harness.Check("a near miss is refused", typo.Fail);
    if (typo.Fail)
    {
        harness.Check("and names what was probably meant",
                      typo.Error.Contains("did you mean 'optimize'"));
    }

    var stranger = Project.Parse("{\"name\":\"a\",\"wibble\":2}", "p.json");
    harness.Check("a name near nothing is refused", stranger.Fail);
    if (stranger.Fail)
    {
        harness.Check("and lists the fields instead of guessing",
                      stranger.Error.Contains("The fields are:")
                      && stranger.Error.Contains("dependencies"));
    }

    var inside = Project.Parse(
        "{\"name\":\"a\",\"dependencies\":{\"x\":{\"pat\":\"../x\"}}}", "p.json");
    harness.Check("an unknown field inside a dependency is refused too", inside.Fail);
    if (inside.Fail)
        harness.Check("and says it is a dependency", inside.Error.Contains("a dependency"));

    var notObject = Project.Parse("[1, 2]", "p.json");
    harness.Check("a document that is not an object is refused", notObject.Fail);

    var broken = Project.Parse("{", "p.json");
    harness.Check("text that is not JSON is refused", broken.Fail);

    var future = Project.Parse("{\"name\":\"a\",\"format\":99}", "p.json");
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
    String written = Project.ToJson(fresh);

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

    var back = Project.Parse(Project.ToJson(changed), "round.json");
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
                      && again.Dependencies.At(0u).Name == "shapes"
                      && again.Dependencies.At(0u).Path == "../shapes");
    }
}
