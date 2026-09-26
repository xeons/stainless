// SPDX-License-Identifier: 0BSD
//
// What a lambda may say about itself: that it captures nothing, what it
// returns, what a parameter defaults to, and which parameters it ignores.
module LambdaExtras;

import Standard.Collections;
import Standard.Console;
import Standard.Text;

public closure int Transform(int value);
public closure int Pair(int a, int b);
public delegate int Plain(int value);

class Node
{
    public int Value;
    public Node(int value) => Value = value;
}

int Apply(Transform transform, int value) => transform(value);

int Main()
{
    // `static` captures nothing, so it may become a delegate.
    Transform twice = static x => x * 2;
    Plain plain = static (int x) => x + 1;
    Console.WriteLine(Text.FromInteger(twice(21)) + " " + Text.FromInteger(plain(1)));

    // A result written out: a type of its own for `var`, and what settles a
    // body whose value would not say.
    var tripled = int (int x) => x * 3;
    var maybe = Node? (bool make) => make ? new Node(5) : null;
    Console.WriteLine(Text.FromInteger(tripled(3)));
    Console.WriteLine(maybe(true) is Node ? "node" : "none");
    Console.WriteLine(maybe(false) is Node ? "node" : "none");
    Console.WriteLine(Text.FromInteger(Apply(int (x) => x - 1, 10)));

    // A block body's result is what its returns agree on.
    var magnitude = (int x) => { if (x > 0) { return x; } return -x; };
    var widened = (bool big) => { if (big) { return 1L << 40; } return 1; };
    var named = (int x) => { return "n" + Text.FromInteger(x); };
    Console.WriteLine(Text.FromInteger(magnitude(-4)) + " " + Text.FromInteger(widened(true)));
    Console.WriteLine(named(7));

    // And a body that returns nothing is a closure returning nothing.
    var say = (String text) => { Console.WriteLine("say " + text); };
    var shout = (String text) => Console.WriteLine(text.ToUpperAscii());
    say("hi");
    shout("hi");

    // A default is part of the lambda's own type, so a call through it may
    // leave the parameter out.
    var area = (int width = 10, int height = 2) => width * height;
    var greet = (String who = "world") => "hello " + who;
    Console.WriteLine(Text.FromInteger(area()) + " " + Text.FromInteger(area(3)) + " " +
                      Text.FromInteger(area(3, 3)));
    Console.WriteLine(greet() + ", " + greet("you"));

    // A name reaches the parameter the signature calls that, past a default.
    Console.WriteLine(Text.FromInteger(area(height: 5)));
    Pair minus = (a, b) => a - b;
    Console.WriteLine(Text.FromInteger(minus(b: 1, a: 5)));

    // Two `_` are discards; one is still a name.
    Pair ignored = (_, _) => 0;
    Pair first = (a, _) => a;
    Transform same = _ => _ + 1;
    Console.WriteLine(Text.FromInteger(ignored(1, 2)) + " " + Text.FromInteger(first(7, 2)) +
                      " " + Text.FromInteger(same(1)));

    // Capture is by value, in a block body with a written result as anywhere.
    int factor = 4;
    var scaled = int (int x) => { return x * factor; };
    factor = 100;
    Console.WriteLine(Text.FromInteger(scaled(2)));

    // A cast is a target like any other.
    Console.WriteLine(Text.FromInteger(((Transform)(y => y * factor))(2)));
    Console.WriteLine(Text.FromInteger(((Plain)(static y => y + 1))(2)));

    // A generic's result is read off a block body's returns, too.
    int[] numbers = [1, 2, 3];
    var labels = numbers.Select(n => { if (n > 1) { return "many"; } return "one"; }).ToArray();
    Console.WriteLine(labels[0] + " " + labels[2]);
    return 0;
}
