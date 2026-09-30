// SPDX-License-Identifier: 0BSD
//
// A String is never null, so an empty Slot<String> has nothing to answer
// with. Reading one stops the program there, rather than hand out a null.
module AbortSlotEmpty;

import Standard.Console;

int Main()
{
    Slot<String>[] room = new Slot<String>[2];
    room[0] = "held";
    Console.WriteLine("full " + room[0].Value);
    Console.WriteLine("never " + room[1].Value);
    return 0;
}
