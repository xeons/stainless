// A generic function's `ref` and `out` parameters take only an argument that
// says so, as a function that is not generic does.
module Bad;

void Swap<T>(ref T left, ref T right)
{
    T held = left;
    left = right;
    right = held;
}

bool TryFirst<T>(T[] items, T fallback, out T first)
{
    first = items.Length == 0u ? fallback : items[0u];
    return items.Length != 0u;
}

int Main()
{
    int a = 1;
    int b = 2;
    Swap(a, ref b);                         // SL0445
    String word = "";
    TryFirst(["x"], "none", ref word);      // SL0445
    long wide = 3L;
    Swap(ref a, ref wide);                  // SL0447
    return 0;
}
