// SPDX-License-Identifier: 0BSD
//
// A step with no type of its own is never made, as an expression statement's
// is not: it has no effect, and says so.
module Steps;

import Standard.Console;
import Standard.Text;

public void Main()
{
    int passes = 0;
    for (int i = 0; i < 3 && passes < 5; i => 1)
        passes++;
    Console.WriteLine(Text.FromInteger(passes));
}
