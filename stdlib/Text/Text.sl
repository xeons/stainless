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

/// The rest of `String`.
///
/// `String` itself is intrinsic: the runtime owns its layout and its allocation,
/// and the compiler creates the symbol before any source is read. What it does
/// not own is the behaviour, and this file adds it -- a type may be declared
/// more than once inside its own module, so `Standard.Text` picks up where
/// `Builtins` left off (§3.2).
///
/// Two rules run through everything here.
///
/// **Positions are byte offsets.** A `String` is UTF-8 and length is O(1)
/// precisely because nothing counts characters, so `IndexOf` answers in bytes
/// and `Substring` takes bytes. Every position this file produces lands on a
/// character boundary, because it came from matching whole text -- a UTF-8
/// sequence cannot begin inside another one, which is what makes byte-wise
/// search correct on encoded text rather than merely fast. Positions a *caller*
/// invents are its own business; `GetCodePointAt` and `SkipCodePoint` are here for
/// walking the text properly.
///
/// **Case and whitespace are ASCII.** Full Unicode case mapping is a table of
/// several thousand entries with locale exceptions, and the runtime has no room
/// for it yet. What is here maps A-Z and a-z and leaves every other byte alone,
/// which is exactly right for identifiers, protocol tokens and file extensions,
/// and visibly wrong for prose in most languages. Anything that says `Ascii` in
/// its name says so; anything that does not is either encoding-independent or
/// documented here.
module Standard.Text;

import Standard.Limits;

/// The byte a search returns when it found nothing.
///
/// Searches answer with a `long` rather than a `nuint` for exactly this: a
/// position is unsigned, "nowhere" is not a position, and every unsigned
/// sentinel anyone has tried -- `npos`, the length, zero -- is a real position
/// in some other string. -1 is not.
public const long NotFound = -1;

/// `String`, spelled the way the primitives are.
///
/// `int` and `double` are keywords and lowercase, and a type that is just as
/// built in has no reason to look different. It is an alias and not a second
/// type, so a diagnostic says `String` whichever one was written.
public using string = String;

/// Text assembled a piece at a time.
///
/// Reach for this where a loop would otherwise write `text = text + more`: a
/// `String` is immutable, so that line allocates and copies everything so far
/// on every pass, and a builder appends into one buffer that grows instead.
/// For two or three pieces known up front, `+` is clearer and costs no more.
///
/// The declaration is the runtime's, as `String`'s is, and the appending is
/// here. Call `ToText` for the text; the builder stays usable afterwards and
/// the string does not change when it is appended to again.
// What a growable buffer needs, and the two ways to stop.
extern "C"
{
    void* realloc(void* block, nuint size);
    void  free(void* block);
    byte* memcpy(byte* to, byte* from, nuint count);
    byte* memmove(byte* to, byte* from, nuint count);

    void sl_fail(byte* message);
    void sl_array_bounds_fail(nuint index, nuint length);
}

// ---------------------------------------------------------------- helpers
//
// None of these is public. `Standard.Text` is imported into every module
// whether the program asked for it or not, so a public function here is a name
// in every scope in the program. What is worth having outside this file lives
// in `Standard.Ascii`, which has to be imported.

/// True for space, tab, newline, carriage return, vertical tab and form feed.
bool IsAsciiWhiteSpace(byte value)
{
    return value == 32 || (value >= 9 && value <= 13);
}

/// The uppercase of an ASCII letter, or the byte unchanged.
byte ToUpperByte(byte value)
{
    if (value >= 97 && value <= 122)
        return (byte)(value - 32);
    return value;
}

/// The lowercase of an ASCII letter, or the byte unchanged.
byte ToLowerByte(byte value)
{
    if (value >= 65 && value <= 90)
        return (byte)(value + 32);
    return value;
}

