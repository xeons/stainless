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

import Standard.Time;

/// Reads encoded values one after another from a run of bytes.
///
/// ```csharp
/// var reader = new AsnReader(der, AsnEncodingRules.Der);
/// var sequence = try reader.ReadSequence();
/// long version = try sequence.ReadInt64();
/// String algorithm = try sequence.ReadObjectIdentifier();
/// if (sequence.VerifyEndOfData() != AsnError.None) { ... }
/// ```
///
/// **A failed read does not move the reader.** Each read decodes and checks
/// the whole value before it steps past it, so after a failure the same value
/// is next.
///
/// **Implicit tagging is the optional `expectedTag`.** Every typed read takes
/// one, and matches the next value's class and number against it in place of
/// the type's universal tag. Explicit tagging is a constructed value holding
/// the real one, and `ReadSequence` with the context tag opens it:
///
/// ```csharp
/// var wrapper = try tbs.ReadSequence(new Asn1Tag(TagClass.ContextSpecific, 0, true));
/// long version = try wrapper.ReadInt64();
/// ```
///
/// The reader holds a view of the caller's array, not a copy. What it hands
/// back as a `ReadOnlySpan<byte>` is a view of the same array.
public sealed class AsnReader
{
    private ReadOnlySpan<byte> _data;
    private AsnEncodingRules _ruleSet;

    /// A reader over `data`, which is not examined until something is read.
    ///
    /// @param data     one or more encoded values
    /// @param ruleSet  the rules every value is held to
    public AsnReader(ReadOnlySpan<byte> data, AsnEncodingRules ruleSet)
    {
        _data = data;
        _ruleSet = ruleSet;
    }

    /// The rules every value is held to.
    public AsnEncodingRules RuleSet => _ruleSet;

    /// Whether anything is left to read.
    public bool HasData => _data.Length > 0u;

    // ------------------------------------------------------------ structure

    /// The tag of the next value, without moving.
    ///
    /// @failure AsnError.Truncated           the input ends inside the tag
    /// @failure AsnError.NonMinimalEncoding  a tag number in more octets than it needs
    /// @failure AsnError.OutOfRange          a tag number past the largest `int`
    public Result<Asn1Tag, AsnError> PeekTag()
    {
        var header = DecodeTag(_data, out nuint length);
        if (!header.Ok)
            return Fail(header.Error);
        return Ok(header.Value);
    }

    /// The whole of the next value — tag, length and contents — without
    /// moving.
    ///
    /// @failure AsnError.Truncated  the input ends inside the value
    /// @failure AsnError.BadLength  the length octets are malformed
    /// @see AsnReader.ReadEncodedValue
    public Result<ReadOnlySpan<byte>, AsnError> PeekEncodedValue()
    {
        var header = DecodeHeader(_data, _ruleSet);
        if (!header.Ok)
            return Fail(header.Error);
        return Ok(_data[:header.Value.TotalLength]);
    }

    /// The whole of the next value — tag, length and contents — and past it.
    ///
    /// The tag and the length are checked; the contents are not looked at.
    /// This is how to keep the exact bytes a signature covers.
    ///
    /// @failure AsnError.Truncated    the input ends inside the value
    /// @failure AsnError.BadLength    the length octets are malformed
    /// @failure AsnError.Unsupported  an indefinite length
    public Result<ReadOnlySpan<byte>, AsnError> ReadEncodedValue()
    {
        var header = DecodeHeader(_data, _ruleSet);
        if (!header.Ok)
            return Fail(header.Error);
        nuint total = header.Value.TotalLength;
        var encoded = _data[:total];
        _data = _data[total:];
        return Ok(encoded);
    }

    /// A reader over the contents of the next `SEQUENCE`, and past it.
    ///
    /// @param expectedTag  the tag in place of `SEQUENCE`, for implicit or explicit tagging
    /// @failure AsnError.UnexpectedTag  the next value is not a constructed value with that tag
    /// @failure AsnError.Truncated      the input ends inside the value
    /// @see AsnReader.ReadSetOf
    public Result<AsnReader, AsnError> ReadSequence(
        Optional<Asn1Tag> expectedTag = default(Optional<Asn1Tag>))
    {
        return ReadConstructed(Asn1Tag.Sequence, expectedTag);
    }

