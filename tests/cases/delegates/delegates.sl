// SPDX-License-Identifier: 0BSD
module Delegates;

import Standard.Console;

extern "C" int printf(byte* format, ...);

// A delegate is one function pointer with the C calling convention, so C can
// both receive one and call back through it. See native.c.
extern "C" int c_apply(Transform f, int value);
extern "C" int c_sum_with(Transform f, int count);

public delegate int Transform(int value);
public delegate void Reporter(int value);

int Double(int value) { return value * 2; }
int Square(int value) { return value * value; }
int Negate(int value) { return 0 - value; }

void Report(int value) { printf("report=%d\n", value); }

// Overloads are separated by the delegate the name is stored in.
int Pick(int value) { return value + 1; }
double Pick(double value) { return value + 1.0; }

// A delegate crosses a function boundary like any other value.
int ApplyTwice(Transform f, int value) { return f(f(value)); }

// And lives in a struct, because it is not managed and holds no reference.
struct Pipeline {
    Transform first;
    Transform second;
}

int Main() {
    Transform t = Double;
    printf("double=%d\n", t(21));

    t = Square;
    printf("square=%d\n", t(7));

    printf("twice=%d\n", ApplyTwice(Negate, 5));
    printf("twiceSquare=%d\n", ApplyTwice(Square, 3));

    // Overload resolved by the delegate's signature, not by an argument.
    Transform picked = Pick;
    printf("picked=%d\n", picked(41));

    Reporter r = Report;
    r(99);

    // A null callback, exactly as C spells it.
    Transform none = null;
    printf("isNull=%d\n", none == null ? 1 : 0);
    printf("isNotNull=%d\n", t != null ? 1 : 0);

    Pipeline p;
    p.first = Double;
    p.second = Square;
    printf("pipeline=%d\n", p.second(p.first(3)));

    // Handed to C, and called from C.
    printf("cApply=%d\n", c_apply(Double, 50));
    printf("cSum=%d\n", c_sum_with(Square, 4));

    printf("done\n");
    return 0;
}
