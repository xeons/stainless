// SPDX-License-Identifier: 0BSD
// samples/shop/src/Shop/Inventory.sl  ->  module Shop.Inventory
module Shop.Inventory;

import Shop.Catalog;
import Shop.Pricing;

// A generic declared here, instantiated from another module entirely.
public class Register<T> {
    T[] items;
    nuint count;

    public Register(nuint capacity) {
        items = new T[capacity];
        count = 0;
    }

    public nuint Count() { return count; }
    public T At(nuint index) { return items[index]; }

    public void Add(T item) {
        items[count] = item;
        count += 1;
    }

    /// `foreach` finds this by name rather than by interface, so a Register is
    /// iterable without implementing anything or importing Standard.Collections.
    public RegisterCursor<T> GetEnumerator() { return new RegisterCursor<T>(this); }
}

public class RegisterCursor<T> {
    Register<T> source;
    nuint next;

    public RegisterCursor(Register<T> register) {
        source = register;
        next = 0;
    }

    public bool MoveNext() {
        if (next >= source.Count()) { return false; }
        next += 1;
        return true;
    }

    public T Current() { return source.At(next - 1); }
}

public Money Total(Register<IPriced> register) {
    var sum = Cents(0);
    foreach (var item in register) { sum = Add(sum, item.Price()); }
    return sum;
}
