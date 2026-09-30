// SPDX-License-Identifier: 0BSD
module Bad;

public struct Flags { public int A : 3; public int B : 5; }

int Main()
{
    Flags f;
    f.A = 1;
    int* p = &f.A;          // a bit-field has no address
    return *p;
}
