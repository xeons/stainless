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

/// A writer that keeps what it is given, for a caller that wanted a
/// `TextWriter` and a string rather than a file.
///
/// @see StringReader
public class StringWriter : TextWriter
{
    StringBuilder _built;

    public StringWriter()
    {
        _built = new StringBuilder();
    }

    public override void Write(String text)
    {
        _built.Append(text);
    }

    /// Nothing is held anywhere else, so this does nothing.
    public override void Flush() { }

    /// Nothing is held anywhere else, so this does nothing either. What was
    /// written stays readable.
    public override void Close() { }

    /// What has been written so far. The writer stays usable afterwards.
    public String ToText() => _built.ToText();
}
