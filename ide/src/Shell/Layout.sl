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

// Where the tool windows are: which edge each is on, which are pinned, and how
// wide the wells are.
//
// **No control is mentioned in this file, and that is the point.** The repo's
// hardest-won lesson is that a GUI self-test proves nothing -- `forms/` passed
// 116 checks for months while a control was one pixel wide and nothing reached
// the screen. So the half of docking that *can* be answered without a screen is
// separated out and tested without one: a layout is a list of placements and
// three sizes, it round-trips through JSON, and a file written by a newer build
// must not take the window down.
//
// `DockHost.sl` is the other half -- the panels, the splitters and the strips --
// and it holds one of these and does what it says. The seam is deliberately at
// "which edge, pinned or not, how wide" rather than lower down, because that is
// exactly the set of questions a person answers by dragging and expects to find
// answered again tomorrow.
module Ide.Shell;

import Standard.Collections;
import Standard.Directory;
import Standard.Env;
import Standard.File;
import Standard.IO;
import Standard.Json;
import Standard.Path;
import Standard.Text;

/// Which well a tool window lives in.
///
/// `Document` is the middle one -- the tabbed editors -- and is here rather
/// than being a separate concept because a layout that could not name it would
/// have no way to say "this pane is not in a side well", and a null edge is a
/// worse way to say the same thing.
public enum DockEdge { Left, Right, Bottom, Document }

/// One tool window's place: which edge, whether it is pinned open, and where it
/// sits among the others on that edge.
///
/// **Named by a string, not by a type.** The layout file outlives the build
/// that wrote it, and a pane that has been renamed or removed since must read
/// back as "a name I do not recognise" rather than as a broken enum. It is also
/// what lets the file be edited by hand, which is worth more here than in most
/// places: this is the file to delete when the window comes back wrong.
public class DockPlacement
{
    public String Name;
    public DockEdge Edge;
    public bool Pinned;
    /// Position within the well, low first. Ties keep the order they were read.
    public nuint Order;

    public DockPlacement(String name, DockEdge edge, bool pinned, nuint order)
    {
        Name = name;
        Edge = edge;
        Pinned = pinned;
        Order = order;
    }
}

/// The smallest a well may be left at, in pixels.
///
/// Not zero: a well dragged shut is indistinguishable from one that failed to
/// appear, and the difference matters when the next person to look at it is
/// deciding whether the IDE is broken. Closing a pane is what closes a pane.
public const int SmallestWell = 60;

/// The widest a side well may be, and the tallest the bottom one. A guard on
/// the file rather than on the drag: a layout written by a build with a bigger
/// screen must not open the next session with no room for the editor.
public const int LargestWell = 1200;

/// Where the tool windows are.
public class DockLayout
{
    List<DockPlacement> _places;
    int _left;
    int _right;
    int _bottom;

    public DockLayout()
    {
        _places = new List<DockPlacement>();
        _left = 240;
        _right = 260;
        _bottom = 180;
    }

    public List<DockPlacement> Places => _places;

    /// How wide the left well is, how wide the right, how tall the bottom.
    ///
    /// Clamped on the way in rather than on the way out, so that a value read
    /// from a file and a value dragged by a person are held to the same rule
    /// and there is one place that knows it.
    public int LeftWidth
    {
        get => _left;
        set => _left = Clamp(value);
    }

    public int RightWidth
    {
        get => _right;
        set => _right = Clamp(value);
    }

    public int BottomHeight
    {
        get => _bottom;
        set => _bottom = Clamp(value);
    }

    static int Clamp(int size)
    {
        if (size < SmallestWell)
            return SmallestWell;
        if (size > LargestWell)
            return LargestWell;
        return size;
    }

    /// The placement of a pane, or null when the layout does not mention it.
    ///
    /// Null rather than a default, because "this file predates the pane" and
    /// "this file puts the pane on the left" are different answers and the
    /// caller is the only one that knows what a missing pane should do.
    public DockPlacement? Find(String name)
    {
        foreach (var place in _places)
        {
            if (place.Name == name)
                return place;
        }
        return null;
    }

    /// Puts a pane somewhere, replacing wherever it was.
    public DockPlacement Place(String name, DockEdge edge, bool pinned)
    {
        var already = Find(name);
        if (already != null)
        {
            var found = (DockPlacement)already;
            found.Edge = edge;
            found.Pinned = pinned;
            return found;
        }

        var made = new DockPlacement(name, edge, pinned, Count(edge));
        _places.Add(made);
        return made;
    }

    /// How many panes are on an edge.
    public nuint Count(DockEdge edge)
    {
        nuint total = 0u;
        foreach (var place in _places)
        {
            if (place.Edge == edge)
                total++;
        }
        return total;
    }

