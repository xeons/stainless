// A constructor and a generic may not be variadic: neither is one C function.
// Both are refused as they are read, which is why they are not beside the
// method in err-variadic-definition.
module ErrVariadicConstructor;

public class Bag
{
    public int Count;

    Bag(int count, ...)                             // SL0493: a constructor
    {
        Count = count;
    }
}

T First<T>(T value, ...)                            // SL0493: a generic
{
    return value;
}

int Main() => 0;
