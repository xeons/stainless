// SPDX-License-Identifier: 0BSD
//
// The elements of a `params Span<T>` call live in the caller's frame, so a slice
// of them that outlives the statement would point at nothing. Nothing in the
// callee's signature can say it keeps one, so the frame checks on the way out
// and stops the program rather than let it dangle.
module Escape;

import Standard.Console;
import Standard.Text;

Span<int> Keep(params Span<int> values) => values;

int First(params Span<int> values)
{
    // A copy the callee lets go of before it returns is not a keep.
    Span<int> held = values;
    return held[0];
}

int Main()
{
    Console.WriteLine(Text.FromInteger(First(7, 8)));

    var kept = Keep(1, 2, 3);
    Console.WriteLine(Text.FromInteger(kept[0]));
    return 0;
}
