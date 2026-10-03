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

import Standard.Collections;

/// Turns HPACK header blocks back into fields, mirroring the peer encoder's
/// dynamic table.
///
/// **Every block MUST be decoded, in the order it arrived**, including one
/// for a stream nobody wants any more, or the table falls out of step with
/// the encoder's.
///
/// The table never grows past the size this end advertised, and a size
/// update asking for more is refused. A block whose fields come to more than
/// `MaxHeaderListSize` is decoded to its end, so that the table stays in
/// step, and reported as too large.
internal sealed class HpackDecoder
{
    private HpackDynamicTable _table;
    private nuint _limit;
    private byte[] _block = new byte[0u];
    private nuint _at = 0u;
    private nuint _end = 0u;

    /// The most a header list may come to, counting each field's name,
    /// value and 32 octets.
    internal nuint MaxHeaderListSize;

    /// A decoder whose table may hold at most `tableLimit`, which is what
    /// this end advertised.
    internal HpackDecoder(nuint tableLimit, nuint maxHeaderListSize)
    {
        _table = new HpackDynamicTable(tableLimit);
        _limit = tableLimit;
        MaxHeaderListSize = maxHeaderListSize;
    }

    internal HpackDynamicTable Table => _table;

    /// Decodes `count` bytes of `block` from `offset`, appending to `fields`.
    internal HpackStatus DecodeHpackHeaderBlock(byte[] block, nuint offset, nuint count,
                                                List<HpackField> fields)
    {
        _block = block;
        _at = offset;
        _end = offset + count;
        nuint listSize = 0u;
        bool tooLarge = false;
        bool fieldSeen = false;

        while (_at < _end)
        {
            uint first = (uint)_block[_at];
            HpackField? field = null;
            if ((first & 0x80u) != 0u)
            {
                if (!ReadHpackInteger(7u, out ulong index) || index == 0u)
                    return HpackStatus.Malformed;
                field = FindHpackIndexedField(index);
                if (field == null)
                    return HpackStatus.Malformed;
            }
            else if ((first & 0xC0u) == 0x40u)
            {
                field = ReadHpackLiteral(6u);
                if (field == null)
                    return HpackStatus.Malformed;
                _table.AddHpackEntry(field);
            }
            else if ((first & 0xE0u) == 0x20u)
            {
                if (fieldSeen || !ReadHpackInteger(5u, out ulong size) || size > (ulong)_limit)
                    return HpackStatus.Malformed;
                _table.ResizeHpackTable((nuint)size);
                continue;
            }
            else
            {
                // Without indexing (0000) or never indexed (0001): both leave
                // the table alone.
                field = ReadHpackLiteral(4u);
                if (field == null)
                    return HpackStatus.Malformed;
            }

            fieldSeen = true;
            var decoded = (HpackField)field;
            listSize += decoded.Size;
            if (listSize > MaxHeaderListSize)
                tooLarge = true;
            if (!tooLarge)
                fields.Add(decoded);
        }
        _block = new byte[0u];
        return tooLarge ? HpackStatus.TooLarge : HpackStatus.Decoded;
    }

    /// The field at `index` in the static table then the dynamic one, or
    /// null past both.
    private HpackField? FindHpackIndexedField(ulong index)
    {
        if (index <= (ulong)HpackStaticTableLength)
            return new HpackField(GetHpackStaticName((nuint)index),
                                  GetHpackStaticValue((nuint)index));
        ulong dynamic = index - (ulong)HpackStaticTableLength;
        if (dynamic > (ulong)_table.Count)
            return null;
        return _table.GetHpackEntry((nuint)dynamic);
    }

    /// A literal whose name index has a `prefixBits`-bit prefix, zero naming
    /// a literal name that follows.
    private HpackField? ReadHpackLiteral(uint prefixBits)
    {
        if (!ReadHpackInteger(prefixBits, out ulong nameIndex))
            return null;
        String name = "";
        if (nameIndex == 0u)
        {
            if (!ReadHpackString(out name))
                return null;
        }
        else
        {
            HpackField? named = FindHpackIndexedField(nameIndex);
            if (named == null)
                return null;
            name = named.Name;
        }
        if (!ReadHpackString(out String value))
            return null;
        return new HpackField(name, value);
    }

    /// An integer with a `prefixBits`-bit prefix (RFC 7541 §5.1). False when
    /// it runs past the block or past 2^32.
    private bool ReadHpackInteger(uint prefixBits, out ulong value)
    {
        value = 0u;
        if (_at >= _end)
            return false;
        ulong limit = ((ulong)1u << prefixBits) - 1u;
        value = (ulong)_block[_at] & limit;
        _at++;
        if (value < limit)
            return true;
        uint shift = 0u;
        while (true)
        {
            if (_at >= _end || shift > 28u)
                return false;
            ulong octet = (ulong)_block[_at];
            _at++;
            value += (octet & 0x7Fu) << shift;
            if (value > 0xFFFFFFFFu)
                return false;
            if ((octet & 0x80u) == 0u)
                return true;
            shift += 7u;
        }
    }

    /// A string literal, Huffman-coded or not (RFC 7541 §5.2).
    private bool ReadHpackString(out String text)
    {
        text = "";
        if (_at >= _end)
            return false;
        bool huffman = ((uint)_block[_at] & 0x80u) != 0u;
        if (!ReadHpackInteger(7u, out ulong length))
            return false;
        if (length > (ulong)(_end - _at))
            return false;
        nuint count = (nuint)length;
        nuint start = _at;
        _at += count;
        if (huffman)
            return DecodeHpackHuffman(_block, start, count, out text);
        text = ConvertHttpBytesToText(_block, start, count);
        return true;
    }
}
