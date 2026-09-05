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

// Turning things into other things: bytes into text, text into numbers.
//
// Two jobs that .NET puts in one class, and they are here together for the same
// reason -- they are what a program reaches for at the edge, where a value
// arrived as characters and has to become something, or has to leave as
// characters and is not one.
//
// Everything that can fail returns a `Result`. There is no `Parse` that stops
// the program and no `TryParse` with an out parameter, because the language has
// neither exceptions nor `out`: a function that can fail says so in its return
// type, and the value is unreadable until the failure has been checked (§2.6).
module Standard.Convert;

import Standard.Text;
import Standard.Ascii;

/// Why a conversion did not happen.
public enum ConvertError {
    /// There was nothing to convert.
    Empty,

    /// A character that cannot appear in this form.
    Malformed,

    /// The digits were fine and the number does not fit.
    OutOfRange,
}

// ------------------------------------------------------------------ integers

/// `text` as a whole number in base ten.
///
/// A leading `+` or `-` is allowed and nothing else is: no spaces, no
/// separators, no trailing units. Trim first if the input might have any.
public Result<long, ConvertError> ToLong(String text) {
    return ToLong(text, 10);
}

/// `text` as a whole number in `radix`, from 2 to 36.
///
/// Letters count from `a` = 10 in either case, so base 16 takes `1F` and `1f`
/// alike, and base 36 goes to `z`.
public Result<long, ConvertError> ToLong(String text, uint radix) {
    if (radix < 2 || radix > 36) { return Fail(ConvertError.Malformed); }

    nuint size = text.ByteLength();
    if (size == 0) { return Fail(ConvertError.Empty); }

    var bytes = text.ToPointer();
    nuint at = 0;
    bool negative = false;

    if (bytes[0] == 43 || bytes[0] == 45) {          // '+' or '-'
        negative = bytes[0] == 45;
        at = 1;
        if (size == 1) { return Fail(ConvertError.Empty); }
    }

    // Accumulated as unsigned so that long.MinValue, whose magnitude does not
    // fit in a long, is still reachable -- which is the one value a naive
    // signed accumulator always gets wrong.
    ulong magnitude = 0;
    ulong limit = 9223372036854775807u;
    if (negative) { limit = 9223372036854775808u; }

    for (nuint i = at; i < size; i = i + 1) {
        int digit = DigitValue(bytes[i]);
        if (digit < 0 || (uint)digit >= radix) { return Fail(ConvertError.Malformed); }

        if (magnitude > (limit - (ulong)digit) / (ulong)radix) {
            return Fail(ConvertError.OutOfRange);
        }
        magnitude = magnitude * (ulong)radix + (ulong)digit;
    }

    if (negative) { return Ok(-(long)magnitude); }
    return Ok((long)magnitude);
}

/// `text` as an `int`, which is `ToLong` plus a range check.
public Result<int, ConvertError> ToInt(String text) {
    return ToInt(text, 10);
}

public Result<int, ConvertError> ToInt(String text, uint radix) {
    var wide = ToLong(text, radix);
    switch (wide) {
        case Ok ok:
            if (ok.Value < -2147483648 || ok.Value > 2147483647) {
                return Fail(ConvertError.OutOfRange);
            }
            return Ok((int)ok.Value);
        case Fail bad:
            return Fail(bad.Error);
    }
}

/// `text` as an unsigned whole number. A leading `-` is malformed rather than
/// wrapping, which is the whole point of asking for an unsigned one.
public Result<ulong, ConvertError> ToULong(String text) {
    return ToULong(text, 10);
}

public Result<ulong, ConvertError> ToULong(String text, uint radix) {
    if (radix < 2 || radix > 36) { return Fail(ConvertError.Malformed); }

    nuint size = text.ByteLength();
    if (size == 0) { return Fail(ConvertError.Empty); }

    var bytes = text.ToPointer();
    nuint at = 0;
    if (bytes[0] == 43) { at = 1; }                  // a '+' is allowed
    if (at == size) { return Fail(ConvertError.Empty); }

    ulong value = 0;
    for (nuint i = at; i < size; i = i + 1) {
        int digit = DigitValue(bytes[i]);
        if (digit < 0 || (uint)digit >= radix) { return Fail(ConvertError.Malformed); }

        if (value > (18446744073709551615u - (ulong)digit) / (ulong)radix) {
            return Fail(ConvertError.OutOfRange);
        }
        value = value * (ulong)radix + (ulong)digit;
    }
    return Ok(value);
}

