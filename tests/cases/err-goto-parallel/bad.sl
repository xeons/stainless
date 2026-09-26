// SPDX-License-Identifier: 0BSD
module Bad;

import Standard.Console;

// A `parallel` block is work queued to finish where it was started, so there
// is nothing a jump out of one could mean -- a `goto`, or a `goto case` to a
// section of a switch around it. A jump inside the block is ordinary. A label
// nothing jumps to is a warning rather than an error: deleting the last jump
// to one is an ordinary edit.
int Main()
{
    int total = 0;

    parallel
    {
        spawn Console.WriteLine("one");
        if (total == 0)
            goto give_up;
        spawn Console.WriteLine("two");
    }

    switch (total)
    {
        case 0:
            parallel
            {
                goto case 1;
            }
            break;
        case 1:
            break;
    }

    for parallel (int i = 0; i < 4; i++)
    {
        int k = i;
    again:
        k++;
        if (k < 10)
            goto again;
        goto give_up;
    }

give_up:
    return total;

orphan:
    return 1;
}
