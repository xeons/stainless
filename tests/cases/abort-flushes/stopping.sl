// SPDX-License-Identifier: 0BSD
//
// What a program leaves behind when it stops.
//
// A bounds violation, a division by zero or a missing key is a mistake in the
// program rather than an outcome of it, so it aborts through the runtime
// rather than returning a `Result` (§2.6). That much was always true. What was
// not is that `abort` does not flush: a buffered stdout was discarded, so the
// reader got the message saying why the program stopped and none of the output
// that led up to it -- not even a line printed immediately before.
//
// The harness reads stdout and then stderr, so this case pins both halves: the
// account the program gave of itself, and the explanation after it.
module Stopping;

import Standard.Console;
import Standard.Collections;

int Main()
{
    Console.WriteLine("one");
    Console.WriteLine("two");

    var map = new Dictionary<String, int>();
    map.Set("here", 1);

    // Asking for a key that is not there. `ContainsKey` and `GetOr` are how a
    // caller asks when a miss is ordinary; this is the bargain `Get` makes.
    var missing = map.Get("absent");

    Console.WriteLine("unreachable");
    return 0;
}
