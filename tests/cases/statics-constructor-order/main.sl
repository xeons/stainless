// SPDX-License-Identifier: 0BSD
//
// A type is set up as a unit: its own field initializers in order, then its
// static constructor. Anything reading one of its statics -- an initializer in
// another type, a module-level static, another type's static constructor --
// runs after both, and so sees what the constructor arranged.
module StaticsConstructorOrder;

import Standard.Console;
import Standard.Collections;

class Config
{
    public static int Base = 1;

    // Its own type's initializer runs before the constructor, as in C#.
    public static int Early = Base * 2;
    public static List<String> Names = new List<String>();

    static Config()
    {
        Base = 40;
        Names.Add("config");
    }
}

class User
{
    public static int Derived = Config.Base + 2;
    public static int Count = 0;

    // Reads Config's statics, so Config is set up first.
    static User()
    {
        Count = (int)Config.Names.Count;
        Config.Names.Add("user");
    }
}

// Written before the types it reads, and still run after them.
static readonly int s_top = Config.Base + User.Derived;

public int Main()
{
    Console.WriteLine($"config   {Config.Base} {Config.Early}");
    Console.WriteLine($"user     {User.Derived} {User.Count}");
    Console.WriteLine($"module   {s_top}");
    Console.WriteLine($"names    {Config.Names.Count} {Config.Names[1]}");
    return 0;
}
