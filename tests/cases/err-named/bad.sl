// SPDX-License-Identifier: 0BSD
module Bad;

// A name says which parameter a value is for, so it has to be a parameter, it
// has to be one nothing else already filled, and it has to leave none empty.
// And the names come last, so that a reader never has to count past them.

String Draw(String text, int width, bool center) => text;

class Rect
{
    public Rect(int left, int top) { }
}

class Square : Rect
{
    // A chained constructor takes its arguments in order: there is no
    // declaration here for a name to match against.
    public Square(int side) => base(left: 0, top: 0);
}

int Main()
{
    // No parameter of that name.
    Draw("hi", width: 2, middle: true);

    // Given twice, once by position and once by name.
    Draw("hi", 2, text: "again");

    // Nothing for `center`.
    Draw(text: "hi", width: 2);

    // A positional argument after a named one.
    Draw(text: "hi", 2, true);

    // The same rules for a constructor.
    var r = new Rect(left: 1, up: 2);
    return 0;
}
