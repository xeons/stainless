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

/// Text over streams: the readers and writers that sit on `IStream`.
///
/// `Standard.IO` declared a second time, because streams and the text on top
/// of them are one module and two files' worth of code.
///
/// **A line ends at a newline, and a carriage return before it is not part of
/// it.** Text written on one platform is read on the other constantly, and a
/// reader that handed back a trailing `\r` would push that job onto every
/// caller. What is written is `NewLine`, which is `"\n"` unless set --
/// deliberately not the platform's, because a program that writes a file
/// should decide what is in it rather than inherit an answer from the machine
/// it happens to run on.
module Standard.IO;

import Standard.Text;
import Standard.Collections;
import Standard.Encoding;

// ================================================================== reading

/// Text arriving from somewhere, a line at a time.
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

/// A reader over text already in memory.
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
        while (_at < size && _text.ByteAt(_at) != 0x0A)
            _at++;

        nuint end = _at;
        if (_at < size)
            _at++;

        // The carriage return of a CRLF belongs to the terminator.
        if (end > start && _text.ByteAt(end - 1u) == 0x0D)
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

/// A reader over a stream, decoding as it goes.
///
/// **It decodes the whole stream at the first read.** `IEncoding` converts a
/// whole array at a time and keeps no state between calls, so there is no way
/// to stop at a character boundary partway through a buffer and carry the
/// remainder -- and for UTF-16 or UTF-32 a byte-wise search for a terminator
/// would find one inside a character. Reading it all is the answer that is
/// correct for every encoding rather than for the convenient ones; a stream
/// larger than memory wants `ReadToEnd` on the bytes and its own decoding.
public class StreamReader : TextReader
{
    IStream _stream;
    IEncoding _encoding;
    StringReader? _text;
    bool _closed;

    /// UTF-8, which is what a file without a preamble almost always is.
    public StreamReader(IStream stream)
    {
        _stream = stream;
        _encoding = Utf8();
        _text = null;
        _closed = false;
    }

    /// In a stated encoding, for a file that is not UTF-8 and says so
    /// somewhere other than in itself.
    public StreamReader(IStream stream, IEncoding encoding)
    {
        _stream = stream;
        _encoding = encoding;
        _text = null;
        _closed = false;
    }

    /// The encoding the text is being read as.
    public IEncoding Encoding => _encoding;

    /// Decodes on the first call and does nothing afterwards.
    ///
    /// The bytes are gathered here rather than through this module's own
    /// `ReadToEnd`, because this class has a method of that name and its own
    /// wins -- which is the collision the standard library's free verbs set up
    /// for anything that names a method after one.
    StringReader Decoded()
    {
        if (_text != null)
            return (StringReader)_text;

        var all = new MemoryStream();
        var chunk = new byte[4096];

        while (true)
        {
            nuint got = _stream.Read(chunk, 0u, 4096u);
            if (got == 0u)
                break;
            all.Write(chunk, 0u, got);
        }

        var made = new StringReader(_encoding.GetString(all.ToArray()));
        _text = made;
        return made;
    }

    public override String? ReadLine()
    {
        if (_closed)
            return null;
        return this.Decoded().ReadLine();
    }

    public override String ReadToEnd()
    {
        if (_closed)
            return "";
        return this.Decoded().ReadToEnd();
    }

    /// Closes the stream under it as well, which is what a reader owning one
    /// is for.
    public override void Close()
    {
        if (_closed)
            return;
        _closed = true;
        _stream.Close();
    }
}

// ================================================================== writing

/// Text going somewhere, a piece at a time.
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

/// A writer that keeps what it is given, for a caller that wanted a
/// `TextWriter` and a string rather than a file.
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

/// A writer over a stream, encoding as it goes.
///
/// Unlike the reader this is genuinely incremental: every encoding here is
/// stateless, so each piece of text can be encoded and written on its own.
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
        _encoding = Utf8();
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
