// SPDX-License-Identifier: 0BSD
module Generics;

import Standard.Console;

public class Box<T> {
    T value;
    public Box(T initial) { value = initial; }
    public T Get() { return value; }
    public void Set(T next) { value = next; }
}

// Self-referential: instantiation must terminate.
public class Node<T> {
    T value;
    Node<T>? next;

    public Node(T initial) { value = initial; }
    public T Value() { return value; }
    public void Attach(Node<T> other) { next = other; }
}

public class List<T> {
    T[] items;
    nuint count;

    public List() {
        items = new T[2];
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

T Pick<T>(T a, T b, bool first) {
    if (first) { return a; }
    return b;
}

nuint CountOf<T>(T[] values) { return values.Length; }

int Main() {
    var number = new Box<int>(41);
    number.Set(number.Get() + 1);
    Console.WriteLine("int=" + Text.FromInteger(number.Get()));

    var text = new Box<String>("boxed");
    Console.WriteLine("str=" + text.Get());

    var chain = new Node<int>(7);
    chain.Attach(new Node<int>(8));
    Console.WriteLine("node=" + Text.FromInteger(chain.Value()));

    var names = new List<String>();
    names.Add("a");
    names.Add("b");
    names.Add("c");         // forces a grow
    Console.WriteLine("count=" + Text.FromInteger(names.Count()));

    var joined = new StringBuilder();
    for (nuint i = 0; i < names.Count(); i = i + 1) { joined.Append(names.At(i)); }
    Console.WriteLine("items=" + joined.ToText());

    Console.WriteLine("pick=" + Text.FromInteger(Pick(10, 20, false)));
    Console.WriteLine("pickstr=" + Pick("first", "second", true));
    Console.WriteLine("countof=" + Text.FromInteger(CountOf(new double[4])));
    return 0;
}
