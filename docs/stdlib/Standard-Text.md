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
invents are its own business; `CodePointAt` and `NextCodePoint` are here for
walking the text properly.

**Case and whitespace are ASCII.** Full Unicode case mapping is a table of
several thousand entries with locale exceptions, and the runtime has no room
for it yet. What is here maps A-Z and a-z and leaves every other byte alone,
which is exactly right for identifiers, protocol tokens and file extensions,
and visibly wrong for prose in most languages. Anything that says `Ascii` in
its name says so; anything that does not is either encoding-independent or
documented here.

## Contents

**Types** &nbsp; [String](#string-class) &middot; [StringBuilder](#stringbuilder-class) &middot; [Utf16String](#utf16string-class) &middot; [string](#string-alias)

**Functions** &nbsp; [FromBool](#frombool-function) &middot; [FromBytes](#frombytes-function) &middot; [FromChar](#fromchar-function) &middot; [FromDouble](#fromdouble-function) &middot; [FromInteger](#frominteger-function) &middot; [FromInteger](#frominteger-function) &middot; [FromInteger](#frominteger-function) &middot; [FromNullTerminated](#fromnullterminated-function) &middot; [FromNullTerminatedUtf16](#fromnullterminatedutf16-function) &middot; [FromUtf16](#fromutf16-function)

**Constants** &nbsp; [NotFound](#notfound-constant)

## Types

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
`CodePointAt` and `NextCodePoint` to walk by character.

Slicing clamps rather than failing: a `start` past the end and a length
past the end both give what is actually there, so `Substring` cannot be
made to abort. `ByteAt` is the exception and reads the buffer directly. A
search that finds nothing answers `NotFound`.

<sub>[stdlib/Text.sl:78](../../stdlib/Text.sl#L78)</sub>

#### Empty *property*

```
static String Empty { get; }
```

Text with no bytes in it.

A property rather than a static field, and the reason is worth knowing:
a `--shared` library has no entry point to run a static's initializer
from (SL0380), so a field here would have made the whole standard
library unusable in one. This costs nothing either way -- a string
literal is one interned object, so every `String.Empty` is the same
object that every `""` already was.

<sub>[stdlib/Text.sl:89](../../stdlib/Text.sl#L89)</sub>

#### StartsWith *method*

```
bool StartsWith(String prefix)
```

True when this text begins with `prefix`. An empty prefix always does.

<sub>[stdlib/Text.sl:94](../../stdlib/Text.sl#L94)</sub>

#### EndsWith *method*

```
bool EndsWith(String suffix)
```

True when this text ends with `suffix`. An empty suffix always does.

<sub>[stdlib/Text.sl:103](../../stdlib/Text.sl#L103)</sub>

#### Contains *method*

```
bool Contains(String value)
```

True when `value` appears anywhere in this text.

<sub>[stdlib/Text.sl:113](../../stdlib/Text.sl#L113)</sub>

#### Contains *method*

```
bool Contains(char value)
```

True when this single code unit appears. Only meaningful for ASCII: a
`char` above 127 is one byte of a sequence rather than a character.

<sub>[stdlib/Text.sl:120](../../stdlib/Text.sl#L120)</sub>

#### IndexOf *method*

```
long IndexOf(String value)
```

Where `value` first appears, or `NotFound`.

An empty `value` is found at 0, which is where it is: every string
begins with the empty string.

<sub>[stdlib/Text.sl:131](../../stdlib/Text.sl#L131)</sub>

#### IndexOf *method*

```
long IndexOf(String value, nuint start)
```

Where `value` first appears at or after `start`, or `NotFound`.

<sub>[stdlib/Text.sl:137](../../stdlib/Text.sl#L137)</sub>

#### LastIndexOf *method*

```
long LastIndexOf(String value)
```

Where `value` last appears, or `NotFound`.

<sub>[stdlib/Text.sl:162](../../stdlib/Text.sl#L162)</sub>

#### IndexOf *method*

```
long IndexOf(char value)
```

Where this code unit first appears, or `NotFound`.

<sub>[stdlib/Text.sl:184](../../stdlib/Text.sl#L184)</sub>

#### LastIndexOf *method*

```
long LastIndexOf(char value)
```

Where this code unit last appears, or `NotFound`.

<sub>[stdlib/Text.sl:198](../../stdlib/Text.sl#L198)</sub>

#### Substring *method*

```
String Substring(nuint start)
```

Everything from `start` to the end. A `start` past the end gives "".

<sub>[stdlib/Text.sl:213](../../stdlib/Text.sl#L213)</sub>

#### Before *method*

```
String Before(String separator)
```

The text before the first `separator`, or all of it when there is none.

<sub>[stdlib/Text.sl:222](../../stdlib/Text.sl#L222)</sub>

#### After *method*

```
String After(String separator)
```

The text after the first `separator`, or "" when there is none.

<sub>[stdlib/Text.sl:231](../../stdlib/Text.sl#L231)</sub>

#### AfterLast *method*

```
String AfterLast(String separator)
```

The text after the last `separator`, or all of it when there is none.

<sub>[stdlib/Text.sl:240](../../stdlib/Text.sl#L240)</sub>

#### Trim *method*

```
String Trim()
```

This text without leading or trailing ASCII whitespace.

<sub>[stdlib/Text.sl:251](../../stdlib/Text.sl#L251)</sub>

#### TrimStart *method*

```
String TrimStart()
```

This text without leading ASCII whitespace.

<sub>[stdlib/Text.sl:257](../../stdlib/Text.sl#L257)</sub>

#### TrimEnd *method*

```
String TrimEnd()
```

This text without trailing ASCII whitespace.

<sub>[stdlib/Text.sl:272](../../stdlib/Text.sl#L272)</sub>

#### Replace *method*

```
String Replace(String from, String to)
```

Every occurrence of `from` replaced by `to`.

Left to right and non-overlapping, so the replacement is never searched
again: replacing "a" with "aa" terminates.

<sub>[stdlib/Text.sl:292](../../stdlib/Text.sl#L292)</sub>

#### Repeat *method*

```
String Repeat(nuint count)
```

This text `count` times over. Zero gives "".

<sub>[stdlib/Text.sl:319](../../stdlib/Text.sl#L319)</sub>

#### PadLeft *method*

```
String PadLeft(nuint width)
```

Spaces on the left until the text is `width` bytes. Never truncates.

<sub>[stdlib/Text.sl:333](../../stdlib/Text.sl#L333)</sub>

#### PadRight *method*

```
String PadRight(nuint width)
```

Spaces on the right until the text is `width` bytes. Never truncates.

<sub>[stdlib/Text.sl:342](../../stdlib/Text.sl#L342)</sub>

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

<sub>[stdlib/Text.sl:357](../../stdlib/Text.sl#L357)</sub>

#### PadRight *method*

```
String PadRight(nuint width, String with)
```

The same as `PadRight(width)` with something other than a space.

Measured in bytes, so a multi-byte `with` pads by whole copies and may
fall short of the width rather than overshoot it. An empty `with`
answers the string unchanged, since no number of copies would reach.

<sub>[stdlib/Text.sl:372](../../stdlib/Text.sl#L372)</sub>

#### Split *method*

```
String[] Split(String separator)
```

This text cut at every `separator`.

Adjacent separators produce empty parts, and so do ones at either end:
splitting "a,,b" on ',' gives three parts, and "" gives one. That is
what makes it reversible -- joining the result with the same separator
gives the original back.

<sub>[stdlib/Text.sl:390](../../stdlib/Text.sl#L390)</sub>

#### Split *method*

```
String[] Split(char separator)
```

This text cut at every occurrence of one code unit.

<sub>[stdlib/Text.sl:425](../../stdlib/Text.sl#L425)</sub>

#### SplitLines *method*

```
String[] SplitLines()
```

This text cut into lines, on "\n" or "\r\n".

A trailing newline does not produce a final empty line, because a file
that ends in one has as many lines as one that does not -- which is the
opposite of what `Split` does, and the reason this is not `Split('\n')`.

<sub>[stdlib/Text.sl:460](../../stdlib/Text.sl#L460)</sub>

#### ToUpperAscii *method*

```
String ToUpperAscii()
```

This text with every ASCII letter uppercased, and every other byte left
as it was. See the note at the top of this file.

<sub>[stdlib/Text.sl:506](../../stdlib/Text.sl#L506)</sub>

#### ToLowerAscii *method*

```
String ToLowerAscii()
```

This text with every ASCII letter lowercased.

<sub>[stdlib/Text.sl:512](../../stdlib/Text.sl#L512)</sub>

#### EqualsIgnoreCaseAscii *method*

```
bool EqualsIgnoreCaseAscii(String other)
```

True when the two texts differ only in the case of ASCII letters.

<sub>[stdlib/Text.sl:518](../../stdlib/Text.sl#L518)</sub>

#### CompareTo *method*

```
int CompareTo(String other)
```

Orders two texts by their bytes: negative, zero or positive.

Comparing UTF-8 byte by byte happens to order by code point as well,
because the encoding was designed so that it would. It is not a
linguistic ordering and does not claim to be one.

<sub>[stdlib/Text.sl:542](../../stdlib/Text.sl#L542)</sub>

#### ByteAt *method*

```
byte ByteAt(nuint index)
```

The byte at `index`, which is a code unit and not a character.

Unchecked, unlike the slicing methods: this reads the buffer directly,
so an `index` at or past `ByteLength` reads memory that is not the
string's. Check the length first, or slice instead.

<sub>[stdlib/Text.sl:569](../../stdlib/Text.sl#L569)</sub>

#### CodePointAt *method*

```
char32 CodePointAt(nuint index)
```

The scalar beginning at `index`.

`index` must be the start of a character; one that lands inside a
sequence gives U+FFFD, which is what a decoder does with a byte that
cannot begin one.

<sub>[stdlib/Text.sl:579](../../stdlib/Text.sl#L579)</sub>

#### NextCodePoint *method*

```
nuint NextCodePoint(nuint index)
```

The index of the character after the one at `index`.

Together with `CodePointAt` this is how the text is walked properly:

```
for (nuint at = 0; at < s.ByteLength(); at = s.NextCodePoint(at)) {
    var c = s.CodePointAt(at);
}
```

<sub>[stdlib/Text.sl:615](../../stdlib/Text.sl#L615)</sub>

#### Join *method*

```
String Join(String[] parts)
```

`parts` written out with this text between them. The inverse of `Split`.

A method on the separator rather than a free function, because every
module imports `Standard.Text` without asking and a global named `Join`
is a global named `Join`. `", ".Join(parts)` also reads in the order it
happens.

<sub>[stdlib/Text.sl:637](../../stdlib/Text.sl#L637)</sub>

#### ToBytes *method*

```
byte[] ToBytes()
```

This text's bytes, copied into an array.

A copy rather than a view: a `String` is immutable and an array is not,
so handing out the storage would let one be changed through the other.

<sub>[stdlib/Text.sl:660](../../stdlib/Text.sl#L660)</sub>

### StringBuilder *class*

```
class StringBuilder
```

*No documentation.*

<sub>[stdlib/Text.sl:728](../../stdlib/Text.sl#L728)</sub>

#### Append *method*

```
void Append(String text)
```

Text, as its bytes.

<sub>[stdlib/Text.sl:808](../../stdlib/Text.sl#L808)</sub>

#### AppendLine *method*

```
void AppendLine(String text)
```

Text and a newline.

<sub>[stdlib/Text.sl:814](../../stdlib/Text.sl#L814)</sub>

#### AppendInteger *method*

```
void AppendInteger(long value)
```

A signed integer in base ten.

Written into the buffer a digit at a time rather than through
`FromInteger`, because a builder appending numbers in a loop should not
allocate a `String` per number.

<sub>[stdlib/Text.sl:825](../../stdlib/Text.sl#L825)</sub>

#### AppendDouble *method*

```
void AppendDouble(double value)
```

The shortest text that reads back as the same number.

This one does allocate a `String` first: shortest round-trip formatting
is the runtime's, and there is nothing to gain by copying it here.

<sub>[stdlib/Text.sl:870](../../stdlib/Text.sl#L870)</sub>

#### AppendByte *method*

```
void AppendByte(byte value)
```

One byte.

The builder holds bytes, so nothing here validates: a caller writing
half a character has written half a character.

<sub>[stdlib/Text.sl:879](../../stdlib/Text.sl#L879)</sub>

#### ByteLength *method*

```
nuint ByteLength()
```

How many bytes have been built. Not a character count.

<sub>[stdlib/Text.sl:889](../../stdlib/Text.sl#L889)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

Whether nothing has been appended, or everything has been cleared.

<sub>[stdlib/Text.sl:892](../../stdlib/Text.sl#L892)</sub>

#### Clear *method*

```
void Clear()
```

Throws the length away and keeps the room, so a builder reused in a
loop allocates once.

<sub>[stdlib/Text.sl:896](../../stdlib/Text.sl#L896)</sub>

#### ByteAt *method*

```
byte ByteAt(nuint index)
```

One byte by position.

A call rather than a pointer, because the buffer moves as it grows and
a `byte*` into it would dangle at the next append -- the one thing
`String`'s own pointer can never do.

<sub>[stdlib/Text.sl:906](../../stdlib/Text.sl#L906)</sub>

#### SetByteAt *method*

```
void SetByteAt(nuint index, byte value)
```

Replaces one byte by position.

<sub>[stdlib/Text.sl:914](../../stdlib/Text.sl#L914)</sub>

#### Insert *method*

```
void Insert(nuint at, String text)
```

Text put in at a position. Inserting at the length is appending, which
is why `at == ByteLength()` is allowed.

<sub>[stdlib/Text.sl:925](../../stdlib/Text.sl#L925)</sub>

#### Remove *method*

```
void Remove(nuint at, nuint count)
```

Bytes taken out from a position. Removing more than is there removes to
the end rather than failing.

<sub>[stdlib/Text.sl:942](../../stdlib/Text.sl#L942)</sub>

#### ToText *method*

```
String ToText()
```

What has been built, as text. The builder stays usable afterwards and
the string does not change when it is appended to again.

<sub>[stdlib/Text.sl:955](../../stdlib/Text.sl#L955)</sub>

#### AppendCodePoint *method*

```
void AppendCodePoint(char32 value)
```

One Unicode scalar, encoded as UTF-8.

This rather than `Append(char)`, because a `char` is one code unit and
appending a lone continuation byte would put the builder into a state
no `String` can be made from. A scalar always encodes to something
whole.

<sub>[stdlib/Text.sl:969](../../stdlib/Text.sl#L969)</sub>

#### AppendLine *method*

```
void AppendLine()
```

A newline on its own.

<sub>[stdlib/Text.sl:1012](../../stdlib/Text.sl#L1012)</sub>

#### Append *method*

```
void Append(bool value)
```

`true` or `false`.

There is deliberately no `Append(long)` or `Append(double)` beside this
one. An integer literal converts to both, so the two together would make
`Append(42)` ambiguous -- which is why `AppendInteger` and `AppendDouble`
were spelled out in the first place. A bool converts to neither.

<sub>[stdlib/Text.sl:1023](../../stdlib/Text.sl#L1023)</sub>

#### AppendBytes *method*

```
void AppendBytes(byte[] data)
```

Raw bytes. They are appended as they are, so it is the caller who
decides whether what comes out is text.

<sub>[stdlib/Text.sl:1030](../../stdlib/Text.sl#L1030)</sub>

#### AppendJoined *method*

```
void AppendJoined(String separator, String[] parts)
```

`parts` with `separator` between them.

<sub>[stdlib/Text.sl:1038](../../stdlib/Text.sl#L1038)</sub>

#### HasContent *property*

```
bool HasContent { get; }
```

Whether anything has been appended. The opposite of `IsEmpty`.

<sub>[stdlib/Text.sl:1051](../../stdlib/Text.sl#L1051)</sub>

#### IndexOf *method*

```
long IndexOf(String value)
```

Where `value` first appears in what has been built, or `NotFound`.

Byte by byte through the runtime rather than over a pointer, because a
builder's storage moves when it grows and a pointer into it would be a
pointer into the previous allocation.

<sub>[stdlib/Text.sl:1064](../../stdlib/Text.sl#L1064)</sub>

#### Contains *method*

```
bool Contains(String value)
```

True when `value` appears in what has been built.

<sub>[stdlib/Text.sl:1091](../../stdlib/Text.sl#L1091)</sub>

#### Truncate *method*

```
void Truncate(nuint at)
```

Everything from `at` to the end, thrown away.

<sub>[stdlib/Text.sl:1099](../../stdlib/Text.sl#L1099)</sub>

#### ReplaceFirst *method*

```
bool ReplaceFirst(String from, String to)
```

The first occurrence of `from` replaced by `to`, if there is one.

<sub>[stdlib/Text.sl:1108](../../stdlib/Text.sl#L1108)</sub>

#### ReplaceAll *method*

```
nuint ReplaceAll(String from, String to)
```

Every occurrence of `from` replaced by `to`.

The search resumes past the replacement, so replacing "a" with "aa"
terminates rather than growing forever.

<sub>[stdlib/Text.sl:1123](../../stdlib/Text.sl#L1123)</sub>

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
`UnitAt` can land on half a surrogate pair. `CodePointAt` joins the pair.

<sub>[stdlib/Text.sl:1180](../../stdlib/Text.sl#L1180)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

Whether there are any units at all.

<sub>[stdlib/Text.sl:1184](../../stdlib/Text.sl#L1184)</sub>

#### UnitAt *method*

```
char16 UnitAt(nuint index)
```

The unit at `index`. A unit, not a character: one half of a surrogate
pair is a unit and is not a character.

<sub>[stdlib/Text.sl:1188](../../stdlib/Text.sl#L1188)</sub>

#### CodePointAt *method*

```
char32 CodePointAt(nuint index)
```

The scalar beginning at `index`, joining a surrogate pair.

An unpaired surrogate gives U+FFFD, which is what transcoding it would
have produced -- a lone half cannot be encoded in UTF-8 at all.

<sub>[stdlib/Text.sl:1197](../../stdlib/Text.sl#L1197)</sub>

#### NextCodePoint *method*

```
nuint NextCodePoint(nuint index)
```

The index of the character after the one at `index`.

<sub>[stdlib/Text.sl:1219](../../stdlib/Text.sl#L1219)</sub>

#### Equals *method*

```
bool Equals(Utf16String other)
```

True when the two hold the same units.

<sub>[stdlib/Text.sl:1232](../../stdlib/Text.sl#L1232)</sub>

#### ToBytes *method*

```
byte[] ToBytes()
```

The units as raw bytes, little-endian, which is what a Windows API and
a UTF-16LE file both expect.

<sub>[stdlib/Text.sl:1251](../../stdlib/Text.sl#L1251)</sub>

### string *alias*

```
using string = String
```

`String`, spelled the way the primitives are.

`int` and `double` are keywords and lowercase, and a type that is just as
built in has no reason to look different. It is an alias and not a second
type, so a diagnostic says `String` whichever one was written.

<sub>[stdlib/Text.sl:704](../../stdlib/Text.sl#L704)</sub>

## Functions

### FromBool *function*

```
String FromBool(bool value)
```

`"true"` or `"false"`.

<sub>[stdlib/Text.sl:1365](../../stdlib/Text.sl#L1365)</sub>

### FromBytes *function*

```
String FromBytes(byte* data, nuint byteLength)
```

A copy of `byteLength` bytes, taken to be UTF-8.

<sub>[stdlib/Text.sl:1372](../../stdlib/Text.sl#L1372)</sub>

### FromChar *function*

```
String FromChar(char32 value)
```

One code point as the character it names, not as its number.
`Text.FromInteger((long)c)` is how to ask for the number.

<sub>[stdlib/Text.sl:1369](../../stdlib/Text.sl#L1369)</sub>

### FromDouble *function*

```
String FromDouble(double value)
```

The shortest text that reads back as the same number.

<sub>[stdlib/Text.sl:1362](../../stdlib/Text.sl#L1362)</sub>

### FromInteger *function*

```
String FromInteger(long value)
```

A signed integer in base ten.

<sub>[stdlib/Text.sl:1345](../../stdlib/Text.sl#L1345)</sub>

### FromInteger *function*

```
String FromInteger(ulong value)
```

An unsigned integer in base ten.

A separate entry point rather than letting the signed one take it: a
`ulong` past 2^63 formatted as signed prints as a negative number.

<sub>[stdlib/Text.sl:1351](../../stdlib/Text.sl#L1351)</sub>

### FromInteger *function*

```
String FromInteger(nuint value)
```

A `nuint` in base ten.

Its own overload rather than a widening, because a `nuint` is a `size_t`
and cannot share the 64-bit entry point: on a 32-bit target the runtime
would read four bytes of argument and four of whatever was next on the
stack, and `$"{n}"` printed 8612659968337772549 for 5.

<sub>[stdlib/Text.sl:1359](../../stdlib/Text.sl#L1359)</sub>

### FromNullTerminated *function*

```
String FromNullTerminated(byte* text)
```

A copy of the bytes up to the first NUL, taken to be UTF-8. What a C
function that answers with a `char*` hands back.

<sub>[stdlib/Text.sl:1377](../../stdlib/Text.sl#L1377)</sub>

### FromNullTerminatedUtf16 *function*

```
String FromNullTerminatedUtf16(char16* units)
```

UTF-16 up to the first NUL unit, transcoded to UTF-8.

<sub>[stdlib/Text.sl:1387](../../stdlib/Text.sl#L1387)</sub>

### FromUtf16 *function*

```
String FromUtf16(char16* units, nuint unitCount)
```

UTF-16 transcoded to UTF-8.

A pointer and a count rather than a `Utf16String`, because a wide platform
API writes into a buffer the caller owns and that pair is what comes back.

<sub>[stdlib/Text.sl:1383](../../stdlib/Text.sl#L1383)</sub>

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

<sub>[stdlib/Text.sl:58](../../stdlib/Text.sl#L58)</sub>

