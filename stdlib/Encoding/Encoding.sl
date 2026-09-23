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

/// Text as bytes, in whichever encoding somebody else chose.
///
/// A `String` is UTF-8 and there is deliberately no second string type (§3).
/// That settles what text *is* inside a program and says nothing about what
/// arrives from outside it -- a file written by a Windows editor, a protocol
/// header that predates Unicode, a registry value in UTF-16. This module is the
/// crossing, and every crossing is explicit.
///
/// The shape is .NET's, adapted to what this language has: an interface rather
/// than an abstract class with static instances, because a static needs a
/// Sendable type and an initializer that `--shared` has nowhere to run. So the
/// encodings come from functions -- `Encoding.CreateUtf8()` -- and a program may add
/// one of its own by implementing `IEncoding`.
///
/// Both directions are lossy by default and say so, which is the same rule the
/// language already applies to `ToUtf16` and `Text.FromUtf16`: what cannot be
/// decoded becomes U+FFFD, and what cannot be encoded becomes `?`. `TryGetString`
/// is the strict form for a caller that needs to know rather than to cope, and
/// `CanRepresent` answers the other direction before anything is written.
module Standard.Encoding;

import Standard.Text;

// ------------------------------------------------------------------ decoding

/// What every decoder does except decide where a character was cut.
///
/// The held bytes and the new ones are joined, everything complete is handed
/// to the encoding it belongs to, and the remainder is kept. Only
/// `CountIncompleteTail` differs between encodings, and it is the one thing that
/// needs to know how the encoding is shaped.
abstract class TailDecoder : IDecoder
{
    IEncoding _encoding;

    /// Four bytes is the longest unfinished character any encoding here has:
    /// three of a UTF-8 sequence, or an odd byte and a high surrogate.
    byte[] _held;
    nuint _heldCount;

    protected TailDecoder(IEncoding encoding)
    {
        _encoding = encoding;
        _held = new byte[4];
        _heldCount = 0u;
    }

    /// How many bytes at the end begin a character that is not finished.
    protected abstract nuint CountIncompleteTail(byte[] data, nuint length);

    public String GetString(byte[] bytes, nuint index, nuint count, bool flush)
    {
        nuint total = _heldCount + count;
        if (total == 0u)
            return "";

        var joined = new byte[total];
        for (nuint i = 0u; i < _heldCount; i++)
            joined[i] = _held[i];
        for (nuint i = 0u; i < count; i++)
            joined[_heldCount + i] = bytes[index + i];

        // Nothing is held back on a flush: what is unfinished then is never
        // going to be finished, and the encoding turns it into U+FFFD.
        nuint tail = flush ? 0u : this.CountIncompleteTail(joined, total);
        if (tail > 4u)
            tail = 4u;

        nuint usable = total - tail;

        _heldCount = tail;
        for (nuint i = 0u; i < tail; i++)
            _held[i] = joined[usable + i];

        if (usable == 0u)
            return "";

        var ready = new byte[usable];
        for (nuint i = 0u; i < usable; i++)
            ready[i] = joined[i];

        return _encoding.GetString(ready);
    }

    public void Reset()
    {
        _heldCount = 0u;
    }
}

/// For an encoding where one byte is one character, so nothing is ever cut.
class WholeDecoder : IDecoder
{
    IEncoding _encoding;

    public WholeDecoder(IEncoding encoding) => _encoding = encoding;

    public String GetString(byte[] bytes, nuint index, nuint count, bool flush)
    {
        if (count == 0u)
            return "";

        var ready = new byte[count];
        for (nuint i = 0u; i < count; i++)
            ready[i] = bytes[index + i];
        return _encoding.GetString(ready);
    }

    public void Reset() { }
}

/// UTF-8, where a lead byte says how many follow it.
class Utf8Decoder : TailDecoder
{
    public Utf8Decoder(IEncoding encoding) { base(encoding); }

