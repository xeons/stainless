// SPDX-License-Identifier: 0BSD
module Bad;

int Main()
{
    // Only a function may be static in a block: a local lives in the frame
    // it was declared in.
    static int counter = 0;
    return 0;
}
