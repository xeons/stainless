// SPDX-License-Identifier: 0BSD
//
// An initializer is run after every static it reads, wherever in it the read
// is: inside an interpolated string, an array literal, a case's arguments, or
// a loop or a switch of a static constructor. Each static here is written
// before the one it reads.
module StaticsReadInside;

import Standard.Console;

static String s_greeting = $"hello {s_name}";
static int[] s_numbers = [s_count, s_count + 1];
static Optional<int> s_maybe = Optional<int>.Some(s_count * 2);
static int s_looped = Looped.Total;

class Looped
{
    public static int Total = 0;

    static Looped()
    {
        int i = 0;
        do
        {
            Total += s_count;
            i++;
        }
        while (i < 2);

        switch (s_name.ByteLength())
        {
            case 5:
                Total += s_limit;
                break;
        }
    }
}

static String s_name = Named();
static int s_count = Counted();
static int s_limit = Counted() * 10;

String Named() => "world";
int Counted() => 41;

public int Main()
{
    Console.WriteLine(s_greeting);
    Console.WriteLine($"{s_numbers[0]} {s_numbers[1]}");
    if (s_maybe is Some value)
        Console.WriteLine($"{value.Value}");
    Console.WriteLine($"{s_looped}");
    return 0;
}
