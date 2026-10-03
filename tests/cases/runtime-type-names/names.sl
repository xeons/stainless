// SPDX-License-Identifier: 0BSD
//
// RuntimeHelpers.GetTypeName<T>: a constant per instantiation, for any T and
// without [Reflect].
module Names;

import Standard.Console;
import Standard.Collections;

public interface IGreeter
{
    String Greet();
}

public struct Point
{
    public int X;
    public int Y;
}

public class Box<T>
{
    public String Describe() => "Box of " + RuntimeHelpers.GetTypeName<T>();
}

String NameThrough<T>() => RuntimeHelpers.GetTypeName<T>();

public int Main()
{
    Console.WriteLine(RuntimeHelpers.GetTypeName<IGreeter>());
    Console.WriteLine(RuntimeHelpers.GetTypeName<Point>());
    Console.WriteLine(RuntimeHelpers.GetTypeName<int>());
    Console.WriteLine(RuntimeHelpers.GetTypeName<String>());
    Console.WriteLine(RuntimeHelpers.GetTypeName<List<Point>>());
    Console.WriteLine(NameThrough<IGreeter>());
    Console.WriteLine(new Box<Point>().Describe());
    return 0;
}
