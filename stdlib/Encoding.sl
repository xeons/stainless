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
/// encodings come from functions -- `Encoding.Utf8()` -- and a program may add
/// one of its own by implementing `IEncoding`.
///
/// Both directions are lossy by default and say so, which is the same rule the
/// language already applies to `ToUtf16` and `Text.FromUtf16`: what cannot be
/// decoded becomes U+FFFD, and what cannot be encoded becomes `?`. `TryGetString`
/// is the strict form for a caller that needs to know rather than to cope, and
/// `CanRepresent` answers the other direction before anything is written.
module Standard.Encoding;

import Standard.Text;

/// Why a decode failed, when a caller asked to be told.
public enum EncodingError
{
    /// The bytes ended in the middle of a character.
    Incomplete,

    /// A byte or a sequence that this encoding cannot produce.
    Invalid,
}

/// One way of writing text as bytes.
///
/// Implement it to add an encoding; nothing here is closed. The two `Get`
/// methods are lossy and total, the `Try` one is strict, and `CanRepresent`
/// asks the encode direction the question `TryGetString` asks of the other.
public interface IEncoding
{
    /// The name IANA gives it, which is also what an HTTP header would carry.
    String Name { get; }

    /// The bytes that mark this encoding at the start of a file, if any.
    byte[] Preamble { get; }

    /// How many bytes `GetBytes` would produce. Costs a pass, saves an
    /// allocation.
    nuint GetByteCount(String text);

    /// `text` in this encoding. A scalar the encoding cannot write becomes
    /// `?`, which is what .NET's default fallback does and what the caller
    /// almost always wants when the alternative is failing a whole file.
    byte[] GetBytes(String text);

    /// `bytes` read as this encoding. Anything malformed becomes U+FFFD, so
    /// the result is always valid UTF-8 -- which it must be, because it is a
    /// `String`.
    String GetString(byte[] bytes);

    /// The same, but saying what went wrong instead of papering over it.
    Result<String, EncodingError> TryGetString(byte[] bytes);

    /// Whether this encoding can write that scalar at all.
    bool CanRepresent(char32 scalar);

    /// A converter that remembers what a buffer ended in the middle of.
    ///
    /// `GetString` takes whole text and cannot help a caller reading a stream
    /// in pieces, because a character may straddle two of them. This is .NET's
    /// `Encoding.GetDecoder`, and it exists for exactly that: the decoder holds
    /// the trailing bytes of an unfinished character and finishes it when the
    /// next piece arrives.
    IDecoder GetDecoder();
}

/// A decode in progress, across as many pieces as the bytes arrive in.
///
/// .NET's `Decoder`, narrowed to what this language needs: it answers with a
/// `String` rather than filling a `char` buffer, so there is no count to ask
/// for first and no `GetCharCount` beside it.
///
/// An encoder has no counterpart here. .NET needs one because a caller can
/// write half a surrogate pair; a caller here writes a `String`, which is
/// whole by construction, so there is never anything for a writer to hold.
public interface IDecoder
{
    /// The text that `count` bytes from `index` complete, with any unfinished
    /// character at the end kept back for the next call.
    ///
    /// `flush` says no more bytes are coming, so anything still held is
    /// malformed and becomes U+FFFD rather than waiting for the rest.
    String GetString(byte[] bytes, nuint index, nuint count, bool flush);

    /// Forgets what is held, for a decoder being pointed at something new.
    void Reset();
}

// ------------------------------------------------------------------ decoding

/// What every decoder does except decide where a character was cut.
///
/// The held bytes and the new ones are joined, everything complete is handed
/// to the encoding it belongs to, and the remainder is kept. Only
/// `IncompleteTail` differs between encodings, and it is the one thing that
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
    protected abstract nuint IncompleteTail(byte[] data, nuint length);

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
        nuint tail = flush ? 0u : this.IncompleteTail(joined, total);
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

    protected override nuint IncompleteTail(byte[] data, nuint length)
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

    protected override nuint IncompleteTail(byte[] data, nuint length)
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

    protected override nuint IncompleteTail(byte[] data, nuint length) => length % 4u;
}

// ------------------------------------------------------------------ choosing

