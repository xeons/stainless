// SPDX-License-Identifier: 0BSD
//
// `T F(args) => expression;` — a body written as the one thing it does.
//
// The same desugaring a property's arrow already had, extended to functions:
// one that returns a value returns the expression, and a `void` one evaluates
// it. That second half is what makes `void Bump() => _count++;` legal, and it
// is why the form is not simply "a return written shorter".
//
// It is a body like any other, so everything that works on a braced one works
// here: a method, a static method, a module-level function, an override, an
// interface implementation, a generic, and a recursive call.
module ExpressionBodied;

import Standard.Console;
import Standard.Text;

interface IArea
{
    int Area();
}

class Square : IArea
{
    int _side;
    int _touched;

    public Square(int side)
    {
        _side = side;
        _touched = 0;
    }

    // A value comes back.
    public virtual int Area() => _side * _side;

    // A `void` arrow evaluates its expression and returns nothing, so a step
    // and a call are both bodies a method may have.
    public void Grow() => _side++;

    public void Touch() => Note();

    void Note() => _touched++;

    public int Touched() => _touched;

    // A property's arrow, which is where the form started, still works.
    public int Side => _side;
}

class Cube : Square
{
    // A constructor returns nothing, so its arrow evaluates the expression the
    // way a `void` one does. `base(...)` is a call like any other.
    public Cube(int side) => base(side);

    // An override is a body like any other.
    public override int Area() => Side * Side * 6;
}

// An operator and a conversion always give a value back, so their arrows are
// a getter's. A type initializer's is a `void` one.
struct Money
{
    public long Cents;

    public static Money Of(long cents)
    {
        Money made;
        made.Cents = cents;
        return made;
    }

    public static Money operator +(Money a, Money b) => Of(a.Cents + b.Cents);

    public static explicit operator long(Money m) => m.Cents;
}

class Registry
{
    public static String Kind = "";

    static Registry() => Kind = "registry";
}

int Twice(int n) => n * 2;

// A generic one, and a recursive call inside an arrow.
T Pick<T>(bool first, T a, T b) => first ? a : b;

int Factorial(int n) => n <= 1 ? 1 : n * Factorial(n - 1);

void Say(String label, long value)
{
    Console.WriteLine(label + " " + Text.FromInteger(value));
}

int Main()
{
    var square = new Square(4);
    Say("area", (long)square.Area());

    square.Grow();
    Say("grown", (long)square.Area());
    Say("side", (long)square.Side);

    square.Touch();
    square.Touch();
    Say("touched", (long)square.Touched());

    // Through the interface, so the arrow body is reached by dynamic dispatch.
    IArea through = square;
    Say("dispatch", (long)through.Area());

    IArea cube = new Cube(3);
    Say("override", (long)cube.Area());

    Say("free", (long)Twice(21));
    Say("generic", (long)Pick(true, 7, 3));
    Say("recursive", (long)Factorial(5));

    var total = Money.Of(30) + Money.Of(12);
    Say("operator", (long)total);
    Console.WriteLine("static " + Registry.Kind);

    return 0;
}
