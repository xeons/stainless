// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This file is part of the Stainless runtime library. It is free
// software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any
// later version.
//
// It is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// As an additional permission under section 7 of that License, compiling
// a program with Stainless does not by itself place that program under
// the GNU General Public License. See LICENSE.RUNTIME.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

/// Arithmetic that is not an operator.
///
/// A module is a scope, so this needs no static class to live in: `Math.Sqrt(x)`
/// is a module-qualified call, and `import Standard.Math;` is what makes the
/// short name reach it.
///
/// The floating-point functions are the C library's, declared here and called
/// directly. That is the whole implementation -- there is no wrapper layer and
/// no conversion, because a Stainless `double` is a C `double`. The integer ones
/// are written out, since C has no such library.
module Standard.Math;

extern "C"
{
    double sqrt(double x);
    double cbrt(double x);
    double pow(double x, double y);
    double exp(double x);
    double log(double x);
    double log2(double x);
    double log10(double x);
    double sin(double x);
    double cos(double x);
    double tan(double x);
    double asin(double x);
    double acos(double x);
    double atan(double x);
    double atan2(double y, double x);
    double sinh(double x);
    double cosh(double x);
    double tanh(double x);
    double floor(double x);
    double ceil(double x);
    double round(double x);
    double trunc(double x);
    double fmod(double x, double y);
    double hypot(double x, double y);
    double fabs(double x);
}

// ------------------------------------------------------------- constants

/// The ratio of a circle's circumference to its diameter.
public const double Pi = 3.14159265358979311600;

/// Two Pi: a whole turn, which is what most angle arithmetic actually wants.
public const double Tau = 6.28318530717958623200;

/// The base of the natural logarithm.
public const double E = 2.71828182845904509080;

/// The smallest step between 1.0 and the next representable double.
public const double Epsilon = 2.220446049250313080847263336181640625e-16;

// ------------------------------------------------------ floating point

// Nothing here signals an error: a value outside a function's domain answers
// NaN and a value past the range answers an infinity, because that is what the
// hardware does and there is no exception for it to raise instead. A caller
// that cares checks with `IsNaN` or `IsFinite` rather than checking first.

/// The square root. Negative `x` gives NaN.
public double Sqrt(double x) => sqrt(x);

/// The cube root, defined for negative `x` as well -- unlike `Sqrt`, and the
/// reason to reach for this rather than `Pow(x, 1.0 / 3.0)`, which is NaN
/// there.
public double Cbrt(double x) => cbrt(x);

/// `x` raised to `y`. A negative `x` with a fractional `y` gives NaN; anything
/// raised to zero, `0.0` included, gives 1.
public double Pow(double x, double y) => pow(x, y);

/// `E` raised to `x`. Overflows to infinity above roughly 709.
public double Exp(double x) => exp(x);

/// The natural logarithm. Zero gives negative infinity and a negative `x`
/// gives NaN.
public double Log(double x) => log(x);

/// The base-two logarithm, with the same edges as `Log`. More accurate than
/// `Log(x) / Log(2.0)`, which is the reason it is here.
public double Log2(double x) => log2(x);

/// The base-ten logarithm, with the same edges as `Log`.
public double Log10(double x) => log10(x);

/// The sine of `x` in radians. Use `ToRadians` on an angle in degrees; a very
/// large `x` loses accuracy, since the reduction is done in the same double.
public double Sin(double x) => sin(x);

/// The cosine of `x` in radians, with the same caveat as `Sin`.
public double Cos(double x) => cos(x);

/// The tangent of `x` in radians. Near an odd multiple of Pi/2 the answer is
/// enormous rather than infinite, because no double lands exactly there.
public double Tan(double x) => tan(x);

/// The angle in [-Pi/2, Pi/2] whose sine is `x`. Outside [-1, 1] gives NaN.
public double Asin(double x) => asin(x);

/// The angle in [0, Pi] whose cosine is `x`. Outside [-1, 1] gives NaN.
public double Acos(double x) => acos(x);

/// The angle in (-Pi/2, Pi/2) whose tangent is `x`. Defined everywhere, and
/// blind to which quadrant the point was in -- `Atan2` is the one that knows.
public double Atan(double x) => atan(x);

/// The angle to (x, y) from the positive x axis, in the correct quadrant.
/// Note the argument order, which is the C library's: y first.
public double Atan2(double y, double x) => atan2(y, x);

