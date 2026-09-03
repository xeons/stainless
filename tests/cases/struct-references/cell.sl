// SPDX-License-Identifier: 0BSD
//
// A struct may hold a reference, and copying one maintains the count. What that
// buys is a value type that owns something -- Result<T, E> is the reason -- and
// what it costs is the C guarantee: such a struct no longer crosses extern "C".
module Cell;

import Standard.Console;

class Tracked {
    public int Id;
    public Tracked(int id) { Id = id; Console.WriteLine("+" + Text.FromInteger(id)); }
    ~Tracked() { Console.WriteLine("-" + Text.FromInteger(Id)); }
}

struct Holder {
    public Tracked Item;
    public int Tag;
}

class Bag {
    public Holder Slot;
    public Bag(Tracked t) { Holder h; h.Item = t; h.Tag = 9; Slot = h; }
}

Holder Wrap(Tracked t, int tag) {
    Holder h;
    h.Item = t;
    h.Tag = tag;
    return h;
}

int Main() {
    Console.WriteLine("-- copy");
    {
        var one = Wrap(new Tracked(1), 10);
        var two = one;
        Console.WriteLine("shared " + Text.FromInteger(two.Item.Id));
    }

    Console.WriteLine("-- reassign");
    {
        var cell = Wrap(new Tracked(2), 20);
        cell = Wrap(new Tracked(3), 30);
        Console.WriteLine("holding " + Text.FromInteger(cell.Item.Id));
    }

    Console.WriteLine("-- self");
    {
        var cell = Wrap(new Tracked(4), 40);
        cell = cell;
        Console.WriteLine("intact " + Text.FromInteger(cell.Item.Id));
    }

    Console.WriteLine("-- class field");
    {
        var bag = new Bag(new Tracked(5));
        Console.WriteLine("bagged " + Text.FromInteger(bag.Slot.Item.Id));
    }

    Console.WriteLine("-- array");
    {
        var cells = new Holder[2];
        cells[0] = Wrap(new Tracked(6), 60);
        cells[1] = Wrap(new Tracked(7), 70);
        Console.WriteLine("stored " + Text.FromInteger(cells[1].Item.Id));
    }

    Console.WriteLine("-- discarded");
    Wrap(new Tracked(8), 80);

    Console.WriteLine("done");
    return 0;
}
