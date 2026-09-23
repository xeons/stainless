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

/// A reader over text already in memory.
///
/// @see StringWriter
public class StringReader : TextReader
{
    String _text;
    nuint _at;

    public StringReader(String text)
    {
        _text = text;
        _at = 0u;
    }

    public override String? ReadLine()
    {
        nuint size = _text.ByteLength();
        if (_at >= size)
            return null;

        // The terminator is found in the bytes, which is safe on UTF-8: a
        // sequence cannot begin inside another, so 0x0A is never part of one.
        nuint start = _at;
        while (_at < size && _text.GetByteAt(_at) != 0x0A)
            _at++;

        nuint end = _at;
        if (_at < size)
            _at++;

        // The carriage return of a CRLF belongs to the terminator.
        if (end > start && _text.GetByteAt(end - 1u) == 0x0D)
            end--;

        return _text.Substring(start, end - start);
    }

    public override String ReadToEnd()
    {
        if (_at >= _text.ByteLength())
            return "";

        String rest = _text.Substring(_at, _text.ByteLength() - _at);
        _at = _text.ByteLength();
        return rest;
    }

    public override void Close()
    {
        _at = _text.ByteLength();
    }
}
