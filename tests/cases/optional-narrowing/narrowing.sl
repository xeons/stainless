// Flow narrowing for `C?`: a checked optional is the thing it holds.
//
// The compiler already tracked which case a variant was holding through an
// `if`, a `!`, `&&`, `||`, a ternary, an early return and a `switch`. An
// optional wanted exactly that machinery and had none of it, which is why a
// structure that walks `next` could not be written at all.
//
// Both kinds of fact now share one table, because the difficulty was never the
// fact -- it is the lifetime of one, and that is the same work for both.
module OptionalNarrowing;

import Standard.Console;
import Standard.Text;

public class Node {
    public int Value;
    public Node? Next;

    public Node(int value) { Value = value; Next = null; }
}

/// An early return proves the rest of the block, which is what makes the
/// recursive shape work: `head` is a `Node?` on the way in and a `Node` from
/// the second line on.
int Sum(Node? head) {
    if (head == null) { return 0; }
    return head.Value + Sum(head.Next);
}

/// The same over a loop rather than a stack.
String Walk(Node? head) {
    var text = new StringBuilder();

    Node? at = head;
    while (at != null) {
        text.AppendInteger((long)at.Value);
        text.Append(" ");
        at = at.Next;               // still assignable: the check said what it
    }                               // held, not what it may be given next
    return text.ToText();
}

/// A narrowed optional is an ordinary reference, so it goes wherever one does.
int Doubled(Node node) { return node.Value * 2; }

Node? Nothing() { return null; }

public void Main() {
    var a = new Node(1);
    var b = new Node(2);
    var c = new Node(3);
    a.Next = b;
    b.Next = c;

    Console.WriteLine("walk  " + Walk(a));
    Console.WriteLine("sum   " + Text.FromInteger((long)Sum(a)));

    // --- if and else --------------------------------------------------
    Node? maybe = b;
    if (maybe != null) { Console.WriteLine("if    " + Text.FromInteger((long)maybe.Value)); }
    else { Console.WriteLine("if    none"); }

    // `== null` proves the other arm, which is the same rule read backwards.
    Node? empty = Nothing();
    if (empty == null) { Console.WriteLine("else  none"); }
    else { Console.WriteLine("else  " + Text.FromInteger((long)empty.Value)); }

    // --- && binds its right operand knowing the left ------------------
    //
    // A field is not narrowable, so the second link goes through a local --
    // the same rule a variant follows, and for the same reason: a check would
    // be about one evaluation and the read about another.
    Node? next = maybe != null ? maybe.Next : null;
    if (maybe != null && next != null) {
        Console.WriteLine("chain " + Text.FromInteger((long)next.Value));
    }

    // --- a ternary ----------------------------------------------------
    Node? t = c;
    Console.WriteLine("tern  " + Text.FromInteger((long)(t != null ? t.Value : -1)));

    // --- as an argument -----------------------------------------------
    if (t != null) { Console.WriteLine("arg   " + Text.FromInteger((long)Doubled(t))); }

    // --- still an optional where it is written ------------------------
    if (maybe != null) { maybe = null; }
    Console.WriteLine("reset " + Text.FromBool(maybe == null));

    // --- and the proof does not outlive what it was about -------------
    Node? again = a;
    if (again != null) {
        Console.WriteLine("held  " + Text.FromInteger((long)again.Value));
        again = Nothing();
        Console.WriteLine("gone  " + Text.FromBool(again == null));
    }

    // --- the same machinery, still narrowing variants -----------------
    //
    // `&&` reaching its right operand was missing for these too, so
    // `r.Ok && r.Value > 0` did not compile before this.
    var found = Find(a, 3);
    if (found.Ok && found.Value > 0) {
        Console.WriteLine("both  " + Text.FromInteger((long)found.Value));
    }

    var missing = Find(a, 99);
    Console.WriteLine("miss  " + Text.FromBool(!missing.Ok));
}

/// Both kinds of narrowing in one function: a Result to report with, and an
/// optional to walk.
Result<int, String> Find(Node? head, int wanted) {
    int steps = 0;

    Node? at = head;
    while (at != null) {
        steps = steps + 1;
        if (at.Value == wanted) { return Ok(steps); }
        at = at.Next;
    }
    return Fail("not found");
}
