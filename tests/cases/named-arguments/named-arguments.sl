// SPDX-License-Identifier: 0BSD
//
// `name: value` at a call.
//
// It exists for the call whose arguments a reader cannot tell apart:
// `Draw(text, 3, true, false)` says nothing about which flag is which, and
// `Draw(text, width: 3, center: true, wrap: false)` says all of it. The
// component layer this language is aiming at is full of that shape.
//
// **Named arguments come after positional ones.** Freely mixing the two orders
// would make a reader count past the names to see where a positional one
// lands. Within the names the order is free, because each says where it goes.
//
// The names also take part in choosing an overload, since two candidates may
// call their parameters different things.
module NamedArguments;

import Standard.Console;
import Standard.Convert;

String Draw(String text, int width, bool center, char fill) {
    var pad = new StringBuilder();
    for (int i = 0; i < width; i++) { pad.Append(Text.FromChar((char32)fill)); }
    return (center ? "[" : "<") + text + pad.ToText() + (center ? "]" : ">");
}

class Rect {
    public int Left; public int Top; public int Right; public int Bottom;

    public Rect(int left, int top, int right, int bottom) {
        Left = left; Top = top; Right = right; Bottom = bottom;
    }

    public String Text() { return $"{Left},{Top} {Right},{Bottom}"; }
}

// Two overloads whose second parameter is named differently, so the name is
// what says which was meant.
String Show(int value, bool hex) {
    return hex ? "0x" + FromLong((long)value, 16u) : Text.FromInteger((long)value);
}

String Show(String value, bool quoted) { return quoted ? "\"" + value + "\"" : value; }

// A name beside `out`, which is a modifier rather than a value.
bool TryHalve(int n, out int half, bool evenOnly) {
    if (evenOnly && n % 2 != 0) { half = 0; return false; }
    half = n / 2;
    return true;
}

public int Main() {
    // Positional, for comparison.
    Console.WriteLine(Draw("hi", 3, true, '.'));

    // Every argument named, in declared order.
    Console.WriteLine(Draw(text: "hi", width: 3, center: false, fill: '-'));

    // Named, in a different order from the declaration.
    Console.WriteLine(Draw(fill: '*', center: true, text: "any", width: 2));

    // Positional first, then names.
    Console.WriteLine(Draw("some", 4, center: false, fill: '+'));

    // A constructor, which is where this reads best.
    var box = new Rect(left: 1, top: 2, right: 30, bottom: 40);
    Console.WriteLine($"rect   {box.Text()}");

    var mixed = new Rect(1, 2, bottom: 40, right: 30);
    Console.WriteLine($"mixed  {mixed.Text()}");

    // The name picking between overloads.
    Console.WriteLine($"hex    {Show(255, hex: true)}");
    Console.WriteLine($"quoted {Show("text", quoted: true)}");

    // Beside `out`, whose variable the call declares.
    if (TryHalve(9, out var half, evenOnly: false)) { Console.WriteLine($"half   {half}"); }
    if (!TryHalve(9, out var nothing, evenOnly: true)) { Console.WriteLine($"refused {nothing}"); }
    return 0;
}
