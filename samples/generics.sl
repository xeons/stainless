// SPDX-License-Identifier: 0BSD
module Generics;

import Standard.Console;

// A generic class. Nothing in it is checked until it is instantiated.
public class Box<T> {
    T value;

    public Box(T initial) { value = initial; }

    public T Get() { return value; }
    public void Set(T next) { value = next; }
}

// A growable list built on arrays.
public class List<T> {
    T[] items;
    nuint count;

    public List() {
        items = new T[4];
        count = 0;
    }

    public nuint Count() { return count; }

    public void Add(T item) {
        if (count == items.Length) {
            var bigger = new T[count * 2];
            for (nuint i = 0; i < count; i = i + 1) { bigger[i] = items[i]; }
            items = bigger;
        }
        items[count] = item;
        count = count + 1;
    }

    public T At(nuint index) { return items[index]; }
}

// A generic function; its type argument is inferred from the arguments.
T Larger<T>(T a, T b, bool takeFirst) {
    if (takeFirst) { return a; }
    return b;
}

int Main() {
    var number = new Box<int>(41);
    number.Set(number.Get() + 1);
    Console.WriteLine("box int    = " + Text.FromInteger(number.Get()));

    var text = new Box<String>("boxed");
    Console.WriteLine("box String = " + text.Get());

    var names = new List<String>();
    names.Add("alpha");
    names.Add("beta");
    names.Add("gamma");
    names.Add("delta");
    names.Add("epsilon");        // forces a grow

    Console.WriteLine("count      = " + Text.FromInteger(names.Count()));
    var joined = new StringBuilder();
    for (nuint i = 0; i < names.Count(); i = i + 1) {
        joined.Append(names.At(i));
        joined.Append(" ");
    }
    Console.WriteLine("items      = " + joined.ToText());

    Console.WriteLine("larger int = " + Text.FromInteger(Larger(10, 20, false)));
    Console.WriteLine("larger str = " + Larger("first", "second", true));
    return 0;
}
