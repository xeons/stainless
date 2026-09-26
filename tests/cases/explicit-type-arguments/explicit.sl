// SPDX-License-Identifier: 0BSD
//
// Type arguments written at a call, and a generic type named in front of its
// static members.
//
// `<` after a name is read as the start of type arguments only when what is
// inside parses as types and the token after the `>` is one C# lists for the
// same question -- so `F<int>(x)` is a call and `Compare(a < b, c > d)` is two
// comparisons.
module ExplicitTypeArguments;

import Standard.Console;
import Standard.Collections;

T Pick<T>(T a, T b, bool first)
{
    if (first)
        return a;
    return b;
}

// T appears only in the result, so nothing passed could say what it is.
T Zero<T>() => default;

List<T> MakeList<T>() => new List<T>();

closure U Converter<T, U>(T value);

class Box<T>
{
    private T _value;

    public static int Made = 0;

    public Box(T value)
    {
        _value = value;
        Made++;
    }

    public T Value => _value;

    public static Box<T> Create(T value) => new Box<T>(value);

    public U Convert<U>(Converter<T, U> convert) => convert(_value);

    public static U Echo<U>(U value) => value;

    public R Blank<R>() => default;
}

class Helper
{
    public static T Take<T>(T value) => value;

    private int Measure<T>(T value) => 2;

    private int Count<T>() => 0;

    public int Run() => Count<int>() + Measure<long>(4);
}

// Written from inside a generic body, where `T` is itself an argument.
List<T> Twice<T>(T value)
{
    List<T> made = MakeList<T>();
    made.Add(Pick<T>(value, value, true));
    made.Add(value);
    return made;
}

bool Compare(bool a, bool b) => a == b;

public variant Tree<T>
{
    Leaf(T Item);
    Empty;
}

public int Main()
{
    // The argument widens to what was written, where inference would take int.
    Console.WriteLine($"a {Pick<long>(1, 2, false)}");
    Console.WriteLine($"b {Zero<int>()} {Zero<double>()}");

    List<String> names = MakeList<String>();
    names.Add("one");
    List<List<int>> nested = MakeList<List<int>>();
    Console.WriteLine($"c {names.Count} {nested.Count}");

    Box<int> box = Box<int>.Create(5);
    Box<String> text = Box<String>.Create("five");
    Console.WriteLine($"d {box.Value} {text.Value} {Box<int>.Made} {Box<String>.Made}");
    Console.WriteLine($"e {ExplicitTypeArguments.Box<int>.Made}");

    Console.WriteLine($"f {box.Convert<String>((v) => $"v{v}")} {Box<long>.Echo<int>(9)}");
    Console.WriteLine($"g {box.Blank<int>()} {Helper.Take<String>("taken")} {new Helper().Run()}");
    Console.WriteLine($"h {Twice<String>("x").Count}");

    // A generic variant named in front of its case, so `var` has a type.
    Result<int, String> made = Result<int, String>.Ok(3);
    var leaf = Tree<int>.Leaf(4);
    var empty = Tree<String>.Empty;
    Console.WriteLine($"i {made.Ok} {leaf is Leaf} {empty is Empty}");

    // Comparisons, not type arguments.
    int a = 1;
    int b = 2;
    int c = 3;
    int d = 4;
    Console.WriteLine($"j {Compare(a < b, c > d)} {a < b == c > d} {a < b && c > d}");
    return 0;
}
