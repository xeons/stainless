// SPDX-License-Identifier: 0BSD
// samples/shop/src/Shop/Bundles.sl  ->  module Shop.Bundles
module Shop.Bundles;

import Standard.Unchecked;
import Shop.Catalog;
import Shop.Pricing;

// A class in this module implementing an interface declared in another one.
// Nothing had to be exported or forward declared to make that work.
public class Bundle : IPriced
{
    String _name;
    // An array of interface references. The slots past `_count` are not
    // items yet, and are written before they are read.
    IPriced[] _items;
    nuint _count;

    public Bundle(String label, nuint capacity)
    {
        _name = label;
        _items = NewUninitializedArray<IPriced>(capacity);
        _count = 0;
    }

    public void Add(IPriced item)
    {
        _items[_count] = item;
        _count++;
    }

    public Money Price
    {
        get
        {
            var total = CreateMoney(0);
            for (nuint i = 0; i < _count; i++)
            {
                // Dynamic dispatch: each element may be a Book, a Subscription,
                // or another Bundle.
                total = AddMoney(total, _items[i].Price);
            }
            return total;
        }
    }

    public String Label => _name + " (" + Text.FromInteger(_count) + " items)";
}