/// UTF-8: what a `String` already is, so both directions are a copy.
public IEncoding Utf8() => new Utf8Encoding();

/// UTF-16, little-endian -- the one Windows means by "Unicode".
public IEncoding Utf16() => new Utf16Encoding(false);

/// UTF-16, big-endian.
public IEncoding Utf16BigEndian() => new Utf16Encoding(true);

/// UTF-32, little-endian: one scalar per four bytes, no surrogates.
public IEncoding Utf32() => new Utf32Encoding(false);

/// UTF-32, big-endian.
public IEncoding Utf32BigEndian() => new Utf32Encoding(true);

/// US-ASCII: seven bits, and nothing above them.
public IEncoding Ascii() => new AsciiEncoding();

/// ISO-8859-1, in which every byte is the code point of the same number. That
/// makes it the one encoding that can carry any byte sequence without failing,
/// which is why it is what a protocol reaches for when it does not know.
public IEncoding Latin1() => new Latin1Encoding();

/// Windows-1252: Latin-1 with the C1 control range replaced by punctuation --
/// curly quotes, the dash, the euro. Most text labelled ISO-8859-1 is really
/// this, because that is what a Windows editor wrote.
public IEncoding Windows1252() => new Windows1252Encoding();

/// Which encoding a byte order mark says this is, or null when there is none.
///
/// UTF-32LE is tested before UTF-16LE deliberately: a UTF-32LE mark begins with
/// the two bytes of a UTF-16LE one, so the longer test has to come first or
/// every UTF-32 file reads as UTF-16 whose first character is NUL.
public IEncoding? Detect(byte[] bytes)
{
    if (StartsWith(bytes, [0xFF, 0xFE, 0x00, 0x00]))
        return Utf32();
    if (StartsWith(bytes, [0x00, 0x00, 0xFE, 0xFF]))
        return Utf32BigEndian();
    if (StartsWith(bytes, [0xEF, 0xBB, 0xBF]))
        return Utf8();
    if (StartsWith(bytes, [0xFF, 0xFE]))
        return Utf16();
    if (StartsWith(bytes, [0xFE, 0xFF]))
        return Utf16BigEndian();
    return null;
}

/// `bytes` without the byte order mark `encoding` writes, if it is there.
public byte[] WithoutPreamble(IEncoding encoding, byte[] bytes)
{
    var mark = encoding.Preamble;
    if (mark.Length == 0 || !StartsWith(bytes, mark))
        return bytes;
    return Tail(bytes, mark.Length);
}

// -------------------------------------------------------------------- UTF-8

/// UTF-8, which is what a `String` already holds.
///
/// Both directions are a copy rather than a transcode. `GetString` still has to
/// validate, because a `byte[]` from outside the program is not a `String` and
/// has promised nothing.
public class Utf8Encoding : IEncoding
{
    /// `"utf-8"`.
    public String Name => "utf-8";

    /// EF BB BF. UTF-8 needs no byte order mark -- there is only one order --
    /// so this is what to *recognise*, not what to write by habit.
    public byte[] Preamble => [0xEF, 0xBB, 0xBF];

    /// The length the text already has. O(1), since no transcode is needed.
    public nuint GetByteCount(String text) => text.ByteLength();

    /// The text's own bytes. A copy, not a transcode.
    public byte[] GetBytes(String text) => text.ToBytes();

    /// Every scalar; that is what UTF-8 is for.
    public bool CanRepresent(char32 scalar) => true;

    /// A decoder that holds the first bytes of a sequence whose rest has
    /// not arrived.
    public IDecoder GetDecoder() => new Utf8Decoder(this);

    /// `bytes` validated, with each malformed byte replaced by U+FFFD.
    ///
    /// One replacement per bad byte rather than per bad sequence, so a run of
    /// rubbish is as many U+FFFDs as it is bytes.
    public String GetString(byte[] bytes)
    {
        var built = new StringBuilder();
        nuint at = 0;

        while (at < bytes.Length)
        {
            nuint width = Utf8Width(bytes[at]);

            if (width == 0 || at + width > bytes.Length || !Continues(bytes, at, width))
            {
                built.AppendCodePoint((char32)0xFFFD);
                at++;
                continue;
            }

            built.AppendCodePoint(Utf8Scalar(bytes, at, width));
            at = at + width;
        }
        return built.ToText();
    }

