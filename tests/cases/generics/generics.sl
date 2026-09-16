// SPDX-License-Identifier: 0BSD
module Generics;

import Standard.Console;

public class Box<T>
{
    T _value;
    public Box(T initial) => _value = initial;
    public T Get() => _value;
    public void Set(T next) => _value = next;
}

// Self-referential: instantiation must terminate.
public class Node<T>
{
    T _value;
    Node<T>? _next;

    public Node(T initial) => _value = initial;
    public T Value() => _value;
    public void Attach(Node<T> other) => _next = other;
}

public class List<T>
{
    T[] _items;
    nuint _count;

    public List()
    {
        _items = new T[2];
        _count = 0;
    }

    public nuint Count() => _count;

    public void Add(T item)
    {
        if (_count == _items.Length)
        {
            var bigger = new T[_count * 2];
            for (nuint i = 0; i < _count; i = i + 1)
                bigger[i] = _items[i];
            _items = bigger;
        }
        _items[_count] = item;
        _count = _count + 1;
    }

    public T At(nuint index) => _items[index];
}

T Pick<T>(T a, T b, bool first)
{
    if (first)
        return a;
    return b;
}

nuint CountOf<T>(T[] values) => values.Length;

int Main()
{
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
    for (nuint i = 0; i < names.Count(); i = i + 1)
        joined.Append(names.At(i));
    Console.WriteLine("items=" + joined.ToText());

    Console.WriteLine("pick=" + Text.FromInteger(Pick(10, 20, false)));
    Console.WriteLine("pickstr=" + Pick("first", "second", true));
    Console.WriteLine("countof=" + Text.FromInteger(CountOf(new double[4])));
    return 0;
}
