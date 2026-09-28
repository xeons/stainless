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

module Standard.Formats.Asn1;

/// Builds DER, one value after another.
///
/// ```csharp
/// var writer = new AsnWriter();
/// writer.PushSequence();
///     writer.WriteInteger(2);
///     writer.PushSequence(new Asn1Tag(TagClass.ContextSpecific, 0, true));
///         writer.WriteBoolean(true);
///     writer.PopSequence();
/// writer.PopSequence();
/// byte[] der = writer.Encode();
/// ```
///
/// **Everything written is DER.** BER's freedoms are all a reader's; a writer
/// never needs one, so there is no rule set to choose.
///
/// **A write that can be refused returns an `AsnError`** — an identifier that
/// is not one, a character a string type does not allow, a time outside the
/// years its type names — and writes nothing when it does. The rest cannot
/// fail and return nothing.
///
/// **Push and Pop MUST pair.** A `Pop` with nothing open, a `PopSetOf` for a
/// `PushSequence`, and an `Encode` with anything still open are mistakes in
/// the program rather than in its data, and abort as an array index past the
/// end does.
public sealed class AsnWriter
{
    private byte[] _buffer;
    private nuint _length;
    private nuint[] _scopeStarts;
    private bool[] _scopeIsSetOf;
    private nuint _depth;

    /// An empty writer.
    public AsnWriter()
    {
        _buffer = new byte[64u];
        _scopeStarts = new nuint[8u];
        _scopeIsSetOf = new bool[8u];
    }

    /// How many sequences and sets are open.
    public nuint Depth => _depth;

    /// What has been written, as one run of bytes.
    ///
    /// Aborts when a sequence or a set is still open, since its length is not
    /// yet known.
    public byte[] Encode()
    {
        if (_depth > 0u)
            sl_fail("AsnWriter.Encode: a Push has no Pop, so a length is not yet known");

        var encoded = new byte[_length];
        for (nuint i = 0u; i < _length; i++)
            encoded[i] = _buffer[i];
        return encoded;
    }

    // ------------------------------------------------------------ structure

    /// Opens a `SEQUENCE`, which lasts until the matching `PopSequence`.
    ///
    /// @param tag  the tag in place of `SEQUENCE`; a context tag here is explicit tagging
    /// @see AsnWriter.PopSequence
    public void PushSequence(Optional<Asn1Tag> tag = default(Optional<Asn1Tag>))
    {
        OpenScope(tag.GetValueOrDefault(Asn1Tag.Sequence), false);
    }

    /// Closes the innermost `PushSequence`.
    public void PopSequence()
    {
        CloseScope(false);
    }

    /// Opens a `SET OF`, which lasts until the matching `PopSetOf`.
    ///
    /// @param tag  the tag in place of `SET`
    /// @see AsnWriter.PopSetOf
    public void PushSetOf(Optional<Asn1Tag> tag = default(Optional<Asn1Tag>))
    {
        OpenScope(tag.GetValueOrDefault(Asn1Tag.SetOf), true);
    }

    /// Closes the innermost `PushSetOf`, sorting its elements into the order
    /// DER requires.
    public void PopSetOf()
    {
        CloseScope(true);
    }

    /// One value that is already encoded, copied as it is.
    ///
    /// Its tag and length are checked; its contents are not.
    ///
    /// @param encoded  exactly one whole value
    /// @returns `AsnError.None`, or why `encoded` is not one DER value
    public AsnError WriteEncodedValue(ReadOnlySpan<byte> encoded)
    {
        var header = AsnReader.DecodeHeader(encoded, AsnEncodingRules.Der);
        if (!header.Ok)
            return header.Error;
        if (header.Value.TotalLength != encoded.Length)
            return AsnError.TrailingData;
        AppendSpan(encoded);
        return AsnError.None;
    }

    // --------------------------------------------------------------- scalars

    /// A `BOOLEAN`: `0xFF` for true, as DER requires.
    ///
    /// @param value  what to write
    /// @param tag    the tag in place of `BOOLEAN`
    public void WriteBoolean(bool value, Optional<Asn1Tag> tag = default(Optional<Asn1Tag>))
    {
        WritePrimitiveHeader(tag, Asn1Tag.Boolean, 1u);
        AppendByte(value ? (byte)0xFF : (byte)0x00);
    }

