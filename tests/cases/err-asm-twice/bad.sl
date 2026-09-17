// SPDX-License-Identifier: 0BSD
module Bad;

int Main()
{
    long total = 0;
    long count = 3;
    asm (in rax = count, in eax = total) { add rax, 1 }  // eax is rax, and both go in
    return (int)total;
}
