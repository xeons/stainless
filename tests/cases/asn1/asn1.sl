// SPDX-License-Identifier: 0BSD
module Asn1Case;

import Standard.Console;
import Standard.Convert;
import Standard.Time;
import Standard.Formats.Asn1;

// The fixed encodings are X.690's own examples or follow from its rules by
// hand. certificate.der is a self-signed P-256 certificate made by OpenSSL
// 3.5, valid from 2026 (a UTCTime) to 2050 (a GeneralizedTime).

[Embed("certificate.der")]
static readonly byte[] CertificateDer;

byte[] Hex(String text) => Convert.FromHexString(text).GetValueOrDefault(new byte[0u]);

String ToHex(ReadOnlySpan<byte> data) => Convert.ToHexString(data.ToArray());

void Check(String label, bool passed)
{
    if (passed)
    {
        Console.WriteLine($"{label} ok");
    }
    else
    {
        Console.WriteLine($"{label} FAIL");
    }
}

void CheckText(String label, String got, String want)
{
    if (got == want)
    {
        Console.WriteLine($"{label} ok");
    }
    else
    {
        Console.WriteLine($"{label} FAIL: got {got}, want {want}");
    }
}

void CheckNumber(String label, long got, long want)
{
    if (got == want)
    {
        Console.WriteLine($"{label} ok");
    }
    else
    {
        Console.WriteLine($"{label} FAIL: got {got}, want {want}");
    }
}

String NameAsnError(AsnError error)
{
    switch (error)
    {
        case AsnError.None: return "None";
        case AsnError.Truncated: return "Truncated";
        case AsnError.BadLength: return "BadLength";
        case AsnError.UnexpectedTag: return "UnexpectedTag";
        case AsnError.NonMinimalEncoding: return "NonMinimalEncoding";
        case AsnError.OutOfRange: return "OutOfRange";
        case AsnError.BadStringContent: return "BadStringContent";
        case AsnError.BadTime: return "BadTime";
        case AsnError.TrailingData: return "TrailingData";
        case AsnError.Unsupported: return "Unsupported";
        case AsnError.Malformed: return "Malformed";
    }
    return "?";
}

void CheckError(String label, AsnError got, AsnError want)
{
    CheckText(label, NameAsnError(got), NameAsnError(want));
}

AsnError ErrorOf<T>(Result<T, AsnError> result) => result.Ok ? AsnError.None : result.Error;

AsnReader Der(String hex) => new AsnReader(Hex(hex), AsnEncodingRules.Der);

AsnReader Ber(String hex) => new AsnReader(Hex(hex), AsnEncodingRules.Ber);

// ------------------------------------------------------------ known encodings

