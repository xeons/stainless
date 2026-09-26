// SPDX-License-Identifier: 0BSD
//
// A bare `default`, which is `default(T)` with the `T` taken from where the
// value is going: a declared local, a return, an argument, a parameter's
// default, a comparison's other side, a cast and a conditional's other arm.
module DefaultLiteral;

import Standard.Console;

class Node
{
    public String Name;

    public Node(String name)
    {
        Name = name;
    }
}

struct Pair
{
    public int Left;
    public int Right;
}

int ReturnsZero() => default;

Node? ReturnsNothing()
{
    return default;
}

T Blank<T>() => default;

bool IsBlank<T>(T value) where T : class => value == default;

int Bumped(int start = default) => start + 1;

String Describe(Node? node) => node?.Name ?? "nothing";

public int Main()
{
    int number = default;
    double real = default;
    bool truth = default;
    Pair pair = default;
    Node? node = default;
    Console.WriteLine($"a {number} {real} {truth} {pair.Left + pair.Right} {node == null}");

    Console.WriteLine($"b {ReturnsZero()} {ReturnsNothing() == null} {Blank<long>()}");
    Console.WriteLine($"c {Bumped()} {Bumped(4)} {Describe(default)}");

    Node named = new Node("named");
    Node? held = named;
    Console.WriteLine($"d {number == default} {held == default} {IsBlank<Node>(named)}");

    long wide = (long)default;
    bool flag = true;
    int chosen = flag ? default : 5;
    int other = !flag ? default : 5;
    Console.WriteLine($"e {wide} {chosen} {other}");

    number = 7;
    number = default;
    Console.WriteLine($"f {number}");
    return 0;
}
