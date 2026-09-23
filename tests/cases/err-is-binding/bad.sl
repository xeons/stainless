// SPDX-License-Identifier: 0BSD
//
// Where a name after `is` is refused, and why.
module Bad;

import Standard.Console;

public interface ISpeaks { String Says(); }
public class Animal : ISpeaks { public virtual String Says() { return "..."; } }

public variant Value
{
    Null;
    Number(double Held);
}

// SL0585: the name needs somewhere to be true, and only a branch or a loop
// body the test guards is such a place.
void OutsideAnIf(Value value)
{
    bool ok = value is Number n;
    Console.WriteLine(Text.FromBool(ok));
}

// The same, under an `&&`: the value would be taken before the `if`, which is
// not when the test would have run.
void UnderAnd(Value value, bool flag)
{
    if (flag && value is Number n)
        Console.WriteLine("no");
}

// And negated, where the name would be true in the branch that ruled it out.
void Negated(Value value)
{
    if (!(value is Number n))
        Console.WriteLine("no");
}

// A `do` runs its body before the test, so there is no pass in which the name
// would be true. A `while` is fine, and is the case beside this one.
void InADoWhile(Value value)
{
    do
        Console.WriteLine("no");
    while (value is Number n);
}

// SL0586: a case that carries nothing has nothing to name.
void NothingToBind(Value value)
{
    if (value is Null nothing)
        Console.WriteLine("no");
}

// SL0587: there is no conversion down to an interface.
void AnInterface(Animal animal)
{
    if (animal is ISpeaks s)
        Console.WriteLine("no");
}

// SL0518: a variant is asked which case it holds and nothing else.
void NoSuchCase(Value value)
{
    if (value is Animal a)
        Console.WriteLine("no");
}

public int Main() => 0;
