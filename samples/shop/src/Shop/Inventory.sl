// SPDX-License-Identifier: 0BSD
// samples/shop/src/Shop/Inventory.sl  ->  module Shop.Inventory
module Shop.Inventory;

import Shop.Catalog;
import Shop.Pricing;

// A generic declared here, instantiated from another module entirely.
public class Register<T>
{
    T[] _items;
    nuint _count;

    public Register(nuint capacity)
    {
        _items = new T[capacity];
        _count = 0;
    }

    public nuint Count => _count;
    public T At(nuint index) => _items[index];

    public void Add(T item)
    {
        _items[_count] = item;
        _count++;
    }

    /// `foreach` finds this by name rather than by interface, so a Register is
    /// iterable without implementing anything or importing Standard.Collections.
    public RegisterCursor<T> GetEnumerator() => new RegisterCursor<T>(this);
}

public class RegisterCursor<T>
{
    Register<T> _source;
    nuint _next;

    public RegisterCursor(Register<T> register)
    {
        _source = register;
        _next = 0;
    }

    public bool MoveNext()
    {
        if (_next >= _source.Count)
            return false;
        _next++;
        return true;
    }

    public T Current => _source.At(_next - 1);
}

public Money Total(Register<IPriced> register)
{
    var sum = Cents(0);
    foreach (var item in register)
        sum = Add(sum, item.Price());
    return sum;
}
