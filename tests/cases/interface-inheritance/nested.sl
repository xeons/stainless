// SPDX-License-Identifier: 0BSD
module Nested;

import Standard.Console;

public interface IReadable
{
    String Read();
}

public interface IWritable : IReadable
{
    void Write(String text);
}

public class Slot : IWritable
{
    String _value;

    public Slot(String initial) => _value = initial;

    public String Read() => _value;
    public void Write(String text) => _value = text;
}

// A value typed by the derived interface still answers the base one's methods,
// and converts to it with no cost.
String Show(IReadable source) => source.Read();

int Main()
{
    IWritable slot = new Slot("first");
    Console.WriteLine(slot.Read());       // declared on IReadable
    slot.Write("second");
    Console.WriteLine(Show(slot));        // IWritable -> IReadable
    return 0;
}
