// SPDX-License-Identifier: 0BSD
//
// A switch expression that names every member of an enum needs no `_`, and
// a value that is none of them -- a cast can make one -- ends the program
// rather than taking whichever arm came last.
module AbortSwitchUnmatched;

import Standard.Console;

public enum Color { Red, Green, Blue }

String Paint(Color color) => color switch
{
    Color.Red => "red",
    Color.Green => "green",
    Color.Blue => "blue",
};

int Main()
{
    Console.WriteLine(Paint(Color.Blue));
    Console.WriteLine(Paint((Color)7));
    Console.WriteLine("not reached");
    return 0;
}
