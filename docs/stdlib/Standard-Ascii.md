# Standard.Ascii

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Asking what a byte is, when the answer is allowed to be an ASCII one.

Every function here works on one byte and says nothing about Unicode. That
is not a limitation being apologised for -- it is the whole point. A byte
above 127 in UTF-8 is part of a character rather than a character, so a
question like "is this a digit" has exactly one honest answer at the byte
level, and it is this one. Anything that needs to ask about a character
should decode first, with `String.GetCodePointAt`.

This is a module of its own rather than more of `Standard.Text` because
`Standard.Text` is imported into every module whether a program asks or not,
and `IsDigit` is far too good a name to take from every program in the world.

## Contents

**Functions** &nbsp; [FromHexDigit](#fromhexdigit-function) &middot; [IsAscii](#isascii-function) &middot; [IsControl](#iscontrol-function) &middot; [IsDigit](#isdigit-function) &middot; [IsHexDigit](#ishexdigit-function) &middot; [IsLetter](#isletter-function) &middot; [IsLetterOrDigit](#isletterordigit-function) &middot; [IsLower](#islower-function) &middot; [IsUpper](#isupper-function) &middot; [IsWhiteSpace](#iswhitespace-function) &middot; [ToHexDigit](#tohexdigit-function) &middot; [ToHexDigitUpper](#tohexdigitupper-function) &middot; [ToLower](#tolower-function) &middot; [ToUpper](#toupper-function)

## Functions

### FromHexDigit *function*

```
int FromHexDigit(byte value)
```

What a hexadecimal digit is worth, or -1 when it is not one.

**See also** &nbsp; [Ascii.ToHexDigit](#tohexdigit-function)

<sub>[stdlib/Ascii.sl:112](../../stdlib/Ascii.sl#L112)</sub>

### IsAscii *function*

```
bool IsAscii(byte value)
```

True for a byte below 128, which is the only range where any of this is
also true of the character.

<sub>[stdlib/Ascii.sl:82](../../stdlib/Ascii.sl#L82)</sub>

### IsControl *function*

```
bool IsControl(byte value)
```

True for a control character: below 32, or DEL.

<sub>[stdlib/Ascii.sl:88](../../stdlib/Ascii.sl#L88)</sub>

### IsDigit *function*

```
bool IsDigit(byte value)
```

True for `0`-`9`.

<sub>[stdlib/Ascii.sl:43](../../stdlib/Ascii.sl#L43)</sub>

### IsHexDigit *function*

```
bool IsHexDigit(byte value)
```

True for `0`-`9`, `a`-`f` and `A`-`F`.

<sub>[stdlib/Ascii.sl:49](../../stdlib/Ascii.sl#L49)</sub>

### IsLetter *function*

```
bool IsLetter(byte value)
```

True for `A`-`Z` and `a`-`z`.

<sub>[stdlib/Ascii.sl:57](../../stdlib/Ascii.sl#L57)</sub>

### IsLetterOrDigit *function*

```
bool IsLetterOrDigit(byte value)
```

True for a letter or a digit.

<sub>[stdlib/Ascii.sl:63](../../stdlib/Ascii.sl#L63)</sub>

### IsLower *function*

```
bool IsLower(byte value)
```

True for `a`-`z`.

<sub>[stdlib/Ascii.sl:75](../../stdlib/Ascii.sl#L75)</sub>

### IsUpper *function*

```
bool IsUpper(byte value)
```

True for `A`-`Z`.

<sub>[stdlib/Ascii.sl:69](../../stdlib/Ascii.sl#L69)</sub>

### IsWhiteSpace *function*

```
bool IsWhiteSpace(byte value)
```

True for space, tab, newline, vertical tab, form feed and carriage return.

<sub>[stdlib/Ascii.sl:37](../../stdlib/Ascii.sl#L37)</sub>

### ToHexDigit *function*

```
byte ToHexDigit(int value)
```

The lowercase hexadecimal digit for a value from 0 to 15.

**See also** &nbsp; [Ascii.FromHexDigit](#fromhexdigit-function) &middot; [Ascii.ToHexDigitUpper](#tohexdigitupper-function)

<sub>[stdlib/Ascii.sl:127](../../stdlib/Ascii.sl#L127)</sub>

### ToHexDigitUpper *function*

```
byte ToHexDigitUpper(int value)
```

The uppercase hexadecimal digit for a value from 0 to 15.

**See also** &nbsp; [Ascii.FromHexDigit](#fromhexdigit-function) &middot; [Ascii.ToHexDigit](#tohexdigit-function)

<sub>[stdlib/Ascii.sl:138](../../stdlib/Ascii.sl#L138)</sub>

### ToLower *function*

```
byte ToLower(byte value)
```

The lowercase of an ASCII letter, or the byte unchanged.

<sub>[stdlib/Ascii.sl:102](../../stdlib/Ascii.sl#L102)</sub>

### ToUpper *function*

```
byte ToUpper(byte value)
```

The uppercase of an ASCII letter, or the byte unchanged.

<sub>[stdlib/Ascii.sl:94](../../stdlib/Ascii.sl#L94)</sub>

