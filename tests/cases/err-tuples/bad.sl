// SPDX-License-Identifier: 0BSD
module Bad;

// A tuple is at least two values, every one of them a value, and taking one
// apart names exactly as many things as it holds.

void Nothing() { }

int Main()
{
    // Nothing is not a value.
    var empty = (1, Nothing());

    var pair = (1, "one");

    // Too few names, and too many.
    var (only) = pair;
    var (a, b, c) = pair;

    // And nothing to take apart at all.
    int plain = 5;
    var (x, y) = plain;
    return 0;
}
