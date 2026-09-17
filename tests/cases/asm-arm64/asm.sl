// SPDX-License-Identifier: 0BSD
//
// The asm statement for ARM64, built to an object file: every register
// spelling LLVM treats differently from the obvious one, and the clobber list
// each system gets. platform.sl is this case's alone, because the register it
// names is one Windows refuses.
module AsmArm64;

long Add(long a, long b)
{
    long total = a;
    asm (inout x0 = total, in x1 = b)
    {
        add x0, x0, x1
    }
    return total;
}

// x30 is 'lr' to LLVM, and a float and a double take the s and d names.
long Registers(int narrow, float single, double wide)
{
    long link = 0;
    float half = single;
    double twice = wide;
    asm (in w9 = narrow, inout x30 = link, inout v1 = half, inout d2 = twice)
    {
        add x30, x30, x9    // a comment
        fadd s1, s1, s1 ; fadd d2, d2, d2
    }
    return link;
}

int Main()
{
    asm { nop }
    return (int)(Add(40, 2) + Registers(1, 1.0f, 2.0));
}
