// SPDX-License-Identifier: 0BSD
//
// Where an initializer has no moment to run at, and what a brace list may not
// contain.
module Bad;

import Standard.Collections;

public struct Point
{
    // A struct is made by declaring one, so there is no constructor here.
    public int X = 1;
}

public class Node
{
    public int Width = 80;

    // The object is not built yet, and every field below this one is still
    // whatever the allocation left.
    public int Half = Width / 2;

    // A property that computes its value owns no storage to give one to.
    public int Computed { get { return 3; } } = 4;

    public int Read() => Width;
}

public class Plain
{
    public int Value;
    public int Squared { get { return Value * Value; } }
}

int Main()
{
    // No such member.
    var a = new Plain { Missing = 1 };

    // A property with no setter.
    var b = new Plain { Squared = 4 };

    // Half a brace list of each kind.
    var c = new List<int> { 1, Value = 2 };

    // And a type with no 'Add' to add to.
    var d = new Plain { 1, 2 };
    return 0;
}
