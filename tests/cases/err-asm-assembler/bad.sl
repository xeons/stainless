// SPDX-License-Identifier: 0BSD
module Bad;

int Main()
{
    long total = 0;
    asm (out rax = total)
    {
        mov rax, 1
        bogus rax           // no such instruction; the assembler says so, here
    }
    return (int)total;
}
