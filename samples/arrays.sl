// SPDX-License-Identifier: 0BSD
//
// `T[]`: counted, bounds checked, and reference counted along with whatever it
// holds.
module Arrays;

import Standard.Console;

int Sum(int[] values) {
    var total = 0;
    for (nuint i = 0u; i < values.Length; i = i + 1u) {
        total = total + values[i];
    }
    return total;
}

/// A slice is a view: no copy, and the array it came from stays alive as long
/// as the view does.
int SumOf(int[:] window) {
    var total = 0;
    for (nuint i = 0u; i < window.Length; i = i + 1u) {
        total = total + window[i];
    }
    return total;
}

int Main() {
    // An array literal takes its type from where it is going, so a `var` here
    // is an `int[]` decided by the elements themselves.
    var squares = [0, 1, 4, 9, 16];

    Console.WriteLine("length = " + Text.FromInteger(squares.Length));
    Console.WriteLine("sum    = " + Text.FromInteger(Sum(squares)));

    // `new T[n]` when the length is not a literal, and the elements are zero.
    var counted = new int[5];
    for (nuint i = 0u; i < counted.Length; i = i + 1u) {
        counted[i] = (int)(i * i);
    }
    Console.WriteLine("same   = " + Text.FromBool(Sum(counted) == Sum(squares)));

    // Arrays of references: each element is retained and released with the
    // array, so nothing here has a lifetime to get wrong.
    var words = ["alpha", "beta", "gamma" + "!"];
    Console.WriteLine(" ".Join(words));

    // A slice of the middle. `squares` is not copied and cannot be freed while
    // the view exists.
    Console.WriteLine("middle = " + Text.FromInteger(SumOf(squares[1:4])));

    // A fixed-length array is a slot rather than an allocation: it lives in the
    // struct or the frame that declares it, which is what makes it C's `int[3]`.
    int[3] inline = [7, 8, 9];
    Console.WriteLine("inline = " + Text.FromInteger(inline[0] + inline[1] + inline[2]));

    // Every index is checked. This one is fine; one past the end would stop the
    // program with the index and the length rather than reading a neighbour.
    Console.WriteLine("last   = " + Text.FromInteger(squares[squares.Length - 1u]));
    return 0;
}
