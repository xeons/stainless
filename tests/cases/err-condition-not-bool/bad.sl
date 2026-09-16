// SPDX-License-Identifier: 0BSD
module Bad;

int Main()
{
    int x = 1;
    if (x)    // Stainless has no truthiness
        return 1;
    return 0;
}
