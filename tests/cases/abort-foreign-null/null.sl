// SPDX-License-Identifier: 0BSD
//
// A declaration that says a C function returns a `String` is a promise C
// cannot be held to. A null coming back stops the program at the call, rather
// than be stored where a `String` is trusted never to be null.
module AbortForeignNull;

import Standard.Console;

extern "C" String? c_find_maybe(int wanted);
extern "C" String c_find_name(int wanted);

int Main()
{
    String? maybe = c_find_maybe(1);
    Console.WriteLine(maybe == null ? "maybe: none" : "maybe: some");
    String name = c_find_name(2);
    Console.WriteLine("never " + name);
    return 0;
}
