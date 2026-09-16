// SPDX-License-Identifier: 0BSD
//
// `as` asks what `is` asks and answers with a value: the reference, or null.
// What it is for is the answer that gets passed on rather than branched on --
// `(shape as INamed)?.Name ?? "anonymous"` is one expression where an `is`
// would be a statement, a local and two branches.
module AsOperator;

import Standard.Console;
import Standard.Text;

public interface INamed
{
    String Name { get; }
}

public class Shape
{
    public virtual int Sides() => 0;
}

public class Square : Shape, INamed
{
    public override int Sides() => 4;
    public String Name => "square";
}

public class Circle : Shape { }

/// The branching use, which `is C c` also covers.
String Describe(Shape shape)
{
    Square? square = shape as Square;

    if (square != null)
        return "square with " + Text.FromInteger(square.Sides()) + " sides";

    return "not a square";
}

/// The one it exists for: an answer with no branch anywhere in it.
String NameOf(Shape shape)
{
    return (shape as INamed)?.Name ?? "anonymous";
}

int Main()
{
    Shape square = new Square();
    Shape circle = new Circle();

    Console.WriteLine(Describe(square));
    Console.WriteLine(Describe(circle));

    Console.WriteLine(NameOf(square));
    Console.WriteLine(NameOf(circle));

    // Through an optional, where the null is an answer of its own rather than
    // a question the test has to ask separately.
    Shape? nothing = null;
    Console.WriteLine(NameOf(nothing ?? circle));

    // Upwards there is nothing to ask: every Square is a Shape, so this is the
    // ordinary widening and no test is emitted for it.
    Shape? widened = square as Shape;
    Console.WriteLine(Text.FromInteger(widened?.Sides() ?? -1));

    // The value is read once. `Made()` allocates, and a second evaluation
    // would be a second object -- and a leak of the first.
    Console.WriteLine(NameOf(Made()));
    return 0;
}

Shape Made()
{
    Console.WriteLine("made one");
    return new Square();
}
