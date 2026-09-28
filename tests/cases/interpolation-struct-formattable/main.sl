// SPDX-License-Identifier: 0BSD
//
// A struct that implements IFormattable writes itself in an interpolation
// hole: its own ToText is called on the value, which never becomes a
// reference to the interface.
module InterpolationStructFormattable;

import Standard.Console;
import Standard.Text;

public struct Money : IFormattable
{
    public long Cents;

    public String ToText(String format) =>
        format == "short" ? "$" + Text.FromInteger(Cents / 100) : Text.FromInteger(Cents) + " cents";
}

int Main()
{
    Money price;
    price.Cents = 1234;
    Console.WriteLine($"{price} or {price:short}");
    return 0;
}
