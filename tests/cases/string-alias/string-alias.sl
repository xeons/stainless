// SPDX-License-Identifier: 0BSD
//
// `string` — `String` spelled the way the primitives are.
//
// It is declared in `Standard.Text`, which every file imports without asking,
// so no program needs an alias of its own to say it. There is no second type
// here and nothing to convert: the two names are interchangeable in every
// position a type can appear, and a diagnostic names `String` whichever one
// the source wrote.
module StringAlias;

import Standard.Console;
import Standard.Text;
import Standard.Collections;

class Person
{
    public string Name;
    public Person(string name) { Name = name; }
    public string Describe() => "a person called " + Name;
}

string Greeting(string who) => "hello, " + who;

int Main()
{
    string who = "world";
    Console.WriteLine(Greeting(who));

    // The alias is the type, so one name assigns to the other both ways.
    String there = who;
    string back = there;
    Console.WriteLine(back);

    // A member call reaches the methods `Standard.Text` writes for `String`.
    Console.WriteLine(Text.FromInteger((int)who.ByteLength()));
    Console.WriteLine(who.ToUpperAscii());

    Console.WriteLine(new Person("ada").Describe());

    // Through a generic, and through a tuple inside one.
    var names = new List<string>();
    names.Add("grace");
    names.Add("edsger");
    foreach (string name in names)
        Console.WriteLine(name);

    var pairs = new List<(int, string)>();
    pairs.Add((1, "one"));
    Console.WriteLine(Text.FromInteger(pairs[0u].Item1) + " = " + pairs[0u].Item2);

    return 0;
}
