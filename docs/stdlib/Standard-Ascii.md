# Standard.Ascii

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Asking what a byte is, when the answer is allowed to be an ASCII one.

Every function here works on one byte and says nothing about Unicode. That
is not a limitation being apologised for -- it is the whole point. A byte
above 127 in UTF-8 is part of a character rather than a character, so a
question like "is this a digit" has exactly one honest answer at the byte
level, and it is this one. Anything that needs to ask about a character
should decode first, with `String.CodePointAt`.

This is a module of its own rather than more of `Standard.Text` because
`Standard.Text` is imported into every module whether a program asks or not,
and `IsDigit` is far too good a name to take from every program in the world.

## Contents

**Functions** &nbsp; [HexDigit](#hexdigit) &middot; [HexDigitUpper](#hexdigitupper) &middot; [HexValue](#hexvalue) &middot; [IsAscii](#isascii) &middot; [IsControl](#iscontrol) &middot; [IsDigit](#isdigit) &middot; [IsHexDigit](#ishexdigit) &middot; [IsLetter](#isletter) &middot; [IsLetterOrDigit](#isletterordigit) &middot; [IsLower](#islower) &middot; [IsUpper](#isupper) &middot; [IsWhiteSpace](#iswhitespace) &middot; [ToLower](#tolower) &middot; [ToUpper](#toupper)

## Functions

### HexDigit *function*

```
byte HexDigit(int value)
```

The lowercase hexadecimal digit for a value from 0 to 15.

<sub>[stdlib/Ascii.sl:105](../../stdlib/Ascii.sl#L105)</sub>

### HexDigitUpper *function*

```
byte HexDigitUpper(int value)
```

The uppercase hexadecimal digit for a value from 0 to 15.

<sub>[stdlib/Ascii.sl:111](../../stdlib/Ascii.sl#L111)</sub>

### HexValue *function*

```
int HexValue(byte value)
```

What a hexadecimal digit is worth, or -1 when it is not one.

<sub>[stdlib/Ascii.sl:97](../../stdlib/Ascii.sl#L97)</sub>

### IsAscii *function*

```
bool IsAscii(byte value)
```

True for a byte below 128, which is the only range where any of this is
also true of the character.

<sub>[stdlib/Ascii.sl:75](../../stdlib/Ascii.sl#L75)</sub>

### IsControl *function*

```
bool IsControl(byte value)
```

True for a control character: below 32, or DEL.

<sub>[stdlib/Ascii.sl:80](../../stdlib/Ascii.sl#L80)</sub>

### IsDigit *function*

```
bool IsDigit(byte value)
```

True for `0`-`9`.

<sub>[stdlib/Ascii.sl:42](../../stdlib/Ascii.sl#L42)</sub>

### IsHexDigit *function*

```
bool IsHexDigit(byte value)
```

True for `0`-`9`, `a`-`f` and `A`-`F`.

<sub>[stdlib/Ascii.sl:47](../../stdlib/Ascii.sl#L47)</sub>

### IsLetter *function*

```
bool IsLetter(byte value)
```

True for `A`-`Z` and `a`-`z`.

<sub>[stdlib/Ascii.sl:54](../../stdlib/Ascii.sl#L54)</sub>

### IsLetterOrDigit *function*

```
bool IsLetterOrDigit(byte value)
```

True for a letter or a digit.

<sub>[stdlib/Ascii.sl:59](../../stdlib/Ascii.sl#L59)</sub>

### IsLower *function*

```
bool IsLower(byte value)
```

True for `a`-`z`.

<sub>[stdlib/Ascii.sl:69](../../stdlib/Ascii.sl#L69)</sub>

### IsUpper *function*

```
bool IsUpper(byte value)
```

True for `A`-`Z`.

<sub>[stdlib/Ascii.sl:64](../../stdlib/Ascii.sl#L64)</sub>

### IsWhiteSpace *function*

```
bool IsWhiteSpace(byte value)
```

True for space, tab, newline, vertical tab, form feed and carriage return.

<sub>[stdlib/Ascii.sl:37](../../stdlib/Ascii.sl#L37)</sub>

### ToLower *function*

```
byte ToLower(byte value)
```

The lowercase of an ASCII letter, or the byte unchanged.

<sub>[stdlib/Ascii.sl:91](../../stdlib/Ascii.sl#L91)</sub>

### ToUpper *function*

```
byte ToUpper(byte value)
```

The uppercase of an ASCII letter, or the byte unchanged.

<sub>[stdlib/Ascii.sl:85](../../stdlib/Ascii.sl#L85)</sub>

