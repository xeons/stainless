// SPDX-License-Identifier: 0BSD
module Generics;

import Standard.Console;

// A generic class. Nothing in it is checked until it is instantiated.
public class Box<T>
{
    public Box(T initial) => Value = initial;

    public T Value { get; set; }
}

// A growable list built on arrays.
public class List<T>
{
    T[] _items;
    nuint _count;

    public List()
    {
        _items = new T[4];
        _count = 0;
    }

    public nuint Count => _count;

    public void Add(T item)
    {
        if (_count == _items.Length)
        {
            var bigger = new T[_count * 2];
            for (nuint i = 0; i < _count; i++)
                bigger[i] = _items[i];
            _items = bigger;
        }
        _items[_count] = item;
        _count++;
    }

    public T this[nuint index]
    {
        get => _items[index];
    }
}

// A generic function; its type argument is inferred from the arguments.
T ChooseEither<T>(T a, T b, bool takeFirst)
{
    if (takeFirst)
        return a;
    return b;
}

int Main()
{
    var number = new Box<int>(41);
    number.Value++;
    Console.WriteLine("box int    = " + Text.FromInteger(number.Value));

    var text = new Box<String>("boxed");
    Console.WriteLine("box String = " + text.Value);

    var names = new List<String>();
    names.Add("alpha");
    names.Add("beta");
    names.Add("gamma");
    names.Add("delta");
    names.Add("epsilon");        // forces a grow

    Console.WriteLine("count      = " + Text.FromInteger(names.Count));
    var joined = new StringBuilder();
    for (nuint i = 0; i < names.Count; i++)
    {
        joined.Append(names[i]);
        joined.Append(" ");
    }
    Console.WriteLine("items      = " + joined.ToText());

    Console.WriteLine("larger int = " + Text.FromInteger(ChooseEither(10, 20, false)));
    Console.WriteLine("larger str = " + ChooseEither("first", "second", true));
    return 0;
}
