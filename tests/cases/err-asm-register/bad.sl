// SPDX-License-Identifier: 0BSD
module Bad;

int Main()
{
    long total = 0;
    asm (out x0 = total) { mov rax, 1 }   // an ARM64 register, on x64
    return (int)total;
}
