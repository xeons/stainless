// SPDX-License-Identifier: 0BSD
//
// The library half. Everything a class derived on the other side needs has to
// leave this compilation: the layout, the dispatch table slot by slot, the
// destroy hook that takes this half of the object apart, and the protected
// members a derived class is allowed to reach.
module Library.Animals;

import Standard.Console;

public class Animal {
    private int legs;
    private String name;

    public Animal(int legs, String name) {
        this.legs = legs;
        this.name = name;
    }

    // Runs after the derived destructor: an object is taken apart from the
    // outside in, and this is where the outside stops.
    ~Animal() { Console.WriteLine("~Animal " + name); }

    public int Legs { get { return legs; } }
    public String Name { get { return name; } }

    // Slot 0 and slot 1. A class derived in another binary copies both and
    // appends after them, so the length of this list is part of what this
    // library promises.
    public virtual String Speak() { return "..."; }
    public virtual int Score() { return legs; }

    // Visible to a derived class and to nothing else. It has to be exported for
    // one compiled elsewhere to call it; what keeps it protected is the binder.
    protected int Doubled() { return legs * 2; }
}

// Sealed, so the refusal still has something to refuse.
public sealed class Rock {
    public int Weight;
}
