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

/// Turns header lists into HPACK header blocks, keeping a dynamic table that
/// the peer's decoder mirrors.
///
/// **Blocks MUST be sent in the order they were encoded**, since each one
/// changes the table the next is read against. The connection encodes and
/// writes a block under one lock.
///
/// A field already in a table is sent as its index. `authorization`,
/// `proxy-authorization` and `cookie` are never indexed (RFC 7541 §7.1.3),
/// so a secret never sits in a table where a guessing attack could probe it.
/// A value too large to be worth keeping is sent without indexing; anything
/// else is added to the table.
internal sealed class HpackEncoder
{
    private HpackDynamicTable _table;
    private nuint _smallestSize;
    private bool _resizePending = false;

    /// Whether a string is Huffman-coded where that makes it shorter.
    internal bool UsesHuffman = true;

    /// An encoder whose table starts at `tableSize`, as both ends assume.
    internal HpackEncoder(nuint tableSize)
    {
        _table = new HpackDynamicTable(tableSize);
        _smallestSize = tableSize;
    }

    internal HpackDynamicTable Table => _table;

    /// Takes the peer's `SETTINGS_HEADER_TABLE_SIZE`. The table is kept at
    /// the default size or the limit, whichever is smaller, and a change is
    /// announced at the start of the next block.
    internal void LimitHpackTableSize(nuint limit)
    {
        nuint size = limit < HpackDefaultTableSize ? limit : HpackDefaultTableSize;
        ChangeHpackTableSize(size);
    }

    /// Resizes the table from the next block on.
    internal void ChangeHpackTableSize(nuint size)
    {
        if (size == _table.MaxSize && !_resizePending)
            return;
        if (!_resizePending || size < _smallestSize)
            _smallestSize = size;
        _resizePending = true;
        _table.ResizeHpackTable(size);
    }

    /// Starts a header block: the size updates owed, the smallest size first
    /// when the table shrank and grew again (RFC 7541 §4.2).
    internal void BeginHpackHeaderBlock(Http2Buffer output)
    {
        if (!_resizePending)
            return;
        _resizePending = false;
        if (_smallestSize < _table.MaxSize)
            WriteHpackInteger(output, 0x20u, 5u, (ulong)_smallestSize);
        WriteHpackInteger(output, 0x20u, 5u, (ulong)_table.MaxSize);
        _smallestSize = _table.MaxSize;
    }

    /// Appends one field, represented as the encoder judges best.
    internal void EncodeHpackField(Http2Buffer output, String name, String value)
    {
        nuint exact = FindHpackStaticField(name, value);
        if (exact == 0u)
        {
            nuint dynamic = _table.FindHpackEntry(name, value);
            if (dynamic != 0u)
                exact = HpackStaticTableLength + dynamic;
        }
        if (exact != 0u)
        {
            WriteHpackInteger(output, 0x80u, 7u, (ulong)exact);
            return;
        }

        HpackIndexing indexing = HpackIndexing.Incremental;
        if (IsHpackSensitiveName(name))
            indexing = HpackIndexing.NeverIndexed;
        else if (name.ByteLength() + value.ByteLength() + HpackEntryOverhead > _table.MaxSize / 2u)
            indexing = HpackIndexing.WithoutIndexing;
        EncodeHpackLiteral(output, name, value, indexing);
    }

    /// Appends one field as a literal represented as `indexing` says, its
    /// name by index where a table has it.
    internal void EncodeHpackLiteral(Http2Buffer output, String name, String value,
                                     HpackIndexing indexing)
    {
        nuint nameIndex = FindHpackStaticName(name);
        if (nameIndex == 0u)
        {
            nuint dynamic = _table.FindHpackEntryName(name);
            if (dynamic != 0u)
                nameIndex = HpackStaticTableLength + dynamic;
        }

        switch (indexing)
        {
            case HpackIndexing.Incremental:
                WriteHpackInteger(output, 0x40u, 6u, (ulong)nameIndex);
                break;
            case HpackIndexing.WithoutIndexing:
                WriteHpackInteger(output, 0x00u, 4u, (ulong)nameIndex);
                break;
            case HpackIndexing.NeverIndexed:
                WriteHpackInteger(output, 0x10u, 4u, (ulong)nameIndex);
                break;
        }
        if (nameIndex == 0u)
            WriteHpackString(output, name, UsesHuffman);
        WriteHpackString(output, value, UsesHuffman);
        if (indexing == HpackIndexing.Incremental)
            _table.AddHpackEntry(new HpackField(name, value));
    }

    /// Appends a field as an index into the tables, which MUST hold it.
    internal void EncodeHpackIndexed(Http2Buffer output, nuint index) =>
        WriteHpackInteger(output, 0x80u, 7u, (ulong)index);
}

/// Whether a field carries a credential, and so is never indexed.
internal bool IsHpackSensitiveName(String name)
{
    switch (name)
    {
        case "authorization":
        case "proxy-authorization":
        case "cookie":
            return true;
    }
    return false;
}
