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

public class Subscription : IPriced
{
    String _name;
    Money _monthly;
    int _months;

    public Subscription(String label, Money perMonth, int count)
    {
        _name = label;
        _monthly = perMonth;
        _months = count;
    }

    public Money Price
    {
        get
        {
            var total = Pricing.CreateMoney(0);
            for (int i = 0; i < _months; i++)
                total = Pricing.AddMoney(total, _monthly);
            return total;
        }
    }

    // QuoteTitle comes from Books.sl -- same module, no import.
    public String Label => QuoteTitle(_name) + " x" + Text.FromInteger(_months);
}
