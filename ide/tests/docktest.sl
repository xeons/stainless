// SPDX-License-Identifier: 0BSD
//
// The docking layout, without a window.
//
//   stainless run ide/tests/docktest.sl ide/src/Shell/Layout.sl
//
// What this can and cannot answer is the whole reason the file it tests exists
// separately. It cannot say a splitter drags or a pane appears -- only a
// screenshot says that. It can say that a layout survives being written and
// read back, that a file from a build that called the panes something else does
// not take the window down, and that a width of 9000 does not arrive at the
// window. Those are the three ways a layout file actually goes wrong.
module Ide.Tests;

import Standard.Console;
import Standard.Text;
import Ide.Shell;

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

    public void CheckSame(String what, String expected, String actual)
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

    public void CheckSameNumber(String what, long expected, long actual)
    {
        CheckSame(what, Standard.Text.FromInteger(expected), Standard.Text.FromInteger(actual));
    }
}

int Main()
{
    var harness = new Harness();

    TestDefaults(harness);
    TestPlacing(harness);
    TestOrdering(harness);
    TestRoundTrip(harness);
    TestRefusing(harness);
    TestSurviving(harness);

    Console.WriteLine(harness.Failures == 0u ? "all checks passed" : "checks FAILED");
    return harness.Failures == 0u ? 0 : 1;
}

void TestDefaults(Harness harness)
{
    Console.WriteLine("the arrangement a first run gets");

    var layout = DockLayout.CreateDefault();
    harness.CheckSameNumber("three panes are placed", 3, (long)layout.Places.Count);
    harness.CheckSameNumber("one on the left", 1, (long)layout.Count(DockEdge.Left));
    harness.CheckSameNumber("two at the bottom", 2, (long)layout.Count(DockEdge.Bottom));

    // The default names only panes the window actually builds. Properties has
    // a constant but no place, so nobody's settings file carries a line for a
    // pane they cannot see.
    harness.Check("and a pane that does not exist yet is not placed",
                  layout.Find(Panes.Properties) == null);
    harness.CheckSameNumber("so the right well is empty", 0,
                            (long)layout.Count(DockEdge.Right));

    var solution = layout.Find(Panes.Solution);
    harness.Check("the tree is on the left", solution != null
                  && ((DockPlacement)solution).Edge == DockEdge.Left);
    harness.Check("and pinned open", solution != null && ((DockPlacement)solution).IsPinned);

    // A name no build uses. The answer must be null rather than a placement,
    // or a pane added later cannot tell "the file predates me" from "the file
    // put me in the document well".
    harness.Check("a pane nobody placed is not found", layout.Find("toolbox") == null);
}

void TestPlacing(Harness harness)
{
    Console.WriteLine("moving a pane");

    var layout = DockLayout.CreateDefault();
    layout.PlacePane(Panes.Solution, DockEdge.Bottom, false);

    harness.CheckSameNumber("still three panes", 3, (long)layout.Places.Count);
    harness.CheckSameNumber("the left well is empty", 0, (long)layout.Count(DockEdge.Left));
    harness.CheckSameNumber("and the bottom has three", 3, (long)layout.Count(DockEdge.Bottom));

    var moved = layout.Find(Panes.Solution);
    harness.Check("unpinned where it was put", moved != null && !((DockPlacement)moved).IsPinned);
}

void TestOrdering(Harness harness)
{
    Console.WriteLine("the order within a well");

    var layout = new DockLayout();
    var first = layout.PlacePane("a", DockEdge.Bottom, true);
    var second = layout.PlacePane("b", DockEdge.Bottom, true);
    var third = layout.PlacePane("c", DockEdge.Bottom, true);

    // Deliberately reversed, and `b` left where it is: that makes two entries
    // share an order, which is the case a sort that is not stable gets wrong
    // and gets wrong only sometimes.
    first.Order = 2u;
    third.Order = 0u;
    second.Order = 0u;

    var ordered = layout.GetPlacementsOn(DockEdge.Bottom);
    harness.CheckSameNumber("three on the edge", 3, (long)ordered.Count);
    harness.CheckSame("the low order leads", "b", ordered[0u].Name);
    harness.CheckSame("the tie keeps the order it was read in", "c", ordered[1u].Name);
    harness.CheckSame("and the high order trails", "a", ordered[2u].Name);
}

