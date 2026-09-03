// SPDX-License-Identifier: 0BSD
module Maths;

import Standard.Math;
import Standard.Console;

extern "C" int printf(byte* format, ...);

int Main() {
    // A module is a scope, so Math needs no static class to live in.
    printf("roots=%.4f %.4f pow=%.1f\n",
        Math.Sqrt(2.0), Math.Cbrt(27.0), Math.Pow(2.0, 10.0));
    printf("hypot=%.1f exp=%.4f log=%.1f %.1f\n",
        Math.Hypot(3.0, 4.0), Math.Exp(0.0), Math.Log2(1024.0), Math.Log10(1000.0));

    printf("rounding=%.1f %.1f %.1f %.1f\n",
        Math.Floor(-1.5), Math.Ceiling(-1.5), Math.Round(2.5), Math.Truncate(-2.7));
    printf("remainder=%.1f\n", Math.Remainder(-7.0, 3.0));

    // Overloaded across int, long and double, resolved by argument type.
    printf("abs=%.1f %d %lld\n", Math.Abs(-3.5), Math.Abs(-4), Math.Abs((long)-5));
    printf("sign=%d %d %d\n", Math.Sign(-2.0), Math.Sign(7), Math.Sign((long)0));
    printf("minmax=%d %d %.1f %.1f\n",
        Math.Min(3, 9), Math.Max(3, 9), Math.Min(1.5, 2.5), Math.Max(1.5, 2.5));
    printf("clamp=%d %d %.1f\n",
        Math.Clamp(15, 0, 10), Math.Clamp(-5, 0, 10), Math.Clamp(0.5, 0.0, 1.0));

    // The three values floating point has that integers do not.
    double zero = 0.0;
    double one = 1.0;
    printf("special=%d %d %d %d\n",
        Math.IsNaN(zero / zero) ? 1 : 0,
        Math.IsInfinite(one / zero) ? 1 : 0,
        Math.IsFinite(1.0) ? 1 : 0,
        Math.IsFinite(zero / zero) ? 1 : 0);

    printf("trig=%.4f %.4f %.4f\n", Math.Sin(0.0), Math.Cos(0.0), Math.Atan2(1.0, 1.0));
    printf("angles=%.1f %.4f\n", Math.Degrees(Math.Pi), Math.Radians(180.0));

    printf("lerp=%.2f near=%d %d\n",
        Math.Lerp(0.0, 10.0, 0.25),
        Math.Near(1.0, 1.001, 0.01) ? 1 : 0,
        Math.Near(1.0, 1.1, 0.01) ? 1 : 0);

    printf("divisors=%lld %lld %llu\n",
        Math.GreatestCommonDivisor(48, 18),
        Math.LeastCommonMultiple(4, 6),
        Math.DivideCeiling((nuint)7, (nuint)2));

    printf("bits=%d %d %d\n",
        Math.PopCount((ulong)255), Math.LeadingZeros((ulong)1), Math.TrailingZeros((ulong)8));
    printf("powers=%d %d %llu %llu\n",
        Math.IsPowerOfTwo((ulong)64) ? 1 : 0,
        Math.IsPowerOfTwo((ulong)63) ? 1 : 0,
        Math.NextPowerOfTwo((ulong)100),
        Math.NextPowerOfTwo((ulong)1));

    printf("constants=%.5f %.5f %.5f\n", Math.Pi, Math.Tau, Math.E);

    printf("done\n");
    return 0;
}
