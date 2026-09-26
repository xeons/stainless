// SPDX-License-Identifier: 0BSD
module DefaultInterfaceMethods;

import Standard.Console;
import Standard.Collections;

public class Note
{
    public String Text;

    public Note(String text) => Text = text;
    ~Note() { Console.WriteLine("~Note " + Text); }
}

// A body on an interface member is what a class that supplies none gets.
public interface IGreeter
{
    String Name { get; }

    String Greet() => "hello " + Name;

    // `this` is the object seen as the interface, so this dispatches.
    String Shout() => this.Greet() + "!";

    String Tag => "[" + Name + "]";

    // A default may make and hand back counted objects like any method.
    Note Remember() => new Note("about " + Name);

    // And capture the object it runs on.
    String Twice()
    {
        Func<String, String> again = s => s + " " + Greet();
        return again(Greet());
    }
}

public class Person : IGreeter
{
    public String Name => "ann";
}

// A class that supplies a member wins over the default.
public class Custom : IGreeter
{
    public String Name => "bob";
    public String Greet() => "hi " + Name;
}

// A base class's member fills the slot for a derived class that lists nothing.
public class Base : IGreeter
{
    public String Name => "base";
    public virtual String Greet() => "base greets";
}

public class Derived : Base
{
    public override String Greet() => "derived greets";
}

// A member written under the interface's name fills its slot and nothing else.
public class Private : IGreeter
{
    public String Name => "dee";
    String IGreeter.Greet() => "quietly " + Name;
    public String Greet() => "loudly " + Name;
}

// An interface extending another may replace its default, under its name.
public interface IExcited : IGreeter
{
    String IGreeter.Shout() => this.Greet() + "!!!";
}

public class Fan : IExcited
{
    public String Name => "eve";
}

// Two defaults for one member, neither more specific, are settled by an
// interface extending both.
public interface IA { String Which() => "A"; }
public interface IB : IA { String IA.Which() => "B"; }
public interface IC : IA { String IA.Which() => "C"; }
public interface ID : IB, IC { String IA.Which() => "D"; }

public class OnlyB : IB { }
public class Merged : ID { }
public class Settled : IB, IC
{
    public String Which() => "own";
}

// A default on a generic interface is built per instantiation.
public interface IStack<T>
{
    List<T> Items { get; }

    void Push(T item) => Items.Add(item);
    nuint Depth => Items.Count;
    T Top() => Items[Items.Count - 1];
}

public class Stack<T> : IStack<T>
{
    List<T> _items = new List<T>();
    public List<T> Items => _items;
}

// An explicit property, filling the slot the class's own property does not.
public interface ISized
{
    int Size { get; }
}

public class Crate : ISized
{
    public int Size => 1;
    int ISized.Size => 99;
}

String Describe(IGreeter greeter) => greeter.Tag + " " + greeter.Shout();

int Main()
{
    Console.WriteLine(Describe(new Person()));
    Console.WriteLine(Describe(new Custom()));
    Console.WriteLine(Describe(new Derived()));
    Console.WriteLine(Describe(new Private()));
    Console.WriteLine(new Private().Greet());
    Console.WriteLine(Describe(new Fan()));

    // A default is the interface's, not the class's: it is reached through one.
    IGreeter person = new Person();
    Console.WriteLine(person.Remember().Text);

    IGreeter twice = new Custom();
    Console.WriteLine(twice.Twice());

    IA b = new OnlyB();
    IA merged = new Merged();
    IA settled = new Settled();
    Console.WriteLine(b.Which() + merged.Which() + settled.Which());

    IStack<Note> notes = new Stack<Note>();
    notes.Push(new Note("one"));
    notes.Push(new Note("two"));
    Console.WriteLine(notes.Top().Text + " of " + Text.FromInteger((long)notes.Depth));

    IStack<int> numbers = new Stack<int>();
    numbers.Push(7);
    Console.WriteLine(Text.FromInteger(numbers.Top()));

    var crate = new Crate();
    ISized sized = crate;
    Console.WriteLine(Text.FromInteger(crate.Size) + " " + Text.FromInteger(sized.Size));
    return 0;
}
