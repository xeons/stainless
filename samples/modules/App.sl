// SPDX-License-Identifier: 0BSD
module App;

import Geometry;

extern "C" int printf(byte* format, ...);

int Main()
{
    Vec2 a;
    a.X = 3.0;
    a.Y = 4.0;

    Vec2 b;
    b.X = 1.0;
    b.Y = 2.0;

    printf("ComputeDotProduct(a, b) = %g\n", ComputeDotProduct(a, b));
    printf("a.LengthSquared         = %g\n", a.LengthSquared);
    printf("SumAccumulated()        = %g\n", SumAccumulated());
    return 0;
}

// Declared after Main, used by Main. No forward declaration, no header.
double SumAccumulated()
{
    var acc = new Accumulator();
    acc.Add(1.5);
    acc.Add(2.5);
    return acc.Total;
}