    /// The strict decode: `Invalid` for anything that is not a scalar, and
    /// `Incomplete` for a sequence the input ran out during.
    ///
    /// Stricter than `GetString`, and deliberately: an overlong sequence, a
    /// surrogate and a value past U+10FFFF are each refused, because each is a
    /// way of spelling something that is not a character and each has been a
    /// security hole in a decoder that accepted it.
    public Result<String, EncodingError> TryGetString(byte[] bytes)
    {
        nuint at = 0;

        while (at < bytes.Length)
        {
            nuint width = Utf8Width(bytes[at]);
            if (width == 0)
                return Fail(EncodingError.Invalid);
            if (at + width > bytes.Length)
                return Fail(EncodingError.Incomplete);
            if (!Continues(bytes, at, width))
                return Fail(EncodingError.Invalid);

            // An overlong sequence, a surrogate or a value past U+10FFFF are
            // each a different way of spelling something that is not a scalar,
            // and a strict decoder refuses all three.
            uint scalar = (uint)Utf8Scalar(bytes, at, width);
            if (Overlong(scalar, width))
                return Fail(EncodingError.Invalid);
            if (scalar > 0x10FFFF)
                return Fail(EncodingError.Invalid);
            if (scalar >= 0xD800 && scalar <= 0xDFFF)
                return Fail(EncodingError.Invalid);

            at = at + width;
        }
        return Ok(GetString(bytes));
    }
}

// ------------------------------------------------------------------- UTF-16

/// UTF-16, in either byte order.
public class Utf16Encoding : IEncoding
{
    bool _bigEndian;

    /// A UTF-16 encoding, big-endian when `big`. `Utf16()` and
    /// `Utf16BigEndian()` are the names to reach for.
    public Utf16Encoding(bool big) => _bigEndian = big;

    /// `"utf-16be"` or `"utf-16le"`, whichever this is.
    public String Name => _bigEndian ? "utf-16be" : "utf-16le";
    // Written as an if rather than a ternary: an array literal takes its type
    // from where it is going, and a ternary arm is not somewhere that says.
    /// FE FF big-endian, FF FE little. Worth writing here, unlike UTF-8's:
    /// without it there is no way to tell the two orders apart.
    public byte[] Preamble
    {
        get
        {
            if (_bigEndian)
                return [0xFE, 0xFF];
            return [0xFF, 0xFE];
        }
    }

    /// Every scalar, in one unit or two.
    public bool CanRepresent(char32 scalar) => true;

    /// A decoder that holds an odd byte, and a high surrogate waiting for
    /// its low one.
    public IDecoder GetDecoder() => new Utf16Decoder(this, _bigEndian);

    /// Two bytes per unit, so four for a scalar outside the basic plane.
    /// Costs a transcode to count, which is what `GetBytes` then does again.
    public nuint GetByteCount(String text) => text.ToUtf16().UnitCount() * 2;

    /// The text as UTF-16 in this byte order, with no byte order mark --
    /// prepend `Preamble` if the reader will need one.
    public byte[] GetBytes(String text)
    {
        var wide = text.ToUtf16();
        nuint count = wide.UnitCount();
        var bytes = new byte[count * 2];

        for (nuint i = 0; i < count; i++)
        {
            uint unit = (uint)wide.UnitAt(i);
            if (_bigEndian)
            {
                bytes[i * 2] = (byte)(unit >> 8);
                bytes[i * 2 + 1] = (byte)(unit & 0xFF);
            }
            else
            {
                bytes[i * 2] = (byte)(unit & 0xFF);
                bytes[i * 2 + 1] = (byte)(unit >> 8);
            }
        }
        return bytes;
    }

