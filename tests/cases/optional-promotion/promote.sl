// SPDX-License-Identifier: 0BSD
//
// A value becomes the `Optional<T>` holding it, the way it becomes a `T?` in
// Swift and C#.
//
// The rule exists so that an indexer can be honest. A getter and a setter
// share one type (§7.5), so a subscript that answers `Optional<V>` takes one
// as well -- and without this every write would read `map[key] = Some(value)`.
// With it, the setter's type says something instead: `None` is the absence of
// a value, which is what removing a key means.
module Promote;

import Standard.Console;
import Standard.Text;
import Standard.Collections;

String N(long v) { return Text.FromInteger(v); }

// An exact match still wins. A promotion is a conversion, and a conversion
// never beats a signature that already fits.
String Which(int v) { return "int"; }
String Which(Optional<int> v) { return "optional"; }

// And is available where nothing exact is there.
String Only(Optional<int> v) { return N((long)v.ValueOr(-1)); }

Optional<int> Returned(int v) { return v; }
Optional<String> Named(String s) { return s; }

struct Point { public int X; public int Y; }

class Node { public int Value; public Node(int v) { Value = v; } }

int Main() {
    Optional<int> number = 5;
    Optional<String> text = "text";
    Optional<int> nothing = None;
    Console.WriteLine("promoted " + N((long)number.ValueOr(-1)) + " " +
        text.ValueOr("?") + " " + N((long)nothing.ValueOr(-1)));

    // Through a return, an argument and an assignment alike.
    Console.WriteLine("shapes " + N((long)Returned(9).ValueOr(-1)) + " " +
        Named("ok").ValueOr("?") + " " + Only(7));

    Console.WriteLine("overload " + Which(5) + " " + Which(Some(5)));

    // A struct, which is an ordinary payload.
    Point p;
    p.X = 3;
    p.Y = 4;
    Optional<Point> located = p;
    if (located is Some here) {
        Console.WriteLine("struct " + N((long)(here.Value.X + here.Value.Y)));
    }

    // A counted reference, which the variant owns like any other field.
    Optional<Node> held = new Node(11);
    if (held is Some node) { Console.WriteLine("class " + N((long)node.Value.Value)); }

    // Something already an Optional is not wrapped twice.
    Optional<int> again = number;
    Console.WriteLine("idempotent " + N((long)again.ValueOr(-1)));

    // But an Optional assigned to an Optional of one is, which is what it
    // means rather than a mistake.
    Optional<Optional<int>> nested = number;
    if (nested is Some lifted) {
        Console.WriteLine("nested " + N((long)lifted.Value.ValueOr(-1)));
    }

    // What the rule was for.
    var settings = new Dictionary<String, int>();
    settings["port"] = 8080;
    Console.WriteLine("subscript " + N((long)settings["port"].ValueOr(-1)) + " " +
        N((long)settings["absent"].ValueOr(-1)));

    return 0;
}
