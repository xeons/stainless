// SPDX-License-Identifier: 0BSD
// A member named for its own enum type — C#'s Color Color. `Color.Red` names
// the enum's member wherever a value called `Color` is also in scope, since a
// value of that type has no member of that name to reach.
module EnumNamedLikeMember;

import Standard.Console;

public enum Color { Red, Green, Blue }

public struct Pen
{
    private Color _color;

    public Pen(Color color) => _color = color;

    public Color Color => _color;

    public bool IsRed => _color == Color.Red;

    public String Describe()
    {
        switch (_color)
        {
            case Color.Red: return "red";
            case Color.Green: return "green";
            default: return "blue";
        }
    }
}

public class Brush
{
    public Color Color;

    public Brush() => Color = Color.Blue;
}

String DescribeLocal(Color Color)
{
    if (Color == Color.Green)
        return "a green parameter";
    return "another parameter";
}

int Main()
{
    var pen = new Pen(Color.Red);
    Console.WriteLine($"{pen.Describe()} {pen.IsRed}");
    Console.WriteLine(new Pen(Color.Green).Describe());
    Console.WriteLine(new Brush().Color == Color.Blue ? "a blue brush" : "wrong");
    Console.WriteLine(DescribeLocal(Color.Green));
    return 0;
}
