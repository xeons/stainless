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

// Where the program is to stop, held as a file and a line.
//
// The engine's `Breakpoint` is an address: chosen when the DWARF is read, slid
// when the loader places the image, gone when the process exits. A file and a
// line outlive all three, and can be set before anything has been compiled.
// This is the list the margin draws and the list each new session is handed.
//
// Nothing here touches a control, a process or a file, so
// `ide/tests/debugtest.sl` can check it with no screen.
module Ide.Debugging;

import Standard.Collections;
import Standard.Text;
import Standard.Path;
import Debugger;

/// One place the program is to stop.
public class SourceBreakpoint
{
    /// The file, spelled however the editor spells it.
    public String File;

    /// The line asked for, counting from one.
    public uint Line;

    /// Whether it is armed. A disabled breakpoint stays in the list and in the
    /// margin, and is not given to the engine.
    public bool Enabled;

    /// Whether the last session found code for it.
    public bool Bound;

    /// The line the engine chose, once it bound.
    ///
    /// A line with no code on it resolves to the first statement at or after
    /// it. The glyph moves to the line chosen, as Visual Studio's does: a
    /// breakpoint that binds elsewhere without saying so wastes an afternoon.
    public uint BoundLine;

    public SourceBreakpoint(String file, uint line)
    {
        File = file;
        Line = line;
        Enabled = true;
        Bound = false;
        BoundLine = line;
    }

    /// Where the glyph goes: the bound line once there is one.
    public uint ShownLine => Bound ? BoundLine : Line;

    /// What the Breakpoints pane shows in its text column.
    public String Describe()
    {
        String where = Standard.Path.FileName(File) + ", line "
                     + Standard.Text.FromInteger((long)ShownLine);
        if (Bound && BoundLine != Line)
            where = where + " (asked for "
                  + Standard.Text.FromInteger((long)Line) + ")";
        return where;
    }
}

/// Every breakpoint the window holds.
public class BreakpointStore
{
    List<SourceBreakpoint> _all;

    public BreakpointStore() => _all = new List<SourceBreakpoint>();

    public List<SourceBreakpoint> All => _all;
    public nuint Count => _all.Count;
    public bool IsEmpty => _all.IsEmpty;

    /// The breakpoint asked for on a line, or null.
    ///
    /// Matched on the line asked for rather than the bound one. This answers a
    /// question about the editor: the caret is on line 12 and F9 was pressed.
    public SourceBreakpoint? At(String file, uint line)
    {
        for (nuint i = 0u; i < _all.Count; i++)
        {
            if (_all[i].Line == line && IsTheSameSourceFile(_all[i].File, file))
                return _all[i];
        }
        return null;
    }

    /// The breakpoint whose glyph is drawn on a line, or null.
    ///
    /// Distinct from `At`, because a bound breakpoint has moved: asked for on
    /// line 12 and drawn on 14. Painting line 14 MUST find it and toggling
    /// line 14 MUST NOT.
    public SourceBreakpoint? ShownAt(String file, uint line)
    {
        for (nuint i = 0u; i < _all.Count; i++)
        {
            if (_all[i].ShownLine == line && IsTheSameSourceFile(_all[i].File, file))
                return _all[i];
        }
        return null;
    }

    /// Adds one if there is none there, removes it if there is. Answers what is
    /// there afterwards, or null when it was removed.
    public SourceBreakpoint? Toggle(String file, uint line)
    {
        var already = At(file, line);
        if (already != null)
        {
            Remove((SourceBreakpoint)already);
            return null;
        }

        var made = new SourceBreakpoint(file, line);
        _all.Add(made);
        return made;
    }

    public void Remove(SourceBreakpoint one)
    {
        for (nuint i = 0u; i < _all.Count; i++)
        {
            if (_all[i] == one)
            {
                _all.RemoveAt(i);
                return;
            }
        }
    }

    public void Clear() => _all.Clear();

    /// Whether any line of a file has one. Tells the editor whether it need
    /// look at the lines it paints at all.
    public bool Touches(String file)
    {
        for (nuint i = 0u; i < _all.Count; i++)
        {
            if (IsTheSameSourceFile(_all[i].File, file))
                return true;
        }
        return false;
    }

    /// Forgets where the last session put them.
    ///
    /// MUST be called when a session ends. A glyph left on the line the
    /// previous build bound it to is a claim about a program that may since
    /// have been edited. Asked-for lines are untouched.
    public void Unbind()
    {
        for (nuint i = 0u; i < _all.Count; i++)
        {
            _all[i].Bound = false;
            _all[i].BoundLine = _all[i].Line;
        }
    }

    /// Records where a session bound one. A `boundLine` of zero means no code
    /// was found for it.
    public void Bind(String file, uint line, uint boundLine)
    {
        var found = At(file, line);
        if (found == null)
            return;
        var one = (SourceBreakpoint)found;
        one.Bound = boundLine != 0u;
        one.BoundLine = boundLine != 0u ? boundLine : line;
    }

    /// Moves the breakpoints below an edit.
    ///
    /// `at` is the first line affected: the first line inserted, or the first
    /// line removed. `by` is how many, negative for a removal.
    ///
    /// A breakpoint inside a removed range lands on the line above it -- the
    /// one the removed text was joined onto, and the only line still there.
    /// Losing it silently would be worse.
    ///
    /// Anything moved is unbound: it was bound against text that has changed.
    public void Shift(String file, uint at, int by)
    {
        if (by == 0)
            return;

        uint floor = at > 1u ? at - 1u : 1u;

        for (nuint i = 0u; i < _all.Count; i++)
        {
            var one = _all[i];
            if (one.Line < at || !IsTheSameSourceFile(one.File, file))
                continue;

            long moved = (long)one.Line + (long)by;
            one.Line = moved < (long)floor ? floor : (uint)moved;
            one.Bound = false;
            one.BoundLine = one.Line;
        }
    }
}
