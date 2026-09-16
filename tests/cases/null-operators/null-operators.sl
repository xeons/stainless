// SPDX-License-Identifier: 0BSD
//
// `?.` and `??`, and `??=` beside them.
//
// **The receiver is read once.** `a?.b` asks whether `a` is there and then
// reaches through it, which is two mentions of one value -- so it is held in a
// hidden local first. Without that, `Next()?.Name` would call `Next` twice and
// ask about one object while reading another. The counter below is what checks
// it.
//
// **Nothing has to be expressible.** A class has null and a value type does
// not (§2.5), so `node?.Name` is a `String?` and answers null, while
// `node?.Weight` has nowhere to put "there was no node" -- and is only
// reachable with a `??` saying what it is instead. That is SL0605, and it is
// why `??` and `?.` are bound together rather than separately: when they meet,
// they fold into one question with two answers.
module NullOperators;

import Standard.Console;

class Node
{
    public String Name { get; set; }
    public Node? Next { get; set; }
    public int Weight { get; set; }

    public Node(String name, int weight)
    {
        Name = name;
        Next = null;
        Weight = weight;
    }

    public String Describe() => $"<{Name}:{Weight}>";
    public void Rename(String to) => Name = to;
}

static int calls = 0;

/// Counts how often it was reached, so that "once" can be checked rather than
/// asserted.
Node? Made(bool real)
{
    calls++;
    return real ? new Node("made", 7) : null;
}

public int Main()
{
    var head = new Node("head", 1);
    head.Next = new Node("tail", 2);

    Node? nothing = null;
    Node? tail = head.Next;

    // ---------------------------------------------------------------- ??

    Console.WriteLine($"a {(nothing ?? head).Name}");
    Console.WriteLine($"b {(tail ?? head).Name}");

    // `C? ?? C` is a `C`, which is the whole point: there is one either way.
    // `C? ?? C?` stays optional, the fallback being able to be nothing too.
    Node? either = nothing ?? tail;
    Console.WriteLine($"c {either != null}");

    // ---------------------------------------------------------------- ?.

    // A reference member answers null, which is a value it can hold.
    Console.WriteLine($"d {tail?.Next == null}");
    Console.WriteLine($"e {nothing?.Next == null}");

    // A value member needs the `??` to say what "no receiver" means.
    Console.WriteLine($"f {tail?.Weight ?? -1}");
    Console.WriteLine($"g {nothing?.Weight ?? -1}");

    // A String is a reference, so it needs no fallback -- but reads better
    // with one.
    Console.WriteLine($"h {tail?.Name ?? "none"}");
    Console.WriteLine($"i {nothing?.Name ?? "none"}");

    // A method, called only when there is something to call it on.
    Console.WriteLine($"j {tail?.Describe() ?? "nothing"}");
    Console.WriteLine($"k {nothing?.Describe() ?? "nothing"}");

    // And one returning nothing, as a statement: it simply does not happen.
    nothing?.Rename("never");
    tail?.Rename("renamed");
    Console.WriteLine($"l {tail?.Name ?? "?"}");

    // Chained. Each `?.` asks its own question, so the second is reached only
    // when the first found something.
    Console.WriteLine($"m {head.Next?.Next?.Name ?? "end"}");
    Console.WriteLine($"n {tail?.Next?.Name ?? "end"}");

    // ---------------------------------------------------------------- ??=

    Node? slot = null;
    slot ??= new Node("filled", 3);
    Console.WriteLine($"o {slot?.Name ?? "?"}");

    slot ??= new Node("ignored", 4);
    Console.WriteLine($"p {slot?.Name ?? "?"}");

    // ------------------------------------------------------ once, not twice

    calls = 0;
    int weight = Made(true)?.Weight ?? 0;
    Console.WriteLine($"q {weight} after {calls} call");

    calls = 0;
    int none = Made(false)?.Weight ?? -1;
    Console.WriteLine($"r {none} after {calls} call");

    // The fallback is not evaluated when there was something.
    calls = 0;
    var kept = tail ?? Made(true) ?? head;
    Console.WriteLine($"s {kept.Name} after {calls} calls");
    return 0;
}
