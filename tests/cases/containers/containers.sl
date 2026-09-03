// SPDX-License-Identifier: 0BSD
module Containers;

import Standard.Collections;
import Standard.Console;

extern "C" int printf(byte* format, ...);

public enum Suit { Clubs, Diamonds, Hearts, Spades }

// A class is a key by saying so; a primitive, an enum and a String need not.
public class Card : IEquatable<Card>, IHashable, IComparable<Card> {
    int rank;
    public Card(int value) { rank = value; }
    public int Rank() { return rank; }

    public bool EqualTo(Card other) { return rank == other.Rank(); }
    public nuint HashCode() { return rank.HashCode(); }
    public int CompareTo(Card other) { return rank.CompareTo(other.Rank()); }
}

// Proves that a container releases what it drops, rather than holding it until
// the container itself dies.
class Tag {
    String name;
    public Tag(String n) { name = n; }
    public String Name() { return name; }
    ~Tag() { printf("~Tag(%s)\n", name.ToPointer()); }
}

int Main() {
    // ---------------------------------------------------------- dictionary
    var ages = new Dictionary<String, int>();
    ages.Set("ada", 36);
    ages.Set("grace", 45);
    ages.Set("alan", 41);

    printf("dict=%llu ada=%d absent=%d\n",
        ages.Count(), ages.Get("ada"), ages.GetOr("nobody", -1));
    printf("has=%d %d\n",
        ages.ContainsKey("alan") ? 1 : 0, ages.ContainsKey("bob") ? 1 : 0);

    ages.Set("ada", 37);
    printf("replaced=%d count=%llu\n", ages.Get("ada"), ages.Count());
    printf("add=%d dup=%d\n", ages.Add("bob", 1) ? 1 : 0, ages.Add("ada", 9) ? 1 : 0);
    printf("remove=%d gone=%d left=%llu\n",
        ages.Remove("grace") ? 1 : 0, ages.Remove("grace") ? 1 : 0, ages.Count());

    // Enough entries to grow several times, then half of them removed. The
    // deletion shifts clusters back, so every survivor is still reachable.
    var squares = new Dictionary<int, int>();
    for (int i = 0; i < 200; i = i + 1) { squares.Set(i, i * i); }
    printf("grown=%llu capacity=%llu at150=%d\n",
        squares.Count(), squares.Capacity(), squares.Get(150));

    int sum = 0;
    foreach (var pair in squares) { sum = sum + pair.Key; }
    printf("keys-sum=%d listed=%llu\n", sum, squares.Keys().Count());

    for (int i = 0; i < 200; i = i + 2) { squares.Remove(i); }
    int survivors = 0;
    for (int i = 1; i < 200; i = i + 2) {
        if (squares.Get(i) == i * i) { survivors = survivors + 1; }
    }
    printf("halved=%llu survivors=%d evens=%d\n",
        squares.Count(), survivors, squares.ContainsKey(150) ? 1 : 0);

    // An enum and a class both work as keys.
    var bySuit = new Dictionary<Suit, String>();
    bySuit.Set(Suit.Hearts, "red");
    bySuit.Set(Suit.Spades, "black");
    var byCard = new Dictionary<Card, int>();
    byCard.Set(new Card(7), 700);
    printf("enum-key=%s class-key=%d\n",
        bySuit.Get(Suit.Hearts).ToPointer(), byCard.Get(new Card(7)));

    // ------------------------------------------------------------- hash set
    var seen = new HashSet<String>();
    printf("set=%d %d %d\n",
        seen.Add("a") ? 1 : 0, seen.Add("a") ? 1 : 0, seen.Contains("a") ? 1 : 0);

    seen.Add("b");
    seen.Add("c");
    var extra = new List<String>();
    extra.Add("c");
    extra.Add("d");
    seen.UnionWith(extra);
    printf("union=%llu\n", seen.Count());

    var keep = new HashSet<String>();
    keep.Add("a");
    keep.Add("d");
    seen.IntersectWith(keep);
    printf("intersect=%llu a=%d b=%d\n",
        seen.Count(), seen.Contains("a") ? 1 : 0, seen.Contains("b") ? 1 : 0);

    seen.ExceptWith(extra);
    printf("except=%llu\n", seen.Count());

    // ---------------------------------------------------------------- queue
    var line = new Queue<int>();
    for (int i = 0; i < 20; i = i + 1) { line.Enqueue(i); }
    printf("queue=%llu peek=%d take=%d %d\n",
        line.Count(), line.Peek(), line.Dequeue(), line.Dequeue());

    int drained = 0;
    while (!line.IsEmpty()) { drained = drained + line.Dequeue(); }
    printf("drained=%d empty=%d\n", drained, line.IsEmpty() ? 1 : 0);

    // ---------------------------------------------------------------- stack
    var plates = new Stack<String>();
    plates.Push("a");
    plates.Push("b");
    plates.Push("c");
    printf("stack=%llu top=%s pop=%s %s\n",
        plates.Count(), plates.Peek().ToPointer(),
        plates.Pop().ToPointer(), plates.Pop().ToPointer());

    // ----------------------------------------------------------- linked list
    var chain = new LinkedList<String>();
    var middle = chain.AddLast("b");
    chain.AddLast("d");
    chain.InsertAfter(middle, "c");
    chain.AddFirst("a");

    var forwards = new StringBuilder();
    for (nint at = chain.First(); at >= 0; at = chain.After(at)) {
        forwards.Append(chain.ValueAt(at));
    }

    var backwards = new StringBuilder();
    for (nint at = chain.Last(); at >= 0; at = chain.Before(at)) {
        backwards.Append(chain.ValueAt(at));
    }
    printf("chain=%s reversed=%s count=%llu\n",
        forwards.ToText().ToPointer(), backwards.ToText().ToPointer(), chain.Count());

    // A handle stays valid until its own node is removed, and its slot is then
    // reused rather than the pool growing.
    chain.RemoveAt(middle);
    printf("removed=%s %s left=%llu\n",
        chain.RemoveFirst().ToPointer(), chain.RemoveLast().ToPointer(), chain.Count());
    chain.AddLast("recycled");
    foreach (var item in chain) { printf("  chain %s\n", item.ToPointer()); }

    // ----------------------------------------------------------- sorted list
    var prices = new SortedList<String, int>();
    prices.Set("pear", 3);
    prices.Set("apple", 1);
    prices.Set("fig", 2);
    prices.Set("apple", 9);
    printf("sorted=%llu apple=%d\n", prices.Count(), prices.Get("apple"));
    foreach (var pair in prices) { printf("  %s=%d\n", pair.Key.ToPointer(), pair.Value); }
    printf("drop=%d still=%d absent=%d\n",
        prices.Remove("fig") ? 1 : 0, prices.ContainsKey("pear") ? 1 : 0,
        prices.GetOr("nope", -1));

    var ordered = new SortedList<int, int>();
    for (int i = 50; i > 0; i = i - 1) { ordered.Set(i, i * 2); }
    printf("ordered=%d %d %d of %llu\n",
        ordered.KeyAt(0), ordered.KeyAt(25), ordered.KeyAt(49), ordered.Count());

    // -------------------------------------------------------------- lifetime
    printf("lifetime\n");
    {
        var held = new Dictionary<String, Tag>();
        held.Set("one", new Tag("one"));
        held.Set("two", new Tag("two"));

        var stacked = new Stack<Tag>();
        stacked.Push(new Tag("stacked"));

        printf("dropping\n");
        held.Remove("one");         // releases the tag now
        stacked.Pop();              // and so does popping
        printf("dropped\n");
    }
    printf("scope left\n");

    printf("done\n");
    return 0;
}