    /// A reader over the contents of the next `SET OF`, and past it.
    ///
    /// **The order of the elements is not checked**, although DER requires
    /// them sorted; see the module's summary.
    ///
    /// @param expectedTag  the tag in place of `SET`
    /// @failure AsnError.UnexpectedTag  the next value is not a constructed value with that tag
    /// @failure AsnError.Truncated      the input ends inside the value
    /// @see AsnReader.ReadSequence
    public Result<AsnReader, AsnError> ReadSetOf(
        Optional<Asn1Tag> expectedTag = default(Optional<Asn1Tag>))
    {
        return ReadConstructed(Asn1Tag.SetOf, expectedTag);
    }

    /// `AsnError.None` when everything has been read, and
    /// `AsnError.TrailingData` when something has not.
    ///
    /// A format MUST call this on each reader it has finished with; a value
    /// with something after it is not the value that was signed.
    public AsnError VerifyEndOfData()
    {
        if (_data.Length > 0u)
            return AsnError.TrailingData;
        return AsnError.None;
    }

    // --------------------------------------------------------------- scalars

    /// The next `BOOLEAN`.
    ///
    /// @param expectedTag  the tag in place of `BOOLEAN`
    /// @failure AsnError.UnexpectedTag       the next value has another tag
    /// @failure AsnError.BadLength           the contents are not one octet
    /// @failure AsnError.NonMinimalEncoding  under DER, an octet other than `0x00` or `0xFF`
    public Result<bool, AsnError> ReadBoolean(
        Optional<Asn1Tag> expectedTag = default(Optional<Asn1Tag>))
    {
        var header = ReadPrimitiveHeader(Asn1Tag.Boolean, expectedTag);
        if (!header.Ok)
            return Fail(header.Error);
        var contents = ContentsOf(header.Value);
        if (contents.Length != 1u)
            return Fail(AsnError.BadLength);

        byte value = contents[0u];
        if (_ruleSet == AsnEncodingRules.Der && value != 0x00 && value != 0xFF)
            return Fail(AsnError.NonMinimalEncoding);

        SkipValue(header.Value);
        return Ok(value != 0x00);
    }

    /// The next `NULL`.
    ///
    /// @param expectedTag  the tag in place of `NULL`
    /// @returns `AsnError.None`, or why the next value is not a `NULL`
    public AsnError ReadNull(Optional<Asn1Tag> expectedTag = default(Optional<Asn1Tag>))
    {
        var header = ReadPrimitiveHeader(Asn1Tag.Null, expectedTag);
        if (!header.Ok)
            return header.Error;
        if (header.Value.ContentLength != 0u)
            return AsnError.BadLength;
        SkipValue(header.Value);
        return AsnError.None;
    }

    /// The contents of the next `INTEGER`: two's complement, big-endian, in
    /// the fewest octets that hold it.
    ///
    /// What a key's modulus or a certificate's serial number is read with,
    /// since neither fits a `long`.
    ///
    /// @param expectedTag  the tag in place of `INTEGER`
    /// @failure AsnError.UnexpectedTag       the next value has another tag
    /// @failure AsnError.BadLength           there are no contents
    /// @failure AsnError.NonMinimalEncoding  a leading `0x00` or `0xFF` that says nothing
    /// @see AsnReader.ReadInt64
    public Result<ReadOnlySpan<byte>, AsnError> ReadIntegerBytes(
        Optional<Asn1Tag> expectedTag = default(Optional<Asn1Tag>))
    {
        return ReadIntegerContents(Asn1Tag.Integer, expectedTag);
    }

    /// The next `INTEGER`, as a `long`.
    ///
    /// @param expectedTag  the tag in place of `INTEGER`
    /// @failure AsnError.UnexpectedTag       the next value has another tag
    /// @failure AsnError.BadLength           there are no contents
    /// @failure AsnError.NonMinimalEncoding  a leading `0x00` or `0xFF` that says nothing
    /// @failure AsnError.OutOfRange          the value does not fit a `long`
    /// @see AsnReader.ReadUInt64
    public Result<long, AsnError> ReadInt64(
        Optional<Asn1Tag> expectedTag = default(Optional<Asn1Tag>))
    {
        return ReadSigned(Asn1Tag.Integer, expectedTag);
    }