    protected override nuint CountIncompleteTail(byte[] data, nuint length)
    {
        // A sequence is at most four bytes, so a lead byte further back than
        // that cannot be waiting on anything here.
        nuint back = length < 4u ? length : 4u;

        for (nuint i = 1u; i <= back; i++)
        {
            byte lead = data[length - i];
            if ((lead & 0xC0) == 0x80)
                continue;

            nuint wanted = 1u;
            if ((lead & 0xE0) == 0xC0)
                wanted = 2u;
            else if ((lead & 0xF0) == 0xE0)
                wanted = 3u;
            else if ((lead & 0xF8) == 0xF0)
                wanted = 4u;

            return i < wanted ? i : 0u;
        }

        // Four continuation bytes and no lead: malformed rather than cut, and
        // the encoding says so better than holding them would.
        return 0u;
    }
}

/// UTF-16, where a unit is two bytes and a high surrogate wants a second unit.
class Utf16Decoder : TailDecoder
{
    bool _bigEndian;

    public Utf16Decoder(IEncoding encoding, bool big)
    {
        base(encoding);
        _bigEndian = big;
    }

    protected override nuint CountIncompleteTail(byte[] data, nuint length)
    {
        nuint odd = length % 2u;
        nuint whole = length - odd;

        if (whole >= 2u)
        {
            nuint at = whole - 2u;
            uint unit = _bigEndian
                ? ((uint)data[at] << 8) | (uint)data[at + 1u]
                : ((uint)data[at + 1u] << 8) | (uint)data[at];

            // A high surrogate is half a character until its low one arrives.
            if (unit >= 0xD800u && unit <= 0xDBFFu)
                return odd + 2u;
        }

        return odd;
    }
}

/// UTF-32, where every character is four bytes and nothing else can be cut.
class Utf32Decoder : TailDecoder
{
    public Utf32Decoder(IEncoding encoding) { base(encoding); }

    protected override nuint CountIncompleteTail(byte[] data, nuint length) => length % 4u;
}

// ------------------------------------------------------------------ choosing

/// UTF-8: what a `String` already is, so both directions are a copy.
public IEncoding CreateUtf8() => new Utf8Encoding();

/// UTF-16, little-endian -- the one Windows means by "Unicode".
public IEncoding CreateUtf16() => new Utf16Encoding(false);

/// UTF-16, big-endian.
public IEncoding CreateUtf16BigEndian() => new Utf16Encoding(true);

/// UTF-32, little-endian: one scalar per four bytes, no surrogates.
public IEncoding CreateUtf32() => new Utf32Encoding(false);

/// UTF-32, big-endian.
public IEncoding CreateUtf32BigEndian() => new Utf32Encoding(true);

/// US-ASCII: seven bits, and nothing above them.
public IEncoding CreateAscii() => new AsciiEncoding();

/// ISO-8859-1, in which every byte is the code point of the same number. That
/// makes it the one encoding that can carry any byte sequence without failing,
/// which is why it is what a protocol reaches for when it does not know.
public IEncoding CreateLatin1() => new Latin1Encoding();

/// Windows-1252: Latin-1 with the C1 control range replaced by punctuation --
/// curly quotes, the dash, the euro. Most text labelled ISO-8859-1 is really
/// this, because that is what a Windows editor wrote.
public IEncoding CreateWindows1252() => new Windows1252Encoding();

/// Which encoding a byte order mark says this is, or null when there is none.
///
/// UTF-32LE is tested before UTF-16LE deliberately: a UTF-32LE mark begins with
/// the two bytes of a UTF-16LE one, so the longer test has to come first or
/// every UTF-32 file reads as UTF-16 whose first character is NUL.
///
/// @see Encoding.StripPreamble
public IEncoding? DetectEncoding(byte[] bytes)
{
    if (BytesStartWith(bytes, [0xFF, 0xFE, 0x00, 0x00]))
        return CreateUtf32();
    if (BytesStartWith(bytes, [0x00, 0x00, 0xFE, 0xFF]))
        return CreateUtf32BigEndian();
    if (BytesStartWith(bytes, [0xEF, 0xBB, 0xBF]))
        return CreateUtf8();
    if (BytesStartWith(bytes, [0xFF, 0xFE]))
        return CreateUtf16();
    if (BytesStartWith(bytes, [0xFE, 0xFF]))
        return CreateUtf16BigEndian();
    return null;
}