    /// A `NULL`.
    ///
    /// @param tag  the tag in place of `NULL`
    public void WriteNull(Optional<Asn1Tag> tag = default(Optional<Asn1Tag>))
    {
        WritePrimitiveHeader(tag, Asn1Tag.Null, 0u);
    }

    /// An `INTEGER`, in the fewest octets that hold it.
    ///
    /// @param value  what to write
    /// @param tag    the tag in place of `INTEGER`
    public void WriteInteger(long value, Optional<Asn1Tag> tag = default(Optional<Asn1Tag>))
    {
        WriteSigned(tag.GetValueOrDefault(Asn1Tag.Integer), value);
    }

    /// An `INTEGER` from an unsigned value, which gains a leading `0x00` when
    /// its top bit is set.
    ///
    /// @param value  what to write
    /// @param tag    the tag in place of `INTEGER`
    public void WriteInteger(ulong value, Optional<Asn1Tag> tag = default(Optional<Asn1Tag>))
    {
        var octets = new byte[9u];
        for (nuint i = 0u; i < 8u; i++)
            octets[i + 1u] = (byte)((value >> (uint)(8u * (7u - i))) & 0xFFu);
        byte[] contents = TrimUnsignedMagnitude(octets);
        WritePrimitiveHeader(tag, Asn1Tag.Integer, contents.Length);
        AppendSpan(contents);
    }

    /// An `INTEGER` whose contents are given: two's complement, big-endian,
    /// already minimal.
    ///
    /// @param value  the contents octets
    /// @param tag    the tag in place of `INTEGER`
    /// @returns `AsnError.BadLength` when `value` is empty,
    ///          `AsnError.NonMinimalEncoding` when it starts with a redundant octet
    /// @see AsnWriter.WriteIntegerUnsigned
    public AsnError WriteIntegerBytes(
        ReadOnlySpan<byte> value, Optional<Asn1Tag> tag = default(Optional<Asn1Tag>))
    {
        if (value.Length == 0u)
            return AsnError.BadLength;
        if (value.Length > 1u)
        {
            uint first = (uint)value[0u];
            uint second = (uint)value[1u] & 0x80u;
            if ((first == 0x00u && second == 0u) || (first == 0xFFu && second != 0u))
                return AsnError.NonMinimalEncoding;
        }

        WritePrimitiveHeader(tag, Asn1Tag.Integer, value.Length);
        AppendSpan(value);
        return AsnError.None;
    }

    /// An `INTEGER` whose magnitude is given, big-endian and unsigned: what a
    /// serial number or an RSA modulus is held as. Leading zeros are dropped
    /// and one is added back when the top bit is set, so the value is never
    /// read as negative.
    ///
    /// @param magnitude  the value's octets; empty is zero
    /// @param tag        the tag in place of `INTEGER`
    /// @see AsnWriter.WriteIntegerBytes
    public void WriteIntegerUnsigned(
        ReadOnlySpan<byte> magnitude, Optional<Asn1Tag> tag = default(Optional<Asn1Tag>))
    {
        var padded = new byte[magnitude.Length + 1u];
        for (nuint i = 0u; i < magnitude.Length; i++)
            padded[i + 1u] = magnitude[i];
        byte[] contents = TrimUnsignedMagnitude(padded);
        WritePrimitiveHeader(tag, Asn1Tag.Integer, contents.Length);
        AppendSpan(contents);
    }

    /// An `ENUMERATED`.
    ///
    /// @param value  what to write
    /// @param tag    the tag in place of `ENUMERATED`
    public void WriteEnumeratedValue(long value, Optional<Asn1Tag> tag = default(Optional<Asn1Tag>))
    {
        WriteSigned(tag.GetValueOrDefault(Asn1Tag.Enumerated), value);
    }