/// A whole number written in `radix`, from 2 to 36, with lowercase letters.
///
/// Base ten needs nothing from here: `Text.FromInteger` already does it, and
/// through C's own formatter.
public String FromLong(long value, uint radix) {
    if (radix < 2 || radix > 36) { return ""; }
    if (value == 0) { return "0"; }

    bool negative = value < 0;

    // The magnitude as unsigned, again so that long.MinValue survives being
    // negated -- in signed arithmetic it does not.
    ulong magnitude = negative ? (ulong)(-(value + 1)) + 1u : (ulong)value;

    var digits = new StringBuilder();
    while (magnitude > 0) {
        byte digit = DigitTable((nuint)(magnitude % (ulong)radix));
        digits.Append(FromBytes(&digit, 1));
        magnitude = magnitude / (ulong)radix;
    }

    var built = new StringBuilder();
    if (negative) { built.Append("-"); }

    // Written backwards, so read backwards.
    for (nuint i = digits.ByteLength(); i > 0; i = i - 1) {
        var one = digits.ByteAt(i - 1);
        built.Append(FromBytes(&one, 1));
    }
    return built.ToText();
}

// ------------------------------------------------------------------ decimals

/// `text` as a floating-point number.
///
/// Accepts what C accepts of the ordinary forms -- an optional sign, digits, a
/// point, an exponent -- and nothing else. Hexadecimal floats, infinities and
/// NaN are not spelled here.
public Result<double, ConvertError> ToDouble(String text) {
    nuint size = text.ByteLength();
    if (size == 0) { return Fail(ConvertError.Empty); }

    var bytes = text.ToPointer();
    nuint at = 0;
    bool negative = false;

    if (bytes[0] == 43 || bytes[0] == 45) {
        negative = bytes[0] == 45;
        at = 1;
    }

    double value = 0.0;
    nuint digits = 0;

    while (at < size && Ascii.IsDigit(bytes[at])) {
        value = value * 10.0 + (double)(int)(bytes[at] - 48);
        at = at + 1;
        digits = digits + 1;
    }

    if (at < size && bytes[at] == 46) {              // '.'
        at = at + 1;
        double scale = 0.1;
        while (at < size && Ascii.IsDigit(bytes[at])) {
            value = value + (double)(int)(bytes[at] - 48) * scale;
            scale = scale * 0.1;
            at = at + 1;
            digits = digits + 1;
        }
    }

    // A sign and a point and no digits at all is not a number.
    if (digits == 0) { return Fail(ConvertError.Malformed); }

    if (at < size && (bytes[at] == 101 || bytes[at] == 69)) {     // 'e' or 'E'
        at = at + 1;
        bool negativeExponent = false;

        if (at < size && (bytes[at] == 43 || bytes[at] == 45)) {
            negativeExponent = bytes[at] == 45;
            at = at + 1;
        }

        if (at >= size || !Ascii.IsDigit(bytes[at])) { return Fail(ConvertError.Malformed); }

        int exponent = 0;
        while (at < size && Ascii.IsDigit(bytes[at])) {
            if (exponent < 10000) { exponent = exponent * 10 + (int)(bytes[at] - 48); }
            at = at + 1;
        }

        for (int i = 0; i < exponent; i = i + 1) {
            if (negativeExponent) { value = value / 10.0; } else { value = value * 10.0; }
        }
    }

    if (at != size) { return Fail(ConvertError.Malformed); }
    if (negative) { return Ok(-value); }
    return Ok(value);
}

// ---------------------------------------------------------------- hexadecimal

/// `data` as lowercase hexadecimal, two characters per byte and nothing between.
public String ToHex(byte[] data) {
    return ToHex(data, false);
}

/// The same, in the case asked for.
public String ToHex(byte[] data, bool upper) {
    var built = new StringBuilder();

    for (nuint i = 0; i < data.Length; i = i + 1) {
        int high = (int)(data[i] >> 4);
        int low = (int)(data[i] & 0x0F);

        byte[2] pair;
        if (upper) {
            pair[0] = Ascii.HexDigitUpper(high);
            pair[1] = Ascii.HexDigitUpper(low);
        } else {
            pair[0] = Ascii.HexDigit(high);
            pair[1] = Ascii.HexDigit(low);
        }
        built.Append(FromBytes(&pair[0], 2));
    }
    return built.ToText();
}

/// Hexadecimal back into bytes. Either case, and an odd number of digits is
/// malformed rather than padded, because there is no way to know which end the
/// missing half belonged to.
public Result<byte[], ConvertError> FromHex(String text) {
    nuint size = text.ByteLength();
    if (size % 2 != 0) { return Fail(ConvertError.Malformed); }

    var bytes = text.ToPointer();
    var data = new byte[size / 2];

    for (nuint i = 0; i < data.Length; i = i + 1) {
        int high = Ascii.HexValue(bytes[i * 2]);
        int low = Ascii.HexValue(bytes[i * 2 + 1]);
        if (high < 0 || low < 0) { return Fail(ConvertError.Malformed); }

        data[i] = (byte)((high << 4) | low);
    }
    return Ok(data);
}

// --------------------------------------------------------------------- base64

/// `data` as base64, padded with `=` to a multiple of four.
public String ToBase64(byte[] data) {
    return Encode64(data, false, true);
}

