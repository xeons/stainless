// SPDX-License-Identifier: 0BSD
// samples/shop/src/Shop/Bundles.sl  ->  module Shop.Bundles
module Shop.Bundles;

import Shop.Catalog;
import Shop.Pricing;

// A class in this module implementing an interface declared in another one.
// Nothing had to be exported or forward declared to make that work.
public class Bundle : IPriced {
    String name;
    IPriced[] items;          // an array of interface references
    nuint count;

    public Bundle(String label, nuint capacity) {
        name = label;
        items = new IPriced[capacity];
        count = 0;
    }

    public void Include(IPriced item) {
        items[count] = item;
        count += 1;
    }

    public Money Price() {
        var total = Cents(0);
        for (nuint i = 0; i < count; i += 1) {
            // Dynamic dispatch: each element may be a Book, a Subscription,
            // or another Bundle.
            total = Add(total, items[i].Price());
        }
        return total;
    }

    public String Label() {
        return name + " (" + Text.FromInteger(count) + " items)";
    }
}
