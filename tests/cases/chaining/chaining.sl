// SPDX-License-Identifier: 0BSD
//
// Uniform call syntax, `default(T)` and `String.Empty`.
//
// **`x.F(y)` means `F(x, y)`** when `x` has no member `F`. That is what turns
// the library's free functions into a pipeline: the same functions, read left
// to right instead of inside out.
//
//     Select(Where(names, keep), change)    // before
//     names.Where(keep).Select(change)      // and after
//
// It is uniform call syntax rather than C#'s extension methods, because this
// language has what C# was working around. A module is a scope here, so a
// function need not be wrapped in a static class to exist -- there is nothing
// for a `this` modifier to add, and every free function in scope is already a
// candidate.
//
// **A member always wins.** This is reached only where member lookup has
// already failed, so a method added to a type can never be shadowed by
// somebody else's function, and a new free function can never quietly take
// over a call that used to reach a method.
module Chaining;

import Standard.Console;
import Standard.Collections;

class Person
{
    public String Name { get; set; }
    public int Age { get; set; }

    public Person(String name, int age)
    {
        Name = name;
        Age = age;
    }

    /// A method, to prove one still wins over a free function of the name.
    public String Describe() => $"{Name} ({Age})";
}

/// A free function of the same name over a different type. Both are in scope,
/// and which is reached is decided by whether the receiver has the member.
String Describe(int age) => $"age {age}";

struct Point { public int X; public int Y; }

/// A generic where `default(T)` is the only value that can be named.
T FirstOrNothing<T>(T[:] items)
{
    if (items.Length == 0u)
        return default(T);
    return items[0u];
}

public int Main()
{
    String[] words = ["delta", "bb", "alpha", "bb", "c", "delta"];

    // --------------------------------------------------------- the pipeline

    var picked = words.Where((w) => w.ByteLength() > 1u)
                      .Distinct()
                      .OrderBy((a, b) => (int)a.ByteLength() - (int)b.ByteLength())
                      .ToArray();

    Console.WriteLine($"picked {picked.Length}");
    foreach (var w in picked)
        Console.WriteLine($"  {w}");

    // The same functions written the old way, to show they are the same.
    var same = ToArray(OrderBy(
        Distinct(Where(words, (w) => w.ByteLength() > 1u)),
        (a, b) => (int)a.ByteLength() - (int)b.ByteLength()));

    Console.WriteLine($"agree  {same.Length == picked.Length}");

    // Through a List, and back to an array.
    var people = new List<Person>();
    people.Add(new Person("ada", 36));
    people.Add(new Person("bob", 71));
    people.Add(new Person("cy", 12));

    var adults = people.Where((p) => p.Age >= 18)
                       .Select((p) => p.Name)
                       .ToArray();

    Console.WriteLine($"adults {adults.Length}: {adults[0]} {adults[1]}");
    Console.WriteLine($"years  {people.Aggregate(0, (sum, p) => sum + p.Age)}");
    Console.WriteLine($"oldest {people.ToArray().Find((p) => p.Age > 60).GetValueOrDefault(people[0u]).Name}");

    // A member wins over a free function of the same name.
    Console.WriteLine($"member {people[0u].Describe()}");
    Console.WriteLine($"free   {36.Describe()}");

    // ---------------------------------------------------------- default(T)

    Console.WriteLine($"zeroes {default(int)} {default(double)} {default(bool)} {default(nuint)}");

    Point origin = default(Point);
    Console.WriteLine($"point  {origin.X},{origin.Y}");

    int[] none = [];
    int[] some = [7, 8];
    Console.WriteLine($"first  {FirstOrNothing(some)} then {FirstOrNothing(none)}");

    // --------------------------------------------------------- String.Empty

    var blank = String.Empty;
    Console.WriteLine($"empty  {blank.ByteLength()} {blank == ""} {blank.IsEmpty}");
    Console.WriteLine($"joined {(blank + "x").ByteLength()}");
    return 0;
}