    /// An `OBJECT IDENTIFIER`, from its dotted form.
    ///
    /// @param dotted  the identifier, as `1.2.840.113549`
    /// @param tag     the tag in place of `OBJECT IDENTIFIER`
    /// @returns `AsnError.None`, or why `dotted` is not an identifier
    /// @see Oid.FromDottedString
    public AsnError WriteObjectIdentifier(
        String dotted, Optional<Asn1Tag> tag = default(Optional<Asn1Tag>))
    {
        var contents = Oid.FromDottedString(dotted);
        if (!contents.Ok)
            return contents.Error;
        WritePrimitiveHeader(tag, Asn1Tag.ObjectIdentifier, contents.Value.Length);
        AppendSpan(contents.Value);
        return AsnError.None;
    }

    // --------------------------------------------------------------- strings

    /// A `BIT STRING` of `value`, the last `unusedBitCount` bits of which are
    /// not part of it.
    ///
    /// @param value           the octets
    /// @param unusedBitCount  zero to seven
    /// @param tag             the tag in place of `BIT STRING`
    /// @returns `AsnError.OutOfRange` for more than seven unused bits,
    ///          `AsnError.Malformed` for unused bits and no octet, and
    ///          `AsnError.NonMinimalEncoding` when an unused bit is not zero
    public AsnError WriteBitString(ReadOnlySpan<byte> value, int unusedBitCount = 0,
                                   Optional<Asn1Tag> tag = default(Optional<Asn1Tag>))
    {
        if (unusedBitCount < 0 || unusedBitCount > 7)
            return AsnError.OutOfRange;
        if (unusedBitCount > 0)
        {
            if (value.Length == 0u)
                return AsnError.Malformed;
            uint mask = (1u << (uint)unusedBitCount) - 1u;
            if (((uint)value[value.Length - 1u] & mask) != 0u)
                return AsnError.NonMinimalEncoding;
        }

        WritePrimitiveHeader(tag, Asn1Tag.PrimitiveBitString, value.Length + 1u);
        AppendByte((byte)unusedBitCount);
        AppendSpan(value);
        return AsnError.None;
    }

    /// An `OCTET STRING`.
    ///
    /// @param value  the octets
    /// @param tag    the tag in place of `OCTET STRING`
    public void WriteOctetString(
        ReadOnlySpan<byte> value, Optional<Asn1Tag> tag = default(Optional<Asn1Tag>))
    {
        WritePrimitiveHeader(tag, Asn1Tag.PrimitiveOctetString, value.Length);
        AppendSpan(value);
    }

    /// A character string of type `encodingType`, from text.
    ///
    /// The types and what each may hold are `AsnReader.ReadCharacterString`'s.
    ///
    /// @param encodingType  which character string type
    /// @param text          what to write
    /// @param tag           the tag in place of `encodingType`'s own
    /// @returns `AsnError.BadStringContent` for a character the type cannot
    ///          hold, `AsnError.Unsupported` for a type that is not a
    ///          character string
    public AsnError WriteCharacterString(UniversalTagNumber encodingType, String text,
                                         Optional<Asn1Tag> tag = default(Optional<Asn1Tag>))
    {
        if (!IsCharacterStringType(encodingType))
            return AsnError.Unsupported;

        var contents = EncodeCharacterString(encodingType, text.ToBytes());
        if (!contents.Ok)
            return contents.Error;
        WritePrimitiveHeader(tag, new Asn1Tag(encodingType), contents.Value.Length);
        AppendSpan(contents.Value);
        return AsnError.None;
    }

    // ----------------------------------------------------------------- times

    /// A `UTCTime`, as `YYMMDDhhmmssZ`.
    ///
    /// @param seconds  seconds since 1970-01-01 UTC
    /// @param tag      the tag in place of `UTCTime`
    /// @returns `AsnError.OutOfRange` when the year is outside 1950 to 2049
    /// @see AsnWriter.WriteGeneralizedTime
    public AsnError WriteUtcTime(long seconds, Optional<Asn1Tag> tag = default(Optional<Asn1Tag>))
    {
        var text = FormatAsnTime(seconds, false);
        if (!text.Ok)
            return text.Error;
        WritePrimitiveHeader(tag, Asn1Tag.UtcTime, text.Value.Length);
        AppendSpan(text.Value);
        return AsnError.None;
    }

