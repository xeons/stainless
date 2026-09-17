// SPDX-License-Identifier: 0BSD
module Bad;

int Main()
{
    String name = "counted";
    long length = 0;
    asm (in rcx = name, out rax = length) { mov rax, rcx }
    return (int)length;
}
