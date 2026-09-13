// SPDX-License-Identifier: 0BSD
//
// Indexers, including on a generic type and on a struct, and the ones the
// containers now carry. Nothing covered a generic indexer before, and the
// containers had `At`, `Get` and `Set` where the language has had `this[...]`
// all along.
module Indexers;

import Standard.Console;
import Standard.Text;
import Standard.Collections;

String N(long v) { return Text.FromInteger(v); }

// A generic class: the accessors are instantiated with everything else.
public class Box<T> {
    T[] cells;

    public Box(nuint size) { cells = new T[size]; }

    public T this[nuint at] {
        get { return cells[at]; }
        set { cells[at] = value; }
    }

    public nuint Count() { return cells.Length; }
}

// A generic struct, where the setter reaches its receiver by pointer.
public struct Row<T> {
    public T[] items;

    public T this[nuint at] {
        get { return items[at]; }
        set { items[at] = value; }
    }
}

// Overloaded on what it takes, which is the reason an indexer is not a
// property with a fixed name.
public class Table {
    int[] byNumber;
    String label;

    public Table() {
        byNumber = new int[4];
        label = "none";
    }

    public int this[nuint at] {
        get { return byNumber[at]; }
        set { byNumber[at] = value; }
    }

    public String this[String named] {
        get { return named + "=" + label; }
        set { label = value; }
    }
}

int Main() {
    var box = new Box<int>(4);
    box[0] = 10;
    box[1] = 20;
    box[1] += 5;                    // read through the getter, write through the setter
    Console.WriteLine("box " + N((long)box[0]) + " " + N((long)box[1]) + " " +
        N((long)box.Count()));

    // Over a reference type, so the assignment is a retain and a release.
    var text = new Box<String>(2);
    text[0] = "a";
    text[1] = text[0] + "b";
    Console.WriteLine("text " + text[0] + text[1]);

    Row<int> row;
    row.items = new int[2];
    row[0] = 7;
    row[0] += 1;
    Console.WriteLine("row " + N((long)row[0]));

    var table = new Table();
    table[2] = 99;
    table["k"] = "set";
    Console.WriteLine("table " + N((long)table[2]) + " " + table["k"]);

    // The containers.
    var list = new List<int>();
    list.Add(1);
    list.Add(2);
    list[1] = 20;
    list[1] += 2;
    Console.WriteLine("list " + N((long)list[0]) + " " + N((long)list[1]) + " " +
        N((long)list.At(1)));

    var map = new Dictionary<String, int>();
    map["a"] = 1;
    map["a"] += 4;
    Console.WriteLine("map " + N((long)map["a"]) + " " + N((long)map.Get("a")) + " " +
        N((long)map.Count()));

    return 0;
}
