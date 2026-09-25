// SPDX-License-Identifier: 0BSD
module Bad;

int Main()
{
    int total = 0;
    for parallel (int i = 0; i < 100; i++)
        total++;                // every chunk stepping one variable
    return total;
}
