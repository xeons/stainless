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

// ================================================================== writing

/// Text going somewhere, a piece at a time.
///
/// @see TextReader
public abstract class TextWriter
{
    /// What `WriteLine` puts after a line. `"\n"` until set.
    String _newLine = "\n";

    /// Text, with nothing after it.
    public abstract void Write(String text);

    /// Pushes whatever is held onward.
    public abstract void Flush();

    /// Flushes and releases what the writer holds.
    public abstract void Close();

    /// What ends a line here.
    public String NewLine
    {
        get { return _newLine; }
        set { _newLine = value; }
    }

    /// Text and a line ending.
    public void WriteLine(String text)
    {
        this.Write(text);
        this.Write(_newLine);
    }

    /// A line ending on its own.
    public void WriteLine()
    {
        this.Write(_newLine);
    }

    /// Each of `lines`, each ended.
    public void WriteLines(String[] lines)
    {
        for (nuint i = 0u; i < lines.Length; i++)
            this.WriteLine(lines[i]);
    }
}
