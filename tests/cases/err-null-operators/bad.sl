// SPDX-License-Identifier: 0BSD
module Bad;

// `?.` asks whether the receiver is there, so there has to be a question --
// and it answers with nothing when there was nothing, so "nothing" has to be
// something the answer's type can hold.

public class Node
{
    public String Name { get; set; }
    public Node? Next { get; set; }
    public int Weight { get; set; }
    public Node(String name)
    {
        Name = name;
        Next = null;
        Weight = 0;
    }
}

int Main()
{
    var here = new Node("here");
    Node? maybe = here.Next;
    int plain = 3;

    // Nothing to ask about: a `Node` is always there.
    var a = here?.Name;

    // Nor an int.
    var b = plain?.ToString;

    // A value member has no null to stand for "there was no receiver".
    var c = maybe?.Weight;

    // The same the other way: `??` needs a left that can be nothing.
    var d = plain ?? 4;
    var e = here ?? here;

    // And `??=` needs somewhere to put one.
    plain ??= 5;
    return 0;
}
