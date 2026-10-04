// Where a '...' may not be written.
//
// A function at module level may be variadic, and reads what follows with a
// VaList. A method may not: it has no C convention to be variadic in. A
// constructor and a generic are err-variadic-constructor.
module ErrVariadicDefinition;

extern "C" int printf(byte* format, ...);           // fine: called

export "C" int log_line(byte* format, ...)          // fine: defined at module level
{
    VaList args = VaList.Start();
    return printf(format);
}

public class Bag
{
    public int Count;

    public int Total(int first, ...)                // SL0493: a method
    {
        return first;
    }
}

int Main()
{
    var bag = new Bag();
    return bag.Count - 1;
}