    /// The next `INTEGER`, as a `ulong`.
    ///
    /// @param expectedTag  the tag in place of `INTEGER`
    /// @failure AsnError.UnexpectedTag       the next value has another tag
    /// @failure AsnError.BadLength           there are no contents
    /// @failure AsnError.NonMinimalEncoding  a leading `0x00` or `0xFF` that says nothing
    /// @failure AsnError.OutOfRange          the value is negative or does not fit a `ulong`
    /// @see AsnReader.ReadInt64
    public Result<ulong, AsnError> ReadUInt64(
        Optional<Asn1Tag> expectedTag = default(Optional<Asn1Tag>))
    {
        var header = ReadPrimitiveHeader(Asn1Tag.Integer, expectedTag);
        if (!header.Ok)
            return Fail(header.Error);
        var contents = ContentsOf(header.Value);
        AsnError shape = CheckIntegerContents(contents);
        if (shape != AsnError.None)
            return Fail(shape);

        if ((contents[0u] & 0x80) != 0)
            return Fail(AsnError.OutOfRange);
        if (contents.Length > 9u || (contents.Length == 9u && contents[0u] != 0x00))
            return Fail(AsnError.OutOfRange);

        ulong value = 0u;
        for (nuint i = 0u; i < contents.Length; i++)
            value = (value << 8) | (ulong)contents[i];

        SkipValue(header.Value);
        return Ok(value);
    }

    /// The next `ENUMERATED`, as a `long`.
    ///
    /// @param expectedTag  the tag in place of `ENUMERATED`
    /// @failure AsnError.UnexpectedTag       the next value has another tag
    /// @failure AsnError.BadLength           there are no contents
    /// @failure AsnError.NonMinimalEncoding  a leading `0x00` or `0xFF` that says nothing
    /// @failure AsnError.OutOfRange          the value does not fit a `long`
    public Result<long, AsnError> ReadEnumeratedValue(
        Optional<Asn1Tag> expectedTag = default(Optional<Asn1Tag>))
    {
        return ReadSigned(Asn1Tag.Enumerated, expectedTag);
    }

    /// The next `OBJECT IDENTIFIER`, dotted: `1.2.840.113549`.
    ///
    /// @param expectedTag  the tag in place of `OBJECT IDENTIFIER`
    /// @failure AsnError.UnexpectedTag       the next value has another tag
    /// @failure AsnError.BadLength           there are no contents
    /// @failure AsnError.NonMinimalEncoding  an arc padded with a leading `0x80`
    /// @failure AsnError.Malformed           the last arc does not end
    /// @failure AsnError.OutOfRange          an arc does not fit a `ulong`
    /// @see Oid.ToDottedString
    public Result<String, AsnError> ReadObjectIdentifier(
        Optional<Asn1Tag> expectedTag = default(Optional<Asn1Tag>))
    {
        var header = ReadPrimitiveHeader(Asn1Tag.ObjectIdentifier, expectedTag);
        if (!header.Ok)
            return Fail(header.Error);
        var dotted = Oid.ToDottedString(ContentsOf(header.Value));
        if (!dotted.Ok)
            return Fail(dotted.Error);
        SkipValue(header.Value);
        return Ok(dotted.Value);
    }

    // --------------------------------------------------------------- strings

    /// The next `BIT STRING`: its octets, and in `unusedBitCount` how many
    /// bits at the end of the last one are not part of the value.
    ///
    /// @param unusedBitCount  zero to seven; zero when the read fails
    /// @param expectedTag     the tag in place of `BIT STRING`
    /// @failure AsnError.UnexpectedTag       the next value has another tag
    /// @failure AsnError.BadLength           there are no contents at all
    /// @failure AsnError.Malformed           more than seven unused bits, or unused bits with
    ///                                       no octet to hold them
    /// @failure AsnError.NonMinimalEncoding  under DER, an unused bit that is not zero, or the
    ///                                       constructed form
    /// @failure AsnError.Unsupported         under BER, the constructed form
    public Result<ReadOnlySpan<byte>, AsnError> ReadBitString(out int unusedBitCount,
        Optional<Asn1Tag> expectedTag = default(Optional<Asn1Tag>))
    {
        unusedBitCount = 0;
        var header = ReadStringHeader(Asn1Tag.PrimitiveBitString, expectedTag);
        if (!header.Ok)
            return Fail(header.Error);
        var contents = ContentsOf(header.Value);
        if (contents.Length == 0u)
            return Fail(AsnError.BadLength);

        uint unused = (uint)contents[0u];
        if (unused > 7u || (unused > 0u && contents.Length == 1u))
            return Fail(AsnError.Malformed);

        if (_ruleSet == AsnEncodingRules.Der && unused > 0u)
        {
            uint mask = (1u << unused) - 1u;
            if (((uint)contents[contents.Length - 1u] & mask) != 0u)
                return Fail(AsnError.NonMinimalEncoding);
        }

        SkipValue(header.Value);
        unusedBitCount = (int)unused;
        return Ok(contents[1u:]);
    }

