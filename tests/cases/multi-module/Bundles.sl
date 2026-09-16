// SPDX-License-Identifier: 0BSD
// samples/shop/src/Shop/Bundles.sl  ->  module Shop.Bundles
module Shop.Bundles;

import Shop.Catalog;
import Shop.Pricing;

// A class in this module implementing an interface declared in another one.
// Nothing had to be exported or forward declared to make that work.
public class Bundle : IPriced
{
    String _name;
    IPriced[] _items;          // an array of interface references
    nuint _count;

    public Bundle(String label, nuint capacity)
    {
        _name = label;
        _items = new IPriced[capacity];
        _count = 0;
    }

    public void Include(IPriced item)
    {
        _items[_count] = item;
        _count = _count + 1;
    }

    public Money Price()
    {
        var total = Cents(0);
        for (nuint i = 0; i < _count; i = i + 1)
        {
            // Dynamic dispatch: each element may be a Book, a Subscription,
            // or another Bundle.
            total = Add(total, _items[i].Price());
        }
        return total;
    }

    public String Label()
    {
        return _name + " (" + Text.FromInteger(_count) + " items)";
    }
}
