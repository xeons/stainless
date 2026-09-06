// SPDX-License-Identifier: 0BSD
//
// `nameof`, and `checked` / `unchecked`.
//
// **`nameof`** answers with the last name written, as a `String` — and what it
// buys over the string literal is that the name is bound. Reflection here is
// reached by name (`FindType`, `Field.Name`, a property by its spelling), so a
// document naming a member that was renamed underneath it fails at run time
// with nothing to say. `nameof` moves that to the compiler.
//
// **`checked`** asks `+`, `-` and `*` on integers to notice that they
// overflowed. Wrapping is the default and is defined (§9) rather than being
// undefined the way C leaves it, so this is opt-in: it costs a test and a
// branch, and it aborts rather than producing a number that is not the answer.
module NameofChecked;

import Standard.Console;

class Button {
    public String Caption { get; set; }
    public int Width { get; set; }

    public Button(String caption) { Caption = caption; Width = 80; }

    public void Press() { }
}

struct Point { public int X; public int Y; }

static int Total = 0;

public int Main() {
    var button = new Button("Save");
    Point spot;
    spot.X = 3;

    // A local, a parameter's type, a field, a property, a method and a static.
    int local = 1;

    Console.WriteLine($"local    {nameof(local)}");
    Console.WriteLine($"type     {nameof(Button)}");
    Console.WriteLine($"struct   {nameof(Point)}");
    Console.WriteLine($"field    {nameof(spot.X)}");
    Console.WriteLine($"property {nameof(button.Caption)}");
    Console.WriteLine($"method   {nameof(button.Press)}");
    Console.WriteLine($"static   {nameof(Total)}");
    Console.WriteLine($"function {nameof(Main)}");

    // The whole point: it is the *last* name, not the path to it.
    Console.WriteLine($"last     {nameof(button.Width)}");

    // ---------------------------------------------------------- arithmetic

    int big = 2147483647;
    int small = -2147483648;

    // Wrapping, which is what happens without asking.
    Console.WriteLine($"wraps    {big + 1}");
    Console.WriteLine($"says so  {unchecked(big + 1)}");
    Console.WriteLine($"down     {small - 1}");

    // Checked, and not overflowing, so the value is the ordinary one.
    Console.WriteLine($"checked  {checked(big - 1)}");
    Console.WriteLine($"times    {checked(1000 * 1000)}");

    // A block, spot everything inside is watched.
    checked {
        int a = 1000000;
        int b = 2000;
        Console.WriteLine($"block    {a + b}");
        Console.WriteLine($"block    {a * 2}");
    }

    // And `unchecked` inside it puts the default back.
    checked {
        unchecked {
            Console.WriteLine($"back     {big + 1}");
        }
    }

    // Unsigned overflow is its own question: 200 + 100 fits a ushort and does
    // not fit a short, and the two ask different intrinsics.
    ushort room = 60000;
    Console.WriteLine($"ushort   {checked(room + 5000)}");

    // Floats have nothing to check: they go to infinity rather than wrapping.
    double huge = 1.0e308;
    Console.WriteLine($"double   {checked(huge * 10.0) > 1.0e308}");
    return 0;
}
