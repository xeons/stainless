// SPDX-License-Identifier: 0BSD
//
// A value taken apart by a pattern: by member, `{ X: 0, Owner.Name: "a" }`;
// by position, through a tuple's elements, a case's payload or a
// `Deconstruct`; and `var`, which names whatever is there. Each part is read
// once, and only after what it is part of is known to be there.
module PatternsRecursive;

import Standard.Console;
import Standard.Text;

public struct Point
{
    public int X;
    public int Y;

    public Point(int x, int y)
    {
        X = x;
        Y = y;
    }

    public void Deconstruct(out int x, out int y)
    {
        x = X;
        y = Y;
    }
}

public class Owner
{
    public String Name;
    public Owner(String name) { Name = name; }
}

public class Pet
{
    public Owner? Keeper;
    public int Age;

    public Pet(Owner? keeper, int age)
    {
        Keeper = keeper;
        Age = age;
    }

    public int Legs => 4;
}

public variant Tree
{
    Leaf(int Value);
    Node(int Left, int Right);
    Empty;
}

String Where(Point p) => p switch
{
    (0, 0) => "origin",
    (0, var y) => "on the y axis at " + Text.FromInteger(y),
    (var x, 0) => "on the x axis at " + Text.FromInteger(x),
    { X: > 0, Y: > 0 } => "first quadrant",
    Point(< 0, _) => "left half",
    _ => "below",
};

String Kind(Tree tree) => tree switch
{
    Leaf(> 10) => "big leaf",
    Leaf(var v) => "leaf " + Text.FromInteger(v),
    Node { Left: 0 } => "node with nothing on the left",
    Node(var left, var right) => "node " + Text.FromInteger(left + right),
    Empty => "empty",
};

String Pair((int, String) pair) => pair switch
{
    (1, "a") => "one and a",
    (1, _) => "one",
    (Item1: var n, Item2: var s) => Text.FromInteger(n) + " and " + s,
};

/// `Keeper.Name` asks that the keeper is there before it asks its name.
String Whose(Pet pet) => pet switch
{
    { Keeper.Name: "ann", Age: < 2, Legs: 4 } => "ann's puppy",
    { Keeper.Name: "ann" } => "ann's",
    { Keeper: null } => "a stray",
    { Keeper: { } someone } => someone.Name + "'s",
};

/// In a generic function, against whatever T turned out to be.
String Both<T>((T, T) pair, T wanted)
{
    if (pair is (var first, var second) && first == wanted && second == wanted)
        return "both";
    return "not both";
}

int Main()
{
    Console.WriteLine(Where(new Point(0, 0)));
    Console.WriteLine(Where(new Point(0, 5)));
    Console.WriteLine(Where(new Point(7, 0)));
    Console.WriteLine(Where(new Point(1, 1)));
    Console.WriteLine(Where(new Point(-1, 1)));
    Console.WriteLine(Where(new Point(1, -1)));

    Console.WriteLine(Kind(Tree.Leaf(20)));
    Console.WriteLine(Kind(Tree.Leaf(3)));
    Console.WriteLine(Kind(Tree.Node(0, 4)));
    Console.WriteLine(Kind(Tree.Node(2, 4)));
    Console.WriteLine(Kind(Tree.Empty));

    Console.WriteLine(Pair((1, "a")));
    Console.WriteLine(Pair((1, "b")));
    Console.WriteLine(Pair((2, "z")));

    Console.WriteLine(Whose(new Pet(new Owner("ann"), 1)));
    Console.WriteLine(Whose(new Pet(new Owner("ann"), 5)));
    Console.WriteLine(Whose(new Pet(null, 3)));
    Console.WriteLine(Whose(new Pet(new Owner("bo"), 3)));

    Console.WriteLine(Both((2, 2), 2));
    Console.WriteLine(Both(("x", "y"), "x"));

    // A statement switch takes the same patterns, with a guard that reads
    // what the label named, and narrows a name it settles.
    Tree tree = Tree.Node(3, 4);
    switch (tree)
    {
        case Node(var l, _) when l > 5:
            Console.WriteLine("heavy on the left");
            break;
        case Node:
            Console.WriteLine("node, right is " + Text.FromInteger(tree.Right));
            break;
        default:
            Console.WriteLine("not a node");
            break;
    }

    // `var (a, b)` over a tuple, and a name for the whole.
    var point = (4, 5);
    if (point is var (a, b) && a < b)
        Console.WriteLine(Text.FromInteger(a) + " before " + Text.FromInteger(b));

    // A closure takes what the pattern named by value, as it takes anything.
    var pet = new Pet(new Owner("cy"), 2);
    if (pet is { Keeper: Owner keeper })
    {
        var greet = () => "hello " + keeper.Name;
        Console.WriteLine(greet());
    }

    return 0;
}
