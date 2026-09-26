// SPDX-License-Identifier: 0BSD
//
// Functions declared in a block. What one reads of the function around it is
// passed at every call, by value: it sees each variable as it stands when it
// is called, and one that reads nothing is a plain function.
module LocalFunctions;

import Standard.Collections;
import Standard.Console;
import Standard.Text;

public closure int Transform(int value);
public delegate int Plain(int value);

class Tally
{
    int _count = 10;
    String _label = "tally";

    public Tally() => Bump(5);

    // The object is reached through `this`, which is read live.
    public int Scaled(int by)
    {
        int Times(int n) => n * by + _count;
        _count = 20;
        return Times(2);
    }

    // Written after the `return`, as C# code often is.
    public String Describe()
    {
        return Label() + " " + Text.FromInteger(Add(1));

        int Add(int n) => n + _count;
        String Label() => _label.ToUpperAscii();
    }

    // A lambda calls one declared after it, and so captures what it reads.
    public int ViaLambda()
    {
        Transform step = v => Step(v);
        return step(1);

        int Step(int v) => v + _count;
    }

    void Bump(int by)
    {
        void Add() => _count += by;
        Add();
    }
}

public struct Point
{
    public int X;
    public int Y;

    public int Sum()
    {
        int Both() => X + Y;
        return Both();
    }
}

public closure int Weigher<T>(T item);

T Largest<T>(T[] items, Weigher<T> weigh)
{
    // Instantiated with the function around it, once per T.
    bool Heavier(T a, T b) => Weight(a) > Weight(b);
    int Weight(T item) => weigh(item);

    T best = items[0];
    foreach (T item in items)
        if (Heavier(item, best))
            best = item;
    return best;
}

int Main()
{
    int Square(int x) => x * x;
    Console.WriteLine(Text.FromInteger(Square(7)));

    // Called before its declaration, reading a variable that is declared
    // before the call.
    int factor = 3;
    Console.WriteLine(Text.FromInteger(Scale(5)));
    int Scale(int x) => x * factor;

    // Each call passes the value the variable has then.
    factor = 10;
    Console.WriteLine(Text.FromInteger(Scale(5)));

    // Recursion, and two that call each other.
    int Factorial(int n)
    {
        if (n <= 1)
            return 1;
        return n * Factorial(n - 1);
    }
    Console.WriteLine(Text.FromInteger(Factorial(5)));

    int limit = 100;
    bool IsEven(int n) => n == 0 || (n < limit && IsOdd(n - 1));
    bool IsOdd(int n) => n != 0 && IsEven(n - 1);
    Console.WriteLine((IsEven(10) ? "even" : "odd") + " " + (IsOdd(7) ? "odd" : "even"));

    // `static` reads nothing, and a generic one is instantiated per call.
    static int Twice(int x) => x * 2;
    T Same<T>(T x) => x;
    T Pick<T>(T a, T b) => factor > 5 ? a : b;
    Console.WriteLine(Text.FromInteger(Twice(21)) + " " + Same("same") + " " +
                      Text.FromInteger(Same(4)) + " " + Pick("a", "b"));

    // As values: one that reads nothing is a function pointer; one that
    // reads something becomes a closure that copies what it reads now.
    Plain plain = Twice;
    Transform scaled = Scale;
    factor = 2;
    Console.WriteLine(Text.FromInteger(plain(5)) + " " + Text.FromInteger(scaled(5)));

    Transform viaLambda = v => Scale(v) + 1;
    Console.WriteLine(Text.FromInteger(viaLambda(4)));

    int[] numbers = [1, 2, 3];
    var squares = numbers.Select(n => Square(n) + factor).ToArray();
    Console.WriteLine(Text.FromInteger(squares[2]));

    // Nested: the inner one reaches past the outer one.
    int Outer(int a)
    {
        int Inner(int b) => a + b + factor;
        return Inner(1);
    }
    Console.WriteLine(Text.FromInteger(Outer(10)));

    // Counted references, captured and returned.
    String name = "world";
    String Greet(String greeting) => greeting + " " + name;
    Console.WriteLine(Greet("hello"));

    var tally = new Tally();
    Console.WriteLine(Text.FromInteger(tally.Scaled(3)));
    Console.WriteLine(tally.Describe());
    Console.WriteLine(Text.FromInteger(tally.ViaLambda()));

    Point point;
    point.X = 3;
    point.Y = 4;
    Console.WriteLine(Text.FromInteger(point.Sum()));

    int[] weights = [5, 9, 2];
    Console.WriteLine(Text.FromInteger(Largest(weights, w => w)));
    String[] words = ["bb", "aaa", "c"];
    Console.WriteLine(Largest(words, w => (int)w.ByteLength()));

    // A default, `params`, and `out`.
    int Total(int first = 1, params int[] rest)
    {
        int sum = first;
        foreach (int value in rest)
            sum += value;
        return sum;
    }
    bool Halve(int n, out int half)
    {
        half = n / 2;
        return n % 2 == 0;
    }
    Console.WriteLine(Text.FromInteger(Total()) + " " + Text.FromInteger(Total(1, 2, 3)));
    Console.WriteLine(Halve(10, out int five) ? Text.FromInteger(five) : "odd");

    // The same name in two blocks is two functions.
    for (int i = 0; i < 2; i++)
    {
        int Local() => i * 100;
        Console.WriteLine(Text.FromInteger(Local()));
    }
    {
        int Local() => -1;
        Console.WriteLine(Text.FromInteger(Local()));
    }

    // Inside a lambda's body.
    Transform nested = v =>
    {
        int Plus(int w) => w + v + factor;
        return Plus(1);
    };
    Console.WriteLine(Text.FromInteger(nested(10)));

    // In a switch section.
    switch (factor)
    {
        case 2:
            int Doubled() => factor * 2;
            Console.WriteLine(Text.FromInteger(Doubled()));
            break;
        default:
            break;
    }
    return 0;
}
