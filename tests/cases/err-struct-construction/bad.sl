// SPDX-License-Identifier: 0BSD
//
// What a struct's constructor may not be: one taking no arguments, one on a
// type `new` cannot make, and one that constructs something above it. And
// `new` on a struct that declares none.
module Bad;

public struct Empty
{
    public int X;

    // A struct declared and never constructed is its zero value, so this would
    // run for some of them and not for others.
    public Empty() { X = 1; }
}

public union Either
{
    public int Number;
    public float Real;

    public Either(int number) { Number = number; }
}

public struct Derived
{
    public int X;

    public Derived(int x)
    {
        base(x);
        X = x;
    }
}

public struct Plain
{
    public int X;
}

int Main()
{
    var plain = new Plain(1);
    return plain.X;
}