/// The hyperbolic sine. Overflows to an infinity past roughly 710.
public double Sinh(double x) => sinh(x);

/// The hyperbolic cosine, which is at least 1 and never negative. Overflows
/// like `Sinh`.
public double Cosh(double x) => cosh(x);

/// The hyperbolic tangent, which stays within (-1, 1) and cannot overflow.
public double Tanh(double x) => tanh(x);

/// The length of the vector (x, y), computed without overflowing on the way.
public double Hypot(double x, double y) => hypot(x, y);

// The rounding functions answer a `double`, not an integer: the result may be
// larger than any `long` holds, and narrowing is the caller's to do once it
// knows the range.

/// The largest whole number at or below `x`. Goes away from zero for negative
/// `x`, unlike `Truncate`: `Floor(-2.5)` is -3.
public double Floor(double x) => floor(x);

/// The smallest whole number at or above `x`. `Ceiling(-2.5)` is -2.
public double Ceiling(double x) => ceil(x);

/// To the nearest integer, halves away from zero -- C's rule, not the
/// banker's rounding C# uses by default.
public double Round(double x) => round(x);

/// Towards zero, dropping the fractional part.
public double Truncate(double x) => trunc(x);

/// The remainder of x/y, with the sign of x. This is C's fmod, not a modulus:
/// `Remainder(-7.0, 3.0)` is -1.0, not 2.0.
public double Remainder(double x, double y) => fmod(x, y);

/// The magnitude, sign removed. Clears the sign bit, so `Abs(-0.0)` is `0.0`
/// and `Abs` of either infinity is positive infinity.
public double Abs(double x) => fabs(x);

/// The smaller of the two. A NaN argument answers `b`, since every comparison
/// against NaN is false -- check with `IsNaN` if that matters.
public double Min(double a, double b) => a < b ? a : b;

/// The larger of the two, with the same NaN behaviour as `Min`.
public double Max(double a, double b) => a > b ? a : b;

/// `x`, brought within [low, high]. Aborts nothing when the bounds are the
/// wrong way round; it simply returns `low`.
public double Clamp(double x, double low, double high)
{
    if (x < low || low > high)
        return low;
    if (x > high)
        return high;
    return x;
}

/// -1, 0 or 1. NaN has no sign, and returns 0.
public int Sign(double x)
{
    if (x < 0.0)
        return -1;
    if (x > 0.0)
        return 1;
    return 0;
}

/// True when `x` is Not a Number, which is the one value not equal to itself.
public bool IsNaN(double x) => x != x;

/// True for either infinity. A finite number minus itself is zero; an infinity
/// minus itself is NaN, which is what separates the two.
public bool IsInfinite(double x)
{
    if (IsNaN(x))
        return false;
    return x - x != 0.0;
}

/// True for an ordinary number: neither NaN nor an infinity. The check to
/// make on a value that came out of a division or a parse.
public bool IsFinite(double x) => !IsNaN(x) && !IsInfinite(x);

/// True when the two are within `tolerance` of each other. Comparing floats
/// with `==` is almost always a mistake, and this is what to write instead.
public bool IsNear(double a, double b, double tolerance)
{
    return Abs(a - b) <= tolerance;
}

/// Straight-line interpolation: `at` of 0 gives `from`, 1 gives `to`.
public double Lerp(double from, double to, double at)
{
    return from + (to - from) * at;
}

/// An angle in radians, as degrees.
public double ToDegrees(double radians) => radians * 180.0 / Pi;

/// An angle in degrees, as radians. Every trigonometric function here takes
/// radians, so this is what goes between a human's number and `Sin`.
public double ToRadians(double degrees) => degrees * Pi / 180.0;

// ---------------------------------------------------------------- integers

/// The magnitude of an `int`.
///
/// The most negative `int` has no positive counterpart, so `Abs(-2147483648)`
/// negates to itself and stays negative. Widen to a `long` first where the
/// input could reach that far.
public int Abs(int x) => x < 0 ? -x : x;

/// The magnitude of a `long`, with the same edge as the `int` form: the most
/// negative `long` answers itself.
public long Abs(long x) => x < 0 ? -x : x;

/// The smaller of two `int`s.
public int Min(int a, int b) => a < b ? a : b;

/// The larger of two `int`s.
public int Max(int a, int b) => a > b ? a : b;

/// The smaller of two `long`s.
public long Min(long a, long b) => a < b ? a : b;

/// The larger of two `long`s.
public long Max(long a, long b) => a > b ? a : b;

