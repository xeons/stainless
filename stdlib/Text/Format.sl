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

// Numbers in .NET's standard numeric formats, which is what an interpolation's
// `{value:X8}` asks for, and padding to a width, which is what `{value,8}`
// asks for.
module Standard.Text;

extern "C"
{
    String sl_string_format_double(double value, int letter, int precision);
}

/// The precision a standard format asks for: -1 for none, and -2 when the text
/// after the letter is not a precision.
int ReadFormatPrecision(String format)
{
    nuint size = format.ByteLength();
    if (size < 2u)
        return -1;
    if (size > 4u)
        return -2;

    int precision = 0;
    for (nuint i = 1u; i < size; i++)
    {
        byte digit = format.GetByteAt(i);
        if (digit < 0x30 || digit > 0x39)
            return -2;
        precision = precision * 10 + (int)(digit - 0x30);
    }
    return precision;
}

/// The letter of a standard format, or 0 for text that is not one.
char ReadFormatLetter(String format)
{
    if (format.IsEmpty || ReadFormatPrecision(format) == -2)
        return (char)0;
    return (char)format.GetByteAt(0u);
}

/// Stops the program over a format no number takes.
void FailFormat(String format, String what)
{
    sl_fail(("'" + format + "' is not a standard format for " + what).ToPointer());
}

/// A magnitude's digits in a radix, zero-padded to `precision` of them.
String FormatUnsignedDigits(ulong magnitude, ulong radix, int precision, bool upper)
{
    // Sixty-four is every ulong there is in binary.
    byte[64] digits;
    nuint written = 0u;

    while (magnitude > 0u || written == 0u)
    {
        uint digit = (uint)(magnitude % radix);
        if (digit < 10u)
        {
            digits[written] = (byte)(0x30u + digit);
        }
        else
        {
            digits[written] = (byte)((upper ? 0x41u : 0x61u) + digit - 10u);
        }
        written++;
        magnitude = magnitude / radix;
    }

    var built = new StringBuilder();
    for (int i = (int)written; i < precision; i++)
        built.AppendByte(0x30);

    // The digits came out least significant first.
    for (nuint i = written; i > 0u; i--)
        built.AppendByte(digits[i - 1u]);
    return built.ToText();
}

/// A magnitude in base ten with its sign, the digits zero-padded to `precision`.
String FormatSignedDigits(bool negative, ulong magnitude, int precision)
{
    String digits = FormatUnsignedDigits(magnitude, 10u, precision, false);
    if (negative)
        return "-" + digits;
    return digits;
}

/// A magnitude in fixed point: its digits, grouped in threes when asked, then
/// `decimals` zeros after the point, since a whole number has no fraction.
String FormatWholeFixed(bool negative, ulong magnitude, int decimals, bool grouped)
{
    String digits = FormatUnsignedDigits(magnitude, 10u, 0, false);
    var built = new StringBuilder();
    if (negative)
        built.AppendByte(0x2D);

    nuint size = digits.ByteLength();
    for (nuint i = 0u; i < size; i++)
    {
        if (grouped && i > 0u && (size - i) % 3u == 0u)
            built.AppendByte(0x2C);
        built.AppendByte(digits.GetByteAt(i));
    }

    if (decimals > 0)
    {
        built.AppendByte(0x2E);
        for (int i = 0; i < decimals; i++)
            built.AppendByte(0x30);
    }
    return built.ToText();
}

