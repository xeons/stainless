// SPDX-License-Identifier: 0BSD
//
// A function reached through its module is a value exactly as its bare name
// is: converted to a delegate or a closure by what it is stored in, which
// also picks the overload.
module FunctionValuesQualified;

import Standard.Console;
import Standard.Env;

public delegate int Transform(int value);
public delegate double Scale(double value);
public closure int Step(int value);
public closure String? Lookup(String name);

int Main()
{
    Transform doubled = Numbers.Double;
    Step stepped = Numbers.Pick;
    Scale halved = Numbers.Pick;
    Lookup environment = Env.GetEnvironmentVariable;

    Console.WriteLine($"{doubled(21)} {stepped(41)} {halved(1.0)}");
    Console.WriteLine(environment("STAINLESS_SURELY_UNSET_VARIABLE") is null ? "unset" : "set");
    return 0;
}
