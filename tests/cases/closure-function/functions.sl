// SPDX-License-Identifier: 0BSD
module FunctionClosures;

import Standard.Collections;
import Standard.Console;
import Standard.Text;

// A plain function, held by a closure with no lambda around it. It has no
// object, so the closure's receiver is null and its function is a thunk the
// compiler writes once per function.

public closure String Shout(String text);
public closure void Doubler(ref int value);
public closure int Combine(int left, int right);
public closure void Handler(int value);

String Upper(String text) => text.ToUpperAscii();

// An overload that inference has to pass over: T is String, so the Upper a
// String pipeline means is the one above.
int Upper(int value) => value + 1000;

void Twice(ref int value)
{
    value = value * 2;
}

static int s_heard = 0;

void Hear(int value)
{
    s_heard = s_heard + value;
}

public class Arithmetic
{
    public static int Add(int left, int right) => left + right;
}

public class Source
{
    public event Handler Raised;

    public void Raise(int value) => Raised(value);
}

int Main()
{
    // Stored, and called.
    Shout loud = Upper;
    Console.WriteLine(loud("quiet"));

    // A static method is a function with a longer name.
    Combine add = Arithmetic.Add;
    Console.WriteLine(Text.FromInteger((long)add(2, 3)));

    // A 'ref' parameter is the caller's storage all the way through the thunk.
    Doubler twice = Twice;
    int n = 21;
    twice(ref n);
    Console.WriteLine(Text.FromInteger((long)n));

    // One thunk per function, so two mentions are the same closure -- which
    // is what lets '-=' find what '+=' added.
    Shout again = Upper;
    Console.WriteLine(loud == again ? "equal" : "different");

    var source = new Source();
    source.Raised += Hear;
    source.Raise(5);
    source.Raised -= Hear;
    source.Raise(7);
    Console.WriteLine("heard=" + Text.FromInteger((long)s_heard));

    // And passed by name to a generic function, whose result type is read off
    // the function's declaration -- in both spellings of the call.
    String[] names = ["alpha", "be", "gamma"];
    var longer = names.Where((name) => name.ByteLength() > 2u).Select(Upper).ToArray();
    Console.WriteLine(longer[0u] + " " + longer[1u]);

    var all = Select(names, Upper);
    Console.WriteLine(all[1u]);

    return 0;
}
