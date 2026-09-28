# Standard.Formats.Asn1

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

ASN.1 values in BER and DER, as X.509, PKCS and TLS carry them.

```csharp
var document = new AsnReader(der, AsnEncodingRules.Der);
var certificate = try document.ReadSequence();
var signed = try certificate.ReadSequence();
String algorithm = try (try certificate.ReadSequence()).ReadObjectIdentifier();

var writer = new AsnWriter();
writer.PushSequence();
writer.WriteInteger(5);
writer.WriteObjectIdentifier("1.2.840.113549");
writer.PopSequence();
byte[] encoded = writer.Encode();
```

**The shape is `System.Formats.Asn1`'s**, with a `Result` where .NET
throws. A read that fails returns an `AsnError` and leaves the reader
where it was, so a caller can try another reading of the same value.

**Every read is bounds-checked against the value that contains it.** A
nested reader sees its own contents and nothing past them, so a length
that claims more than its parent holds is `Truncated` rather than a read
of a neighbour. Nothing here aborts on input.

**Times are seconds since 1970-01-01 UTC, in a `long`.** A
`GeneralizedTime` can name 9999, and `DateTimeOffset` counts nanoseconds and
ends in 2262; `ConvertAsnTimeToDateTimeOffset` crosses over where it can.

**SET OF ordering is not verified on reading.** DER requires the elements
in order and a reader that checks costs a sort per set; X.509 signs the
bytes rather than the order, so the check buys nothing there. The writer
does sort.

Object identifiers are dotted strings. Which one means what belongs to the
format that uses it, and is not this module's.

## Contents

