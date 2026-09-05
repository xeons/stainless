// Stainless - an experimental systems language.
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

// Text as bytes, in whichever encoding somebody else chose.
//
// A `String` is UTF-8 and there is deliberately no second string type (§3).
// That settles what text *is* inside a program and says nothing about what
// arrives from outside it -- a file written by a Windows editor, a protocol
// header that predates Unicode, a registry value in UTF-16. This module is the
// crossing, and every crossing is explicit.
//
// The shape is .NET's, adapted to what this language has: an interface rather
// than an abstract class with static instances, because a static needs a
// Sendable type and an initializer that `--shared` has nowhere to run. So the
// encodings come from functions -- `Encoding.Utf8()` -- and a program may add
// one of its own by implementing `IEncoding`.
//
// Both directions are lossy by default and say so, which is the same rule the
// language already applies to `ToUtf16` and `Text.FromUtf16`: what cannot be
// decoded becomes U+FFFD, and what cannot be encoded becomes `?`. `TryGetString`
// is the strict form for a caller that needs to know rather than to cope, and
// `CanRepresent` answers the other direction before anything is written.
module Standard.Encoding;

import Standard.Text;

/// Why a decode failed, when a caller asked to be told.
public enum EncodingError {
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
public interface IEncoding {
    /// The name IANA gives it, which is also what an HTTP header would carry.
    String Name();

    /// The bytes that mark this encoding at the start of a file, if any.
    byte[] Preamble();

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
}

// ------------------------------------------------------------------ choosing

/// UTF-8: what a `String` already is, so both directions are a copy.
public IEncoding Utf8() { return new Utf8Encoding(); }

/// UTF-16, little-endian -- the one Windows means by "Unicode".
public IEncoding Utf16() { return new Utf16Encoding(false); }

/// UTF-16, big-endian.
public IEncoding Utf16BigEndian() { return new Utf16Encoding(true); }

/// UTF-32, little-endian: one scalar per four bytes, no surrogates.
public IEncoding Utf32() { return new Utf32Encoding(false); }

/// UTF-32, big-endian.
public IEncoding Utf32BigEndian() { return new Utf32Encoding(true); }

/// US-ASCII: seven bits, and nothing above them.
public IEncoding Ascii() { return new AsciiEncoding(); }

/// ISO-8859-1, in which every byte is the code point of the same number. That
/// makes it the one encoding that can carry any byte sequence without failing,
/// which is why it is what a protocol reaches for when it does not know.
public IEncoding Latin1() { return new Latin1Encoding(); }

/// Windows-1252: Latin-1 with the C1 control range replaced by punctuation --
/// curly quotes, the dash, the euro. Most text labelled ISO-8859-1 is really
/// this, because that is what a Windows editor wrote.
public IEncoding Windows1252() { return new Windows1252Encoding(); }

/// Which encoding a byte order mark says this is, or null when there is none.
///
/// UTF-32LE is tested before UTF-16LE deliberately: a UTF-32LE mark begins with
/// the two bytes of a UTF-16LE one, so the longer test has to come first or
/// every UTF-32 file reads as UTF-16 whose first character is NUL.
public IEncoding? Detect(byte[] bytes) {
    if (StartsWith(bytes, [0xFF, 0xFE, 0x00, 0x00])) { return Utf32(); }
    if (StartsWith(bytes, [0x00, 0x00, 0xFE, 0xFF])) { return Utf32BigEndian(); }
    if (StartsWith(bytes, [0xEF, 0xBB, 0xBF])) { return Utf8(); }
    if (StartsWith(bytes, [0xFF, 0xFE])) { return Utf16(); }
    if (StartsWith(bytes, [0xFE, 0xFF])) { return Utf16BigEndian(); }
    return null;
}

/// `bytes` without the byte order mark `encoding` writes, if it is there.
public byte[] WithoutPreamble(IEncoding encoding, byte[] bytes) {
    var mark = encoding.Preamble();
    if (mark.Length == 0 || !StartsWith(bytes, mark)) { return bytes; }
    return Tail(bytes, mark.Length);
}

// -------------------------------------------------------------------- UTF-8

/// UTF-8, which is what a `String` already holds.
///
/// Both directions are a copy rather than a transcode. `GetString` still has to
/// validate, because a `byte[]` from outside the program is not a `String` and
/// has promised nothing.
public class Utf8Encoding : IEncoding {
    public String Name() { return "utf-8"; }
    public byte[] Preamble() { return [0xEF, 0xBB, 0xBF]; }

