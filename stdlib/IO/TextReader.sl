// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This file is part of the Stainless runtime library. It is free
// software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any
// later version.
//
// It is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// As an additional permission under section 7 of that License, compiling
// a program with Stainless does not by itself place that program under
// the GNU General Public License. See LICENSE.RUNTIME.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

module Standard.IO;

import Standard.Text;
import Standard.Collections;
import Standard.Encoding;

// ================================================================== reading

/// Text arriving from somewhere, a line at a time.
///
/// @see TextWriter
public abstract class TextReader
{
    /// One line without its terminator, or null once there are no more.
    ///
    /// Null rather than empty, because a blank line and no line at all are
    /// different answers and a loop reading to the end has to tell them apart.
    public abstract String? ReadLine();

    /// Everything not yet read, as one string.
    public abstract String ReadToEnd();

    /// Whatever the reader holds open.
    public abstract void Close();

    /// Every remaining line, which is `ReadLine` until it says there are none.
    public String[] ReadLines()
    {
        var found = new List<String>();
        while (true)
        {
            var line = this.ReadLine();
            if (line == null)
                break;
            found.Add((String)line);
        }
        return found.ToArray();
    }
}
