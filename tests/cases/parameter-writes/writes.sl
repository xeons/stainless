// SPDX-License-Identifier: 0BSD
//
// A parameter is borrowed and owns nothing -- until the body writes to it. Then
// the release the write performs would fall on a reference the caller still
// owns, so a written parameter is retained on entry and released on exit.
module Writes;

import Standard.Console;

class Tracked {
    public int Id;
    public Tracked(int id) { Id = id; Console.WriteLine("+" + Text.FromInteger(id)); }
    ~Tracked() { Console.WriteLine("-" + Text.FromInteger(Id)); }
}

struct Cell { public Tracked Item; }

// Rebinding a reference parameter: the caller's object must outlive the call.
void Rebind(Tracked t) {
    t = new Tracked(2);
    Console.WriteLine("inside " + Text.FromInteger(t.Id));
}

// Writing through a struct parameter, which is the caller's bytes copied but
// not the caller's ownership.
void Overwrite(Cell c) {
    c.Item = new Tracked(4);
    Console.WriteLine("inside " + Text.FromInteger(c.Item.Id));
}

// A struct's property setter writes the receiver's own storage, so it is the
// same write as the one above and adopts the parameter the same way.
struct Slot { public Tracked Item { get; set; } }

void Replace(Slot s) {
    s.Item = new Tracked(6);
    Console.WriteLine("inside " + Text.FromInteger(s.Item.Id));
}

// Reading a parameter costs nothing at all, which is the point of borrowing.
int Read(Tracked t) { return t.Id; }

int Main() {
    Console.WriteLine("-- rebind");
    {
        var original = new Tracked(1);
        Rebind(original);
        Console.WriteLine("after " + Text.FromInteger(original.Id));
    }

    Console.WriteLine("-- overwrite");
    {
        Cell outer;
        outer.Item = new Tracked(3);
        Overwrite(outer);
        Console.WriteLine("after " + Text.FromInteger(outer.Item.Id));
    }

    Console.WriteLine("-- setter");
    {
        Slot outer;
        outer.Item = new Tracked(5);
        Replace(outer);
        Console.WriteLine("after " + Text.FromInteger(outer.Item.Id));
    }

    Console.WriteLine("-- read");
    {
        var borrowed = new Tracked(7);
        Console.WriteLine("read " + Text.FromInteger(Read(borrowed)));
    }

    Console.WriteLine("done");
    return 0;
}
