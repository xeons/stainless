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

module Standard.IO.Compression;

// ------------------------------------------------------------------ CRC-32

/// CRC-32 as gzip, zip and PNG compute it: IEEE 802.3, reflected, polynomial
/// `0xEDB88320`, starting from all ones and inverted at the end.
///
///     uint check = Crc32.Compute("123456789"u8);     // 0xCBF43926
///
/// **The table is built per object**, 256 words, rather than held in a
/// static: this module is compiled into every program, and a static would
/// run its initializer before every `Main`. Building it costs about as much
/// as checking two kilobytes, so an object that is kept and appended to is
/// the cheap way to check many small pieces.
public sealed class Crc32
{
    uint[] _table;
    uint _state;

    /// A checksum of nothing, ready to be appended to.
    public Crc32()
    {
        _table = new uint[256];
        for (uint n = 0; n < 256u; n++)
        {
            uint c = n;
            for (int k = 0; k < 8; k++)
            {
                if ((c & 1u) != 0u)
                    c = 0xEDB88320u ^ (c >> 1);
                else
                    c = c >> 1;
            }
            _table[n] = c;
        }
        _state = 0xFFFFFFFFu;
    }

    /// The checksum of everything appended since construction or `Reset`.
    /// Reading it changes nothing, so appending may go on afterwards.
    public uint Value => _state ^ 0xFFFFFFFFu;

    /// The checksum of `data` on its own.
    public static uint Compute(ReadOnlySpan<byte> data)
    {
        var crc = new Crc32();
        crc.Append(data);
        return crc.Value;
    }

    /// Adds `data` to what has been checked so far.
    public void Append(ReadOnlySpan<byte> data)
    {
        uint c = _state;
        uint[] table = _table;
        nuint count = data.Length;
        for (nuint i = 0; i < count; i++)
            c = table[(c ^ (uint)data[i]) & 0xFFu] ^ (c >> 8);
        _state = c;
    }

    // One byte, for a caller that has no span to hand over.
    void AppendByte(byte value)
    {
        _state = _table[(_state ^ (uint)value) & 0xFFu] ^ (_state >> 8);
    }

    /// Forgets everything appended, as though the object were new.
    public void Reset()
    {
        _state = 0xFFFFFFFFu;
    }
}
