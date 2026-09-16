// SPDX-License-Identifier: 0BSD
module Text.Demo;

import Standard.Console;

extern "C" int printf(byte* format, ...);

class Person
{
    String _name;

    Person(String who) => _name = who;
    ~Person() { Console.Write("~Person "); Console.WriteLine(_name); }

    public String Name => _name;
    public String Greeting() => "Hello, " + _name;
}

int Main()
{
    String a = "Hello";
    String b = "World";
    Console.WriteLine(a + ", " + b + "!");

    printf("bytes=%llu points=%llu\n", a.ByteLength(), a.CodePointCount());

    // Multi-byte UTF-8: bytes, scalars and UTF-16 units all differ.
    String accented = "n\u00e4ive caf\u00e9";
    printf("utf8=%llu points=%llu utf16=%llu\n",
           accented.ByteLength(), accented.CodePointCount(), accented.ToUtf16().UnitCount());

    // Value equality: the left side is built on the heap at run time.
    printf("eq=%d ne=%d\n", ("Hel" + "lo") == a, a != b);

    printf("cstring=%s\n", b.ToPointer());
    Console.WriteLine(b.Substring(0, 3));
    printf("empty=%d\n", "".IsEmpty());

    {
        var p = new Person("Ada");
        Console.WriteLine(p.Greeting());
        Console.WriteLine(p.Name);
    }
    Console.WriteLine("after scope");

    // Each iteration makes two temporaries that must be released on the spot.
    String accumulated = "";
    for (int i = 0; i < 3; i = i + 1)
    {
        accumulated = accumulated + Text.FromInteger(i) + ",";
    }
    Console.WriteLine(accumulated);
    return 0;
}
