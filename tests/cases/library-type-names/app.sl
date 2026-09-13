// SPDX-License-Identifier: 0BSD
module App;

import Standard.Console;
import Standard.Text;
import Library.Names;

int Main() {
    var u = Measure();
    Console.WriteLine("units " + Text.FromInteger((int)u.Byte) + " " +
        Text.FromInteger((int)u.Utf16) + " " + Text.FromInteger((int)u.Scalar) + " " +
        Text.FromDouble(u.Ratio) + " " + Text.FromInteger((int)u.Count));

    var numbers = Squares(5);
    int[:] tail = Tail(numbers);
    Console.WriteLine("tail " + Text.FromInteger((int)tail.Length) + " " +
        Text.FromInteger(tail[3]));

    var pair = Pair(7);
    Console.WriteLine("pair " + Text.FromInteger(pair.Item1) + " " + pair.Item2);

    var both = Both(numbers);
    Console.WriteLine("both " + Text.FromInteger(both.Item1.X + both.Item1.Y) + " " +
        Text.FromInteger((int)both.Item2.Length));

    // The whole point of interning: a slice named by the library and one
    // written here are one type, so either may be assigned to the other.
    int[:] mine = numbers[0:2];
    Console.WriteLine("mine " + Text.FromInteger((int)mine.Length));
    mine = tail;
    Console.WriteLine("assigned " + Text.FromInteger((int)mine.Length));
    return 0;
}
