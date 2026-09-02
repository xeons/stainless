// samples/shop/src/Shop/Catalog.sl  ->  module Shop.Catalog
module Shop.Catalog;

// Brings Shop.Pricing's public members into scope. After this, its members can
// be named three ways: bare (`Money`), by last segment (`Pricing.Money`), or
// fully (`Shop.Pricing.Money`).
import Shop.Pricing;

public interface Priced {
    Money Price();
    String Label();
}

public class Book : Priced {
    String title;
    Money price;

    public Book(String name, Money amount) {
        title = name;
        price = amount;
    }

    // `Money` unqualified, because Shop.Pricing is imported.
    public Money Price() { return price; }
    public String Label() { return title; }
}

public class Subscription : Priced {
    String name;
    Money monthly;
    int months;

    public Subscription(String label, Money perMonth, int count) {
        name = label;
        monthly = perMonth;
        months = count;
    }

    public Money Price() {
        // Qualified by the module's last segment.
        var total = Pricing.Cents(0);
        for (int i = 0; i < months; i = i + 1) { total = Pricing.Add(total, monthly); }
        return total;
    }

    public String Label() { return name + " x" + Text.FromInteger(months); }
}
