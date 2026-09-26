// SPDX-License-Identifier: 0BSD
//
// Inside a type, a static's initializer names the type's other statics, its
// constants and its static methods bare, as the type's methods do -- and so
// does a lambda written in the type, whose own class is not the one the names
// belong to.
module StaticsBareNames;

import Standard.Console;

public closure int IntFn(int x);

class Tuning
{
    const int Scale = 3;
    public static int Seed = Compute(2);
    public static int Next = Seed + Scale;
    public static IntFn Apply = (int x) => x * Scale + Seed;

    static int Compute(int value) => value * Scale;

    public static IntFn Make() => (int x) => x + Next;
}

public int Main()
{
    Console.WriteLine($"seed  {Tuning.Seed} {Tuning.Next}");
    Console.WriteLine($"apply {Tuning.Apply(1)} {Tuning.Make()(1)}");
    return 0;
}
