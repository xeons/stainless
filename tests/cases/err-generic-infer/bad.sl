// SPDX-License-Identifier: 0BSD
module Bad;

// T appears only in the return type, so nothing can pin it down.
T Make<T>(int seed) { return seed; }

int Main() {
    var x = Make(1);
    return 0;
}
