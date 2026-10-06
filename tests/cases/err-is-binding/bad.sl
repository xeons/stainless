// SPDX-License-Identifier: 0BSD
//
// Where a name after `is` is refused, and why.
module Bad;

import Standard.Console;
import Standard.Text;

public interface ISpeaks { String Says(); }
public class Animal : ISpeaks { public virtual String Says() { return "..."; } }

public variant Value
{
    Null;
    Number(double Held);
}

// SLF0024: a name is in scope only where the pattern is known to have
// matched -- the rest of an `&&`, the branch the test guards, and after an
// `if` whose other branch always leaves. Read anywhere else, it may never
// have been assigned.
void OutsideAnIf(Value value)
{
    bool ok = value is Number n;
    Console.WriteLine(Text.FromDouble(n.Held));
}

// Under an `||`, where the branch runs whether or not the test did.
void UnderOr(Value value, bool flag)
{
    if (flag || value is Number n)
        Console.WriteLine(Text.FromDouble(n.Held));
}

// As an argument, which has no branch of its own.
void AsAnArgument(Value value)
{
    if (Holds(value is Number n))
        Console.WriteLine(Text.FromDouble(n.Held));
}

bool Holds(bool truth) => truth;

// Negated, where the name is assigned in the branch that did not run.
void Negated(Value value)
{
    if (!(value is Number n))
        Console.WriteLine(Text.FromDouble(n.Held));
}

// After a loop, which is left by failing the test that named it.
void AfterAWhile(Value value)
{
    while (value is Number n)
        value = Value.Null;
    Console.WriteLine(Text.FromDouble(n.Held));
}

// SLF0025: a case that carries nothing has nothing to name.
void NothingToBind(Value value)
{
    if (value is Null nothing)
        Console.WriteLine("no");
}

// SLF0026: there is no conversion down to an interface.
void AnInterface(Animal animal)
{
    if (animal is ISpeaks s)
        Console.WriteLine("no");
}

// SLN0013: a variant is asked which case it holds and nothing else.
void NoSuchCase(Value value)
{
    if (value is Animal a)
        Console.WriteLine("no");
}

public int Main() => 0;