    /// `bytes` read as UTF-16, with an unpaired surrogate or a trailing odd
    /// byte becoming U+FFFD. A byte order mark, if present, is not stripped --
    /// `WithoutPreamble` is what does that.
    public String GetString(byte[] bytes)
    {
        var built = new StringBuilder();
        nuint at = 0;

        // A trailing odd byte is half a unit and cannot be anything.
        while (at + 1 < bytes.Length)
        {
            uint first = this.UnitAt(bytes, at);
            at = at + 2;

            if (first < 0xD800 || first > 0xDFFF)
            {
                built.AppendCodePoint((char32)first);
                continue;
            }

            if (first > 0xDBFF || at + 1 >= bytes.Length)
            {
                built.AppendCodePoint((char32)0xFFFD);
                continue;
            }

            uint second = this.UnitAt(bytes, at);
            if (second < 0xDC00 || second > 0xDFFF)
            {
                built.AppendCodePoint((char32)0xFFFD);
                continue;
            }

            at = at + 2;
            built.AppendCodePoint((char32)(0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)));
        }

        if (at < bytes.Length)
            built.AppendCodePoint((char32)0xFFFD);
        return built.ToText();
    }

    /// The strict decode: `Incomplete` for an odd number of bytes or a high
    /// surrogate at the end, `Invalid` for a surrogate that is not paired.
    public Result<String, EncodingError> TryGetString(byte[] bytes)
    {
        if (bytes.Length % 2 != 0)
            return Fail(EncodingError.Incomplete);

        nuint at = 0;
        while (at < bytes.Length)
        {
            uint first = this.UnitAt(bytes, at);
            at = at + 2;

            if (first < 0xD800 || first > 0xDFFF)
                continue;
            if (first > 0xDBFF)
                return Fail(EncodingError.Invalid);
            if (at >= bytes.Length)
                return Fail(EncodingError.Incomplete);

            uint second = this.UnitAt(bytes, at);
            if (second < 0xDC00 || second > 0xDFFF)
                return Fail(EncodingError.Invalid);
            at = at + 2;
        }
        return Ok(GetString(bytes));
    }

    uint UnitAt(byte[] bytes, nuint at)
    {
        if (_bigEndian)
            return ((uint)bytes[at] << 8) | (uint)bytes[at + 1];
        return (uint)bytes[at] | ((uint)bytes[at + 1] << 8);
    }
}

// ------------------------------------------------------------------- UTF-32

/// UTF-32: one scalar per four bytes, and no surrogates anywhere.
public class Utf32Encoding : IEncoding
{
    bool _bigEndian;

    /// A UTF-32 encoding, big-endian when `big`. `Utf32()` and
    /// `Utf32BigEndian()` are the names to reach for.
    public Utf32Encoding(bool big) => _bigEndian = big;

    /// `"utf-32be"` or `"utf-32le"`, whichever this is.
    public String Name => _bigEndian ? "utf-32be" : "utf-32le";

    /// Four bytes, and the little-endian one begins with UTF-16LE's -- which
    /// is why `Detect` tests UTF-32 first.
    public byte[] Preamble
    {
        get
        {
            if (_bigEndian)
                return [0x00, 0x00, 0xFE, 0xFF];
            return [0xFF, 0xFE, 0x00, 0x00];
        }
    }

    /// Every scalar, in exactly four bytes.
    public bool CanRepresent(char32 scalar) => true;

    /// A decoder that holds whatever is left of a four-byte group.
    public IDecoder GetDecoder() => new Utf32Decoder(this);

    /// Four bytes per scalar. Costs a pass to count the scalars.
    public nuint GetByteCount(String text) => text.CodePointCount() * 4;

    /// The text as UTF-32 in this byte order, with no byte order mark.
    public byte[] GetBytes(String text)
    {
        var bytes = new byte[text.CodePointCount() * 4];
        nuint out = 0;

        for (nuint at = 0; at < text.ByteLength(); at = text.NextCodePoint(at))
        {
            uint scalar = (uint)text.CodePointAt(at);
            if (_bigEndian)
            {
                bytes[out] = (byte)(scalar >> 24);
                bytes[out + 1] = (byte)((scalar >> 16) & 0xFF);
                bytes[out + 2] = (byte)((scalar >> 8) & 0xFF);
                bytes[out + 3] = (byte)(scalar & 0xFF);
            }
            else
            {
                bytes[out] = (byte)(scalar & 0xFF);
                bytes[out + 1] = (byte)((scalar >> 8) & 0xFF);
                bytes[out + 2] = (byte)((scalar >> 16) & 0xFF);
                bytes[out + 3] = (byte)(scalar >> 24);
            }
            out = out + 4;
        }
        return bytes;
    }

