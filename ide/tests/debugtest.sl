// SPDX-License-Identifier: 0BSD
//
// The breakpoint model, without a window and without a process.
//
//   stainless run ide/tests/debugtest.sl ide/src/Debug/Breakpoints.sl debug/src
//
// What this can answer is where a breakpoint is, which file it belongs to, and
// where it goes when the text around it moves. What it cannot answer is
// whether anything was drawn, or whether the program stopped: the first wants
// a screenshot and the second wants `sldb`, which has both.
//
// The path comparison is the half worth testing hardest. A compiler joining a
// directory to a file name writes one separator from each half, so the editor
// and the debug information spell the same file differently -- and a
// breakpoint compared with `==` silently never fires.
module Ide.Tests;

import Standard.Console;
import Standard.Text;
import Ide.Debugging;

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

    public void SameNumber(String what, long expected, long actual)
    {
        bool passed = expected == actual;
        Console.WriteLine((passed ? "  ok   " : "  FAIL ") + what);
        if (!passed)
        {
            Console.WriteLine("         expected: "
                              + Standard.Text.FromInteger(expected));
            Console.WriteLine("         actual:   "
                              + Standard.Text.FromInteger(actual));
            Failures++;
        }
    }
}

int Main()
{
    var harness = new Harness();

    Toggling(harness);
    Matching(harness);
    Binding(harness);
    Shifting(harness);

    Console.WriteLine("");
    if (harness.Failures == 0u)
    {
        Console.WriteLine("all checks passed");
        return 0;
    }
    Console.WriteLine(Standard.Text.FromInteger((long)harness.Failures)
                      + " check(s) failed");
    return 1;
}

void Toggling(Harness harness)
{
    Console.WriteLine("toggling");
    var store = new BreakpointStore();

    harness.Check("a new store is empty", store.IsEmpty);

    var made = store.Toggle("src/Main.sl", 12u);
    harness.Check("toggling once adds one", made != null && store.Count == 1u);
    harness.Check("and it is found where it was put",
                  store.At("src/Main.sl", 12u) != null);
    harness.Check("and not on the line below",
                  store.At("src/Main.sl", 13u) == null);

    var gone = store.Toggle("src/Main.sl", 12u);
    harness.Check("toggling again removes it", gone == null && store.IsEmpty);

    store.Toggle("src/Main.sl", 3u);
    store.Toggle("src/Other.sl", 3u);
    harness.SameNumber("one line of two files is two breakpoints",
                       2, (long)store.Count);
    harness.Check("a file with one is touched", store.Touches("src/Main.sl"));
    harness.Check("a file with none is not", !store.Touches("src/Third.sl"));

    store.Clear();
    harness.Check("clearing empties it", store.IsEmpty);
}

void Matching(Harness harness)
{
    Console.WriteLine("paths, on either system");
    var store = new BreakpointStore();
    store.Toggle("/home/p/src/Main.sl", 5u);

    // The build ran in the project's directory, so the compiler recorded a
    // relative path where the editor holds an absolute one.
    harness.Check("a relative tail matches an absolute path",
                  store.At("src/Main.sl", 5u) != null);

    // A tail that does not begin at a separator is a different file.
    harness.Check("a partial name is not a match",
                  store.At("ain.sl", 5u) == null);
    harness.Check("and neither is the same name elsewhere",
                  store.At("tests/Main.sl", 5u) == null);

    Separators(harness);
}

#if WINDOWS

/// Windows accepts both separators and ignores case, so one file has many
/// spellings -- and the compiler's own debug information mixes them, writing
/// one separator from the directory and one from the join.
void Separators(Harness harness)
{
    Console.WriteLine("paths, as Windows spells them");
    var store = new BreakpointStore();
    store.Toggle("C:\\p\\src\\Main.sl", 5u);

    harness.Check("mixed separators are the same file",
                  store.At("C:\\p\\src/Main.sl", 5u) != null);
    harness.Check("case is ignored",
                  store.At("c:\\P\\SRC\\main.SL", 5u) != null);
    harness.Check("a relative tail matches whichever way it is spelled",
                  store.At("src/Main.sl", 5u) != null
                  && store.At("src\\Main.sl", 5u) != null);
}

