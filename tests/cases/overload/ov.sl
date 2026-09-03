// SPDX-License-Identifier: 0BSD
module Ov;

extern "C" int printf(byte* format, ...);

int Describe(int value)    { return value * 10; }
int Describe(double value) { return (int)value + 1000; }

// An array parameter has to be part of the mangled name, or these three are
// one symbol: the element type distinguishes two of them, and the absence of
// a parameter used to be spelled the same way an array was.
int Count()             { return 1; }
int Count(int[] values) { return 2 + (int)values.Length; }
int Count(String[] all) { return 20 + (int)all.Length; }

int Main() {
    printf("%d\n", Describe(7));
    printf("%d\n", Describe(2.5));
    var numbers = new int[3];
    var words = new String[2];
    printf("%d %d %d\n", Count(), Count(numbers), Count(words));
    return 0;
}