    /// The panes on one edge, in the order they should appear.
    ///
    /// An insertion sort over a handful of entries, which is the right
    /// algorithm for a list never longer than the number of tool windows the
    /// IDE has. Insertion rather than selection because it is **stable**: two
    /// panes written with the same order keep the order the file had, instead
    /// of swapping about between runs for no reason a reader could see.
    public List<DockPlacement> On(DockEdge edge)
    {
        var chosen = new List<DockPlacement>();
        foreach (var place in _places)
        {
            if (place.Edge == edge)
                chosen.Add(place);
        }

        for (nuint i = 1u; i < chosen.Count; i++)
        {
            var moving = chosen.At(i);
            nuint j = i;
            while (j > 0u && chosen.At(j - 1u).Order > moving.Order)
            {
                chosen.Set(j, chosen.At(j - 1u));
                j--;
            }
            chosen.Set(j, moving);
        }

        return chosen;
    }

    /// The arrangement a first run gets: the tree on the left, properties on
    /// the right, the build's two panes sharing the bottom.
    ///
    /// The Visual Studio arrangement rather than an invention, because the
    /// point of the exercise is that someone who knows that window knows this
    /// one. What is deliberately different is that nothing floats -- see
    /// `DockHost.sl` for why that is a decision and not an omission.
    /// **Only panes that exist.** `Panes.Properties` is named here in the
    /// constant list and deliberately not placed: the pane is not built yet, and
    /// a default layout describing one the window never makes would put a line
    /// in everyone's settings file for something they cannot see. When the pane
    /// arrives it is placed by `DockHost.Add`'s fallback, which is the same path
    /// that handles a settings file written before any later pane existed.
    public static DockLayout Default()
    {
        var layout = new DockLayout();
        layout.Place(Panes.Solution, DockEdge.Left, true);
        layout.Place(Panes.Errors, DockEdge.Bottom, true);
        layout.Place(Panes.Output, DockEdge.Bottom, true);
        return layout;
    }
}

/// What each pane is called in the layout file.
///
/// Constants rather than literals at the call sites, so that the name in the
/// file and the name the window asks for cannot drift apart silently -- which
/// is the one failure this file is otherwise wide open to, since an unknown
/// name is deliberately not an error.
public static class Panes
{
    public static readonly String Solution = "solution";
    public static readonly String Properties = "properties";
    public static readonly String Errors = "errors";
    public static readonly String Output = "output";
}

// ===================================================================== naming

/// The edge an enum member is written as in the file.
public String EdgeName(DockEdge edge)
{
    if (edge == DockEdge.Left)
        return "left";
    if (edge == DockEdge.Right)
        return "right";
    if (edge == DockEdge.Bottom)
        return "bottom";
    return "document";
}

/// And back. An unrecognised edge is the document well, which is the one that
/// always exists -- so a file naming an edge this build does not have puts the
/// pane somewhere visible rather than nowhere.
public DockEdge EdgeFrom(String name)
{
    if (name == "left")
        return DockEdge.Left;
    if (name == "right")
        return DockEdge.Right;
    if (name == "bottom")
        return DockEdge.Bottom;
    return DockEdge.Document;
}

// ==================================================================== reading

/// Reads a layout, answering the default arrangement for anything that is not
/// one.
///
/// **It cannot fail, and that is deliberate.** Every other reader in this tree
/// refuses what it does not understand -- `stainless.json` names the typo and
/// stops, because a project half-read builds the wrong program. A layout is the
/// opposite case: there is nothing to get wrong that is worth losing the window
/// over, and an IDE that will not start because a pane's width is a string is a
/// worse tool than one that opens with the panes where they started. So this
/// takes what it recognises and quietly drops the rest.
///
/// The thing that *is* checked is the size, because a well wider than the
/// screen is how a layout file takes the editor away entirely.
public DockLayout ReadLayout(String path)
{
    if (!File.Exists(path))
        return DockLayout.Default();

    var text = File.ReadAllText(path);
    if (!text.Ok)
        return DockLayout.Default();

    return ParseLayout(text.Value);
}