    /// The contents of the next `OCTET STRING`.
    ///
    /// @param expectedTag  the tag in place of `OCTET STRING`
    /// @failure AsnError.UnexpectedTag       the next value has another tag
    /// @failure AsnError.NonMinimalEncoding  under DER, the constructed form
    /// @failure AsnError.Unsupported         under BER, the constructed form
    public Result<ReadOnlySpan<byte>, AsnError> ReadOctetString(
        Optional<Asn1Tag> expectedTag = default(Optional<Asn1Tag>))
    {
        var header = ReadStringHeader(Asn1Tag.PrimitiveOctetString, expectedTag);
        if (!header.Ok)
            return Fail(header.Error);
        var contents = ContentsOf(header.Value);
        SkipValue(header.Value);
        return Ok(contents);
    }

    /// The next character string of type `encodingType`, as text.
    ///
    /// | Type | What it may hold |
    /// |---|---|
    /// | `Utf8String` | well-formed UTF-8 |
    /// | `PrintableString` | letters, digits, space and `'()+,-./:=?` |
    /// | `IA5String` | ASCII, `0x00` to `0x7F` |
    /// | `VisibleString` | printable ASCII, `0x20` to `0x7E` |
    /// | `NumericString` | digits and space |
    /// | `T61String` | any octet, read as Latin-1 |
    /// | `BmpString` | UCS-2 big-endian, no surrogates |
    /// | `UniversalString` | UCS-4 big-endian, scalar values only |
    ///
    /// @param encodingType  which of the types above
    /// @param expectedTag   the tag in place of `encodingType`'s own
    /// @failure AsnError.UnexpectedTag       the next value has another tag
    /// @failure AsnError.BadStringContent    a character the type does not allow
    /// @failure AsnError.NonMinimalEncoding  under DER, the constructed form
    /// @failure AsnError.Unsupported         `encodingType` is not in the table, or under BER
    ///                                       the constructed form
    public Result<String, AsnError> ReadCharacterString(UniversalTagNumber encodingType,
        Optional<Asn1Tag> expectedTag = default(Optional<Asn1Tag>))
    {
        if (!IsCharacterStringType(encodingType))
            return Fail(AsnError.Unsupported);

        var header = ReadStringHeader(new Asn1Tag(encodingType), expectedTag);
        if (!header.Ok)
            return Fail(header.Error);

        var text = DecodeCharacterString(encodingType, ContentsOf(header.Value));
        if (!text.Ok)
            return Fail(text.Error);
        SkipValue(header.Value);
        return Ok(text.Value);
    }

    // ----------------------------------------------------------------- times

    /// The next `UTCTime`, as seconds since 1970-01-01 UTC.
    ///
    /// The year has two digits and RFC 5280 says which century: `50` to `99`
    /// are 1950 to 1999, and `00` to `49` are 2000 to 2049. DER requires
    /// `YYMMDDhhmmssZ` exactly; BER also accepts no seconds and an offset of
    /// `+hhmm` or `-hhmm` in place of the `Z`.
    ///
    /// @param expectedTag  the tag in place of `UTCTime`
    /// @failure AsnError.UnexpectedTag  the next value has another tag
    /// @failure AsnError.BadTime        not the form the rules require, or not a real moment
    /// @see ConvertAsnTimeToDateTimeOffset
    public Result<long, AsnError> ReadUtcTime(
        Optional<Asn1Tag> expectedTag = default(Optional<Asn1Tag>))
    {
        var header = ReadStringHeader(Asn1Tag.UtcTime, expectedTag);
        if (!header.Ok)
            return Fail(header.Error);
        var seconds = ParseUtcTime(ContentsOf(header.Value), _ruleSet);
        if (!seconds.Ok)
            return Fail(seconds.Error);
        SkipValue(header.Value);
        return Ok(seconds.Value);
    }

    /// The next `GeneralizedTime`, as seconds since 1970-01-01 UTC.
    ///
    /// DER requires `YYYYMMDDhhmmssZ`, optionally with a fraction of a second
    /// after a `.` that does not end in `0`. BER also accepts a `,`, the
    /// minutes and seconds left off, and an offset in place of the `Z`.
    /// **The fraction is checked and dropped**, since the answer is whole
    /// seconds; RFC 5280 forbids one in a certificate anyway.
    ///
    /// @param expectedTag  the tag in place of `GeneralizedTime`
    /// @failure AsnError.UnexpectedTag  the next value has another tag
    /// @failure AsnError.BadTime        not the form the rules require, or not a real moment
    /// @failure AsnError.Unsupported    under BER, a local time with no zone, or a fraction
    ///                                  of an hour or a minute
    /// @see ConvertAsnTimeToDateTimeOffset
    public Result<long, AsnError> ReadGeneralizedTime(
        Optional<Asn1Tag> expectedTag = default(Optional<Asn1Tag>))
    {
        var header = ReadStringHeader(Asn1Tag.GeneralizedTime, expectedTag);
        if (!header.Ok)
            return Fail(header.Error);
        var seconds = ParseGeneralizedTime(ContentsOf(header.Value), _ruleSet);
        if (!seconds.Ok)
            return Fail(seconds.Error);
        SkipValue(header.Value);
        return Ok(seconds.Value);
    }

