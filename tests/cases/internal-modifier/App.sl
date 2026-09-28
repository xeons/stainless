// SPDX-License-Identifier: 0BSD
//
// From another module: what is public, and what 'protected internal' hands a
// derived class.
module App;

import Standard.Console;
import Shop;

internal class Counter : Till
{
    internal Counter()
    {
    }

    internal int Open() => Drawer() + 2;
}

public int Main()
{
    ShowShop();
    Console.WriteLine($"derived {new Counter().Open()}");
    return 0;
}
