// SPDX-License-Identifier: 0BSD
//
// A struct's constructor: `new` over a slot rather than an allocation. What is
// checked here is that the value is a value -- copied on assignment, laid out
// as C lays it out -- and that a field no constructor wrote is the zero the
// declared form would have left there.
module StructConstructors;

import Standard.Console;
import Standard.Text;

String N(long value) => Text.FromInteger(value);

public struct Point
{
    public int X;
    public int Y;

    public Point(int x, int y)
    {
        X = x;
        Y = y;
    }

    // Overloaded, and delegating: the square is the rectangle with one side.
    public Point(int both) : this(both, both) { }

    public int Sum => X + Y;
}

// A field the constructors do not write, to prove the slot starts zeroed.
public struct Span
{
    public int Start;
    public int Length;
    public int Mark;

    public Span(int start, int length)
    {
        Start = start;
        Length = length;
    }

    public int End() => Start + Length;
}

// A struct holding a reference, so the constructor's store is a retain and the
// temporary's drop is a release.
public struct Tag
{
    public String Name;
    public int Weight;

    public Tag(String name, int weight)
    {
        Name = name;
        Weight = weight;
    }
}

// A constructor with work in it, and one whose body writes through `this`.
public struct Checksum
{
    public nuint Value;

    public Checksum(String text)
    {
        this.Value = 0u;
        for (nuint i = 0u; i < text.ByteLength(); i++)
            this.Value = this.Value * 31u + (nuint)text.GetByteAt(i);
    }
}

// A generic struct, whose constructor is instantiated with everything else.
public struct Pair<T>
{
    public T First;
    public T Second;

    public Pair(T first, T second)
    {
        First = first;
        Second = second;
    }
}

int SumOf(Point point) => point.X + point.Y;

// A struct made where a static's value is settled, which is before Main.
static Point s_origin = new Point(1, 2);

// And one made where a class's field is.
public class Sheet
{
    public Span Area = new Span(2, 3);
    public Tag Label;

    public Sheet(String name) => Label = new Tag(name, 1);
}

int Main()
{
    var point = new Point(3, 4);
    Console.WriteLine("point " + N((long)point.X) + " " + N((long)point.Y) + " " +
        N((long)point.Sum));

    // Delegated, and the copy is a copy: writing to one does not reach the other.
    var square = new Point(5);
    var copy = square;
    copy.X = 9;
    Console.WriteLine("square " + N((long)square.X) + " " + N((long)square.Y) + " " +
        N((long)copy.X));

    // Handed straight to a function, and made inside an expression.
    Console.WriteLine("sum " + N((long)SumOf(new Point(10, 20))) + " " +
        N((long)new Point(2, 3).Sum));

    var span = new Span(4, 6);
    Console.WriteLine("span " + N((long)span.Start) + " " + N((long)span.End()) + " " +
        N((long)span.Mark));

    // Into an array element and out again, which is a copy each way.
    var spans = new Span[2];
    spans[1] = new Span(7, 1);
    Console.WriteLine("stored " + N((long)spans[1].Start) + " " + N((long)spans[0].Start));

    var tag = new Tag("alpha" + "-one", 2);
    var same = tag;
    Console.WriteLine("tag " + tag.Name + " " + same.Name + " " + N((long)tag.Weight));

    var sum = new Checksum("abc");
    Console.WriteLine("checksum " + N((long)sum.Value));

    // Made and dropped a great many times, so a store that failed to retain or
    // a temporary that failed to release would show as a crash rather than as
    // a number.
    nuint counted = 0u;
    for (nuint i = 0u; i < 200u; i++)
    {
        var made = new Tag("x" + N((long)i), (int)i);
        counted += made.Name.ByteLength();
    }
    Console.WriteLine("counted " + N((long)counted));

    // Named members after the constructor ran, as on a class.
    var marked = new Span(1, 2) { Mark = 5 };
    Console.WriteLine("marked " + N((long)marked.Start) + " " + N((long)marked.Mark));

    var numbers = new Pair<int>(1, 2);
    var words = new Pair<String>("a", "b");
    Console.WriteLine("pair " + N((long)numbers.Second) + " " + words.First + words.Second);

    var sheet = new Sheet("sheet");
    Console.WriteLine("fields " + N((long)s_origin.Sum) + " " + N((long)sheet.Area.End()) +
        " " + sheet.Label.Name);

    // The layout is C's: a constructor adds no header and no hidden field.
    Console.WriteLine("size " + N((long)sizeof(Point)) + " " + N((long)sizeof(Span)));

    return 0;
}
