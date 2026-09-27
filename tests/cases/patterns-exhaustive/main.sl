// SPDX-License-Identifier: 0BSD
//
// A switch expression needs no `_` where its arms already cover every value:
// both bools, every case of a variant, every member of an enum, and the same
// again inside a tuple, a payload or a member. A statement switch that covers
// everything ends the function as a `default` would.
module PatternsExhaustive;

import Standard.Console;
import Standard.Text;

public enum Color { Red, Green, Blue }

public variant Shape
{
    Circle(double Radius);
    Rect(double Width, double Height);
    Empty;
}

String Paint(Color color) => color switch
{
    Color.Red => "red",
    Color.Green => "green",
    Color.Blue => "blue",
};

String Both(bool a, bool b) => (a, b) switch
{
    (true, true) => "both",
    (true, false) => "the first",
    (false, _) => "not the first",
};

String Flagged(Shape shape, bool flag) => (shape, flag) switch
{
    (Circle(var r), true) => "flagged circle " + Text.FromDouble(r),
    (Circle, false) => "circle",
    (Rect { Width: 0.0 }, _) => "flat rect",
    (Rect, _) => "rect",
    (Empty, _) => "empty",
};

/// `not` leaves every other case, which the next arm then covers.
String NotACircle(Shape shape) => shape switch
{
    not Circle => "not a circle",
    Circle c => "circle " + Text.FromDouble(c.Radius),
};

String Warmth(Color color) => color switch
{
    Color.Red or Color.Green => "warm enough",
    Color.Blue => "cold",
};

/// Every length: none, one, and one followed by any number more.
int Count(Span<int> items) => items switch
{
    [] => 0,
    [_] => 1,
    [_, .. var rest] => 1 + Count(rest),
};

String Sign(bool negative)
{
    switch (negative)
    {
        case true when false:
            return "never";
        case true:
            return "minus";
        case false:
            return "plus";
    }
}

int Main()
{
    Console.WriteLine(Paint(Color.Blue));
    Console.WriteLine(Both(true, false));
    Console.WriteLine(Both(false, true));
    Console.WriteLine(Flagged(Shape.Circle(2.0), true));
    Console.WriteLine(Flagged(Shape.Circle(2.0), false));
    Console.WriteLine(Flagged(Shape.Rect(0.0, 3.0), false));
    Console.WriteLine(Flagged(Shape.Rect(1.0, 3.0), true));
    Console.WriteLine(Flagged(Shape.Empty, false));
    Console.WriteLine(NotACircle(Shape.Empty));
    Console.WriteLine(NotACircle(Shape.Circle(1.5)));
    Console.WriteLine(Warmth(Color.Green));
    int[] numbers = [5, 6, 7];
    Console.WriteLine(Text.FromInteger(Count(numbers[:])));
    Console.WriteLine(Sign(true));
    Console.WriteLine(Sign(false));
    return 0;
}
