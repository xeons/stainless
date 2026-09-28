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

/// Reads TLS structures out of part of an array, big-endian.
///
/// **Failure is sticky.** A read past the end sets `Failed`, answers zero or
/// nothing, and every read after it does the same, so a parser reads every
/// field and checks once. A vector read from here is a reader of its own over
/// the vector's bytes; its failure is its own to check.
internal sealed class TlsReader
{
    private byte[] _data;
    private nuint _position;
    private nuint _end;
    private bool _failed;

    internal TlsReader(byte[] data, nuint offset, nuint length)
    {
        _data = data;
        _position = offset;
        _end = offset + length;
        _failed = false;
    }

    internal bool Failed => _failed;

    internal bool IsAtEnd => _position == _end;

    internal nuint Remaining => _end - _position;

    /// Where the next read will happen, in the array underneath.
    internal nuint Position => _position;

    internal byte[] Underlying => _data;

    internal void MarkFailed() => _failed = true;

    internal uint ReadByte()
    {
        if (!CanReadTlsBytes(1u))
            return 0u;
        uint value = (uint)_data[_position];
        _position++;
        return value;
    }

    internal uint ReadUInt16()
    {
        if (!CanReadTlsBytes(2u))
            return 0u;
        uint value = ((uint)_data[_position] << 8) | (uint)_data[_position + 1u];
        _position += 2u;
        return value;
    }

    internal uint ReadUInt24()
    {
        if (!CanReadTlsBytes(3u))
            return 0u;
        uint value = ((uint)_data[_position] << 16) | ((uint)_data[_position + 1u] << 8) |
                     (uint)_data[_position + 2u];
        _position += 3u;
        return value;
    }

    internal uint ReadUInt32()
    {
        uint high = ReadUInt16();
        uint low = ReadUInt16();
        return (high << 16) | low;
    }

    /// The next `count` bytes as a view of the array underneath.
    internal ReadOnlySpan<byte> ReadSpan(nuint count)
    {
        if (!CanReadTlsBytes(count))
            return ReadOnlySpan<byte>.Empty;
        ReadOnlySpan<byte> part = _data[_position:][:count];
        _position += count;
        return part;
    }

    /// The next `count` bytes as an array of their own.
    internal byte[] ReadArray(nuint count)
    {
        if (!CanReadTlsBytes(count))
            return new byte[0u];
        var copy = new byte[count];
        if (count > 0u)
            memcpy(&copy[0u], &_data[_position], count);
        _position += count;
        return copy;
    }

    /// A vector: a length prefix of `prefixSize` bytes, then that many bytes,
    /// which MUST number between `minimum` and `maximum`.
    internal TlsReader ReadVector(nuint prefixSize, nuint minimum, nuint maximum)
    {
        nuint size = ReadTlsVectorLength(prefixSize);
        if (_failed || size < minimum || size > maximum || size > Remaining)
        {
            _failed = true;
            return new TlsReader(_data, _position, 0u);
        }

        var inner = new TlsReader(_data, _position, size);
        _position += size;
        return inner;
    }

    /// A vector's bytes as an array of their own.
    internal byte[] ReadVectorArray(nuint prefixSize, nuint minimum, nuint maximum)
    {
        nuint size = ReadTlsVectorLength(prefixSize);
        if (_failed || size < minimum || size > maximum || size > Remaining)
        {
            _failed = true;
            return new byte[0u];
        }
        return ReadArray(size);
    }

    private nuint ReadTlsVectorLength(nuint prefixSize)
    {
        switch (prefixSize)
        {
            case 1u: return (nuint)ReadByte();
            case 2u: return (nuint)ReadUInt16();
            default: return (nuint)ReadUInt24();
        }
    }

    private bool CanReadTlsBytes(nuint count)
    {
        if (_failed || count > _end - _position)
        {
            _failed = true;
            return false;
        }
        return true;
    }
}