    public nuint GetByteCount(String text) { return text.ByteLength(); }
    public byte[] GetBytes(String text) { return text.ToBytes(); }

    /// Every scalar; that is what UTF-8 is for.
    public bool CanRepresent(char32 scalar) { return true; }

    public String GetString(byte[] bytes) {
        var built = new StringBuilder();
        nuint at = 0;

        while (at < bytes.Length) {
            nuint width = Utf8Width(bytes[at]);

            if (width == 0 || at + width > bytes.Length || !Continues(bytes, at, width)) {
                built.AppendCodePoint((char32)0xFFFD);
                at = at + 1;
                continue;
            }

            built.AppendCodePoint(Utf8Scalar(bytes, at, width));
            at = at + width;
        }
        return built.ToText();
    }

    public Result<String, EncodingError> TryGetString(byte[] bytes) {
        nuint at = 0;

        while (at < bytes.Length) {
            nuint width = Utf8Width(bytes[at]);
            if (width == 0) { return Fail(EncodingError.Invalid); }
            if (at + width > bytes.Length) { return Fail(EncodingError.Incomplete); }
            if (!Continues(bytes, at, width)) { return Fail(EncodingError.Invalid); }

            // An overlong sequence, a surrogate or a value past U+10FFFF are
            // each a different way of spelling something that is not a scalar,
            // and a strict decoder refuses all three.
            uint scalar = (uint)Utf8Scalar(bytes, at, width);
            if (Overlong(scalar, width)) { return Fail(EncodingError.Invalid); }
            if (scalar > 0x10FFFF) { return Fail(EncodingError.Invalid); }
            if (scalar >= 0xD800 && scalar <= 0xDFFF) { return Fail(EncodingError.Invalid); }

            at = at + width;
        }
        return Ok(GetString(bytes));
    }
}

// ------------------------------------------------------------------- UTF-16

/// UTF-16, in either byte order.
public class Utf16Encoding : IEncoding {
    bool bigEndian;

    public Utf16Encoding(bool big) { bigEndian = big; }

    public String Name() { return bigEndian ? "utf-16be" : "utf-16le"; }
    // Written as an if rather than a ternary: an array literal takes its type
    // from where it is going, and a ternary arm is not somewhere that says.
    public byte[] Preamble() {
        if (bigEndian) { return [0xFE, 0xFF]; }
        return [0xFF, 0xFE];
    }

    /// Every scalar, in one unit or two.
    public bool CanRepresent(char32 scalar) { return true; }

    public nuint GetByteCount(String text) { return text.ToUtf16().UnitCount() * 2; }

    public byte[] GetBytes(String text) {
        var wide = text.ToUtf16();
        nuint count = wide.UnitCount();
        var bytes = new byte[count * 2];

        for (nuint i = 0; i < count; i = i + 1) {
            uint unit = (uint)wide.UnitAt(i);
            if (bigEndian) {
                bytes[i * 2] = (byte)(unit >> 8);
                bytes[i * 2 + 1] = (byte)(unit & 0xFF);
            } else {
                bytes[i * 2] = (byte)(unit & 0xFF);
                bytes[i * 2 + 1] = (byte)(unit >> 8);
            }
        }
        return bytes;
    }

    public String GetString(byte[] bytes) {
        var built = new StringBuilder();
        nuint at = 0;

        // A trailing odd byte is half a unit and cannot be anything.
        while (at + 1 < bytes.Length) {
            uint first = this.UnitAt(bytes, at);
            at = at + 2;

            if (first < 0xD800 || first > 0xDFFF) {
                built.AppendCodePoint((char32)first);
                continue;
            }

            if (first > 0xDBFF || at + 1 >= bytes.Length) {
                built.AppendCodePoint((char32)0xFFFD);
                continue;
            }

            uint second = this.UnitAt(bytes, at);
            if (second < 0xDC00 || second > 0xDFFF) {
                built.AppendCodePoint((char32)0xFFFD);
                continue;
            }

            at = at + 2;
            built.AppendCodePoint((char32)(0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)));
        }

        if (at < bytes.Length) { built.AppendCodePoint((char32)0xFFFD); }
        return built.ToText();
    }