    // --------------------------------------------------------------- private

    private ReadOnlySpan<byte> ContentsOf(AsnHeader header) =>
        _data[header.HeaderLength:header.TotalLength];

    private void SkipValue(AsnHeader header)
    {
        _data = _data[header.TotalLength:];
    }

    private Result<AsnReader, AsnError> ReadConstructed(
        Asn1Tag universal, Optional<Asn1Tag> expectedTag)
    {
        var header = DecodeHeader(_data, _ruleSet);
        if (!header.Ok)
            return Fail(header.Error);

        Asn1Tag want = expectedTag.GetValueOrDefault(universal);
        Asn1Tag found = header.Value.Tag;
        if (!found.HasSameClassAndValue(want) || !found.IsConstructed)
            return Fail(AsnError.UnexpectedTag);

        var nested = new AsnReader(ContentsOf(header.Value), _ruleSet);
        SkipValue(header.Value);
        return Ok(nested);
    }

    /// The next value's header, when its tag matches and it is primitive.
    private Result<AsnHeader, AsnError> ReadPrimitiveHeader(
        Asn1Tag universal, Optional<Asn1Tag> expectedTag)
    {
        var header = DecodeHeader(_data, _ruleSet);
        if (!header.Ok)
            return Fail(header.Error);

        Asn1Tag want = expectedTag.GetValueOrDefault(universal);
        Asn1Tag found = header.Value.Tag;
        if (!found.HasSameClassAndValue(want) || found.IsConstructed)
            return Fail(AsnError.UnexpectedTag);
        return Ok(header.Value);
    }

    /// The same for a string type, whose constructed form BER allows and this
    /// reader does not assemble.
    private Result<AsnHeader, AsnError> ReadStringHeader(
        Asn1Tag universal, Optional<Asn1Tag> expectedTag)
    {
        var header = DecodeHeader(_data, _ruleSet);
        if (!header.Ok)
            return Fail(header.Error);

        Asn1Tag want = expectedTag.GetValueOrDefault(universal);
        Asn1Tag found = header.Value.Tag;
        if (!found.HasSameClassAndValue(want))
            return Fail(AsnError.UnexpectedTag);

        if (found.IsConstructed)
        {
            if (_ruleSet == AsnEncodingRules.Der)
                return Fail(AsnError.NonMinimalEncoding);
            return Fail(AsnError.Unsupported);
        }
        return Ok(header.Value);
    }

    private Result<ReadOnlySpan<byte>, AsnError> ReadIntegerContents(
        Asn1Tag universal, Optional<Asn1Tag> expectedTag)
    {
        var header = ReadPrimitiveHeader(universal, expectedTag);
        if (!header.Ok)
            return Fail(header.Error);
        var contents = ContentsOf(header.Value);
        AsnError shape = CheckIntegerContents(contents);
        if (shape != AsnError.None)
            return Fail(shape);
        SkipValue(header.Value);
        return Ok(contents);
    }

    private Result<long, AsnError> ReadSigned(Asn1Tag universal, Optional<Asn1Tag> expectedTag)
    {
        var header = ReadPrimitiveHeader(universal, expectedTag);
        if (!header.Ok)
            return Fail(header.Error);
        var contents = ContentsOf(header.Value);
        AsnError shape = CheckIntegerContents(contents);
        if (shape != AsnError.None)
            return Fail(shape);
        if (contents.Length > 8u)
            return Fail(AsnError.OutOfRange);

        ulong value = (contents[0u] & 0x80) != 0 ? 18446744073709551615u : 0u;
        for (nuint i = 0u; i < contents.Length; i++)
            value = (value << 8) | (ulong)contents[i];

        SkipValue(header.Value);
        return Ok((long)value);
    }

