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

module Standard.Net.Security;

/// A growable run of bytes that TLS structures are written into, big-endian,
/// with vectors whose length prefix is filled in once their contents are.
///
/// **A vector too long for its prefix is sticky, as `TlsReader`'s failure
/// is.** `EndVector` sets `HasOverflowed` rather than write a length that
/// wraps, and whoever builds a structure from peer-sized or caller-sized
/// parts MUST check it before the bytes are used.
internal sealed class TlsBuffer
{
    private byte[] _bytes;
    private nuint _length;
    private bool _overflowed;

    internal TlsBuffer(nuint capacity)
    {
        _bytes = new byte[capacity == 0u ? 16u : capacity];
        _length = 0u;
        _overflowed = false;
    }

    /// Whether a vector was longer than its length prefix can say.
    internal bool HasOverflowed => _overflowed;

    /// How many bytes have been written.
    internal nuint Length => _length;

    /// The storage. Only the first `Length` bytes mean anything.
    internal byte[] Storage => _bytes;

    /// The bytes written so far, as a view.
    internal ReadOnlySpan<byte> Written => _bytes[:_length];

    internal void Clear()
    {
        _length = 0u;
        _overflowed = false;
    }

    internal void WriteByte(uint value)
    {
        ReserveTlsBytes(1u);
        _bytes[_length] = (byte)(value & 0xFFu);
        _length++;
    }

    internal void WriteUInt16(uint value)
    {
        ReserveTlsBytes(2u);
        _bytes[_length] = (byte)((value >> 8) & 0xFFu);
        _bytes[_length + 1u] = (byte)(value & 0xFFu);
        _length += 2u;
    }

    internal void WriteUInt24(uint value)
    {
        ReserveTlsBytes(3u);
        _bytes[_length] = (byte)((value >> 16) & 0xFFu);
        _bytes[_length + 1u] = (byte)((value >> 8) & 0xFFu);
        _bytes[_length + 2u] = (byte)(value & 0xFFu);
        _length += 3u;
    }

    internal void WriteUInt32(uint value)
    {
        WriteUInt16(value >> 16);
        WriteUInt16(value & 0xFFFFu);
    }

    internal void WriteBytes(ReadOnlySpan<byte> data)
    {
        ReserveTlsBytes(data.Length);
        for (nuint i = 0u; i < data.Length; i++)
            _bytes[_length + i] = data[i];
        _length += data.Length;
    }

    /// Writes `count` bytes of `data` from `offset` with one copy.
    internal void WriteArray(byte[] data, nuint offset, nuint count)
    {
        if (count == 0u)
            return;
        ReserveTlsBytes(count);
        memcpy(&_bytes[_length], &data[offset], count);
        _length += count;
    }

    /// Reserves a length prefix of `prefixSize` bytes and answers where it
    /// is, for `EndVector` to fill in.
    internal nuint BeginVector(nuint prefixSize)
    {
        nuint at = _length;
        ReserveTlsBytes(prefixSize);
        for (nuint i = 0u; i < prefixSize; i++)
            _bytes[_length + i] = 0;
        _length += prefixSize;
        return at;
    }

    /// Fills in the prefix `BeginVector` reserved with the length of what
    /// was written since. A length the prefix cannot hold sets
    /// `HasOverflowed` and leaves the prefix zero.
    internal void EndVector(nuint at, nuint prefixSize)
    {
        nuint size = _length - at - prefixSize;
        if (prefixSize < 8u && size >> (8u * prefixSize) != 0u)
        {
            _overflowed = true;
            return;
        }
        for (nuint i = 0u; i < prefixSize; i++)
            _bytes[at + prefixSize - 1u - i] = (byte)((size >> (8u * i)) & 0xFFu);
    }

    /// Drops the first `count` bytes and moves the rest down.
    internal void RemoveFront(nuint count)
    {
        nuint left = _length - count;
        if (left > 0u)
            memmove(&_bytes[0u], &_bytes[count], left);
        _length = left;
    }

    internal byte[] ToArray()
    {
        var copy = new byte[_length];
        if (_length > 0u)
            memcpy(&copy[0u], &_bytes[0u], _length);
        return copy;
    }

    private void ReserveTlsBytes(nuint more)
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
