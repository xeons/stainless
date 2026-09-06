// SPDX-License-Identifier: 0BSD
module Bad;

import Standard.Console;

// A `parallel` block is work queued to finish where it was started, and every
// label is outside one -- so there is nothing a jump out could mean. A label
// nothing jumps to is a warning rather than an error: deleting the last jump
// to one is an ordinary edit.
int Main() {
    int total = 0;

    parallel {
        spawn Console.WriteLine("one");
        if (total == 0) { goto give_up; }
        spawn Console.WriteLine("two");
    }

give_up:
    return total;

orphan:
    return 1;
}
