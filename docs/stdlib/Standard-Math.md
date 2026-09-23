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

**Functions** &nbsp; [Abs](#abs-function) &middot; [Abs](#abs-function) &middot; [Abs](#abs-function) &middot; [Acos](#acos-function) &middot; [Asin](#asin-function) &middot; [Atan](#atan-function) &middot; [Atan2](#atan2-function) &middot; [Cbrt](#cbrt-function) &middot; [Ceiling](#ceiling-function) &middot; [Clamp](#clamp-function) &middot; [Clamp](#clamp-function) &middot; [Clamp](#clamp-function) &middot; [Clamp](#clamp-function) &middot; [Cos](#cos-function) &middot; [Cosh](#cosh-function) &middot; [DegreesToRadians](#degreestoradians-function) &middot; [DivideCeiling](#divideceiling-function) &middot; [Exp](#exp-function) &middot; [Floor](#floor-function) &middot; [GreatestCommonDivisor](#greatestcommondivisor-function) &middot; [Hypot](#hypot-function) &middot; [IsFinite](#isfinite-function) &middot; [IsInfinity](#isinfinity-function) &middot; [IsNaN](#isnan-function) &middot; [IsNear](#isnear-function) &middot; [LeastCommonMultiple](#leastcommonmultiple-function) &middot; [Lerp](#lerp-function) &middot; [Log](#log-function) &middot; [Log10](#log10-function) &middot; [Log2](#log2-function) &middot; [Max](#max-function) &middot; [Max](#max-function) &middot; [Max](#max-function) &middot; [Max](#max-function) &middot; [Min](#min-function) &middot; [Min](#min-function) &middot; [Min](#min-function) &middot; [Min](#min-function) &middot; [Pow](#pow-function) &middot; [RadiansToDegrees](#radianstodegrees-function) &middot; [Remainder](#remainder-function) &middot; [Round](#round-function) &middot; [Sign](#sign-function) &middot; [Sign](#sign-function) &middot; [Sign](#sign-function) &middot; [Sin](#sin-function) &middot; [Sinh](#sinh-function) &middot; [Sqrt](#sqrt-function) &middot; [Tan](#tan-function) &middot; [Tanh](#tanh-function) &middot; [Truncate](#truncate-function)

**Constants** &nbsp; [E](#e-constant) &middot; [MachineEpsilon](#machineepsilon-constant) &middot; [Pi](#pi-constant) &middot; [Tau](#tau-constant)

## Functions

### Abs *function*

```
double Abs(double x)
```

The magnitude, sign removed. Clears the sign bit, so `Abs(-0.0)` is `0.0`
and `Abs` of either infinity is positive infinity.

<sub>[stdlib/Math.sl:177](../../stdlib/Math.sl#L177)</sub>

### Abs *function*

```
int Abs(int x)
```

The magnitude of an `int`.

The most negative `int` has no positive counterpart, so `Abs(-2147483648)`
negates to itself and stays negative. Widen to a `long` first where the
input could reach that far.

<sub>[stdlib/Math.sl:254](../../stdlib/Math.sl#L254)</sub>

### Abs *function*

```
long Abs(long x)
```

The magnitude of a `long`, with the same edge as the `int` form: the most
negative `long` answers itself.

<sub>[stdlib/Math.sl:258](../../stdlib/Math.sl#L258)</sub>

### Acos *function*

```
double Acos(double x)
```

The angle in [0, Pi] whose cosine is `x`. Outside [-1, 1] gives NaN.

<sub>[stdlib/Math.sl:124](../../stdlib/Math.sl#L124)</sub>

### Asin *function*

```
double Asin(double x)
```

The angle in [-Pi/2, Pi/2] whose sine is `x`. Outside [-1, 1] gives NaN.

<sub>[stdlib/Math.sl:121](../../stdlib/Math.sl#L121)</sub>

### Atan *function*

```
double Atan(double x)
```

The angle in (-Pi/2, Pi/2) whose tangent is `x`. Defined everywhere, and
blind to which quadrant the point was in -- `Atan2` is the one that knows.

**See also** &nbsp; [Math.Atan2](#atan2-function)

<sub>[stdlib/Math.sl:130](../../stdlib/Math.sl#L130)</sub>

### Atan2 *function*

```
double Atan2(double y, double x)
```

The angle to (x, y) from the positive x axis, in the correct quadrant.
Note the argument order, which is the C library's: y first.

**Parameters**

- `y` — the point's y coordinate, which comes first
- `x` — the point's x coordinate

**See also** &nbsp; [Math.Atan](#atan-function)

<sub>[stdlib/Math.sl:138](../../stdlib/Math.sl#L138)</sub>

### Cbrt *function*

```
double Cbrt(double x)
```

The cube root, defined for negative `x` as well -- unlike `Sqrt`, and the
reason to reach for this rather than `Pow(x, 1.0 / 3.0)`, which is NaN
there.

<sub>[stdlib/Math.sl:89](../../stdlib/Math.sl#L89)</sub>

### Ceiling *function*

```
double Ceiling(double x)
```

The smallest whole number at or above `x`. `Ceiling(-2.5)` is -2.

<sub>[stdlib/Math.sl:162](../../stdlib/Math.sl#L162)</sub>

### Clamp *function*

```
double Clamp(double x, double low, double high)
```

`x`, brought within [low, high]. Aborts nothing when the bounds are the
wrong way round; it simply returns `low`.

<sub>[stdlib/Math.sl:188](../../stdlib/Math.sl#L188)</sub>

### Clamp *function*

```
int Clamp(int x, int low, int high)
```

`x`, brought within [low, high]. Bounds the wrong way round give `low`
rather than an error, as in the `double` form.

<sub>[stdlib/Math.sl:280](../../stdlib/Math.sl#L280)</sub>

### Clamp *function*

```
long Clamp(long x, long low, long high)
```

`x`, brought within [low, high]. Bounds the wrong way round give `low`.

<sub>[stdlib/Math.sl:290](../../stdlib/Math.sl#L290)</sub>

### Clamp *function*

```
nuint Clamp(nuint x, nuint low, nuint high)
```

`x`, brought within [low, high]. Unsigned, so there is no negative side to
clamp against and `low` of zero is the natural floor. Bounds the wrong way
round give `low`.

<sub>[stdlib/Math.sl:302](../../stdlib/Math.sl#L302)</sub>

### Cos *function*

```
double Cos(double x)
```

The cosine of `x` in radians, with the same caveat as `Sin`.

<sub>[stdlib/Math.sl:114](../../stdlib/Math.sl#L114)</sub>

### Cosh *function*

```
double Cosh(double x)
```

The hyperbolic cosine, which is at least 1 and never negative. Overflows
like `Sinh`.

<sub>[stdlib/Math.sl:145](../../stdlib/Math.sl#L145)</sub>

### DegreesToRadians *function*

```
double DegreesToRadians(double degrees)
```

An angle in degrees, as radians. Every trigonometric function here takes
radians, so this is what goes between a human's number and `Sin`.

**See also** &nbsp; [Math.RadiansToDegrees](#radianstodegrees-function)

<sub>[stdlib/Math.sl:245](../../stdlib/Math.sl#L245)</sub>

### DivideCeiling *function*

```
nuint DivideCeiling(nuint a, nuint b)
```

`a` divided by `b`, rounded up. Written this way rather than as
`(a + b - 1) / b` so that a large `a` cannot overflow on the way.

<sub>[stdlib/Math.sl:334](../../stdlib/Math.sl#L334)</sub>

### Exp *function*

```
double Exp(double x)
```

`E` raised to `x`. Overflows to infinity above roughly 709.

<sub>[stdlib/Math.sl:96](../../stdlib/Math.sl#L96)</sub>

### Floor *function*

```
double Floor(double x)
```

The largest whole number at or below `x`. Goes away from zero for negative
`x`, unlike `Truncate`: `Floor(-2.5)` is -3.

<sub>[stdlib/Math.sl:159](../../stdlib/Math.sl#L159)</sub>

### GreatestCommonDivisor *function*

```
long GreatestCommonDivisor(long a, long b)
```

The greatest common divisor, by Euclid. Never negative, but for one case.

Zero with zero answers zero. The answer is 2^63 when both arguments are the
most negative `long`, or one is and the other is zero; no `long` holds that,
so it answers `MinLong`, whose magnitude it is, as `Abs` does.

**See also** &nbsp; [Math.LeastCommonMultiple](#leastcommonmultiple-function)

<sub>[stdlib/Math.sl:348](../../stdlib/Math.sl#L348)</sub>

### Hypot *function*

```
double Hypot(double x, double y)
```

The length of the vector (x, y), computed without overflowing on the way.

<sub>[stdlib/Math.sl:151](../../stdlib/Math.sl#L151)</sub>

### IsFinite *function*

```
bool IsFinite(double x)
```

True for an ordinary number: neither NaN nor an infinity. The check to
make on a value that came out of a division or a parse.

<sub>[stdlib/Math.sl:221](../../stdlib/Math.sl#L221)</sub>

### IsInfinity *function*

```
bool IsInfinity(double x)
```

True for either infinity. A finite number minus itself is zero; an infinity
minus itself is NaN, which is what separates the two.

<sub>[stdlib/Math.sl:212](../../stdlib/Math.sl#L212)</sub>

### IsNaN *function*

```
bool IsNaN(double x)
```

True when `x` is Not a Number, which is the one value not equal to itself.

<sub>[stdlib/Math.sl:208](../../stdlib/Math.sl#L208)</sub>

### IsNear *function*

```
bool IsNear(double a, double b, double tolerance)
```

True when the two are within `tolerance` of each other. Comparing floats
with `==` is almost always a mistake, and this is what to write instead.

<sub>[stdlib/Math.sl:225](../../stdlib/Math.sl#L225)</sub>

### LeastCommonMultiple *function*

```
long LeastCommonMultiple(long a, long b)
```

The least common multiple. Zero when either argument is zero.

Divides before multiplying, which keeps the intermediate as small as it can
be; two large arguments can still overflow, and nothing here detects it.

**See also** &nbsp; [Math.GreatestCommonDivisor](#greatestcommondivisor-function)

<sub>[stdlib/Math.sl:371](../../stdlib/Math.sl#L371)</sub>

### Lerp *function*

```
double Lerp(double from, double to, double at)
```

Straight-line interpolation: `at` of 0 gives `from`, 1 gives `to`.

<sub>[stdlib/Math.sl:231](../../stdlib/Math.sl#L231)</sub>

### Log *function*

```
double Log(double x)
```

The natural logarithm. Zero gives negative infinity and a negative `x`
gives NaN.

<sub>[stdlib/Math.sl:100](../../stdlib/Math.sl#L100)</sub>

### Log10 *function*

```
double Log10(double x)
```

The base-ten logarithm, with the same edges as `Log`.

<sub>[stdlib/Math.sl:107](../../stdlib/Math.sl#L107)</sub>

### Log2 *function*

```
double Log2(double x)
```

The base-two logarithm, with the same edges as `Log`. More accurate than
`Log(x) / Log(2.0)`, which is the reason it is here.

<sub>[stdlib/Math.sl:104](../../stdlib/Math.sl#L104)</sub>

### Max *function*

```
double Max(double a, double b)
```

The larger of the two, with the same NaN behaviour as `Min`.

<sub>[stdlib/Math.sl:184](../../stdlib/Math.sl#L184)</sub>

### Max *function*

```
int Max(int a, int b)
```

The larger of two `int`s.

<sub>[stdlib/Math.sl:264](../../stdlib/Math.sl#L264)</sub>

### Max *function*

```
long Max(long a, long b)
```

The larger of two `long`s.

<sub>[stdlib/Math.sl:270](../../stdlib/Math.sl#L270)</sub>

### Max *function*

```
nuint Max(nuint a, nuint b)
```

The larger of two `nuint`s.

<sub>[stdlib/Math.sl:276](../../stdlib/Math.sl#L276)</sub>

### Min *function*

```
double Min(double a, double b)
```

The smaller of the two. A NaN argument answers `b`, since every comparison
against NaN is false -- check with `IsNaN` if that matters.

<sub>[stdlib/Math.sl:181](../../stdlib/Math.sl#L181)</sub>

### Min *function*

```
int Min(int a, int b)
```

The smaller of two `int`s.

<sub>[stdlib/Math.sl:261](../../stdlib/Math.sl#L261)</sub>

### Min *function*

```
long Min(long a, long b)
```

The smaller of two `long`s.

<sub>[stdlib/Math.sl:267](../../stdlib/Math.sl#L267)</sub>

### Min *function*

```
nuint Min(nuint a, nuint b)
```

The smaller of two `nuint`s.

<sub>[stdlib/Math.sl:273](../../stdlib/Math.sl#L273)</sub>

### Pow *function*

```
double Pow(double x, double y)
```

`x` raised to `y`. A negative `x` with a fractional `y` gives NaN; anything
raised to zero, `0.0` included, gives 1.

<sub>[stdlib/Math.sl:93](../../stdlib/Math.sl#L93)</sub>

### RadiansToDegrees *function*

```
double RadiansToDegrees(double radians)
```

An angle in radians, as degrees.

**See also** &nbsp; [Math.DegreesToRadians](#degreestoradians-function)

<sub>[stdlib/Math.sl:239](../../stdlib/Math.sl#L239)</sub>

### Remainder *function*

```
double Remainder(double x, double y)
```

The remainder of x/y, with the sign of x. This is C's fmod, not a modulus:
`Remainder(-7.0, 3.0)` is -1.0, not 2.0.

<sub>[stdlib/Math.sl:173](../../stdlib/Math.sl#L173)</sub>

### Round *function*

```
double Round(double x)
```

To the nearest integer, halves away from zero -- C's rule, not the
banker's rounding C# uses by default.

<sub>[stdlib/Math.sl:166](../../stdlib/Math.sl#L166)</sub>

### Sign *function*

```
int Sign(double x)
```

-1, 0 or 1. NaN has no sign, and returns 0.

<sub>[stdlib/Math.sl:198](../../stdlib/Math.sl#L198)</sub>

### Sign *function*

```
int Sign(int x)
```

-1, 0 or 1 for a negative, zero or positive `int`.

<sub>[stdlib/Math.sl:312](../../stdlib/Math.sl#L312)</sub>

### Sign *function*

```
int Sign(long x)
```

-1, 0 or 1 for a negative, zero or positive `long`. An `int` either way,
since three values need no more.

<sub>[stdlib/Math.sl:323](../../stdlib/Math.sl#L323)</sub>

### Sin *function*

```
double Sin(double x)
```

The sine of `x` in radians. Use `DegreesToRadians` on an angle in degrees; a very
large `x` loses accuracy, since the reduction is done in the same double.

<sub>[stdlib/Math.sl:111](../../stdlib/Math.sl#L111)</sub>

### Sinh *function*

```
double Sinh(double x)
```

The hyperbolic sine. Overflows to an infinity past roughly 710.

<sub>[stdlib/Math.sl:141](../../stdlib/Math.sl#L141)</sub>

### Sqrt *function*

```
double Sqrt(double x)
```

The square root. Negative `x` gives NaN.

<sub>[stdlib/Math.sl:84](../../stdlib/Math.sl#L84)</sub>

### Tan *function*

```
double Tan(double x)
```

The tangent of `x` in radians. Near an odd multiple of Pi/2 the answer is
enormous rather than infinite, because no double lands exactly there.

<sub>[stdlib/Math.sl:118](../../stdlib/Math.sl#L118)</sub>

### Tanh *function*

```
double Tanh(double x)
```

The hyperbolic tangent, which stays within (-1, 1) and cannot overflow.

<sub>[stdlib/Math.sl:148](../../stdlib/Math.sl#L148)</sub>

### Truncate *function*

```
double Truncate(double x)
```

Towards zero, dropping the fractional part.

<sub>[stdlib/Math.sl:169](../../stdlib/Math.sl#L169)</sub>

## Constants

### E *constant*

```
const double E = 2.718281828459045
```

The base of the natural logarithm.

<sub>[stdlib/Math.sl:71](../../stdlib/Math.sl#L71)</sub>

### MachineEpsilon *constant*

```
const double MachineEpsilon = 2.220446049250313E-16
```

The smallest step between 1.0 and the next representable double.

<sub>[stdlib/Math.sl:74](../../stdlib/Math.sl#L74)</sub>

### Pi *constant*

```
const double Pi = 3.141592653589793
```

The ratio of a circle's circumference to its diameter.

<sub>[stdlib/Math.sl:65](../../stdlib/Math.sl#L65)</sub>

### Tau *constant*

```
const double Tau = 6.283185307179586
```

Two Pi: a whole turn, which is what most angle arithmetic actually wants.

<sub>[stdlib/Math.sl:68](../../stdlib/Math.sl#L68)</sub>

