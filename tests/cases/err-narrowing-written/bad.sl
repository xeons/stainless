// SPDX-License-Identifier: 0BSD
//
// A proof does not survive a write the compiler can see: a `ref` argument,
// or an assignment in a later operand of the same `&&`.
module Bad;

import Standard.Console;
import Standard.Text;

public class Node { public int V = 1; }

void Spoil(ref Result<int, String> r) { r = Fail("spoiled"); }
void Clear(ref Node? n) { n = null; }

void ByReference()
{
    Result<int, String> r = Ok(3);
    if (r.Ok)
    {
        Spoil(ref r);
        Console.WriteLine(Text.FromInteger(r.Value));   // SL0285
    }
}

void InALaterOperand()
{
    Node? n = new Node();
    if (n != null && (n = null) == null)
        Console.WriteLine(Text.FromInteger(n.V));       // SL0248
}

void OptionalByReference()
{
    Node? m = new Node();
    if (m != null)
    {
        Clear(ref m);
        Console.WriteLine(Text.FromInteger(m.V));       // SL0248
    }
}

int Main() => 0;
