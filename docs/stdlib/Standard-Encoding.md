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

**Types** &nbsp; [AsciiEncoding](#asciiencoding) &middot; [EncodingError](#encodingerror) &middot; [IEncoding](#iencoding) &middot; [Latin1Encoding](#latin1encoding) &middot; [SingleByteEncoding](#singlebyteencoding) &middot; [Utf16Encoding](#utf16encoding) &middot; [Utf32Encoding](#utf32encoding) &middot; [Utf8Encoding](#utf8encoding) &middot; [Windows1252Encoding](#windows1252encoding)

**Functions** &nbsp; [Ascii](#ascii) &middot; [Detect](#detect) &middot; [Latin1](#latin1) &middot; [Utf16](#utf16) &middot; [Utf16BigEndian](#utf16bigendian) &middot; [Utf32](#utf32) &middot; [Utf32BigEndian](#utf32bigendian) &middot; [Utf8](#utf8) &middot; [Windows1252](#windows1252) &middot; [WithoutPreamble](#withoutpreamble)

## Types

### AsciiEncoding *class*

```
class AsciiEncoding : SingleByteEncoding
```

US-ASCII. A byte above 127 is not ASCII, and reads as U+FFFD.

<sub>[stdlib/Encoding.sl:480](../../stdlib/Encoding.sl#L480)</sub>

#### Name *method*

```
override String Name()
```

`"us-ascii"`.

<sub>[stdlib/Encoding.sl:482](../../stdlib/Encoding.sl#L482)</sub>

#### ToScalar *method*

```
override char32 ToScalar(byte value)
```

The byte itself below 128, and U+FFFD at or above it.

<sub>[stdlib/Encoding.sl:485](../../stdlib/Encoding.sl#L485)</sub>

#### FromScalar *method*

```
override int FromScalar(char32 scalar)
```

The scalar itself below U+0080, and -1 at or above it.

<sub>[stdlib/Encoding.sl:490](../../stdlib/Encoding.sl#L490)</sub>

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

<sub>[stdlib/Encoding.sl:48](../../stdlib/Encoding.sl#L48)</sub>

#### Invalid *case*

```
Invalid
```

A byte or a sequence that this encoding cannot produce.

<sub>[stdlib/Encoding.sl:51](../../stdlib/Encoding.sl#L51)</sub>

### IEncoding *interface*

```
interface IEncoding
```

One way of writing text as bytes.

Implement it to add an encoding; nothing here is closed. The two `Get`
methods are lossy and total, the `Try` one is strict, and `CanRepresent`
asks the encode direction the question `TryGetString` asks of the other.

<sub>[stdlib/Encoding.sl:59](../../stdlib/Encoding.sl#L59)</sub>

#### Name *method*

```
String Name()
```

The name IANA gives it, which is also what an HTTP header would carry.

<sub>[stdlib/Encoding.sl:61](../../stdlib/Encoding.sl#L61)</sub>

#### Preamble *method*

```
byte[] Preamble()
```

The bytes that mark this encoding at the start of a file, if any.

<sub>[stdlib/Encoding.sl:64](../../stdlib/Encoding.sl#L64)</sub>

#### GetByteCount *method*

```
nuint GetByteCount(String text)
```

How many bytes `GetBytes` would produce. Costs a pass, saves an
allocation.

<sub>[stdlib/Encoding.sl:68](../../stdlib/Encoding.sl#L68)</sub>

#### GetBytes *method*

```
byte[] GetBytes(String text)
```

`text` in this encoding. A scalar the encoding cannot write becomes
`?`, which is what .NET's default fallback does and what the caller
almost always wants when the alternative is failing a whole file.

<sub>[stdlib/Encoding.sl:73](../../stdlib/Encoding.sl#L73)</sub>

#### GetString *method*

```
String GetString(byte[] bytes)
```

`bytes` read as this encoding. Anything malformed becomes U+FFFD, so
the result is always valid UTF-8 -- which it must be, because it is a
`String`.

<sub>[stdlib/Encoding.sl:78](../../stdlib/Encoding.sl#L78)</sub>

#### TryGetString *method*

```
Result<String, EncodingError> TryGetString(byte[] bytes)
```

The same, but saying what went wrong instead of papering over it.

<sub>[stdlib/Encoding.sl:81](../../stdlib/Encoding.sl#L81)</sub>

#### CanRepresent *method*

```
bool CanRepresent(char32 scalar)
```

Whether this encoding can write that scalar at all.

<sub>[stdlib/Encoding.sl:84](../../stdlib/Encoding.sl#L84)</sub>

### Latin1Encoding *class*

```
class Latin1Encoding : SingleByteEncoding
```

ISO-8859-1, where byte n is code point n for every n. Nothing can fail in
either direction below U+0100, and nothing above it can be written.

<sub>[stdlib/Encoding.sl:498](../../stdlib/Encoding.sl#L498)</sub>

#### Name *method*

```
override String Name()
```

`"iso-8859-1"`.

<sub>[stdlib/Encoding.sl:500](../../stdlib/Encoding.sl#L500)</sub>

#### ToScalar *method*

```
override char32 ToScalar(byte value)
```

Byte n is code point n, for every n. Never U+FFFD, which is what makes
this encoding able to carry any byte sequence at all.

<sub>[stdlib/Encoding.sl:504](../../stdlib/Encoding.sl#L504)</sub>

#### FromScalar *method*

```
override int FromScalar(char32 scalar)
```

The scalar itself below U+0100, and -1 at or above it.

<sub>[stdlib/Encoding.sl:507](../../stdlib/Encoding.sl#L507)</sub>

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

<sub>[stdlib/Encoding.sl:428](../../stdlib/Encoding.sl#L428)</sub>

#### ToScalar *method*

```
abstract char32 ToScalar(byte value)
```

What this byte means. Every byte means something.

<sub>[stdlib/Encoding.sl:430](../../stdlib/Encoding.sl#L430)</sub>

#### FromScalar *method*

```
abstract int FromScalar(char32 scalar)
```

Which byte writes this scalar, or -1 when none does.

<sub>[stdlib/Encoding.sl:433](../../stdlib/Encoding.sl#L433)</sub>

#### Name *method*

```
abstract String Name()
```

The IANA name, which each subclass supplies.

<sub>[stdlib/Encoding.sl:436](../../stdlib/Encoding.sl#L436)</sub>

#### Preamble *method*

```
byte[] Preamble()
```

None of these has one: a byte order mark is a Unicode idea.

<sub>[stdlib/Encoding.sl:439](../../stdlib/Encoding.sl#L439)</sub>

#### CanRepresent *method*

```
bool CanRepresent(char32 scalar)
```

Whether the table has a byte for that scalar. Most of Unicode is not in
any of these tables, so this is false far more often than it is true.

<sub>[stdlib/Encoding.sl:443](../../stdlib/Encoding.sl#L443)</sub>

#### GetByteCount *method*

```
nuint GetByteCount(String text)
```

One byte per scalar, always -- so the count is the scalar count, not
the text's byte length.

<sub>[stdlib/Encoding.sl:447](../../stdlib/Encoding.sl#L447)</sub>

#### GetBytes *method*

```
byte[] GetBytes(String text)
```

The text in this encoding, with anything the table cannot write
becoming `?`. Check `CanRepresent` first where losing it matters.

<sub>[stdlib/Encoding.sl:451](../../stdlib/Encoding.sl#L451)</sub>

#### GetString *method*

```
String GetString(byte[] bytes)
```

`bytes` through the table, one character per byte. Cannot fail: every
byte means something, even if that something is U+FFFD.

<sub>[stdlib/Encoding.sl:465](../../stdlib/Encoding.sl#L465)</sub>

#### TryGetString *method*

```
Result<String, EncodingError> TryGetString(byte[] bytes)
```

Never fails, which is the whole character of a single-byte encoding.

<sub>[stdlib/Encoding.sl:474](../../stdlib/Encoding.sl#L474)</sub>

### Utf16Encoding *class*

```
class Utf16Encoding : IEncoding
```

UTF-16, in either byte order.

<sub>[stdlib/Encoding.sl:218](../../stdlib/Encoding.sl#L218)</sub>

#### Name *method*

```
String Name()
```

`"utf-16be"` or `"utf-16le"`, whichever this is.

<sub>[stdlib/Encoding.sl:226](../../stdlib/Encoding.sl#L226)</sub>

#### Preamble *method*

```
byte[] Preamble()
```

FE FF big-endian, FF FE little. Worth writing here, unlike UTF-8's:
without it there is no way to tell the two orders apart.

<sub>[stdlib/Encoding.sl:231](../../stdlib/Encoding.sl#L231)</sub>

#### CanRepresent *method*

```
bool CanRepresent(char32 scalar)
```

Every scalar, in one unit or two.

<sub>[stdlib/Encoding.sl:237](../../stdlib/Encoding.sl#L237)</sub>

#### GetByteCount *method*

```
nuint GetByteCount(String text)
```

Two bytes per unit, so four for a scalar outside the basic plane.
Costs a transcode to count, which is what `GetBytes` then does again.

<sub>[stdlib/Encoding.sl:241](../../stdlib/Encoding.sl#L241)</sub>

#### GetBytes *method*

```
byte[] GetBytes(String text)
```

The text as UTF-16 in this byte order, with no byte order mark --
prepend `Preamble()` if the reader will need one.

<sub>[stdlib/Encoding.sl:245](../../stdlib/Encoding.sl#L245)</sub>

#### GetString *method*

```
String GetString(byte[] bytes)
```

`bytes` read as UTF-16, with an unpaired surrogate or a trailing odd
byte becoming U+FFFD. A byte order mark, if present, is not stripped --
`WithoutPreamble` is what does that.

<sub>[stdlib/Encoding.sl:266](../../stdlib/Encoding.sl#L266)</sub>

#### TryGetString *method*

```
Result<String, EncodingError> TryGetString(byte[] bytes)
```

The strict decode: `Incomplete` for an odd number of bytes or a high
surrogate at the end, `Invalid` for a surrogate that is not paired.

<sub>[stdlib/Encoding.sl:301](../../stdlib/Encoding.sl#L301)</sub>

### Utf32Encoding *class*

```
class Utf32Encoding : IEncoding
```

UTF-32: one scalar per four bytes, and no surrogates anywhere.

<sub>[stdlib/Encoding.sl:329](../../stdlib/Encoding.sl#L329)</sub>

#### Name *method*

```
String Name()
```

`"utf-32be"` or `"utf-32le"`, whichever this is.

<sub>[stdlib/Encoding.sl:337](../../stdlib/Encoding.sl#L337)</sub>

#### Preamble *method*

```
byte[] Preamble()
```

Four bytes, and the little-endian one begins with UTF-16LE's -- which
is why `Detect` tests UTF-32 first.

<sub>[stdlib/Encoding.sl:341](../../stdlib/Encoding.sl#L341)</sub>

#### CanRepresent *method*

```
bool CanRepresent(char32 scalar)
```

Every scalar, in exactly four bytes.

<sub>[stdlib/Encoding.sl:347](../../stdlib/Encoding.sl#L347)</sub>

#### GetByteCount *method*

```
nuint GetByteCount(String text)
```

Four bytes per scalar. Costs a pass to count the scalars.

<sub>[stdlib/Encoding.sl:350](../../stdlib/Encoding.sl#L350)</sub>

#### GetBytes *method*

```
byte[] GetBytes(String text)
```

The text as UTF-32 in this byte order, with no byte order mark.

<sub>[stdlib/Encoding.sl:353](../../stdlib/Encoding.sl#L353)</sub>

#### GetString *method*

```
String GetString(byte[] bytes)
```

`bytes` read as UTF-32, with a value that is not a scalar -- a
surrogate, or anything past U+10FFFF -- becoming U+FFFD. Trailing bytes
that do not make a whole four are dropped.

<sub>[stdlib/Encoding.sl:378](../../stdlib/Encoding.sl#L378)</sub>

#### TryGetString *method*

```
Result<String, EncodingError> TryGetString(byte[] bytes)
```

The strict decode: `Incomplete` when the length is not a multiple of
four, `Invalid` for a value that is not a scalar.

<sub>[stdlib/Encoding.sl:393](../../stdlib/Encoding.sl#L393)</sub>

### Utf8Encoding *class*

```
class Utf8Encoding : IEncoding
```

UTF-8, which is what a `String` already holds.

Both directions are a copy rather than a transcode. `GetString` still has to
validate, because a `byte[]` from outside the program is not a `String` and
has promised nothing.

<sub>[stdlib/Encoding.sl:145](../../stdlib/Encoding.sl#L145)</sub>

#### Name *method*

```
String Name()
```

`"utf-8"`.

<sub>[stdlib/Encoding.sl:147](../../stdlib/Encoding.sl#L147)</sub>

#### Preamble *method*

```
byte[] Preamble()
```

EF BB BF. UTF-8 needs no byte order mark -- there is only one order --
so this is what to *recognise*, not what to write by habit.

<sub>[stdlib/Encoding.sl:151](../../stdlib/Encoding.sl#L151)</sub>

#### GetByteCount *method*

```
nuint GetByteCount(String text)
```

The length the text already has. O(1), since no transcode is needed.

<sub>[stdlib/Encoding.sl:154](../../stdlib/Encoding.sl#L154)</sub>

#### GetBytes *method*

```
byte[] GetBytes(String text)
```

The text's own bytes. A copy, not a transcode.

<sub>[stdlib/Encoding.sl:157](../../stdlib/Encoding.sl#L157)</sub>

#### CanRepresent *method*

```
bool CanRepresent(char32 scalar)
```

Every scalar; that is what UTF-8 is for.

<sub>[stdlib/Encoding.sl:160](../../stdlib/Encoding.sl#L160)</sub>

#### GetString *method*

```
String GetString(byte[] bytes)
```

`bytes` validated, with each malformed byte replaced by U+FFFD.

One replacement per bad byte rather than per bad sequence, so a run of
rubbish is as many U+FFFDs as it is bytes.

<sub>[stdlib/Encoding.sl:166](../../stdlib/Encoding.sl#L166)</sub>

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

<sub>[stdlib/Encoding.sl:192](../../stdlib/Encoding.sl#L192)</sub>

### Windows1252Encoding *class*

```
class Windows1252Encoding : SingleByteEncoding
```

Windows-1252: Latin-1, except that 0x80 to 0x9F carry punctuation rather
than C1 controls. Five of those 32 positions are unassigned and read as
U+FFFD.

<sub>[stdlib/Encoding.sl:516](../../stdlib/Encoding.sl#L516)</sub>

#### Name *method*

```
override String Name()
```

`"windows-1252"`.

<sub>[stdlib/Encoding.sl:518](../../stdlib/Encoding.sl#L518)</sub>

#### ToScalar *method*

```
override char32 ToScalar(byte value)
```

Latin-1 outside 0x80 to 0x9F, and the punctuation table inside it.
Five of those 32 positions are unassigned and read as U+FFFD.

<sub>[stdlib/Encoding.sl:522](../../stdlib/Encoding.sl#L522)</sub>

#### FromScalar *method*

```
override int FromScalar(char32 scalar)
```

The Latin-1 byte where there is one, else a scan of the 32-entry
punctuation table, else -1.

<sub>[stdlib/Encoding.sl:529](../../stdlib/Encoding.sl#L529)</sub>

## Functions

### Ascii *function*

```
IEncoding Ascii()
```

US-ASCII: seven bits, and nothing above them.

<sub>[stdlib/Encoding.sl:105](../../stdlib/Encoding.sl#L105)</sub>

### Detect *function*

```
IEncoding? Detect(byte[] bytes)
```

Which encoding a byte order mark says this is, or null when there is none.

UTF-32LE is tested before UTF-16LE deliberately: a UTF-32LE mark begins with
the two bytes of a UTF-16LE one, so the longer test has to come first or
every UTF-32 file reads as UTF-16 whose first character is NUL.

<sub>[stdlib/Encoding.sl:122](../../stdlib/Encoding.sl#L122)</sub>

### Latin1 *function*

```
IEncoding Latin1()
```

ISO-8859-1, in which every byte is the code point of the same number. That
makes it the one encoding that can carry any byte sequence without failing,
which is why it is what a protocol reaches for when it does not know.

<sub>[stdlib/Encoding.sl:110](../../stdlib/Encoding.sl#L110)</sub>

### Utf16 *function*

```
IEncoding Utf16()
```

UTF-16, little-endian -- the one Windows means by "Unicode".

<sub>[stdlib/Encoding.sl:93](../../stdlib/Encoding.sl#L93)</sub>

### Utf16BigEndian *function*

```
IEncoding Utf16BigEndian()
```

UTF-16, big-endian.

<sub>[stdlib/Encoding.sl:96](../../stdlib/Encoding.sl#L96)</sub>

### Utf32 *function*

```
IEncoding Utf32()
```

UTF-32, little-endian: one scalar per four bytes, no surrogates.

<sub>[stdlib/Encoding.sl:99](../../stdlib/Encoding.sl#L99)</sub>

### Utf32BigEndian *function*

```
IEncoding Utf32BigEndian()
```

UTF-32, big-endian.

<sub>[stdlib/Encoding.sl:102](../../stdlib/Encoding.sl#L102)</sub>

### Utf8 *function*

```
IEncoding Utf8()
```

UTF-8: what a `String` already is, so both directions are a copy.

<sub>[stdlib/Encoding.sl:90](../../stdlib/Encoding.sl#L90)</sub>

### Windows1252 *function*

```
IEncoding Windows1252()
```

Windows-1252: Latin-1 with the C1 control range replaced by punctuation --
curly quotes, the dash, the euro. Most text labelled ISO-8859-1 is really
this, because that is what a Windows editor wrote.

<sub>[stdlib/Encoding.sl:115](../../stdlib/Encoding.sl#L115)</sub>

### WithoutPreamble *function*

```
byte[] WithoutPreamble(IEncoding encoding, byte[] bytes)
```

`bytes` without the byte order mark `encoding` writes, if it is there.

<sub>[stdlib/Encoding.sl:132](../../stdlib/Encoding.sl#L132)</sub>

