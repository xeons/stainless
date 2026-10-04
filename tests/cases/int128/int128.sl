// int128 and uint128: arithmetic past 64 bits, the conversions to and from
// the narrower integers and the floats, division (a runtime call on every
// target), and formatting.
module Int128;

import Standard.Console;

int128 Factorial(int n)
{
    int128 product = 1;
    for (int i = 2; i <= n; i++)
        product = product * i;
    return product;
}

int Main()
{
    // 30! is past ulong's 1.8e19.
    Console.WriteLine($"30! = {Factorial(30)}");

    // The extremes, built by shifting, as C builds them.
    uint128 most = ~(uint128)0;
    int128 highest = (int128)(most >> 1);
    int128 lowest = -highest - 1;
    Console.WriteLine($"uint128 max = {most}");
    Console.WriteLine($"int128 max = {highest}");
    Console.WriteLine($"int128 min = {lowest}");

    // Division and remainder, signed and unsigned.
    int128 big = Factorial(25);
    Console.WriteLine($"25! / 1000003 = {big / 1000003}, remainder {big % 1000003}");
    Console.WriteLine($"-7 / 2 = {(int128)(-7) / 2}, -7 % 2 = {(int128)(-7) % 2}");
    Console.WriteLine($"max / 3 = {most / 3}");

    // Narrower integers widen to it on their own; it narrows by a cast.
    long small = -42;
    int128 widened = small;
    ulong low = (ulong)(most >> 64);
    Console.WriteLine($"widened {widened}, high half {low}, low int {(int)Factorial(20)}");

    // Floats both ways.
    double approximate = (double)Factorial(30);
    int128 back = (int128)1.5e20;
    Console.WriteLine($"30! as double {approximate > 2.65e32 && approximate < 2.66e32}, 1.5e20 back {back}");

    // Wraparound and comparison.
    uint128 wrapped = most + 1;
    Console.WriteLine($"max + 1 = {wrapped}, ordered {lowest < 0 && highest > (int128)(~0UL)}");
    return 0;
}
