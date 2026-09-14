// SPDX-License-Identifier: 0BSD
//
// A lambda is typed by what it is assigned to, and for most of them that is
// the only thing that could type one: `x => x` says nothing about what `x` is.
// One that writes its parameter types out has said everything but its result,
// and binding the body answers that -- so it has a type of its own, and `var`
// can hold it.
//
// The type is a `closure` rather than a `delegate`, because a lambda may
// capture and a delegate is one pointer with nowhere to keep what it captured.
module LambdaNaturalType;

import Standard.Console;
import Standard.Text;

public closure int Transform(int value);

int Apply(Transform t, int n) { return t(n); }

int Main() {
    var doubled = (int x) => x * 2;
    Console.WriteLine(Text.FromInteger(doubled(21)));

    // Captured by value, the way any closure is.
    int step = 5;
    var stepped = (int x) => x + step;
    Console.WriteLine(Text.FromInteger(stepped(1)));

    // The same shape is the same type, so one can be assigned to the other.
    doubled = stepped;
    Console.WriteLine(Text.FromInteger(doubled(1)));

    // And a declared closure of that shape takes it.
    Console.WriteLine(Text.FromInteger(Apply(stepped, 10)));

    Transform declared = (int x) => x - 1;
    var fromDeclared = declared;
    Console.WriteLine(Text.FromInteger(fromDeclared(10)));

    // A different shape is a different type.
    var describe = (int x, bool loud) => loud ? "LOUD" : Text.FromInteger(x);
    Console.WriteLine(describe(3, false));
    Console.WriteLine(describe(3, true));
    return 0;
}