void WriteKnownEncodings()
{
    var writer = new AsnWriter();
    writer.WriteInteger(128);
    CheckText("integer 128", ToHex(writer.Encode()), "02020080");

    long[] values = [0, 127, 256, -128, -129, -9223372036854775807 - 1];
    String[] wanted = [
        "020100", "02017f", "02020100", "020180", "0202ff7f", "02088000000000000000"];
    for (nuint i = 0u; i < values.Length; i++)
    {
        var one = new AsnWriter();
        one.WriteInteger(values[i]);
        CheckText($"integer {values[i]}", ToHex(one.Encode()), wanted[i]);
    }

    var wide = new AsnWriter();
    wide.WriteInteger(18446744073709551615u);
    CheckText("integer ulong max", ToHex(wide.Encode()), "020900ffffffffffffffff");

    var oid = new AsnWriter();
    Check("oid write", oid.WriteObjectIdentifier("1.2.840.113549") == AsnError.None);
    CheckText("oid 1.2.840.113549", ToHex(oid.Encode()), "06062a864886f70d");

    var joint = new AsnWriter();
    joint.WriteObjectIdentifier("2.999.3");
    CheckText("oid 2.999.3", ToHex(joint.Encode()), "0603883703");

    // X.690 §8.6.4.2: '0A3B5F291CD'H, 44 bits, so four unused.
    var bits = new AsnWriter();
    Check("bit string write", bits.WriteBitString(Hex("0a3b5f291cd0"), 4) == AsnError.None);
    CheckText("bit string 0A3B5F291CD", ToHex(bits.Encode()), "0307040a3b5f291cd0");

    var empty = new AsnWriter();
    empty.WriteBitString(new byte[0u]);
    CheckText("bit string empty", ToHex(empty.Encode()), "030100");

    var simple = new AsnWriter();
    simple.WriteBoolean(true);
    simple.WriteBoolean(false);
    simple.WriteNull();
    simple.WriteOctetString(Hex("0102"));
    simple.WriteEnumeratedValue(3);
    CheckText(
        "boolean null octets enumerated", ToHex(simple.Encode()), "0101ff0101000500040201020a0103");

    var printable = new AsnWriter();
    printable.WriteCharacterString(UniversalTagNumber.PrintableString, "Test User 1");
    CheckText("printable string", ToHex(printable.Encode()), "130b5465737420557365722031");

    var nested = new AsnWriter();
    nested.PushSequence();
    nested.PushSequence(new Asn1Tag(TagClass.ContextSpecific, 0, true));
    nested.WriteInteger(2);
    nested.PopSequence();
    nested.WriteInteger(5, new Asn1Tag(TagClass.ContextSpecific, 1));
    nested.PopSequence();
    CheckText("explicit and implicit tags", ToHex(nested.Encode()), "3008a003020102810105");

    var set = new AsnWriter();
    set.PushSetOf();
    set.WriteInteger(3);
    set.WriteInteger(1);
    set.WriteOctetString(Hex("00"));
    set.WriteInteger(2);
    set.PopSetOf();
    CheckText("set of sorted", ToHex(set.Encode()), "310c020101020102020103040100");

    var high = new AsnWriter();
    high.WriteNull(new Asn1Tag(TagClass.ContextSpecific, 200));
    CheckText("tag number 200", ToHex(high.Encode()), "9f814800");

    var utc = new AsnWriter();
    utc.WriteUtcTime(673573540);
    CheckText("utc time 1991", ToHex(utc.Encode()), "170d3931303530363233343534305a");

    var general = new AsnWriter();
    general.WriteGeneralizedTime(253402300799);
    CheckText(
        "generalized time 9999", ToHex(general.Encode()), "180f39393939313233313233353935395a");
}

void WriteLongForms()
{
    var octets = new byte[200u];
    var writer = new AsnWriter();
    writer.WriteOctetString(octets);
    byte[] encoded = writer.Encode();
    CheckText("length 200", ToHex(encoded[:4u]), "0481c800");
    CheckNumber("length 200 size", (long)encoded.Length, 203);

    var outer = new AsnWriter();
    outer.PushSequence();
    outer.WriteOctetString(new byte[300u]);
    outer.WriteBoolean(true);
    outer.PopSequence();
    byte[] big = outer.Encode();
    CheckText("pushed length 309", ToHex(big[:8u]), "308201330482012c");
    CheckText("pushed tail", ToHex(big[(big.Length - 3u):]), "0101ff");

    var reader = new AsnReader(big, AsnEncodingRules.Der);
    var sequence = reader.ReadSequence();
    if (!sequence.Ok)
    {
        Check("pushed read", false);
        return;
    }
    var inside = sequence.Value;
    var content = inside.ReadOctetString();
    var flag = inside.ReadBoolean();
    Check("pushed read", content.Ok && content.Value.Length == 300u && flag.Ok && flag.Value &&
          inside.VerifyEndOfData() == AsnError.None && !reader.HasData);
}

// ----------------------------------------------------------------- round trip

