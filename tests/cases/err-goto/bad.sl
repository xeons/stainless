// SPDX-License-Identifier: 0BSD
module Bad;

// A label goes at the top level of a function, is named once, and is named by
// something. All three are about the same thing: a jump has to know what to
// release on the way, and that answer has to be the same whichever jump lands.

int Nowhere() {
    // No label of that name in this function.
    goto elsewhere;
}

int Nested(bool flag) {
    if (flag) {
        // Two jumps from different depths would have different amounts to let
        // go of, so a label inside a block has no single answer.
    inner:
        return 1;
    }
    goto inner;
}

int Twice() {
    int n = 0;

again:
    n++;
    if (n < 2) { goto again; }

// The same name a second time: a jump would have two destinations.
again:
    return n;
}

int Main() { return Nowhere() + Nested(true) + Twice(); }
