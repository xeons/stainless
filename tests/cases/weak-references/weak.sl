// SPDX-License-Identifier: 0BSD
//
// A weak reference is the only way to break a cycle, because ARC cannot collect
// one. Assigning to it is an ordinary assignment: the slot's type is what makes
// the store count weakly.
module Weak;

import Standard.Console;

class Child {
    public int Id;
    public weak Parent? Owner;
    public Child(int id) { Id = id; }
    ~Child() { Console.WriteLine("-child " + Text.FromInteger(Id)); }
}

class Parent {
    public int Id;
    public Child? Kid;
    public Parent(int id) { Id = id; }
    ~Parent() { Console.WriteLine("-parent " + Text.FromInteger(Id)); }
}

int Main() {
    // Strong down, weak back up: both ends still die at the end of the scope.
    {
        var parent = new Parent(1);
        var child = new Child(2);
        parent.Kid = child;
        child.Owner = parent;
        Console.WriteLine("linked");
    }
    Console.WriteLine("scope left");

    // A weak reference reads back as null once the object it named is gone,
    // rather than as a pointer into freed memory.
    var orphan = new Child(3);
    {
        var owner = new Parent(4);
        orphan.Owner = owner;
        Parent? alive = orphan.Owner;
        Console.WriteLine(alive == null ? "alive: null" : "alive: present");
    }

    Parent? gone = orphan.Owner;
    Console.WriteLine(gone == null ? "dead: null" : "dead: present");

    // Assigning null clears it, and an optional may be assigned as well.
    Parent? maybe = new Parent(5);
    orphan.Owner = maybe;
    orphan.Owner = null;
    Console.WriteLine("cleared");

    return 0;
}
