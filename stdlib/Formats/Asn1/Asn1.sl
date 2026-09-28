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

/// ASN.1 values in BER and DER, as X.509, PKCS and TLS carry them.
///
/// ```csharp
/// var document = new AsnReader(der, AsnEncodingRules.Der);
/// var certificate = try document.ReadSequence();
/// var signed = try certificate.ReadSequence();
/// String algorithm = try (try certificate.ReadSequence()).ReadObjectIdentifier();
///
/// var writer = new AsnWriter();
/// writer.PushSequence();
/// writer.WriteInteger(5);
/// writer.WriteObjectIdentifier("1.2.840.113549");
/// writer.PopSequence();
/// byte[] encoded = writer.Encode();
/// ```
///
/// **The shape is `System.Formats.Asn1`'s**, with a `Result` where .NET
/// throws. A read that fails returns an `AsnError` and leaves the reader
/// where it was, so a caller can try another reading of the same value.
///
/// **Every read is bounds-checked against the value that contains it.** A
/// nested reader sees its own contents and nothing past them, so a length
/// that claims more than its parent holds is `Truncated` rather than a read
/// of a neighbour. Nothing here aborts on input.
///
/// **Times are seconds since 1970-01-01 UTC, in a `long`.** A
/// `GeneralizedTime` can name 9999, and `DateTimeOffset` counts nanoseconds and
/// ends in 2262; `ConvertAsnTimeToDateTimeOffset` crosses over where it can.
///
/// **SET OF ordering is not verified on reading.** DER requires the elements
/// in order and a reader that checks costs a sort per set; X.509 signs the
/// bytes rather than the order, so the check buys nothing there. The writer
/// does sort.
///
/// Object identifiers are dotted strings. Which one means what belongs to the
/// format that uses it, and is not this module's.
module Standard.Formats.Asn1;

import Standard.Time;

[DoesNotReturn]
extern "C" void sl_fail(byte* message);

/// A sentence describing an error, for a message a person will read.
public String DescribeAsnError(AsnError error)
{
    switch (error)
    {
        case AsnError.None: return "no error";
        case AsnError.Truncated: return "the input ends inside a value";
        case AsnError.BadLength: return "a length that is malformed or wrong for the type";
        case AsnError.UnexpectedTag: return "not the tag expected";
        case AsnError.NonMinimalEncoding: return "an encoding the rules in force forbid";
        case AsnError.OutOfRange: return "a value too large for what it is read into";
        case AsnError.BadStringContent: return "a character the string type does not allow";
        case AsnError.BadTime: return "a malformed or impossible time";
        case AsnError.TrailingData: return "data after the last value";
        case AsnError.Unsupported: return "an encoding this reader does not support";
        case AsnError.Malformed: return "contents that do not encode their type";
    }
    return "unknown error";
}

/// An ASN.1 time as a `DateTimeOffset`, where one can hold it.
///
/// @param seconds  seconds since 1970-01-01 UTC, as `AsnReader.ReadUtcTime` answers
/// @failure AsnError.OutOfRange  the moment is before 1677-09-21 or after 2262-04-11,
///                               where a count of nanoseconds in a `long` ends
/// @see AsnReader.ReadGeneralizedTime
public Result<DateTimeOffset, AsnError> ConvertAsnTimeToDateTimeOffset(long seconds)
{
    if (seconds > 9223372036 || seconds < -9223372036)
        return Fail(AsnError.OutOfRange);
    return Ok(DateTimeOffset.FromUnixTimeSeconds(seconds));
}

// ------------------------------------------------------------------ calendar

/// Days since 1970-01-01 of a proleptic Gregorian date. Exact for every year
/// a `GeneralizedTime` can write.
long CountDaysFromCivil(long year, long month, long day)
{
    long shifted = month <= 2 ? year - 1 : year;
    long era = (shifted >= 0 ? shifted : shifted - 399) / 400;
    long yearOfEra = shifted - era * 400;
    long monthFromMarch = month > 2 ? month - 3 : month + 9;
    long dayOfYear = (153 * monthFromMarch + 2) / 5 + day - 1;
    long dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear;
    return era * 146097 + dayOfEra - 719468;
}

/// The date `days` after 1970-01-01, as year, month and day.
(long, long, long) ConvertDaysToCivil(long days)
{
    long shifted = days + 719468;
    long era = (shifted >= 0 ? shifted : shifted - 146096) / 146097;
    long dayOfEra = shifted - era * 146097;
    long yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146096) / 365;
    long dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100);
    long monthFromMarch = (5 * dayOfYear + 2) / 153;
    long day = dayOfYear - (153 * monthFromMarch + 2) / 5 + 1;
    long month = monthFromMarch < 10 ? monthFromMarch + 3 : monthFromMarch - 9;
    long year = yearOfEra + era * 400;
    if (month <= 2)
        year++;
    return (year, month, day);
}

// ---------------------------------------------------------------------- UTF-8

/// The scalar value encoded at `at`, or -1 when the octets there are not
/// well-formed UTF-8. Overlong forms, surrogates and values past U+10FFFF are
/// all refused. `width` is how many octets it took.
int DecodeUtf8ScalarAt(ReadOnlySpan<byte> data, nuint at, out nuint width)
{
    width = 1u;
    uint lead = (uint)data[at];
    if (lead < 0x80u)
        return (int)lead;

    nuint count = 0u;
    uint scalar = 0u;
    uint low = 0x80u;
    uint high = 0xBFu;
    if (lead >= 0xC2u && lead <= 0xDFu)
    {
        count = 1u;
        scalar = lead & 0x1Fu;
    }
    else if (lead >= 0xE0u && lead <= 0xEFu)
    {
        count = 2u;
        scalar = lead & 0x0Fu;
        if (lead == 0xE0u)
            low = 0xA0u;
        if (lead == 0xEDu)
            high = 0x9Fu;
    }
    else if (lead >= 0xF0u && lead <= 0xF4u)
    {
        count = 3u;
        scalar = lead & 0x07u;
        if (lead == 0xF0u)
            low = 0x90u;
        if (lead == 0xF4u)
            high = 0x8Fu;
    }
    else
    {
        return -1;
    }

    if (count > data.Length - at - 1u)
        return -1;

    for (nuint i = 1u; i <= count; i++)
    {
        uint next = (uint)data[at + i];
        if (next < low || next > high)
            return -1;
        low = 0x80u;
        high = 0xBFu;
        scalar = (scalar << 6) | (next & 0x3Fu);
    }

    width = count + 1u;
    return (int)scalar;
}
