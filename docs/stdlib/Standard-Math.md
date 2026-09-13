# Standard.Math

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Arithmetic that is not an operator.

A module is a scope, so this needs no static class to live in: `Math.Sqrt(x)`
is a module-qualified call, and `import Standard.Math;` is what makes the
short name reach it.

The floating-point functions are the C library's, declared here and called
directly. That is the whole implementation -- there is no wrapper layer and
no conversion, because a Stainless `double` is a C `double`. The integer ones
are written out, since C has no such library.

## Contents

**Functions** &nbsp; [Abs](#abs) &middot; [Abs](#abs) &middot; [Abs](#abs) &middot; [Acos](#acos) &middot; [Asin](#asin) &middot; [Atan](#atan) &middot; [Atan2](#atan2) &middot; [Cbrt](#cbrt) &middot; [Ceiling](#ceiling) &middot; [Clamp](#clamp) &middot; [Clamp](#clamp) &middot; [Clamp](#clamp) &middot; [Clamp](#clamp) &middot; [Cos](#cos) &middot; [Cosh](#cosh) &middot; [Degrees](#degrees) &middot; [DivideCeiling](#divideceiling) &middot; [Exp](#exp) &middot; [Floor](#floor) &middot; [GreatestCommonDivisor](#greatestcommondivisor) &middot; [Hypot](#hypot) &middot; [IsFinite](#isfinite) &middot; [IsInfinite](#isinfinite) &middot; [IsNaN](#isnan) &middot; [IsPowerOfTwo](#ispoweroftwo) &middot; [LeadingZeros](#leadingzeros) &middot; [LeastCommonMultiple](#leastcommonmultiple) &middot; [Lerp](#lerp) &middot; [Log](#log) &middot; [Log10](#log10) &middot; [Log2](#log2) &middot; [Max](#max) &middot; [Max](#max) &middot; [Max](#max) &middot; [Max](#max) &middot; [Min](#min) &middot; [Min](#min) &middot; [Min](#min) &middot; [Min](#min) &middot; [Near](#near) &middot; [NextPowerOfTwo](#nextpoweroftwo) &middot; [PopCount](#popcount) &middot; [Pow](#pow) &middot; [Radians](#radians) &middot; [Remainder](#remainder) &middot; [Round](#round) &middot; [Sign](#sign) &middot; [Sign](#sign) &middot; [Sign](#sign) &middot; [Sin](#sin) &middot; [Sinh](#sinh) &middot; [Sqrt](#sqrt) &middot; [Tan](#tan) &middot; [Tanh](#tanh) &middot; [TrailingZeros](#trailingzeros) &middot; [Truncate](#truncate)

**Constants** &nbsp; [E](#e) &middot; [Epsilon](#epsilon) &middot; [Pi](#pi) &middot; [Tau](#tau)

## Functions

### Abs *function*

```
double Abs(double x)
```

The magnitude, sign removed. Clears the sign bit, so `Abs(-0.0)` is `0.0`
and `Abs` of either infinity is positive infinity.

<sub>[stdlib/Math.sl:170](../../stdlib/Math.sl#L170)</sub>

### Abs *function*

```
int Abs(int x)
```

The magnitude of an `int`.

The most negative `int` has no positive counterpart, so `Abs(-2147483648)`
negates to itself and stays negative. Widen to a `long` first where the
input could reach that far.

<sub>[stdlib/Math.sl:233](../../stdlib/Math.sl#L233)</sub>

### Abs *function*

```
long Abs(long x)
```

The magnitude of a `long`, with the same edge as the `int` form: the most
negative `long` answers itself.

<sub>[stdlib/Math.sl:237](../../stdlib/Math.sl#L237)</sub>

### Acos *function*

```
double Acos(double x)
```

The angle in [0, Pi] whose cosine is `x`. Outside [-1, 1] gives NaN.

<sub>[stdlib/Math.sl:123](../../stdlib/Math.sl#L123)</sub>

### Asin *function*

```
double Asin(double x)
```

The angle in [-Pi/2, Pi/2] whose sine is `x`. Outside [-1, 1] gives NaN.

<sub>[stdlib/Math.sl:120](../../stdlib/Math.sl#L120)</sub>

### Atan *function*

```
double Atan(double x)
```

The angle in (-Pi/2, Pi/2) whose tangent is `x`. Defined everywhere, and
blind to which quadrant the point was in -- `Atan2` is the one that knows.

<sub>[stdlib/Math.sl:127](../../stdlib/Math.sl#L127)</sub>

### Atan2 *function*

```
double Atan2(double y, double x)
```

The angle to (x, y) from the positive x axis, in the correct quadrant.
Note the argument order, which is the C library's: y first.

<sub>[stdlib/Math.sl:131](../../stdlib/Math.sl#L131)</sub>

### Cbrt *function*

```
double Cbrt(double x)
```

The cube root, defined for negative `x` as well -- unlike `Sqrt`, and the
reason to reach for this rather than `Pow(x, 1.0 / 3.0)`, which is NaN
there.

<sub>[stdlib/Math.sl:88](../../stdlib/Math.sl#L88)</sub>

### Ceiling *function*

```
double Ceiling(double x)
```

The smallest whole number at or above `x`. `Ceiling(-2.5)` is -2.

<sub>[stdlib/Math.sl:155](../../stdlib/Math.sl#L155)</sub>

### Clamp *function*

```
double Clamp(double x, double low, double high)
```

`x`, brought within [low, high]. Aborts nothing when the bounds are the
wrong way round; it simply returns `low`.

<sub>[stdlib/Math.sl:181](../../stdlib/Math.sl#L181)</sub>

### Clamp *function*

```
int Clamp(int x, int low, int high)
```

`x`, brought within [low, high]. Bounds the wrong way round give `low`
rather than an error, as in the `double` form.

<sub>[stdlib/Math.sl:259](../../stdlib/Math.sl#L259)</sub>

### Clamp *function*

```
long Clamp(long x, long low, long high)
```

`x`, brought within [low, high].

<sub>[stdlib/Math.sl:266](../../stdlib/Math.sl#L266)</sub>

### Clamp *function*

```
nuint Clamp(nuint x, nuint low, nuint high)
```

`x`, brought within [low, high]. Unsigned, so there is no negative side to
clamp against and `low` of zero is the natural floor.

<sub>[stdlib/Math.sl:274](../../stdlib/Math.sl#L274)</sub>

### Cos *function*

```
double Cos(double x)
```

The cosine of `x` in radians, with the same caveat as `Sin`.

<sub>[stdlib/Math.sl:113](../../stdlib/Math.sl#L113)</sub>

### Cosh *function*

```
double Cosh(double x)
```

The hyperbolic cosine, which is at least 1 and never negative. Overflows
like `Sinh`.

<sub>[stdlib/Math.sl:138](../../stdlib/Math.sl#L138)</sub>

### Degrees *function*

```
double Degrees(double radians)
```

An angle in radians, as degrees.

<sub>[stdlib/Math.sl:220](../../stdlib/Math.sl#L220)</sub>

### DivideCeiling *function*

```
nuint DivideCeiling(nuint a, nuint b)
```

`a` divided by `b`, rounded up. Written this way rather than as
`(a + b - 1) / b` so that a large `a` cannot overflow on the way.

<sub>[stdlib/Math.sl:297](../../stdlib/Math.sl#L297)</sub>

### Exp *function*

```
double Exp(double x)
```

`E` raised to `x`. Overflows to infinity above roughly 709.

<sub>[stdlib/Math.sl:95](../../stdlib/Math.sl#L95)</sub>

### Floor *function*

```
double Floor(double x)
```

The largest whole number at or below `x`. Goes away from zero for negative
`x`, unlike `Truncate`: `Floor(-2.5)` is -3.

<sub>[stdlib/Math.sl:152](../../stdlib/Math.sl#L152)</sub>

### GreatestCommonDivisor *function*

```
long GreatestCommonDivisor(long a, long b)
```

The greatest common divisor, by Euclid.

<sub>[stdlib/Math.sl:303](../../stdlib/Math.sl#L303)</sub>

### Hypot *function*

```
double Hypot(double x, double y)
```

The length of the vector (x, y), computed without overflowing on the way.

<sub>[stdlib/Math.sl:144](../../stdlib/Math.sl#L144)</sub>

### IsFinite *function*

```
bool IsFinite(double x)
```

True for an ordinary number: neither NaN nor an infinity. The check to
make on a value that came out of a division or a parse.

<sub>[stdlib/Math.sl:206](../../stdlib/Math.sl#L206)</sub>

### IsInfinite *function*

```
bool IsInfinite(double x)
```

True for either infinity. A finite number minus itself is zero; an infinity
minus itself is NaN, which is what separates the two.

<sub>[stdlib/Math.sl:199](../../stdlib/Math.sl#L199)</sub>

### IsNaN *function*

```
bool IsNaN(double x)
```

True when `x` is Not a Number, which is the one value not equal to itself.

<sub>[stdlib/Math.sl:195](../../stdlib/Math.sl#L195)</sub>

### IsPowerOfTwo *function*

```
bool IsPowerOfTwo(ulong value)
```

True when exactly one bit is set. Zero is not a power of two and answers
false, which is the case a bare `value & (value - 1)` test gets wrong.

<sub>[stdlib/Math.sl:363](../../stdlib/Math.sl#L363)</sub>

### LeadingZeros *function*

```
int LeadingZeros(ulong value)
```

How many zero bits sit above the highest set bit. 64 for zero.

<sub>[stdlib/Math.sl:338](../../stdlib/Math.sl#L338)</sub>

### LeastCommonMultiple *function*

```
long LeastCommonMultiple(long a, long b)
```

The least common multiple. Zero when either argument is zero.

Divides before multiplying, which keeps the intermediate as small as it can
be; two large arguments can still overflow, and nothing here detects it.

<sub>[stdlib/Math.sl:319](../../stdlib/Math.sl#L319)</sub>

### Lerp *function*

```
double Lerp(double from, double to, double at)
```

Straight-line interpolation: `at` of 0 gives `from`, 1 gives `to`.

<sub>[stdlib/Math.sl:215](../../stdlib/Math.sl#L215)</sub>

### Log *function*

```
double Log(double x)
```

The natural logarithm. Zero gives negative infinity and a negative `x`
gives NaN.

<sub>[stdlib/Math.sl:99](../../stdlib/Math.sl#L99)</sub>

### Log10 *function*

```
double Log10(double x)
```

The base-ten logarithm, with the same edges as `Log`.

<sub>[stdlib/Math.sl:106](../../stdlib/Math.sl#L106)</sub>

### Log2 *function*

```
double Log2(double x)
```

The base-two logarithm, with the same edges as `Log`. More accurate than
`Log(x) / Log(2.0)`, which is the reason it is here.

<sub>[stdlib/Math.sl:103](../../stdlib/Math.sl#L103)</sub>

### Max *function*

```
double Max(double a, double b)
```

The larger of the two, with the same NaN behaviour as `Min`.

<sub>[stdlib/Math.sl:177](../../stdlib/Math.sl#L177)</sub>

### Max *function*

```
int Max(int a, int b)
```

The larger of two `int`s.

<sub>[stdlib/Math.sl:243](../../stdlib/Math.sl#L243)</sub>

### Max *function*

```
long Max(long a, long b)
```

The larger of two `long`s.

<sub>[stdlib/Math.sl:249](../../stdlib/Math.sl#L249)</sub>

### Max *function*

```
nuint Max(nuint a, nuint b)
```

The larger of two `nuint`s.

<sub>[stdlib/Math.sl:255](../../stdlib/Math.sl#L255)</sub>

### Min *function*

```
double Min(double a, double b)
```

The smaller of the two. A NaN argument answers `b`, since every comparison
against NaN is false -- check with `IsNaN` if that matters.

<sub>[stdlib/Math.sl:174](../../stdlib/Math.sl#L174)</sub>

### Min *function*

```
int Min(int a, int b)
```

The smaller of two `int`s.

<sub>[stdlib/Math.sl:240](../../stdlib/Math.sl#L240)</sub>

### Min *function*

```
long Min(long a, long b)
```

The smaller of two `long`s.

<sub>[stdlib/Math.sl:246](../../stdlib/Math.sl#L246)</sub>

### Min *function*

```
nuint Min(nuint a, nuint b)
```

The smaller of two `nuint`s.

<sub>[stdlib/Math.sl:252](../../stdlib/Math.sl#L252)</sub>

### Near *function*

```
bool Near(double a, double b, double tolerance)
```

True when the two are within `tolerance` of each other. Comparing floats
with `==` is almost always a mistake, and this is what to write instead.

<sub>[stdlib/Math.sl:210](../../stdlib/Math.sl#L210)</sub>

### NextPowerOfTwo *function*

```
ulong NextPowerOfTwo(ulong value)
```

The smallest power of two that is at least `value`. Zero and one both give
one; a value above 2^63 has no answer and gives zero.

<sub>[stdlib/Math.sl:369](../../stdlib/Math.sl#L369)</sub>

### PopCount *function*

```
int PopCount(ulong value)
```

How many bits are set. Kernighan's loop: each step clears the lowest set
bit, so it runs once per bit that is actually there.

<sub>[stdlib/Math.sl:328](../../stdlib/Math.sl#L328)</sub>

### Pow *function*

```
double Pow(double x, double y)
```

`x` raised to `y`. A negative `x` with a fractional `y` gives NaN; anything
raised to zero, `0.0` included, gives 1.

<sub>[stdlib/Math.sl:92](../../stdlib/Math.sl#L92)</sub>

### Radians *function*

```
double Radians(double degrees)
```

An angle in degrees, as radians. Every trigonometric function here takes
radians, so this is what goes between a human's number and `Sin`.

<sub>[stdlib/Math.sl:224](../../stdlib/Math.sl#L224)</sub>

### Remainder *function*

```
double Remainder(double x, double y)
```

The remainder of x/y, with the sign of x. This is C's fmod, not a modulus:
`Remainder(-7.0, 3.0)` is -1.0, not 2.0.

<sub>[stdlib/Math.sl:166](../../stdlib/Math.sl#L166)</sub>

### Round *function*

```
double Round(double x)
```

To the nearest integer, halves away from zero -- C's rule, not the
banker's rounding C# uses by default.

<sub>[stdlib/Math.sl:159](../../stdlib/Math.sl#L159)</sub>

### Sign *function*

```
int Sign(double x)
```

-1, 0 or 1. NaN has no sign, and returns 0.

<sub>[stdlib/Math.sl:188](../../stdlib/Math.sl#L188)</sub>

### Sign *function*

```
int Sign(int x)
```

-1, 0 or 1 for a negative, zero or positive `int`.

<sub>[stdlib/Math.sl:281](../../stdlib/Math.sl#L281)</sub>

### Sign *function*

```
int Sign(long x)
```

-1, 0 or 1 for a negative, zero or positive `long`. An `int` either way,
since three values need no more.

<sub>[stdlib/Math.sl:289](../../stdlib/Math.sl#L289)</sub>

### Sin *function*

```
double Sin(double x)
```

The sine of `x` in radians. Use `Radians` on an angle in degrees; a very
large `x` loses accuracy, since the reduction is done in the same double.

<sub>[stdlib/Math.sl:110](../../stdlib/Math.sl#L110)</sub>

### Sinh *function*

```
double Sinh(double x)
```

The hyperbolic sine. Overflows to an infinity past roughly 710.

<sub>[stdlib/Math.sl:134](../../stdlib/Math.sl#L134)</sub>

### Sqrt *function*

```
double Sqrt(double x)
```

The square root. Negative `x` gives NaN.

<sub>[stdlib/Math.sl:83](../../stdlib/Math.sl#L83)</sub>

### Tan *function*

```
double Tan(double x)
```

The tangent of `x` in radians. Near an odd multiple of Pi/2 the answer is
enormous rather than infinite, because no double lands exactly there.

<sub>[stdlib/Math.sl:117](../../stdlib/Math.sl#L117)</sub>

### Tanh *function*

```
double Tanh(double x)
```

The hyperbolic tangent, which stays within (-1, 1) and cannot overflow.

<sub>[stdlib/Math.sl:141](../../stdlib/Math.sl#L141)</sub>

### TrailingZeros *function*

```
int TrailingZeros(ulong value)
```

How many zero bits sit below the lowest set bit. 64 for zero.

<sub>[stdlib/Math.sl:350](../../stdlib/Math.sl#L350)</sub>

### Truncate *function*

```
double Truncate(double x)
```

Towards zero, dropping the fractional part.

<sub>[stdlib/Math.sl:162](../../stdlib/Math.sl#L162)</sub>

## Constants

### E *constant*

```
const double E = 2.718281828459045
```

The base of the natural logarithm.

<sub>[stdlib/Math.sl:70](../../stdlib/Math.sl#L70)</sub>

### Epsilon *constant*

```
const double Epsilon = 2.2204E-16
```

The smallest step between 1.0 and the next representable double.

<sub>[stdlib/Math.sl:73](../../stdlib/Math.sl#L73)</sub>

### Pi *constant*

```
const double Pi = 3.141592653589793
```

The ratio of a circle's circumference to its diameter.

<sub>[stdlib/Math.sl:64](../../stdlib/Math.sl#L64)</sub>

### Tau *constant*

```
const double Tau = 6.283185307179586
```

Two Pi: a whole turn, which is what most angle arithmetic actually wants.

<sub>[stdlib/Math.sl:67](../../stdlib/Math.sl#L67)</sub>

