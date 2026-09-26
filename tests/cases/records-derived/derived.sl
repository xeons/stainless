// SPDX-License-Identifier: 0BSD
//
// A record deriving from a record: the parameters the base has are the base's,
// equality compares everything and asks for the same type, and `with` copies
// the object whole even when it is reached through its base.
module RecordsDerived;

import Standard.Console;
import Standard.Collections;

record Shape(int Id);
record Circle(int Id, String Name) : Shape(Id);
record Ring(int Id, String Name, bool Filled) : Circle(Id, Name);

// A base that computes its value from the parameter: `with` copies it rather
// than passing it through the computation again.
record Scaled(int Id, String Tag) : Shape(Id * 10);

record Box<T>(T Value);
record Labelled<T>(T Value, String Label) : Box<T>(Value);

void Says(String what, bool value)
{
    Console.WriteLine(what + " " + (value ? "yes" : "no"));
}

public int Main()
{
    var shape = new Shape(1);
    var circle = new Circle(1, "x");
    Shape circleAsShape = circle;

    // --------------------------------------------------------- equality

    Says("shape = circle   ", shape.Equals(circleAsShape));
    Says("circle = shape   ", circleAsShape.Equals(shape));
    Says("circle == same   ", circle == new Circle(1, "x"));
    Says("circle != other  ", circle != new Circle(1, "y"));
    Says("as base, same    ", circleAsShape.Equals(new Circle(1, "x")));
    Shape otherAsShape = new Circle(1, "y");
    Says("as base, other   ", circleAsShape.Equals(otherAsShape));
    Says("hash agrees      ", circle.GetHashCode() == new Circle(1, "x").GetHashCode());

    var ring = new Ring(1, "x", true);
    Circle ringAsCircle = ring;
    Says("circle = ring    ", circleAsShape.Equals(ring));
    Says("ring = ring      ", ringAsCircle.Equals(new Ring(1, "x", true)));
    Says("ring = other ring", ringAsCircle.Equals(new Ring(1, "x", false)));

    // ------------------------------------------------------------- with

    var scaled = new Scaled(3, "t");
    var retagged = scaled with { Tag = "u" };
    Console.WriteLine($"scaled {scaled.Id} {retagged.Id} {retagged.Tag}");

    Shape reached = circle;
    var moved = reached with { Id = 7 };
    Says("copy is a circle ", moved is Circle);
    if (moved is Circle whole)
        Console.WriteLine($"copy {whole.Id} {whole.Name}");
    Console.WriteLine($"original {circle.Id}");

    // ---------------------------------------------------- taking apart

    var (id, name) = circle;
    Console.WriteLine($"two   {id} {name}");
    var (ringId, ringName, filled) = ring;
    Console.WriteLine($"three {ringId} {ringName} {filled}");

    // ----------------------------------------------------- as a key

    var seen = new Dictionary<Shape, String>();
    seen.SetValue(shape, "shape");
    seen.SetValue(circle, "circle");
    String missing = "-";
    String foundCircle = seen.GetValueOrDefault(new Circle(1, "x"), missing);
    String foundShape = seen.GetValueOrDefault(new Shape(1), missing);
    Console.WriteLine($"keys {seen.Count} {foundCircle} {foundShape}");

    // --------------------------------------------------------- generic

    Box<int> labelled = new Labelled<int>(5, "five");
    Says("generic same     ", labelled.Equals(new Labelled<int>(5, "five")));
    Says("generic base     ", labelled.Equals(new Box<int>(5)));
    var changed = labelled with { Value = 6 };
    if (changed is Labelled<int> kept)
        Console.WriteLine($"generic copy {kept.Value} {kept.Label}");
    return 0;
}
