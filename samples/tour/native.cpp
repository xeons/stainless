// SPDX-License-Identifier: 0BSD
//
// Ordinary C++, with no `extern "C"` anywhere and no shim. Stainless reaches
// these by mangling their signatures the way the target's own C++ compiler
// does -- Itanium on Linux, MSVC's scheme on Windows -- which is why §8.1 is
// about names rather than about calls.

namespace tour {
    double area(double width, double height) { return width * height; }
}

// Defined in Stainless as `export "C++" int tour::Doubled(int)`, and called
// from here to prove the mangling agrees in both directions.
namespace tour { int Doubled(int n); }

int cpp_round_trip(int n) { return tour::Doubled(n) + 1; }
