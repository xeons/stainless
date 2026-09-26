// SPDX-License-Identifier: 0BSD
//
// The consumer has the library's metadata and no source, and calls its
// `params` functions with the elements written out.
module App;

import Standard.Console;
import Standard.Text;
import Library.Numbers;

int Main()
{
    Console.WriteLine(Text.FromInteger(Total(1, 2, 3)));
    Console.WriteLine(Text.FromInteger(Total()));
    Console.WriteLine(Joined("/", "usr", "local", "bin"));
    return 0;
}
