// SPDX-License-Identifier: 0BSD
//
// How a double is spelled, which had no case of its own and was wrong for
// every value that needed more than six significant digits: pi printed as
// 3.14159, and nothing at all survived being written and read back.
//
// The rule is the shortest text that reads back as the same double. Shortest
// *text*, not shortest precision -- "%.1g" of 60 is "6e+01", which round-trips
// and is five characters where "60" is two -- and on a tie the spelling
// without an exponent wins, since "7e+04" and "70000" are the same length and
// only one of them is what anybody meant.
module Numbers;

import Standard.Console;
import Standard.Text;
import Standard.Convert;

String D(double v) { return Text.FromDouble(v); }

// Every one of these must read back as the value it was written from.
bool Survives(double v) {
    var back = Convert.ToDouble(Text.FromDouble(v));
    return back.Ok && back.Value == v;
}

int Main() {
    // A round number stays round rather than turning scientific.
    Console.WriteLine("round " + D(0.0) + " " + D(1.0) + " " + D(60.0) + " " +
        D(100.0) + " " + D(150.0) + " " + D(70000.0) + " " + D(-70000.0));

    // Precision is kept, which is the whole of the bug this covers.
    Console.WriteLine("exact " + D(3.141592653589793) + " " + D(0.1) + " " +
        D(1.0 / 3.0) + " " + D(0.1234567890123));

    // Far from one, an exponent is genuinely shorter.
    Console.WriteLine("far   " + D(1e21) + " " + D(1e100) + " " + D(1e-7) + " " +
        D(2.5e-10));

    // Negative zero keeps its sign, as it does everywhere else.
    Console.WriteLine("zero  " + D(-0.0));

    // The largest integer a double holds exactly, and one past it.
    Console.WriteLine("ints  " + D(9007199254740992.0) + " " + D(123456789012345.0));

    // A builder spells a number the same way a String does; two spellings for
    // one number is the kind of difference nobody looks for.
    var built = new StringBuilder();
    built.AppendDouble(3.141592653589793);
    built.Append(" ");
    built.AppendDouble(60.0);
    Console.WriteLine("built " + built.ToText());

    Console.WriteLine("round-trip " +
        (Survives(3.141592653589793) && Survives(0.1) && Survives(1.0 / 3.0) &&
         Survives(1e-7) && Survives(1e21) && Survives(60.0) && Survives(-0.0)
            ? "every one" : "LOST"));
    return 0;
}
