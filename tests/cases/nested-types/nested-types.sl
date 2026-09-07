// SPDX-License-Identifier: 0BSD
//
// A type declared inside another.
//
// **It is lifted out and named for where it was written.** `Outer.Inner` is
// the type's name everywhere -- in a diagnostic, in the mangled symbol, and at
// a use site -- and the inner type is an ordinary module-level type that
// happens to have a dot in its name.
//
// That is the whole of what nesting means here: it is about where a name is
// *reached from*. An inner type has no privileged view of the outer one, no
// implicit reference to an instance of it, and no bearing on layout. C#'s
// nested types work the same way; Java's inner classes do not, and the
// difference is the hidden field Java adds.
//
// The short name works inside the type it was written in, and the long one
// everywhere else, which is what makes it worth having over a naming
// convention.
module NestedTypes;

import Standard.Console;

// ---------------------------------------------------------- inside a struct

public struct Rect {
    public struct Point { public int X; public int Y; }

    public Point TopLeft;
    public Point BottomRight;

    /// The short name, from inside.
    public Point Middle() {
        Point at;
        at.X = (TopLeft.X + BottomRight.X) / 2;
        at.Y = (TopLeft.Y + BottomRight.Y) / 2;
        return at;
    }

    public int Width() { return BottomRight.X - TopLeft.X; }
}

// ----------------------------------------------------------- inside a class

public class Widget {
    public enum State { Idle, Busy, Gone }

    public class Handle {
        public int Id { get; set; }
        public Handle(int id) { Id = id; }
    }

    /// Two deep, to show the naming composes.
    public class Bag {
        public struct Slot { public int Index; public bool Filled; }

        public Slot First;
        public Bag() { First.Index = 0; First.Filled = false; }
    }

    public State Now;
    public Handle Grip;
    public Bag Held;

    public Widget(int id) {
        Now = State.Idle;
        Grip = new Handle(id);
        Held = new Bag();
    }

    public void Start() { Now = State.Busy; }

    public String Describe() { return $"{(long)Now} #{Grip.Id}"; }
}

// -------------------------------------------------------- inside a generic

public class Cache<T> {
    public struct Entry { public nuint Age; public bool Live; }

    Entry state;
    T held;

    public Cache(T value) {
        held = value;
        state.Age = 0u;
        state.Live = true;
    }

    public T Get() { state.Age++; return held; }
    public nuint Age() { return state.Age; }
}

public int Main() {
    // The long name, from outside.
    Rect.Point corner;
    corner.X = 2;
    corner.Y = 4;

    Rect box;
    box.TopLeft = corner;
    box.BottomRight.X = 12;
    box.BottomRight.Y = 24;

    Console.WriteLine($"corner   {corner.X},{corner.Y}");
    Console.WriteLine($"middle   {box.Middle().X},{box.Middle().Y}");
    Console.WriteLine($"width    {box.Width()}");

    // Nesting says nothing about layout: a Rect is four ints, and a Point two.
    Console.WriteLine($"sizes    {sizeof(Rect)} {sizeof(Rect.Point)}");

    // A nested enum, reached both ways.
    var w = new Widget(7);
    Console.WriteLine($"widget   {w.Describe()}");

    w.Start();
    Console.WriteLine($"started  {w.Now == Widget.State.Busy}");

    Widget.State asked = Widget.State.Gone;
    Console.WriteLine($"asked    {asked != w.Now}");

    // A nested class, made from outside.
    var loose = new Widget.Handle(11);
    Console.WriteLine($"handle   {loose.Id}");

    // Two deep.
    Widget.Bag.Slot slot;
    slot.Index = 3;
    slot.Filled = true;
    Console.WriteLine($"slot     {slot.Index} {slot.Filled} {w.Held.First.Filled}");

    // And inside a generic, where the outer type's own parameters are fixed.
    var cache = new Cache<String>("held");
    Console.WriteLine($"cache    {cache.Get()} age {cache.Age()}");

    var numbers = new Cache<int>(41);
    Console.WriteLine($"cache    {numbers.Get() + 1} age {numbers.Age()}");
    return 0;
}
