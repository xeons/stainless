// SPDX-License-Identifier: 0BSD
//
// What a value cannot be taken apart as.
module Bad;

public class Node
{
    public int Value;
    public int Twice() => Value * 2;
}

public variant Shape
{
    Circle(double Radius);
    Empty;
}

// SL0774: a list pattern wants a length and elements to read by index.
String NotAList(Node node) => node switch
{
    [1] => "one",
    _ => "other",
};

// SL0775: one '..' at most, and only inside a list pattern.
String TwoRuns(int[] items) => items switch
{
    [.., 1, ..] => "one somewhere",
    _ => "other",
};

String Stray(int n) => n switch
{
    .. => "anything",
};

// SL0775: what '..' skipped is a slice, which only an array or a slice has.
String RunOfAnInline(in int[3] items) => items switch
{
    [1, .. var rest] => "starts with one",
    _ => "other",
};

// SL0776: a property pattern reads a field or a property, not a method.
String Method(Node node) => node switch
{
    { Twice: 4 } => "two",
    _ => "other",
};

// SL0776: a name in a position says which element it is.
String WrongName((int, int) pair) => pair switch
{
    (Item1: 1, Second: 2) => "one, two",
    _ => "other",
};

// SL0609: as many positions as the value has.
String TooMany((int, int) pair) => pair switch
{
    (1, 2, 3) => "three",
    _ => "other",
};

String PayloadCount(Shape shape) => shape switch
{
    Circle(var r, var extra) => "circle",
    _ => "other",
};

// SL0619: a name under 'not' in an arm is never assigned where the arm runs.
String NamedUnderNot(Shape shape) => shape switch
{
    not Circle c => "not",
    _ => "other",
};

// SL0639: what a variant holds depends on its case, so the case comes first.
String NoCase(Shape shape) => shape switch
{
    { Radius: > 1.0 } => "large",
    _ => "other",
};

// SL0637: every arm of a switch expression is a value.
void Nothing() { }

void NoValue(int n)
{
    var none = n switch
    {
        _ => Nothing(),
    };
}

public int Main() => 0;