    /// X.690 §8.3.2: the first nine bits are never all the same. That holds
    /// under every rule set, not only DER.
    private static AsnError CheckIntegerContents(ReadOnlySpan<byte> contents)
    {
        if (contents.Length == 0u)
            return AsnError.BadLength;
        if (contents.Length > 1u)
        {
            uint first = (uint)contents[0u];
            uint second = (uint)contents[1u] & 0x80u;
            if ((first == 0x00u && second == 0u) || (first == 0xFFu && second != 0u))
                return AsnError.NonMinimalEncoding;
        }
        return AsnError.None;
    }

    // ----------------------------------------------------------- the header

    /// The tag at the start of `data`, and in `length` how many octets it took.
    static Result<Asn1Tag, AsnError> DecodeTag(ReadOnlySpan<byte> data, out nuint length)
    {
        length = 0u;
        if (data.Length == 0u)
            return Fail(AsnError.Truncated);

        uint first = (uint)data[0u];
        var tagClass = (TagClass)(int)(first & 0xC0u);
        bool constructed = (first & 0x20u) != 0u;
        uint number = first & 0x1Fu;
        nuint at = 1u;

        if (number == 0x1Fu)
        {
            number = 0u;
            while (true)
            {
                if (at >= data.Length)
                    return Fail(AsnError.Truncated);
                uint octet = (uint)data[at];
                at++;
                if (number == 0u && octet == 0x80u)
                    return Fail(AsnError.NonMinimalEncoding);
                if (number > (0x7FFFFFFFu >> 7))
                    return Fail(AsnError.OutOfRange);
                number = (number << 7) | (octet & 0x7Fu);
                if ((octet & 0x80u) == 0u)
                    break;
            }

            if (number < 0x1Fu)
                return Fail(AsnError.NonMinimalEncoding);
        }

        length = at;
        return Ok(new Asn1Tag(tagClass, (int)number, constructed));
    }

    /// The tag and length at the start of `data`, with the contents checked
    /// to be inside it.
    static Result<AsnHeader, AsnError> DecodeHeader(
        ReadOnlySpan<byte> data, AsnEncodingRules ruleSet)
    {
        var tag = DecodeTag(data, out nuint at);
        if (!tag.Ok)
            return Fail(tag.Error);

        if (at >= data.Length)
            return Fail(AsnError.Truncated);

        uint first = (uint)data[at];
        at++;
        nuint available = data.Length - at;
        nuint length = 0u;

        if (first < 0x80u)
        {
            length = (nuint)first;
        }
        else if (first == 0x80u)
        {
            return Fail(AsnError.Unsupported);
        }
        else if (first == 0xFFu)
        {
            return Fail(AsnError.BadLength);
        }
        else
        {
            nuint count = (nuint)(first & 0x7Fu);
            if (count > available)
                return Fail(AsnError.Truncated);
            if (ruleSet == AsnEncodingRules.Der && data[at] == 0x00)
                return Fail(AsnError.NonMinimalEncoding);

            for (nuint i = 0u; i < count; i++)
            {
                // Past this, the length already exceeds what is left.
                if (length > ((available - count) >> 8))
                    return Fail(AsnError.Truncated);
                length = (length << 8) | (nuint)data[at + i];
            }
            at += count;
            available -= count;

            if (ruleSet == AsnEncodingRules.Der && length < 0x80u)
                return Fail(AsnError.NonMinimalEncoding);
        }

        if (length > available)
            return Fail(AsnError.Truncated);

        AsnHeader header;
        header.Tag = tag.Value;
        header.HeaderLength = at;
        header.ContentLength = length;
        return Ok(header);
    }
}

// ------------------------------------------------------------ character sets

bool IsCharacterStringType(UniversalTagNumber type)
{
    switch (type)
    {
        case UniversalTagNumber.Utf8String:
        case UniversalTagNumber.PrintableString:
        case UniversalTagNumber.IA5String:
        case UniversalTagNumber.VisibleString:
        case UniversalTagNumber.NumericString:
        case UniversalTagNumber.T61String:
        case UniversalTagNumber.BmpString:
        case UniversalTagNumber.UniversalString:
            return true;
    }
    return false;
}

