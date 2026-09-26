// SPDX-License-Identifier: 0BSD
//
// `field` inside an accessor is the storage the compiler made for that
// property, which is what lets an accessor do work without a field written
// beside it. Anywhere else, and as `@field`, it is an ordinary name.
module FieldKeyword;

import Standard.Console;
import Standard.Text;

public class Node
{
    public String Name;

    public Node(String name)
    {
        Name = name;
    }

    ~Node()
    {
        Console.WriteLine("released " + Name);
    }
}

public closure int Reading();

public class Person
{
    int _made = 0;

    /// An automatic getter beside a setter that does work.
    public String Name { get; set => field = value.Trim(); }

    /// Filled on first use and kept: the storage starts empty whatever the
    /// type says, and `??=` is how an accessor fills it.
    public Node Badge { get => field ??= MakeBadge(); }

    /// Both accessors written, both naming the storage.
    public int Score
    {
        get { return field * 10; }
        set { field = value < 0 ? 0 : value; }
    }

    /// A lambda in an accessor reaches the storage through the object, so it
    /// reads what is there when it runs.
    public int Level
    {
        get
        {
            Reading later = () => field;
            field++;
            return later();
        }
    }

    /// A member that happens to be called `field`, reached as `@field` and
    /// `this.field` wherever `field` would mean the storage.
    public int @field = 7;

    public int Twice
    {
        get
        {
            int copy = @field;
            return copy + this.field;
        }
    }

    Node MakeBadge()
    {
        _made++;
        return new Node("badge " + Text.FromInteger(_made));
    }
}

/// On a struct the storage is part of the value, as any field is.
public struct Temperature
{
    public double Celsius { get; set => field = value < -273.15 ? -273.15 : value; }
}

/// And on a generic type, once per instantiation.
public class Slot<T>
{
    public T Value { get; set => field = value; }
    public int Writes { get => field; private set => field = value; }

    public void Put(T value)
    {
        Value = value;
        Writes++;
    }
}

int Main()
{
    var person = new Person();
    person.Name = "  ada  ";
    person.Score = 4;
    Console.WriteLine("[" + person.Name + "] " + Text.FromInteger(person.Score));

    person.Score = -3;
    Console.WriteLine(Text.FromInteger(person.Score) + " " + Text.FromInteger(person.Level) + " " +
                      Text.FromInteger(person.Level));

    Console.WriteLine(person.Badge.Name + ", " + person.Badge.Name);
    Console.WriteLine(Text.FromInteger(person.Twice));

    // A local called `field` is a name like any other outside an accessor.
    int field = 5;
    Console.WriteLine(Text.FromInteger(field + 1));

    Temperature t;
    t.Celsius = -500.0;
    Console.WriteLine(Text.FromDouble(t.Celsius));

    var slot = new Slot<String>();
    slot.Put("a");
    slot.Put("b");
    Console.WriteLine(slot.Value + " " + Text.FromInteger(slot.Writes));
    return 0;
}