void RoundTripEveryType()
{
    var writer = new AsnWriter();
    writer.PushSequence();
    writer.WriteBoolean(true);
    writer.WriteInteger(-1234567890123);
    writer.WriteInteger(18446744073709551615u);
    writer.WriteIntegerUnsigned(Hex("0000ff01"));
    writer.WriteIntegerBytes(Hex("00ff"));
    writer.WriteNull();
    writer.WriteBitString(Hex("f0"), 4);
    writer.WriteOctetString(Hex("deadbeef"));
    writer.WriteObjectIdentifier("1.3.6.1.4.1.311.21.20");
    writer.WriteEnumeratedValue(-2);
    writer.WriteCharacterString(UniversalTagNumber.Utf8String, "Grüße, 世界");
    writer.WriteCharacterString(UniversalTagNumber.T61String, "Grüße");
    writer.WriteCharacterString(UniversalTagNumber.BmpString, "Grüße");
    writer.WriteCharacterString(UniversalTagNumber.UniversalString, "a😀");
    writer.WriteCharacterString(UniversalTagNumber.IA5String, "user@example.com");
    writer.WriteCharacterString(UniversalTagNumber.VisibleString, "Visible ~");
    writer.WriteCharacterString(UniversalTagNumber.NumericString, "123 45");
    writer.WriteUtcTime(-631152000);
    writer.WriteGeneralizedTime(-62135596800);
    writer.PushSetOf(new Asn1Tag(TagClass.Application, 7, true));
    writer.WriteOctetString(Hex("02"));
    writer.WriteOctetString(Hex("01"));
    writer.PopSetOf();
    writer.PopSequence();
    Check("writer closed", writer.Depth == 0u);
    byte[] encoded = writer.Encode();

    var outer = new AsnReader(encoded, AsnEncodingRules.Der);
    var opened = outer.ReadSequence();
    if (!opened.Ok)
    {
        Check("round trip sequence", false);
        return;
    }
    var reader = opened.Value;

    var boolean = reader.ReadBoolean();
    Check("round trip boolean", boolean.Ok && boolean.Value);
    var signed = reader.ReadInt64();
    Check("round trip long", signed.Ok && signed.Value == -1234567890123);
    var unsigned = reader.ReadUInt64();
    Check("round trip ulong", unsigned.Ok && unsigned.Value == 18446744073709551615u);
    var magnitude = reader.ReadIntegerBytes();
    Check("round trip unsigned bytes", magnitude.Ok && ToHex(magnitude.Value) == "00ff01");
    var exact = reader.ReadIntegerBytes();
    Check("round trip integer bytes", exact.Ok && ToHex(exact.Value) == "00ff");
    Check("round trip null", reader.ReadNull() == AsnError.None);
    var bits = reader.ReadBitString(out int unused);
    Check("round trip bit string", bits.Ok && ToHex(bits.Value) == "f0" && unused == 4);
    var octets = reader.ReadOctetString();
    Check("round trip octet string", octets.Ok && ToHex(octets.Value) == "deadbeef");
    var oid = reader.ReadObjectIdentifier();
    Check("round trip oid", oid.Ok && oid.Value == "1.3.6.1.4.1.311.21.20");
    var enumerated = reader.ReadEnumeratedValue();
    Check("round trip enumerated", enumerated.Ok && enumerated.Value == -2);

    var utf8 = reader.ReadCharacterString(UniversalTagNumber.Utf8String);
    Check("round trip utf8", utf8.Ok && utf8.Value == "Grüße, 世界");
    var t61Raw = reader.PeekEncodedValue();
    Check("t61 is latin-1", t61Raw.Ok && ToHex(t61Raw.Value) == "14054772fcdf65");
    var t61 = reader.ReadCharacterString(UniversalTagNumber.T61String);
    Check("round trip t61", t61.Ok && t61.Value == "Grüße");
    var bmpRaw = reader.PeekEncodedValue();
    Check("bmp is ucs-2", bmpRaw.Ok && ToHex(bmpRaw.Value) == "1e0a0047007200fc00df0065");
    var bmp = reader.ReadCharacterString(UniversalTagNumber.BmpString);
    Check("round trip bmp", bmp.Ok && bmp.Value == "Grüße");
    var universal = reader.ReadCharacterString(UniversalTagNumber.UniversalString);
    Check("round trip universal", universal.Ok && universal.Value == "a😀");
    var ia5 = reader.ReadCharacterString(UniversalTagNumber.IA5String);
    Check("round trip ia5", ia5.Ok && ia5.Value == "user@example.com");
    var visible = reader.ReadCharacterString(UniversalTagNumber.VisibleString);
    Check("round trip visible", visible.Ok && visible.Value == "Visible ~");
    var numeric = reader.ReadCharacterString(UniversalTagNumber.NumericString);
    Check("round trip numeric", numeric.Ok && numeric.Value == "123 45");

    var utc = reader.ReadUtcTime();
    Check("round trip utc 1950", utc.Ok && utc.Value == -631152000);
    var general = reader.ReadGeneralizedTime();
    Check("round trip generalized 0001", general.Ok && general.Value == -62135596800);

    var tag = reader.PeekTag();
    Check(
        "peek application tag", tag.Ok && tag.Value == new Asn1Tag(TagClass.Application, 7, true));
    if (tag.Ok)
        CheckText("tag text", tag.Value.ToString(), "Application 7 constructed");
    var set = reader.ReadSetOf(new Asn1Tag(TagClass.Application, 7));
    if (set.Ok)
    {
        var first = set.Value.ReadOctetString();
        Check("round trip set of", first.Ok && ToHex(first.Value) == "01");
    }
    else
    {
        Check("round trip set of", false);
    }

    Check("round trip end", reader.VerifyEndOfData() == AsnError.None && !outer.HasData);
}

