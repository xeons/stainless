// SPDX-License-Identifier: 0BSD
// samples/shop/src/Program.sl  ->  module Program
//
// Sits directly under the root, so its inferred name has no dots.
module Program;

import Standard.Console;
import Shop.Catalog;
import Shop.Inventory;

// An alias, for when a module's last segment reads badly at the call site.
import Shop.Pricing as Money;

// Shop.Bundles is deliberately NOT imported. A fully qualified name still
// reaches it, because qualification names the module directly.

int Main()
{
    var register = new Register<IPriced>(4);

    // `Book` and `Subscription` come from Shop.Catalog, unqualified.
    register.Add(new Book("The Annotated Turing", Money.CreateMoney(3499)));
    register.Add(new Subscription("Journal", Money.CreateMoney(500), 12));

    // Fully qualified, with no import of Shop.Bundles anywhere in this file.
    var boxed = new Shop.Bundles.Bundle("Starter set", 2);
    boxed.Add(new Book("SICP", Money.CreateMoney(5200)));
    boxed.Add(new Book("TAPL", Money.CreateMoney(6800)));
    register.Add(boxed);

    foreach (var item in register)
    {
        Console.WriteLine("  " + item.Label + " = " + Money.FormatMoney(item.Price));
    }

    // SumPrices comes from Shop.Inventory; FormatMoney from Shop.Pricing via
    // its alias.
    var total = SumPrices(register);
    Console.WriteLine("total = " + Money.FormatMoney(total));
    Console.WriteLine("twice = " + Money.FormatMoney(Money.DoubleMoney(total)));
    return 0;
}