/// The smaller of two `nuint`s.
public nuint Min(nuint a, nuint b) => a < b ? a : b;

/// The larger of two `nuint`s.
public nuint Max(nuint a, nuint b) => a > b ? a : b;

/// `x`, brought within [low, high]. Bounds the wrong way round give `low`
/// rather than an error, as in the `double` form.
public int Clamp(int x, int low, int high)
{
    if (x < low || low > high)
        return low;
    if (x > high)
        return high;
    return x;
}

/// `x`, brought within [low, high]. Bounds the wrong way round give `low`.
public long Clamp(long x, long low, long high)
{
    if (x < low || low > high)
        return low;
    if (x > high)
        return high;
    return x;
}

/// `x`, brought within [low, high]. Unsigned, so there is no negative side to
/// clamp against and `low` of zero is the natural floor. Bounds the wrong way
/// round give `low`.
public nuint Clamp(nuint x, nuint low, nuint high)
{
    if (x < low || low > high)
        return low;
    if (x > high)
        return high;
    return x;
}

/// -1, 0 or 1 for a negative, zero or positive `int`.
public int Sign(int x)
{
    if (x < 0)
        return -1;
    if (x > 0)
        return 1;
    return 0;
}

/// -1, 0 or 1 for a negative, zero or positive `long`. An `int` either way,
/// since three values need no more.
public int Sign(long x)
{
    if (x < 0)
        return -1;
    if (x > 0)
        return 1;
    return 0;
}

/// `a` divided by `b`, rounded up. Written this way rather than as
/// `(a + b - 1) / b` so that a large `a` cannot overflow on the way.
public nuint DivideCeiling(nuint a, nuint b)
{
    if (a == 0)
        return 0;
    return (a - 1) / b + 1;
}

/// The greatest common divisor, by Euclid. Never negative, but for one case.
///
/// Zero with zero answers zero. The answer is 2^63 when both arguments are the
/// most negative `long`, or one is and the other is zero; no `long` holds that,
/// so it answers `MinLong`, whose magnitude it is, as `Abs` does.
public long GreatestCommonDivisor(long a, long b)
{
    ulong left = GetMagnitude(a);
    ulong right = GetMagnitude(b);

    while (right != 0)
    {
        ulong next = left % right;
        left = right;
        right = next;
    }
    return (long)left;
}

/// The magnitude of a `long` as a `ulong`, which holds every one.
ulong GetMagnitude(long x) => x < 0 ? (ulong)0 - (ulong)x : (ulong)x;

/// The least common multiple. Zero when either argument is zero.
///
/// Divides before multiplying, which keeps the intermediate as small as it can
/// be; two large arguments can still overflow, and nothing here detects it.
public long LeastCommonMultiple(long a, long b)
{
    if (a == 0 || b == 0)
        return 0;
    return Abs(a / GreatestCommonDivisor(a, b) * b);
}

// -------------------------------------------------------------------- bits

/// How many bits are set. Kernighan's loop: each step clears the lowest set
/// bit, so it runs once per bit that is actually there.
public int PopCount(ulong value)
{
    int count = 0;
    while (value != 0)
    {
        value = value & (value - 1);
        count++;
    }
    return count;
}

/// How many zero bits sit above the highest set bit. 64 for zero.
public int LeadingZeroCount(ulong value)
{
    if (value == 0)
        return 64;

    int count = 0;
    while ((value & 0x8000000000000000) == 0)
    {
        value = value << 1;
        count++;
    }
    return count;
}

/// How many zero bits sit below the lowest set bit. 64 for zero.
public int TrailingZeroCount(ulong value)
{
    if (value == 0)
        return 64;

    int count = 0;
    while ((value & 1) == 0)
    {
        value = value >> 1;
        count++;
    }
    return count;
}

/// True when exactly one bit is set. Zero is not a power of two and answers
/// false, which is the case a bare `value & (value - 1)` test gets wrong.
public bool IsPowerOfTwo(ulong value)
{
    return value != 0 && (value & (value - 1)) == 0;
}

/// The smallest power of two that is at least `value`. Zero and one both give
/// one; a value above 2^63 has no answer and gives zero.
public ulong RoundUpToPowerOfTwo(ulong value)
{
    if (value <= 1)
        return 1;
    if (value > 0x8000000000000000)
        return 0;

    ulong result = 1;
    while (result < value)
        result = result << 1;
    return result;
}
