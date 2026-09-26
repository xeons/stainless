// SPDX-License-Identifier: 0BSD
//
// `a?[i]` and `x!`.
//
// `?[` asks what `?.` asks, before an element rather than a member: the
// receiver is read once, and the whole is nothing when it was nothing. An
// array is never null, so what is asked about is a `C?` whose class declares
// an indexer. A reference element answers null; a value element needs `??`.
//
// `x!` is `(C)x`: a `C?` used as the `C` it holds, with nothing checked.
module NullConditionalIndex;

import Standard.Console;
import Standard.Collections;

class Node
{
    public String Name;
    public Node? Next;

    public Node(String name)
    {
        Name = name;
        Next = null;
    }
}

class Shelf
{
    private Node?[] _slots = new Node?[3];

    public Node? this[int i]
    {
        get => _slots[i];
        set => _slots[i] = value;
    }

    public Node this[String name] => new Node(name);
}

static int s_calls = 0;

List<Node>? Nodes(bool real)
{
    s_calls++;
    return real ? new List<Node> { new Node("first"), new Node("second") } : null;
}

public int Main()
{
    List<Node>? some = Nodes(true);
    List<Node>? none = Nodes(false);

    // A reference element answers null, so each of these is a `Node?`.
    Console.WriteLine($"a {some?[1]?.Name ?? "none"} {none?[1]?.Name ?? "none"}");

    // Read once: the call runs one time however far the chain goes.
    s_calls = 0;
    Console.WriteLine($"b {Nodes(true)?[0]?.Next?.Name ?? "no next"} after {s_calls}");

    // A value element has no null, so it is reached with a fallback.
    List<int>? numbers = new List<int> { 1, 2, 3 };
    List<int>? missing = null;
    Console.WriteLine($"c {numbers?[2] ?? -1} {missing?[2] ?? -1}");

    // A declared indexer, of either shape.
    var shelf = new Shelf();
    shelf[1] = new Node("slot");
    Shelf? here = shelf;
    Shelf? gone = null;
    Console.WriteLine($"d {here?[1]?.Name ?? "empty"} {gone?[1]?.Name ?? "empty"} " +
                      $"{here?["named"]?.Name ?? "empty"}");

    // Inside a conditional's true arm, which is where `?[` and `? [` meet.
    bool flag = true;
    Node? picked = flag ? gone?[1] : some?[0];
    Node? other = !flag ? gone?[1] : some?[0];
    int[] literal = flag ? [1, 2] : [3];
    Console.WriteLine($"e {picked?.Name ?? "nothing"} {other?.Name ?? "nothing"} " +
                      $"{literal.Length}");

    // A reference member answers null the same way.
    Node? tail = some?[1];
    String? name = tail?.Name;
    Console.WriteLine($"f {name ?? "?"}");

    // `!`: the same pointer, now a `Node`.
    Node sure = tail!;
    Console.WriteLine($"g {sure.Name} {tail!.Name} {some![0].Name} {Nodes(true)!.Count}");

    // Postfix `!` beside prefix `!` and `!=`.
    bool present = tail != null;
    Console.WriteLine($"h {!present} {present!} {!present!}");
    return 0;
}
