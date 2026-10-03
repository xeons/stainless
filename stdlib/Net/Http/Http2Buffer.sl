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

module Standard.Net.Http;

/// A growable run of bytes that frames are built in.
internal sealed class Http2Buffer
{
    private byte[] _bytes;
    private nuint _length = 0u;

    internal Http2Buffer(nuint capacity) => _bytes = new byte[capacity == 0u ? 64u : capacity];

    internal nuint Length => _length;

    /// The storage; only the first `Length` bytes mean anything.
    internal byte[] Storage => _bytes;

    internal void Clear() => _length = 0u;

    internal void WriteByte(uint value)
    {
        ReserveHttp2Bytes(1u);
        _bytes[_length] = (byte)(value & 0xFFu);
        _length++;
    }

    internal void WriteUInt16(uint value)
    {
        WriteByte(value >> 8);
        WriteByte(value);
    }

    internal void WriteUInt24(uint value)
    {
        WriteByte(value >> 16);
        WriteByte(value >> 8);
        WriteByte(value);
    }

    internal void WriteUInt32(uint value)
    {
        WriteUInt16(value >> 16);
        WriteUInt16(value & 0xFFFFu);
    }

    internal void WriteArray(byte[] data, nuint offset, nuint count)
    {
        if (count == 0u)
            return;
        ReserveHttp2Bytes(count);
        memcpy(&_bytes[_length], &data[offset], count);
        _length += count;
    }

    internal void WriteText(String text)
    {
        nuint count = text.ByteLength();
        if (count == 0u)
            return;
        ReserveHttp2Bytes(count);
        memcpy(&_bytes[_length], text.ToPointer(), count);
        _length += count;
    }

    /// Appends a frame header.
    internal void WriteHttp2FrameHeader(nuint length, Http2FrameType type, uint flags,
                                        uint streamId)
    {
        WriteUInt24((uint)length);
        WriteByte((uint)type);
        WriteByte(flags);
        WriteUInt32(streamId & Http2MaxStreamId);
    }

    internal byte[] ToArray()
    {
        var copy = new byte[_length];
        if (_length > 0u)
            memcpy(&copy[0u], &_bytes[0u], _length);
        return copy;
    }

    private void ReserveHttp2Bytes(nuint more)
    {
        if (_length + more <= _bytes.Length)
            return;
        nuint size = _bytes.Length * 2u;
        while (size < _length + more)
            size *= 2u;
        var grown = new byte[size];
        if (_length > 0u)
            memcpy(&grown[0u], &_bytes[0u], _length);
        _bytes = grown;
    }
}
