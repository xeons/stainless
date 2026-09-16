// SPDX-License-Identifier: 0BSD
//
// `is` with a name: what a test found, under a name of its own.
//
// The bare narrowing -- `if (v.Circle) { v.Radius }` -- needs a local or a
// parameter to be about, because a field or a call result could be a different
// value by the time the payload is read. This is the form for those: the value
// is taken once, and what came out of it is named.
module IsBinding;

import Standard.Collections;
import Standard.Console;

extern "C" int printf(byte* format, ...);

public variant Value
{
    Null;
    Bool(bool Held);
    Number(double Held);
    Pair(int Left, int Right);
}

// A destructor is how a leak or a double release shows itself: the count of
// these lines is the assertion.
class Tracked
{
    public String Name;
    Tracked(String name) => Name = name;
    ~Tracked() { printf("~Tracked(%s)\n", Name.ToPointer()); }
}

variant Holder
{
    Empty;
    One(Tracked Thing);
}

class Node
{
    public Value Payload;
    public Node(Value payload) => Payload = payload;
    public Value Get() => Payload;
}

// A field: the case this exists for.
String OfField(Node node)
{
    if (node.Payload is Number n)
        return "number " + Text.FromDouble(n.Held);
    if (node.Payload is Bool b)
        return "bool " + Text.FromBool(b.Held);
    if (node.Payload is Pair p)
    {
        return "pair " + Text.FromInteger((long)p.Left) + "," + Text.FromInteger((long)p.Right);
    }
    if (node.Payload is Null)
        return "null";
    return "?";
}

// A call result: the other half of the same hole. It is called once, which is
// what the spill is for.
String OfCall(Node node)
{
    if (node.Get() is Number n)
        return "call " + Text.FromDouble(n.Held);
    return "call none";
}

// A parameter is already a name, so nothing is spilled and the ordinary
// narrowing is available beside the binding.
String OfParameter(Value value)
{
    if (value is Pair p)
        return "local " + Text.FromInteger((long)(p.Left + p.Right));
    if (value is Number)
        return "local " + Text.FromDouble(value.Held);
    return "local none";
}

// An else, and an else-if chain over the same field.
String Chain(Node node)
{
    if (node.Payload is Bool b)
    {
        return "chain bool " + Text.FromBool(b.Held);
    }
    else if (node.Payload is Number n)
    {
        return "chain number " + Text.FromDouble(n.Held);
    }
    else
    {
        return "chain other";
    }
}

// The binding is a value like any other, so a case carrying two fields names
// both of them.
int Sum(Node node)
{
    if (node.Payload is Pair p)
        return p.Left + p.Right;
    return 0;
}

class Animal { public virtual String Says() { return "..."; } }
class Dog : Animal { public override String Says() { return "woof"; } }
class Puppy : Dog { }

// A class: the test proved the downcast, and the name is the cast.
String Speak(Animal animal)
{
    if (animal is Dog dog)
        return "dog says " + dog.Says();
    return "animal says " + animal.Says();
}

String Deep(Animal? animal)
{
    if (animal is Puppy p)
        return "puppy " + p.Says();
    return "not a puppy";
}

class Link
{
    public int Value;
    public Link? Next;
    public Link(int value)
    {
        Value = value;
        Next = null;
    }
}

// A nullable field, which no check can be about (SL0248). Through `is` it can:
// the test asks about the null and the class at once, and the field is read
// exactly once.
int SecondOr(Link link, int fallback)
{
    if (link.Next is Link next)
        return next.Value;
    return fallback;
}

// A payload holding a reference, taken and released the ordinary way.
String Named(Holder holder)
{
    if (holder is One held)
        return held.Thing.Name;
    return "(none)";
}

public int Main()
{
    Console.WriteLine(OfField(new Node(Value.Number(2.5))));
    Console.WriteLine(OfField(new Node(Value.Bool(true))));
    Console.WriteLine(OfField(new Node(Value.Pair(3, 4))));
    Console.WriteLine(OfField(new Node(Value.Null)));

    Console.WriteLine(OfCall(new Node(Value.Number(9.0))));
    Console.WriteLine(OfCall(new Node(Value.Null)));

    Console.WriteLine(OfParameter(Value.Pair(1, 2)));
    Console.WriteLine(OfParameter(Value.Number(0.5)));
    Console.WriteLine(OfParameter(Value.Null));

    Console.WriteLine(Chain(new Node(Value.Bool(false))));
    Console.WriteLine(Chain(new Node(Value.Number(-1.0))));
    Console.WriteLine(Chain(new Node(Value.Null)));

    Console.WriteLine("sum=" + Text.FromInteger((long)Sum(new Node(Value.Pair(20, 22)))));

    Console.WriteLine(Speak(new Puppy()));
    Console.WriteLine(Speak(new Animal()));
    Console.WriteLine(Deep(new Puppy()));
    Console.WriteLine(Deep(new Dog()));
    Console.WriteLine(Deep(null));

    var head = new Link(1);
    Console.WriteLine("link " + Text.FromInteger((long)SecondOr(head, -1)));
    head.Next = new Link(2);
    Console.WriteLine("link " + Text.FromInteger((long)SecondOr(head, -1)));

    // The reference in a payload: one construction, one destruction, whether
    // or not the test matched.
    printf("holder\n");
    Console.WriteLine(Named(Holder.One(new Tracked("kept"))));
    Console.WriteLine(Named(Holder.Empty));
    printf("held\n");

    // A loop: the spill is evaluated on every pass, the binding only where the
    // test held.
    var boxes = new List<Node>();
    boxes.Add(new Node(Value.Number(1.0)));
    boxes.Add(new Node(Value.Null));
    boxes.Add(new Node(Value.Number(3.0)));

    var builder = new StringBuilder();
    for (nuint i = 0u; i < boxes.Count; i = i + 1u)
    {
        if (boxes.At(i).Get() is Number n)
        {
            builder.AppendDouble(n.Held);
        }
        else
        {
            builder.Append(".");
        }
    }
    Console.WriteLine("walk " + builder.ToText());

    return 0;
}
