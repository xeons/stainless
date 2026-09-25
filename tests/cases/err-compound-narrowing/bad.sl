// SPDX-License-Identifier: 0BSD
module Bad;

// `b += y` casts the result back to a byte only when `y` is itself a byte's
// worth; 300 is not, and neither is an int that could hold anything.
int Main()
{
    byte b = 1;
    b += 300;

    int wide = 5;
    short s = 1;
    s += wide;
    return b + s;
}
