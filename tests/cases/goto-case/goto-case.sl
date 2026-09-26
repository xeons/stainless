// SPDX-License-Identifier: 0BSD
//
// `goto case` and `goto default`: a jump to another section of the switch
// the jump is in, named by its constant label.
//
// A section that ends in one does not fall through, and what the section
// declared is released on the way out, as it is for `break`.
module GotoCase;

import Standard.Console;

class Tag
{
    public String Name;
    public Tag(String name)
    {
        Name = name;
        Console.WriteLine($"  + {name}");
    }
    ~Tag() { Console.WriteLine($"  - {Name}"); }
}

struct Held
{
    public Tag Inside;
    public int Count;
}

enum Light { Red, Amber, Green }

/// Forwards and backwards, to a case and to the default.
String Describe(int n)
{
    String text = "";

    switch (n)
    {
        case 0:
            text = text + "zero ";
            goto case 1;
        case 1:
            text = text + "small ";
            goto default;
        case 5:
            var held = new Tag("five");
            text = text + held.Name + " ";
            goto case 0;
        default:
            text = text + "done";
            break;
    }

    return text;
}

/// The constant converts to the governing type, as a label's does.
String Next(Light light)
{
    switch (light)
    {
        case Light.Red: return "stop";
        case Light.Amber: goto case Light.Red;
        default: return "go";
    }
}

int Number(String word)
{
    switch (word)
    {
        case "one": return 1;
        case "uno": goto case "one";
        case "two": return 2;
        default: return 0;
    }
}

/// Among patterns, a constant label is still somewhere to land.
String Classify(int n)
{
    switch (n)
    {
        case 3: return "three";
        case > 10: goto case 3;
        case int k when k < 0: goto default;
        default: return "other";
    }
}

/// A state machine whose sections hand on to each other, holding a
/// reference and a struct of one as they go.
void Machine()
{
    int steps = 0;

    switch (steps)
    {
        case 0:
            var step = new Tag($"step {steps}");
            Held pair;
            pair.Inside = new Tag($"pair {steps}");
            steps++;
            if (steps < 3)
                goto case 0;
            goto case 1;
        case 1:
            var last = new Tag("last");
            break;
    }

    Console.WriteLine($"  steps {steps}");
}

/// A loop that only ends by returning needs nothing after it.
int OnlyOnce()
{
    do
    {
        return 7;
    }
    while (true);
}

public int Main()
{
    Console.WriteLine(Describe(0));
    Console.WriteLine(Describe(1));
    Console.WriteLine(Describe(5));
    Console.WriteLine(Describe(9));
    Console.WriteLine($"{Next(Light.Amber)} {Next(Light.Green)}");
    Console.WriteLine($"{Number("uno")} {Number("two")} {Number("three")}");
    Console.WriteLine($"{Classify(3)} {Classify(12)} {Classify(-4)} {Classify(7)}");
    Console.WriteLine("machine:");
    Machine();
    Console.WriteLine($"once {OnlyOnce()}");
    return 0;
}
