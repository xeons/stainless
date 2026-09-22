// SPDX-License-Identifier: 0BSD
//
// Half of a two-file program, which is the half that matters: the IDE could
// only ever compile one file, so a project whose source is two is the smallest
// thing that proves it is building the project rather than the file in front.
module Fixture;

import Standard.Console;

int Main()
{
    Console.WriteLine(FormatGreeting());
    return 0;
}