// ---------------------------------------------------------------------- times

void ReadTimes()
{
    var boundary = Der("170d3530303130313030303030305a");                    // 500101000000Z
    CheckNumber("utc 50 is 1950", boundary.ReadUtcTime().GetValueOrDefault(0), -631152000);
    var last = Der("170d3439313233313233353935395a");                        // 491231235959Z
    CheckNumber("utc 49 is 2049", last.ReadUtcTime().GetValueOrDefault(0), 2524607999);
    var far = Der("180f39393939313233313233353935395a");                     // 99991231235959Z
    CheckNumber("generalized 9999", far.ReadGeneralizedTime().GetValueOrDefault(0), 253402300799);

    var farResult = ConvertAsnTimeToDateTimeOffset(253402300799);
    CheckError("9999 is past DateTimeOffset", ErrorOf(farResult), AsnError.OutOfRange);
    var nearResult = ConvertAsnTimeToDateTimeOffset(673573540);
    if (nearResult.Ok)
    {
        CheckText("1991 as DateTimeOffset", nearResult.Value.FormatIso(), "1991-05-06T23:45:40Z");
    }
    else
    {
        Check("1991 as DateTimeOffset", false);
    }

    var tooEarly = new AsnWriter();
    CheckError("utc refuses 1949", tooEarly.WriteUtcTime(-631152001), AsnError.OutOfRange);
    CheckError("utc refuses 2050", tooEarly.WriteUtcTime(2524608000), AsnError.OutOfRange);
    CheckError(
        "generalized refuses 10000",
        tooEarly.WriteGeneralizedTime(253402300800),
        AsnError.OutOfRange);
    CheckNumber("refused writes wrote nothing", (long)tooEarly.Encode().Length, 0);

    // 19700101000000.5Z, then .50Z, then ,5Z.
    var fraction = Der("181131393730303130313030303030302e355a");
    CheckNumber("fraction dropped", fraction.ReadGeneralizedTime().GetValueOrDefault(-1), 0);
    var trailingZero = Der("18123139373030313031303030303030" + "2e35305a");
    CheckError(
        "der fraction trailing zero",
        ErrorOf(trailingZero.ReadGeneralizedTime()),
        AsnError.BadTime);
    var comma = "181131393730303130313030303030302c355a";
    CheckError("der fraction comma", ErrorOf(Der(comma).ReadGeneralizedTime()), AsnError.BadTime);
    CheckNumber("ber fraction comma", Ber(comma).ReadGeneralizedTime().GetValueOrDefault(-1), 0);

    // 9105062345+0100: no seconds and an offset, which only BER allows.
    var offset = "170f393130353036323334352b30313030";
    CheckError("der utc offset", ErrorOf(Der(offset).ReadUtcTime()), AsnError.BadTime);
    CheckNumber("ber utc offset", Ber(offset).ReadUtcTime().GetValueOrDefault(0), 673569900);

    // 19910506234540 with no zone is a local time.
    var local = "180e3139393130353036323334353430";
    CheckError("ber local time", ErrorOf(Ber(local).ReadGeneralizedTime()), AsnError.Unsupported);
    CheckError("der local time", ErrorOf(Der(local).ReadGeneralizedTime()), AsnError.BadTime);

    CheckError(
        "month 13", ErrorOf(Der("170d3931313330363030303030305a").ReadUtcTime()), AsnError.BadTime);
    CheckError(
        "february 30",
        ErrorOf(Der("170d3931303233303030303030305a").ReadUtcTime()),
        AsnError.BadTime);
    CheckError(
        "february 29 2001",
        ErrorOf(Der("170d3031303232393030303030305a").ReadUtcTime()),
        AsnError.BadTime);
    CheckNumber(
        "february 29 2000",
        Der("170d3030303232393030303030305a").ReadUtcTime().GetValueOrDefault(0),
        951782400);
    CheckError(
        "utc without zone",
        ErrorOf(Der("170c393130353036323334353430").ReadUtcTime()),
        AsnError.BadTime);
    CheckError(
        "second 60",
        ErrorOf(Der("170d3931303530363233343536305a").ReadUtcTime()),
        AsnError.BadTime);
}

