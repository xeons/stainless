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

**Types** &nbsp; [String](#string-class) &middot; [StringBuilder](#stringbuilder-class) &middot; [Utf16String](#utf16string-class)

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

<sub>[stdlib/Text.sl:76](../../stdlib/Text.sl#L76)</sub>

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

<sub>[stdlib/Text.sl:87](../../stdlib/Text.sl#L87)</sub>

#### StartsWith *method*

```
bool StartsWith(String prefix)
```

True when this text begins with `prefix`. An empty prefix always does.

<sub>[stdlib/Text.sl:92](../../stdlib/Text.sl#L92)</sub>

#### EndsWith *method*

```
bool EndsWith(String suffix)
```

True when this text ends with `suffix`. An empty suffix always does.

<sub>[stdlib/Text.sl:101](../../stdlib/Text.sl#L101)</sub>

#### Contains *method*

```
bool Contains(String value)
```

True when `value` appears anywhere in this text.

<sub>[stdlib/Text.sl:111](../../stdlib/Text.sl#L111)</sub>

#### Contains *method*

```
bool Contains(char value)
```

True when this single code unit appears. Only meaningful for ASCII: a
`char` above 127 is one byte of a sequence rather than a character.

<sub>[stdlib/Text.sl:118](../../stdlib/Text.sl#L118)</sub>

#### IndexOf *method*

```
long IndexOf(String value)
```

Where `value` first appears, or `NotFound`.

An empty `value` is found at 0, which is where it is: every string
begins with the empty string.

<sub>[stdlib/Text.sl:129](../../stdlib/Text.sl#L129)</sub>

#### IndexOf *method*

```
long IndexOf(String value, nuint start)
```

Where `value` first appears at or after `start`, or `NotFound`.

<sub>[stdlib/Text.sl:135](../../stdlib/Text.sl#L135)</sub>

#### LastIndexOf *method*

```
long LastIndexOf(String value)
```

Where `value` last appears, or `NotFound`.

<sub>[stdlib/Text.sl:160](../../stdlib/Text.sl#L160)</sub>

#### IndexOf *method*

```
long IndexOf(char value)
```

Where this code unit first appears, or `NotFound`.

<sub>[stdlib/Text.sl:182](../../stdlib/Text.sl#L182)</sub>

#### LastIndexOf *method*

```
long LastIndexOf(char value)
```

Where this code unit last appears, or `NotFound`.

<sub>[stdlib/Text.sl:196](../../stdlib/Text.sl#L196)</sub>

#### Substring *method*

```
String Substring(nuint start)
```

Everything from `start` to the end. A `start` past the end gives "".

<sub>[stdlib/Text.sl:211](../../stdlib/Text.sl#L211)</sub>

#### Before *method*

```
String Before(String separator)
```

The text before the first `separator`, or all of it when there is none.

<sub>[stdlib/Text.sl:220](../../stdlib/Text.sl#L220)</sub>

#### After *method*

```
String After(String separator)
```

The text after the first `separator`, or "" when there is none.

<sub>[stdlib/Text.sl:229](../../stdlib/Text.sl#L229)</sub>

#### AfterLast *method*

```
String AfterLast(String separator)
```

The text after the last `separator`, or all of it when there is none.

<sub>[stdlib/Text.sl:238](../../stdlib/Text.sl#L238)</sub>

#### Trim *method*

```
String Trim()
```

This text without leading or trailing ASCII whitespace.

<sub>[stdlib/Text.sl:249](../../stdlib/Text.sl#L249)</sub>

#### TrimStart *method*

```
String TrimStart()
```

This text without leading ASCII whitespace.

<sub>[stdlib/Text.sl:255](../../stdlib/Text.sl#L255)</sub>

#### TrimEnd *method*

```
String TrimEnd()
```

This text without trailing ASCII whitespace.

<sub>[stdlib/Text.sl:270](../../stdlib/Text.sl#L270)</sub>

#### Replace *method*

```
String Replace(String from, String to)
```

Every occurrence of `from` replaced by `to`.

Left to right and non-overlapping, so the replacement is never searched
again: replacing "a" with "aa" terminates.

<sub>[stdlib/Text.sl:290](../../stdlib/Text.sl#L290)</sub>

#### Repeat *method*

```
String Repeat(nuint count)
```

This text `count` times over. Zero gives "".

<sub>[stdlib/Text.sl:317](../../stdlib/Text.sl#L317)</sub>

#### PadLeft *method*

```
String PadLeft(nuint width)
```

Spaces on the left until the text is `width` bytes. Never truncates.

<sub>[stdlib/Text.sl:331](../../stdlib/Text.sl#L331)</sub>

#### PadRight *method*

```
String PadRight(nuint width)
```

Spaces on the right until the text is `width` bytes. Never truncates.

<sub>[stdlib/Text.sl:340](../../stdlib/Text.sl#L340)</sub>

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

<sub>[stdlib/Text.sl:355](../../stdlib/Text.sl#L355)</sub>

#### PadRight *method*

```
String PadRight(nuint width, String with)
```

The same as `PadRight(width)` with something other than a space.

Measured in bytes, so a multi-byte `with` pads by whole copies and may
fall short of the width rather than overshoot it. An empty `with`
answers the string unchanged, since no number of copies would reach.

<sub>[stdlib/Text.sl:370](../../stdlib/Text.sl#L370)</sub>

#### Split *method*

```
String[] Split(String separator)
```

This text cut at every `separator`.

Adjacent separators produce empty parts, and so do ones at either end:
splitting "a,,b" on ',' gives three parts, and "" gives one. That is
what makes it reversible -- joining the result with the same separator
gives the original back.

<sub>[stdlib/Text.sl:388](../../stdlib/Text.sl#L388)</sub>

#### Split *method*

```
String[] Split(char separator)
```

This text cut at every occurrence of one code unit.

<sub>[stdlib/Text.sl:423](../../stdlib/Text.sl#L423)</sub>

#### SplitLines *method*

```
String[] SplitLines()
```

This text cut into lines, on "\n" or "\r\n".

A trailing newline does not produce a final empty line, because a file
that ends in one has as many lines as one that does not -- which is the
opposite of what `Split` does, and the reason this is not `Split('\n')`.

<sub>[stdlib/Text.sl:458](../../stdlib/Text.sl#L458)</sub>

#### ToUpperAscii *method*

```
String ToUpperAscii()
```

This text with every ASCII letter uppercased, and every other byte left
as it was. See the note at the top of this file.

<sub>[stdlib/Text.sl:504](../../stdlib/Text.sl#L504)</sub>

#### ToLowerAscii *method*

```
String ToLowerAscii()
```

This text with every ASCII letter lowercased.

<sub>[stdlib/Text.sl:510](../../stdlib/Text.sl#L510)</sub>

#### EqualsIgnoreCaseAscii *method*

```
bool EqualsIgnoreCaseAscii(String other)
```

True when the two texts differ only in the case of ASCII letters.

<sub>[stdlib/Text.sl:516](../../stdlib/Text.sl#L516)</sub>

#### CompareTo *method*

```
int CompareTo(String other)
```

Orders two texts by their bytes: negative, zero or positive.

Comparing UTF-8 byte by byte happens to order by code point as well,
because the encoding was designed so that it would. It is not a
linguistic ordering and does not claim to be one.

<sub>[stdlib/Text.sl:540](../../stdlib/Text.sl#L540)</sub>

#### ByteAt *method*

```
byte ByteAt(nuint index)
```

The byte at `index`, which is a code unit and not a character.

Unchecked, unlike the slicing methods: this reads the buffer directly,
so an `index` at or past `ByteLength` reads memory that is not the
string's. Check the length first, or slice instead.

<sub>[stdlib/Text.sl:567](../../stdlib/Text.sl#L567)</sub>

#### CodePointAt *method*

```
char32 CodePointAt(nuint index)
```

The scalar beginning at `index`.

`index` must be the start of a character; one that lands inside a
sequence gives U+FFFD, which is what a decoder does with a byte that
cannot begin one.

<sub>[stdlib/Text.sl:577](../../stdlib/Text.sl#L577)</sub>

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

<sub>[stdlib/Text.sl:613](../../stdlib/Text.sl#L613)</sub>

#### Join *method*

```
String Join(String[] parts)
```

`parts` written out with this text between them. The inverse of `Split`.

A method on the separator rather than a free function, because every
module imports `Standard.Text` without asking and a global named `Join`
is a global named `Join`. `", ".Join(parts)` also reads in the order it
happens.

<sub>[stdlib/Text.sl:635](../../stdlib/Text.sl#L635)</sub>

#### ToBytes *method*

```
byte[] ToBytes()
```

This text's bytes, copied into an array.

A copy rather than a view: a `String` is immutable and an array is not,
so handing out the storage would let one be changed through the other.

<sub>[stdlib/Text.sl:658](../../stdlib/Text.sl#L658)</sub>

### StringBuilder *class*

```
class StringBuilder
```

Text assembled a piece at a time.

Reach for this where a loop would otherwise write `text = text + more`: a
`String` is immutable, so that line allocates and copies everything so far
on every pass, and a builder appends into one buffer that grows instead.
For two or three pieces known up front, `+` is clearer and costs no more.

The declaration is the runtime's, as `String`'s is, and the appending is
here. Call `ToString` for the text; the builder stays usable afterwards and
the string does not change when it is appended to again.

<sub>[stdlib/Text.sl:707](../../stdlib/Text.sl#L707)</sub>

#### AppendCodePoint *method*

```
void AppendCodePoint(char32 value)
```

One Unicode scalar, encoded as UTF-8.

This rather than `Append(char)`, because a `char` is one code unit and
appending a lone continuation byte would put the builder into a state
no `String` can be made from. A scalar always encodes to something
whole.

<sub>[stdlib/Text.sl:718](../../stdlib/Text.sl#L718)</sub>

#### AppendLine *method*

```
void AppendLine()
```

A newline on its own.

<sub>[stdlib/Text.sl:761](../../stdlib/Text.sl#L761)</sub>

#### Append *method*

```
void Append(bool value)
```

`true` or `false`.

There is deliberately no `Append(long)` or `Append(double)` beside this
one. An integer literal converts to both, so the two together would make
`Append(42)` ambiguous -- which is why `AppendInteger` and `AppendDouble`
were spelled out in the first place. A bool converts to neither.

<sub>[stdlib/Text.sl:772](../../stdlib/Text.sl#L772)</sub>

#### AppendBytes *method*

```
void AppendBytes(byte[] data)
```

Raw bytes. They are appended as they are, so it is the caller who
decides whether what comes out is text.

<sub>[stdlib/Text.sl:779](../../stdlib/Text.sl#L779)</sub>

#### AppendJoined *method*

```
void AppendJoined(String separator, String[] parts)
```

`parts` with `separator` between them.

<sub>[stdlib/Text.sl:788](../../stdlib/Text.sl#L788)</sub>

#### HasContent *property*

```
bool HasContent { get; }
```

Whether anything has been appended. The opposite of `IsEmpty`.

<sub>[stdlib/Text.sl:801](../../stdlib/Text.sl#L801)</sub>

#### IndexOf *method*

```
long IndexOf(String value)
```

Where `value` first appears in what has been built, or `NotFound`.

Byte by byte through the runtime rather than over a pointer, because a
builder's storage moves when it grows and a pointer into it would be a
pointer into the previous allocation.

<sub>[stdlib/Text.sl:814](../../stdlib/Text.sl#L814)</sub>

#### Contains *method*

```
bool Contains(String value)
```

True when `value` appears in what has been built.

<sub>[stdlib/Text.sl:841](../../stdlib/Text.sl#L841)</sub>

#### Truncate *method*

```
void Truncate(nuint at)
```

Everything from `at` to the end, thrown away.

<sub>[stdlib/Text.sl:849](../../stdlib/Text.sl#L849)</sub>

#### ReplaceFirst *method*

```
bool ReplaceFirst(String from, String to)
```

The first occurrence of `from` replaced by `to`, if there is one.

<sub>[stdlib/Text.sl:858](../../stdlib/Text.sl#L858)</sub>

#### ReplaceAll *method*

```
nuint ReplaceAll(String from, String to)
```

Every occurrence of `from` replaced by `to`.

The search resumes past the replacement, so replacing "a" with "aa"
terminates rather than growing forever.

<sub>[stdlib/Text.sl:873](../../stdlib/Text.sl#L873)</sub>

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

<sub>[stdlib/Text.sl:930](../../stdlib/Text.sl#L930)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

Whether there are any units at all.

<sub>[stdlib/Text.sl:934](../../stdlib/Text.sl#L934)</sub>

#### UnitAt *method*

```
char16 UnitAt(nuint index)
```

The unit at `index`. A unit, not a character: one half of a surrogate
pair is a unit and is not a character.

<sub>[stdlib/Text.sl:938](../../stdlib/Text.sl#L938)</sub>

#### CodePointAt *method*

```
char32 CodePointAt(nuint index)
```

The scalar beginning at `index`, joining a surrogate pair.

An unpaired surrogate gives U+FFFD, which is what transcoding it would
have produced -- a lone half cannot be encoded in UTF-8 at all.

<sub>[stdlib/Text.sl:947](../../stdlib/Text.sl#L947)</sub>

#### NextCodePoint *method*

```
nuint NextCodePoint(nuint index)
```

The index of the character after the one at `index`.

<sub>[stdlib/Text.sl:969](../../stdlib/Text.sl#L969)</sub>

#### Equals *method*

```
bool Equals(Utf16String other)
```

True when the two hold the same units.

<sub>[stdlib/Text.sl:982](../../stdlib/Text.sl#L982)</sub>

#### ToBytes *method*

```
byte[] ToBytes()
```

The units as raw bytes, little-endian, which is what a Windows API and
a UTF-16LE file both expect.

<sub>[stdlib/Text.sl:1001](../../stdlib/Text.sl#L1001)</sub>

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

<sub>[stdlib/Text.sl:56](../../stdlib/Text.sl#L56)</sub>

