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

// HPACK (RFC 7541): the static table, the dynamic table, and the integer and
// string representations the encoder and decoder share.

/// The entries of the static table, numbered from 1.
internal const nuint HpackStaticTableLength = 61u;

/// What a dynamic table may hold until the peer's settings say otherwise.
internal const nuint HpackDefaultTableSize = 4096u;

/// What an entry costs beyond its name and value (RFC 7541 §4.1).
internal const nuint HpackEntryOverhead = 32u;

/// One field: a name and a value, both as octets.
internal sealed class HpackField
{
    internal String Name;
    internal String Value;

    internal HpackField(String name, String value)
    {
        Name = name;
        Value = value;
    }

    /// What the field costs in a table, and against a header list's limit.
    internal nuint Size => Name.ByteLength() + Value.ByteLength() + HpackEntryOverhead;
}

/// How a literal field is to be represented (RFC 7541 §6.2).
internal enum HpackIndexing
{
    /// Added to the dynamic table.
    Incremental,

    /// Not added, and an intermediary MAY add it when it re-encodes.
    WithoutIndexing,

    /// Not added, and an intermediary MUST NOT add it either.
    NeverIndexed,
}

// ------------------------------------------------------------ static table

/// The name of static entry `index`, from 1 to 61.
internal String GetHpackStaticName(nuint index)
{
    switch (index)
    {
        case 1u: return ":authority";
        case 2u: return ":method";
        case 3u: return ":method";
        case 4u: return ":path";
        case 5u: return ":path";
        case 6u: return ":scheme";
        case 7u: return ":scheme";
        case 8u: return ":status";
        case 9u: return ":status";
        case 10u: return ":status";
        case 11u: return ":status";
        case 12u: return ":status";
        case 13u: return ":status";
        case 14u: return ":status";
        case 15u: return "accept-charset";
        case 16u: return "accept-encoding";
        case 17u: return "accept-language";
        case 18u: return "accept-ranges";
        case 19u: return "accept";
        case 20u: return "access-control-allow-origin";
        case 21u: return "age";
        case 22u: return "allow";
        case 23u: return "authorization";
        case 24u: return "cache-control";
        case 25u: return "content-disposition";
        case 26u: return "content-encoding";
        case 27u: return "content-language";
        case 28u: return "content-length";
        case 29u: return "content-location";
        case 30u: return "content-range";
        case 31u: return "content-type";
        case 32u: return "cookie";
        case 33u: return "date";
        case 34u: return "etag";
        case 35u: return "expect";
        case 36u: return "expires";
        case 37u: return "from";
        case 38u: return "host";
        case 39u: return "if-match";
        case 40u: return "if-modified-since";
        case 41u: return "if-none-match";
        case 42u: return "if-range";
        case 43u: return "if-unmodified-since";
        case 44u: return "last-modified";
        case 45u: return "link";
        case 46u: return "location";
        case 47u: return "max-forwards";
        case 48u: return "proxy-authenticate";
        case 49u: return "proxy-authorization";
        case 50u: return "range";
        case 51u: return "referer";
        case 52u: return "refresh";
        case 53u: return "retry-after";
        case 54u: return "server";
        case 55u: return "set-cookie";
        case 56u: return "strict-transport-security";
        case 57u: return "transfer-encoding";
        case 58u: return "user-agent";
        case 59u: return "vary";
        case 60u: return "via";
        case 61u: return "www-authenticate";
    }
    return "";
}

/// The value of static entry `index`: empty for all but fifteen.
internal String GetHpackStaticValue(nuint index)
{
    switch (index)
    {
        case 2u: return "GET";
        case 3u: return "POST";
        case 4u: return "/";
        case 5u: return "/index.html";
        case 6u: return "http";
        case 7u: return "https";
        case 8u: return "200";
        case 9u: return "204";
        case 10u: return "206";
        case 11u: return "304";
        case 12u: return "400";
        case 13u: return "404";
        case 14u: return "500";
        case 16u: return "gzip, deflate";
    }
    return "";
}

/// The first static entry named `name`, or zero.
internal nuint FindHpackStaticName(String name)
{
    switch (name)
    {
        case ":authority": return 1u;
        case ":method": return 2u;
        case ":path": return 4u;
        case ":scheme": return 6u;
        case ":status": return 8u;
        case "accept-charset": return 15u;
        case "accept-encoding": return 16u;
        case "accept-language": return 17u;
        case "accept-ranges": return 18u;
        case "accept": return 19u;
        case "access-control-allow-origin": return 20u;
        case "age": return 21u;
        case "allow": return 22u;
        case "authorization": return 23u;
        case "cache-control": return 24u;
        case "content-disposition": return 25u;
        case "content-encoding": return 26u;
        case "content-language": return 27u;
        case "content-length": return 28u;
        case "content-location": return 29u;
        case "content-range": return 30u;
        case "content-type": return 31u;
        case "cookie": return 32u;
        case "date": return 33u;
        case "etag": return 34u;
        case "expect": return 35u;
        case "expires": return 36u;
        case "from": return 37u;
        case "host": return 38u;
        case "if-match": return 39u;
        case "if-modified-since": return 40u;
        case "if-none-match": return 41u;
        case "if-range": return 42u;
        case "if-unmodified-since": return 43u;
        case "last-modified": return 44u;
        case "link": return 45u;
        case "location": return 46u;
        case "max-forwards": return 47u;
        case "proxy-authenticate": return 48u;
        case "proxy-authorization": return 49u;
        case "range": return 50u;
        case "referer": return 51u;
        case "refresh": return 52u;
        case "retry-after": return 53u;
        case "server": return 54u;
        case "set-cookie": return 55u;
        case "strict-transport-security": return 56u;
        case "transfer-encoding": return 57u;
        case "user-agent": return 58u;
        case "vary": return 59u;
        case "via": return 60u;
        case "www-authenticate": return 61u;
    }
    return 0u;
}