    /// A `GeneralizedTime`, as `YYYYMMDDhhmmssZ`.
    ///
    /// @param seconds  seconds since 1970-01-01 UTC
    /// @param tag      the tag in place of `GeneralizedTime`
    /// @returns `AsnError.OutOfRange` when the year is outside 0000 to 9999
    /// @see AsnWriter.WriteUtcTime
    public AsnError WriteGeneralizedTime(
        long seconds, Optional<Asn1Tag> tag = default(Optional<Asn1Tag>))
    {
        var text = FormatAsnTime(seconds, true);
        if (!text.Ok)
            return text.Error;
        WritePrimitiveHeader(tag, Asn1Tag.GeneralizedTime, text.Value.Length);
        AppendSpan(text.Value);
        return AsnError.None;
    }

    // --------------------------------------------------------------- private

    private void WriteSigned(Asn1Tag tag, long value)
    {
        byte[8] octets;
        ulong bits = (ulong)value;
        for (nuint i = 0u; i < 8u; i++)
            octets[i] = (byte)((bits >> (uint)(8u * (7u - i))) & 0xFFu);

        nuint start = 0u;
        while (start < 7u)
        {
            uint first = (uint)octets[start];
            uint next = (uint)octets[start + 1u] & 0x80u;
            if ((first == 0x00u && next == 0u) || (first == 0xFFu && next != 0u))
            {
                start++;
            }
            else
            {
                break;
            }
        }

        WriteHeader(tag.AsPrimitive(), 8u - start);
        for (nuint i = start; i < 8u; i++)
            AppendByte(octets[i]);
    }

    /// `octets`, whose first element is a zero pad, cut to the fewest that
    /// still read as the same non-negative value.
    private static byte[] TrimUnsignedMagnitude(ReadOnlySpan<byte> octets)
    {
        nuint start = 0u;
        while (start + 1u < octets.Length && octets[start] == 0x00 &&
               (octets[start + 1u] & 0x80) == 0)
        {
            start++;
        }
        return octets[start:].ToArray();
    }

    private void OpenScope(Asn1Tag tag, bool isSetOf)
    {
        WriteTag(tag.AsConstructed());
        AppendByte(0);

        if (_depth == _scopeStarts.Length)
        {
            var starts = new nuint[_depth * 2u];
            var kinds = new bool[_depth * 2u];
            for (nuint i = 0u; i < _depth; i++)
            {
                starts[i] = _scopeStarts[i];
                kinds[i] = _scopeIsSetOf[i];
            }
            _scopeStarts = starts;
            _scopeIsSetOf = kinds;
        }

        _scopeStarts[_depth] = _length;
        _scopeIsSetOf[_depth] = isSetOf;
        _depth++;
    }

    private void CloseScope(bool isSetOf)
    {
        if (_depth == 0u)
            sl_fail("AsnWriter: a Pop with nothing open");
        if (_scopeIsSetOf[_depth - 1u] != isSetOf)
            sl_fail("AsnWriter: PopSequence MUST close PushSequence, and PopSetOf PushSetOf");

        _depth--;
        nuint start = _scopeStarts[_depth];
        nuint contentLength = _length - start;
        if (isSetOf)
            SortSetOfElements(start, _length);

        if (contentLength < 0x80u)
        {
            _buffer[start - 1u] = (byte)contentLength;
            return;
        }

        nuint extra = CountLengthOctets(contentLength);
        EnsureCapacity(_length + extra);
        for (nuint i = _length; i > start; i--)
            _buffer[i - 1u + extra] = _buffer[i - 1u];
        _length += extra;

        _buffer[start - 1u] = (byte)(0x80u | (uint)extra);
        for (nuint i = 0u; i < extra; i++)
            _buffer[start + i] = (byte)((contentLength >> (uint)(8u * (extra - 1u - i))) & 0xFFu);
    }

