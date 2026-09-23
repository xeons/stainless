<sub>[Stainless](../../README.md) &rsaquo; [Language specification](index.md)</sub>

# 3. Text

Stainless has exactly one string type. `String` is immutable, reference
counted, and always UTF-8.

There is deliberately no second encoding-flavoured string type. The
`AnsiString`/`UnicodeString` split that Delphi and Free Pascal carry exists to
serve Win32's parallel `A` and `W` APIs, and it charges for that with implicit
conversions that narrow lossily and transcode invisibly. Stainless keeps one
representation and makes every crossing explicit instead.

```csharp
String greeting = "Hello";          // a literal is a String
String subject  = "Stainless";

String message = greeting + ", " + subject + "!";
bool   matched = message == "Hello, Stainless!";   // compares by value, not identity

string same = message;              // `string` is the same type
```

**`string` is `String`.** `Standard.Text` declares it as an alias
([§1.5](01-modules.md#15-aliases)) and that module is imported into every file
([§1.7](01-modules.md#17-what-is-automatic)), so either spelling works anywhere
with nothing to import. An alias and not a keyword, which is what makes it free:
there is one type, no conversion, and a diagnostic names `String` whichever the
source wrote. The lowercase spelling is there because `int` and `double` have it
and a type just as built in has no reason to look different.

## 3.1 Representation

A `String` is an ordinary reference counted object whose bytes live inline,
immediately after the object header, with a trailing NUL:

```
offset 0   strong      : nuint          the usual ARC header
offset 8   weak        : nuint
offset 16  type        : TypeInfo*
offset 24  byteLength  : nuint          not counting the NUL
offset 32  bytes       : byte[n + 1]    UTF-8, NUL terminated
```

Three things follow from that shape:

- **Length is O(1).** Nothing ever scans for a terminator.
- **Reaching C copies nothing.** `ToPointer()` is `this + 32`.
- **Literals never allocate.** The compiler emits them as static constants with
  an *immortal* reference count, which `retain` and `release` skip entirely.

Because a `String` owns a reference count, a `struct` holding one retains it on
every copy and can no longer be handed to C ([§2.2](02-types.md#22-struct--value-type-c-layout)) — a struct of plain data is
copied as raw bytes, which is what keeps it C-compatible.

## 3.2 Members

Eight of these are intrinsic — the runtime implements them and the compiler
declares them. The rest are ordinary Stainless, written in `stdlib/Text.sl` as
a second declaration of the type ([§1.2.1](01-modules.md#121-and-so-may-a-type)), which is why they can return a
`String[]` where a C function could not.

| Member | Result | Notes |
|---|---|---|
| `a + b` | `String` | allocates and copies |
| `a == b`, `a != b` | `bool` | compares bytes, not identity |
| `ByteLength()` | `nuint` | O(1) |
| `CodePointCount()` | `nuint` | O(n) |
| `IsEmpty` | `bool` | O(1) |
| `ToPointer()` | `byte*` | O(1), no copy |
| `ToUtf16()` | `Utf16String` | allocates and transcodes |
| **testing** | | |
| `StartsWith(p)`, `EndsWith(s)` | `bool` | an empty argument is always found |
| `Contains(v)` | `bool` | a `String` or one `char` |
| **searching** | | |
| `IndexOf(v)`, `IndexOf(v, from)` | `long` | the byte offset, or `Text.NotFound` |
| `LastIndexOf(v)` | `long` | as above, from the end |
| **slicing** | | |
| `Substring(start)`, `Substring(start, n)` | `String` | byte offsets, clamped to the end |
| `SubstringBefore(sep)`, `SubstringAfter(sep)`, `SubstringAfterLast(sep)` | `String` | the halves either side of a separator |
| **trimming** | | |
| `Trim()`, `TrimStart()`, `TrimEnd()` | `String` | ASCII whitespace |
| **rebuilding** | | |
| `Replace(from, to)` | `String` | left to right, non-overlapping |
| `Repeat(n)`, `PadLeft(w)`, `PadRight(w)` | `String` | padding never truncates |
| **splitting** | | |
| `Split(sep)` | `String[]` | a `String` or one `char`; empty parts kept |
| `SplitLines()` | `String[]` | on `\n` or `\r\n`; a trailing one adds no line |
| `sep.Join(parts)` | `String` | the inverse of `Split` |
| **case and order** | | |
| `ToUpperAscii()`, `ToLowerAscii()` | `String` | see below |
| `EqualsIgnoreCaseAscii(o)` | `bool` | |
| `CompareTo(o)` | `int` | ordinal: negative, zero or positive |
| **characters** | | |
| `GetByteAt(i)` | `byte` | a code unit, not a character |
| `GetCodePointAt(i)`, `SkipCodePoint(i)` | `char32`, `nuint` | how the text is walked properly |
| `ToBytes()` | `byte[]` | a copy, because a `String` is immutable |

Two rules run through all of it.

**Positions are byte offsets.** Length is O(1) precisely because nothing counts
characters. Every position these produce lands on a character boundary anyway,
because it came from matching whole text — a UTF-8 sequence cannot begin inside
another one, which is what makes byte-wise search correct on encoded text rather
than merely fast. A position the *caller* invents is its own business, and
`GetCodePointAt` with `SkipCodePoint` is the way to walk:

```csharp
for (nuint at = 0; at < s.ByteLength(); at = s.SkipCodePoint(at))
{
    char32 c = s.GetCodePointAt(at);
}
```

**Case is ASCII, and says so in its name.** Full Unicode case mapping is a table
of several thousand entries with locale exceptions, and the runtime has no room
for it yet. `ToUpperAscii` maps A–Z and leaves every other byte alone, which is
right for identifiers, protocol tokens and file extensions, and visibly wrong
for prose in most languages. `Standard.Ascii` asks the same questions of one
byte: `IsDigit`, `IsLetter`, `IsHexDigit`, `IsWhiteSpace`, `ToUpper`, `FromHexDigit`
and the rest. It is a module of its own, and imported rather than automatic,
because `IsDigit` is too good a name to take from every program.

`Standard.Text` is imported into every module automatically, since a literal
produces a `String` whether the program asked for one or not. It also provides
`FromInteger`, `FromDouble`, `FromBool`, `FromBytes` and `FromNullTerminated`,
plus `StringBuilder`.

**`FromDouble` writes the shortest text that reads back as the same number**,
which is what C# and every modern runtime do: `0.1` rather than
`0.10000000000000001`, and `3.141592653589793` rather than a rounding of it. A
round number stays round — `60`, not `6e+01` — and an exponent appears only
where it is genuinely shorter. `Standard.Convert`'s `ToDouble` is its inverse
and is correctly rounded, so anything written can be read back unchanged.
`AppendDouble` spells a number the same way, since two spellings for one number
is a difference nobody looks for.

`StringBuilder` appends (`Append`, `AppendLine`, `AppendInteger`,
`AppendDouble`, `AppendByte`, `AppendBytes`, `AppendCodePoint`, `AppendJoined`), reads (`GetByteAt`, `IndexOf`,
`Contains`) and edits (`Insert`, `Remove`, `TruncateTo`, `SetByteAt`,
`ReplaceFirst`, `ReplaceAll`). Unlike `String` it hands out no pointer: its
bytes are a growable allocation that moves, so a `byte*` into it would dangle at
the next append. Reading is a call per byte instead.

`StringBuilder` is itself written in Stainless, in `stdlib/Text.sl`: three
fields and a destructor over a buffer it grows by doubling.

`Standard.Console` is *not* automatic and provides `Write`, `WriteLine` and
`WriteError`.

## 3.3 Reaching C

`ToPointer()` returns the interior `byte*`, valid for as long as the `String`
is alive:

```csharp
extern "C" int puts(byte* text);

String name = "Ada" + " Lovelace";
puts(name.ToPointer());
```

A `String` never converts to `byte*` implicitly, because the conversion hands
out a pointer whose lifetime the compiler can no longer see. A *literal* is the
exception, and passes straight through, since its bytes are static:

```csharp
puts("this is fine");                       // literal: static bytes
printf("%s\n", name.ToPointer());   // variable: say so explicitly
```

Two things worth knowing: a `String` may contain interior NULs, in which case C
sees a truncated view; and `Substring` counts bytes, so slicing mid-character
is possible.

## 3.4 UTF-16 for platform APIs

`Utf16String` exists so that wide platform APIs can be called. Nothing converts
to it implicitly.

```csharp
extern "C" int MessageBoxW(nuint window, char16* text, char16* caption, uint kind);

var wide = message.ToUtf16();       // owned, NUL terminated, released by ARC
MessageBoxW(0, wide.ToPointer(), null, 0);
```

It offers `UnitCount()`, `IsEmpty`, `GetUnitAt(i)`, `GetCodePointAt(i)` and
`SkipCodePoint(i)` — which join a surrogate pair, so a character outside the
basic plane reads as one scalar across two units — plus `Equals(other)`,
`ToBytes()`, which gives the raw little-endian units, `ToPointer()`, which
returns `char16*`, and `ToText()`, which transcodes back.

`char16*` and not `ushort*`: the two are the same width, and a wide API that
took the second would accept any 16-bit pointer within reach — an array of
counts, a `short*` off by one field. Naming the units is what makes the wrong
pointer a compile error, and it is the same move the handle types made against
`void*` ([§2.2.2](02-types.md#222-struct-hwnd__--a-type-declared-and-not-laid-out)). A cast still crosses between them where a C header really did
mean a number.

The return direction usually is not a `Utf16String` at all, because a wide API
answers by writing into a buffer the caller owns rather than by producing an
object. Two free functions take that shape directly:

```csharp
GetCurrentDirectoryW(capacity, buffer);
String here = Text.FromUtf16(buffer, units);        // a pointer and a length
String also = Text.FromNullTerminatedUtf16(buffer); // up to the first NUL
```

| Direction | Call | Cost |
|---|---|---|
| UTF-8 to UTF-16 | `text.ToUtf16()` | one allocation, two passes |
| UTF-16 to UTF-8 | `wide.ToText()` | one allocation, two passes |
| a buffer to UTF-8 | `Text.FromUtf16(units, count)` | one allocation, two passes |
| a buffer to UTF-8 | `Text.FromNullTerminatedUtf16(units)` | as above, plus the scan |

**Anything malformed becomes U+FFFD** in both directions, rather than being
rejected or passed through. That is not politeness: a `String` is UTF-8 by
invariant and everything downstream relies on it, and what a wide API hands back
is whatever was in the filesystem or on the clipboard — an unpaired surrogate is
a real thing to receive. A null pointer reads as the empty string, because a
wide call that failed leaves the caller holding one.

## 3.5 StringBuilder

`String` is immutable, so building text by repeated concatenation is O(n^2).
`StringBuilder` is the mutable counterpart, with amortised O(1) appends:

```csharp
var builder = new StringBuilder();
for (int i = 0; i < 5; i++)
{
    builder.AppendInteger(i);
    builder.Append(",");
}
Console.WriteLine(builder.ToText());       // 0,1,2,3,4,
```

| Member | Result |
|---|---|
| `Append(String)`, `Append(bool)` | `void` |
| `AppendLine(String)`, `AppendLine()` | `void`, adds a newline |
| `AppendInteger(long)`, `AppendDouble(double)` | `void` |
| `AppendCodePoint(char32)` | `void`, encoded as UTF-8 |
| `AppendJoined(sep, parts)` | `void` |
| `ByteLength()`, `IsEmpty`, `HasContent` | `nuint`, `bool`, `bool` |
| `GetByteAt(i)`, `SetByteAt(i, b)` | `byte`, `void` |
| `IndexOf(String)`, `Contains(String)` | `long`, `bool` |
| `Insert(at, String)`, `Remove(at, n)`, `TruncateTo(at)` | `void` |
| `ReplaceFirst(from, to)`, `ReplaceAll(from, to)` | `bool`, `nuint` |
| `Clear()` | `void`, keeps the capacity |
| `ToText()` | `String`, a snapshot; the builder stays usable |

There is deliberately no `Append(long)` or `Append(double)`. An integer literal
converts to both, and although `Append(42)` would now choose `long`
([§7.1](07-functions-members.md#71-functions)), a name that says what is written is still
the clearer call — which is why the two were spelled out in the first place.

Unlike `String`, its bytes are a separate growable allocation, so it is not
NUL-terminated and has no `ToPointer()`. Call `ToText().ToPointer()` to reach C.
The same allocation moving as it grows is why reading goes through `GetByteAt`
rather than through a pointer: one taken before an append would be a pointer
into the previous allocation.

## 3.6 Other encodings

`String` is UTF-8 and there is one string type. That settles what text *is*
inside a program and says nothing about what arrives from outside one — a file
written by a Windows editor, a protocol header older than Unicode, a registry
value in UTF-16. `Standard.Encoding` is the crossing, and every crossing is
explicit.

The shape is .NET's, with the static instances replaced by functions: a static
needs an initializer, and `--shared` has nowhere to run one ([§9.3](09-statements-expressions.md#93-const-and-static)), so
`Encoding.CreateUtf8()` is a call. Everything is behind an interface, so a
program may add an encoding of its own.

```csharp
import Standard.Encoding;

var bytes = Encoding.CreateUtf16().GetBytes("héllo");    // 10 bytes, little-endian
var back  = Encoding.CreateUtf16().GetString(bytes);     // "héllo"
```

| Member of `IEncoding` | Result |
|---|---|
| `Name` | `String`, as IANA spells it |
| `Preamble` | `byte[]`, the byte order mark or empty |
| `GetByteCount(text)` | `nuint` |
| `GetBytes(text)` | `byte[]` |
| `GetString(bytes)` | `String` |
| `TryGetString(bytes)` | `Result<String, EncodingError>` |
| `CanRepresent(scalar)` | `bool` |

| Encoding | From | Notes |
|---|---|---|
| UTF-8 | `Encoding.CreateUtf8()` | what a `String` already is; both directions copy |
| UTF-16 | `CreateUtf16()`, `CreateUtf16BigEndian()` | |
| UTF-32 | `CreateUtf32()`, `CreateUtf32BigEndian()` | one scalar per four bytes |
| US-ASCII | `CreateAscii()` | |
| ISO-8859-1 | `CreateLatin1()` | byte *n* is code point *n*; decoding never fails |
| Windows-1252 | `CreateWindows1252()` | Latin-1 with punctuation at 0x80–0x9F |

**Both directions are lossy by default**, which is the rule the language
already applies to `ToUtf16` and `Text.FromUtf16`: what cannot be decoded
becomes U+FFFD, and what cannot be encoded becomes `?`. That is not politeness
— `GetString` returns a `String`, and a `String` is valid UTF-8 by invariant,
so there is nothing else it could return. `TryGetString` is the strict form for
a caller that needs to know rather than to cope, and it refuses an overlong
UTF-8 sequence as well as a malformed one: two spellings of one character is
how a filter that checked the bytes gets walked past.

`Encoding.DetectEncoding(bytes)` reads a byte order mark and gives back the
encoding it names, or null. `Encoding.StripPreamble(encoding, bytes)` drops the
mark.

## 3.7 Conversions

`Standard.Convert` is the other edge: values that arrived as characters, and
values that have to leave as them.

```csharp
import Standard.Convert;

var port = Convert.ToInt(text);
switch (port)
{
    case Ok ok:  Listen(ok.Value); break;
    case Fail:   Complain(); break;
}
```

| | |
|---|---|
| `ToLong`, `ToInt`, `ToULong` | `Result<_, ConvertError>`, base 10 or any radix from 2 to 36 |
| `ToDouble` | `Result<double, ConvertError>` |
| `FromLong(value, radix)` | `String` — base 10 is `Text.FromInteger` |
| `ToHexString(data)`, `FromHexString(text)` | `String`, `Result<byte[], ConvertError>` |
| `ToBase64String(data)`, `ToBase64Url(data)`, `ToBase64String(text)` | `String` |
| `FromBase64String(text)` | `Result<byte[], ConvertError>`, either alphabet |

Everything that can fail returns a `Result`. There is no `Parse` that stops the
program, because the language has no exceptions, and no `TryParse` with an
`out` parameter, because a conversion that fails has a reason to give and `out`
is for the answer that has none ([§7.2.1](07-functions-members.md#721-out)).

Two details worth knowing, because both are where a parser is usually wrong.
The integer parsers accumulate as *unsigned* so that the most negative `long`,
whose magnitude does not fit in a `long`, is reachable — a signed accumulator
gets exactly that one value wrong. And `FromBase64String` skips whitespace, because
base64 in the wild arrives wrapped at 64 or 76 columns and a decoder that
refused a newline would be useless for the thing it is most often pointed at.

## 3.8 Interpolation

```csharp
Console.WriteLine($"clicks: {clicks}  at {x}, {y}");
```

`$"..."` writes the pieces between the braces into the text around them. It is
sugar over the `Text.From*` conversions that were already there, with one
difference that is not cosmetic: the whole string is **joined in a single
allocation**. The `+` chain it replaces calls `sl_string_concat` once per
operator and throws every result but the last away — the line above emits five
calls written that way, and one written this way.

An interpolation with no holes is a literal, and costs what one costs.

**What may go in a hole.** One expression, of a type that has text to write:

| | |
|---|---|
| `String` | itself |
| an integer, signed or unsigned | its digits |
| `float`, `double` | `Text.FromDouble` |
| `bool` | `true` or `false` |
| `char32` | the character it names, not its number |

Anything else is refused (SL0557) rather than given a default. There is no
`ToString` that every type owes, and inventing one to make this work would be a
much larger decision than a formatting syntax — every class would owe an
implementation, and a default that printed a type name would be worse than
nothing.

Two refusals are worth the words they take. A **`char` or `char16` is one code
unit, not a character** ([§2.1](02-types.md#21-primitives)), so which of the two meanings was wanted has to
be said: `(char32)c` writes the character, `(long)c` writes the number. And an
**enum** would have to write its number, because nothing records a member's
name yet; the error says so rather than printing a `1`.

**Braces.** `{{` and `}}` are how a literal brace is written. A lone `}` closes
nothing and is refused (SL0554), because it is far more often the end of a hole
that was never opened. A hole may contain braces of its own — an index, a
nested interpolation, a string with braces in it — and the depth is counted:

```csharp
$"deep {$"inner {n}"}"          // an interpolation inside a hole
$"quoted {"has {braces}"}"      // a string inside a hole
$"{{{n}}}"                      // a literal brace either side of a hole
```

**An empty hole** names no value (SL0555), and **two expressions in one hole**
would mean the second was silently dropped (SL0556). Both are errors.

**No format specifiers yet.** `{n:x}` and `{n,8}` are not written; `:` and `,`
inside a hole are reserved so that adding them later is not a change of
meaning. Padding and radix are `PadLeft` and `Convert.FromLong` until then.

---

<sub>[&larr; Types](02-types.md) &nbsp;&middot;&nbsp; [Generics &rarr;](04-generics.md)</sub>
