// SPDX-License-Identifier: 0BSD
//
// Two generics that instantiate themselves with a larger argument each time:
// a type whose method makes one of itself around itself, and a function that
// calls itself with an array of what it was given. Each is refused where it
// grows past the limit, rather than overflowing the compiler's stack or never
// finishing.
module ErrGenericRunaway;

class Cell<T>
{
    T _value;

    public Cell(T value) { _value = value; }

    public Cell<Cell<T>> Wrap() => new Cell<Cell<T>>(this);
}

void Deep<T>(int n, T x)
{
    if (n > 0)
        Deep(n - 1, new T[1]);
}

int Main()
{
    var cell = new Cell<int>(1);
    Deep(3, 1);
    return 0;
}
