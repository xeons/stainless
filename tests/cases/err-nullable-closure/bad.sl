// A `Notify?` is not called before a check, and is not a `Notify` without one.
module Bad;

public closure void Notify(int value);

int Main()
{
    Notify? maybe = null;
    maybe(1);
    Notify sure = maybe;
    return 0;
}
