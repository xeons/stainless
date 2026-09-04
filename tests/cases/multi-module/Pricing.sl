// SPDX-License-Identifier: 0BSD
// samples/shop/src/Shop/Pricing.sl
//
// This file joins the module `Shop.Pricing`. The name is stated here, never
// inferred from the path -- so moving this file changes nothing, and several
// files may name the same module and merge into it.
module Shop.Pricing;

// `public` is the only thing that controls what other modules can see.
public struct Money {
    public long Cents;

    public double AsDollars() { return (double)Cents / 100.0; }
}

public Money Cents(long amount) {
    Money m;
    m.Cents = amount;
    return m;
}

public Money Add(Money left, Money right) {
    return Cents(left.Cents + right.Cents);
}

public String Format(Money amount) {
    return "$" + Text.FromDouble(amount.AsDollars());
}

// No `public`, so nothing outside Shop.Pricing can name this -- not even
// Shop.Catalog, which imports the module.
long Doubled(long value) { return value * 2; }

public Money Twice(Money amount) { return Cents(Doubled(amount.Cents)); }
