// SPDX-License-Identifier: 0BSD
module Bad;

public delegate int Plain(int value);

class Holder
{
    int _field = 1;

    public int Read()
    {
        // A static local function reaches nothing around it, the object included.
        static int Field() => _field;
        return Field();
    }
}

int Main()
{
    int x = 1;

    // Static: no variable from around it either.
    static int Reads() => x;

    // What a local function reads it is given by value at each call, so
    // assigning it would change only the copy.
    void Bump() => x++;
    void Reset() { x = 0; }

    // A call passes what the function reads, so that has to exist at the call.
    Late();
    int y = 2;
    int Late() => y;

    // One that reads something has nowhere in a function pointer to keep it.
    Plain plain = Reader;
    int Reader(int v) => v + x;

    // A generic one is a value only once a call has said its type arguments.
    T Same<T>(T value) => value;
    var same = Same;

    // Local functions are not overloaded, and share names with locals.
    int Twice(int v) => v * 2;
    long Twice(long v) => v * 2;
    int x2 = 0;
    int x2() => 0;

    return 0;
}