**Types** &nbsp; [Asn1Tag](#asn1tag-struct) &middot; [AsnEncodingRules](#asnencodingrules-enum) &middot; [AsnError](#asnerror-enum) &middot; [AsnReader](#asnreader-class) &middot; [AsnWriter](#asnwriter-class) &middot; [Oid](#oid-class) &middot; [TagClass](#tagclass-enum) &middot; [UniversalTagNumber](#universaltagnumber-enum)

**Functions** &nbsp; [ConvertAsnTimeToDateTimeOffset](#convertasntimetodatetimeoffset-function) &middot; [DescribeAsnError](#describeasnerror-function)

## Types

### Asn1Tag *struct*

```
struct Asn1Tag
```

The identifier of an encoded value: a class, a number, and whether the
contents are themselves encoded values.

```csharp
var version = new Asn1Tag(TagClass.ContextSpecific, 0, true);   // [0] EXPLICIT
if ((try reader.PeekTag()).HasSameClassAndValue(version)) { ... }
```

A value, as .NET's is. `==` compares all three parts; a reader matches on
class and number and checks the constructed bit against the type, which is
what `HasSameClassAndValue` asks.

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:35](../../stdlib/Formats/Asn1/Asn1Tag.sl#L35)</sub>

#### TagClass *property*

```
TagClass TagClass { get; }
```

Which namespace the number is in.

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:67](../../stdlib/Formats/Asn1/Asn1Tag.sl#L67)</sub>

#### TagValue *property*

```
int TagValue { get; }
```

The number within its class.

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:70](../../stdlib/Formats/Asn1/Asn1Tag.sl#L70)</sub>

#### IsConstructed *property*

```
bool IsConstructed { get; }
```

Whether the contents are a series of encoded values.

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:73](../../stdlib/Formats/Asn1/Asn1Tag.sl#L73)</sub>

#### Boolean *property*

```
static Asn1Tag Boolean { get; }
```

`BOOLEAN`.

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:76](../../stdlib/Formats/Asn1/Asn1Tag.sl#L76)</sub>

#### Integer *property*

```
static Asn1Tag Integer { get; }
```

`INTEGER`.

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:79](../../stdlib/Formats/Asn1/Asn1Tag.sl#L79)</sub>

#### PrimitiveBitString *property*

```
static Asn1Tag PrimitiveBitString { get; }
```

`BIT STRING`, in the primitive form DER requires.

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:82](../../stdlib/Formats/Asn1/Asn1Tag.sl#L82)</sub>

#### ConstructedBitString *property*

```
static Asn1Tag ConstructedBitString { get; }
```

`BIT STRING`, in the constructed form only BER allows.

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:85](../../stdlib/Formats/Asn1/Asn1Tag.sl#L85)</sub>

#### PrimitiveOctetString *property*

```
static Asn1Tag PrimitiveOctetString { get; }
```

`OCTET STRING`, in the primitive form DER requires.

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:88](../../stdlib/Formats/Asn1/Asn1Tag.sl#L88)</sub>

#### ConstructedOctetString *property*

```
static Asn1Tag ConstructedOctetString { get; }
```

`OCTET STRING`, in the constructed form only BER allows.

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:91](../../stdlib/Formats/Asn1/Asn1Tag.sl#L91)</sub>

#### Null *property*

```
static Asn1Tag Null { get; }
```

`NULL`.

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:95](../../stdlib/Formats/Asn1/Asn1Tag.sl#L95)</sub>

#### ObjectIdentifier *property*

```
static Asn1Tag ObjectIdentifier { get; }
```

`OBJECT IDENTIFIER`.

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:98](../../stdlib/Formats/Asn1/Asn1Tag.sl#L98)</sub>

#### Enumerated *property*

```
static Asn1Tag Enumerated { get; }
```

`ENUMERATED`.

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:101](../../stdlib/Formats/Asn1/Asn1Tag.sl#L101)</sub>

#### Sequence *property*

```
static Asn1Tag Sequence { get; }
```

`SEQUENCE` and `SEQUENCE OF`, which are always constructed.

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:104](../../stdlib/Formats/Asn1/Asn1Tag.sl#L104)</sub>

#### SetOf *property*

```
static Asn1Tag SetOf { get; }
```

`SET` and `SET OF`, which are always constructed.

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:107](../../stdlib/Formats/Asn1/Asn1Tag.sl#L107)</sub>

#### UtcTime *property*

```
static Asn1Tag UtcTime { get; }
```

`UTCTime`.

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:110](../../stdlib/Formats/Asn1/Asn1Tag.sl#L110)</sub>

#### GeneralizedTime *property*

```
static Asn1Tag GeneralizedTime { get; }
```

`GeneralizedTime`.

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:113](../../stdlib/Formats/Asn1/Asn1Tag.sl#L113)</sub>

#### AsConstructed *method*

```
Asn1Tag AsConstructed()
```

This tag with the constructed bit set.

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:116](../../stdlib/Formats/Asn1/Asn1Tag.sl#L116)</sub>

#### AsPrimitive *method*

```
Asn1Tag AsPrimitive()
```

This tag with the constructed bit clear.

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:119](../../stdlib/Formats/Asn1/Asn1Tag.sl#L119)</sub>

#### HasSameClassAndValue *method*

```
bool HasSameClassAndValue(Asn1Tag other)
```

Whether `other` has this class and number, whatever its constructed bit.

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:122](../../stdlib/Formats/Asn1/Asn1Tag.sl#L122)</sub>

#### Equals *method*

```
bool Equals(Asn1Tag other)
```

Whether all three parts are the same.

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:126](../../stdlib/Formats/Asn1/Asn1Tag.sl#L126)</sub>

#### EncodedLength *property*

```
nuint EncodedLength { get; }
```

The identifier octets: one when the number is under 31, and a number
in base 128 after a marker otherwise.

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:131](../../stdlib/Formats/Asn1/Asn1Tag.sl#L131)</sub>

#### ToString *method*

```
String ToString()
```

The tag written for a person: `Universal 16 constructed`, `[0]`.

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:150](../../stdlib/Formats/Asn1/Asn1Tag.sl#L150)</sub>

#### operator == *operator*

```
static bool operator ==(Asn1Tag left, Asn1Tag right)
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:167](../../stdlib/Formats/Asn1/Asn1Tag.sl#L167)</sub>

#### operator != *operator*

```
static bool operator !=(Asn1Tag left, Asn1Tag right)
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/Asn1Tag.sl:169](../../stdlib/Formats/Asn1/Asn1Tag.sl#L169)</sub>

### AsnEncodingRules *enum*

```
enum AsnEncodingRules
```

Which of X.690's encodings a reader holds its input to.

CER is not here. Nothing a certificate or a TLS handshake carries uses it,
and its one distinguishing feature is the indefinite length this module
does not read.

<sub>[stdlib/Formats/Asn1/AsnEncodingRules.sl:29](../../stdlib/Formats/Asn1/AsnEncodingRules.sl#L29)</sub>

#### Ber *case*

```
Ber
```

The Basic Encoding Rules, where they are cheap to accept: a long-form
length that fits the short form, a length with leading zeros, a
`BOOLEAN` true other than `0xFF`, unused bits that are not zero, and a
time with an offset or without its seconds.

**Indefinite lengths and constructed strings are refused** with
`AsnError.Unsupported`. Both need a reader that reassembles what it
hands back, and neither appears in the formats this module exists for.

<sub>[stdlib/Formats/Asn1/AsnEncodingRules.sl:39](../../stdlib/Formats/Asn1/AsnEncodingRules.sl#L39)</sub>

#### Der *case*

```
Der
```

The Distinguished Encoding Rules: exactly one encoding for every value.
What X.509 signs, and the rules a reader SHOULD use for anything a
signature covers.

<sub>[stdlib/Formats/Asn1/AsnEncodingRules.sl:44](../../stdlib/Formats/Asn1/AsnEncodingRules.sl#L44)</sub>

### AsnError *enum*

```
enum AsnError
```

Why a value could not be read or written.

<sub>[stdlib/Formats/Asn1/AsnError.sl:25](../../stdlib/Formats/Asn1/AsnError.sl#L25)</sub>

#### None *case*

```
None
```

Nothing went wrong. What an operation that produces no value answers on
success.

<sub>[stdlib/Formats/Asn1/AsnError.sl:29](../../stdlib/Formats/Asn1/AsnError.sl#L29)</sub>

#### Truncated *case*

```
Truncated
```

The input ends inside an identifier, a length or the contents that
length promised.

<sub>[stdlib/Formats/Asn1/AsnError.sl:33](../../stdlib/Formats/Asn1/AsnError.sl#L33)</sub>

#### BadLength *case*

```
BadLength
```

A length that is malformed, or impossible for the type: a `BOOLEAN`
that is not one octet, a `NULL` that is not empty, an `INTEGER` of none.

<sub>[stdlib/Formats/Asn1/AsnError.sl:37](../../stdlib/Formats/Asn1/AsnError.sl#L37)</sub>

#### UnexpectedTag *case*

```
UnexpectedTag
```

The next value's tag is not the one asked for, or it is constructed
where the type is primitive or the other way round.

<sub>[stdlib/Formats/Asn1/AsnError.sl:41](../../stdlib/Formats/Asn1/AsnError.sl#L41)</sub>

#### NonMinimalEncoding *case*

```
NonMinimalEncoding
```

A form the rules in force forbid although a looser set allows it: a
length or tag number in more octets than it needs, an `INTEGER` with a
redundant leading `0x00` or `0xFF`, a `BOOLEAN` true other than `0xFF`
or a constructed string under DER.

<sub>[stdlib/Formats/Asn1/AsnError.sl:47](../../stdlib/Formats/Asn1/AsnError.sl#L47)</sub>

#### OutOfRange *case*

```
OutOfRange
```

The value is well-formed and does not fit what it is being read into:
an `INTEGER` too wide for a `long`, an arc too wide for a `ulong`, a
time outside the years a `UTCTime` can name.

<sub>[stdlib/Formats/Asn1/AsnError.sl:52](../../stdlib/Formats/Asn1/AsnError.sl#L52)</sub>

#### BadStringContent *case*

```
BadStringContent
```

A character string holds a character its type does not allow, or
octets that are not a valid encoding in its character set.

<sub>[stdlib/Formats/Asn1/AsnError.sl:56](../../stdlib/Formats/Asn1/AsnError.sl#L56)</sub>

#### BadTime *case*

```
BadTime
```

A `UTCTime` or `GeneralizedTime` that is not in the form the rules
require, or does not name a real moment.

<sub>[stdlib/Formats/Asn1/AsnError.sl:60](../../stdlib/Formats/Asn1/AsnError.sl#L60)</sub>

#### TrailingData *case*

```
TrailingData
```

Something follows the last value where nothing may.

<sub>[stdlib/Formats/Asn1/AsnError.sl:63](../../stdlib/Formats/Asn1/AsnError.sl#L63)</sub>

#### Unsupported *case*

```
Unsupported
```

Valid ASN.1 this module does not read: an indefinite length, a
constructed string under BER, a time with no zone.

<sub>[stdlib/Formats/Asn1/AsnError.sl:67](../../stdlib/Formats/Asn1/AsnError.sl#L67)</sub>

#### Malformed *case*

```
Malformed
```

Contents that are not an encoding of their type under any rules: a
`BIT STRING` claiming more than seven unused bits, an object identifier
whose last arc does not end, a dotted string that is not one.

<sub>[stdlib/Formats/Asn1/AsnError.sl:72](../../stdlib/Formats/Asn1/AsnError.sl#L72)</sub>

### AsnReader *class*

```
sealed class AsnReader
```

Reads encoded values one after another from a run of bytes.

```csharp
var reader = new AsnReader(der, AsnEncodingRules.Der);
var sequence = try reader.ReadSequence();
long version = try sequence.ReadInt64();
String algorithm = try sequence.ReadObjectIdentifier();
if (sequence.VerifyEndOfData() != AsnError.None) { ... }
```

**A failed read does not move the reader.** Each read decodes and checks
the whole value before it steps past it, so after a failure the same value
is next.

**Implicit tagging is the optional `expectedTag`.** Every typed read takes
one, and matches the next value's class and number against it in place of
the type's universal tag. Explicit tagging is a constructed value holding
the real one, and `ReadSequence` with the context tag opens it:

```csharp
var wrapper = try tbs.ReadSequence(new Asn1Tag(TagClass.ContextSpecific, 0, true));
long version = try wrapper.ReadInt64();
```

The reader holds a view of the caller's array, not a copy. What it hands
back as a `ReadOnlySpan<byte>` is a view of the same array.

<sub>[stdlib/Formats/Asn1/AsnReader.sl:62](../../stdlib/Formats/Asn1/AsnReader.sl#L62)</sub>

#### RuleSet *property*

```
AsnEncodingRules RuleSet { get; }
```

The rules every value is held to.

<sub>[stdlib/Formats/Asn1/AsnReader.sl:78](../../stdlib/Formats/Asn1/AsnReader.sl#L78)</sub>

#### HasData *property*

```
bool HasData { get; }
```

Whether anything is left to read.

<sub>[stdlib/Formats/Asn1/AsnReader.sl:81](../../stdlib/Formats/Asn1/AsnReader.sl#L81)</sub>

#### PeekTag *method*

```
Result<Asn1Tag, AsnError> PeekTag()
```

The tag of the next value, without moving.

**Fails with**

- [AsnError.Truncated](#truncated-case) — the input ends inside the tag
- [AsnError.NonMinimalEncoding](#nonminimalencoding-case) — a tag number in more octets than it needs
- [AsnError.OutOfRange](#outofrange-case) — a tag number past the largest `int`

<sub>[stdlib/Formats/Asn1/AsnReader.sl:90](../../stdlib/Formats/Asn1/AsnReader.sl#L90)</sub>

#### PeekEncodedValue *method*

```
Result<ReadOnlySpan<byte>, AsnError> PeekEncodedValue()
```

The whole of the next value — tag, length and contents — without
moving.

**Fails with**

- [AsnError.Truncated](#truncated-case) — the input ends inside the value
- [AsnError.BadLength](#badlength-case) — the length octets are malformed

**See also** &nbsp; [AsnReader.ReadEncodedValue](#readencodedvalue-method)

<sub>[stdlib/Formats/Asn1/AsnReader.sl:104](../../stdlib/Formats/Asn1/AsnReader.sl#L104)</sub>

#### ReadEncodedValue *method*

```
Result<ReadOnlySpan<byte>, AsnError> ReadEncodedValue()
```

The whole of the next value — tag, length and contents — and past it.

The tag and the length are checked; the contents are not looked at.
This is how to keep the exact bytes a signature covers.

**Fails with**

- [AsnError.Truncated](#truncated-case) — the input ends inside the value
- [AsnError.BadLength](#badlength-case) — the length octets are malformed
- [AsnError.Unsupported](#unsupported-case) — an indefinite length

<sub>[stdlib/Formats/Asn1/AsnReader.sl:120](../../stdlib/Formats/Asn1/AsnReader.sl#L120)</sub>

#### ReadSequence *method*

```
Result<AsnReader, AsnError> ReadSequence(Optional<Asn1Tag> expectedTag)
```

A reader over the contents of the next `SEQUENCE`, and past it.

**Parameters**

- `expectedTag` — the tag in place of `SEQUENCE`, for implicit or explicit tagging

**Fails with**

- [AsnError.UnexpectedTag](#unexpectedtag-case) — the next value is not a constructed value with that tag
- [AsnError.Truncated](#truncated-case) — the input ends inside the value

**See also** &nbsp; [AsnReader.ReadSetOf](#readsetof-method)

<sub>[stdlib/Formats/Asn1/AsnReader.sl:137](../../stdlib/Formats/Asn1/AsnReader.sl#L137)</sub>

#### ReadSetOf *method*

```
Result<AsnReader, AsnError> ReadSetOf(Optional<Asn1Tag> expectedTag)
```

A reader over the contents of the next `SET OF`, and past it.

**The order of the elements is not checked**, although DER requires
them sorted; see the module's summary.

**Parameters**

- `expectedTag` — the tag in place of `SET`

**Fails with**

- [AsnError.UnexpectedTag](#unexpectedtag-case) — the next value is not a constructed value with that tag
- [AsnError.Truncated](#truncated-case) — the input ends inside the value

**See also** &nbsp; [AsnReader.ReadSequence](#readsequence-method)

<sub>[stdlib/Formats/Asn1/AsnReader.sl:152](../../stdlib/Formats/Asn1/AsnReader.sl#L152)</sub>

#### VerifyEndOfData *method*

```
AsnError VerifyEndOfData()
```

`AsnError.None` when everything has been read, and
`AsnError.TrailingData` when something has not.

A format MUST call this on each reader it has finished with; a value
with something after it is not the value that was signed.

<sub>[stdlib/Formats/Asn1/AsnReader.sl:163](../../stdlib/Formats/Asn1/AsnReader.sl#L163)</sub>

#### ReadBoolean *method*

```
Result<bool, AsnError> ReadBoolean(Optional<Asn1Tag> expectedTag)
```

The next `BOOLEAN`.

**Parameters**

- `expectedTag` — the tag in place of `BOOLEAN`

**Fails with**

- [AsnError.UnexpectedTag](#unexpectedtag-case) — the next value has another tag
- [AsnError.BadLength](#badlength-case) — the contents are not one octet
- [AsnError.NonMinimalEncoding](#nonminimalencoding-case) — under DER, an octet other than `0x00` or `0xFF`

<sub>[stdlib/Formats/Asn1/AsnReader.sl:178](../../stdlib/Formats/Asn1/AsnReader.sl#L178)</sub>

#### ReadNull *method*

```
AsnError ReadNull(Optional<Asn1Tag> expectedTag)
```

The next `NULL`.

**Parameters**

- `expectedTag` — the tag in place of `NULL`

**Returns** &nbsp; `AsnError.None`, or why the next value is not a `NULL`

<sub>[stdlib/Formats/Asn1/AsnReader.sl:200](../../stdlib/Formats/Asn1/AsnReader.sl#L200)</sub>

#### ReadIntegerBytes *method*

```
Result<ReadOnlySpan<byte>, AsnError> ReadIntegerBytes(Optional<Asn1Tag> expectedTag)
```

The contents of the next `INTEGER`: two's complement, big-endian, in
the fewest octets that hold it.

What a key's modulus or a certificate's serial number is read with,
since neither fits a `long`.

**Parameters**

- `expectedTag` — the tag in place of `INTEGER`

**Fails with**

- [AsnError.UnexpectedTag](#unexpectedtag-case) — the next value has another tag
- [AsnError.BadLength](#badlength-case) — there are no contents
- [AsnError.NonMinimalEncoding](#nonminimalencoding-case) — a leading `0x00` or `0xFF` that says nothing

**See also** &nbsp; [AsnReader.ReadInt64](#readint64-method)

<sub>[stdlib/Formats/Asn1/AsnReader.sl:222](../../stdlib/Formats/Asn1/AsnReader.sl#L222)</sub>

#### ReadInt64 *method*

```
Result<long, AsnError> ReadInt64(Optional<Asn1Tag> expectedTag)
```

The next `INTEGER`, as a `long`.

**Parameters**

- `expectedTag` — the tag in place of `INTEGER`

**Fails with**

- [AsnError.UnexpectedTag](#unexpectedtag-case) — the next value has another tag
- [AsnError.BadLength](#badlength-case) — there are no contents
- [AsnError.NonMinimalEncoding](#nonminimalencoding-case) — a leading `0x00` or `0xFF` that says nothing
- [AsnError.OutOfRange](#outofrange-case) — the value does not fit a `long`

**See also** &nbsp; [AsnReader.ReadUInt64](#readuint64-method)

<sub>[stdlib/Formats/Asn1/AsnReader.sl:236](../../stdlib/Formats/Asn1/AsnReader.sl#L236)</sub>

#### ReadUInt64 *method*

```
Result<ulong, AsnError> ReadUInt64(Optional<Asn1Tag> expectedTag)
```

The next `INTEGER`, as a `ulong`.

**Parameters**

- `expectedTag` — the tag in place of `INTEGER`

**Fails with**

- [AsnError.UnexpectedTag](#unexpectedtag-case) — the next value has another tag
- [AsnError.BadLength](#badlength-case) — there are no contents
- [AsnError.NonMinimalEncoding](#nonminimalencoding-case) — a leading `0x00` or `0xFF` that says nothing
- [AsnError.OutOfRange](#outofrange-case) — the value is negative or does not fit a `ulong`

**See also** &nbsp; [AsnReader.ReadInt64](#readint64-method)

<sub>[stdlib/Formats/Asn1/AsnReader.sl:250](../../stdlib/Formats/Asn1/AsnReader.sl#L250)</sub>

#### ReadEnumeratedValue *method*

```
Result<long, AsnError> ReadEnumeratedValue(Optional<Asn1Tag> expectedTag)
```

The next `ENUMERATED`, as a `long`.

**Parameters**

- `expectedTag` — the tag in place of `ENUMERATED`

**Fails with**

- [AsnError.UnexpectedTag](#unexpectedtag-case) — the next value has another tag
- [AsnError.BadLength](#badlength-case) — there are no contents
- [AsnError.NonMinimalEncoding](#nonminimalencoding-case) — a leading `0x00` or `0xFF` that says nothing
- [AsnError.OutOfRange](#outofrange-case) — the value does not fit a `long`

<sub>[stdlib/Formats/Asn1/AsnReader.sl:281](../../stdlib/Formats/Asn1/AsnReader.sl#L281)</sub>

#### ReadObjectIdentifier *method*

```
Result<String, AsnError> ReadObjectIdentifier(Optional<Asn1Tag> expectedTag)
```

The next `OBJECT IDENTIFIER`, dotted: `1.2.840.113549`.

**Parameters**

- `expectedTag` — the tag in place of `OBJECT IDENTIFIER`

**Fails with**

- [AsnError.UnexpectedTag](#unexpectedtag-case) — the next value has another tag
- [AsnError.BadLength](#badlength-case) — there are no contents
- [AsnError.NonMinimalEncoding](#nonminimalencoding-case) — an arc padded with a leading `0x80`
- [AsnError.Malformed](#malformed-case) — the last arc does not end
- [AsnError.OutOfRange](#outofrange-case) — an arc does not fit a `ulong`

**See also** &nbsp; [Oid.ToDottedString](#todottedstring-method)

<sub>[stdlib/Formats/Asn1/AsnReader.sl:296](../../stdlib/Formats/Asn1/AsnReader.sl#L296)</sub>

#### ReadBitString *method*

```
Result<ReadOnlySpan<byte>, AsnError> ReadBitString(out int unusedBitCount, Optional<Asn1Tag> expectedTag)
```

The next `BIT STRING`: its octets, and in `unusedBitCount` how many
bits at the end of the last one are not part of the value.

**Parameters**

- `unusedBitCount` — zero to seven; zero when the read fails
- `expectedTag` — the tag in place of `BIT STRING`

**Fails with**

- [AsnError.UnexpectedTag](#unexpectedtag-case) — the next value has another tag
- [AsnError.BadLength](#badlength-case) — there are no contents at all
- [AsnError.Malformed](#malformed-case) — more than seven unused bits, or unused bits with no octet to hold them
- [AsnError.NonMinimalEncoding](#nonminimalencoding-case) — under DER, an unused bit that is not zero, or the constructed form
- [AsnError.Unsupported](#unsupported-case) — under BER, the constructed form

<sub>[stdlib/Formats/Asn1/AsnReader.sl:323](../../stdlib/Formats/Asn1/AsnReader.sl#L323)</sub>

#### ReadOctetString *method*

```
Result<ReadOnlySpan<byte>, AsnError> ReadOctetString(Optional<Asn1Tag> expectedTag)
```

The contents of the next `OCTET STRING`.

**Parameters**

- `expectedTag` — the tag in place of `OCTET STRING`

**Fails with**

- [AsnError.UnexpectedTag](#unexpectedtag-case) — the next value has another tag
- [AsnError.NonMinimalEncoding](#nonminimalencoding-case) — under DER, the constructed form
- [AsnError.Unsupported](#unsupported-case) — under BER, the constructed form

<sub>[stdlib/Formats/Asn1/AsnReader.sl:356](../../stdlib/Formats/Asn1/AsnReader.sl#L356)</sub>

#### ReadCharacterString *method*

```
Result<String, AsnError> ReadCharacterString(UniversalTagNumber encodingType, Optional<Asn1Tag> expectedTag)
```

The next character string of type `encodingType`, as text.

| Type | What it may hold |
|---|---|
| `Utf8String` | well-formed UTF-8 |
| `PrintableString` | letters, digits, space and `'()+,-./:=?` |
| `IA5String` | ASCII, `0x00` to `0x7F` |
| `VisibleString` | printable ASCII, `0x20` to `0x7E` |
| `NumericString` | digits and space |
| `T61String` | any octet, read as Latin-1 |
| `BmpString` | UCS-2 big-endian, no surrogates |
| `UniversalString` | UCS-4 big-endian, scalar values only |

**Parameters**

- `encodingType` — which of the types above
- `expectedTag` — the tag in place of `encodingType`'s own

**Fails with**

- [AsnError.UnexpectedTag](#unexpectedtag-case) — the next value has another tag
- [AsnError.BadStringContent](#badstringcontent-case) — a character the type does not allow
- [AsnError.NonMinimalEncoding](#nonminimalencoding-case) — under DER, the constructed form
- [AsnError.Unsupported](#unsupported-case) — `encodingType` is not in the table, or under BER the constructed form

<sub>[stdlib/Formats/Asn1/AsnReader.sl:387](../../stdlib/Formats/Asn1/AsnReader.sl#L387)</sub>

#### ReadUtcTime *method*

```
Result<long, AsnError> ReadUtcTime(Optional<Asn1Tag> expectedTag)
```

The next `UTCTime`, as seconds since 1970-01-01 UTC.

The year has two digits and RFC 5280 says which century: `50` to `99`
are 1950 to 1999, and `00` to `49` are 2000 to 2049. DER requires
`YYMMDDhhmmssZ` exactly; BER also accepts no seconds and an offset of
`+hhmm` or `-hhmm` in place of the `Z`.

**Parameters**

- `expectedTag` — the tag in place of `UTCTime`

**Fails with**

- [AsnError.UnexpectedTag](#unexpectedtag-case) — the next value has another tag
- [AsnError.BadTime](#badtime-case) — not the form the rules require, or not a real moment

**See also** &nbsp; [ConvertAsnTimeToDateTimeOffset](#convertasntimetodatetimeoffset-function)

<sub>[stdlib/Formats/Asn1/AsnReader.sl:417](../../stdlib/Formats/Asn1/AsnReader.sl#L417)</sub>

#### ReadGeneralizedTime *method*

```
Result<long, AsnError> ReadGeneralizedTime(Optional<Asn1Tag> expectedTag)
```

The next `GeneralizedTime`, as seconds since 1970-01-01 UTC.

DER requires `YYYYMMDDhhmmssZ`, optionally with a fraction of a second
after a `.` that does not end in `0`. BER also accepts a `,`, the
minutes and seconds left off, and an offset in place of the `Z`.
**The fraction is checked and dropped**, since the answer is whole
seconds; RFC 5280 forbids one in a certificate anyway.

**Parameters**

- `expectedTag` — the tag in place of `GeneralizedTime`

**Fails with**

- [AsnError.UnexpectedTag](#unexpectedtag-case) — the next value has another tag
- [AsnError.BadTime](#badtime-case) — not the form the rules require, or not a real moment
- [AsnError.Unsupported](#unsupported-case) — under BER, a local time with no zone, or a fraction of an hour or a minute

**See also** &nbsp; [ConvertAsnTimeToDateTimeOffset](#convertasntimetodatetimeoffset-function)

<sub>[stdlib/Formats/Asn1/AsnReader.sl:444](../../stdlib/Formats/Asn1/AsnReader.sl#L444)</sub>

### AsnWriter *class*

```
sealed class AsnWriter
```

Builds DER, one value after another.

```csharp
var writer = new AsnWriter();
writer.PushSequence();
    writer.WriteInteger(2);
    writer.PushSequence(new Asn1Tag(TagClass.ContextSpecific, 0, true));
        writer.WriteBoolean(true);
    writer.PopSequence();
writer.PopSequence();
byte[] der = writer.Encode();
```

**Everything written is DER.** BER's freedoms are all a reader's; a writer
never needs one, so there is no rule set to choose.

**A write that can be refused returns an `AsnError`** — an identifier that
is not one, a character a string type does not allow, a time outside the
years its type names — and writes nothing when it does. The rest cannot
fail and return nothing.

**Push and Pop MUST pair.** A `Pop` with nothing open, a `PopSetOf` for a
`PushSequence`, and an `Encode` with anything still open are mistakes in
the program rather than in its data, and abort as an array index past the
end does.

<sub>[stdlib/Formats/Asn1/AsnWriter.sl:49](../../stdlib/Formats/Asn1/AsnWriter.sl#L49)</sub>

#### Depth *property*

```
nuint Depth { get; }
```

How many sequences and sets are open.

<sub>[stdlib/Formats/Asn1/AsnWriter.sl:66](../../stdlib/Formats/Asn1/AsnWriter.sl#L66)</sub>

#### Encode *method*

```
byte[] Encode()
```

What has been written, as one run of bytes.

Aborts when a sequence or a set is still open, since its length is not
yet known.

<sub>[stdlib/Formats/Asn1/AsnWriter.sl:72](../../stdlib/Formats/Asn1/AsnWriter.sl#L72)</sub>

#### PushSequence *method*

```
void PushSequence(Optional<Asn1Tag> tag)
```

Opens a `SEQUENCE`, which lasts until the matching `PopSequence`.

**Parameters**

- `tag` — the tag in place of `SEQUENCE`; a context tag here is explicit tagging

**See also** &nbsp; [AsnWriter.PopSequence](#popsequence-method)

<sub>[stdlib/Formats/Asn1/AsnWriter.sl:89](../../stdlib/Formats/Asn1/AsnWriter.sl#L89)</sub>

#### PopSequence *method*

```
void PopSequence()
```

Closes the innermost `PushSequence`.

<sub>[stdlib/Formats/Asn1/AsnWriter.sl:95](../../stdlib/Formats/Asn1/AsnWriter.sl#L95)</sub>

#### PushSetOf *method*

```
void PushSetOf(Optional<Asn1Tag> tag)
```

Opens a `SET OF`, which lasts until the matching `PopSetOf`.

**Parameters**

- `tag` — the tag in place of `SET`

**See also** &nbsp; [AsnWriter.PopSetOf](#popsetof-method)

<sub>[stdlib/Formats/Asn1/AsnWriter.sl:104](../../stdlib/Formats/Asn1/AsnWriter.sl#L104)</sub>

#### PopSetOf *method*

```
void PopSetOf()
```

Closes the innermost `PushSetOf`, sorting its elements into the order
DER requires.

<sub>[stdlib/Formats/Asn1/AsnWriter.sl:111](../../stdlib/Formats/Asn1/AsnWriter.sl#L111)</sub>

#### WriteEncodedValue *method*

```
AsnError WriteEncodedValue(ReadOnlySpan<byte> encoded)
```

One value that is already encoded, copied as it is.

Its tag and length are checked; its contents are not.

**Parameters**

- `encoded` — exactly one whole value

**Returns** &nbsp; `AsnError.None`, or why `encoded` is not one DER value

<sub>[stdlib/Formats/Asn1/AsnWriter.sl:122](../../stdlib/Formats/Asn1/AsnWriter.sl#L122)</sub>

#### WriteBoolean *method*

```
void WriteBoolean(bool value, Optional<Asn1Tag> tag)
```

A `BOOLEAN`: `0xFF` for true, as DER requires.

**Parameters**

- `value` — what to write
- `tag` — the tag in place of `BOOLEAN`

<sub>[stdlib/Formats/Asn1/AsnWriter.sl:139](../../stdlib/Formats/Asn1/AsnWriter.sl#L139)</sub>

#### WriteNull *method*

```
void WriteNull(Optional<Asn1Tag> tag)
```

A `NULL`.

**Parameters**

- `tag` — the tag in place of `NULL`

<sub>[stdlib/Formats/Asn1/AsnWriter.sl:148](../../stdlib/Formats/Asn1/AsnWriter.sl#L148)</sub>

#### WriteInteger *method*

```
void WriteInteger(long value, Optional<Asn1Tag> tag)
```

An `INTEGER`, in the fewest octets that hold it.

**Parameters**

- `value` — what to write
- `tag` — the tag in place of `INTEGER`

<sub>[stdlib/Formats/Asn1/AsnWriter.sl:157](../../stdlib/Formats/Asn1/AsnWriter.sl#L157)</sub>

#### WriteInteger *method*

```
void WriteInteger(ulong value, Optional<Asn1Tag> tag)
```

An `INTEGER` from an unsigned value, which gains a leading `0x00` when
its top bit is set.

**Parameters**

- `value` — what to write
- `tag` — the tag in place of `INTEGER`

<sub>[stdlib/Formats/Asn1/AsnWriter.sl:167](../../stdlib/Formats/Asn1/AsnWriter.sl#L167)</sub>

#### WriteIntegerBytes *method*

```
AsnError WriteIntegerBytes(ReadOnlySpan<byte> value, Optional<Asn1Tag> tag)
```

An `INTEGER` whose contents are given: two's complement, big-endian,
already minimal.

**Parameters**

- `value` — the contents octets
- `tag` — the tag in place of `INTEGER`

**Returns** &nbsp; `AsnError.BadLength` when `value` is empty, `AsnError.NonMinimalEncoding` when it starts with a redundant octet

**See also** &nbsp; [AsnWriter.WriteIntegerUnsigned](#writeintegerunsigned-method)

<sub>[stdlib/Formats/Asn1/AsnWriter.sl:185](../../stdlib/Formats/Asn1/AsnWriter.sl#L185)</sub>

#### WriteIntegerUnsigned *method*

```
void WriteIntegerUnsigned(ReadOnlySpan<byte> magnitude, Optional<Asn1Tag> tag)
```

An `INTEGER` whose magnitude is given, big-endian and unsigned: what a
serial number or an RSA modulus is held as. Leading zeros are dropped
and one is added back when the top bit is set, so the value is never
read as negative.

**Parameters**

- `magnitude` — the value's octets; empty is zero
- `tag` — the tag in place of `INTEGER`

**See also** &nbsp; [AsnWriter.WriteIntegerBytes](#writeintegerbytes-method)

<sub>[stdlib/Formats/Asn1/AsnWriter.sl:211](../../stdlib/Formats/Asn1/AsnWriter.sl#L211)</sub>

#### WriteEnumeratedValue *method*

```
void WriteEnumeratedValue(long value, Optional<Asn1Tag> tag)
```

An `ENUMERATED`.

**Parameters**

- `value` — what to write
- `tag` — the tag in place of `ENUMERATED`

<sub>[stdlib/Formats/Asn1/AsnWriter.sl:226](../../stdlib/Formats/Asn1/AsnWriter.sl#L226)</sub>

#### WriteObjectIdentifier *method*

```
AsnError WriteObjectIdentifier(String dotted, Optional<Asn1Tag> tag)
```

An `OBJECT IDENTIFIER`, from its dotted form.

**Parameters**

- `dotted` — the identifier, as `1.2.840.113549`
- `tag` — the tag in place of `OBJECT IDENTIFIER`

**Returns** &nbsp; `AsnError.None`, or why `dotted` is not an identifier

**See also** &nbsp; [Oid.FromDottedString](#fromdottedstring-method)

<sub>[stdlib/Formats/Asn1/AsnWriter.sl:237](../../stdlib/Formats/Asn1/AsnWriter.sl#L237)</sub>

#### WriteBitString *method*

```
AsnError WriteBitString(ReadOnlySpan<byte> value, int unusedBitCount, Optional<Asn1Tag> tag)
```

A `BIT STRING` of `value`, the last `unusedBitCount` bits of which are
not part of it.

**Parameters**

- `value` — the octets
- `unusedBitCount` — zero to seven
- `tag` — the tag in place of `BIT STRING`

**Returns** &nbsp; `AsnError.OutOfRange` for more than seven unused bits, `AsnError.Malformed` for unused bits and no octet, and `AsnError.NonMinimalEncoding` when an unused bit is not zero

<sub>[stdlib/Formats/Asn1/AsnWriter.sl:259](../../stdlib/Formats/Asn1/AsnWriter.sl#L259)</sub>

#### WriteOctetString *method*

```
void WriteOctetString(ReadOnlySpan<byte> value, Optional<Asn1Tag> tag)
```

An `OCTET STRING`.

**Parameters**

- `value` — the octets
- `tag` — the tag in place of `OCTET STRING`

<sub>[stdlib/Formats/Asn1/AsnWriter.sl:283](../../stdlib/Formats/Asn1/AsnWriter.sl#L283)</sub>

#### WriteCharacterString *method*

```
AsnError WriteCharacterString(UniversalTagNumber encodingType, String text, Optional<Asn1Tag> tag)
```

A character string of type `encodingType`, from text.

The types and what each may hold are `AsnReader.ReadCharacterString`'s.

**Parameters**

- `encodingType` — which character string type
- `text` — what to write
- `tag` — the tag in place of `encodingType`'s own

**Returns** &nbsp; `AsnError.BadStringContent` for a character the type cannot hold, `AsnError.Unsupported` for a type that is not a character string

<sub>[stdlib/Formats/Asn1/AsnWriter.sl:300](../../stdlib/Formats/Asn1/AsnWriter.sl#L300)</sub>

#### WriteUtcTime *method*

```
AsnError WriteUtcTime(long seconds, Optional<Asn1Tag> tag)
```

A `UTCTime`, as `YYMMDDhhmmssZ`.

**Parameters**

- `seconds` — seconds since 1970-01-01 UTC
- `tag` — the tag in place of `UTCTime`

**Returns** &nbsp; `AsnError.OutOfRange` when the year is outside 1950 to 2049

**See also** &nbsp; [AsnWriter.WriteGeneralizedTime](#writegeneralizedtime-method)

<sub>[stdlib/Formats/Asn1/AsnWriter.sl:322](../../stdlib/Formats/Asn1/AsnWriter.sl#L322)</sub>

#### WriteGeneralizedTime *method*

```
AsnError WriteGeneralizedTime(long seconds, Optional<Asn1Tag> tag)
```

A `GeneralizedTime`, as `YYYYMMDDhhmmssZ`.

**Parameters**

- `seconds` — seconds since 1970-01-01 UTC
- `tag` — the tag in place of `GeneralizedTime`

**Returns** &nbsp; `AsnError.OutOfRange` when the year is outside 0000 to 9999

**See also** &nbsp; [AsnWriter.WriteUtcTime](#writeutctime-method)

<sub>[stdlib/Formats/Asn1/AsnWriter.sl:338](../../stdlib/Formats/Asn1/AsnWriter.sl#L338)</sub>

### Oid *class*

```
class Oid
```

Object identifiers between their dotted form and their contents octets.

```csharp
byte[] contents = try Oid.FromDottedString("1.2.840.113549");   // 2a 86 48 86 f7 0d
String dotted = try Oid.ToDottedString(contents);
```

The contents are what follows the tag and the length; `AsnReader` and
`AsnWriter` add those. **Every arc MUST fit a `ulong`.** The UUID arcs
under `2.25` are 128 bits and are refused with `AsnError.OutOfRange`;
nothing in X.509 or TLS uses them.

<sub>[stdlib/Formats/Asn1/Oid.sl:35](../../stdlib/Formats/Asn1/Oid.sl#L35)</sub>

#### ToDottedString *method*

```
static Result<String, AsnError> ToDottedString(ReadOnlySpan<byte> contents)
```

The dotted form of an identifier's contents octets.

The first octet group holds two arcs, as X.690 §8.19.4 says: under 40
is `0.n`, under 80 is `1.n`, and the rest is `2.n`.

**Parameters**

- `contents` — the octets after the tag and the length

**Fails with**

- [AsnError.BadLength](#badlength-case) — there are no octets
- [AsnError.NonMinimalEncoding](#nonminimalencoding-case) — an arc starts with the padding octet `0x80`
- [AsnError.Malformed](#malformed-case) — the last arc does not end
- [AsnError.OutOfRange](#outofrange-case) — an arc does not fit a `ulong`

**See also** &nbsp; [Oid.FromDottedString](#fromdottedstring-method)

<sub>[stdlib/Formats/Asn1/Oid.sl:48](../../stdlib/Formats/Asn1/Oid.sl#L48)</sub>

#### FromDottedString *method*

```
static Result<byte[], AsnError> FromDottedString(String dotted)
```

The contents octets of a dotted identifier.

Two arcs at least, decimal digits with no sign and no leading zero, and
one dot between each pair. The first arc is 0, 1 or 2, and under 0 and
1 the second is below 40.

**Parameters**

- `dotted` — the identifier, as `1.2.840.113549`

**Fails with**

- [AsnError.Malformed](#malformed-case) — the text is not in that form
- [AsnError.OutOfRange](#outofrange-case) — an arc does not fit a `ulong`

**See also** &nbsp; [Oid.ToDottedString](#todottedstring-method)

<sub>[stdlib/Formats/Asn1/Oid.sl:119](../../stdlib/Formats/Asn1/Oid.sl#L119)</sub>

### TagClass *enum*

```
enum TagClass
```

Which namespace a tag number belongs to.

The values are the top two bits of an identifier octet, as .NET's are, so
a class is its own encoding.

<sub>[stdlib/Formats/Asn1/TagClass.sl:28](../../stdlib/Formats/Asn1/TagClass.sl#L28)</sub>

#### Universal *case*

```
Universal = 0
```

Defined by X.680 itself: `INTEGER`, `SEQUENCE`, `UTF8String`.

<sub>[stdlib/Formats/Asn1/TagClass.sl:31](../../stdlib/Formats/Asn1/TagClass.sl#L31)</sub>

#### Application *case*

```
Application = 64
```

Defined by a whole specification, once for all of it.

<sub>[stdlib/Formats/Asn1/TagClass.sl:34](../../stdlib/Formats/Asn1/TagClass.sl#L34)</sub>

#### ContextSpecific *case*

```
ContextSpecific = 128
```

Meaningful only inside the type that uses it — the `[0]` and `[3]` of
an X.509 certificate.

<sub>[stdlib/Formats/Asn1/TagClass.sl:38](../../stdlib/Formats/Asn1/TagClass.sl#L38)</sub>

#### Private *case*

```
Private = 192
```

Defined by an organisation for its own use.

<sub>[stdlib/Formats/Asn1/TagClass.sl:41](../../stdlib/Formats/Asn1/TagClass.sl#L41)</sub>

### UniversalTagNumber *enum*

```
enum UniversalTagNumber
```

The tag numbers X.680 assigns in the `Universal` class.

Every one is listed so that a tag read from the wire can be named. Only
some have a reader of their own; the rest are reached through
`AsnReader.ReadEncodedValue`.

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:29](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L29)</sub>

#### EndOfContents *case*

```
EndOfContents = 0
```

Ends an indefinite-length encoding, which this module does not read.

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:32](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L32)</sub>

#### Boolean *case*

```
Boolean = 1
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:33](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L33)</sub>

#### Integer *case*

```
Integer = 2
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:34](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L34)</sub>

#### BitString *case*

```
BitString = 3
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:35](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L35)</sub>

#### OctetString *case*

```
OctetString = 4
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:36](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L36)</sub>

#### Null *case*

```
Null = 5
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:37](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L37)</sub>

#### ObjectIdentifier *case*

```
ObjectIdentifier = 6
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:38](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L38)</sub>

#### ObjectDescriptor *case*

```
ObjectDescriptor = 7
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:39](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L39)</sub>

#### External *case*

```
External = 8
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:40](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L40)</sub>

#### Real *case*

```
Real = 9
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:41](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L41)</sub>

#### Enumerated *case*

```
Enumerated = 10
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:42](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L42)</sub>

#### Embedded *case*

```
Embedded = 11
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:43](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L43)</sub>

#### Utf8String *case*

```
Utf8String = 12
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:44](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L44)</sub>

#### RelativeObjectIdentifier *case*

```
RelativeObjectIdentifier = 13
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:45](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L45)</sub>

#### Time *case*

```
Time = 14
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:46](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L46)</sub>

#### Sequence *case*

```
Sequence = 16
```

`SEQUENCE` and `SEQUENCE OF`, which share a tag.

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:49](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L49)</sub>

#### Set *case*

```
Set = 17
```

`SET` and `SET OF`, which share a tag.

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:52](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L52)</sub>

#### NumericString *case*

```
NumericString = 18
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:53](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L53)</sub>

#### PrintableString *case*

```
PrintableString = 19
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:54](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L54)</sub>

#### T61String *case*

```
T61String = 20
```

TeletexString. Read and written here as Latin-1, as every X.509
implementation in practice does.

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:58](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L58)</sub>

#### VideotexString *case*

```
VideotexString = 21
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:59](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L59)</sub>

#### IA5String *case*

```
IA5String = 22
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:60](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L60)</sub>

#### UtcTime *case*

```
UtcTime = 23
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:61](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L61)</sub>

#### GeneralizedTime *case*

```
GeneralizedTime = 24
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:62](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L62)</sub>

#### GraphicString *case*

```
GraphicString = 25
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:63](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L63)</sub>

#### VisibleString *case*

```
VisibleString = 26
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:64](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L64)</sub>

#### GeneralString *case*

```
GeneralString = 27
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:65](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L65)</sub>

#### UniversalString *case*

```
UniversalString = 28
```

UCS-4, big-endian.

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:68](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L68)</sub>

#### UnrestrictedCharacterString *case*

```
UnrestrictedCharacterString = 29
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:69](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L69)</sub>

#### BmpString *case*

```
BmpString = 30
```

UCS-2, big-endian: the Basic Multilingual Plane and nothing past it.

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:72](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L72)</sub>

#### Date *case*

```
Date = 31
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:73](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L73)</sub>

#### TimeOfDay *case*

```
TimeOfDay = 32
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:74](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L74)</sub>

#### DateTime *case*

```
DateTime = 33
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:75](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L75)</sub>

#### Duration *case*

```
Duration = 34
```

*No documentation.*

<sub>[stdlib/Formats/Asn1/UniversalTagNumber.sl:76](../../stdlib/Formats/Asn1/UniversalTagNumber.sl#L76)</sub>

## Functions

### ConvertAsnTimeToDateTimeOffset *function*

```
Result<DateTimeOffset, AsnError> ConvertAsnTimeToDateTimeOffset(long seconds)
```

An ASN.1 time as a `DateTimeOffset`, where one can hold it.

**Parameters**

- `seconds` — seconds since 1970-01-01 UTC, as `AsnReader.ReadUtcTime` answers

**Fails with**

- [AsnError.OutOfRange](#outofrange-case) — the moment is before 1677-09-21 or after 2262-04-11, where a count of nanoseconds in a `long` ends

**See also** &nbsp; [AsnReader.ReadGeneralizedTime](#readgeneralizedtime-method)

<sub>[stdlib/Formats/Asn1/Asn1.sl:90](../../stdlib/Formats/Asn1/Asn1.sl#L90)</sub>

### DescribeAsnError *function*

```
String DescribeAsnError(AsnError error)
```

A sentence describing an error, for a message a person will read.

<sub>[stdlib/Formats/Asn1/Asn1.sl:65](../../stdlib/Formats/Asn1/Asn1.sl#L65)</sub>

