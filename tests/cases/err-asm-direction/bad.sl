// SPDX-License-Identifier: 0BSD
module Bad;

int Main()
{
    long total = 0;
    asm (rax = total) { mov rax, 1 }    // in, out or inout?
    return (int)total;
}
