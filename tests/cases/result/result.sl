// SPDX-License-Identifier: 0BSD
//
// Result<T, E>: the language's answer to an exception. A function that can fail
// says so in its type, and the two halves are readable only where the compiler
// has seen which one is there.
module Check;

import Standard.Console;

enum Why { None = 0, TooSmall = 1, TooBig = 2 }

Result<int, Why> Doubled(int n) {
    if (n < 0)   { return Fail(Why.TooSmall); }
    if (n > 100) { return Fail(Why.TooBig); }
    return Ok(n * 2);
}

// The early return: after it, the rest of the function holds a value.
Result<String, Why> Described(int n) {
    var doubled = Doubled(n);
    if (!doubled.Ok) { return Fail(doubled.Error); }
    return Ok("got " + Text.FromInteger(doubled.Value));
}

String Either(int n) {
    var described = Described(n);
    return described.Ok ? described.Value : "no: " + Text.FromInteger((int)described.Error);
}

int Main() {
    Console.WriteLine(Either(21));
    Console.WriteLine(Either(-1));
    Console.WriteLine(Either(500));

    // Both halves, each under its own branch.
    var small = Doubled(-5);
    if (small.Ok) { Console.WriteLine("value " + Text.FromInteger(small.Value)); }
    else          { Console.WriteLine("why " + Text.FromInteger((int)small.Error)); }

    // A default needs no proof, because it supplies one.
    Console.WriteLine(Text.FromInteger(Doubled(1000).ValueOr(-1)));

    // `&&` carries the proof into what it guards.
    var left = Doubled(4);
    var right = Doubled(6);
    if (left.Ok && right.Ok) {
        Console.WriteLine("sum " + Text.FromInteger(left.Value + right.Value));
    }

    // A Result holding a reference owns it: this one is the only thing keeping
    // the String alive, and it is released with the local.
    {
        var held = Described(50);
        if (held.Ok) { Console.WriteLine(held.Value); }
    }

    Console.WriteLine("done");
    return 0;
}