// ------------------------------------------------------------------ refusals

void RefuseEachError()
{
    CheckError("empty input", ErrorOf(Der("").ReadInt64()), AsnError.Truncated);
    CheckError("contents cut short", ErrorOf(Der("02030102").ReadInt64()), AsnError.Truncated);
    CheckError("high tag unterminated", ErrorOf(Der("1f81").PeekTag()), AsnError.Truncated);
    CheckError(
        "length octets cut short", ErrorOf(Der("0482").ReadOctetString()), AsnError.Truncated);
    CheckError(
        "huge length",
        ErrorOf(Der("0488ffffffffffffffff00").ReadOctetString()),
        AsnError.Truncated);
    CheckError(
        "nested past parent",
        ErrorOf((Der("300204030000").ReadSequence().GetValueOrDefault(Der(""))).ReadOctetString()),
        AsnError.Truncated);

    CheckError("boolean of two", ErrorOf(Der("010200ff").ReadBoolean()), AsnError.BadLength);
    CheckError("empty integer", ErrorOf(Der("0200").ReadInt64()), AsnError.BadLength);
    CheckError("null with contents", Der("050100").ReadNull(), AsnError.BadLength);
    CheckError("length ff", ErrorOf(Der("04ff").ReadOctetString()), AsnError.BadLength);
    CheckError(
        "empty bit string", ErrorOf(Der("0300").ReadBitString(out int none)), AsnError.BadLength);

    CheckError("boolean as integer", ErrorOf(Der("0101ff").ReadInt64()), AsnError.UnexpectedTag);
    CheckError("primitive sequence", ErrorOf(Der("1000").ReadSequence()), AsnError.UnexpectedTag);
    CheckError(
        "constructed integer", ErrorOf(Der("2203020101").ReadInt64()), AsnError.UnexpectedTag);
    CheckError(
        "wrong implicit tag",
        ErrorOf(Der("810105").ReadInt64(new Asn1Tag(TagClass.ContextSpecific, 2))),
        AsnError.UnexpectedTag);
    CheckNumber(
        "right implicit tag",
        Der("810105").ReadInt64(new Asn1Tag(TagClass.ContextSpecific, 1)).GetValueOrDefault(0),
        5);

    CheckError(
        "integer leading zero", ErrorOf(Der("02020001").ReadInt64()), AsnError.NonMinimalEncoding);
    CheckError(
        "integer leading ff", ErrorOf(Ber("0202ff80").ReadInt64()), AsnError.NonMinimalEncoding);
    CheckError(
        "der long length", ErrorOf(Der("02810105").ReadInt64()), AsnError.NonMinimalEncoding);
    CheckNumber("ber long length", Ber("02810105").ReadInt64().GetValueOrDefault(0), 5);
    CheckError(
        "der length leading zero",
        ErrorOf(Der("0482008000").ReadOctetString()),
        AsnError.NonMinimalEncoding);
    CheckError("der boolean 01", ErrorOf(Der("010101").ReadBoolean()), AsnError.NonMinimalEncoding);
    Check("ber boolean 01", Ber("010101").ReadBoolean().GetValueOrDefault(false));
    CheckError(
        "high form for small tag", ErrorOf(Der("1f0500").PeekTag()), AsnError.NonMinimalEncoding);
    CheckError("tag padded", ErrorOf(Der("1f807f00").PeekTag()), AsnError.NonMinimalEncoding);
    CheckError(
        "oid padded", ErrorOf(Der("06028001").ReadObjectIdentifier()), AsnError.NonMinimalEncoding);
    CheckError(
        "der unused bits set",
        ErrorOf(Der("030206ff").ReadBitString(out int setBits)),
        AsnError.NonMinimalEncoding);
    Check("ber unused bits set", Ber("030206ff").ReadBitString(out int berBits).Ok && berBits == 6);
    CheckError(
        "der constructed octets",
        ErrorOf(Der("2403040100").ReadOctetString()),
        AsnError.NonMinimalEncoding);

    CheckError(
        "integer past long",
        ErrorOf(Der("0209010000000000000000").ReadInt64()),
        AsnError.OutOfRange);
    CheckError("negative as ulong", ErrorOf(Der("0201ff").ReadUInt64()), AsnError.OutOfRange);
    CheckError(
        "oid arc past ulong",
        ErrorOf(Der("060b2a82808080808080808000").ReadObjectIdentifier()),
        AsnError.OutOfRange);
    CheckError(
        "dotted arc past ulong",
        ErrorOf(Oid.FromDottedString("1.2.18446744073709551616")),
        AsnError.OutOfRange);
    CheckError("tag past int", ErrorOf(Der("1f8880808000").PeekTag()), AsnError.OutOfRange);

    CheckError(
        "printable at sign",
        ErrorOf(Der("130140").ReadCharacterString(UniversalTagNumber.PrintableString)),
        AsnError.BadStringContent);
    CheckError(
        "utf8 overlong",
        ErrorOf(Der("0c02c0af").ReadCharacterString(UniversalTagNumber.Utf8String)),
        AsnError.BadStringContent);
    CheckError(
        "utf8 surrogate",
        ErrorOf(Der("0c03eda080").ReadCharacterString(UniversalTagNumber.Utf8String)),
        AsnError.BadStringContent);
    CheckError(
        "utf8 cut short",
        ErrorOf(Der("0c02e282").ReadCharacterString(UniversalTagNumber.Utf8String)),
        AsnError.BadStringContent);
    CheckError(
        "bmp odd length",
        ErrorOf(Der("1e03004100").ReadCharacterString(UniversalTagNumber.BmpString)),
        AsnError.BadStringContent);
    CheckError(
        "bmp surrogate",
        ErrorOf(Der("1e02d800").ReadCharacterString(UniversalTagNumber.BmpString)),
        AsnError.BadStringContent);
    CheckError(
        "universal past 10ffff",
        ErrorOf(Der("1c0400110000").ReadCharacterString(UniversalTagNumber.UniversalString)),
        AsnError.BadStringContent);
    CheckError(
        "ia5 high bit",
        ErrorOf(Der("160180").ReadCharacterString(UniversalTagNumber.IA5String)),
        AsnError.BadStringContent);
    CheckError(
        "numeric letter",
        ErrorOf(Der("120141").ReadCharacterString(UniversalTagNumber.NumericString)),
        AsnError.BadStringContent);
    var strings = new AsnWriter();
    CheckError(
        "write printable at sign",
        strings.WriteCharacterString(UniversalTagNumber.PrintableString, "a@b"),
        AsnError.BadStringContent);
    CheckError(
        "write bmp emoji",
        strings.WriteCharacterString(UniversalTagNumber.BmpString, "😀"),
        AsnError.BadStringContent);
    CheckError(
        "write t61 beyond latin-1",
        strings.WriteCharacterString(UniversalTagNumber.T61String, "世"),
        AsnError.BadStringContent);

    var twoNulls = Der("05000500");
    Check("first null", twoNulls.ReadNull() == AsnError.None);
    CheckError("trailing data", twoNulls.VerifyEndOfData(), AsnError.TrailingData);
    CheckError(
        "write two values as one",
        new AsnWriter().WriteEncodedValue(Hex("05000500")),
        AsnError.TrailingData);

    CheckError(
        "indefinite length", ErrorOf(Ber("30800201050000").ReadSequence()), AsnError.Unsupported);
    CheckError(
        "ber constructed octets",
        ErrorOf(Ber("2403040100").ReadOctetString()),
        AsnError.Unsupported);
    CheckError(
        "integer as string type",
        ErrorOf(Der("020105").ReadCharacterString(UniversalTagNumber.Integer)),
        AsnError.Unsupported);

    CheckError(
        "eight unused bits",
        ErrorOf(Der("03020800").ReadBitString(out int eight)),
        AsnError.Malformed);
    CheckError(
        "unused bits and no octet",
        ErrorOf(Ber("030103").ReadBitString(out int alone)),
        AsnError.Malformed);
    CheckError(
        "oid unterminated", ErrorOf(Der("060186").ReadObjectIdentifier()), AsnError.Malformed);
    CheckError("dotted trailing dot", ErrorOf(Oid.FromDottedString("1.2.")), AsnError.Malformed);
    CheckError("dotted first arc 3", ErrorOf(Oid.FromDottedString("3.1")), AsnError.Malformed);
    CheckError("dotted second arc 40", ErrorOf(Oid.FromDottedString("1.40")), AsnError.Malformed);
    CheckError("dotted leading zero", ErrorOf(Oid.FromDottedString("1.02")), AsnError.Malformed);
    CheckError("dotted one arc", ErrorOf(Oid.FromDottedString("1")), AsnError.Malformed);
    var bad = new AsnWriter();
    CheckError("write bad oid", bad.WriteObjectIdentifier("1..2"), AsnError.Malformed);
    CheckError(
        "write unused bit set", bad.WriteBitString(Hex("01"), 1), AsnError.NonMinimalEncoding);
    CheckError("write nine unused", bad.WriteBitString(Hex("00"), 9), AsnError.OutOfRange);
    CheckError(
        "write integer bytes padded",
        bad.WriteIntegerBytes(Hex("0001")),
        AsnError.NonMinimalEncoding);
    CheckNumber("refusals wrote nothing", (long)bad.Encode().Length, 0);

    // A refused read leaves the reader where it was.
    var still = Der("0101ff");
    CheckError("refused read", ErrorOf(still.ReadInt64()), AsnError.UnexpectedTag);
    Check("then read as boolean", still.ReadBoolean().GetValueOrDefault(false) && !still.HasData);

    CheckText("describe", DescribeAsnError(AsnError.TrailingData), "data after the last value");
}

