// SPDX-License-Identifier: 0BSD
//
// A range whose length is near the top of `nuint` must not walk past the
// guard that checks it.
//
// `index + count > _count` wraps: with a count two short of the maximum, the
// sum comes out below the list's length and the check passes. `RemoveRange`
// then set `_count = _count - count`, which wraps upward, and the list was
// left claiming eight items over a buffer of five -- every read past the
// fifth inside what the bounds check believed, and so unreported.
//
// The guard subtracts on the side that cannot wrap, and the failure names the
// position the range asked for rather than the one it started at.
module Ranges;

import Standard.Console;
import Standard.Text;
import Standard.Collections;
import Standard.Limits;

int Main()
{
    var list = new List<int>();
    for (int i = 0; i < 5; i++)
        list.Add(i);

    Console.WriteLine("count " + Text.FromInteger((long)list.Count));

    // In range, so that the failure below is about the one that is not.
    var kept = list.GetRange(3u, 2u);
    Console.WriteLine("range " + Text.FromInteger((long)kept.Count));

    list.RemoveRange(3u, MaxNUInt - 2u);

    Console.WriteLine("unreachable " + Text.FromInteger((long)list.Count));
    return 0;
}
