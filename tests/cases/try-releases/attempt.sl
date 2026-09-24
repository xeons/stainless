// SPDX-License-Identifier: 0BSD
//
// `try` lets go of what it unwrapped.
//
// It evaluates its operand into a slot, which takes a reference, and both
// arms read the payload back out of it. The failure arm returns, and a return
// releases the statement's temporaries and then forgets them -- so the
// success arm, which is a branch and not a later statement, has to be handed
// them back or nothing releases anything. That is the shape this pins: a
// `Result` carrying an object, unwrapped on the path that succeeds.
module Attempt;

import Standard.Console;

public enum Woe { None, Bad }

public class Held
{
    public int N;
    public Held(int n) { N = n; }
    ~Held() { Console.WriteLine("  ~Held " + FromInt(N)); }
}

String FromInt(int n) => Standard.Convert.FromLong((long)n, 10u);

Result<Held, Woe> MakeHeld(int n) => Ok(new Held(n));
Result<Held, Woe> Refuse() => Fail(Woe.Bad);

// Unwrapped and bound to a local.
Result<int, Woe> ViaLocal()
{
    var held = try MakeHeld(1);
    return Ok(held.N);
}

// Unwrapped and used without ever being named.
Result<int, Woe> Anonymous() => Ok((try MakeHeld(2)).N);

// Two in one function, so the slot is not the only thing being counted.
Result<int, Woe> Twice()
{
    var first = try MakeHeld(3);
    var second = try MakeHeld(4);
    return Ok(first.N + second.N);
}

// The arm that returns: what the operand made still has to go.
Result<int, Woe> Failing()
{
    var held = try Refuse();
    return Ok(held.N);
}

// Inside a loop, where the slot is reused on every turn.
Result<int, Woe> Looping()
{
    int total = 0;
    for (int i = 5; i < 8; i++)
    {
        var held = try MakeHeld(i);
        total = total + held.N;
    }
    return Ok(total);
}

/// Names the answer, because `Value` may only be read from a local.
String Answer(Result<int, Woe> given)
{
    var held = given;
    return held.Ok ? FromInt(held.Value) : "refused";
}

int Main()
{
    Console.WriteLine("local");
    Console.WriteLine("  = " + Answer(ViaLocal()));
    Console.WriteLine("anonymous");
    Console.WriteLine("  = " + Answer(Anonymous()));
    Console.WriteLine("twice");
    Console.WriteLine("  = " + Answer(Twice()));
    Console.WriteLine("failing");
    Console.WriteLine("  = " + Answer(Failing()));
    Console.WriteLine("looping");
    Console.WriteLine("  = " + Answer(Looping()));
    return 0;
}
