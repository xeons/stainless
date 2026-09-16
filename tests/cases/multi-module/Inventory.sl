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

    public nuint Count() => _count;
    public T At(nuint index) => _items[index];

    public void Add(T item)
    {
        _items[_count] = item;
        _count = _count + 1;
    }
}

public Money Total(Register<IPriced> register)
{
    var sum = Cents(0);
    for (nuint i = 0; i < register.Count(); i = i + 1)
    {
        sum = Add(sum, register.At(i).Price());
    }
    return sum;
}