// --------------------------------------------------------------- certificate

String ReadDirectoryName(AsnReader name)
{
    var built = new StringBuilder();
    while (name.HasData)
    {
        var set = name.ReadSetOf();
        if (!set.Ok)
            return "bad set";
        var pair = set.Value.ReadSequence();
        if (!pair.Ok)
            return "bad pair";
        var attributeType = pair.Value.ReadObjectIdentifier();
        var tag = pair.Value.PeekTag();
        if (!attributeType.Ok || !tag.Ok)
            return "bad attributeType";
        var text = pair.Value.ReadCharacterString((UniversalTagNumber)tag.Value.TagValue);
        if (!text.Ok)
            return "bad text";
        if (!built.IsEmpty)
            built.Append(", ");
        built.Append($"{attributeType.Value}={text.Value}");
    }
    return built.ToText();
}

Result<long, AsnError> ReadCertificateTime(AsnReader validity)
{
    Asn1Tag tag = try validity.PeekTag();
    if (tag == Asn1Tag.UtcTime)
        return validity.ReadUtcTime();
    return validity.ReadGeneralizedTime();
}

String FormatCertificateTime(long seconds)
{
    var moment = ConvertAsnTimeToDateTimeOffset(seconds);
    if (!moment.Ok)
        return "out of range";
    return moment.Value.FormatIso();
}

