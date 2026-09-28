# Standard.Text

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

The rest of `String`.

`String` itself is intrinsic: the runtime owns its layout and its allocation,
and the compiler creates the symbol before any source is read. What it does
not own is the behaviour, and this file adds it -- a type may be declared
more than once inside its own module, so `Standard.Text` picks up where
`Builtins` left off (§3.2).

Two rules run through everything here.

**Positions are byte offsets.** A `String` is UTF-8 and length is O(1)
precisely because nothing counts characters, so `IndexOf` answers in bytes
and `Substring` takes bytes. Every position this file produces lands on a
character boundary, because it came from matching whole text -- a UTF-8
sequence cannot begin inside another one, which is what makes byte-wise
search correct on encoded text rather than merely fast. Positions a *caller*
invents are its own business; `GetCodePointAt` and `SkipCodePoint` are here for
walking the text properly.

**Case and whitespace are ASCII.** Full Unicode case mapping is a table of
several thousand entries with locale exceptions, and the runtime has no room
for it yet. What is here maps A-Z and a-z and leaves every other byte alone,
which is exactly right for identifiers, protocol tokens and file extensions,
and visibly wrong for prose in most languages. Anything that says `Ascii` in
its name says so; anything that does not is either encoding-independent or
documented here.

## Contents

**Types** &nbsp; [IFormattable](#iformattable-interface) &middot; [String](#string-class) &middot; [StringBuilder](#stringbuilder-class) &middot; [Utf16String](#utf16string-class) &middot; [string](#string-alias)

**Functions** &nbsp; [AlignText](#aligntext-function) &middot; [FormatDouble](#formatdouble-function) &middot; [FormatInteger](#formatinteger-function) &middot; [FormatInteger](#formatinteger-function) &middot; [FromBool](#frombool-function) &middot; [FromBytes](#frombytes-function) &middot; [FromChar](#fromchar-function) &middot; [FromDouble](#fromdouble-function) &middot; [FromInteger](#frominteger-function) &middot; [FromInteger](#frominteger-function) &middot; [FromInteger](#frominteger-function) &middot; [FromNullTerminated](#fromnullterminated-function) &middot; [FromNullTerminatedUtf16](#fromnullterminatedutf16-function) &middot; [FromUtf16](#fromutf16-function)

**Constants** &nbsp; [NotFound](#notfound-constant)

## Types

### IFormattable *interface*

```
interface IFormattable
```

A value that has text to write into an interpolated string.

**Opted into, never owed.** There is no `ToString` every type has, and a
class that does not implement this is still refused by `$"{value}"`. One
that does is written by its own `ToText`, which is handed the hole's format
-- `{when:yyyy-MM-dd}` passes `"yyyy-MM-dd"` -- or `""` when the hole has
none. What a format means is the type's to decide, and nothing checks it
when the program compiles.

A struct implements no interface, so this is for classes; a struct's text is
a method it names, called in the hole.

<sub>[stdlib/Text/IFormattable.sl:35](../../stdlib/Text/IFormattable.sl#L35)</sub>

#### ToText *method*

```
String ToText(String format)
```

This value as text, in `format`, which is `""` for the type's default.

<sub>[stdlib/Text/IFormattable.sl:38](../../stdlib/Text/IFormattable.sl#L38)</sub>

### String *class*

```
class String
```

Immutable UTF-8 text.

The declaration is the runtime's and the behaviour is here, so this is the
second half of a type that `Builtins` opened. Three things a caller needs
before reaching for anything below:

A string cannot be changed once made. Every method that looks like it edits
one -- `Trim`, `Replace`, `ToUpperAscii` -- answers a new string, and the
ones that would have nothing to change answer `this` rather than a copy.

Every position is a byte offset, and every length is a byte count.
`ByteLength` is O(1) and no method here counts characters. Use
`GetCodePointAt` and `SkipCodePoint` to walk by character.

Slicing clamps rather than failing: a `start` past the end and a length
past the end both give what is actually there, so `Substring` cannot be
made to abort. `GetByteAt` is the exception and reads the buffer directly. A
search that finds nothing answers `NotFound`.

<sub>[stdlib/Text/String.sl:44](../../stdlib/Text/String.sl#L44)</sub>

#### Empty *property*

```
static String Empty { get; }
```

Text with no bytes in it.

A string literal is one interned object, so every `String.Empty` is the
same object that every `""` already was.

<sub>[stdlib/Text/String.sl:51](../../stdlib/Text/String.sl#L51)</sub>

#### StartsWith *method*

```
bool StartsWith(String prefix)
```

True when this text begins with `prefix`. An empty prefix always does.

<sub>[stdlib/Text/String.sl:56](../../stdlib/Text/String.sl#L56)</sub>

#### EndsWith *method*

```
bool EndsWith(String suffix)
```

True when this text ends with `suffix`. An empty suffix always does.

<sub>[stdlib/Text/String.sl:65](../../stdlib/Text/String.sl#L65)</sub>

#### Contains *method*

```
bool Contains(String value)
```

True when `value` appears anywhere in this text.

**See also** &nbsp; [String.IndexOf](#indexof-method)

<sub>[stdlib/Text/String.sl:77](../../stdlib/Text/String.sl#L77)</sub>

#### Contains *method*

```
bool Contains(char value)
```

True when this single code unit appears. Only meaningful for ASCII: a
`char` above 127 is one byte of a sequence rather than a character.

<sub>[stdlib/Text/String.sl:84](../../stdlib/Text/String.sl#L84)</sub>

#### IndexOf *method*

```
long IndexOf(String value)
```

Where `value` first appears, or `NotFound`.

An empty `value` is found at 0, which is where it is: every string
begins with the empty string.

**See also** &nbsp; [String.LastIndexOf](#lastindexof-method) &middot; [Text.NotFound](#notfound-constant)

<sub>[stdlib/Text/String.sl:98](../../stdlib/Text/String.sl#L98)</sub>

#### IndexOf *method*

```
long IndexOf(String value, nuint start)
```

Where `value` first appears at or after `start`, or `NotFound`.

<sub>[stdlib/Text/String.sl:104](../../stdlib/Text/String.sl#L104)</sub>

#### LastIndexOf *method*

```
long LastIndexOf(String value)
```

Where `value` last appears, or `NotFound`.

**See also** &nbsp; [String.IndexOf](#indexof-method)

<sub>[stdlib/Text/String.sl:131](../../stdlib/Text/String.sl#L131)</sub>

#### IndexOf *method*

```
long IndexOf(char value)
```

Where this code unit first appears, or `NotFound`.

<sub>[stdlib/Text/String.sl:153](../../stdlib/Text/String.sl#L153)</sub>

#### LastIndexOf *method*

```
long LastIndexOf(char value)
```

Where this code unit last appears, or `NotFound`.

<sub>[stdlib/Text/String.sl:167](../../stdlib/Text/String.sl#L167)</sub>

#### Substring *method*

```
String Substring(nuint start)
```

Everything from `start` to the end. A `start` past the end gives "".

<sub>[stdlib/Text/String.sl:182](../../stdlib/Text/String.sl#L182)</sub>

#### SubstringBefore *method*

```
String SubstringBefore(String separator)
```

The text before the first `separator`, or all of it when there is none.

**See also** &nbsp; [String.SubstringAfter](#substringafter-method)

<sub>[stdlib/Text/String.sl:193](../../stdlib/Text/String.sl#L193)</sub>

#### SubstringAfter *method*

```
String SubstringAfter(String separator)
```

The text after the first `separator`, or "" when there is none.

**See also** &nbsp; [String.SubstringBefore](#substringbefore-method) &middot; [String.SubstringAfterLast](#substringafterlast-method)

<sub>[stdlib/Text/String.sl:205](../../stdlib/Text/String.sl#L205)</sub>

#### SubstringAfterLast *method*

```
String SubstringAfterLast(String separator)
```

The text after the last `separator`, or all of it when there is none.

**See also** &nbsp; [String.SubstringAfter](#substringafter-method)

<sub>[stdlib/Text/String.sl:216](../../stdlib/Text/String.sl#L216)</sub>

#### Trim *method*

```
String Trim()
```

This text without leading or trailing ASCII whitespace.

**See also** &nbsp; [String.TrimStart](#trimstart-method) &middot; [String.TrimEnd](#trimend-method)

<sub>[stdlib/Text/String.sl:230](../../stdlib/Text/String.sl#L230)</sub>

#### TrimStart *method*

```
String TrimStart()
```

This text without leading ASCII whitespace.

<sub>[stdlib/Text/String.sl:236](../../stdlib/Text/String.sl#L236)</sub>

#### TrimEnd *method*

```
String TrimEnd()
```

This text without trailing ASCII whitespace.

<sub>[stdlib/Text/String.sl:251](../../stdlib/Text/String.sl#L251)</sub>

#### Replace *method*

```
String Replace(String from, String to)
```

Every occurrence of `from` replaced by `to`.

Left to right and non-overlapping, so the replacement is never searched
again: replacing "a" with "aa" terminates.

**See also** &nbsp; [StringBuilder.ReplaceAll](#replaceall-method)

<sub>[stdlib/Text/String.sl:273](../../stdlib/Text/String.sl#L273)</sub>

#### Repeat *method*

```
String Repeat(nuint count)
```

This text `count` times over. Zero gives "".

<sub>[stdlib/Text/String.sl:300](../../stdlib/Text/String.sl#L300)</sub>

#### PadLeft *method*

```
String PadLeft(nuint width)
```

Spaces on the left until the text is `width` bytes. Never truncates.

**See also** &nbsp; [String.PadRight](#padright-method)

<sub>[stdlib/Text/String.sl:316](../../stdlib/Text/String.sl#L316)</sub>

#### PadRight *method*

```
String PadRight(nuint width)
```

Spaces on the right until the text is `width` bytes. Never truncates.

**See also** &nbsp; [String.PadLeft](#padleft-method)

<sub>[stdlib/Text/String.sl:327](../../stdlib/Text/String.sl#L327)</sub>

#### PadLeft *method*

```
String PadLeft(nuint width, String with)
```

The same, padded with something other than a space -- a zero, usually,
which is what a formatted number wants.

The padding is measured in bytes like everything else here, so a `with`
of more than one byte pads by whole copies and may fall short of the
width rather than overshoot it. A single character is the sane case and
the one to use.

<sub>[stdlib/Text/String.sl:342](../../stdlib/Text/String.sl#L342)</sub>

#### PadRight *method*

```
String PadRight(nuint width, String with)
```

The same as `PadRight(width)` with something other than a space.

Measured in bytes, so a multi-byte `with` pads by whole copies and may
fall short of the width rather than overshoot it. An empty `with`
answers the string unchanged, since no number of copies would reach.

<sub>[stdlib/Text/String.sl:357](../../stdlib/Text/String.sl#L357)</sub>

#### Split *method*

```
String[] Split(String separator)
```

This text cut at every `separator`.

Adjacent separators produce empty parts, and so do ones at either end:
splitting "a,,b" on ',' gives three parts, and "" gives one. That is
what makes it reversible -- joining the result with the same separator
gives the original back.

**See also** &nbsp; [String.Join](#join-method) &middot; [String.SplitLines](#splitlines-method)

<sub>[stdlib/Text/String.sl:378](../../stdlib/Text/String.sl#L378)</sub>

#### Split *method*

```
String[] Split(char separator)
```

This text cut at every occurrence of one code unit.

<sub>[stdlib/Text/String.sl:413](../../stdlib/Text/String.sl#L413)</sub>

#### SplitLines *method*

```
String[] SplitLines()
```

This text cut into lines, on "\n" or "\r\n".

A trailing newline does not produce a final empty line, because a file
that ends in one has as many lines as one that does not -- which is the
opposite of what `Split` does, and the reason this is not `Split('\n')`.

**See also** &nbsp; [String.Split](#split-method)

<sub>[stdlib/Text/String.sl:450](../../stdlib/Text/String.sl#L450)</sub>

#### ToUpperAscii *method*

```
String ToUpperAscii()
```

This text with every ASCII letter uppercased, and every other byte left
as it was. See the note at the top of this file.

**See also** &nbsp; [String.ToLowerAscii](#tolowerascii-method) &middot; [String.EqualsIgnoreCaseAscii](#equalsignorecaseascii-method)

<sub>[stdlib/Text/String.sl:499](../../stdlib/Text/String.sl#L499)</sub>

#### ToLowerAscii *method*

```
String ToLowerAscii()
```

This text with every ASCII letter lowercased.

**See also** &nbsp; [String.ToUpperAscii](#toupperascii-method)

<sub>[stdlib/Text/String.sl:507](../../stdlib/Text/String.sl#L507)</sub>

#### EqualsIgnoreCaseAscii *method*

```
bool EqualsIgnoreCaseAscii(String other)
```

True when the two texts differ only in the case of ASCII letters.

<sub>[stdlib/Text/String.sl:513](../../stdlib/Text/String.sl#L513)</sub>

#### CompareTo *method*

```
int CompareTo(String other)
```

Orders two texts by their bytes: negative, zero or positive.

Comparing UTF-8 byte by byte happens to order by code point as well,
because the encoding was designed so that it would. It is not a
linguistic ordering and does not claim to be one.

<sub>[stdlib/Text/String.sl:537](../../stdlib/Text/String.sl#L537)</sub>

#### GetByteAt *method*

```
byte GetByteAt(nuint index)
```

The byte at `index`, which is a code unit and not a character.

Unchecked, unlike the slicing methods: this reads the buffer directly,
so an `index` at or past `ByteLength` reads memory that is not the
string's. Check the length first, or slice instead.

**See also** &nbsp; [String.GetCodePointAt](#getcodepointat-method)

<sub>[stdlib/Text/String.sl:566](../../stdlib/Text/String.sl#L566)</sub>

#### GetCodePointAt *method*

```
char32 GetCodePointAt(nuint index)
```

The scalar beginning at `index`.

`index` must be the start of a character; one that lands inside a
sequence gives U+FFFD, which is what a decoder does with a byte that
cannot begin one. So does a sequence that is not well formed: one cut
short, an overlong form, a surrogate or a value past U+10FFFF.

**See also** &nbsp; [String.SkipCodePoint](#skipcodepoint-method)

<sub>[stdlib/Text/String.sl:579](../../stdlib/Text/String.sl#L579)</sub>

#### SkipCodePoint *method*

```
nuint SkipCodePoint(nuint index)
```

The index of the character after the one at `index`.

Together with `GetCodePointAt` this is how the text is walked properly:

```
for (nuint at = 0; at < s.ByteLength(); at = s.SkipCodePoint(at)) {
    var c = s.GetCodePointAt(at);
}
```

A sequence that is not well formed is stepped over one byte at a time,
each byte reading as U+FFFD. `CodePointCount` counts the same steps.

**See also** &nbsp; [String.GetCodePointAt](#getcodepointat-method)

<sub>[stdlib/Text/String.sl:614](../../stdlib/Text/String.sl#L614)</sub>

#### Join *method*

```
String Join(String[] parts)
```

`parts` written out with this text between them. The inverse of `Split`.

A method on the separator rather than a free function, because every
module imports `Standard.Text` without asking and a global named `Join`
is a global named `Join`. `", ".Join(parts)` also reads in the order it
happens.

**See also** &nbsp; [String.Split](#split-method)

<sub>[stdlib/Text/String.sl:636](../../stdlib/Text/String.sl#L636)</sub>

#### ToBytes *method*

```
byte[] ToBytes()
```

This text's bytes, copied into an array.

A copy rather than a view: a `String` is immutable and an array is not,
so handing out the storage would let one be changed through the other.

**See also** &nbsp; [Text.FromBytes](#frombytes-function)

<sub>[stdlib/Text/String.sl:661](../../stdlib/Text/String.sl#L661)</sub>

### StringBuilder *class*

```
class StringBuilder
```

*No documentation.*

<sub>[stdlib/Text/StringBuilder.sl:26](../../stdlib/Text/StringBuilder.sl#L26)</sub>

#### Append *method*

```
void Append(String text)
```

Text, as its bytes.

<sub>[stdlib/Text/StringBuilder.sl:106](../../stdlib/Text/StringBuilder.sl#L106)</sub>

#### AppendLine *method*

```
void AppendLine(String text)
```

Text and a newline.

<sub>[stdlib/Text/StringBuilder.sl:112](../../stdlib/Text/StringBuilder.sl#L112)</sub>

#### AppendInteger *method*

```
void AppendInteger(long value)
```

A signed integer in base ten.

Written into the buffer a digit at a time rather than through
`FromInteger`, because a builder appending numbers in a loop should not
allocate a `String` per number.

**See also** &nbsp; [Text.FromInteger](#frominteger-function)

<sub>[stdlib/Text/StringBuilder.sl:125](../../stdlib/Text/StringBuilder.sl#L125)</sub>

#### AppendDouble *method*

```
void AppendDouble(double value)
```

The shortest text that reads back as the same number.

This one does allocate a `String` first: shortest round-trip formatting
is the runtime's, and there is nothing to gain by copying it here.

**See also** &nbsp; [Text.FromDouble](#fromdouble-function)

<sub>[stdlib/Text/StringBuilder.sl:172](../../stdlib/Text/StringBuilder.sl#L172)</sub>

#### AppendByte *method*

```
void AppendByte(byte value)
```

One byte.

The builder holds bytes, so nothing here validates: a caller writing
half a character has written half a character.

<sub>[stdlib/Text/StringBuilder.sl:181](../../stdlib/Text/StringBuilder.sl#L181)</sub>

#### ByteLength *method*

```
nuint ByteLength()
```

How many bytes have been built. Not a character count.

<sub>[stdlib/Text/StringBuilder.sl:191](../../stdlib/Text/StringBuilder.sl#L191)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

Whether nothing has been appended, or everything has been cleared.

**See also** &nbsp; [StringBuilder.HasContent](#hascontent-property)

<sub>[stdlib/Text/StringBuilder.sl:196](../../stdlib/Text/StringBuilder.sl#L196)</sub>

#### Clear *method*

```
void Clear()
```

Throws the length away and keeps the room, so a builder reused in a
loop allocates once.

<sub>[stdlib/Text/StringBuilder.sl:200](../../stdlib/Text/StringBuilder.sl#L200)</sub>

#### GetByteAt *method*

```
byte GetByteAt(nuint index)
```

One byte by position.

A call rather than a pointer, because the buffer moves as it grows and
a `byte*` into it would dangle at the next append -- the one thing
`String`'s own pointer can never do.

<sub>[stdlib/Text/StringBuilder.sl:210](../../stdlib/Text/StringBuilder.sl#L210)</sub>

#### SetByteAt *method*

```
void SetByteAt(nuint index, byte value)
```

Replaces one byte by position.

<sub>[stdlib/Text/StringBuilder.sl:218](../../stdlib/Text/StringBuilder.sl#L218)</sub>

#### Insert *method*

```
void Insert(nuint at, String text)
```

Text put in at a position. Inserting at the length is appending, which
is why `at == ByteLength()` is allowed.

**See also** &nbsp; [StringBuilder.Remove](#remove-method)

<sub>[stdlib/Text/StringBuilder.sl:231](../../stdlib/Text/StringBuilder.sl#L231)</sub>

#### Remove *method*

```
void Remove(nuint at, nuint count)
```

Bytes taken out from a position. Removing more than is there removes to
the end rather than failing.

**See also** &nbsp; [StringBuilder.Insert](#insert-method) &middot; [StringBuilder.TruncateTo](#truncateto-method)

<sub>[stdlib/Text/StringBuilder.sl:251](../../stdlib/Text/StringBuilder.sl#L251)</sub>

#### ToText *method*

```
String ToText()
```

What has been built, as text. The builder stays usable afterwards and
the string does not change when it is appended to again.

<sub>[stdlib/Text/StringBuilder.sl:264](../../stdlib/Text/StringBuilder.sl#L264)</sub>

#### AppendCodePoint *method*

```
void AppendCodePoint(char32 value)
```

One Unicode scalar, encoded as UTF-8.

This rather than `Append(char)`, because a `char` is one code unit and
appending a lone continuation byte would put the builder into a state
no `String` can be made from. A scalar always encodes to something
whole.

**See also** &nbsp; [Text.FromChar](#fromchar-function)

<sub>[stdlib/Text/StringBuilder.sl:280](../../stdlib/Text/StringBuilder.sl#L280)</sub>

#### AppendLine *method*

```
void AppendLine()
```

A newline on its own.

<sub>[stdlib/Text/StringBuilder.sl:323](../../stdlib/Text/StringBuilder.sl#L323)</sub>

#### Append *method*

```
void Append(bool value)
```

`true` or `false`.

There is deliberately no `Append(long)` or `Append(double)` beside this
one. An integer literal converts to both, so the two together would make
`Append(42)` ambiguous -- which is why `AppendInteger` and `AppendDouble`
were spelled out in the first place. A bool converts to neither.

<sub>[stdlib/Text/StringBuilder.sl:334](../../stdlib/Text/StringBuilder.sl#L334)</sub>

#### AppendBytes *method*

```
void AppendBytes(byte[] data)
```

Raw bytes. They are appended as they are, so it is the caller who
decides whether what comes out is text.

<sub>[stdlib/Text/StringBuilder.sl:341](../../stdlib/Text/StringBuilder.sl#L341)</sub>

#### AppendJoined *method*

```
void AppendJoined(String separator, String[] parts)
```

`parts` with `separator` between them.

<sub>[stdlib/Text/StringBuilder.sl:349](../../stdlib/Text/StringBuilder.sl#L349)</sub>

#### HasContent *property*

```
bool HasContent { get; }
```

Whether anything has been appended. The opposite of `IsEmpty`.

**See also** &nbsp; [StringBuilder.IsEmpty](#isempty-property)

<sub>[stdlib/Text/StringBuilder.sl:364](../../stdlib/Text/StringBuilder.sl#L364)</sub>

#### IndexOf *method*

```
long IndexOf(String value)
```

Where `value` first appears in what has been built, or `NotFound`.

Byte by byte through the runtime rather than over a pointer, because a
builder's storage moves when it grows and a pointer into it would be a
pointer into the previous allocation.

**See also** &nbsp; [StringBuilder.Contains](#contains-method)

<sub>[stdlib/Text/StringBuilder.sl:379](../../stdlib/Text/StringBuilder.sl#L379)</sub>

#### Contains *method*

```
bool Contains(String value)
```

True when `value` appears in what has been built.

**See also** &nbsp; [StringBuilder.IndexOf](#indexof-method)

<sub>[stdlib/Text/StringBuilder.sl:408](../../stdlib/Text/StringBuilder.sl#L408)</sub>

#### TruncateTo *method*

```
void TruncateTo(nuint at)
```

Everything from `at` to the end, thrown away.

<sub>[stdlib/Text/StringBuilder.sl:416](../../stdlib/Text/StringBuilder.sl#L416)</sub>

#### ReplaceFirst *method*

```
bool ReplaceFirst(String from, String to)
```

The first occurrence of `from` replaced by `to`, if there is one.

**Returns** &nbsp; whether there was one to replace

**See also** &nbsp; [StringBuilder.ReplaceAll](#replaceall-method)

<sub>[stdlib/Text/StringBuilder.sl:428](../../stdlib/Text/StringBuilder.sl#L428)</sub>

#### ReplaceAll *method*

```
nuint ReplaceAll(String from, String to)
```

Every occurrence of `from` replaced by `to`.

The search resumes past the replacement, so replacing "a" with "aa"
terminates rather than growing forever.

**Returns** &nbsp; how many occurrences were replaced

**See also** &nbsp; [StringBuilder.ReplaceFirst](#replacefirst-method)

<sub>[stdlib/Text/StringBuilder.sl:446](../../stdlib/Text/StringBuilder.sl#L446)</sub>

### Utf16String *class*

```
class Utf16String
```

UTF-16 text, which exists for the platforms that ask for it.

Not the string type to write a program in -- that is `String`, and this is
what a Windows `W` entry point or a Java-shaped protocol wants on the wire.
Convert at the boundary and stay in `String` everywhere else.

Positions are units, not characters and not bytes: a scalar outside the
basic plane is two units, so `UnitCount` is not a character count and
`GetUnitAt` can land on half a surrogate pair. `GetCodePointAt` joins the pair.

<sub>[stdlib/Text/Utf16String.sl:35](../../stdlib/Text/Utf16String.sl#L35)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

Whether there are any units at all.

<sub>[stdlib/Text/Utf16String.sl:39](../../stdlib/Text/Utf16String.sl#L39)</sub>

#### GetUnitAt *method*

```
char16 GetUnitAt(nuint index)
```

The unit at `index`. A unit, not a character: one half of a surrogate
pair is a unit and is not a character.

<sub>[stdlib/Text/Utf16String.sl:43](../../stdlib/Text/Utf16String.sl#L43)</sub>

#### GetCodePointAt *method*

```
char32 GetCodePointAt(nuint index)
```

The scalar beginning at `index`, joining a surrogate pair.

An unpaired surrogate gives U+FFFD, which is what transcoding it would
have produced -- a lone half cannot be encoded in UTF-8 at all.

**See also** &nbsp; [Utf16String.SkipCodePoint](#skipcodepoint-method) &middot; [String.GetCodePointAt](#getcodepointat-method)

<sub>[stdlib/Text/Utf16String.sl:55](../../stdlib/Text/Utf16String.sl#L55)</sub>

#### SkipCodePoint *method*

```
nuint SkipCodePoint(nuint index)
```

The index of the character after the one at `index`.

**See also** &nbsp; [Utf16String.GetCodePointAt](#getcodepointat-method)

<sub>[stdlib/Text/Utf16String.sl:79](../../stdlib/Text/Utf16String.sl#L79)</sub>

#### Equals *method*

```
bool Equals(Utf16String other)
```

True when the two hold the same units.

<sub>[stdlib/Text/Utf16String.sl:97](../../stdlib/Text/Utf16String.sl#L97)</sub>

#### ToBytes *method*

```
byte[] ToBytes()
```

The units as raw bytes, little-endian, which is what a Windows API and
a UTF-16LE file both expect.

**See also** &nbsp; [Text.FromUtf16](#fromutf16-function)

<sub>[stdlib/Text/Utf16String.sl:118](../../stdlib/Text/Utf16String.sl#L118)</sub>

### string *alias*

```
using string = String
```

`String`, spelled the way the primitives are.

`int` and `double` are keywords and lowercase, and a type that is just as
built in has no reason to look different. It is an alias and not a second
type, so a diagnostic says `String` whichever one was written.

<sub>[stdlib/Text/Text.sl:65](../../stdlib/Text/Text.sl#L65)</sub>

## Functions

### AlignText *function*

```
String AlignText(String text, int alignment)
```

`text` padded with spaces to `alignment` characters: on the left when it is
positive, so the text ends at the width, and on the right when it is
negative. Never truncates. This is `{value,8}` and `{value,-8}`.

**Characters, not bytes**, unlike `PadLeft`: a width is a column, and a
column holds a character however many bytes encode it.

**See also** &nbsp; [String.PadLeft](#padleft-method)

<sub>[stdlib/Text/Format.sl:286](../../stdlib/Text/Format.sl#L286)</sub>

### FormatDouble *function*

```
String FormatDouble(double value, String format)
```

A floating-point number in a standard numeric format, as `{value:F2}`
writes it: `F`, `N`, `E` or `G`, as `FormatInteger` describes them. `D`,
`X` and `B` are integer formats and are not taken here.

**See also** &nbsp; [Text.FormatInteger](#formatinteger-function)

<sub>[stdlib/Text/Format.sl:256](../../stdlib/Text/Format.sl#L256)</sub>

### FormatInteger *function*

```
String FormatInteger(long value, String format)
```

A signed integer in a standard numeric format, as `{value:D8}` writes it.

A format is a letter and an optional precision of up to three digits:

| Format | Integers | Floating point |
|---|---|---|
| `D` | digits, zero-padded to the precision | -- |
| `X`, `x` | hexadecimal in that case, zero-padded | -- |
| `B` | binary, zero-padded | -- |
| `F` | fixed point, the precision's decimals (2) | the same |
| `N` | `F` with a comma between groups of three | the same |
| `E`, `e` | scientific, the precision's decimals (6) | the same |
| `G`, `g` | the digits, or the precision's significant digits | the shortest spelling, or the same |

Either case of a letter is accepted; only `X`, `E` and `G` write something
that differs by case. Rounding is half away from zero, and the separators
are the invariant culture's, since there is no other.

`X` and `B` write the two's complement of all 64 bits, so a narrower type
widened to reach here reads as that type only if it was widened unsigned;
an interpolation does that for itself. **A format that is not in the table
stops the program**, as an index out of range does: which format is asked
for is fixed where the call is written, and an interpolation's is checked
when it compiles.

**See also** &nbsp; [Text.FormatDouble](#formatdouble-function)

<sub>[stdlib/Text/Format.sl:160](../../stdlib/Text/Format.sl#L160)</sub>

### FormatInteger *function*

```
String FormatInteger(ulong value, String format)
```

An unsigned integer in a standard numeric format.

**See also** &nbsp; [Text.FormatInteger](#formatinteger-function)

<sub>[stdlib/Text/Format.sl:209](../../stdlib/Text/Format.sl#L209)</sub>

### FromBool *function*

```
String FromBool(bool value)
```

`"true"` or `"false"`.

<sub>[stdlib/Text/Text.sl:219](../../stdlib/Text/Text.sl#L219)</sub>

### FromBytes *function*

```
String FromBytes(byte* data, nuint byteLength)
```

A copy of `byteLength` bytes, taken to be UTF-8.

**See also** &nbsp; [String.ToBytes](#tobytes-method)

<sub>[stdlib/Text/Text.sl:230](../../stdlib/Text/Text.sl#L230)</sub>

### FromChar *function*

```
String FromChar(char32 value)
```

One code point as the character it names, not as its number.
`Text.FromInteger((long)c)` is how to ask for the number.

**See also** &nbsp; [Text.FromInteger](#frominteger-function)

<sub>[stdlib/Text/Text.sl:225](../../stdlib/Text/Text.sl#L225)</sub>

### FromDouble *function*

```
String FromDouble(double value)
```

The shortest text that reads back as the same number.

<sub>[stdlib/Text/Text.sl:216](../../stdlib/Text/Text.sl#L216)</sub>

### FromInteger *function*

```
String FromInteger(long value)
```

A signed integer in base ten.

<sub>[stdlib/Text/Text.sl:199](../../stdlib/Text/Text.sl#L199)</sub>

### FromInteger *function*

```
String FromInteger(ulong value)
```

An unsigned integer in base ten.

A separate entry point rather than letting the signed one take it: a
`ulong` past 2^63 formatted as signed prints as a negative number.

<sub>[stdlib/Text/Text.sl:205](../../stdlib/Text/Text.sl#L205)</sub>

### FromInteger *function*

```
String FromInteger(nuint value)
```

A `nuint` in base ten.

Its own overload rather than a widening, because a `nuint` is a `size_t`
and cannot share the 64-bit entry point: on a 32-bit target the runtime
would read four bytes of argument and four of whatever was next on the
stack, and `$"{n}"` printed 8612659968337772549 for 5.

<sub>[stdlib/Text/Text.sl:213](../../stdlib/Text/Text.sl#L213)</sub>

### FromNullTerminated *function*

```
String FromNullTerminated(byte* text)
```

A copy of the bytes up to the first NUL, taken to be UTF-8. What a C
function that answers with a `char*` hands back.

**See also** &nbsp; [Text.FromBytes](#frombytes-function)

<sub>[stdlib/Text/Text.sl:237](../../stdlib/Text/Text.sl#L237)</sub>

### FromNullTerminatedUtf16 *function*

```
String FromNullTerminatedUtf16(char16* units)
```

UTF-16 up to the first NUL unit, transcoded to UTF-8.

**See also** &nbsp; [Text.FromUtf16](#fromutf16-function)

<sub>[stdlib/Text/Text.sl:251](../../stdlib/Text/Text.sl#L251)</sub>

### FromUtf16 *function*

```
String FromUtf16(char16* units, nuint unitCount)
```

UTF-16 transcoded to UTF-8.

A pointer and a count rather than a `Utf16String`, because a wide platform
API writes into a buffer the caller owns and that pair is what comes back.

**See also** &nbsp; [Text.FromNullTerminatedUtf16](#fromnullterminatedutf16-function)

<sub>[stdlib/Text/Text.sl:245](../../stdlib/Text/Text.sl#L245)</sub>

## Constants

### NotFound *constant*

```
const long NotFound = -1
```

The byte a search returns when it found nothing.

Searches answer with a `long` rather than a `nuint` for exactly this: a
position is unsigned, "nowhere" is not a position, and every unsigned
sentinel anyone has tried -- `npos`, the length, zero -- is a real position
in some other string. -1 is not.

<sub>[stdlib/Text/Text.sl:58](../../stdlib/Text/Text.sl#L58)</sub>

