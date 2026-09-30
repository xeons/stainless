// `ref` and `out` arguments to a generic function. The parameter is written as
// the variable's type, so a type argument is read through the address, even
// when that argument is the only one that names it.
module GenericRefOut;

import Standard.Console;

void Swap<T>(ref T left, ref T right)
{
    T held = left;
    left = right;
    right = held;
}

void Reset<T>(ref T[] array, nuint size) where T : zeroable
{
    array = new T[size];
}

bool TryLast<T>(T[] items, T fallback, out T last)
{
    if (items.Length == 0u)
    {
        last = fallback;
        return false;
    }

    last = items[items.Length - 1u];
    return true;
}

int Main()
{
    String left = "left";
    String right = "right";
    Swap(ref left, ref right);
    Console.WriteLine($"{left} {right}");

    int[] numbers = [1, 2, 3];
    Reset(ref numbers, 2u);
    Console.WriteLine($"{numbers.Length} {numbers[0]}");

    String[] words = ["a", "b"];
    String found = "";
    bool had = TryLast(words, "none", out found);
    Console.WriteLine($"{had} {found}");

    bool again = TryLast(Array.Empty<String>(), "none", out var missing);
    Console.WriteLine($"{again} {missing}");
    return 0;
}
