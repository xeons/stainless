// SPDX-License-Identifier: 0BSD
//
// A type is named by its name and its number of type parameters, as in C#, so
// a generic and a non-generic class of one name are two types.
module TypeArity;

import Standard.Console;
import Standard.Text;

public class Work<T>
{
    public T Value { get; }
    public Work(T value) { Value = value; }
}

public class Work
{
    public int Steps { get; }
    public Work() { Steps = 3; }
}

public class Work<T, U>
{
    public T First { get; }
    public U Second { get; }
    public Work(T first, U second)
    {
        First = first;
        Second = second;
    }
}

int Main()
{
    var one = new Work<String>("generic");
    var none = new Work();
    var two = new Work<int, String>(2, "two");
    Console.WriteLine(one.Value + " " + Text.FromInteger((long)none.Steps) + " " +
        Text.FromInteger((long)two.First) + " " + two.Second);
    return 0;
}
