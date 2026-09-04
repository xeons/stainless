// SPDX-License-Identifier: 0BSD
module Variants;

import Standard.Console;
import Standard.Collections;

// A destructor is the only way to watch a reference count from inside the
// language, so the reference-counting cases below hold one of these.
public class Trace {
    public String Name { get; }
    public Trace(String name) { Name = name; }
    ~Trace() { Console.WriteLine("~" + Name); }
}

public variant Shape {
    Circle(double Radius);
    Rect(double Width, double Height);
    Empty;
}

// A case may carry a counted reference, and then copying and dropping the
// variant has to ask the tag which one is really in there.
public variant Message {
    Text(String Body);
    Tagged(String Body, Trace Marker);
    Silence;
}

public variant Tree<T> {
    Leaf(T Item);
    Empty;
}

double Area(Shape shape) {
    switch (shape) {
        case Circle c: return 3.14159 * c.Radius * c.Radius;
        case Rect r:   return r.Width * r.Height;
        case Empty:    return 0.0;
    }
}

// The same switch without bindings: inside an arm the value is known to be
// that case, so its fields are readable under their own names.
String Describe(Shape shape) {
    switch (shape) {
        case Circle: return "circle r=" + Text.FromDouble(shape.Radius);
        case Rect:   return "rect " + Text.FromDouble(shape.Width) +
                            "x" + Text.FromDouble(shape.Height);
        case Empty:  return "empty";
    }
}

// Stacked labels, and a default standing in for what is left.
String Sides(Shape shape) {
    switch (shape) {
        case Circle: case Empty: return "round or nothing";
        default: return "cornered";
    }
}

String Read(Message message) {
    switch (message) {
        case Text t:   return t.Body;
        case Tagged g: return g.Body + "/" + g.Marker.Name;
        case Silence:  return "-";
    }
}

int Main() {
    Console.WriteLine(Text.FromDouble(Area(Shape.Circle(2.0))));
    Console.WriteLine(Text.FromDouble(Area(Shape.Rect(3.0, 4.0))));
    Console.WriteLine(Text.FromDouble(Area(Shape.Empty)));

    Console.WriteLine(Describe(Shape.Circle(1.5)));
    Console.WriteLine(Describe(Shape.Rect(2.0, 5.0)));
    Console.WriteLine(Sides(Shape.Rect(1.0, 1.0)));
    Console.WriteLine(Sides(Shape.Empty));

    // Narrowing through an `if`, exactly as a Result narrows.
    Shape held = Shape.Rect(6.0, 7.0);
    if (held.Rect) { Console.WriteLine(Text.FromDouble(held.Width * held.Height)); }
    if (!held.Rect) { Console.WriteLine("not a rect"); }

    // Only one case is ever present, so the payloads overlap: Rect is the
    // widest at two doubles, and the tag rounds the whole thing up to 24.
    Console.WriteLine("sizeof Shape=" + Text.FromInteger((int)sizeof(Shape)));

    Console.WriteLine("--- references ---");

    // The String and the Trace are held by the variant, released when it dies.
    {
        Message plain = Message.Text("plain");
        Console.WriteLine(Read(plain));

        Message marked = Message.Tagged("marked", new Trace("marker"));
        Console.WriteLine(Read(marked));

        // Copying the variant copies what the live case holds, and only that:
        // the bytes of the case that is not there are never counted.
        Message copy = marked;
        Console.WriteLine(Read(copy));

        Console.WriteLine("leaving");
    }
    Console.WriteLine("left");

    Console.WriteLine("--- reassignment ---");

    // Storing a new case over an old one drops what the old one held, and only
    // what it held: the tag decides that, not the fields the type declares.
    {
        Message slot = Message.Tagged("first", new Trace("first"));
        Console.WriteLine(Read(slot));
        slot = Message.Tagged("second", new Trace("second"));
        Console.WriteLine(Read(slot));
        slot = Message.Silence;
        Console.WriteLine(Read(slot));
        Console.WriteLine("still here");
    }

    Console.WriteLine("--- inside other things ---");

    // A variant held in a class field is dropped when the object is, and one
    // switched on as a temporary needs no name of its own.
    {
        var box = new Envelope(Message.Tagged("boxed", new Trace("boxed")));
        Console.WriteLine(Read(box.Carried));
        Console.WriteLine(Read(Wrap("temporary")));
        Console.WriteLine("closing");
    }
    Console.WriteLine("closed");

    // A variant with no payload at all is a tag and nothing else.
    Console.WriteLine("sizeof Silence-only=" + Text.FromInteger((int)sizeof(Flag)));

    Console.WriteLine("--- control flow ---");

    // A case that carries nothing is written without parentheses, and `break`
    // and `continue` mean in a variant switch what they mean in any other.
    {
        var steps = new Step[5];
        steps[0] = Take(1);
        steps[1] = Skip;
        steps[2] = Take(10);
        steps[3] = Stop;
        steps[4] = Take(100);

        int total = 0;
        for (nuint i = 0; i < steps.Length; i = i + 1) {
            Step step = steps[i];
            switch (step) {
                case Skip:   continue;
                case Take t: total = total + t.N; break;
                case Stop:   i = steps.Length; break;
            }
            total = total + 1000;
        }
        Console.WriteLine(Text.FromInteger(total));
    }

    // Generic variants instantiate like anything else.
    Tree<int> number = Ok3();
    Tree<String> word = Word();
    Console.WriteLine(Text.FromInteger(Sum(number)));
    Console.WriteLine(Label(word));

    // Result is now an ordinary variant, and reads exactly as it did.
    var found = Halve(10);
    if (found.Ok) { Console.WriteLine(Text.FromInteger(found.Value)); }

    var refused = Halve(7);
    if (!refused.Ok) { Console.WriteLine(refused.Error); }
    Console.WriteLine(Text.FromInteger(Halve(9).ValueOr(-1)));

    return 0;
}

public variant Flag {
    Up;
    Down;
}

public variant Step {
    Skip;
    Take(int N);
    Stop;
}

public class Envelope {
    public Message Carried;
    public Envelope(Message carried) { Carried = carried; }
    ~Envelope() { Console.WriteLine("~Envelope"); }
}

Message Wrap(String body) { return Message.Text(body); }

Tree<int> Ok3() { return Leaf(3); }
Tree<String> Word() { return Leaf("leaf"); }

int Sum(Tree<int> tree) {
    switch (tree) {
        case Leaf l: return l.Item;
        case Empty:  return 0;
    }
}

String Label(Tree<String> tree) {
    switch (tree) {
        case Leaf l: return l.Item;
        case Empty:  return "";
    }
}

Result<int, String> Halve(int n) {
    if (n % 2 != 0) { return Fail("odd"); }
    return Ok(n / 2);
}
