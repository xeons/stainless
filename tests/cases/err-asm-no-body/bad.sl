// SPDX-License-Identifier: 0BSD
module Bad;

int Main()
{
    long total = 0;
    asm (out rax = total);      // the instructions go between braces
    return (int)total;
}
