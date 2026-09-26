// SPDX-License-Identifier: 0BSD
//
// A static holding a closure or a delegate is called by its name, as a local
// or a field holding one is: bare, through the type that owns it, and through
// the module.
module ClosureStatics;

import Standard.Console;
import ClosureLibrary;

public delegate int Plain(int x);

int Tripled(int x) => x * 3;

static IntFn s_tripled = Tripled;
static Plain s_plain = Tripled;

class Local
{
    public static IntFn Handler = (int x) => x - 1;
    public static Plain Raw = Tripled;

    public static int CallBare() => Handler(10);
}

public int Main()
{
    Console.WriteLine($"bare      {s_tripled(4)} {s_plain(5)} {s_doubled(21)}");
    Console.WriteLine($"type      {Local.Handler(2)} {Local.Raw(3)} {Handlers.Offset(1)}");
    Console.WriteLine($"module    {ClosureLibrary.s_doubled(4)} {ClosureLibrary.Handlers.Offset(2)}");
    Console.WriteLine($"inside    {Local.CallBare()}");

    // Reassigned, and called again through the same name.
    s_tripled = (int x) => x + 1;
    Console.WriteLine($"replaced  {s_tripled(4)}");
    return 0;
}
