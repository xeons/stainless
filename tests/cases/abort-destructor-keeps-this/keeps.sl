// SPDX-License-Identifier: 0BSD
//
// A destructor that leaves a reference to its object behind would leave that
// reference naming freed memory, so the program stops, naming the type.
module AbortDestructorKeepsThis;

import Standard.Console;

class Holder
{
    public Node? Kept;
}

class Node
{
    Holder _into;

    public Node(Holder into) => _into = into;

    ~Node()
    {
        Console.WriteLine("destroying");
        _into.Kept = this;
    }
}

int Main()
{
    var holder = new Holder();
    {
        var node = new Node(holder);
    }

    Console.WriteLine("not reached");
    return 0;
}
