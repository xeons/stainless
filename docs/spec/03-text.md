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
declares them. The rest are ordinary Stainless, written in `stdlib/Text/String.sl` as
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
`FromInteger`, `FromDouble`, `FromBool`, `FromBytes` and `FromNullTerminated`;
`FormatInteger`, `FormatDouble` and `AlignText`, which are what an
interpolation's formats reach for ([§3.8.1](#381-alignment-and-format)); and
`StringBuilder`.

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

`StringBuilder` is itself written in Stainless, in `stdlib/Text/StringBuilder.sl`: three
fields and a destructor over a buffer it grows by doubling.

`Standard.Console` is *not* automatic and provides `Write`, `WriteLine`,
`WriteError`, `ReadLine` and `ReadToEnd`.

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
converts to both, and although `Append(42)` would choose `long`
([section 7.1](07-functions-members.md#71-functions)), a name that says what is written is
the clearer call.

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

The shape is .NET's, with the static instances replaced by functions, so
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
sugar over the `Text.From*` conversions that are already there, with one
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
| an enum | its member's name, or the names of its set flags ([§2.13](02-types.md#213-enum--a-distinct-type-over-an-integer)) |
| a class that implements `IFormattable` | its own `ToText(format)` |

Anything else is refused (SL0557) rather than given a default. There is no
`ToString` that every type owes, and inventing one to make this work would be a
much larger decision than a formatting syntax — every class would owe an
implementation, and a default that printed a type name would be worse than
nothing. **`IFormattable` is the opt-in instead.** It is in `Standard.Text`,
it has one method, `String ToText(String format)`, and a class that implements
it has text to write: the hole calls it through the interface, so an override
answers, and hands it the hole's format or `""`. A struct may implement it
too, and its own `ToText` is called on the value in place, since a struct is
never a reference to the interface
([§2.10](02-types.md#210-interface--a-contract-dispatched-dynamically)).

One refusal is worth the words it takes. A **`char` or `char16` is one code
unit, not a character** ([§2.1](02-types.md#21-primitives)), so which of the two meanings was wanted has to
be said: `(char32)c` writes the character, `(long)c` writes the number.

An **enum** writes what C#'s would: `Color.Green` is `Green`, a `[Flags]`
value is its set flags joined by `", "`, and a value no name covers is its
number. `value.ToText()` is the same text outside a string.

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

### 3.8.1 Alignment and format

```csharp
$"{count,6}"            // right-aligned in six columns
$"{name,-12}|"          // left-aligned in twelve
$"{flags:X8}"           // eight hexadecimal digits
$"{price,10:N2}"        // both: 1,234.50 right-aligned in ten
```

C#'s shape and C#'s meanings. After the expression, a `,` and an **alignment**,
then a `:` and a **format**, each optional and in that order.

**The alignment is a constant integer** (SL0754): a literal, a negated one or a
`const`. Positive pads on the left and negative on the right, with spaces, and
text already wider is never cut. It counts characters rather than bytes, unlike
`PadLeft`, because a width is a column and a column holds a character however
many bytes encode it. It applies to anything a hole can hold. A width known
only when the program runs is `Text.AlignText(text, width)`, which is what the
hole calls.

**The format is .NET's standard numeric formats**, a letter and up to three
digits of precision:

| | Integers | `float`, `double` |
|---|---|---|
| `D` | digits, zero-padded to the precision | — |
| `X`, `x` | hexadecimal in that case, zero-padded | — |
| `B` | binary, zero-padded | — |
| `F` | fixed point, with the precision's decimals (2) | the same |
| `N` | `F`, with a comma between groups of three | the same |
| `E`, `e` | scientific, the precision's decimals (6), a three-digit exponent | the same |
| `G`, `g` | the digits, or the precision's significant digits | the shortest spelling, or the same |

Rounding is half away from zero on the exact binary value, which is .NET's
rule and why `{0.125:F2}` is `0.13` and `{9.995:F2}` is `9.99` — the double
nearest 9.995 is below it. The separators are the invariant culture's, since
there is no other. A signed value in `X` or `B` writes its two's complement at
its own width, so an `int` of -1 is `FFFFFFFF` and a `long` of -1 is sixteen
`F`s. `G` with no precision is the language's shortest spelling of a double
(§3.2), not .NET's, which differs from it only in where an exponent appears.

**A number's format is checked when the program compiles** (SL0753). It is text
in the source and the value's type is known, so `{n:Q}`, `{price:X}` on a
`double` and `{name:D}` on a `String` are errors where they are written rather
than a failure the first time the line runs. What was rejected is .NET's
custom patterns — `0.00`, `#,##0` — which are a second small language, and
three letters and a precision cover what they are mostly written for. The
same formats are callable directly as `Text.FormatInteger(value, format)` and
`Text.FormatDouble(value, format)`, where a format no number takes stops the
program, as an index out of range does.

A class that implements `IFormattable` receives the format as written and
decides what it means, so `{when:yyyy-MM-dd}` is the class's business and is
not checked.

An enum takes no format, so `{level:D}` is SL0753 too. Its number is a cast
away — `{(int)level:D}` — which is also where a reader looks for it.

**A conditional in a hole is parenthesised** (SL0755), as in C#. The `:` that
starts a format is found by the lexer — the format is not code, and
`{when:HH:mm}` would not lex as any — so `{ok ? 1 : 2}` is `ok ? 1` with a
format of ` 2`. Only a `:` outside every bracket starts one, so
`{(ok ? 1 : 2)}`, `{items[i > 0 ? i : 0]}` and `{F(x: 1)}` are code.

### 3.8.2 Verbatim and raw interpolations

`$@"..."` and `@$"..."` are verbatim strings with holes, and `$"""..."""` is a
raw one; §3.9 is what each is without the `$`. A raw string's `$` count is how
many braces open a hole, which is what lets text hold braces without doubling
them:

```csharp
$$"""{"id": {{id}}, "tags": []}"""       // {"id": 7, "tags": []}
```

With `n` dollars a run of fewer than `n` braces is text, and a run of `n` to
`2n - 1` is text followed by a hole's opening. A longer run, or a run of `n`
closing braces outside a hole, is SL0750, and so is a hole closed with fewer
braces than opened it. More than one `$` on anything but a raw string is
SL0751, since only a raw string has braces that need telling apart.

## 3.9 Writing a string

```csharp
"C:\\temp\\log.txt"               // regular: escapes, one line
@"C:\temp\log.txt"                // verbatim: a backslash is itself
"""She said "hi" and \n."""       // raw: nothing is special
"GET"u8                           // the bytes, not a String
```

C#'s four forms, each with C#'s rules, and one departure.

**Verbatim**, `@"..."`: no escapes, so a backslash is itself; `""` is a quote;
and the string may run over several lines, each line break being part of it.

**Raw**, three or more quotes: the opening run is the delimiter, and only a run
of exactly as many closes it, so the content may hold any shorter one. On one
line the content is what stands between. Across lines the quotes stand on lines
of their own — nothing but whitespace after the opening ones (SL0746), and
before the closing ones (SL0747) — and the whitespace in front of the closing
quotes is the literal's indentation, which comes off every line of content:

```csharp
String query = """
    SELECT name
      FROM users
    """;                            // "SELECT name\n  FROM users"
```

A line that does not start with exactly that whitespace is SL0748, a tab where
the closing line has spaces included, since there is no telling how wide a tab
was meant to be. A line of nothing but whitespace is exempt and is empty. A run
of quotes longer than the delimiter is SL0749, because it can be neither the
end nor text.

**A line break inside any string is one `\n`**, however the file was saved.
That is the departure: C# keeps a verbatim or raw literal's line breaks as the
file has them, so one checkout with CRLF and another with LF compile the same
source to different strings. Here they compile to the same one.

**`u8`** after a regular, verbatim or raw literal makes its UTF-8 bytes rather
than a `String`. Its type is `ReadOnlySpan<byte>`, as C#'s is, over an array
in read-only storage with an immortal count, laid out as an embedded file's is
([§8.7](08-interop-libraries.md#87-embedding-a-file)). Nothing is allocated,
copying the slice counts nothing, and a NUL follows the bytes without being
counted in them. **The bytes are not writable**, and the type says so: a store
through the slice is refused where it is written (SL0808,
[§2.12.1](02-types.md#2121-readonlyspant)) rather than faulting where it runs.
An interpolated string cannot take `u8` (SL0752),
since its bytes do not exist until it runs; `ToBytes()` on the `String` is
that.

---

<sub>[&larr; Types](02-types.md) &nbsp;&middot;&nbsp; [Generics &rarr;](04-generics.md)</sub>
