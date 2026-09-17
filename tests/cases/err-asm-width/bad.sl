// SPDX-License-Identifier: 0BSD
module Bad;

int Main()
{
    long wide = 5000000000;
    int total = 0;
    asm (in ecx = wide, out eax = total) { mov eax, ecx }
    return total;
}
