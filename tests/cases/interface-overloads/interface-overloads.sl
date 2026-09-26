// SPDX-License-Identifier: 0BSD
module InterfaceOverloads;

import Standard.Console;

public struct Point
{
    public int X;
    public int Y;

    public Point(int x, int y)
    {
        X = x;
        Y = y;
    }
}

// Each overload takes a slot of its own, so the table has four entries.
public interface IWriter
{
    String Write(int value);
    String Write(long value);
    String Write(String value);
    String Write(Point value);
}

public interface ISink<T>
{
    String Put(T item);
    String Put(T item, int times);
}

// A derived interface overloads a name its base declares.
public interface IWideWriter : IWriter
{
    String Write(double value);
}

public class Label
{
    public String Text;

    public Label(String text) => Text = text;
    ~Label() { Console.WriteLine("~Label " + Text); }
}

public class Writer : IWideWriter
{
    public String Write(int value) => "int " + Text.FromInteger(value);
    public String Write(long value) => "long " + Text.FromInteger(value);
    public String Write(String value) => "text " + value;
    public String Write(Point value) =>
        "point " + Text.FromInteger(value.X) + "," + Text.FromInteger(value.Y);
    public String Write(double value) => "double " + Text.FromDouble(value);
}

// Implemented partly by a base and partly by the class itself.
public class BaseSink
{
    public String Put(Label item) => "one " + item.Text;
}

public class Sink : BaseSink, ISink<Label>
{
    public String Put(Label item, int times) => "many " + item.Text + " x" + Text.FromInteger(times);
}

// Two instantiations of one overloaded interface.
public class Both : ISink<int>, ISink<String>
{
    public String Put(int item) => "int";
    public String Put(int item, int times) => "int x" + Text.FromInteger(times);
    public String Put(String item) => "String";
    public String Put(String item, int times) => "String x" + Text.FromInteger(times);
}

String Drain<T>(ISink<T> sink, T item) => sink.Put(item) + " / " + sink.Put(item, 2);

int Main()
{
    IWideWriter wide = new Writer();
    Console.WriteLine(wide.Write(1));
    Console.WriteLine(wide.Write((long)2));
    Console.WriteLine(wide.Write("three"));
    Console.WriteLine(wide.Write(new Point(4, 5)));
    Console.WriteLine(wide.Write(6.5));

    // Through the base, the double overload is not there, and an int still
    // picks the int overload.
    IWriter narrow = wide;
    Console.WriteLine(narrow.Write(7));

    ISink<Label> sink = new Sink();
    var label = new Label("a");
    Console.WriteLine(sink.Put(label));
    Console.WriteLine(sink.Put(label, 3));
    Console.WriteLine(Drain(sink, new Label("b")));

    var both = new Both();
    Console.WriteLine(Drain<int>(both, 1));
    Console.WriteLine(Drain<String>(both, "x"));

    // A lambda reaching an overload through the interface.
    Func<int, String> through = n => narrow.Write(n);
    Console.WriteLine(through(8));
    return 0;
}
