// SPDX-License-Identifier: 0BSD
//
// `{value,alignment:format}`: .NET's standard numeric formats, padding to a
// width, and a class that writes itself through `IFormattable`.
module InterpolationFormat;

import Standard.Console;
import Standard.Collections;

public class Money : IFormattable
{
    long _cents;

    public Money(long cents)
    {
        _cents = cents;
    }

    public long Cents => _cents;

    public virtual String ToText(String format)
    {
        if (format == "whole")
            return $"{_cents / 100}";
        return $"${_cents / 100:N0}.{_cents % 100:D2}";
    }
}

public class Refund : Money
{
    public Refund(long cents) : base(cents)
    {
    }

    public override String ToText(String format) => $"-{base.ToText(format)}";
}

public struct Reading
{
    public int Sensor;
    public double Value;
}

String ShowAll<T>(List<T> items) where T : IFormattable
{
    var built = new StringBuilder();
    foreach (var item in items)
        built.Append($"[{item,8:whole}]");
    return built.ToText();
}

public interface IText { String Produce(); }

const int Wide = 12;

int Main()
{
    int n = 255;
    int negative = -1;
    sbyte small = -2;
    long big = 1234567;
    ulong huge = 18446744073709551615u;

    Console.WriteLine($"{n:D} {n:D6} {-n:D6} {n:X} {n:x4} {negative:X} {small:X} {(long)negative:X}");
    Console.WriteLine($"{n:B} {n:B12} {big:N} {big:N0} {-big:N2} {big:F1} {huge:N0}");
    Console.WriteLine($"{big:E2} {big:e} {big:G} {big:G3}");

    double pi = 3.14159265358979;
    Console.WriteLine($"{pi:F} {pi:F0} {pi:F4} {pi:N3} {pi:E} {pi:e3} {pi:G} {pi:G3}");
    Console.WriteLine($"{1234567.891:N2} {0.000012345:G3} {1e20:F0} {-0.001:F2}");
    Console.WriteLine($"{0.125:F2} {2.5:F0} {-2.5:F0} {0.5:F0} {9.995:F2} {99.95:F1}");
    Console.WriteLine($"{1.5f:F3} {0.0:E2} {-0.0:F1} {123456789.0:G4} {0.0001:G}");

    // Alignment: right with a positive width, left with a negative one, and
    // counted in characters rather than bytes.
    Console.WriteLine($"[{n,6}] [{n,-6}] [{pi,10:F3}] [{"é",3}] [{true,-6}] [{n,Wide:X}]");
    Console.WriteLine($"[{"wider than the width",4}] [{(n > 100 ? "big" : "small"),-7}]");

    // Verbatim and raw interpolations format the same way.
    Console.WriteLine($@"{n:X4}\{n,4}");
    Console.WriteLine($$"""{{{n:X}}} {{pi:F1}}""");

    // A class writes itself, through the interface, so an override is what
    // answers; it is handed the format, or "" when there is none.
    Money price = new Money(123456);
    Money back = new Refund(250);
    Console.WriteLine($"{price} {price:whole} [{price,12}] {back} {back:whole}");

    var wallet = new List<Money>();
    wallet.Add(new Money(100));
    wallet.Add(new Refund(4200));
    Console.WriteLine(ShowAll(wallet));

    Reading reading;
    reading.Sensor = 7;
    reading.Value = 21.456;
    Console.WriteLine($"sensor {reading.Sensor:D3}: {reading.Value,8:F1}");

    // Captured into a closure, formatted when it runs.
    int count = 3;
    IText later = () => $"{count:D4}|{price:whole}";
    Console.WriteLine(later.Produce());

    // The library functions the holes lower to, called directly.
    Console.WriteLine(Text.FormatInteger(48879L, "X") + " " + Text.FormatDouble(2.0 / 3.0, "F3") +
                      " [" + Text.AlignText("ab", -4) + "]");
    return 0;
}
