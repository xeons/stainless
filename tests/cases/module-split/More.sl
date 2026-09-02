// SPDX-License-Identifier: 0BSD
// The same module, written in a second file. No import between them.
module Shop.Catalog;

public class Bundle {
    Book first;
    public Bundle(Book b) { first = b; }
    public String Describe() { return Decorate(first.Title()); }
}
