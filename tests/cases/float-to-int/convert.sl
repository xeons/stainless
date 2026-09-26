// SPDX-License-Identifier: 0BSD
//
// A float to an integer truncates toward zero, and a value that no integer of
// the target holds saturates to the nearest end, NaN becoming zero -- what
// .NET does on x64. Inside `checked` the same casts abort instead, so only the
// ones that fit are run there.
module FloatToInt;

import Standard.Console;

// Computed, so that nothing is folded before the conversion is emitted.
double Scaled(double scale) => 1e19 * scale;
double Zero() => 0.0;
double NotANumber() => 0.0 / Zero();
float Single(float value) => value;

public int Main()
{
    Console.WriteLine($"int high   {(int)Scaled(1)}");
    Console.WriteLine($"int low    {(int)Scaled(-1)}");
    Console.WriteLine($"int nan    {(int)NotANumber()}");
    Console.WriteLine($"long high  {(long)Scaled(1)}");
    Console.WriteLine($"long low   {(long)Scaled(-1)}");
    Console.WriteLine($"ulong      {(ulong)Scaled(1)}");
    Console.WriteLine($"ulong neg  {(ulong)Scaled(-1)}");
    Console.WriteLine($"uint neg   {(uint)Scaled(-1)}");
    Console.WriteLine($"byte high  {(byte)Scaled(1)}");
    Console.WriteLine($"short low  {(short)Scaled(-1)}");
    Console.WriteLine($"float      {(int)Single(3e9f)}");
    Console.WriteLine($"truncates  {(int)(-2.9)}");

    // In range, so checked has nothing to say.
    checked
    {
        double edge = -2147483648.9;
        Console.WriteLine($"edge       {(int)edge}");
        double below = -0.9;
        Console.WriteLine($"toward 0   {(uint)below}");
        long fits = 255;
        Console.WriteLine($"narrow     {(byte)fits}");
        int positive = 7;
        Console.WriteLine($"sign       {(ulong)positive}");
        byte small = 250;
        small += 5;
        Console.WriteLine($"compound   {small}");
        int m = -2147483647;
        Console.WriteLine($"negate     {-m}");
    }

    // Outside it, the same shapes wrap.
    long wide = 300;
    Console.WriteLine($"wraps      {(byte)wide}");
    int least = -2147483648;
    Console.WriteLine($"negates    {-least}");
    return 0;
}
