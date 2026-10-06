// SPDX-License-Identifier: 0BSD
//
// A C name is one symbol, whatever declares it: a variable cannot share one
// with a function, nor with a variable of another type.
module Bad;

extern "C" int printf;                          // SLI0004
extern "C" int printf(byte* format, ...);

extern "C" int shared_depth;

int Main() => 0;