/// The same, from text in hand. This is what the tests drive.
public DockLayout ParseLayout(String text)
{
    var parsed = Json.Parse(text);
    if (!parsed.Ok)
        return DockLayout.Default();

    var document = parsed.Value;
    if (!document.Object)
        return DockLayout.Default();

    var members = document.Members;
    var layout = new DockLayout();

    if (members.IndexOf("left") is Some left)
        layout.LeftWidth = (int)Json.IntegerOr(members.ValueAt(left.Value), (long)layout.LeftWidth);
    if (members.IndexOf("right") is Some right)
        layout.RightWidth = (int)Json.IntegerOr(members.ValueAt(right.Value), (long)layout.RightWidth);
    if (members.IndexOf("bottom") is Some bottom)
        layout.BottomHeight = (int)Json.IntegerOr(members.ValueAt(bottom.Value), (long)layout.BottomHeight);

    if (members.IndexOf("panes") is Some at)
    {
        var value = members.ValueAt(at.Value);
        if (value.Array)
        {
            var items = value.Items;
            for (nuint i = 0u; i < items.Count; i++)
            {
                var item = items.At(i);
                if (!item.Object)
                    continue;

                var inside = item.Members;
                if (inside.IndexOf("name") is Some named)
                {
                    String name = Json.TextOr(inside.ValueAt(named.Value), "");
                    if (name == "")
                        continue;

                    DockEdge edge = DockEdge.Document;
                    if (inside.IndexOf("edge") is Some where)
                        edge = EdgeFrom(Json.TextOr(inside.ValueAt(where.Value), "document"));

                    bool pinned = true;
                    if (inside.IndexOf("pinned") is Some held)
                        pinned = Json.BoolOr(inside.ValueAt(held.Value), true);

                    var place = layout.Place(name, edge, pinned);
                    place.Order = i;
                }
            }
        }
    }

    // A file that named no pane it recognised is a file from a build that
    // called them something else, and starting with three empty wells would
    // read as the panes having failed to appear. The default arrangement is
    // the honest answer, and the next save overwrites the file.
    if (layout.Places.IsEmpty())
        return DockLayout.Default();

    return layout;
}

/// What the layout is written as.
public String WriteLayout(DockLayout layout)
{
    var members = new JsonObject();
    members.Add("left", Json.NumberOf((long)layout.LeftWidth));
    members.Add("right", Json.NumberOf((long)layout.RightWidth));
    members.Add("bottom", Json.NumberOf((long)layout.BottomHeight));

    var panes = new List<JsonValue>();
    AppendEdge(panes, layout, DockEdge.Left);
    AppendEdge(panes, layout, DockEdge.Right);
    AppendEdge(panes, layout, DockEdge.Bottom);
    AppendEdge(panes, layout, DockEdge.Document);

    members.Add("panes", JsonValue.Array(panes));
    return Json.WriteIndented(JsonValue.Object(members));
}

/// Written edge by edge rather than in the order the panes were added, so that
/// the file groups the way the window does and a person reading it can see the
/// arrangement. The order within the array is what `Order` is read back from,
/// which is why this is also what makes the round trip stable.
void AppendEdge(List<JsonValue> panes, DockLayout layout, DockEdge edge)
{
    foreach (var place in layout.On(edge))
    {
        var inside = new JsonObject();
        inside.Add("name", JsonValue.Text(place.Name));
        inside.Add("edge", JsonValue.Text(EdgeName(place.Edge)));
        inside.Add("pinned", JsonValue.Bool(place.Pinned));
        panes.Add(JsonValue.Object(inside));
    }
}

/// Saves a layout, making the directory if it is not there. Answers whether it
/// landed; a caller that cannot save its layout carries on regardless, which is
/// why nothing here says what went wrong.
public bool SaveLayout(DockLayout layout, String path)
{
    String folder = Path.DirectoryName(path);
    if (folder != "" && !Directory.Exists(folder))
    {
        if (Directory.CreateAll(folder) != IOError.None)
            return false;
    }

    return File.WriteAllText(path, WriteLayout(layout)) == IOError.None;
}

/// Where the settings live: `%APPDATA%/Stainless/ide` on Windows, and
/// `$XDG_CONFIG_HOME/stainless/ide` -- falling back to `~/.config` -- on
/// everything else.
///
/// The two spellings differ in case as well as in place, which is not an
/// oversight: each matches what the rest of that system does, and a directory
/// called `Stainless` in `~/.config` would be the odd one out there in exactly
/// the way `stainless` would be under `%APPDATA%`.
public String SettingsDirectory()
{
#if WINDOWS
    String roaming = Env.GetOr("APPDATA", "");
    if (roaming != "")
        return Path.Join(Path.Join(roaming, "Stainless"), "ide");
#else
    String config = Env.GetOr("XDG_CONFIG_HOME", "");
    if (config == "")
    {
        String home = Env.GetOr("HOME", "");
        if (home != "")
            config = Path.Join(home, ".config");
    }
    if (config != "")
        return Path.Join(Path.Join(config, "stainless"), "ide");
#endif

    // Nowhere to put it. The caller gets a path in the current directory,
    // which is wrong but writable -- and better than a path that is empty,
    // since that one silently writes a file called `layout.json` at the root.
    return ".";
}

/// The layout file itself.
public String LayoutPath() => Path.Join(SettingsDirectory(), "layout.json");