    public Result<String, EncodingError> TryGetString(byte[] bytes) {
        if (bytes.Length % 2 != 0) { return Fail(EncodingError.Incomplete); }

        nuint at = 0;
        while (at < bytes.Length) {
            uint first = this.UnitAt(bytes, at);
            at = at + 2;

            if (first < 0xD800 || first > 0xDFFF) { continue; }
            if (first > 0xDBFF) { return Fail(EncodingError.Invalid); }
            if (at >= bytes.Length) { return Fail(EncodingError.Incomplete); }

            uint second = this.UnitAt(bytes, at);
            if (second < 0xDC00 || second > 0xDFFF) { return Fail(EncodingError.Invalid); }
            at = at + 2;
        }
        return Ok(GetString(bytes));
    }

    uint UnitAt(byte[] bytes, nuint at) {
        if (bigEndian) { return ((uint)bytes[at] << 8) | (uint)bytes[at + 1]; }
        return (uint)bytes[at] | ((uint)bytes[at + 1] << 8);
    }
}

// ------------------------------------------------------------------- UTF-32

/// UTF-32: one scalar per four bytes, and no surrogates anywhere.
public class Utf32Encoding : IEncoding {
    bool bigEndian;

    public Utf32Encoding(bool big) { bigEndian = big; }

    public String Name() { return bigEndian ? "utf-32be" : "utf-32le"; }

    public byte[] Preamble() {
        if (bigEndian) { return [0x00, 0x00, 0xFE, 0xFF]; }
        return [0xFF, 0xFE, 0x00, 0x00];
    }

    public bool CanRepresent(char32 scalar) { return true; }

    public nuint GetByteCount(String text) { return text.CodePointCount() * 4; }

    public byte[] GetBytes(String text) {
        var bytes = new byte[text.CodePointCount() * 4];
        nuint out = 0;

        for (nuint at = 0; at < text.ByteLength(); at = text.NextCodePoint(at)) {
            uint scalar = (uint)text.CodePointAt(at);
            if (bigEndian) {
                bytes[out] = (byte)(scalar >> 24);
                bytes[out + 1] = (byte)((scalar >> 16) & 0xFF);
                bytes[out + 2] = (byte)((scalar >> 8) & 0xFF);
                bytes[out + 3] = (byte)(scalar & 0xFF);
            } else {
                bytes[out] = (byte)(scalar & 0xFF);
                bytes[out + 1] = (byte)((scalar >> 8) & 0xFF);
                bytes[out + 2] = (byte)((scalar >> 16) & 0xFF);
                bytes[out + 3] = (byte)(scalar >> 24);
            }
            out = out + 4;
        }
        return bytes;
    }

    public String GetString(byte[] bytes) {
        var built = new StringBuilder();

        nuint at = 0;
        while (at + 3 < bytes.Length) {
            built.AppendCodePoint((char32)this.ScalarAt(bytes, at));
            at = at + 4;
        }

        if (at < bytes.Length) { built.AppendCodePoint((char32)0xFFFD); }
        return built.ToText();
    }

    public Result<String, EncodingError> TryGetString(byte[] bytes) {
        if (bytes.Length % 4 != 0) { return Fail(EncodingError.Incomplete); }

        nuint at = 0;
        while (at < bytes.Length) {
            uint scalar = this.ScalarAt(bytes, at);
            if (scalar > 0x10FFFF) { return Fail(EncodingError.Invalid); }
            if (scalar >= 0xD800 && scalar <= 0xDFFF) { return Fail(EncodingError.Invalid); }
            at = at + 4;
        }
        return Ok(GetString(bytes));
    }

