// SPDX-License-Identifier: 0BSD
module Shop.Catalog;

public class Book
{
    String _title;
    public Book(String name) => _title = name;
    public String Title() => _title;
}

// Module-wide, not exported: the sibling file can see it, importers cannot.
String Decorate(String text) => "<" + text + ">";
