// SPDX-License-Identifier: 0BSD
// The same module, written in a second file. No import between them.
module Shop.Catalog;

public class Bundle
{
    Book _first;
    public Bundle(Book b) => _first = b;
    public String Describe() => Decorate(_first.Title());
}