    /// `bytes` read as UTF-32, with a value that is not a scalar -- a
    /// surrogate, or anything past U+10FFFF -- becoming U+FFFD. Trailing bytes
    /// that do not make a whole four are dropped.
    public String GetString(byte[] bytes)
    {
        var built = new StringBuilder();

        nuint at = 0;
        while (at + 3 < bytes.Length)
        {
            built.AppendCodePoint((char32)this.ScalarAt(bytes, at));
            at = at + 4;
        }

        if (at < bytes.Length)
            built.AppendCodePoint((char32)0xFFFD);
        return built.ToText();
    }

    /// The strict decode: `Incomplete` when the length is not a multiple of
    /// four, `Invalid` for a value that is not a scalar.
    public Result<String, EncodingError> TryGetString(byte[] bytes)
    {
        if (bytes.Length % 4 != 0)
            return Fail(EncodingError.Incomplete);

        nuint at = 0;
        while (at < bytes.Length)
        {
            uint scalar = this.ScalarAt(bytes, at);
            if (scalar > 0x10FFFF)
                return Fail(EncodingError.Invalid);
            if (scalar >= 0xD800 && scalar <= 0xDFFF)
                return Fail(EncodingError.Invalid);
            at = at + 4;
        }
        return Ok(GetString(bytes));
    }

    uint ScalarAt(byte[] bytes, nuint at)
    {
        if (_bigEndian)
        {
            return ((uint)bytes[at] << 24) | ((uint)bytes[at + 1] << 16)
                 | ((uint)bytes[at + 2] << 8) | (uint)bytes[at + 3];
        }
        return (uint)bytes[at] | ((uint)bytes[at + 1] << 8)
             | ((uint)bytes[at + 2] << 16) | ((uint)bytes[at + 3] << 24);
    }
}

// ------------------------------------------------------- one byte, one scalar

/// An encoding in which every byte is exactly one character.
///
/// Decoding one of these cannot fail: there is no sequence to run out of and no
/// byte that means nothing, only a table with 256 entries. Encoding can, since
/// most of Unicode is not in that table, and what cannot be written becomes
/// `?`.
///
/// A base class rather than three copies, because the three differ only in the
/// table -- and the two that matter differ only in the 32 entries between 0x80
/// and 0x9F.
public abstract class SingleByteEncoding : IEncoding
{
    /// What this byte means. Every byte means something.
    public abstract char32 ToScalar(byte value);

    /// Which byte writes this scalar, or -1 when none does.
    public abstract int FromScalar(char32 scalar);

    /// The IANA name, which each subclass supplies.
    public abstract String Name { get; }

    /// None of these has one: a byte order mark is a Unicode idea.
    public byte[] Preamble => [];

    /// Whether the table has a byte for that scalar. Most of Unicode is not in
    /// any of these tables, so this is false far more often than it is true.
    public bool CanRepresent(char32 scalar) => this.FromScalar(scalar) >= 0;

    /// One byte is one character here, so a decoder has nothing to hold.
    public IDecoder GetDecoder() => new WholeDecoder(this);

    /// One byte per scalar, always -- so the count is the scalar count, not
    /// the text's byte length.
    public nuint GetByteCount(String text) => text.CodePointCount();

    /// The text in this encoding, with anything the table cannot write
    /// becoming `?`. Check `CanRepresent` first where losing it matters.
    public byte[] GetBytes(String text)
    {
        var bytes = new byte[text.CodePointCount()];
        nuint out = 0;

        for (nuint at = 0; at < text.ByteLength(); at = text.NextCodePoint(at))
        {
            int written = this.FromScalar(text.CodePointAt(at));
            bytes[out] = written < 0 ? (byte)63 : (byte)written;      // '?'
            out++;
        }
        return bytes;
    }

