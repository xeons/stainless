// SPDX-License-Identifier: 0BSD
module Bad;

public struct Point { public int X; }

// A constraint is something with implementers or something with derived types.
// A struct has neither, so a parameter constrained to one could only ever be
// that struct -- which is a parameter that did not need to be one.
public class Holder<T> where T : Point { T item; }

int Main() {
    Holder<Point> h;
    return 0;
}
