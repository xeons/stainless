// SPDX-License-Identifier: 0BSD
//
// An enum from a referenced library writes its names here as it does there,
// and its [Flags] crosses with it: '|' and 'HasFlag' are allowed on it, and
// its text is the flags that are set.
module App;

import Standard.Console;
import Library.Palette;

int Main()
{
    var access = Access.Read | Access.Execute;
    Console.WriteLine($"{Colour.Red} {Colour.Blue} {(Colour)7}");
    Console.WriteLine($"{Access.None} | {access} | {access.HasFlag(Access.Write)}");
    Console.WriteLine(DescribeAccess(access | Access.Write));
    return 0;
}