Result<bool, AsnError> WalkCertificate(byte[] der)
{
    var document = new AsnReader(der, AsnEncodingRules.Der);
    var certificate = try document.ReadSequence();
    Check("certificate is one value", document.VerifyEndOfData() == AsnError.None);

    ReadOnlySpan<byte> signed = try certificate.PeekEncodedValue();
    Console.WriteLine($"tbs {signed.Length} bytes");
    var tbs = try certificate.ReadSequence();

    var explicitVersion = new Asn1Tag(TagClass.ContextSpecific, 0, true);
    if ((try tbs.PeekTag()).HasSameClassAndValue(explicitVersion))
    {
        var wrapper = try tbs.ReadSequence(explicitVersion);
        long version = try wrapper.ReadInt64();
        Console.WriteLine($"version {version + 1}");
    }

    Console.WriteLine($"serial {ToHex(try tbs.ReadIntegerBytes())}");
    Console.WriteLine($"signature {try (try tbs.ReadSequence()).ReadObjectIdentifier()}");
    Console.WriteLine($"issuer {ReadDirectoryName(try tbs.ReadSequence())}");

    var validity = try tbs.ReadSequence();
    long notBefore = try ReadCertificateTime(validity);
    long notAfter = try ReadCertificateTime(validity);
    Console.WriteLine($"not before {notBefore} {FormatCertificateTime(notBefore)}");
    Console.WriteLine($"not after {notAfter} {FormatCertificateTime(notAfter)}");
    Console.WriteLine($"subject {ReadDirectoryName(try tbs.ReadSequence())}");

    var publicKeyInfo = try tbs.ReadSequence();
    var algorithm = try publicKeyInfo.ReadSequence();
    Console.WriteLine(
        $"key {try algorithm.ReadObjectIdentifier()} {try algorithm.ReadObjectIdentifier()}");
    var key = try publicKeyInfo.ReadBitString(out int keyUnused);
    Console.WriteLine(
        $"key bits {key.Length * 8u - (nuint)keyUnused}, first octet {ToHex(key[:1u])}");

    var extensionsWrapper = try tbs.ReadSequence(new Asn1Tag(TagClass.ContextSpecific, 3, true));
    var extensions = try extensionsWrapper.ReadSequence();
    while (extensions.HasData)
    {
        var extension = try extensions.ReadSequence();
        String id = try extension.ReadObjectIdentifier();
        bool critical = false;
        if ((try extension.PeekTag()) == Asn1Tag.Boolean)
            critical = try extension.ReadBoolean();
        var value = try extension.ReadOctetString();
        Console.WriteLine($"extension {id} critical {critical} {value.Length} bytes");
        Check("extension end", extension.VerifyEndOfData() == AsnError.None);
    }
    Check("tbs end", tbs.VerifyEndOfData() == AsnError.None);

    Console.WriteLine($"signed with {try (try certificate.ReadSequence()).ReadObjectIdentifier()}");
    var signature = try certificate.ReadBitString(out int signatureUnused);
    Console.WriteLine($"signature {signature.Length} bytes, {signatureUnused} unused");
    Check("certificate end", certificate.VerifyEndOfData() == AsnError.None);

    // The signature is an ECDSA-Sig-Value inside the bit string.
    var ecdsa = new AsnReader(signature, AsnEncodingRules.Der);
    var pair = try ecdsa.ReadSequence();
    var r = try pair.ReadIntegerBytes();
    var s = try pair.ReadIntegerBytes();
    Check(
        "ecdsa r and s", r.Length > 0u && s.Length > 0u && pair.VerifyEndOfData() == AsnError.None);

    // Writing back what was read gives the same bytes.
    var copy = new AsnWriter();
    Check("rewrite certificate", copy.WriteEncodedValue(der) == AsnError.None);
    Check("rewritten bytes", ToHex(copy.Encode()) == ToHex(der));
    return Ok(true);
}

int Main()
{
    WriteKnownEncodings();
    WriteLongForms();
    RoundTripEveryType();
    ReadTimes();
    RefuseEachError();

    var walked = WalkCertificate(CertificateDer);
    if (!walked.Ok)
        Console.WriteLine($"certificate FAIL: {DescribeAsnError(walked.Error)}");

    return 0;
}
