// SPDX-License-Identifier: 0BSD
//
// A late field read before anything gave it a value stops the program,
// naming the field, rather than handing on a null where none can be.
module AbortLateUnset;

import Standard.Console;

public class Node
{
    public String Name;

    public Node(String name) => Name = name;
}

public class Holder
{
    late Node _node;

    public Holder() { }

    public void Fill() => _node = new Node("filled");

    public String Describe() => _node.Name;
}

int Main()
{
    var full = new Holder();
    full.Fill();
    Console.WriteLine("found " + full.Describe());

    var empty = new Holder();
    Console.WriteLine("found " + empty.Describe());
    return 0;
}