    uint ScalarAt(byte[] bytes, nuint at) {
        if (bigEndian) {
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
public abstract class SingleByteEncoding : IEncoding {
    /// What this byte means. Every byte means something.
    public abstract char32 ToScalar(byte value);

    /// Which byte writes this scalar, or -1 when none does.
    public abstract int FromScalar(char32 scalar);

    public abstract String Name();

    /// None of these has one: a byte order mark is a Unicode idea.
    public byte[] Preamble() { return []; }

    public bool CanRepresent(char32 scalar) { return this.FromScalar(scalar) >= 0; }

    public nuint GetByteCount(String text) { return text.CodePointCount(); }

    public byte[] GetBytes(String text) {
        var bytes = new byte[text.CodePointCount()];
        nuint out = 0;

        for (nuint at = 0; at < text.ByteLength(); at = text.NextCodePoint(at)) {
            int written = this.FromScalar(text.CodePointAt(at));
            bytes[out] = written < 0 ? (byte)63 : (byte)written;      // '?'
            out = out + 1;
        }
        return bytes;
    }

    public String GetString(byte[] bytes) {
        var built = new StringBuilder();
        for (nuint i = 0; i < bytes.Length; i = i + 1) {
            built.AppendCodePoint(this.ToScalar(bytes[i]));
        }
        return built.ToText();
    }

    /// Never fails, which is the whole character of a single-byte encoding.
    public Result<String, EncodingError> TryGetString(byte[] bytes) {
        return Ok(this.GetString(bytes));
    }
}

/// US-ASCII. A byte above 127 is not ASCII, and reads as U+FFFD.
public class AsciiEncoding : SingleByteEncoding {
    public override String Name() { return "us-ascii"; }

    public override char32 ToScalar(byte value) {
        return value < 128 ? (char32)(uint)value : (char32)0xFFFD;
    }

    public override int FromScalar(char32 scalar) {
        uint value = (uint)scalar;
        return value < 128 ? (int)value : -1;
    }
}

/// ISO-8859-1, where byte n is code point n for every n. Nothing can fail in
/// either direction below U+0100, and nothing above it can be written.
public class Latin1Encoding : SingleByteEncoding {
    public override String Name() { return "iso-8859-1"; }

    public override char32 ToScalar(byte value) { return (char32)(uint)value; }

    public override int FromScalar(char32 scalar) {
        uint value = (uint)scalar;
        return value < 256 ? (int)value : -1;
    }
}

/// Windows-1252: Latin-1, except that 0x80 to 0x9F carry punctuation rather
/// than C1 controls. Five of those 32 positions are unassigned and read as
/// U+FFFD.
public class Windows1252Encoding : SingleByteEncoding {
    public override String Name() { return "windows-1252"; }

    public override char32 ToScalar(byte value) {
        if (value < 0x80 || value > 0x9F) { return (char32)(uint)value; }
        return (char32)Cp1252High((nuint)(value - 0x80));
    }

    public override int FromScalar(char32 scalar) {
        uint value = (uint)scalar;
        if (value < 0x80 || (value >= 0xA0 && value < 0x100)) { return (int)value; }

        for (nuint i = 0; i < 32; i = i + 1) {
            if (Cp1252High(i) == value) { return (int)(0x80 + i); }
        }
        return -1;
    }
}

/// What Windows-1252 puts at 0x80 + `index`. 0xFFFD marks the five that are
/// not assigned at all.
uint Cp1252High(nuint index) {
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
nuint Utf8Width(byte lead) {
    if (lead < 0x80) { return 1; }
    if ((lead & 0xE0) == 0xC0) { return 2; }
    if ((lead & 0xF0) == 0xE0) { return 3; }
    if ((lead & 0xF8) == 0xF0) { return 4; }
    return 0;
}

/// Whether the bytes after the lead really are continuation bytes.
bool Continues(byte[] bytes, nuint at, nuint width) {
    for (nuint i = 1; i < width; i = i + 1) {
        if ((bytes[at + i] & 0xC0) != 0x80) { return false; }
    }
    return true;
}

/// The scalar a validated sequence spells.
char32 Utf8Scalar(byte[] bytes, nuint at, nuint width) {
    if (width == 1) { return (char32)(uint)bytes[at]; }

    uint scalar = (uint)(bytes[at] & (byte)(0x7F >> (int)width));
    for (nuint i = 1; i < width; i = i + 1) {
        scalar = (scalar << 6) | (uint)(bytes[at + i] & 0x3F);
    }
    return (char32)scalar;
}

/// Whether a scalar was written in more bytes than it needed.
///
/// An overlong sequence decodes to the right number and is still refused,
/// because two spellings of one character is how a filter that checked the
/// bytes gets walked past.
bool Overlong(uint scalar, nuint width) {
    if (width == 2) { return scalar < 0x80; }
    if (width == 3) { return scalar < 0x800; }
    if (width == 4) { return scalar < 0x10000; }
    return false;
}

// -------------------------------------------------------------------- arrays

/// Whether `bytes` begins with `prefix`.
bool StartsWith(byte[] bytes, byte[] prefix) {
    if (prefix.Length > bytes.Length) { return false; }
    for (nuint i = 0; i < prefix.Length; i = i + 1) {
        if (bytes[i] != prefix[i]) { return false; }
    }
    return true;
}

/// `bytes` from `at` to the end.
byte[] Tail(byte[] bytes, nuint at) {
    if (at >= bytes.Length) { return []; }

    var rest = new byte[bytes.Length - at];
    for (nuint i = 0; i < rest.Length; i = i + 1) { rest[i] = bytes[at + i]; }
    return rest;
}
