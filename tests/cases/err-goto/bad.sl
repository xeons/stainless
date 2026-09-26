// SPDX-License-Identifier: 0BSD
module Bad;

// A label is named once, is named by something, and is reached only from
// inside the block it is in. A jump may leave blocks but not enter one: what
// the block declared before the label would never have been made.

int Nowhere()
{
    // No label of that name in this function.
    goto elsewhere;
}

int Into(bool flag)
{
    if (flag)
    {
    inner:
        return 1;
    }
    goto inner;
}

int Sideways()
{
    {
        goto other;
    }
    {
    other:
        return 2;
    }
}

int Twice()
{
    int n = 0;

again:
    n++;
    if (n < 2)
        goto again;

// The same name a second time: a jump would have two destinations.
again:
    return n;
}

// A lambda's labels are its own, so the enclosing function's is not one.
int Across()
{
    Func<int, int> f = x =>
    {
        goto start;
    };

start:
    return f(1);
}

// A jump out of a loop to a label that runs off the end still runs off it.
int Falling(int n)
{
    while (true)
    {
        if (n > 3)
            goto done;
        n++;
    }
done:
    n++;
}

int Main() => Nowhere() + Into(true) + Sideways() + Twice() + Across() + Falling(0);
