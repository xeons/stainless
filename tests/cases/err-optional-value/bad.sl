// SPDX-License-Identifier: 0BSD
//
// Only a reference can be optional, because the null is the pointer. A value
// type has no spare bit to be null with, so `Option<T>` is what says "a value
// or none" for one -- see §2.8.1.
module Bad;

public struct Point { public int X; }

nuint? Missing() { return null; }

int Main() {
    int? count = null;
    Point? here = null;
    return 0;
}
