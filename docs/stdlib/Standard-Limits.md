# Standard.Limits

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

What each number type holds.

A primitive is not a class, so there is nowhere to hang a `MaxValue` on and
these are named for their type instead -- `Limits.MaxLong`, not
`long.MaxValue`. That is the same reason `Text.FromInteger` is a function
rather than a method on `int`.

**A limit is worth naming because the literal is not checkable.** A reader
can see that `MaxInt` is right; nobody can see that `2147483647` is, and a
digit dropped from it still compiles.

`MinNInt` and the two `NUInt` limits depend on the target, so they are the
only ones written twice.

## Contents

**Constants** &nbsp; [MaxByte](#maxbyte-constant) &middot; [MaxDouble](#maxdouble-constant) &middot; [MaxFloat](#maxfloat-constant) &middot; [MaxInt](#maxint-constant) &middot; [MaxLong](#maxlong-constant) &middot; [MaxNInt](#maxnint-constant) &middot; [MaxNUInt](#maxnuint-constant) &middot; [MaxSByte](#maxsbyte-constant) &middot; [MaxShort](#maxshort-constant) &middot; [MaxUInt](#maxuint-constant) &middot; [MaxULong](#maxulong-constant) &middot; [MaxUShort](#maxushort-constant) &middot; [MinByte](#minbyte-constant) &middot; [MinDouble](#mindouble-constant) &middot; [MinFloat](#minfloat-constant) &middot; [MinInt](#minint-constant) &middot; [MinLong](#minlong-constant) &middot; [MinNInt](#minnint-constant) &middot; [MinNUInt](#minnuint-constant) &middot; [MinSByte](#minsbyte-constant) &middot; [MinShort](#minshort-constant) &middot; [MinUInt](#minuint-constant) &middot; [MinULong](#minulong-constant) &middot; [MinUShort](#minushort-constant) &middot; [SmallestDouble](#smallestdouble-constant) &middot; [SmallestFloat](#smallestfloat-constant)

## Constants

### MaxByte *constant*

```
const byte MaxByte = 255
```

*No documentation.*

<sub>[stdlib/Limits.sl:59](../../stdlib/Limits.sl#L59)</sub>

### MaxDouble *constant*

```
const double MaxDouble = 1.7976931348623157E+308
```

*No documentation.*

<sub>[stdlib/Limits.sl:95](../../stdlib/Limits.sl#L95)</sub>

### MaxFloat *constant*

```
const float MaxFloat = 3.4028235E+38
```

The largest finite value. Anything above it is the infinity that `Math`'s
`IsFinite` reports on, not an error.

<sub>[stdlib/Limits.sl:88](../../stdlib/Limits.sl#L88)</sub>

### MaxInt *constant*

```
const int MaxInt = 2147483647
```

*No documentation.*

<sub>[stdlib/Limits.sl:46](../../stdlib/Limits.sl#L46)</sub>

### MaxLong *constant*

```
const long MaxLong = 9223372036854775807
```

*No documentation.*

<sub>[stdlib/Limits.sl:52](../../stdlib/Limits.sl#L52)</sub>

### MaxNInt *constant*

```
const nint MaxNInt = 9223372036854775807
```

*No documentation.*

<sub>[stdlib/Limits.sl:79](../../stdlib/Limits.sl#L79)</sub>

### MaxNUInt *constant*

```
const nuint MaxNUInt = 18446744073709551615
```

*No documentation.*

<sub>[stdlib/Limits.sl:81](../../stdlib/Limits.sl#L81)</sub>

### MaxSByte *constant*

```
const sbyte MaxSByte = 127
```

*No documentation.*

<sub>[stdlib/Limits.sl:40](../../stdlib/Limits.sl#L40)</sub>

### MaxShort *constant*

```
const short MaxShort = 32767
```

*No documentation.*

<sub>[stdlib/Limits.sl:43](../../stdlib/Limits.sl#L43)</sub>

### MaxUInt *constant*

```
const uint MaxUInt = 4294967295
```

*No documentation.*

<sub>[stdlib/Limits.sl:65](../../stdlib/Limits.sl#L65)</sub>

### MaxULong *constant*

```
const ulong MaxULong = 18446744073709551615
```

*No documentation.*

<sub>[stdlib/Limits.sl:68](../../stdlib/Limits.sl#L68)</sub>

### MaxUShort *constant*

```
const ushort MaxUShort = 65535
```

*No documentation.*

<sub>[stdlib/Limits.sl:62](../../stdlib/Limits.sl#L62)</sub>

### MinByte *constant*

```
const byte MinByte = 0
```

Zero, and named rather than assumed: a loop written against `MinUInt`
survives the day its type changes to a signed one.

<sub>[stdlib/Limits.sl:58](../../stdlib/Limits.sl#L58)</sub>

### MinDouble *constant*

```
const double MinDouble = -1.7976931348623157E+308
```

*No documentation.*

<sub>[stdlib/Limits.sl:96](../../stdlib/Limits.sl#L96)</sub>

### MinFloat *constant*

```
const float MinFloat = -3.4028235E+38
```

*No documentation.*

<sub>[stdlib/Limits.sl:89](../../stdlib/Limits.sl#L89)</sub>

### MinInt *constant*

```
const int MinInt = -2147483648
```

*No documentation.*

<sub>[stdlib/Limits.sl:45](../../stdlib/Limits.sl#L45)</sub>

### MinLong *constant*

```
const long MinLong = -9223372036854775808
```

The magnitude of this one is not itself a `long` -- `9223372036854775808`
alone is a `ulong`. The minus is read as part of the literal rather than as
an operator on it, which is what makes the smallest long writable at all.

<sub>[stdlib/Limits.sl:51](../../stdlib/Limits.sl#L51)</sub>

### MinNInt *constant*

```
const nint MinNInt = -9223372036854775808
```

*No documentation.*

<sub>[stdlib/Limits.sl:78](../../stdlib/Limits.sl#L78)</sub>

### MinNUInt *constant*

```
const nuint MinNUInt = 0
```

*No documentation.*

<sub>[stdlib/Limits.sl:80](../../stdlib/Limits.sl#L80)</sub>

### MinSByte *constant*

```
const sbyte MinSByte = -128
```

*No documentation.*

<sub>[stdlib/Limits.sl:39](../../stdlib/Limits.sl#L39)</sub>

### MinShort *constant*

```
const short MinShort = -32768
```

*No documentation.*

<sub>[stdlib/Limits.sl:42](../../stdlib/Limits.sl#L42)</sub>

### MinUInt *constant*

```
const uint MinUInt = 0
```

*No documentation.*

<sub>[stdlib/Limits.sl:64](../../stdlib/Limits.sl#L64)</sub>

### MinULong *constant*

```
const ulong MinULong = 0
```

*No documentation.*

<sub>[stdlib/Limits.sl:67](../../stdlib/Limits.sl#L67)</sub>

### MinUShort *constant*

```
const ushort MinUShort = 0
```

*No documentation.*

<sub>[stdlib/Limits.sl:61](../../stdlib/Limits.sl#L61)</sub>

### SmallestDouble *constant*

```
const double SmallestDouble = 2.2250738585072014E-308
```

The smallest positive double that is not denormal.

<sub>[stdlib/Limits.sl:99](../../stdlib/Limits.sl#L99)</sub>

### SmallestFloat *constant*

```
const float SmallestFloat = 1.1754944E-38
```

The smallest positive value that is not denormal. Below this a `float`
still holds numbers, with fewer bits of precision at each step down.

<sub>[stdlib/Limits.sl:93](../../stdlib/Limits.sl#L93)</sub>