    /// X.690 §11.6: the elements in ascending order of their encodings, a
    /// shorter one compared as though padded with zeros.
    private void SortSetOfElements(nuint start, nuint end)
    {
        nuint count = 0u;
        nuint at = start;
        while (at < end)
        {
            var remaining = new ReadOnlySpan<byte>(_buffer, at, end - at);
            var header = AsnReader.DecodeHeader(remaining, AsnEncodingRules.Der);
            if (!header.Ok)
            {
                sl_fail("AsnWriter: a SET OF holds something that is not a value");
                return;
            }
            at += header.Value.TotalLength;
            count++;
        }

        if (count < 2u)
            return;

        var offsets = new nuint[count];
        var lengths = new nuint[count];
        at = start;
        for (nuint i = 0u; i < count; i++)
        {
            var remaining = new ReadOnlySpan<byte>(_buffer, at, end - at);
            var header = AsnReader.DecodeHeader(remaining, AsnEncodingRules.Der);
            if (!header.Ok)
            {
                sl_fail("AsnWriter: a SET OF holds something that is not a value");
                return;
            }
            offsets[i] = at;
            lengths[i] = header.Value.TotalLength;
            at += lengths[i];
        }

        for (nuint i = 1u; i < count; i++)
        {
            nuint offset = offsets[i];
            nuint length = lengths[i];
            nuint j = i;
            while (j > 0u &&
                   CompareSetOfElements(offsets[j - 1u], lengths[j - 1u], offset, length) > 0)
            {
                offsets[j] = offsets[j - 1u];
                lengths[j] = lengths[j - 1u];
                j--;
            }
            offsets[j] = offset;
            lengths[j] = length;
        }

        var sorted = new byte[end - start];
        nuint written = 0u;
        for (nuint i = 0u; i < count; i++)
        {
            for (nuint k = 0u; k < lengths[i]; k++)
                sorted[written + k] = _buffer[offsets[i] + k];
            written += lengths[i];
        }
        for (nuint i = 0u; i < sorted.Length; i++)
            _buffer[start + i] = sorted[i];
    }

    private int CompareSetOfElements(nuint left, nuint leftLength, nuint right, nuint rightLength)
    {
        nuint longest = leftLength > rightLength ? leftLength : rightLength;
        for (nuint i = 0u; i < longest; i++)
        {
            uint a = i < leftLength ? (uint)_buffer[left + i] : 0u;
            uint b = i < rightLength ? (uint)_buffer[right + i] : 0u;
            if (a != b)
                return a < b ? -1 : 1;
        }
        return 0;
    }

    private void WritePrimitiveHeader(Optional<Asn1Tag> tag, Asn1Tag universal, nuint contentLength)
    {
        WriteHeader(tag.GetValueOrDefault(universal).AsPrimitive(), contentLength);
    }

    private void WriteHeader(Asn1Tag tag, nuint contentLength)
    {
        WriteTag(tag);
        WriteLength(contentLength);
    }

    private void WriteTag(Asn1Tag tag)
    {
        uint first = (uint)(int)tag.TagClass;
        if (tag.IsConstructed)
            first |= 0x20u;

        uint number = (uint)tag.TagValue;
        if (number < 0x1Fu)
        {
            AppendByte((byte)(first | number));
            return;
        }

        AppendByte((byte)(first | 0x1Fu));
        nuint octets = Oid.CountBase128Octets((ulong)number);
        for (nuint i = 0u; i < octets; i++)
        {
            uint septet = (number >> (uint)(7u * (octets - 1u - i))) & 0x7Fu;
            if (i + 1u < octets)
                septet |= 0x80u;
            AppendByte((byte)septet);
        }
    }

    private void WriteLength(nuint length)
    {
        if (length < 0x80u)
        {
            AppendByte((byte)length);
            return;
        }

        nuint octets = CountLengthOctets(length);
        AppendByte((byte)(0x80u | (uint)octets));
        for (nuint i = 0u; i < octets; i++)
            AppendByte((byte)((length >> (uint)(8u * (octets - 1u - i))) & 0xFFu));
    }

    private static nuint CountLengthOctets(nuint length)
    {
        nuint octets = 0u;
        while (length > 0u)
        {
            octets++;
            length >>= 8;
        }
        return octets;
    }

    private void EnsureCapacity(nuint needed)
    {
        if (needed <= _buffer.Length)
            return;

        nuint capacity = _buffer.Length * 2u;
        if (capacity < needed)
            capacity = needed;
        var grown = new byte[capacity];
        for (nuint i = 0u; i < _length; i++)
            grown[i] = _buffer[i];
        _buffer = grown;
    }

