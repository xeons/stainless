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
encodings come from functions -- `Encoding.CreateUtf8()` -- and a program may add
one of its own by implementing `IEncoding`.

Both directions are lossy by default and say so, which is the same rule the
language already applies to `ToUtf16` and `Text.FromUtf16`: what cannot be
decoded becomes U+FFFD, and what cannot be encoded becomes `?`. `TryGetString`
is the strict form for a caller that needs to know rather than to cope, and
`CanRepresent` answers the other direction before anything is written.

## Contents

**Types** &nbsp; [AsciiEncoding](#asciiencoding-class) &middot; [EncodingError](#encodingerror-enum) &middot; [IDecoder](#idecoder-interface) &middot; [IEncoding](#iencoding-interface) &middot; [Latin1Encoding](#latin1encoding-class) &middot; [SingleByteEncoding](#singlebyteencoding-class) &middot; [Utf16Encoding](#utf16encoding-class) &middot; [Utf32Encoding](#utf32encoding-class) &middot; [Utf8Encoding](#utf8encoding-class) &middot; [Windows1252Encoding](#windows1252encoding-class)

**Functions** &nbsp; [CreateAscii](#createascii-function) &middot; [CreateLatin1](#createlatin1-function) &middot; [CreateUtf16](#createutf16-function) &middot; [CreateUtf16BigEndian](#createutf16bigendian-function) &middot; [CreateUtf32](#createutf32-function) &middot; [CreateUtf32BigEndian](#createutf32bigendian-function) &middot; [CreateUtf8](#createutf8-function) &middot; [CreateWindows1252](#createwindows1252-function) &middot; [DetectEncoding](#detectencoding-function) &middot; [StripPreamble](#strippreamble-function)

## Types

### AsciiEncoding *class*

```
class AsciiEncoding : SingleByteEncoding
```

US-ASCII. A byte above 127 is not ASCII, and reads as U+FFFD.

<sub>[stdlib/Encoding/AsciiEncoding.sl:27](../../stdlib/Encoding/AsciiEncoding.sl#L27)</sub>

#### Name *property*

```
String Name { get; }
```

`"us-ascii"`.

<sub>[stdlib/Encoding/AsciiEncoding.sl:30](../../stdlib/Encoding/AsciiEncoding.sl#L30)</sub>

#### ToScalar *method*

```
override char32 ToScalar(byte value)
```

The byte itself below 128, and U+FFFD at or above it.

<sub>[stdlib/Encoding/AsciiEncoding.sl:33](../../stdlib/Encoding/AsciiEncoding.sl#L33)</sub>

#### FromScalar *method*

```
override int FromScalar(char32 scalar)
```

The scalar itself below U+0080, and -1 at or above it.

<sub>[stdlib/Encoding/AsciiEncoding.sl:39](../../stdlib/Encoding/AsciiEncoding.sl#L39)</sub>

### EncodingError *enum*

```
enum EncodingError
```

Why a decode failed, when a caller asked to be told.

<sub>[stdlib/Encoding/EncodingError.sl:27](../../stdlib/Encoding/EncodingError.sl#L27)</sub>

#### Incomplete *case*

```
Incomplete
```

The bytes ended in the middle of a character.

<sub>[stdlib/Encoding/EncodingError.sl:30](../../stdlib/Encoding/EncodingError.sl#L30)</sub>

#### Invalid *case*

```
Invalid
```

A byte or a sequence that this encoding cannot produce.

<sub>[stdlib/Encoding/EncodingError.sl:33](../../stdlib/Encoding/EncodingError.sl#L33)</sub>

### IDecoder *interface*

```
interface IDecoder
```

A decode in progress, across as many pieces as the bytes arrive in.

.NET's `Decoder`, narrowed to what this language needs: it answers with a
`String` rather than filling a `char` buffer, so there is no count to ask
for first and no `GetCharCount` beside it.

An encoder has no counterpart here. .NET needs one because a caller can
write half a surrogate pair; a caller here writes a `String`, which is
whole by construction, so there is never anything for a writer to hold.

<sub>[stdlib/Encoding/IDecoder.sl:35](../../stdlib/Encoding/IDecoder.sl#L35)</sub>

#### GetString *method*

```
String GetString(byte[] bytes, nuint index, nuint count, bool flush)
```

The text that `count` bytes from `index` complete, with any unfinished
character at the end kept back for the next call.

`flush` says no more bytes are coming, so anything still held is
malformed and becomes U+FFFD rather than waiting for the rest.

<sub>[stdlib/Encoding/IDecoder.sl:42](../../stdlib/Encoding/IDecoder.sl#L42)</sub>

#### Reset *method*

```
void Reset()
```

Forgets what is held, for a decoder being pointed at something new.

<sub>[stdlib/Encoding/IDecoder.sl:45](../../stdlib/Encoding/IDecoder.sl#L45)</sub>

### IEncoding *interface*

```
interface IEncoding
```

One way of writing text as bytes.

Implement it to add an encoding; nothing here is closed. The two `Get`
methods are lossy and total, the `Try` one is strict, and `CanRepresent`
asks the encode direction the question `TryGetString` asks of the other.

<sub>[stdlib/Encoding/IEncoding.sl:31](../../stdlib/Encoding/IEncoding.sl#L31)</sub>

#### Name *property*

```
String Name { get; }
```

The name IANA gives it, which is also what an HTTP header would carry.

<sub>[stdlib/Encoding/IEncoding.sl:34](../../stdlib/Encoding/IEncoding.sl#L34)</sub>

#### Preamble *property*

```
byte[] Preamble { get; }
```

The bytes that mark this encoding at the start of a file, if any.

<sub>[stdlib/Encoding/IEncoding.sl:37](../../stdlib/Encoding/IEncoding.sl#L37)</sub>

#### GetByteCount *method*

```
nuint GetByteCount(String text)
```

How many bytes `GetBytes` would produce. Costs a pass, saves an
allocation.

**See also** &nbsp; [IEncoding.GetBytes](#getbytes-method)

<sub>[stdlib/Encoding/IEncoding.sl:43](../../stdlib/Encoding/IEncoding.sl#L43)</sub>

#### GetBytes *method*

```
byte[] GetBytes(String text)
```

`text` in this encoding. A scalar the encoding cannot write becomes
`?`, which is what .NET's default fallback does and what the caller
almost always wants when the alternative is failing a whole file.

**See also** &nbsp; [IEncoding.GetString](#getstring-method) &middot; [IEncoding.CanRepresent](#canrepresent-method)

<sub>[stdlib/Encoding/IEncoding.sl:51](../../stdlib/Encoding/IEncoding.sl#L51)</sub>

#### GetString *method*

```
String GetString(byte[] bytes)
```

`bytes` read as this encoding. Anything malformed becomes U+FFFD, so
the result is always valid UTF-8 -- which it must be, because it is a
`String`.

**See also** &nbsp; [IEncoding.GetBytes](#getbytes-method) &middot; [IEncoding.TryGetString](#trygetstring-method)

<sub>[stdlib/Encoding/IEncoding.sl:59](../../stdlib/Encoding/IEncoding.sl#L59)</sub>

#### TryGetString *method*

```
Result<String, EncodingError> TryGetString(byte[] bytes)
```

The same, but saying what went wrong instead of papering over it.

**Fails with**

- [EncodingError.Incomplete](#incomplete-case) — the bytes end part-way through a character
- [EncodingError.Invalid](#invalid-case) — a byte or a sequence this encoding cannot produce

**See also** &nbsp; [IEncoding.GetString](#getstring-method)

<sub>[stdlib/Encoding/IEncoding.sl:66](../../stdlib/Encoding/IEncoding.sl#L66)</sub>

#### CanRepresent *method*

```
bool CanRepresent(char32 scalar)
```

Whether this encoding can write that scalar at all.

<sub>[stdlib/Encoding/IEncoding.sl:69](../../stdlib/Encoding/IEncoding.sl#L69)</sub>

#### GetDecoder *method*

```
IDecoder GetDecoder()
```

A converter that remembers what a buffer ended in the middle of.

`GetString` takes whole text and cannot help a caller reading a stream
in pieces, because a character may straddle two of them. This is .NET's
`Encoding.GetDecoder`, and it exists for exactly that: the decoder holds
the trailing bytes of an unfinished character and finishes it when the
next piece arrives.

<sub>[stdlib/Encoding/IEncoding.sl:78](../../stdlib/Encoding/IEncoding.sl#L78)</sub>

### Latin1Encoding *class*

```
class Latin1Encoding : SingleByteEncoding
```

ISO-8859-1, where byte n is code point n for every n. Nothing can fail in
either direction below U+0100, and nothing above it can be written.

<sub>[stdlib/Encoding/Latin1Encoding.sl:28](../../stdlib/Encoding/Latin1Encoding.sl#L28)</sub>

#### Name *property*

```
String Name { get; }
```

`"iso-8859-1"`.

<sub>[stdlib/Encoding/Latin1Encoding.sl:31](../../stdlib/Encoding/Latin1Encoding.sl#L31)</sub>

#### ToScalar *method*

```
override char32 ToScalar(byte value)
```

Byte n is code point n, for every n. Never U+FFFD, which is what makes
this encoding able to carry any byte sequence at all.

<sub>[stdlib/Encoding/Latin1Encoding.sl:35](../../stdlib/Encoding/Latin1Encoding.sl#L35)</sub>

#### FromScalar *method*

```
override int FromScalar(char32 scalar)
```

The scalar itself below U+0100, and -1 at or above it.

<sub>[stdlib/Encoding/Latin1Encoding.sl:38](../../stdlib/Encoding/Latin1Encoding.sl#L38)</sub>

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

<sub>[stdlib/Encoding/SingleByteEncoding.sl:38](../../stdlib/Encoding/SingleByteEncoding.sl#L38)</sub>

#### ToScalar *method*

```
abstract char32 ToScalar(byte value)
```

What this byte means. Every byte means something.

<sub>[stdlib/Encoding/SingleByteEncoding.sl:41](../../stdlib/Encoding/SingleByteEncoding.sl#L41)</sub>

#### FromScalar *method*

```
abstract int FromScalar(char32 scalar)
```

Which byte writes this scalar, or -1 when none does.

<sub>[stdlib/Encoding/SingleByteEncoding.sl:44](../../stdlib/Encoding/SingleByteEncoding.sl#L44)</sub>

#### Name *property*

```
String Name { get; }
```

The IANA name, which each subclass supplies.

<sub>[stdlib/Encoding/SingleByteEncoding.sl:47](../../stdlib/Encoding/SingleByteEncoding.sl#L47)</sub>

#### Preamble *property*

```
byte[] Preamble { get; }
```

None of these has one: a byte order mark is a Unicode idea.

**Value** &nbsp; an empty array, always.

<sub>[stdlib/Encoding/SingleByteEncoding.sl:52](../../stdlib/Encoding/SingleByteEncoding.sl#L52)</sub>

#### CanRepresent *method*

```
bool CanRepresent(char32 scalar)
```

Whether the table has a byte for that scalar. Most of Unicode is not in
any of these tables, so this is false far more often than it is true.

<sub>[stdlib/Encoding/SingleByteEncoding.sl:56](../../stdlib/Encoding/SingleByteEncoding.sl#L56)</sub>

#### GetDecoder *method*

```
IDecoder GetDecoder()
```

One byte is one character here, so a decoder has nothing to hold.

<sub>[stdlib/Encoding/SingleByteEncoding.sl:59](../../stdlib/Encoding/SingleByteEncoding.sl#L59)</sub>

#### GetByteCount *method*

```
nuint GetByteCount(String text)
```

One byte per scalar, always -- so the count is the scalar count, not
the text's byte length.

<sub>[stdlib/Encoding/SingleByteEncoding.sl:63](../../stdlib/Encoding/SingleByteEncoding.sl#L63)</sub>

#### GetBytes *method*

```
byte[] GetBytes(String text)
```

The text in this encoding, with anything the table cannot write
becoming `?`. Check `CanRepresent` first where losing it matters.

**See also** &nbsp; [SingleByteEncoding.CanRepresent](#canrepresent-method)

<sub>[stdlib/Encoding/SingleByteEncoding.sl:69](../../stdlib/Encoding/SingleByteEncoding.sl#L69)</sub>

#### GetString *method*

```
String GetString(byte[] bytes)
```

`bytes` through the table, one character per byte. Cannot fail: every
byte means something, even if that something is U+FFFD.

<sub>[stdlib/Encoding/SingleByteEncoding.sl:85](../../stdlib/Encoding/SingleByteEncoding.sl#L85)</sub>

#### TryGetString *method*

```
Result<String, EncodingError> TryGetString(byte[] bytes)
```

Never fails, which is the whole character of a single-byte encoding.

<sub>[stdlib/Encoding/SingleByteEncoding.sl:96](../../stdlib/Encoding/SingleByteEncoding.sl#L96)</sub>

### Utf16Encoding *class*

```
class Utf16Encoding : IEncoding
```

UTF-16, in either byte order.

<sub>[stdlib/Encoding/Utf16Encoding.sl:29](../../stdlib/Encoding/Utf16Encoding.sl#L29)</sub>

#### Name *property*

```
String Name { get; }
```

`"utf-16be"` or `"utf-16le"`, whichever this is.

<sub>[stdlib/Encoding/Utf16Encoding.sl:41](../../stdlib/Encoding/Utf16Encoding.sl#L41)</sub>

#### Preamble *property*

```
byte[] Preamble { get; }
```

FE FF big-endian, FF FE little. Worth writing here, unlike UTF-8's:
without it there is no way to tell the two orders apart.

<sub>[stdlib/Encoding/Utf16Encoding.sl:46](../../stdlib/Encoding/Utf16Encoding.sl#L46)</sub>

#### CanRepresent *method*

```
bool CanRepresent(char32 scalar)
```

Every scalar, in one unit or two.

<sub>[stdlib/Encoding/Utf16Encoding.sl:57](../../stdlib/Encoding/Utf16Encoding.sl#L57)</sub>

#### GetDecoder *method*

```
IDecoder GetDecoder()
```

A decoder that holds an odd byte, and a high surrogate waiting for
its low one.

<sub>[stdlib/Encoding/Utf16Encoding.sl:61](../../stdlib/Encoding/Utf16Encoding.sl#L61)</sub>

#### GetByteCount *method*

```
nuint GetByteCount(String text)
```

Two bytes per unit, so four for a scalar outside the basic plane.
Costs a transcode to count, which is what `GetBytes` then does again.

<sub>[stdlib/Encoding/Utf16Encoding.sl:65](../../stdlib/Encoding/Utf16Encoding.sl#L65)</sub>

#### GetBytes *method*

```
byte[] GetBytes(String text)
```

The text as UTF-16 in this byte order, with no byte order mark --
prepend `Preamble` if the reader will need one.

<sub>[stdlib/Encoding/Utf16Encoding.sl:69](../../stdlib/Encoding/Utf16Encoding.sl#L69)</sub>

#### GetString *method*

```
String GetString(byte[] bytes)
```

`bytes` read as UTF-16, with an unpaired surrogate or a trailing odd
byte becoming U+FFFD. A byte order mark, if present, is not stripped --
`StripPreamble` is what does that.

<sub>[stdlib/Encoding/Utf16Encoding.sl:95](../../stdlib/Encoding/Utf16Encoding.sl#L95)</sub>

#### TryGetString *method*

```
Result<String, EncodingError> TryGetString(byte[] bytes)
```

The strict decode: `Incomplete` for an odd number of bytes or a high
surrogate at the end, `Invalid` for a surrogate that is not paired.

**Fails with**

- [EncodingError.Incomplete](#incomplete-case) — an odd number of bytes, or a high surrogate with no unit after it
- [EncodingError.Invalid](#invalid-case) — a low surrogate first, or a high one followed by something that is not a low one

**See also** &nbsp; [Utf16Encoding.GetString](#getstring-method)

<sub>[stdlib/Encoding/Utf16Encoding.sl:142](../../stdlib/Encoding/Utf16Encoding.sl#L142)</sub>

### Utf32Encoding *class*

```
class Utf32Encoding : IEncoding
```

UTF-32: one scalar per four bytes, and no surrogates anywhere.

<sub>[stdlib/Encoding/Utf32Encoding.sl:29](../../stdlib/Encoding/Utf32Encoding.sl#L29)</sub>

#### Name *property*

```
String Name { get; }
```

`"utf-32be"` or `"utf-32le"`, whichever this is.

<sub>[stdlib/Encoding/Utf32Encoding.sl:41](../../stdlib/Encoding/Utf32Encoding.sl#L41)</sub>

#### Preamble *property*

```
byte[] Preamble { get; }
```

Four bytes, and the little-endian one begins with UTF-16LE's -- which
is why `DetectEncoding` tests UTF-32 first.

**See also** &nbsp; [Encoding.DetectEncoding](#detectencoding-function)

<sub>[stdlib/Encoding/Utf32Encoding.sl:47](../../stdlib/Encoding/Utf32Encoding.sl#L47)</sub>

#### CanRepresent *method*

```
bool CanRepresent(char32 scalar)
```

Every scalar, in exactly four bytes.

<sub>[stdlib/Encoding/Utf32Encoding.sl:58](../../stdlib/Encoding/Utf32Encoding.sl#L58)</sub>

#### GetDecoder *method*

```
IDecoder GetDecoder()
```

A decoder that holds whatever is left of a four-byte group.

<sub>[stdlib/Encoding/Utf32Encoding.sl:61](../../stdlib/Encoding/Utf32Encoding.sl#L61)</sub>

#### GetByteCount *method*

```
nuint GetByteCount(String text)
```

Four bytes per scalar. Costs a pass to count the scalars.

<sub>[stdlib/Encoding/Utf32Encoding.sl:64](../../stdlib/Encoding/Utf32Encoding.sl#L64)</sub>

#### GetBytes *method*

```
byte[] GetBytes(String text)
```

The text as UTF-32 in this byte order, with no byte order mark.

<sub>[stdlib/Encoding/Utf32Encoding.sl:67](../../stdlib/Encoding/Utf32Encoding.sl#L67)</sub>

#### GetString *method*

```
String GetString(byte[] bytes)
```

`bytes` read as UTF-32, with a value that is not a scalar -- a
surrogate, or anything past U+10FFFF -- becoming U+FFFD. Trailing bytes
that do not make a whole four are one more U+FFFD.

<sub>[stdlib/Encoding/Utf32Encoding.sl:97](../../stdlib/Encoding/Utf32Encoding.sl#L97)</sub>

#### TryGetString *method*

```
Result<String, EncodingError> TryGetString(byte[] bytes)
```

The strict decode: `Incomplete` when the length is not a multiple of
four, `Invalid` for a value that is not a scalar.

**Fails with**

- [EncodingError.Incomplete](#incomplete-case) — the length is not a multiple of four
- [EncodingError.Invalid](#invalid-case) — a surrogate, or a value past U+10FFFF

**See also** &nbsp; [Utf32Encoding.GetString](#getstring-method)

<sub>[stdlib/Encoding/Utf32Encoding.sl:119](../../stdlib/Encoding/Utf32Encoding.sl#L119)</sub>

### Utf8Encoding *class*

```
class Utf8Encoding : IEncoding
```

UTF-8, which is what a `String` already holds.

Both directions are a copy rather than a transcode. `GetString` still has to
validate, because a `byte[]` from outside the program is not a `String` and
has promised nothing.

<sub>[stdlib/Encoding/Utf8Encoding.sl:33](../../stdlib/Encoding/Utf8Encoding.sl#L33)</sub>

#### Name *property*

```
String Name { get; }
```

`"utf-8"`.

<sub>[stdlib/Encoding/Utf8Encoding.sl:36](../../stdlib/Encoding/Utf8Encoding.sl#L36)</sub>

#### Preamble *property*

```
byte[] Preamble { get; }
```

EF BB BF. UTF-8 needs no byte order mark -- there is only one order --
so this is what to *recognise*, not what to write by habit.

<sub>[stdlib/Encoding/Utf8Encoding.sl:40](../../stdlib/Encoding/Utf8Encoding.sl#L40)</sub>

#### GetByteCount *method*

```
nuint GetByteCount(String text)
```

The length the text already has. O(1), since no transcode is needed.

<sub>[stdlib/Encoding/Utf8Encoding.sl:43](../../stdlib/Encoding/Utf8Encoding.sl#L43)</sub>

#### GetBytes *method*

```
byte[] GetBytes(String text)
```

The text's own bytes. A copy, not a transcode.

<sub>[stdlib/Encoding/Utf8Encoding.sl:46](../../stdlib/Encoding/Utf8Encoding.sl#L46)</sub>

#### CanRepresent *method*

```
bool CanRepresent(char32 scalar)
```

Every scalar; that is what UTF-8 is for.

<sub>[stdlib/Encoding/Utf8Encoding.sl:49](../../stdlib/Encoding/Utf8Encoding.sl#L49)</sub>

#### GetDecoder *method*

```
IDecoder GetDecoder()
```

A decoder that holds the first bytes of a sequence whose rest has
not arrived.

<sub>[stdlib/Encoding/Utf8Encoding.sl:53](../../stdlib/Encoding/Utf8Encoding.sl#L53)</sub>

#### GetString *method*

```
String GetString(byte[] bytes)
```

`bytes` validated, with each malformed byte replaced by U+FFFD.

One replacement per bad byte rather than per bad sequence, so a run of
rubbish is as many U+FFFDs as it is bytes. Malformed means what
`TryGetString` refuses, overlong forms and surrogates included.

<sub>[stdlib/Encoding/Utf8Encoding.sl:60](../../stdlib/Encoding/Utf8Encoding.sl#L60)</sub>

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

**Fails with**

- [EncodingError.Incomplete](#incomplete-case) — a sequence the bytes ran out during
- [EncodingError.Invalid](#invalid-case) — a byte that starts nothing, a missing continuation byte, an overlong form, a surrogate, or a value past U+10FFFF

**See also** &nbsp; [Utf8Encoding.GetString](#getstring-method)

<sub>[stdlib/Encoding/Utf8Encoding.sl:103](../../stdlib/Encoding/Utf8Encoding.sl#L103)</sub>

### Windows1252Encoding *class*

```
class Windows1252Encoding : SingleByteEncoding
```

Windows-1252: Latin-1, except that 0x80 to 0x9F carry punctuation rather
than C1 controls. Five of those 32 positions are unassigned and read as
U+FFFD.

<sub>[stdlib/Encoding/Windows1252Encoding.sl:29](../../stdlib/Encoding/Windows1252Encoding.sl#L29)</sub>

#### Name *property*

```
String Name { get; }
```

`"windows-1252"`.

<sub>[stdlib/Encoding/Windows1252Encoding.sl:32](../../stdlib/Encoding/Windows1252Encoding.sl#L32)</sub>

#### ToScalar *method*

```
override char32 ToScalar(byte value)
```

Latin-1 outside 0x80 to 0x9F, and the punctuation table inside it.
Five of those 32 positions are unassigned and read as U+FFFD.

<sub>[stdlib/Encoding/Windows1252Encoding.sl:36](../../stdlib/Encoding/Windows1252Encoding.sl#L36)</sub>

#### FromScalar *method*

```
override int FromScalar(char32 scalar)
```

The Latin-1 byte where there is one, else a scan of the 32-entry
punctuation table, else -1. U+FFFD is -1: it marks the table's
unassigned bytes and is written by none of them.

<sub>[stdlib/Encoding/Windows1252Encoding.sl:46](../../stdlib/Encoding/Windows1252Encoding.sl#L46)</sub>

## Functions

### CreateAscii *function*

```
IEncoding CreateAscii()
```

US-ASCII: seven bits, and nothing above them.

<sub>[stdlib/Encoding/Encoding.sl:225](../../stdlib/Encoding/Encoding.sl#L225)</sub>

### CreateLatin1 *function*

```
IEncoding CreateLatin1()
```

ISO-8859-1, in which every byte is the code point of the same number. That
makes it the one encoding that can carry any byte sequence without failing,
which is why it is what a protocol reaches for when it does not know.

<sub>[stdlib/Encoding/Encoding.sl:230](../../stdlib/Encoding/Encoding.sl#L230)</sub>

### CreateUtf16 *function*

```
IEncoding CreateUtf16()
```

UTF-16, little-endian -- the one Windows means by "Unicode".

<sub>[stdlib/Encoding/Encoding.sl:213](../../stdlib/Encoding/Encoding.sl#L213)</sub>

### CreateUtf16BigEndian *function*

```
IEncoding CreateUtf16BigEndian()
```

UTF-16, big-endian.

<sub>[stdlib/Encoding/Encoding.sl:216](../../stdlib/Encoding/Encoding.sl#L216)</sub>

### CreateUtf32 *function*

```
IEncoding CreateUtf32()
```

UTF-32, little-endian: one scalar per four bytes, no surrogates.

<sub>[stdlib/Encoding/Encoding.sl:219](../../stdlib/Encoding/Encoding.sl#L219)</sub>

### CreateUtf32BigEndian *function*

```
IEncoding CreateUtf32BigEndian()
```

UTF-32, big-endian.

<sub>[stdlib/Encoding/Encoding.sl:222](../../stdlib/Encoding/Encoding.sl#L222)</sub>

### CreateUtf8 *function*

```
IEncoding CreateUtf8()
```

UTF-8: what a `String` already is, so both directions are a copy.

<sub>[stdlib/Encoding/Encoding.sl:210](../../stdlib/Encoding/Encoding.sl#L210)</sub>

### CreateWindows1252 *function*

```
IEncoding CreateWindows1252()
```

Windows-1252: Latin-1 with the C1 control range replaced by punctuation --
curly quotes, the dash, the euro. Most text labelled ISO-8859-1 is really
this, because that is what a Windows editor wrote.

<sub>[stdlib/Encoding/Encoding.sl:235](../../stdlib/Encoding/Encoding.sl#L235)</sub>

### DetectEncoding *function*

```
IEncoding? DetectEncoding(byte[] bytes)
```

Which encoding a byte order mark says this is, or null when there is none.

UTF-32LE is tested before UTF-16LE deliberately: a UTF-32LE mark begins with
the two bytes of a UTF-16LE one, so the longer test has to come first or
every UTF-32 file reads as UTF-16 whose first character is NUL.

**See also** &nbsp; [Encoding.StripPreamble](#strippreamble-function)

<sub>[stdlib/Encoding/Encoding.sl:244](../../stdlib/Encoding/Encoding.sl#L244)</sub>

### StripPreamble *function*

```
byte[] StripPreamble(IEncoding encoding, byte[] bytes)
```

`bytes` without the byte order mark `encoding` writes, if it is there.

<sub>[stdlib/Encoding/Encoding.sl:260](../../stdlib/Encoding/Encoding.sl#L260)</sub>

