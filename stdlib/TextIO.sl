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

/// A reader over a stream, decoding as it goes.
///
/// It reads a buffer at a time and decodes each one through an `IDecoder`,
/// which keeps the bytes a buffer ended in the middle of and finishes the
/// character when the next buffer arrives. That is what makes this a stream
/// reader rather than a way of spelling `ReadToEnd`: a log being followed, or
/// a file larger than memory, works.
///
/// A byte order mark at the very start is dropped, in whatever encoding: it
/// says how the text is stored and is not part of the first line.
///
/// `ReadLine` answers null at the end and also when the stream fails; `Error`
/// tells the two apart.
///
/// @see StreamWriter
public class StreamReader : TextReader
{
    /// What .NET reads at a time, and for the same reason: large enough that
    /// the syscall is not the cost, small enough to be nothing on a small file.
    const nuint BufferSize = 1024;

    IStream _stream;
    IEncoding _encoding;
    IDecoder _decoder;

    byte[] _bytes;

    /// Text decoded and not yet handed back, and how far into it that is.
    StringBuilder _ready;
    nuint _at;

    bool _ended;
    bool _closed;
    bool _markChecked;
    IOError _error;

    /// UTF-8, which is what a file without a preamble almost always is.
    public StreamReader(IStream stream)
    {
        _stream = stream;
        _encoding = CreateUtf8();
        _decoder = _encoding.GetDecoder();
        _bytes = new byte[BufferSize];
        _ready = new StringBuilder();
        _at = 0u;
        _ended = false;
        _closed = false;
        _markChecked = false;
        _error = IOError.None;
    }

    /// In a stated encoding, for a file that is not UTF-8 and says so
    /// somewhere other than in itself.
    public StreamReader(IStream stream, IEncoding encoding)
    {
        _stream = stream;
        _encoding = encoding;
        _decoder = encoding.GetDecoder();
        _bytes = new byte[BufferSize];
        _ready = new StringBuilder();
        _at = 0u;
        _ended = false;
        _closed = false;
        _markChecked = false;
        _error = IOError.None;
    }

    /// The encoding the text is being read as.
    public IEncoding Encoding => _encoding;

    /// Why the stream stopped, when it was a failure rather than the end.
    /// `None` until then.
    public IOError Error => _error;

    /// Reads one buffer and decodes it, answering whether anything new
    /// arrived. False means the stream is finished and the decoder flushed.
    bool FillBuffer()
    {
        if (_ended)
            return false;

        nuint got = _stream.Read(_bytes, 0u, BufferSize);
        if (got == 0u)
        {
            _ended = true;
            _error = _stream.Error;

            // The flush turns anything the decoder still holds into U+FFFD: a
            // file that stops mid-character is malformed, not unfinished.
            String last = _decoder.GetString(_bytes, 0u, 0u, true);
            if (last.IsEmpty)
                return false;

            _ready.Append(last);
            this.DropByteOrderMark();
            return true;
        }

        String more = _decoder.GetString(_bytes, 0u, got, false);

        // A whole buffer can complete no character at all -- one scalar of
        // UTF-32 split across two reads, say -- so this says nothing arrived
        // rather than that the stream ended.
        if (more.IsEmpty)
            return true;

        _ready.Append(more);
        this.DropByteOrderMark();
        return true;
    }

    /// Removes U+FEFF from the start of the text, once, when the first
    /// decoded text arrives. The decoder hands back whole characters, so a
    /// mark is never split across two calls.
    void DropByteOrderMark()
    {
        if (_markChecked || _ready.ByteLength() == 0u)
            return;
        _markChecked = true;

        if (_ready.ByteLength() >= 3u && _ready.GetByteAt(0u) == 0xEF
            && _ready.GetByteAt(1u) == 0xBB && _ready.GetByteAt(2u) == 0xBF)
        {
            _ready.Remove(0u, 3u);
        }
    }

    /// Drops what has already been handed back, so a long read does not keep
    /// growing the buffer it is reading from.
    void CompactBuffer()
    {
        if (_at == 0u)
            return;
        _ready.Remove(0u, _at);
        _at = 0u;
    }

    public override String? ReadLine()
    {
        if (_closed)
            return null;

        while (true)
        {
            // The terminator is looked for in what is decoded, which is UTF-8
            // whatever the stream was: 0x0A there is never part of a character.
            for (nuint i = _at; i < _ready.ByteLength(); i++)
            {
                if (_ready.GetByteAt(i) != 0x0A)
                    continue;

                nuint end = i;
                if (end > _at && _ready.GetByteAt(end - 1u) == 0x0D)
                    end--;

                String line = DecodeBetween(_at, end);
                _at = i + 1u;
                this.CompactBuffer();
                return line;
            }

            if (!this.FillBuffer())
                break;
        }

        // Whatever is left with no terminator after it is still a line.
        if (_at >= _ready.ByteLength())
            return null;

        String rest = DecodeBetween(_at, _ready.ByteLength());
        _at = _ready.ByteLength();
        this.CompactBuffer();
        return rest;
    }

    public override String ReadToEnd()
    {
        if (_closed)
            return "";

        while (this.FillBuffer()) { }

        if (_at >= _ready.ByteLength())
            return "";

        String rest = DecodeBetween(_at, _ready.ByteLength());
        _at = _ready.ByteLength();
        this.CompactBuffer();
        return rest;
    }

    /// The decoded text between two byte positions.
    String DecodeBetween(nuint from, nuint to)
    {
        if (to <= from)
            return "";

        var piece = new StringBuilder();
        for (nuint i = from; i < to; i++)
            piece.AppendByte(_ready.GetByteAt(i));
        return piece.ToText();
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
