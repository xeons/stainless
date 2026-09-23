# Standard.Convert

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Turning things into other things: bytes into text, text into numbers.

Two jobs that .NET puts in one class, and they are here together for the same
reason -- they are what a program reaches for at the edge, where a value
arrived as characters and has to become something, or has to leave as
characters and is not one.

Everything that can fail returns a `Result`. There is no `Parse` that stops
the program and no `TryParse` with an out parameter, because the language has
neither exceptions nor `out`: a function that can fail says so in its return
type, and the value is unreadable until the failure has been checked (§2.6).

## Contents

**Types** &nbsp; [ConvertError](#converterror-enum)

**Functions** &nbsp; [FromBase64](#frombase64-function) &middot; [FromHex](#fromhex-function) &middot; [FromLong](#fromlong-function) &middot; [ToBase64](#tobase64-function) &middot; [ToBase64Text](#tobase64text-function) &middot; [ToBase64Url](#tobase64url-function) &middot; [ToDouble](#todouble-function) &middot; [ToHex](#tohex-function) &middot; [ToHex](#tohex-function) &middot; [ToInt](#toint-function) &middot; [ToInt](#toint-function) &middot; [ToLong](#tolong-function) &middot; [ToLong](#tolong-function) &middot; [ToULong](#toulong-function) &middot; [ToULong](#toulong-function)

## Types

### ConvertError *enum*

```
enum ConvertError
```

Why a conversion did not happen.

<sub>[stdlib/Convert.sl:43](../../stdlib/Convert.sl#L43)</sub>

#### Empty *case*

```
Empty
```

There was nothing to convert.

<sub>[stdlib/Convert.sl:46](../../stdlib/Convert.sl#L46)</sub>

#### Malformed *case*

```
Malformed
```

A character that cannot appear in this form.

<sub>[stdlib/Convert.sl:49](../../stdlib/Convert.sl#L49)</sub>

#### OutOfRange *case*

```
OutOfRange
```

The digits were fine and the number does not fit.

<sub>[stdlib/Convert.sl:52](../../stdlib/Convert.sl#L52)</sub>

## Functions

### FromBase64 *function*

```
Result<byte[], ConvertError> FromBase64(String text)
```

Base64 back into bytes, accepting both alphabets and padding or none.
Padding MUST come only at the end, and MUST complete the last group of
four when it is there at all.

Whitespace is skipped, because base64 in the wild arrives wrapped at 64 or
76 columns and a decoder that refused a newline would be useless for the
thing it is most often pointed at.

**Fails with**

- [ConvertError.Malformed](#malformed-case) — a character outside both alphabets, or padding that is not a whole tail of the last group

**See also** &nbsp; [Convert.ToBase64](#tobase64-function) &middot; [Convert.ToBase64Url](#tobase64url-function)

<sub>[stdlib/Convert.sl:439](../../stdlib/Convert.sl#L439)</sub>

### FromHex *function*

```
Result<byte[], ConvertError> FromHex(String text)
```

Hexadecimal back into bytes. Either case, and an odd number of digits is
malformed rather than padded, because there is no way to know which end the
missing half belonged to.

**Fails with**

- [ConvertError.Malformed](#malformed-case) — an odd number of digits, or a character that is not one

**See also** &nbsp; [Convert.ToHex](#tohex-function)

<sub>[stdlib/Convert.sl:387](../../stdlib/Convert.sl#L387)</sub>

### FromLong *function*

```
String FromLong(long value, uint radix)
```

A whole number written in `radix`, from 2 to 36, with lowercase letters.

Base ten needs nothing from here: `Text.FromInteger` already does it, and
through C's own formatter.

**A radix outside 2 to 36 answers `""`.** There is no digit vocabulary for
one, and the answer is a `String` rather than a `Result`, so an empty one
is what says so. `ToLong` reports the same mistake as
`ConvertError.Malformed`, because there it has somewhere to put it.

**Parameters**

- `value` — the number to write, negative or not
- `radix` — the base to write it in, from 2 to 36

**See also** &nbsp; [Convert.ToLong](#tolong-function) &middot; [Text.FromInteger](Standard-Text.md#frominteger-function)

<sub>[stdlib/Convert.sl:231](../../stdlib/Convert.sl#L231)</sub>

### ToBase64 *function*

```
String ToBase64(byte[] data)
```

`data` as base64, padded with `=` to a multiple of four.

**See also** &nbsp; [Convert.FromBase64](#frombase64-function)

<sub>[stdlib/Convert.sl:413](../../stdlib/Convert.sl#L413)</sub>

### ToBase64Text *function*

```
String ToBase64Text(String text)
```

Base64 of the UTF-8 bytes of `text`, which is the common case.

**See also** &nbsp; [Convert.ToBase64](#tobase64-function)

<sub>[stdlib/Convert.sl:514](../../stdlib/Convert.sl#L514)</sub>

### ToBase64Url *function*

```
String ToBase64Url(byte[] data)
```

`data` as base64url: `-` and `_` for the last two characters, and no
padding. What a JWT and a URL query both want, and RFC 4648 §5.

**See also** &nbsp; [Convert.FromBase64](#frombase64-function)

<sub>[stdlib/Convert.sl:422](../../stdlib/Convert.sl#L422)</sub>

### ToDouble *function*

```
Result<double, ConvertError> ToDouble(String text)
```

`text` as a floating-point number.

Accepts what C accepts of the ordinary forms -- an optional sign, digits, a
point, an exponent -- and nothing else. Hexadecimal floats, infinities and
NaN are not spelled here.

A magnitude past the largest double is `OutOfRange`. One below the
smallest rounds to zero, which is the nearest double and not a failure.

**Fails with**

- [ConvertError.Empty](#empty-case) — the text is empty
- [ConvertError.Malformed](#malformed-case) — the text is not one of the forms above
- [ConvertError.OutOfRange](#outofrange-case) — the magnitude is past the largest double

<sub>[stdlib/Convert.sl:279](../../stdlib/Convert.sl#L279)</sub>

### ToHex *function*

```
String ToHex(byte[] data)
```

`data` as lowercase hexadecimal, two characters per byte and nothing between.

**See also** &nbsp; [Convert.FromHex](#fromhex-function)

<sub>[stdlib/Convert.sl:346](../../stdlib/Convert.sl#L346)</sub>

### ToHex *function*

```
String ToHex(byte[] data, bool upper)
```

The same, in the case asked for.

**Parameters**

- `data` — the bytes to write out
- `upper` — true for `A`-`F`, false for `a`-`f`

**See also** &nbsp; [Convert.FromHex](#fromhex-function)

<sub>[stdlib/Convert.sl:356](../../stdlib/Convert.sl#L356)</sub>

### ToInt *function*

```
Result<int, ConvertError> ToInt(String text)
```

`text` as an `int`, which is `ToLong` plus a range check.

**Fails with**

- [ConvertError.Empty](#empty-case) — the text is empty, or is a sign and nothing else
- [ConvertError.Malformed](#malformed-case) — a character is not a digit
- [ConvertError.OutOfRange](#outofrange-case) — the digits do not fit an `int`

**See also** &nbsp; [Convert.ToLong](#tolong-function)

<sub>[stdlib/Convert.sl:134](../../stdlib/Convert.sl#L134)</sub>

### ToInt *function*

```
Result<int, ConvertError> ToInt(String text, uint radix)
```

`text` as an `int` in `radix`, from 2 to 36.

A number that parses as a `long` and does not fit an `int` is
`OutOfRange`, not a truncation.

**Fails with**

- [ConvertError.Empty](#empty-case) — the text is empty, or is a sign and nothing else
- [ConvertError.Malformed](#malformed-case) — `radix` is outside 2 to 36, or a character is not a digit in it
- [ConvertError.OutOfRange](#outofrange-case) — the digits do not fit an `int`

**See also** &nbsp; [Convert.ToLong](#tolong-function)

<sub>[stdlib/Convert.sl:149](../../stdlib/Convert.sl#L149)</sub>

### ToLong *function*

```
Result<long, ConvertError> ToLong(String text)
```

`text` as a whole number in base ten.

A leading `+` or `-` is allowed and nothing else is: no spaces, no
separators, no trailing units. Trim first if the input might have any.

**Fails with**

- [ConvertError.Empty](#empty-case) — the text is empty, or is a sign and nothing else
- [ConvertError.Malformed](#malformed-case) — a character is not a digit
- [ConvertError.OutOfRange](#outofrange-case) — the digits do not fit a `long`

**See also** &nbsp; [Convert.FromLong](#fromlong-function)

<sub>[stdlib/Convert.sl:66](../../stdlib/Convert.sl#L66)</sub>

### ToLong *function*

```
Result<long, ConvertError> ToLong(String text, uint radix)
```

`text` as a whole number in `radix`, from 2 to 36.

Letters count from `a` = 10 in either case, so base 16 takes `1F` and `1f`
alike, and base 36 goes to `z`.

**Fails with**

- [ConvertError.Empty](#empty-case) — the text is empty, or is a sign and nothing else
- [ConvertError.Malformed](#malformed-case) — `radix` is outside 2 to 36, or a character is not a digit in it
- [ConvertError.OutOfRange](#outofrange-case) — the digits do not fit a `long`

**See also** &nbsp; [Convert.FromLong](#fromlong-function)

<sub>[stdlib/Convert.sl:81](../../stdlib/Convert.sl#L81)</sub>

### ToULong *function*

```
Result<ulong, ConvertError> ToULong(String text)
```

`text` as an unsigned whole number. A leading `-` is malformed rather than
wrapping, which is the whole point of asking for an unsigned one.

**Fails with**

- [ConvertError.Empty](#empty-case) — the text is empty, or is a `+` and nothing else
- [ConvertError.Malformed](#malformed-case) — a character is not a digit, a leading `-` among them
- [ConvertError.OutOfRange](#outofrange-case) — the digits do not fit a `ulong`

<sub>[stdlib/Convert.sl:171](../../stdlib/Convert.sl#L171)</sub>

### ToULong *function*

```
Result<ulong, ConvertError> ToULong(String text, uint radix)
```

`text` as an unsigned whole number in `radix`, from 2 to 36.

Letters count from `a` = 10 in either case. A leading `+` is allowed; a
leading `-` is `Malformed`.

**Fails with**

- [ConvertError.Empty](#empty-case) — the text is empty, or is a `+` and nothing else
- [ConvertError.Malformed](#malformed-case) — `radix` is outside 2 to 36, a character is not a digit in it, or the number carries a leading `-`
- [ConvertError.OutOfRange](#outofrange-case) — the digits do not fit a `ulong`

<sub>[stdlib/Convert.sl:185](../../stdlib/Convert.sl#L185)</sub>