    private void AppendByte(byte value)
    {
        EnsureCapacity(_length + 1u);
        _buffer[_length] = value;
        _length++;
    }

    private void AppendSpan(ReadOnlySpan<byte> values)
    {
        EnsureCapacity(_length + values.Length);
        for (nuint i = 0u; i < values.Length; i++)
            _buffer[_length + i] = values[i];
        _length += values.Length;
    }
}

/// The contents of a character string of `type` holding the UTF-8 `text`.
Result<byte[], AsnError> EncodeCharacterString(UniversalTagNumber type, byte[] text)
{
    ReadOnlySpan<byte> view = text;
    nuint count = 0u;
    nuint at = 0u;
    while (at < text.Length)
    {
        int scalar = DecodeUtf8ScalarAt(view, at, out nuint width);
        if (scalar < 0)
            return Fail(AsnError.BadStringContent);
        at += width;
        count++;
    }

    switch (type)
    {
        case UniversalTagNumber.Utf8String:
            return Ok(text);

        case UniversalTagNumber.T61String:
        case UniversalTagNumber.BmpString:
        case UniversalTagNumber.UniversalString:
        {
            nuint unit = 1u;
            uint limit = 0xFFu;
            if (type == UniversalTagNumber.BmpString)
            {
                unit = 2u;
                limit = 0xFFFFu;
            }
            else if (type == UniversalTagNumber.UniversalString)
            {
                unit = 4u;
                limit = 0x10FFFFu;
            }

            var contents = new byte[count * unit];
            at = 0u;
            nuint written = 0u;
            while (at < text.Length)
            {
                uint scalar = (uint)DecodeUtf8ScalarAt(view, at, out nuint width);
                at += width;
                if (scalar > limit)
                    return Fail(AsnError.BadStringContent);
                for (nuint i = 0u; i < unit; i++)
                {
                    uint shift = (uint)(8u * (unit - 1u - i));
                    contents[written + i] = (byte)((scalar >> shift) & 0xFFu);
                }
                written += unit;
            }
            return Ok(contents);
        }

        default:
            for (nuint i = 0u; i < text.Length; i++)
            {
                if (!IsAllowedInAsciiString(type, (uint)text[i]))
                    return Fail(AsnError.BadStringContent);
            }
            return Ok(text);
    }
}

/// `seconds` as the text of a `GeneralizedTime`, or of a `UTCTime` when
/// `fourDigitYear` is false.
Result<byte[], AsnError> FormatAsnTime(long seconds, bool fourDigitYear)
{
    // The day is floored, so a moment before the epoch still has its time of
    // day counted forward from midnight.
    long days = seconds / 86400;
    long within = seconds % 86400;
    if (within < 0)
    {
        within += 86400;
        days--;
    }

    var (year, month, day) = ConvertDaysToCivil(days);
    if (fourDigitYear)
    {
        if (year < 0 || year > 9999)
            return Fail(AsnError.OutOfRange);
    }
    else
    {
        if (year < 1950 || year > 2049)
            return Fail(AsnError.OutOfRange);
    }

    nuint width = fourDigitYear ? 15u : 13u;
    var text = new byte[width];
    nuint at = 0u;
    if (fourDigitYear)
    {
        WriteAsnDigits(text, at, year, 4u);
        at += 4;
    }
    else
    {
        WriteAsnDigits(text, at, year % 100, 2u);
        at += 2;
    }

    WriteAsnDigits(text, at, month, 2u);
    WriteAsnDigits(text, at + 2u, day, 2u);
    WriteAsnDigits(text, at + 4u, within / 3600, 2u);
    WriteAsnDigits(text, at + 6u, within / 60 % 60, 2u);
    WriteAsnDigits(text, at + 8u, within % 60, 2u);
    text[width - 1u] = 90;                                          // 'Z'
    return Ok(text);
}

void WriteAsnDigits(byte[] into, nuint at, long value, nuint count)
{
    for (nuint i = count; i > 0u; i--)
    {
        into[at + i - 1u] = (byte)(48 + value % 10);
        value /= 10;
    }
}
