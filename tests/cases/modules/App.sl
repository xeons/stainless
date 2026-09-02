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

    printf("dot=%g\n", Dot(a, b));
    printf("len2=%g\n", a.Length2());
    printf("total=%g\n", Total());
    printf("scaled=%g\n", Geometry.Scale(2.0, 3.0));
    return 0;
}

// Used above, declared below. No forward declaration exists in this language.
double Total() {
    var acc = new Accumulator();
    acc.Add(1.5);
    acc.Add(2.5);
    return acc.Total();
}
