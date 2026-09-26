// SPDX-License-Identifier: 0BSD
//
// A narrowed optional is still storage: it may be passed by `ref` or `out`,
// and what was proved about it is forgotten, because the callee may have
// written anything its type allows.
module NarrowingWritten;

import Standard.Console;
import Standard.Text;

public class Node { public int V = 1; }

void Clear(ref Node? n) { n = null; }
void Fill(out Node? n) { n = new Node(); }
void Replace(ref Node n) { n = new Node(); }

/// A parameter passed by `ref` is written, so it is owned for the call.
void Take(Node p)
{
    Replace(ref p);
    Console.WriteLine(Text.FromInteger(p.V));
}

int Main()
{
    Node? m = new Node();
    if (m != null)
    {
        Clear(ref m);
        Console.WriteLine(m == null ? "cleared" : "kept");
    }

    Node? k = null;
    if (k == null)
    {
        Fill(out k);
        Console.WriteLine(k == null ? "empty" : "filled");
    }

    // Written in a loop body by `ref`: the condition's proof is not trusted
    // on the next pass.
    Node? walk = new Node();
    int passes = 0;
    while (walk != null)
    {
        passes++;
        Clear(ref walk);
    }
    Console.WriteLine(Text.FromInteger(passes));

    Take(new Node());
    return 0;
}
