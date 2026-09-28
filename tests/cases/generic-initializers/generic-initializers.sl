// SPDX-License-Identifier: 0BSD
//
// A generic class that declares no constructor still runs its field
// initializers: each instantiation is given the constructor to run them in,
// however late in the compilation it is made.
module GenericInitializers;

import Standard.Console;
import Standard.Text;

public class Labelled<T>
{
    public T Value;
    public String Label = "value";
    public int Count { get; set; } = 3;
}

public class Pair<TFirst, TSecond> : Labelled<TFirst>
{
    public TSecond Second;
    public int Extra = 4;
}

int Main()
{
    var labelled = new Labelled<int>();
    var pair = new Pair<String?, double>();
    Console.WriteLine(labelled.Label + " " + Text.FromInteger(labelled.Count));
    Console.WriteLine(pair.Label + " " + Text.FromInteger(pair.Count + pair.Extra));
    return 0;
}
