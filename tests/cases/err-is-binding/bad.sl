// SPDX-License-Identifier: 0BSD
//
// Where a name after `is` is refused, and why.
module Bad;

import Standard.Console;

public interface ISpeaks { String Says(); }
public class Animal : ISpeaks { public virtual String Says() { return "..."; } }

public variant Value {
    Null;
    Number(double Held);
}

// SL0585: the name needs a branch to be true in, and only an `if` whose whole
// condition is the test has one.
void OutsideAnIf(Value value) {
    bool ok = value is Number n;
    Console.WriteLine(Text.FromBool(ok));
}

// The same, under an `&&`: the value would be taken before the `if`, which is
// not when the test would have run.
void UnderAnd(Value value, bool flag) {
    if (flag && value is Number n) { Console.WriteLine("no"); }
}

// And negated, where the name would be true in the branch that ruled it out.
void Negated(Value value) {
    if (!(value is Number n)) { Console.WriteLine("no"); }
}

void InAWhile(Value value) {
    while (value is Number n) { Console.WriteLine("no"); }
}

// SL0586: a case that carries nothing has nothing to name.
void NothingToBind(Value value) {
    if (value is Null nothing) { Console.WriteLine("no"); }
}

// SL0587: there is no conversion down to an interface.
void AnInterface(Animal animal) {
    if (animal is ISpeaks s) { Console.WriteLine("no"); }
}

// SL0518: a variant is asked which case it holds and nothing else.
void NoSuchCase(Value value) {
    if (value is Animal a) { Console.WriteLine("no"); }
}

public int Main() { return 0; }
