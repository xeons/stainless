// SPDX-License-Identifier: 0BSD
module Shop.Catalog;

public class Book {
    String title;
    public Book(String name) { title = name; }
    public String Title() { return title; }
}

// Module-wide, not exported: the sibling file can see it, importers cannot.
String Decorate(String text) { return "<" + text + ">"; }
