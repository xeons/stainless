// SPDX-License-Identifier: 0BSD
module Bad;

// A block's braces are counted, so a '{' inside it without a partner takes the
// function's closing brace as the block's, and one more takes the rest of the
// file. The two masks below are never closed, so the block never ends.
int Main()
{
    asm
    {
        vmovaps zmm0 {k1, zmm1
        vmovaps zmm2 {k2, zmm3
    }
    return 0;
}
