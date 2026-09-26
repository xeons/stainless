// SPDX-License-Identifier: 0BSD
//
// What a C variadic function cannot be given: a value that takes its type from
// a parameter, where '...' declares none, and a name for an argument that has
// only a position.
module Bad;

extern "C" int printf(byte* format, ...);

int Twice(int x) => x * 2;

int Main()
{
    printf("%p\n", []);                     // SL0805
    printf("%p\n", Twice);                  // SL0805
    printf("%p\n", (int x) => x);           // SL0805
    printf("%d\n", 1, width: 2);            // SL0601
    return 0;
}
