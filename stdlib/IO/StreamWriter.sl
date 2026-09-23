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

/// A writer over a stream, encoding as it goes.
///
/// Unlike the reader this is genuinely incremental: every encoding here is
/// stateless, so each piece of text can be encoded and written on its own.
///
/// @see StreamReader
public class StreamWriter : TextWriter
{
    IStream _stream;
    IEncoding _encoding;
    bool _closed;

    /// UTF-8, and no preamble: a preamble is a choice about the file rather
    /// than about the text, so it is `WritePreamble` and not automatic.
    public StreamWriter(IStream stream)
    {
        _stream = stream;
        _encoding = CreateUtf8();
        _closed = false;
    }

    public StreamWriter(IStream stream, IEncoding encoding)
    {
        _stream = stream;
        _encoding = encoding;
        _closed = false;
    }

    /// The encoding the text is being written in.
    public IEncoding Encoding => _encoding;

    /// The bytes that mark this encoding, written at the position the stream
    /// is at. Call it before anything else or not at all.
    public void WritePreamble()
    {
        byte[] mark = _encoding.Preamble;
        if (mark.Length > 0u)
            _stream.Write(mark, 0u, mark.Length);
    }

    public override void Write(String text)
    {
        if (_closed || text.IsEmpty)
            return;

        byte[] bytes = _encoding.GetBytes(text);
        if (bytes.Length > 0u)
            _stream.Write(bytes, 0u, bytes.Length);
    }

    public override void Flush()
    {
        if (!_closed)
            _stream.Flush();
    }

    /// Flushes and closes the stream under it.
    public override void Close()
    {
        if (_closed)
            return;
        _stream.Flush();
        _stream.Close();
        _closed = true;
    }
}
