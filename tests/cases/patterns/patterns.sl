// SPDX-License-Identifier: 0BSD
//
// A `case` label that is not a constant: a range, a type, a `when`, an `or`.
// A switch whose labels are all constants is still one LLVM `switch` and a
// jump table; one with a pattern in it becomes a chain of tests, asked in
// order, and everything else about the statement is unchanged -- sections that
// may not fall through, `break` that belongs to the switch, `continue` that
// passes through it to the loop.
module Patterns;

import Standard.Console;
import Standard.Text;

public class Node { public int Id = 1; }
public class Leaf : Node { public int Value = 4; }
public class Twig : Node { }

public variant Shape
{
    Circle(double Radius);
    Rect(double Width, double Height);
    Empty;
}

String Classify(int n)
{
    switch (n)
    {
        case < 0:        return "negative";
        case 0:          return "zero";
        case 1 or 2:     return "small";
        case < 10:       return "medium";
        case > 100:      return "huge";
        default:         return "large";
    }
}

String Kind(Node node)
{
    switch (node)
    {
        case Leaf leaf when leaf.Value > 3:
            return "big leaf " + Text.FromInteger(leaf.Value);

        case Leaf leaf:
            return "leaf " + Text.FromInteger(leaf.Value);

        case Twig:
            return "twig";

        default:
            return "node";
    }
}

String Area(Shape shape)
{
    switch (shape)
    {
        case Circle c when c.Radius > 10.0:
            return "big circle";

        case Circle c:
            return "circle " + Text.FromDouble(c.Radius);

        case Rect r:
            return "rect " + Text.FromDouble(r.Width * r.Height);

        case Empty:
            return "empty";
    }
}

/// A String switch is a chain of comparisons already, and a pattern over one
/// is the same chain asking a little more.
String Word(String text)
{
    switch (text)
    {
        case "a" or "b": return "letter";
        case "1":        return "digit";
        default:         return "other";
    }
}

/// `and` and `not` over the same value, which is what makes a range readable.
String Range(int n)
{
    switch (n)
    {
        case > 0 and < 10: return "single digit";
        case not 0:        return "other";
        default:           return "zero";
    }
}

int Main()
{
    Console.WriteLine(Word("a"));
    Console.WriteLine(Word("1"));
    Console.WriteLine(Word("z"));

    Console.WriteLine(Range(5));
    Console.WriteLine(Range(50));
    Console.WriteLine(Range(0));

    Console.WriteLine(Classify(-1));
    Console.WriteLine(Classify(0));
    Console.WriteLine(Classify(2));
    Console.WriteLine(Classify(5));
    Console.WriteLine(Classify(50));
    Console.WriteLine(Classify(500));

    Console.WriteLine(Kind(new Leaf()));
    Console.WriteLine(Kind(new Twig()));
    Console.WriteLine(Kind(new Node()));

    Console.WriteLine(Area(Circle(20.0)));
    Console.WriteLine(Area(Circle(1.5)));
    Console.WriteLine(Area(Rect(2.0, 3.0)));
    Console.WriteLine(Area(Empty()));

    // break still belongs to the switch, and continue to the loop.
    int total = 0;

    for (int i = 0; i < 6; i++)
    {
        switch (i)
        {
            case < 2:  continue;
            case 4:    break;
            default:   total += i; break;
        }

        total += 100;
    }

    Console.WriteLine(Text.FromInteger(total));
    return 0;
}
