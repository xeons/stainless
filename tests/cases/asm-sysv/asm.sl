// SPDX-License-Identifier: 0BSD
//
// The x64 clobber list under System V, pinned as text so that Windows checks it
// too; asm-clobbers is what proves it on a Linux machine by running.
module AsmSysV;

long Add(long a, long b)
{
    long total = a;
    asm (inout rax = total, in rdi = b)
    {
        add rax, rdi
    }
    return total;
}

// rbx is callee-saved on both systems, and naming it adds it to the clobbers.
double Scale(double value, int by)
{
    double result = value;
    long scratch = 0;
    asm (inout xmm0 = result, in ecx = by, out rbx = scratch)
    {
        cvtsi2sd xmm1, ecx
        mulsd xmm0, xmm1
        mov rbx, 1
    }
    return result;
}

int Main()
{
    return (int)Add(40, 2) + (int)Scale(1.5, 2);
}
