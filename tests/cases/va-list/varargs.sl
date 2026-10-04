// Variadic functions defined here, read with a VaList: called from C past
// every register the conventions have, called from here with promotions, and
// a list handed on to C's own va_arg and vsnprintf.
module VaListCase;

import Standard.Console;

extern "C"
{
    long call_sum();
    double call_mixed();
    long call_forward();
    long c_vsum(int count, VaList args);
    int c_format(byte* buffer, nuint size, byte* format, VaList args);
}

export "C" long sl_sum(int count, ...)
{
    VaList args = VaList.Start();
    long total = 0;
    for (int i = 0; i < count; i++)
        total = total * 10 + args.Next<int>() % 10;
    return total;
}

export "C" double sl_mixed(int count, ...)
{
    VaList args = VaList.Start();
    double total = 0;
    for (int i = 0; i < count; i++)
    {
        long whole = args.Next<long>();
        double part = args.Next<double>();
        total = total + whole * part;
    }
    return total;
}

export "C" long sl_forward(int count, ...)
{
    VaList args = VaList.Start();
    return c_vsum(count, args);
}

// Not exported: a variadic Stainless calls itself.
String Describe(byte* label, int count, ...)
{
    VaList args = VaList.Start();
    String text = "";
    for (int i = 0; i < count; i++)
        text = text + $" {args.Next<double>()}";
    return text;
}

int Format(byte* buffer, nuint size, byte* format, ...)
{
    VaList args = VaList.Start();
    return c_format(buffer, size, format, args);
}

int Main()
{
    Console.WriteLine($"twelve from C: {call_sum()}");
    Console.WriteLine($"mixed from C: {call_mixed()}");
    Console.WriteLine($"handed on to va_arg: {call_forward()}");

    float quarter = 0.25f;
    Console.WriteLine($"promoted here:{Describe(null, 3, quarter, 1.5, 2.0)}");

    byte[] buffer = new byte[64];
    int written = Format(&buffer[0], 64, "%d and %.2f and %s", 42, 3.14159, "text");
    Console.WriteLine($"vsnprintf: {written} '{Text.FromNullTerminated(&buffer[0])}'");
    return 0;
}