/// `data` as base64url: `-` and `_` for the last two characters, and no
/// padding. What a JWT and a URL query both want, and RFC 4648 §5.
public String ToBase64Url(byte[] data) {
    return Encode64(data, true, false);
}

/// Base64 back into bytes, accepting both alphabets and padding or none.
///
/// Whitespace is skipped, because base64 in the wild arrives wrapped at 64 or
/// 76 columns and a decoder that refused a newline would be useless for the
/// thing it is most often pointed at.
public Result<byte[], ConvertError> FromBase64(String text) {
    nuint size = text.ByteLength();
    var bytes = text.ToPointer();

    // Counted first: four characters become three bytes, and the padding says
    // how many of the last three are real.
    nuint characters = 0;
    for (nuint i = 0; i < size; i = i + 1) {
        byte one = bytes[i];
        if (Ascii.IsWhiteSpace(one) || one == 61) { continue; }      // '='
        if (Base64Value(one) < 0) { return Fail(ConvertError.Malformed); }
        characters = characters + 1;
    }

    if (characters % 4 == 1) { return Fail(ConvertError.Malformed); }

    var data = new byte[characters * 3 / 4];
    uint accumulator = 0;
    nuint held = 0;
    nuint out = 0;

    for (nuint i = 0; i < size; i = i + 1) {
        byte one = bytes[i];
        if (Ascii.IsWhiteSpace(one) || one == 61) { continue; }

        accumulator = (accumulator << 6) | (uint)Base64Value(one);
        held = held + 1;

        if (held == 4) {
            data[out] = (byte)(accumulator >> 16);
            data[out + 1] = (byte)((accumulator >> 8) & 0xFF);
            data[out + 2] = (byte)(accumulator & 0xFF);
            out = out + 3;
            accumulator = 0;
            held = 0;
        }
    }

    // A tail of two characters carries one byte and of three carries two; the
    // bits below those are padding and are dropped.
    if (held == 2) {
        data[out] = (byte)((accumulator >> 4) & 0xFF);
    } else if (held == 3) {
        data[out] = (byte)((accumulator >> 10) & 0xFF);
        data[out + 1] = (byte)((accumulator >> 2) & 0xFF);
    }

    return Ok(data);
}

/// Base64 of the UTF-8 bytes of `text`, which is the common case.
public String ToBase64Text(String text) {
    return ToBase64(text.ToBytes());
}

// --------------------------------------------------------------------- private

String Encode64(byte[] data, bool url, bool pad) {
    var built = new StringBuilder();
    nuint at = 0;

    while (at + 2 < data.Length) {
        uint block = ((uint)data[at] << 16) | ((uint)data[at + 1] << 8) | (uint)data[at + 2];
        AppendSix(built, block, 4, url);
        at = at + 3;
    }

    nuint left = data.Length - at;
    if (left == 1) {
        AppendSix(built, (uint)data[at] << 16, 2, url);
        if (pad) { built.Append("=="); }
    } else if (left == 2) {
        AppendSix(built, ((uint)data[at] << 16) | ((uint)data[at + 1] << 8), 3, url);
        if (pad) { built.Append("="); }
    }

    return built.ToText();
}

/// The top `count` six-bit groups of a 24-bit block, as characters.
void AppendSix(StringBuilder built, uint block, nuint count, bool url) {
    for (nuint i = 0; i < count; i = i + 1) {
        uint six = (uint)((block >> (int)(18 - i * 6)) & 0x3F);
        var one = Base64Digit(six, url);
        built.Append(FromBytes(&one, 1));
    }
}

byte Base64Digit(uint value, bool url) {
    if (value < 26) { return (byte)(65 + value); }               // 'A'
    if (value < 52) { return (byte)(97 + value - 26); }          // 'a'
    if (value < 62) { return (byte)(48 + value - 52); }          // '0'
    if (value == 62) { return url ? (byte)45 : (byte)43; }       // '-' or '+'
    return url ? (byte)95 : (byte)47;                            // '_' or '/'
}

/// What a base64 character is worth, in either alphabet, or -1.
int Base64Value(byte one) {
    if (one >= 65 && one <= 90) { return (int)one - 65; }
    if (one >= 97 && one <= 122) { return (int)one - 97 + 26; }
    if (one >= 48 && one <= 57) { return (int)one - 48 + 52; }
    if (one == 43 || one == 45) { return 62; }                   // '+' and '-'
    if (one == 47 || one == 95) { return 63; }                   // '/' and '_'
    return -1;
}

/// What a digit is worth in any radix up to 36, or -1.
int DigitValue(byte one) {
    if (Ascii.IsDigit(one)) { return (int)one - 48; }
    if (one >= 97 && one <= 122) { return (int)one - 97 + 10; }
    if (one >= 65 && one <= 90) { return (int)one - 65 + 10; }
    return -1;
}

/// The lowercase character for a digit value up to 35.
byte DigitTable(nuint value) {
    if (value < 10) { return (byte)(48 + value); }
    return (byte)(87 + value);
}