/// A signed integer in a standard numeric format, as `{value:D8}` writes it.
///
/// A format is a letter and an optional precision of up to three digits:
///
/// | Format | Integers | Floating point |
/// |---|---|---|
/// | `D` | digits, zero-padded to the precision | -- |
/// | `X`, `x` | hexadecimal in that case, zero-padded | -- |
/// | `B` | binary, zero-padded | -- |
/// | `F` | fixed point, the precision's decimals (2) | the same |
/// | `N` | `F` with a comma between groups of three | the same |
/// | `E`, `e` | scientific, the precision's decimals (6) | the same |
/// | `G`, `g` | the digits, or the precision's significant digits | the shortest spelling, or the same |
///
/// Either case of a letter is accepted; only `X`, `E` and `G` write something
/// that differs by case. Rounding is half away from zero, and the separators
/// are the invariant culture's, since there is no other.
///
/// `X` and `B` write the two's complement of all 64 bits, so a narrower type
/// widened to reach here reads as that type only if it was widened unsigned;
/// an interpolation does that for itself. **A format that is not in the table
/// stops the program**, as an index out of range does: which format is asked
/// for is fixed where the call is written, and an interpolation's is checked
/// when it compiles.
///
/// @see Text.FormatDouble
public String FormatInteger(long value, String format)
{
    int precision = ReadFormatPrecision(format);
    bool negative = value < 0;

    // The magnitude as unsigned, so that the smallest long -- whose magnitude
    // is not itself a long -- survives being negated.
    ulong magnitude = negative ? (ulong)(-(value + 1)) + 1u : (ulong)value;

    char letter = ReadFormatLetter(format);

    switch (letter)
    {
        case 'D':
        case 'd':
            return FormatSignedDigits(negative, magnitude, precision);

        case 'G':
        case 'g':
            if (precision > 0)
                return sl_string_format_double((double)value, (int)letter, precision);
            return FormatSignedDigits(negative, magnitude, 0);

        case 'X':
        case 'x':
        case 'B':
        case 'b':
            return FormatInteger((ulong)value, format);

        case 'F':
        case 'f':
            return FormatWholeFixed(negative, magnitude, precision < 0 ? 2 : precision, false);

        case 'N':
        case 'n':
            return FormatWholeFixed(negative, magnitude, precision < 0 ? 2 : precision, true);

        case 'E':
        case 'e':
            return sl_string_format_double((double)value, (int)letter, precision);
    }

    FailFormat(format, "an integer");
    return "";
}

/// An unsigned integer in a standard numeric format.
///
/// @see Text.FormatInteger
public String FormatInteger(ulong value, String format)
{
    int precision = ReadFormatPrecision(format);
    char letter = ReadFormatLetter(format);

    switch (letter)
    {
        case 'D':
        case 'd':
            return FormatUnsignedDigits(value, 10u, precision, false);

        case 'G':
        case 'g':
            if (precision > 0)
                return sl_string_format_double((double)value, (int)letter, precision);
            return FormatUnsignedDigits(value, 10u, 0, false);

        case 'X':
        case 'x':
            return FormatUnsignedDigits(value, 16u, precision, letter == 'X');

        case 'B':
        case 'b':
            return FormatUnsignedDigits(value, 2u, precision, false);

        case 'F':
        case 'f':
            return FormatWholeFixed(false, value, precision < 0 ? 2 : precision, false);

        case 'N':
        case 'n':
            return FormatWholeFixed(false, value, precision < 0 ? 2 : precision, true);

        case 'E':
        case 'e':
            return sl_string_format_double((double)value, (int)letter, precision);
    }

    FailFormat(format, "an integer");
    return "";
}

/// A floating-point number in a standard numeric format, as `{value:F2}`
/// writes it: `F`, `N`, `E` or `G`, as `FormatInteger` describes them. `D`,
/// `X` and `B` are integer formats and are not taken here.
///
/// @see Text.FormatInteger
public String FormatDouble(double value, String format)
{
    int precision = ReadFormatPrecision(format);
    char letter = ReadFormatLetter(format);

    switch (letter)
    {
        case 'F':
        case 'f':
        case 'N':
        case 'n':
        case 'E':
        case 'e':
        case 'G':
        case 'g':
            return sl_string_format_double(value, (int)letter, precision);
    }

    FailFormat(format, "a floating-point number");
    return "";
}

/// `text` padded with spaces to `alignment` characters: on the left when it is
/// positive, so the text ends at the width, and on the right when it is
/// negative. Never truncates. This is `{value,8}` and `{value,-8}`.
///
/// **Characters, not bytes**, unlike `PadLeft`: a width is a column, and a
/// column holds a character however many bytes encode it.
///
/// @see String.PadLeft
public String AlignText(String text, int alignment)
{
    nuint width = alignment < 0 ? (nuint)(-(long)alignment) : (nuint)alignment;
    nuint count = text.CodePointCount();
    if (count >= width)
        return text;

    String padding = " ".Repeat(width - count);
    if (alignment < 0)
        return text + padding;
    return padding + text;
}
