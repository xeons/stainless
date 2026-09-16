// SPDX-License-Identifier: 0BSD
//
// The consumer, deriving from a class it has only the metadata of. Its objects
// carry a dispatch table built here on top of one compiled there, its fields
// sit after fields it never saw laid out, and its destructor hands the object
// back to the library when it is done with its own half.
module App;

import Standard.Console;
import Library.Animals;

public class Dog : Animal
{
    private String _toy;

    // The base constructor runs first, across the boundary.
    public Dog(String toy)
    {
        base(4, "dog");
        this._toy = toy;
    }

    ~Dog() { Console.WriteLine("~Dog " + _toy); }

    // Slot 0, replaced.
    public override String Speak() => "woof";

    // A protected member of a class compiled somewhere else.
    public int Twice() => Doubled();
}

// Two levels, the second of which never sees the library at all except through
// the first.
public class Puppy : Dog
{
    public Puppy() => base("sock");

    public override String Speak() => "yip";
    public override int Score() => 99;
}

int Main()
{
    {
        Animal a = new Dog("ball");

        // A field the library laid out, read through a property it compiled.
        Console.WriteLine(Text.FromInteger(a.Legs) + " " + a.Name);

        // Dispatch through a base reference reaches what the object really is.
        Console.WriteLine(a.Speak() + " " + Text.FromInteger(a.Score()));

        Animal p = new Puppy();
        Console.WriteLine(p.Speak() + " " + Text.FromInteger(p.Score()));

        // The base chain crosses the boundary, so a test against it walks from
        // a TypeInfo built here into one built there.
        if (p is Dog d)
            Console.WriteLine("dog " + Text.FromInteger(d.Twice()));
        if (p is Puppy)
            Console.WriteLine("puppy");
        if (a is Puppy)
            Console.WriteLine("WRONG");
        if (p is Animal)
            Console.WriteLine("animal");

        Console.WriteLine("dropping");
    }

    Console.WriteLine("done");
    return 0;
}
