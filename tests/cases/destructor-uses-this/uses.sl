// SPDX-License-Identifier: 0BSD
//
// A destructor may hand `this` around while it runs -- as an argument, into a
// list that goes with it -- and still runs exactly once. A weak reference to
// the object already reads as gone inside its own destructor.
module DestructorUsesThis;

import Standard.Console;
import Standard.Collections;

extern "C" int printf(byte* format, ...);

class Watcher
{
    public weak Node? Watched;
}

class Node
{
    public int N;
    public Watcher Seen = new Watcher();

    public Node(int n)
    {
        N = n;
        Seen.Watched = this;
    }

    ~Node()
    {
        printf("  ~Node %d\n", N);
        Describe(this);

        var list = new List<Node>();
        list.Add(this);
        printf("  listed %d\n", (int)list.Count);

        Node? self = Seen.Watched;
        Console.WriteLine(self is null ? "  weak is gone" : "  weak is alive");
    }
}

void Describe(Node node) => printf("  described %d\n", node.N);

int Main()
{
    Console.WriteLine("scope");
    {
        var node = new Node(1);
        printf("  made %d\n", node.N);
    }

    Console.WriteLine("done");
    return 0;
}
