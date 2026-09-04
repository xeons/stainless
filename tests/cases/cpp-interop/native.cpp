// SPDX-License-Identifier: 0BSD
//
// Ordinary C++. Nothing here is extern "C", and there is no shim: Stainless
// resolves these by mangling their signatures the way the target's compiler
// does.

int cpp_add(int a, int b) { return a + b; }
double cpp_scale(double x, float y) { return x * y; }
long long cpp_wide(long long a, unsigned long long b) { return a + (long long)b; }
bool cpp_flag(bool b, char c) { return b && c == 'x'; }
int cpp_deref(int *p, int *q) { return *p + *q; }

namespace geometry {
    double area(double w, double h) { return w * h; }
    int mix(int *p, double *q, int *r) { return *p + (int)*q + *r; }
}

namespace outer { namespace inner {
    int deep(int n) { return n * 7; }
} }

// Declared as C++ would declare anything, and resolved against what Stainless
// emitted for its `export "C++"` functions.
namespace Interop { int Doubled(int n); }
namespace shapes  { double Perimeter(double w, double h); }

int RoundTrip(int n) {
    return Interop::Doubled(n) + (int)shapes::Perimeter(0.5, 0.5);
}
