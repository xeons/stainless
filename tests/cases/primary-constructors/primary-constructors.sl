// SPDX-License-Identifier: 0BSD
//
// A parameter list after a class or struct's name is its primary constructor.
// The parameters are in scope through the whole body: an initializer and the
// base's arguments read the parameter itself, and a member body reads a hidden
// field the constructor copied it into -- made only for the parameters some
// member body names, laid out after the declared fields.
module PrimaryConstructors;

import Standard.Console;
import Standard.Text;

public class Logger
{
    public String Prefix;

    public Logger(String prefix)
    {
        Prefix = prefix;
    }

    ~Logger()
    {
        Console.WriteLine("released " + Prefix);
    }

    public void Log(String line) => Console.WriteLine(Prefix + line);
}

public closure String Describer();

/// `log` and `size` are named by member bodies, so both are kept; `size` is
/// also read by two initializers, which see the parameter.
public class Service(Logger log, int size)
{
    public int Doubled = size * 2;
    public int Size { get; } = size;

    /// Another constructor runs the primary one first.
    public Service(Logger log) : this(log, 1) { }

    public void Run()
    {
        log.Log("running " + Text.FromInteger(size));
        size++;
    }

    /// A lambda reads the kept copy through the object, so it sees the change.
    public Describer Describe() => () => "size " + Text.FromInteger(size);

    public int Scaled(int by)
    {
        int Times(int n) => n * size;
        return Times(by);
    }
}

/// Only an initializer names `seed`, so nothing is kept: the class holds its
/// one declared field and no more.
public class Seeded(int seed)
{
    public int First = seed + 1;
}

public class Shape(String name)
{
    public String Name => name;
    public virtual String Kind => "shape";
}

/// `: Shape("circle")` is the primary constructor's call to the base.
public class Circle(double radius) : Shape("circle")
{
    public override String Kind => "round";
    public double Area => radius * radius * 3.0;
}

/// A struct keeps what it keeps inside its own value, after the fields it
/// declares, and may give those fields initializers: every constructor of it
/// runs the primary one.
public struct Point(int x, int y)
{
    public int X = x;
    public int Y = y;

    public int Sum() => x + y;
}

public struct Plain(int x, int y)
{
    public int X = x;
    public int Y = y;
}

public class Box<T>(T value)
{
    public T Get() => value;
}

/// A parameter list and nothing else.
public class Tag(String text);

/// A record passes its own arguments on the same way.
public class Entity(int key)
{
    public int Key => key;
}

public record Item(int Id, String Name) : Entity(Id * 10);

int Main()
{
    var service = new Service(new Logger("[a] "), 4);
    service.Run();
    service.Run();
    Console.WriteLine(Text.FromInteger(service.Doubled) + " " + Text.FromInteger(service.Size));
    Console.WriteLine(service.Describe()() + " " + Text.FromInteger(service.Scaled(2)));

    var other = new Service(new Logger("[b] "));
    other.Run();

    Console.WriteLine(Text.FromInteger(new Seeded(4).First));

    Shape shape = new Circle(2.0);
    var circle = (Circle)shape;
    Console.WriteLine(shape.Name + " " + shape.Kind + " " + Text.FromDouble(circle.Area));

    var point = new Point(3, 4);
    Point made = new(5, 6);
    var plain = new Plain(1, 2);
    Console.WriteLine(Text.FromInteger(point.X + point.Y) + " " + Text.FromInteger(point.Sum()) +
                      " " + Text.FromInteger(made.Sum()));
    Console.WriteLine(Text.FromInteger((int)sizeof(Point)) + " " +
                      Text.FromInteger((int)sizeof(Plain)) + " " + Text.FromInteger(plain.X));

    var box = new Box<Logger>(new Logger("[boxed] "));
    box.Get().Log("hello");

    var tag = new Tag("t");
    var item = new Item(7, "seven");
    Console.WriteLine(Text.FromInteger(item.Key) + " " + item.Name);
    return 0;
}
