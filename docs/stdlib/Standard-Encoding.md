# Standard.Encoding

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Text as bytes, in whichever encoding somebody else chose.

A `String` is UTF-8 and there is deliberately no second string type (§3).
That settles what text *is* inside a program and says nothing about what
arrives from outside it -- a file written by a Windows editor, a protocol
header that predates Unicode, a registry value in UTF-16. This module is the
crossing, and every crossing is explicit.

The shape is .NET's, adapted to what this language has: an interface rather
than an abstract class with static instances, because a static needs a
Sendable type and an initializer that `--shared` has nowhere to run. So the
encodings come from functions -- `Encoding.Utf8()` -- and a program may add
one of its own by implementing `IEncoding`.

Both directions are lossy by default and say so, which is the same rule the
language already applies to `ToUtf16` and `Text.FromUtf16`: what cannot be
decoded becomes U+FFFD, and what cannot be encoded becomes `?`. `TryGetString`
is the strict form for a caller that needs to know rather than to cope, and
`CanRepresent` answers the other direction before anything is written.

## Contents

**Types** &nbsp; [AsciiEncoding](#asciiencoding-class) &middot; [EncodingError](#encodingerror-enum) &middot; [IEncoding](#iencoding-interface) &middot; [Latin1Encoding](#latin1encoding-class) &middot; [SingleByteEncoding](#singlebyteencoding-class) &middot; [Utf16Encoding](#utf16encoding-class) &middot; [Utf32Encoding](#utf32encoding-class) &middot; [Utf8Encoding](#utf8encoding-class) &middot; [Windows1252Encoding](#windows1252encoding-class)

**Functions** &nbsp; [Ascii](#ascii-function) &middot; [Detect](#detect-function) &middot; [Latin1](#latin1-function) &middot; [Utf16](#utf16-function) &middot; [Utf16BigEndian](#utf16bigendian-function) &middot; [Utf32](#utf32-function) &middot; [Utf32BigEndian](#utf32bigendian-function) &middot; [Utf8](#utf8-function) &middot; [Windows1252](#windows1252-function) &middot; [WithoutPreamble](#withoutpreamble-function)

## Types

### AsciiEncoding *class*

```
class AsciiEncoding : SingleByteEncoding
```

US-ASCII. A byte above 127 is not ASCII, and reads as U+FFFD.

<sub>[stdlib/Encoding.sl:549](../../stdlib/Encoding.sl#L549)</sub>

#### Name *method*

```
override String Name()
```

`"us-ascii"`.

<sub>[stdlib/Encoding.sl:552](../../stdlib/Encoding.sl#L552)</sub>

#### ToScalar *method*

```
override char32 ToScalar(byte value)
```

The byte itself below 128, and U+FFFD at or above it.

<sub>[stdlib/Encoding.sl:555](../../stdlib/Encoding.sl#L555)</sub>

#### FromScalar *method*

```
override int FromScalar(char32 scalar)
```

The scalar itself below U+0080, and -1 at or above it.

<sub>[stdlib/Encoding.sl:561](../../stdlib/Encoding.sl#L561)</sub>

### EncodingError *enum*

```
enum EncodingError
```

Why a decode failed, when a caller asked to be told.

<sub>[stdlib/Encoding.sl:46](../../stdlib/Encoding.sl#L46)</sub>

#### Incomplete *case*

```
Incomplete
```

The bytes ended in the middle of a character.

<sub>[stdlib/Encoding.sl:49](../../stdlib/Encoding.sl#L49)</sub>

#### Invalid *case*

```
Invalid
```

A byte or a sequence that this encoding cannot produce.

<sub>[stdlib/Encoding.sl:52](../../stdlib/Encoding.sl#L52)</sub>

### IEncoding *interface*

```
interface IEncoding
```

One way of writing text as bytes.

Implement it to add an encoding; nothing here is closed. The two `Get`
methods are lossy and total, the `Try` one is strict, and `CanRepresent`
asks the encode direction the question `TryGetString` asks of the other.

<sub>[stdlib/Encoding.sl:60](../../stdlib/Encoding.sl#L60)</sub>

#### Name *method*

```
String Name()
```

The name IANA gives it, which is also what an HTTP header would carry.

<sub>[stdlib/Encoding.sl:63](../../stdlib/Encoding.sl#L63)</sub>

#### Preamble *method*

```
byte[] Preamble()
```

The bytes that mark this encoding at the start of a file, if any.

<sub>[stdlib/Encoding.sl:66](../../stdlib/Encoding.sl#L66)</sub>

#### GetByteCount *method*

```
nuint GetByteCount(String text)
```

How many bytes `GetBytes` would produce. Costs a pass, saves an
allocation.

<sub>[stdlib/Encoding.sl:70](../../stdlib/Encoding.sl#L70)</sub>

#### GetBytes *method*

```
byte[] GetBytes(String text)
```

`text` in this encoding. A scalar the encoding cannot write becomes
`?`, which is what .NET's default fallback does and what the caller
almost always wants when the alternative is failing a whole file.

<sub>[stdlib/Encoding.sl:75](../../stdlib/Encoding.sl#L75)</sub>

#### GetString *method*

```
String GetString(byte[] bytes)
```

`bytes` read as this encoding. Anything malformed becomes U+FFFD, so
the result is always valid UTF-8 -- which it must be, because it is a
`String`.

<sub>[stdlib/Encoding.sl:80](../../stdlib/Encoding.sl#L80)</sub>

#### TryGetString *method*

```
Result<String, EncodingError> TryGetString(byte[] bytes)
```

The same, but saying what went wrong instead of papering over it.

<sub>[stdlib/Encoding.sl:83](../../stdlib/Encoding.sl#L83)</sub>

#### CanRepresent *method*

```
bool CanRepresent(char32 scalar)
```

Whether this encoding can write that scalar at all.

<sub>[stdlib/Encoding.sl:86](../../stdlib/Encoding.sl#L86)</sub>

### Latin1Encoding *class*

```
class Latin1Encoding : SingleByteEncoding
```

ISO-8859-1, where byte n is code point n for every n. Nothing can fail in
either direction below U+0100, and nothing above it can be written.

<sub>[stdlib/Encoding.sl:570](../../stdlib/Encoding.sl#L570)</sub>

#### Name *method*

```
override String Name()
```

`"iso-8859-1"`.

<sub>[stdlib/Encoding.sl:573](../../stdlib/Encoding.sl#L573)</sub>

#### ToScalar *method*

```
override char32 ToScalar(byte value)
```

Byte n is code point n, for every n. Never U+FFFD, which is what makes
this encoding able to carry any byte sequence at all.

<sub>[stdlib/Encoding.sl:577](../../stdlib/Encoding.sl#L577)</sub>

#### FromScalar *method*

```
override int FromScalar(char32 scalar)
```

The scalar itself below U+0100, and -1 at or above it.

<sub>[stdlib/Encoding.sl:580](../../stdlib/Encoding.sl#L580)</sub>

### SingleByteEncoding *class*

```
abstract class SingleByteEncoding : IEncoding
```

An encoding in which every byte is exactly one character.

Decoding one of these cannot fail: there is no sequence to run out of and no
byte that means nothing, only a table with 256 entries. Encoding can, since
most of Unicode is not in that table, and what cannot be written becomes
`?`.

A base class rather than three copies, because the three differ only in the
table -- and the two that matter differ only in the 32 entries between 0x80
and 0x9F.

<sub>[stdlib/Encoding.sl:491](../../stdlib/Encoding.sl#L491)</sub>

#### ToScalar *method*

```
abstract char32 ToScalar(byte value)
```

What this byte means. Every byte means something.

<sub>[stdlib/Encoding.sl:494](../../stdlib/Encoding.sl#L494)</sub>

#### FromScalar *method*

```
abstract int FromScalar(char32 scalar)
```

Which byte writes this scalar, or -1 when none does.

<sub>[stdlib/Encoding.sl:497](../../stdlib/Encoding.sl#L497)</sub>

#### Name *method*

```
abstract String Name()
```

The IANA name, which each subclass supplies.

<sub>[stdlib/Encoding.sl:500](../../stdlib/Encoding.sl#L500)</sub>

#### Preamble *method*

```
byte[] Preamble()
```

None of these has one: a byte order mark is a Unicode idea.

<sub>[stdlib/Encoding.sl:503](../../stdlib/Encoding.sl#L503)</sub>

#### CanRepresent *method*

```
bool CanRepresent(char32 scalar)
```

Whether the table has a byte for that scalar. Most of Unicode is not in
any of these tables, so this is false far more often than it is true.

<sub>[stdlib/Encoding.sl:507](../../stdlib/Encoding.sl#L507)</sub>

#### GetByteCount *method*

```
nuint GetByteCount(String text)
```

One byte per scalar, always -- so the count is the scalar count, not
the text's byte length.

<sub>[stdlib/Encoding.sl:511](../../stdlib/Encoding.sl#L511)</sub>

#### GetBytes *method*

```
byte[] GetBytes(String text)
```

The text in this encoding, with anything the table cannot write
becoming `?`. Check `CanRepresent` first where losing it matters.

<sub>[stdlib/Encoding.sl:515](../../stdlib/Encoding.sl#L515)</sub>

#### GetString *method*

```
String GetString(byte[] bytes)
```

`bytes` through the table, one character per byte. Cannot fail: every
byte means something, even if that something is U+FFFD.

<sub>[stdlib/Encoding.sl:531](../../stdlib/Encoding.sl#L531)</sub>

#### TryGetString *method*

```
Result<String, EncodingError> TryGetString(byte[] bytes)
```

Never fails, which is the whole character of a single-byte encoding.

<sub>[stdlib/Encoding.sl:542](../../stdlib/Encoding.sl#L542)</sub>

### Utf16Encoding *class*

```
class Utf16Encoding : IEncoding
```

UTF-16, in either byte order.

<sub>[stdlib/Encoding.sl:240](../../stdlib/Encoding.sl#L240)</sub>

#### Name *method*

```
String Name()
```

`"utf-16be"` or `"utf-16le"`, whichever this is.

<sub>[stdlib/Encoding.sl:249](../../stdlib/Encoding.sl#L249)</sub>

#### Preamble *method*

```
byte[] Preamble()
```

FE FF big-endian, FF FE little. Worth writing here, unlike UTF-8's:
without it there is no way to tell the two orders apart.

<sub>[stdlib/Encoding.sl:254](../../stdlib/Encoding.sl#L254)</sub>

#### CanRepresent *method*

```
bool CanRepresent(char32 scalar)
```

Every scalar, in one unit or two.

<sub>[stdlib/Encoding.sl:262](../../stdlib/Encoding.sl#L262)</sub>

#### GetByteCount *method*

```
nuint GetByteCount(String text)
```

Two bytes per unit, so four for a scalar outside the basic plane.
Costs a transcode to count, which is what `GetBytes` then does again.

<sub>[stdlib/Encoding.sl:266](../../stdlib/Encoding.sl#L266)</sub>

#### GetBytes *method*

```
byte[] GetBytes(String text)
```

The text as UTF-16 in this byte order, with no byte order mark --
prepend `Preamble()` if the reader will need one.

<sub>[stdlib/Encoding.sl:270](../../stdlib/Encoding.sl#L270)</sub>

#### GetString *method*

```
String GetString(byte[] bytes)
```

`bytes` read as UTF-16, with an unpaired surrogate or a trailing odd
byte becoming U+FFFD. A byte order mark, if present, is not stripped --
`WithoutPreamble` is what does that.

<sub>[stdlib/Encoding.sl:296](../../stdlib/Encoding.sl#L296)</sub>

#### TryGetString *method*

```
Result<String, EncodingError> TryGetString(byte[] bytes)
```

The strict decode: `Incomplete` for an odd number of bytes or a high
surrogate at the end, `Invalid` for a surrogate that is not paired.

<sub>[stdlib/Encoding.sl:337](../../stdlib/Encoding.sl#L337)</sub>

### Utf32Encoding *class*

```
class Utf32Encoding : IEncoding
```

UTF-32: one scalar per four bytes, and no surrogates anywhere.

<sub>[stdlib/Encoding.sl:374](../../stdlib/Encoding.sl#L374)</sub>

#### Name *method*

```
String Name()
```

`"utf-32be"` or `"utf-32le"`, whichever this is.

<sub>[stdlib/Encoding.sl:383](../../stdlib/Encoding.sl#L383)</sub>

#### Preamble *method*

```
byte[] Preamble()
```

Four bytes, and the little-endian one begins with UTF-16LE's -- which
is why `Detect` tests UTF-32 first.

<sub>[stdlib/Encoding.sl:387](../../stdlib/Encoding.sl#L387)</sub>

#### CanRepresent *method*

```
bool CanRepresent(char32 scalar)
```

Every scalar, in exactly four bytes.

<sub>[stdlib/Encoding.sl:395](../../stdlib/Encoding.sl#L395)</sub>

#### GetByteCount *method*

```
nuint GetByteCount(String text)
```

Four bytes per scalar. Costs a pass to count the scalars.

<sub>[stdlib/Encoding.sl:398](../../stdlib/Encoding.sl#L398)</sub>

#### GetBytes *method*

```
byte[] GetBytes(String text)
```

The text as UTF-32 in this byte order, with no byte order mark.

<sub>[stdlib/Encoding.sl:401](../../stdlib/Encoding.sl#L401)</sub>

#### GetString *method*

```
String GetString(byte[] bytes)
```

`bytes` read as UTF-32, with a value that is not a scalar -- a
surrogate, or anything past U+10FFFF -- becoming U+FFFD. Trailing bytes
that do not make a whole four are dropped.

<sub>[stdlib/Encoding.sl:431](../../stdlib/Encoding.sl#L431)</sub>

#### TryGetString *method*

```
Result<String, EncodingError> TryGetString(byte[] bytes)
```

The strict decode: `Incomplete` when the length is not a multiple of
four, `Invalid` for a value that is not a scalar.

<sub>[stdlib/Encoding.sl:449](../../stdlib/Encoding.sl#L449)</sub>

### Utf8Encoding *class*

```
class Utf8Encoding : IEncoding
```

UTF-8, which is what a `String` already holds.

Both directions are a copy rather than a transcode. `GetString` still has to
validate, because a `byte[]` from outside the program is not a `String` and
has promised nothing.

<sub>[stdlib/Encoding.sl:155](../../stdlib/Encoding.sl#L155)</sub>

#### Name *method*

```
String Name()
```

`"utf-8"`.

<sub>[stdlib/Encoding.sl:158](../../stdlib/Encoding.sl#L158)</sub>

#### Preamble *method*

```
byte[] Preamble()
```

EF BB BF. UTF-8 needs no byte order mark -- there is only one order --
so this is what to *recognise*, not what to write by habit.

<sub>[stdlib/Encoding.sl:162](../../stdlib/Encoding.sl#L162)</sub>

#### GetByteCount *method*

```
nuint GetByteCount(String text)
```

The length the text already has. O(1), since no transcode is needed.

<sub>[stdlib/Encoding.sl:165](../../stdlib/Encoding.sl#L165)</sub>

#### GetBytes *method*

```
byte[] GetBytes(String text)
```

The text's own bytes. A copy, not a transcode.

<sub>[stdlib/Encoding.sl:168](../../stdlib/Encoding.sl#L168)</sub>

#### CanRepresent *method*

```
bool CanRepresent(char32 scalar)
```

Every scalar; that is what UTF-8 is for.

<sub>[stdlib/Encoding.sl:171](../../stdlib/Encoding.sl#L171)</sub>

#### GetString *method*

```
String GetString(byte[] bytes)
```

`bytes` validated, with each malformed byte replaced by U+FFFD.

One replacement per bad byte rather than per bad sequence, so a run of
rubbish is as many U+FFFDs as it is bytes.

<sub>[stdlib/Encoding.sl:177](../../stdlib/Encoding.sl#L177)</sub>

#### TryGetString *method*

```
Result<String, EncodingError> TryGetString(byte[] bytes)
```

The strict decode: `Invalid` for anything that is not a scalar, and
`Incomplete` for a sequence the input ran out during.

Stricter than `GetString`, and deliberately: an overlong sequence, a
surrogate and a value past U+10FFFF are each refused, because each is a
way of spelling something that is not a character and each has been a
security hole in a decoder that accepted it.

<sub>[stdlib/Encoding.sl:206](../../stdlib/Encoding.sl#L206)</sub>

### Windows1252Encoding *class*

```
class Windows1252Encoding : SingleByteEncoding
```

Windows-1252: Latin-1, except that 0x80 to 0x9F carry punctuation rather
than C1 controls. Five of those 32 positions are unassigned and read as
U+FFFD.

<sub>[stdlib/Encoding.sl:590](../../stdlib/Encoding.sl#L590)</sub>

#### Name *method*

```
override String Name()
```

`"windows-1252"`.

<sub>[stdlib/Encoding.sl:593](../../stdlib/Encoding.sl#L593)</sub>

#### ToScalar *method*

```
override char32 ToScalar(byte value)
```

Latin-1 outside 0x80 to 0x9F, and the punctuation table inside it.
Five of those 32 positions are unassigned and read as U+FFFD.

<sub>[stdlib/Encoding.sl:597](../../stdlib/Encoding.sl#L597)</sub>

#### FromScalar *method*

```
override int FromScalar(char32 scalar)
```

The Latin-1 byte where there is one, else a scan of the 32-entry
punctuation table, else -1.

<sub>[stdlib/Encoding.sl:606](../../stdlib/Encoding.sl#L606)</sub>

## Functions

### Ascii *function*

```
IEncoding Ascii()
```

US-ASCII: seven bits, and nothing above them.

<sub>[stdlib/Encoding.sl:107](../../stdlib/Encoding.sl#L107)</sub>

### Detect *function*

```
IEncoding? Detect(byte[] bytes)
```

Which encoding a byte order mark says this is, or null when there is none.

UTF-32LE is tested before UTF-16LE deliberately: a UTF-32LE mark begins with
the two bytes of a UTF-16LE one, so the longer test has to come first or
every UTF-32 file reads as UTF-16 whose first character is NUL.

<sub>[stdlib/Encoding.sl:124](../../stdlib/Encoding.sl#L124)</sub>

### Latin1 *function*

```
IEncoding Latin1()
```

ISO-8859-1, in which every byte is the code point of the same number. That
makes it the one encoding that can carry any byte sequence without failing,
which is why it is what a protocol reaches for when it does not know.

<sub>[stdlib/Encoding.sl:112](../../stdlib/Encoding.sl#L112)</sub>

### Utf16 *function*

```
IEncoding Utf16()
```

UTF-16, little-endian -- the one Windows means by "Unicode".

<sub>[stdlib/Encoding.sl:95](../../stdlib/Encoding.sl#L95)</sub>

### Utf16BigEndian *function*

```
IEncoding Utf16BigEndian()
```

UTF-16, big-endian.

<sub>[stdlib/Encoding.sl:98](../../stdlib/Encoding.sl#L98)</sub>

### Utf32 *function*

```
IEncoding Utf32()
```

UTF-32, little-endian: one scalar per four bytes, no surrogates.

<sub>[stdlib/Encoding.sl:101](../../stdlib/Encoding.sl#L101)</sub>

### Utf32BigEndian *function*

```
IEncoding Utf32BigEndian()
```

UTF-32, big-endian.

<sub>[stdlib/Encoding.sl:104](../../stdlib/Encoding.sl#L104)</sub>

### Utf8 *function*

```
IEncoding Utf8()
```

UTF-8: what a `String` already is, so both directions are a copy.

<sub>[stdlib/Encoding.sl:92](../../stdlib/Encoding.sl#L92)</sub>

### Windows1252 *function*

```
IEncoding Windows1252()
```

Windows-1252: Latin-1 with the C1 control range replaced by punctuation --
curly quotes, the dash, the euro. Most text labelled ISO-8859-1 is really
this, because that is what a Windows editor wrote.

<sub>[stdlib/Encoding.sl:117](../../stdlib/Encoding.sl#L117)</sub>

### WithoutPreamble *function*

```
byte[] WithoutPreamble(IEncoding encoding, byte[] bytes)
```

`bytes` without the byte order mark `encoding` writes, if it is there.

<sub>[stdlib/Encoding.sl:140](../../stdlib/Encoding.sl#L140)</sub>

