// SPDX-License-Identifier: 0BSD
// samples/shop/src/Shop/Catalog/Subscriptions.sl
//
// The second half of `Shop.Catalog`. It needs no import to reach Book, IPriced
// or Decorate: they are already in this module.
//
// It DOES need its own `import Shop.Pricing`, because imports are written per
// file, exactly as `using` is in C#. Books.sl importing it changes nothing here.
module Shop.Catalog;

import Shop.Pricing;

public class Subscription : IPriced {
    String name;
    Money monthly;
    int months;

    public Subscription(String label, Money perMonth, int count) {
        name = label;
        monthly = perMonth;
        months = count;
    }

    public Money Price() {
        var total = Pricing.Cents(0);
        for (int i = 0; i < months; i = i + 1) { total = Pricing.Add(total, monthly); }
        return total;
    }

    // Decorate comes from Books.sl -- same module, no import.
    public String Label() { return Decorate(name) + " x" + Text.FromInteger(months); }
}
