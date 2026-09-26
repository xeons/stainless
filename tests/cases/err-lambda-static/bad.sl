// SPDX-License-Identifier: 0BSD
module Bad;

// A static lambda captures nothing: not a local, not a parameter, not `this`,
// and not a member read through it.
public closure int Transform(int value);

class Counter
{
    int _step = 2;

    public Transform ByMember() => static x => x + _step;
    public Transform ByThis() => static x => x + this._step;
    public Transform ByMethod() => static x => Twice(x);

    int Twice(int x) => x * 2;
}

Transform ByParameter(int amount) => static x => x + amount;

int Main()
{
    int factor = 3;
    Transform byLocal = static x => x * factor;

    // Through a lambda nested in it, too.
    Transform nested = static x =>
    {
        Transform inner = y => y * factor;
        return inner(x);
    };

    // What is not captured is fine.
    Transform fine = static x => x * 2;
    return 0;
}
