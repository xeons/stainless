// SPDX-License-Identifier: 0BSD
module Bad;

int Main()
{
    long top = 0;
    asm (out rsp = top) { nop }
    return (int)top;
}
