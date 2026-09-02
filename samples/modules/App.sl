// SPDX-License-Identifier: 0BSD
module App;

import Geometry;

extern "C" int printf(byte* format, ...);

int Main() {
    Vec2 a;
    a.X = 3.0;
    a.Y = 4.0;

    Vec2 b;
    b.X = 1.0;
    b.Y = 2.0;

    printf("Dot(a, b)   = %g\n", Dot(a, b));
    printf("a.Length2() = %g\n", a.Length2());
    printf("Total       = %g\n", Total());
    return 0;
}

// Declared after Main, used by Main. No forward declaration, no header.
double Total() {
    var acc = new Accumulator();
    acc.Add(1.5);
    acc.Add(2.5);
    return acc.Total();
}
