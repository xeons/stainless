// SPDX-License-Identifier: 0BSD
//
// A double is written and read with a '.', whatever the C locale says. GTK
// sets the locale from the environment as it starts, and under German
// settings the C library's own decimal point is a comma.
module NumbersIgnoreLocale;

import Standard.Console;
import Standard.Convert;
import Standard.Text;

extern "C" byte* setlocale(int category, byte* name);

const int LocaleAll = 0;

int Main()
{
    var switched = setlocale(LocaleAll, "de-DE".ToPointer());
    Console.WriteLine(switched != null ? "switched" : "not switched");

    Console.WriteLine(Text.FromDouble(3.25));
    Console.WriteLine(Text.FromDouble(-0.001));
    Console.WriteLine(Text.FromDouble(1e300));

    var parsed = Convert.ToDouble("3.25");
    Console.WriteLine(parsed.Ok && parsed.Value == 3.25 ? "parsed 3.25" : "misread");

    var small = Convert.ToDouble("6.02e-23");
    Console.WriteLine(small.Ok && small.Value == 6.02e-23 ? "parsed 6.02e-23" : "misread");
    return 0;
}