/// `bytes` without the byte order mark `encoding` writes, if it is there.
public byte[] StripPreamble(IEncoding encoding, byte[] bytes)
{
    var mark = encoding.Preamble;
    if (mark.Length == 0 || !BytesStartWith(bytes, mark))
        return bytes;
    return CopyBytesFrom(bytes, mark.Length);
}

/// What Windows-1252 puts at 0x80 + `index`. 0xFFFD marks the five that are
/// not assigned at all.
uint DecodeCp1252High(nuint index)
{
    uint[32] table = [
        0x20AC, 0xFFFD, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
        0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0xFFFD, 0x017D, 0xFFFD,
        0xFFFD, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
        0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0xFFFD, 0x017E, 0x0178,
    ];
    return table[index];
}

// ---------------------------------------------------------------- UTF-8 bits

/// How many bytes the sequence starting with this byte occupies, or 0 when it
/// cannot start one.
nuint GetUtf8Width(byte lead)
{
    if (lead < 0x80)
        return 1;
    if ((lead & 0xE0) == 0xC0)
        return 2;
    if ((lead & 0xF0) == 0xE0)
        return 3;
    if ((lead & 0xF8) == 0xF0)
        return 4;
    return 0;
}

/// Whether the bytes after the lead really are continuation bytes.
bool HasContinuationBytes(byte[] bytes, nuint at, nuint width)
{
    for (nuint i = 1; i < width; i++)
    {
        if ((bytes[at + i] & 0xC0) != 0x80)
            return false;
    }
    return true;
}

/// The scalar a validated sequence spells.
char32 DecodeUtf8Scalar(byte[] bytes, nuint at, nuint width)
{
    if (width == 1)
        return (char32)(uint)bytes[at];

    uint scalar = (uint)(bytes[at] & (byte)(0x7F >> (int)width));
    for (nuint i = 1; i < width; i++)
    {
        scalar = (scalar << 6) | (uint)(bytes[at + i] & 0x3F);
    }
    return (char32)scalar;
}

/// Whether a scalar was written in more bytes than it needed.
///
/// An overlong sequence decodes to the right number and is still refused,
/// because two spellings of one character is how a filter that checked the
/// bytes gets walked past.
bool IsOverlong(uint scalar, nuint width)
{
    if (width == 2)
        return scalar < 0x80;
    if (width == 3)
        return scalar < 0x800;
    if (width == 4)
        return scalar < 0x10000;
    return false;
}

/// Whether a decoded sequence is a scalar in its one legal spelling: not
/// overlong, not a surrogate and not past U+10FFFF.
bool IsScalarSpelledOnce(uint scalar, nuint width)
{
    if (IsOverlong(scalar, width) || scalar > 0x10FFFF)
        return false;
    return scalar < 0xD800 || scalar > 0xDFFF;
}

// -------------------------------------------------------------------- arrays

/// Whether `bytes` begins with `prefix`.
bool BytesStartWith(byte[] bytes, byte[] prefix)
{
    if (prefix.Length > bytes.Length)
        return false;
    for (nuint i = 0; i < prefix.Length; i++)
    {
        if (bytes[i] != prefix[i])
            return false;
    }
    return true;
}

/// `bytes` from `at` to the end.
byte[] CopyBytesFrom(byte[] bytes, nuint at)
{
    if (at >= bytes.Length)
        return [];

    var rest = new byte[bytes.Length - at];
    for (nuint i = 0; i < rest.Length; i++)
        rest[i] = bytes[at + i];
    return rest;
}
