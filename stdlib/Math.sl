// Stainless - an experimental systems language.
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

// Arithmetic that is not an operator.
//
// A module is a scope, so this needs no static class to live in: `Math.Sqrt(x)`
// is a module-qualified call, and `import Standard.Math;` is what makes the
// short name reach it.
//
// The floating-point functions are the C library's, declared here and called
// directly. That is the whole implementation -- there is no wrapper layer and
// no conversion, because a Stainless `double` is a C `double`. The integer ones
// are written out, since C has no such library.
module Standard.Math;

extern "C" {
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
public const double Epsilon = 0.00000000000000022204;

// ------------------------------------------------------ floating point

public double Sqrt(double x) { return sqrt(x); }
public double Cbrt(double x) { return cbrt(x); }
public double Pow(double x, double y) { return pow(x, y); }
public double Exp(double x) { return exp(x); }
public double Log(double x) { return log(x); }
public double Log2(double x) { return log2(x); }
public double Log10(double x) { return log10(x); }

public double Sin(double x) { return sin(x); }
public double Cos(double x) { return cos(x); }
public double Tan(double x) { return tan(x); }
public double Asin(double x) { return asin(x); }
public double Acos(double x) { return acos(x); }
public double Atan(double x) { return atan(x); }

/// The angle to (x, y) from the positive x axis, in the correct quadrant.
/// Note the argument order, which is the C library's: y first.
public double Atan2(double y, double x) { return atan2(y, x); }

public double Sinh(double x) { return sinh(x); }
public double Cosh(double x) { return cosh(x); }
public double Tanh(double x) { return tanh(x); }

/// The length of the vector (x, y), computed without overflowing on the way.
public double Hypot(double x, double y) { return hypot(x, y); }

public double Floor(double x) { return floor(x); }
public double Ceiling(double x) { return ceil(x); }

/// To the nearest integer, halves away from zero -- C's rule, not the
/// banker's rounding C# uses by default.
public double Round(double x) { return round(x); }

/// Towards zero, dropping the fractional part.
public double Truncate(double x) { return trunc(x); }

/// The remainder of x/y, with the sign of x. This is C's fmod, not a modulus:
/// `Remainder(-7.0, 3.0)` is -1.0, not 2.0.
public double Remainder(double x, double y) { return fmod(x, y); }

public double Abs(double x) { return fabs(x); }

public double Min(double a, double b) { return a < b ? a : b; }
public double Max(double a, double b) { return a > b ? a : b; }

/// `x`, brought within [low, high]. Aborts nothing when the bounds are the
/// wrong way round; it simply returns `low`.
public double Clamp(double x, double low, double high) {
    if (x < low) { return low; }
    if (x > high) { return high; }
    return x;
}

/// -1, 0 or 1. NaN has no sign, and returns 0.
public int Sign(double x) {
    if (x < 0.0) { return -1; }
    if (x > 0.0) { return 1; }
    return 0;
}

/// True when `x` is Not a Number, which is the one value not equal to itself.
public bool IsNaN(double x) { return x != x; }

/// True for either infinity. A finite number minus itself is zero; an infinity
/// minus itself is NaN, which is what separates the two.
public bool IsInfinite(double x) {
    if (IsNaN(x)) { return false; }
    return x - x != 0.0;
}

public bool IsFinite(double x) { return !IsNaN(x) && !IsInfinite(x); }

/// True when the two are within `tolerance` of each other. Comparing floats
/// with `==` is almost always a mistake, and this is what to write instead.
public bool Near(double a, double b, double tolerance) {
    return Abs(a - b) <= tolerance;
}

/// Straight-line interpolation: `at` of 0 gives `from`, 1 gives `to`.
public double Lerp(double from, double to, double at) {
    return from + (to - from) * at;
}

public double Degrees(double radians) { return radians * 180.0 / Pi; }
public double Radians(double degrees) { return degrees * Pi / 180.0; }

// ---------------------------------------------------------------- integers

public int Abs(int x) { return x < 0 ? -x : x; }
public long Abs(long x) { return x < 0 ? -x : x; }

public int Min(int a, int b) { return a < b ? a : b; }
public int Max(int a, int b) { return a > b ? a : b; }
public long Min(long a, long b) { return a < b ? a : b; }
public long Max(long a, long b) { return a > b ? a : b; }
public nuint Min(nuint a, nuint b) { return a < b ? a : b; }
public nuint Max(nuint a, nuint b) { return a > b ? a : b; }

public int Clamp(int x, int low, int high) {
    if (x < low) { return low; }
    if (x > high) { return high; }
    return x;
}

public long Clamp(long x, long low, long high) {
    if (x < low) { return low; }
    if (x > high) { return high; }
    return x;
}

public nuint Clamp(nuint x, nuint low, nuint high) {
    if (x < low) { return low; }
    if (x > high) { return high; }
    return x;
}

public int Sign(int x) {
    if (x < 0) { return -1; }
    if (x > 0) { return 1; }
    return 0;
}

public int Sign(long x) {
    if (x < 0) { return -1; }
    if (x > 0) { return 1; }
    return 0;
}

/// `a` divided by `b`, rounded up. Written this way rather than as
/// `(a + b - 1) / b` so that a large `a` cannot overflow on the way.
public nuint DivideCeiling(nuint a, nuint b) {
    if (a == 0) { return 0; }
    return (a - 1) / b + 1;
}

/// The greatest common divisor, by Euclid.
public long GreatestCommonDivisor(long a, long b) {
    a = Abs(a);
    b = Abs(b);

    while (b != 0) {
        long next = a % b;
        a = b;
        b = next;
    }
    return a;
}

public long LeastCommonMultiple(long a, long b) {
    if (a == 0 || b == 0) { return 0; }
    return Abs(a / GreatestCommonDivisor(a, b) * b);
}

// -------------------------------------------------------------------- bits

/// How many bits are set. Kernighan's loop: each step clears the lowest set
/// bit, so it runs once per bit that is actually there.
public int PopCount(ulong value) {
    int count = 0;
    while (value != 0) {
        value = value & (value - 1);
        count = count + 1;
    }
    return count;
}

/// How many zero bits sit above the highest set bit. 64 for zero.
public int LeadingZeros(ulong value) {
    if (value == 0) { return 64; }

    int count = 0;
    while ((value & 0x8000000000000000) == 0) {
        value = value << 1;
        count = count + 1;
    }
    return count;
}

/// How many zero bits sit below the lowest set bit. 64 for zero.
public int TrailingZeros(ulong value) {
    if (value == 0) { return 64; }

    int count = 0;
    while ((value & 1) == 0) {
        value = value >> 1;
        count = count + 1;
    }
    return count;
}

public bool IsPowerOfTwo(ulong value) {
    return value != 0 && (value & (value - 1)) == 0;
}

/// The smallest power of two that is at least `value`. Zero and one both give
/// one; a value above 2^63 has no answer and gives zero.
public ulong NextPowerOfTwo(ulong value) {
    if (value <= 1) { return 1; }
    if (value > 0x8000000000000000) { return 0; }

    ulong result = 1;
    while (result < value) { result = result << 1; }
    return result;
}
