// SPDX-License-Identifier: 0BSD
module Bad;

int Main()
{
    double half = 0.5;
    long bits = 0;
    asm (in rcx = half, out rax = bits) { mov rax, rcx }
    return (int)bits;
}