    /// `bytes` through the table, one character per byte. Cannot fail: every
    /// byte means something, even if that something is U+FFFD.
    public String GetString(byte[] bytes)
    {
        var built = new StringBuilder();
        for (nuint i = 0; i < bytes.Length; i++)
        {
            built.AppendCodePoint(this.ToScalar(bytes[i]));
        }
        return built.ToText();
    }

    /// Never fails, which is the whole character of a single-byte encoding.
    public Result<String, EncodingError> TryGetString(byte[] bytes)
    {
        return Ok(this.GetString(bytes));
    }
}

/// US-ASCII. A byte above 127 is not ASCII, and reads as U+FFFD.
public class AsciiEncoding : SingleByteEncoding
{
    /// `"us-ascii"`.
    public override String Name => "us-ascii";

    /// The byte itself below 128, and U+FFFD at or above it.
    public override char32 ToScalar(byte value)
    {
        return value < 128 ? (char32)(uint)value : (char32)0xFFFD;
    }

    /// The scalar itself below U+0080, and -1 at or above it.
    public override int FromScalar(char32 scalar)
    {
        uint value = (uint)scalar;
        return value < 128 ? (int)value : -1;
    }
}

/// ISO-8859-1, where byte n is code point n for every n. Nothing can fail in
/// either direction below U+0100, and nothing above it can be written.
public class Latin1Encoding : SingleByteEncoding
{
    /// `"iso-8859-1"`.
    public override String Name => "iso-8859-1";

    /// Byte n is code point n, for every n. Never U+FFFD, which is what makes
    /// this encoding able to carry any byte sequence at all.
    public override char32 ToScalar(byte value) => (char32)(uint)value;

    /// The scalar itself below U+0100, and -1 at or above it.
    public override int FromScalar(char32 scalar)
    {
        uint value = (uint)scalar;
        return value < 256 ? (int)value : -1;
    }
}

/// Windows-1252: Latin-1, except that 0x80 to 0x9F carry punctuation rather
/// than C1 controls. Five of those 32 positions are unassigned and read as
/// U+FFFD.
public class Windows1252Encoding : SingleByteEncoding
{
    /// `"windows-1252"`.
    public override String Name => "windows-1252";

    /// Latin-1 outside 0x80 to 0x9F, and the punctuation table inside it.
    /// Five of those 32 positions are unassigned and read as U+FFFD.
    public override char32 ToScalar(byte value)
    {
        if (value < 0x80 || value > 0x9F)
            return (char32)(uint)value;
        return (char32)Cp1252High((nuint)(value - 0x80));
    }

    /// The Latin-1 byte where there is one, else a scan of the 32-entry
    /// punctuation table, else -1.
    public override int FromScalar(char32 scalar)
    {
        uint value = (uint)scalar;
        if (value < 0x80 || (value >= 0xA0 && value < 0x100))
            return (int)value;

        for (nuint i = 0; i < 32; i++)
        {
            if (Cp1252High(i) == value)
                return (int)(0x80 + i);
        }
        return -1;
    }
}

/// What Windows-1252 puts at 0x80 + `index`. 0xFFFD marks the five that are
/// not assigned at all.
uint Cp1252High(nuint index)
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
nuint Utf8Width(byte lead)
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
bool Continues(byte[] bytes, nuint at, nuint width)
{
    for (nuint i = 1; i < width; i++)
    {
        if ((bytes[at + i] & 0xC0) != 0x80)
            return false;
    }
    return true;
}

/// The scalar a validated sequence spells.
char32 Utf8Scalar(byte[] bytes, nuint at, nuint width)
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
bool Overlong(uint scalar, nuint width)
{
    if (width == 2)
        return scalar < 0x80;
    if (width == 3)
        return scalar < 0x800;
    if (width == 4)
        return scalar < 0x10000;
    return false;
}

// -------------------------------------------------------------------- arrays

/// Whether `bytes` begins with `prefix`.
bool StartsWith(byte[] bytes, byte[] prefix)
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
byte[] Tail(byte[] bytes, nuint at)
{
    if (at >= bytes.Length)
        return [];

    var rest = new byte[bytes.Length - at];
    for (nuint i = 0; i < rest.Length; i++)
        rest[i] = bytes[at + i];
    return rest;
}