/// The static entry that is exactly `name: value`, or zero.
internal nuint FindHpackStaticField(String name, String value)
{
    nuint first = FindHpackStaticName(name);
    if (first == 0u)
        return 0u;
    for (nuint index = first; index <= HpackStaticTableLength; index++)
    {
        if (GetHpackStaticName(index) != name)
            return 0u;
        if (GetHpackStaticValue(index) == value)
            return index;
    }
    return 0u;
}

// ----------------------------------------------------------- dynamic table

/// The dynamic table: newest entry first, evicted from the oldest end as
/// it outgrows its size (RFC 7541 §4).
internal sealed class HpackDynamicTable
{
    private List<HpackField> _entries = new List<HpackField>();
    private nuint _size = 0u;
    private nuint _maxSize;

    internal HpackDynamicTable(nuint maxSize) => _maxSize = maxSize;

    internal nuint Count => _entries.Count;

    /// The sum of the entries' sizes.
    internal nuint Size => _size;

    internal nuint MaxSize => _maxSize;

    /// Entry `index`, counting the newest as 1.
    internal HpackField GetHpackEntry(nuint index) => _entries[index - 1u];

    /// Changes the size limit, evicting what no longer fits.
    internal void ResizeHpackTable(nuint maxSize)
    {
        _maxSize = maxSize;
        EvictHpackEntries(0u);
    }

    /// Adds `field` as the newest entry. One larger than the whole table
    /// empties it and is not added (RFC 7541 §4.4).
    internal void AddHpackEntry(HpackField field)
    {
        nuint size = field.Size;
        if (size > _maxSize)
        {
            _entries.Clear();
            _size = 0u;
            return;
        }
        EvictHpackEntries(size);
        _entries.Insert(0u, field);
        _size += size;
    }

    /// The newest entry that is exactly `name: value`, counting from 1, or
    /// zero.
    internal nuint FindHpackEntry(String name, String value)
    {
        for (nuint i = 0u; i < _entries.Count; i++)
        {
            HpackField entry = _entries[i];
            if (entry.Name == name && entry.Value == value)
                return i + 1u;
        }
        return 0u;
    }

    /// The newest entry named `name`, counting from 1, or zero.
    internal nuint FindHpackEntryName(String name)
    {
        for (nuint i = 0u; i < _entries.Count; i++)
        {
            if (_entries[i].Name == name)
                return i + 1u;
        }
        return 0u;
    }

    private void EvictHpackEntries(nuint room)
    {
        while (_entries.Count > 0u && _size + room > _maxSize)
        {
            nuint last = _entries.Count - 1u;
            _size -= _entries[last].Size;
            _entries.RemoveAt(last);
        }
    }
}

// ------------------------------------------------------ primitive encoding

/// Appends `value` as an integer with an `prefixBits`-bit prefix, the bits
/// above the prefix in the first octet being `flags` (RFC 7541 §5.1).
internal void WriteHpackInteger(Http2Buffer output, uint flags, uint prefixBits, ulong value)
{
    ulong limit = ((ulong)1u << prefixBits) - 1u;
    if (value < limit)
    {
        output.WriteByte(flags | (uint)value);
        return;
    }
    output.WriteByte(flags | (uint)limit);
    ulong rest = value - limit;
    while (rest >= 128u)
    {
        output.WriteByte((uint)(rest & 0x7Fu) | 0x80u);
        rest >>= 7;
    }
    output.WriteByte((uint)rest);
}

/// Appends a string literal, Huffman-coded when `huffman` and that is
/// shorter (RFC 7541 §5.2).
internal void WriteHpackString(Http2Buffer output, String text, bool huffman)
{
    nuint length = text.ByteLength();
    if (huffman)
    {
        nuint coded = MeasureHpackHuffman(text);
        if (coded <= length && length > 0u)
        {
            WriteHpackInteger(output, 0x80u, 7u, (ulong)coded);
            EncodeHpackHuffman(text, output);
            return;
        }
    }
    WriteHpackInteger(output, 0u, 7u, (ulong)length);
    output.WriteText(text);
}
