// SPDX-License-Identifier: 0BSD
//
// Working out a lambda's natural type binds its body once and throws that
// away. What the trial instantiated on the way -- `Box<long>`, named here and
// nowhere else -- is kept, since the real binding finds it already made.
module ProbeGeneric;

import Standard.Console;
import Standard.Text;

class Box<T>
{
    public T Value;
    public Box(T value) => Value = value;
}

int Main()
{
    var make = (int x) => new Box<long>((long)x * 2);
    var label = (int x) => { return new Box<String>(Text.FromInteger(x)); };
    Console.WriteLine(Text.FromInteger(make(21).Value) + " " + label(7).Value);
    return 0;
}
