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

import Standard.Collections;

// ----------------------------------------------------------- memory stream

/// A stream over a growable byte buffer.
///
/// The same interface as a file, with nothing behind it but memory: useful for
/// building a payload before writing it, and for testing something that takes
/// an `IStream` without touching a disk.
public class MemoryStream : IStream
{
    byte[] _bytes;
    nuint _length;
    nuint _at;

    /// An empty stream, positioned at the beginning.
    public MemoryStream()
    {
        _bytes = new byte[64];
        _length = 0;
        _at = 0;
    }

    /// Starts with a copy of `initial`, positioned at the beginning.
    public MemoryStream(byte[] initial)
    {
        _bytes = new byte[initial.Length + 1];
        for (nuint i = 0; i < initial.Length; i++)
            _bytes[i] = initial[i];
        _length = initial.Length;
        _at = 0;
    }

    /// Always true.
    public bool CanRead => true;
    /// Always true.
    public bool CanWrite => true;
    /// Always true.
    public bool CanSeek => true;

    /// Reads up to `count` bytes into `buffer` at `offset`, answering how
    /// many it read. Zero means the position has reached the end; there is no
    /// failure to distinguish it from.
    public nuint Read(byte[] buffer, nuint offset, nuint count)
    {
        if (offset > buffer.Length || count > buffer.Length - offset)
            return 0;

        nuint available = _length - _at;
        nuint taking = count < available ? count : available;

        for (nuint i = 0; i < taking; i++)
            buffer[offset + i] = _bytes[_at + i];
        _at = _at + taking;
        return taking;
    }

    /// Writes `count` bytes from `buffer` at `offset`, growing the buffer as
    /// needed and answering `count`.
    ///
    /// Writing over the middle replaces those bytes rather than inserting, so
    /// the length only grows when the position passes the old end.
    public nuint Write(byte[] buffer, nuint offset, nuint count)
    {
        if (offset > buffer.Length || count > buffer.Length - offset)
            return 0;

        EnsureCapacity(_at + count);
        for (nuint i = 0; i < count; i++)
            _bytes[_at + i] = buffer[offset + i];

        _at = _at + count;
        if (_at > _length)
            _length = _at;
        return count;
    }

    /// Appends the UTF-8 bytes of `text`.
    public void WriteText(String text)
    {
        nuint size = text.ByteLength();
        EnsureCapacity(_at + size);

        var source = text.ToPointer();
        for (nuint i = 0; i < size; i++)
            _bytes[_at + i] = source[i];

        _at = _at + size;
        if (_at > _length)
            _length = _at;
    }

    /// Where the next read or write will happen.
    public long Position => (long)_at;
    /// How many bytes have been written, measured to the furthest the
    /// position has ever reached -- not the capacity of the buffer behind it.
    public long Length => (long)_length;

    /// Moves the position, answering whether it worked.
    ///
    /// Unlike a file, seeking past the end is refused: there is nothing there
    /// to leave a gap in.
    public bool Seek(long offset, SeekOrigin origin)
    {
        long target = offset;
        if (origin == SeekOrigin.Current)
            target = (long)_at + offset;
        if (origin == SeekOrigin.End)
            target = (long)_length + offset;

        if (target < 0 || target > (long)_length)
            return false;
        _at = (nuint)target;
        return true;
    }

    /// Does nothing. There is nothing behind the buffer to push bytes to.
    public void Flush() { }

    /// Nothing to release; a memory stream stays usable after it.
    public void Close() { }

    /// Always `None`. Nothing a memory stream does can fail.
    public IOError Error => IOError.None;

    /// A copy of what has been written, from the start to the high-water mark.
    public byte[] ToArray()
    {
        var copy = new byte[_length];
        for (nuint i = 0; i < _length; i++)
            copy[i] = _bytes[i];
        return copy;
    }

    /// The contents as text, read as UTF-8.
    public String ToText()
    {
        if (_length == 0)
            return "";
        return Text.FromBytes(&_bytes[0], _length);
    }

    void EnsureCapacity(nuint wanted)
    {
        if (wanted <= _bytes.Length)
            return;

        nuint size = _bytes.Length * 2;
        while (size < wanted)
            size = size * 2;

        var bigger = new byte[size];
        for (nuint i = 0; i < _length; i++)
            bigger[i] = _bytes[i];
        _bytes = bigger;
    }
}
