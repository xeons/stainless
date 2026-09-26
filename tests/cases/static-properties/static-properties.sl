// SPDX-License-Identifier: 0BSD
//
// A static automatic property: two static accessors over a static that
// nothing else can name. With no `= value` it starts as its type's zero, which
// a global is born holding; with one, it is ordered with every other static.
module StaticProperties;

import Standard.Console;
import Standard.Text;

public class Node
{
    public String Name;

    public Node(String name)
    {
        Name = name;
    }

    ~Node()
    {
        Console.WriteLine("released " + Name);
    }
}

public static class Registry
{
    static int s_hidden = 4;

    public static int Count { get; set; }
    public static String Label { get; set; } = "registry";
    public static Node? Last { get; private set; }

    /// Written once, by the static constructor.
    public static int Fixed { get; }

    public static int Doubled => Count * 2;

    public static int Hidden
    {
        get => s_hidden;
        set => s_hidden = value;
    }

    static Registry()
    {
        Fixed = 42;
    }

    public static void Remember(String name) => Last = new Node(name);
}

public struct Point
{
    public int X;

    public static int Made { get; set; } = 3;
}

public class Tally<T>
{
    public static int Seen { get; set; }

    public T Value;

    public Tally(T value)
    {
        Value = value;
        Seen++;
    }
}

/// Reads a static property in its initializer, so it is ordered after it.
public static class Greetings
{
    public static String Greeting = Registry.Label + "!";
}

/// A property whose storage is filled on first use, through `field`.
public static class Cache
{
    public static Node Shared { get => field ??= new Node("shared"); }
}

int Main()
{
    Console.WriteLine(Text.FromInteger(Registry.Count) + " " + Registry.Label + " " + Greetings.Greeting);

    Registry.Count = 5;
    Registry.Count++;
    Registry.Count += 2;
    Console.WriteLine(Text.FromInteger(Registry.Count) + " " + Text.FromInteger(Registry.Doubled));
    Console.WriteLine(Text.FromInteger(Registry.Fixed));

    Registry.Remember("first");
    Registry.Remember("second");
    Console.WriteLine(Registry.Last?.Name ?? "none");

    Registry.Hidden = 9;
    Point.Made *= 2;
    Console.WriteLine(Text.FromInteger(Registry.Hidden) + " " + Text.FromInteger(Point.Made));

    var a = new Tally<int>(1);
    var b = new Tally<int>(2);
    var c = new Tally<String>("c");
    Console.WriteLine(Text.FromInteger(Tally<int>.Seen) + " " + Text.FromInteger(Tally<String>.Seen));

    Console.WriteLine(Cache.Shared.Name + " " + Cache.Shared.Name);
    return 0;
}