/// Whether `type` allows the ASCII character `octet`. Only the four types
/// that are subsets of ASCII are asked.
bool IsAllowedInAsciiString(UniversalTagNumber type, uint octet)
{
    switch (type)
    {
        case UniversalTagNumber.IA5String:
            return octet < 0x80u;
        case UniversalTagNumber.VisibleString:
            return octet >= 0x20u && octet <= 0x7Eu;
        case UniversalTagNumber.NumericString:
            return octet == 0x20u || (octet >= 0x30u && octet <= 0x39u);
        case UniversalTagNumber.PrintableString:
            if ((octet >= 0x41u && octet <= 0x5Au) || (octet >= 0x61u && octet <= 0x7Au) ||
                (octet >= 0x30u && octet <= 0x39u))
            {
                return true;
            }
            switch (octet)
            {
                case 0x20u:
                case 0x27u:
                case 0x28u:
                case 0x29u:
                case 0x2Bu:
                case 0x2Cu:
                case 0x2Du:
                case 0x2Eu:
                case 0x2Fu:
                case 0x3Au:
                case 0x3Du:
                case 0x3Fu:
                    return true;
            }
            return false;
    }
    return false;
}

/// Whether `scalar` is a Unicode scalar value: in range and not a surrogate.
bool IsUnicodeScalar(uint scalar) => scalar <= 0x10FFFFu && (scalar < 0xD800u || scalar > 0xDFFFu);

Result<String, AsnError> DecodeCharacterString(UniversalTagNumber type, ReadOnlySpan<byte> contents)
{
    var built = new StringBuilder();
    switch (type)
    {
        case UniversalTagNumber.Utf8String:
        {
            nuint at = 0u;
            while (at < contents.Length)
            {
                int scalar = DecodeUtf8ScalarAt(contents, at, out nuint width);
                if (scalar < 0)
                    return Fail(AsnError.BadStringContent);
                at += width;
            }
            built.AppendBytes(contents.ToArray());
            return Ok(built.ToText());
        }

        case UniversalTagNumber.T61String:
            for (nuint i = 0u; i < contents.Length; i++)
                built.AppendCodePoint((char32)(uint)contents[i]);
            return Ok(built.ToText());

        case UniversalTagNumber.BmpString:
            if (contents.Length % 2u != 0u)
                return Fail(AsnError.BadStringContent);
            for (nuint i = 0u; i < contents.Length; i += 2)
            {
                uint unit = ((uint)contents[i] << 8) | (uint)contents[i + 1u];
                if (!IsUnicodeScalar(unit))
                    return Fail(AsnError.BadStringContent);
                built.AppendCodePoint((char32)unit);
            }
            return Ok(built.ToText());

        case UniversalTagNumber.UniversalString:
            if (contents.Length % 4u != 0u)
                return Fail(AsnError.BadStringContent);
            for (nuint i = 0u; i < contents.Length; i += 4)
            {
                uint scalar = ((uint)contents[i] << 24) | ((uint)contents[i + 1u] << 16) |
                              ((uint)contents[i + 2u] << 8) | (uint)contents[i + 3u];
                if (!IsUnicodeScalar(scalar))
                    return Fail(AsnError.BadStringContent);
                built.AppendCodePoint((char32)scalar);
            }
            return Ok(built.ToText());

        default:
            for (nuint i = 0u; i < contents.Length; i++)
            {
                if (!IsAllowedInAsciiString(type, (uint)contents[i]))
                    return Fail(AsnError.BadStringContent);
            }
            built.AppendBytes(contents.ToArray());
            return Ok(built.ToText());
    }
}

// --------------------------------------------------------------------- times

/// `count` decimal digits at `at`, or -1 when any is not a digit.
long ParseAsnDigits(ReadOnlySpan<byte> text, nuint at, nuint count)
{
    long value = 0;
    for (nuint i = 0u; i < count; i++)
    {
        byte digit = text[at + i];
        if (digit < 48 || digit > 57)
            return -1;
        value = value * 10 + (long)(digit - 48);
    }
    return value;
}

/// Seconds since the epoch of a date and time already split into fields, or
/// `BadTime` when they do not name a real moment. `offset` is east of UTC.
Result<long, AsnError> ComposeAsnTime(long year, long month, long day, long hour, long minute,
                                      long second, long offset)
{
    if (month < 1 || month > 12 || day < 1 || day > (long)DaysInMonth((int)year, (int)month))
        return Fail(AsnError.BadTime);
    if (hour > 23 || minute > 59 || second > 59)
        return Fail(AsnError.BadTime);
    long days = CountDaysFromCivil(year, month, day);
    return Ok(days * 86400 + hour * 3600 + minute * 60 + second - offset);
}

