// An unqualified call to a generic method of the enclosing type is that
// type's method, ahead of a free function of the same name, and a static one
// is called with no receiver.
module GenericStaticSibling;

import Standard.Collections;
import Standard.Console;

public static class Tools
{
    public static void Reverse<T>(T[] items)
    {
        Console.WriteLine($"Tools.Reverse of {items.Length}");
    }

    public static T Twice<T>(T value, Func<T, T, T> add) => add(value, value);

    public static void Run()
    {
        int[] numbers = [1, 2, 3];
        Reverse(numbers);
        Console.WriteLine($"{numbers[0]} {numbers[1]} {numbers[2]}");
        Console.WriteLine($"{Twice(21, (x, y) => x + y)}");
    }
}

public class Counter
{
    private int _count;

    public void Add<T>(T[] items) => _count += (int)items.Length;

    public int Total()
    {
        Add([1, 2]);
        Add(["a"]);
        return _count;
    }
}

int Main()
{
    Tools.Run();
    Console.WriteLine($"{new Counter().Total()}");
    return 0;
}
