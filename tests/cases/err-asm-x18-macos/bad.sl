// SPDX-License-Identifier: 0BSD
module Bad;

// macOS reserves x18, so a block may neither name it nor be assumed to change it.
int Main()
{
    long r = 0;
    asm (in x18 = 1, out x0 = r) { mov x0, x18 }
    return (int)r;
}
