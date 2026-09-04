// SPDX-License-Identifier: 0BSD
module Bad;

public struct Point { public double X; }

// A slice holds a reference, so it is not a value C can be handed.
export "C" int Take(int[:] values) { return 0; }

int Length(int[:] values) { return (int)values.Length; }

int Main() {
    var numbers = new int[4];
    int[:] window = numbers[1:3];

    // A slice has only Length.
    int n = (int)window.Count;

    // Slicing something that is neither an array nor a slice.
    Point p;
    var bad = p[0:1];

    // A bound is an integer.
    var wrong = numbers["a":2];

    // A slice does not convert back to an array on its own.
    int[] whole = window;

    return n;
}