void TestRoundTrip(Harness harness)
{
    Console.WriteLine("written and read back");

    var layout = DockLayout.CreateDefault();
    layout.LeftWidth = 300;
    layout.RightWidth = 200;
    layout.BottomHeight = 120;
    layout.PlacePane(Panes.Properties, DockEdge.Left, false);

    var again = ParseLayout(SerializeLayout(layout));

    harness.CheckSameNumber("the left width came back", 300, (long)again.LeftWidth);
    harness.CheckSameNumber("the right width came back", 200, (long)again.RightWidth);
    harness.CheckSameNumber("the bottom height came back", 120, (long)again.BottomHeight);
    harness.CheckSameNumber("every pane came back", 4, (long)again.Places.Count);

    var moved = again.Find(Panes.Properties);
    harness.Check("the moved pane kept its edge", moved != null
                  && ((DockPlacement)moved).Edge == DockEdge.Left);
    harness.Check("and kept being unpinned", moved != null && !((DockPlacement)moved).IsPinned);

    // Two panes on one edge must come back in the order they went out, which
    // is what makes the tab order of the bottom well stay put between runs.
    var bottom = again.GetPlacementsOn(DockEdge.Bottom);
    harness.CheckSameNumber("the bottom well still has two", 2, (long)bottom.Count);
    harness.CheckSame("in the order they were written", Panes.Errors, bottom[0u].Name);
    harness.CheckSame("and the second stayed second", Panes.Output, bottom[1u].Name);

    // The text itself, not merely what it parses to: a file a person is
    // expected to be able to edit is a file that has to be readable.
    harness.Check("it is written indented", SerializeLayout(layout).Contains("\n  \"left\""));
}

void TestRefusing(Harness harness)
{
    Console.WriteLine("sizes that would hide the editor");

    var layout = new DockLayout();
    layout.LeftWidth = 9000;
    harness.CheckSameNumber("a width past the screen is capped", (long)LargestWell,
                            (long)layout.LeftWidth);

    layout.BottomHeight = 2;
    harness.CheckSameNumber("and one dragged shut is floored", (long)SmallestWell,
                            (long)layout.BottomHeight);

    // Through the file, which is the path that matters: the drag is guarded by
    // the control, and the file is guarded by nothing else.
    var read = ParseLayout("{\"left\":40000,\"bottom\":-5,"
                           + "\"panes\":[{\"name\":\"solution\",\"edge\":\"left\"}]}");
    harness.CheckSameNumber("a file saying 40000 is capped too", (long)LargestWell,
                            (long)read.LeftWidth);
    harness.CheckSameNumber("and a negative height is floored", (long)SmallestWell,
                            (long)read.BottomHeight);
}

void TestSurviving(Harness harness)
{
    Console.WriteLine("files that are not what this build writes");

    // Not JSON at all. The window opens on the default arrangement; it does
    // not refuse to open, which is the difference between this reader and
    // every other one in the tree and is argued for where it is written.
    var broken = ParseLayout("{not json");
    harness.CheckSameNumber("a broken file gives the default", 3, (long)broken.Places.Count);
    harness.Check("with the tree on the left", broken.Find(Panes.Solution) != null);

    var empty = ParseLayout("");
    harness.CheckSameNumber("so does an empty one", 3, (long)empty.Places.Count);

    var array = ParseLayout("[1,2,3]");
    harness.CheckSameNumber("so does JSON that is not an object", 3, (long)array.Places.Count);

    // A byte order mark in front of it, which is what Notepad and PowerShell
    // 5.1 write. This one is not hypothetical: it is how the first hand-edited
    // layout file silently did nothing, and the fix is in `Standard.Json`.
    var marked = ParseLayout("﻿{\"left\":320,\"panes\":["
                             + "{\"name\":\"solution\",\"edge\":\"left\"}]}");
    harness.CheckSameNumber("a file with a byte order mark is read", 1,
                            (long)marked.Places.Count);
    harness.CheckSameNumber("and its widths arrive", 320, (long)marked.LeftWidth);

    // A file from a build that had panes this one does not. The unknown pane
    // is kept -- it costs nothing and a downgrade followed by an upgrade
    // should not lose where the toolbox was -- and the known ones still land.
    var newer = ParseLayout("{\"left\":250,\"panes\":["
                            + "{\"name\":\"toolbox\",\"edge\":\"left\",\"pinned\":true},"
                            + "{\"name\":\"solution\",\"edge\":\"right\",\"pinned\":false}]}");
    harness.CheckSameNumber("a newer file keeps both panes", 2, (long)newer.Places.Count);
    harness.Check("the pane this build knows moved", newer.Find(Panes.Solution) != null
                  && ((DockPlacement)newer.Find(Panes.Solution)).Edge == DockEdge.Right);
    harness.Check("and the one it does not is kept", newer.Find("toolbox") != null);
    harness.CheckSameNumber("the width came through", 250, (long)newer.LeftWidth);

    // An edge name from a build with a fourth well. It must land somewhere
    // visible rather than nowhere, so it lands in the document well.
    var strange = ParseLayout("{\"panes\":[{\"name\":\"solution\",\"edge\":\"ceiling\"}]}");
    var lost = strange.Find(Panes.Solution);
    harness.Check("an edge this build has no well for is the document well",
                  lost != null && ((DockPlacement)lost).Edge == DockEdge.Document);

    // A pane whose fields are the wrong shape entirely. Dropped, not fatal.
    var wrong = ParseLayout("{\"panes\":[{\"name\":5},{\"name\":\"output\",\"pinned\":\"yes\"}]}");
    harness.CheckSameNumber("a pane with no usable name is dropped", 1,
                            (long)wrong.Places.Count);
    harness.Check("and a pinned that is not a bool reads as pinned",
                  wrong.Find(Panes.Output) != null
                  && ((DockPlacement)wrong.Find(Panes.Output)).IsPinned);
}
