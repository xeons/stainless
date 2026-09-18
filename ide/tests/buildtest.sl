// SPDX-License-Identifier: 0BSD
//
// Reading what the compiler said.
//
//   stainless run ide/tests/buildtest.sl ide/src/Build
//
// The lines here are real ones, copied from `stainless build --diagnostics
// json` rather than invented, because the thing most likely to go wrong is a
// disagreement about a field name — and a fixture written from memory agrees
// with memory.
//
// No widget set: `Ide.Build` is a module of its own precisely so this can run
// without opening a window.
module Ide.Tests;

import Standard.Console;
import Standard.Text;
import Ide.Build;

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

    Diagnostics(harness);
    NotDiagnostics(harness);
    Describes(harness);

    Console.WriteLine(harness.Failures == 0u ? "all checks passed" : "checks FAILED");
    return harness.Failures == 0u ? 0 : 1;
}

void Diagnostics(Harness harness)
{
    Console.WriteLine("diagnostics");

    String line = "{\"severity\":\"error\",\"code\":\"SL0265\","
        + "\"message\":\"cannot convert 'String' to 'int'\","
        + "\"file\":\"C:\\\\Code\\\\src\\\\main.sl\",\"line\":5,\"column\":13,\"length\":14}";

    var message = BuildMessage.Parse(line);
    harness.Check("a diagnostic is recognised", message.IsDiagnostic);
    harness.Check("and is an error", message.IsError);
    harness.Same("with its code", "SL0265", message.Code);
    harness.Same("and its message", "cannot convert 'String' to 'int'", message.Message);
    harness.Check("and its place", message.Line == 5u && message.Column == 13u);
    harness.Check("and something to underline", message.Length == 14u);
    harness.Check("and it has a place", message.HasPlace);

    // The escaped backslashes are the half that decides whether this works on
    // Windows at all: read wrongly, every path is mangled and every
    // double-click opens nothing.
    harness.Same("with the path unescaped", "C:\\Code\\src\\main.sl", message.File);

    String warning = "{\"severity\":\"warning\",\"code\":\"SL0222\","
        + "\"message\":\"this expression has no effect\","
        + "\"file\":\"a.sl\",\"line\":2,\"column\":1,\"length\":3}";

    var second = BuildMessage.Parse(warning);
    harness.Check("a warning is not an error", second.IsDiagnostic && !second.IsError);

    // Something read back from a library's metadata has no file. It must not
    // look like a place, or a double-click goes hunting for line zero of
    // nothing.
    String placeless = "{\"severity\":\"error\",\"code\":\"SL0999\","
        + "\"message\":\"no source here\"}";

    var third = BuildMessage.Parse(placeless);
    harness.Check("one with no file is still a diagnostic", third.IsDiagnostic);
    harness.Check("and says it has no place", !third.HasPlace && third.File == "");
}

void NotDiagnostics(Harness harness)
{
    Console.WriteLine("everything else");

    // The linker's own complaints come through the same stream untouched, and
    // so does whatever a crash leaves behind. A line that is not the
    // compiler's is a line to show, not a reason to stop.
    var linker = BuildMessage.Parse("lld-link: error: could not open 'x.lib'");
    harness.Check("a linker line is not a diagnostic", !linker.IsDiagnostic);
    harness.Same("and is kept as it came",
                 "lld-link: error: could not open 'x.lib'", linker.Describe());

    var empty = BuildMessage.Parse("");
    harness.Check("an empty line is harmless", !empty.IsDiagnostic);

    // A brace that is not JSON, and JSON that is not a diagnostic. Both are
    // reachable: a program under `run` may print either.
    var broken = BuildMessage.Parse("{not json at all");
    harness.Check("a broken object is kept as text", !broken.IsDiagnostic);
    harness.Same("and not swallowed", "{not json at all", broken.Describe());

    var other = BuildMessage.Parse("{\"hello\":1}");
    harness.Check("an object that is not a diagnostic is kept as text",
                  !other.IsDiagnostic);
}

void Describes(Harness harness)
{
    Console.WriteLine("describing");

    String line = "{\"severity\":\"error\",\"code\":\"SL0265\","
        + "\"message\":\"cannot convert 'String' to 'int'\","
        + "\"file\":\"C:\\\\Code\\\\src\\\\main.sl\",\"line\":5,\"column\":13,\"length\":14}";

    // What the output pane shows. The message leads and the place trails: a
    // list of diagnostics is read for what is wrong, and a path first buries
    // every one of them behind the part they all share.
    harness.Same("a diagnostic reads as one line",
                 "error[SL0265]: cannot convert 'String' to 'int'   main.sl:5:13",
                 BuildMessage.Parse(line).Describe());

    String warning = "{\"severity\":\"warning\",\"code\":\"SL0222\","
        + "\"message\":\"no effect\",\"file\":\"/home/b/a.sl\",\"line\":2,"
        + "\"column\":1,\"length\":3}";

    harness.Same("and a warning says so, with a unix path",
                 "warning[SL0222]: no effect   a.sl:2:1",
                 BuildMessage.Parse(warning).Describe());

    String placeless = "{\"severity\":\"error\",\"code\":\"\",\"message\":\"the linker refused\"}";
    harness.Same("one with no place says only what happened",
                 "error: the linker refused",
                 BuildMessage.Parse(placeless).Describe());
}