/// The zone at `at` to the end: `Z`, or under BER `+hhmm` or `-hhmm`. The
/// offset east of UTC, in seconds.
Result<long, AsnError> ParseAsnZone(ReadOnlySpan<byte> text, nuint at, AsnEncodingRules ruleSet,
                                    bool hourOnlyAllowed)
{
    nuint left = text.Length - at;
    if (left == 0u)
    {
        if (ruleSet == AsnEncodingRules.Der)
            return Fail(AsnError.BadTime);
        return Fail(AsnError.Unsupported);
    }

    byte sign = text[at];
    if (sign == 90 && left == 1u)                                   // 'Z'
        return Ok(0L);
    if (ruleSet == AsnEncodingRules.Der || (sign != 43 && sign != 45))
        return Fail(AsnError.BadTime);

    long minutes = 0;
    if (left == 5u)
    {
        minutes = ParseAsnDigits(text, at + 3u, 2u);
    }
    else if (left != 3u || !hourOnlyAllowed)
    {
        return Fail(AsnError.BadTime);
    }

    long hours = ParseAsnDigits(text, at + 1u, 2u);
    if (hours < 0 || minutes < 0 || hours > 23 || minutes > 59)
        return Fail(AsnError.BadTime);

    long offset = hours * 3600 + minutes * 60;
    return Ok(sign == 45 ? -offset : offset);
}

Result<long, AsnError> ParseUtcTime(ReadOnlySpan<byte> text, AsnEncodingRules ruleSet)
{
    if (text.Length < 11u)
        return Fail(AsnError.BadTime);

    long year = ParseAsnDigits(text, 0u, 2u);
    long month = ParseAsnDigits(text, 2u, 2u);
    long day = ParseAsnDigits(text, 4u, 2u);
    long hour = ParseAsnDigits(text, 6u, 2u);
    long minute = ParseAsnDigits(text, 8u, 2u);
    if (year < 0 || month < 0 || day < 0 || hour < 0 || minute < 0)
        return Fail(AsnError.BadTime);

    long second = 0;
    nuint at = 10u;
    if (text.Length >= 12u && text[10u] >= 48 && text[10u] <= 57)
    {
        second = ParseAsnDigits(text, 10u, 2u);
        if (second < 0)
            return Fail(AsnError.BadTime);
        at = 12u;
    }
    else if (ruleSet == AsnEncodingRules.Der)
    {
        return Fail(AsnError.BadTime);
    }

    var offset = ParseAsnZone(text, at, ruleSet, false);
    if (!offset.Ok)
    {
        // UTCTime has no local form, so a missing zone is malformed here.
        return Fail(AsnError.BadTime);
    }

    year += year >= 50 ? 1900 : 2000;
    return ComposeAsnTime(year, month, day, hour, minute, second, offset.Value);
}

Result<long, AsnError> ParseGeneralizedTime(ReadOnlySpan<byte> text, AsnEncodingRules ruleSet)
{
    if (text.Length < 10u)
        return Fail(AsnError.BadTime);

    long year = ParseAsnDigits(text, 0u, 4u);
    long month = ParseAsnDigits(text, 4u, 2u);
    long day = ParseAsnDigits(text, 6u, 2u);
    long hour = ParseAsnDigits(text, 8u, 2u);
    if (year < 0 || month < 0 || day < 0 || hour < 0)
        return Fail(AsnError.BadTime);

    long minute = 0;
    long second = 0;
    nuint at = 10u;
    nuint fields = 0u;
    while (fields < 2u && text.Length >= at + 2u && text[at] >= 48 && text[at] <= 57)
    {
        long value = ParseAsnDigits(text, at, 2u);
        if (value < 0)
            return Fail(AsnError.BadTime);
        if (fields == 0u)
        {
            minute = value;
        }
        else
        {
            second = value;
        }
        at += 2;
        fields++;
    }

    if (fields < 2u && ruleSet == AsnEncodingRules.Der)
        return Fail(AsnError.BadTime);

    if (at < text.Length && (text[at] == 46 || text[at] == 44))    // '.' or ','
    {
        if (fields < 2u)
            return Fail(AsnError.Unsupported);
        if (text[at] == 44 && ruleSet == AsnEncodingRules.Der)
            return Fail(AsnError.BadTime);
        at++;

        nuint start = at;
        while (at < text.Length && text[at] >= 48 && text[at] <= 57)
            at++;
        if (at == start)
            return Fail(AsnError.BadTime);
        if (ruleSet == AsnEncodingRules.Der && text[at - 1u] == 48)
            return Fail(AsnError.BadTime);
    }

    var offset = ParseAsnZone(text, at, ruleSet, true);
    if (!offset.Ok)
        return Fail(offset.Error);

    return ComposeAsnTime(year, month, day, hour, minute, second, offset.Value);
}
