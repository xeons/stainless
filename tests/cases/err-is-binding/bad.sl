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

// SL0585: the name needs somewhere to be true, and only the rest of an `&&`
// and the branch or loop body it guards are such places.
void OutsideAnIf(Value value)
{
    bool ok = value is Number n;
    Console.WriteLine(Text.FromBool(ok));
}

// Under an `||`, where the branch runs whether or not the test did.
void UnderOr(Value value, bool flag)
{
    if (flag || value is Number n)
        Console.WriteLine("no");
}

// As an argument, which has no branch of its own.
void AsAnArgument(Value value)
{
    if (Holds(value is Number n))
        Console.WriteLine("no");
}

bool Holds(bool truth) => truth;

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
