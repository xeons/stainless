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
        count = count + 1;
    }
}

public Money Total(Register<IPriced> register) {
    var sum = Cents(0);
    for (nuint i = 0; i < register.Count(); i = i + 1) {
        sum = Add(sum, register.At(i).Price());
    }
    return sum;
}
