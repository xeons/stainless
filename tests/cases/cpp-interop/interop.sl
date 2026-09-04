// SPDX-License-Identifier: 0BSD
//
// C++ by its mangled name, in both directions and with no shim in between.
//
// C++ has no ABI of its own, so there are two schemes and they share nothing:
// Itanium for gcc and clang, Microsoft's for MSVC and for clang targeting it.
// This test links against a real C++ translation unit, so the linker checks
// the mangling rather than a string comparison doing it.
module Interop;

import Standard.Console;

extern "C++" int cpp_add(int a, int b);
extern "C++" double cpp_scale(double x, float y);
extern "C++" long cpp_wide(long a, ulong b);
extern "C++" bool cpp_flag(bool b, char c);
extern "C++" int cpp_deref(int* p, int* q);

// A namespace is written on the declaration. It decides the linker name and
// nothing else: the function joins this module like any other, so it is called
// by its plain name.
extern "C++" double geometry::area(double w, double h);
extern "C++" int geometry::mix(int* p, double* q, int* r);
extern "C++" int outer::inner::deep(int n);

// Exported the same way. With no namespace written it takes the module's,
// because a module is what Stainless calls a namespace.
export "C++" int Doubled(int n) { return n * 2; }
export "C++" double shapes::Perimeter(double w, double h) { return 2.0 * (w + h); }

// Which the C++ side calls back, to prove the export resolves too.
extern "C++" int RoundTrip(int n);

int Main() {
    Console.WriteLine(Text.FromInteger(cpp_add(40, 2)));
    Console.WriteLine(Text.FromDouble(cpp_scale(2.5, (float)4.0)));
    Console.WriteLine(Text.FromInteger(cpp_wide(40, 2)));
    Console.WriteLine(cpp_flag(true, 'x') ? "flag:yes" : "flag:no");

    int one = 20;
    int two = 22;
    Console.WriteLine(Text.FromInteger(cpp_deref(&one, &two)));

    Console.WriteLine(Text.FromDouble(area(3.0, 4.0)));

    // Two int* and one double*: the repeated pointer is a back-reference in
    // both schemes, which is the part a naive mangler gets wrong.
    double half = 0.5;
    Console.WriteLine(Text.FromInteger(mix(&one, &half, &two)));

    Console.WriteLine(Text.FromInteger(deep(6)));
    Console.WriteLine(Text.FromInteger(RoundTrip(20)));
    return 0;
}
