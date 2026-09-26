// SPDX-License-Identifier: 0BSD
//
// `^n` past the start stops the program as any index out of range does, and
// the message names the `^n` that was written rather than the index the
// subtraction wrapped to.
module AbortIndexFromEnd;

import Standard.Console;
import Standard.Text;

int Main()
{
    int[] numbers = [1, 2, 3];
    Console.WriteLine("last " + Text.FromInteger(numbers[^1]));

    int back = 4;
    var lost = numbers[^back];

    Console.WriteLine("unreachable");
    return 0;
}
