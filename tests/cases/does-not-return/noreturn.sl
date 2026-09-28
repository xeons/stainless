// `[DoesNotReturn]` on an extern: nothing after a call to it is reached.
//
// So a function whose last statement is such a call needs no `return` after
// it, and an `out` it has not written by then is not a broken promise.
module DoesNotReturn;

import Standard.Console;

extern "C"
{
    [DoesNotReturn]
    void sl_fail(byte* message);
}

[DoesNotReturn]
extern "C" void abort();

int Positive(int value)
{
    if (value > 0)
        return value;

    sl_fail("not positive");
}

bool TryHalve(int value, out int half)
{
    if (value % 2 == 0)
    {
        half = value / 2;
        return true;
    }

    abort();
}

int Main()
{
    Console.WriteLine($"{Positive(3)}");
    if (TryHalve(8, out int half))
        Console.WriteLine($"{half}");
    return 0;
}