#else

/// On Linux a backslash is an ordinary character in a filename and case
/// matters, so none of the Windows spellings names the same file. Asserted
/// rather than skipped: getting this wrong would silently merge two files.
void Separators(Harness harness)
{
    Console.WriteLine("paths, as Linux spells them");
    var store = new BreakpointStore();
    store.Toggle("/home/p/src/Main.sl", 5u);

    harness.Check("a backslash is not a separator",
                  store.At("/home/p/src\\Main.sl", 5u) == null);
    harness.Check("case matters",
                  store.At("/home/p/src/main.sl", 5u) == null);
    harness.Check("and a relative tail still matches",
                  store.At("src/Main.sl", 5u) != null);
}

#endif

void Binding(Harness harness)
{
    Console.WriteLine("binding");
    var store = new BreakpointStore();
    store.Toggle("src/Main.sl", 10u);

    var found = store.At("src/Main.sl", 10u);
    harness.Check("it starts unbound",
                  found != null && !((SourceBreakpoint)found).Bound);
    harness.SameNumber("and is shown on the line asked for",
                       10, (long)((SourceBreakpoint)found).ShownLine);

    // A blank line resolves to the first statement after it.
    store.Bind("src/Main.sl", 10u, 14u);
    harness.SameNumber("binding moves where it is shown",
                       14, (long)((SourceBreakpoint)found).ShownLine);
    harness.Check("the glyph is found on the bound line",
                  store.ShownAt("src/Main.sl", 14u) != null);
    harness.Check("and toggling still answers the line asked for",
                  store.At("src/Main.sl", 10u) != null
                  && store.At("src/Main.sl", 14u) == null);
    harness.Check("the description says where it was asked for",
                  ((SourceBreakpoint)found).Describe().Contains("asked for 10"));

    // Zero means no code was found.
    store.Bind("src/Main.sl", 10u, 0u);
    harness.Check("binding to nothing leaves it unbound",
                  !((SourceBreakpoint)found).Bound);
    harness.SameNumber("and back on the line asked for",
                       10, (long)((SourceBreakpoint)found).ShownLine);

    store.Bind("src/Main.sl", 10u, 14u);
    store.Unbind();
    harness.Check("a session ending unbinds everything",
                  !((SourceBreakpoint)found).Bound);
}

void Shifting(Harness harness)
{
    Console.WriteLine("editing around one");
    var store = new BreakpointStore();
    store.Toggle("src/Main.sl", 20u);
    store.Bind("src/Main.sl", 20u, 20u);

    store.Shift("src/Main.sl", 5u, 2);
    var moved = store.At("src/Main.sl", 22u);
    harness.Check("typing two lines above it pushes it down", moved != null);
    harness.Check("and unbinds it, because the text has changed",
                  moved != null && !((SourceBreakpoint)moved).Bound);

    store.Shift("src/Main.sl", 30u, 5);
    harness.Check("an edit below it leaves it alone",
                  store.At("src/Main.sl", 22u) != null);

    store.Shift("src/Other.sl", 1u, 9);
    harness.Check("an edit in another file leaves it alone",
                  store.At("src/Main.sl", 22u) != null);

    store.Shift("src/Main.sl", 10u, -3);
    harness.Check("deleting above it pulls it up",
                  store.At("src/Main.sl", 19u) != null);

    // Deleting from line 15 down past it: line 14 is what the removed text
    // was joined onto, and the only line still there.
    store.Shift("src/Main.sl", 15u, -40);
    harness.Check("deleting across it leaves it on the line above the cut",
                  store.At("src/Main.sl", 14u) != null);
    harness.SameNumber("and there is still exactly one", 1, (long)store.Count);

    // The same at the top of a file, where there is no line above.
    var top = new BreakpointStore();
    top.Toggle("src/Main.sl", 3u);
    top.Shift("src/Main.sl", 1u, -9);
    harness.Check("a deletion from line 1 leaves it on line 1",
                  top.At("src/Main.sl", 1u) != null);
}