/// How many bytes the well-formed UTF-8 sequence at `index` occupies, or 0
/// when the bytes there are not one.
///
/// Well formed is Unicode's Table 3-7: every continuation byte present, and no
/// overlong form, surrogate or value past U+10FFFF. The runtime's
/// `sl_utf8_well_formed_width` MUST give the same answers.
nuint GetWellFormedWidth(byte* bytes, nuint index, nuint size)
{
    byte lead = bytes[index];
    if (lead < 0x80)
        return 1;
    if (lead < 0xC2 || lead > 0xF4)
        return 0;

    nuint width = 4;
    if (lead < 0xE0)
        width = 2;
    else if (lead < 0xF0)
        width = 3;

    if (index + width > size)
        return 0;

    // The lead narrows the second byte's range, which is what rules out the
    // overlong forms, the surrogates and everything past U+10FFFF.
    byte low = 0x80;
    byte high = 0xBF;
    switch (lead)
    {
        case 0xE0: low = 0xA0; break;
        case 0xED: high = 0x9F; break;
        case 0xF0: low = 0x90; break;
        case 0xF4: high = 0x8F; break;
    }

    byte second = bytes[index + 1];
    if (second < low || second > high)
        return 0;

    for (nuint i = 2; i < width; i++)
    {
        if ((bytes[index + i] & 0xC0) != 0x80)
            return 0;
    }
    return width;
}

/// Whether `count` bytes at two addresses are the same.
bool AreBytesEqual(byte* left, byte* right, nuint count)
{
    for (nuint i = 0; i < count; i++)
    {
        if (left[i] != right[i])
            return false;
    }
    return true;
}

// ============================================================== conversions

// Making a `String` out of something that is not one. The runtime allocates
// and fills it -- the layout is its, as `String`'s declaration is ([§1.2.1](../docs/spec/01-modules.md#121-and-so-may-a-type))
// -- and what is here is the names a program calls and the widths they cross
// on.
extern "C"
{
    String sl_string_from_integer(long value);
    String sl_string_from_unsigned(ulong value);
    String sl_string_from_size(nuint value);
    String sl_string_from_double(double value);
    String sl_string_from_bool(bool value);
    String sl_string_from_char(char32 codePoint);

    String sl_string_from_bytes(byte* data, nuint byteLength);
    String sl_string_from_null_terminated(byte* text);

    String sl_string_from_utf16(char16* units, nuint unitCount);
    String sl_string_from_null_terminated_utf16(char16* units);
}

/// A signed integer in base ten.
public String FromInteger(long value) => sl_string_from_integer(value);

/// An unsigned integer in base ten.
///
/// A separate entry point rather than letting the signed one take it: a
/// `ulong` past 2^63 formatted as signed prints as a negative number.
public String FromInteger(ulong value) => sl_string_from_unsigned(value);

/// A `nuint` in base ten.
///
/// Its own overload rather than a widening, because a `nuint` is a `size_t`
/// and cannot share the 64-bit entry point: on a 32-bit target the runtime
/// would read four bytes of argument and four of whatever was next on the
/// stack, and `$"{n}"` printed 8612659968337772549 for 5.
public String FromInteger(nuint value) => sl_string_from_size(value);

/// The shortest text that reads back as the same number.
public String FromDouble(double value) => sl_string_from_double(value);

/// `"true"` or `"false"`.
public String FromBool(bool value) => sl_string_from_bool(value);

/// One code point as the character it names, not as its number.
/// `Text.FromInteger((long)c)` is how to ask for the number.
///
/// @see Text.FromInteger
public String FromChar(char32 value) => sl_string_from_char(value);

/// A copy of `byteLength` bytes, taken to be UTF-8.
///
/// @see String.ToBytes
public String FromBytes(byte* data, nuint byteLength) =>
    sl_string_from_bytes(data, byteLength);

/// A copy of the bytes up to the first NUL, taken to be UTF-8. What a C
/// function that answers with a `char*` hands back.
///
/// @see Text.FromBytes
public String FromNullTerminated(byte* text) => sl_string_from_null_terminated(text);

/// UTF-16 transcoded to UTF-8.
///
/// A pointer and a count rather than a `Utf16String`, because a wide platform
/// API writes into a buffer the caller owns and that pair is what comes back.
///
/// @see Text.FromNullTerminatedUtf16
public String FromUtf16(char16* units, nuint unitCount) =>
    sl_string_from_utf16(units, unitCount);

/// UTF-16 up to the first NUL unit, transcoded to UTF-8.
///
/// @see Text.FromUtf16
public String FromNullTerminatedUtf16(char16* units) =>
    sl_string_from_null_terminated_utf16(units);
