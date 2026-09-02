// samples/shop/src/Shop/Catalog/Books.sl
//
// One of TWO files that make up `Shop.Catalog`. The module is named here, in
// the file -- folders are a convention for people, not something the compiler
// reads.
module Shop.Catalog;

import Shop.Pricing;

public interface IPriced {
    Money Price();
    String Label();
}

public class Book : IPriced {
    String title;
    Money price;

    public Book(String name, Money amount) {
        title = name;
        price = amount;
    }

    public Money Price() { return price; }
    public String Label() { return Decorate(title); }
}

// No `public`: visible throughout Shop.Catalog, including its other file, but
// invisible to anyone who imports the module. This is C#'s `internal`, with the
// module playing the part of the assembly.
String Decorate(String text) { return "\"" + text + "\""; }
