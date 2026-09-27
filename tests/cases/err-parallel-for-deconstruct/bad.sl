// SPDX-License-Identifier: 0BSD
module Bad;

int Main()
{
    int last = 0;
    int[] seen = new int[100];
    for parallel (int i = 0; i < 100; i++)
    {
        (seen[i], last) = (i, i);   // the element is this chunk's own; 'last' is everyone's
    }
    return last;
}
