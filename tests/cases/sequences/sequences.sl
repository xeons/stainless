// SPDX-License-Identifier: 0BSD
//
// Doing something to every element, and ordering them.
//
// The point being proved twice over: a lambda becomes a single-method
// interface, so combinators need no function type in the language; and a type
// parameter that appears only in a lambda's *result* is worked out by binding
// the body, which is what makes `Select` writable at all.
module Sequences;

import Standard.Console;
import Standard.Collections;

extern "C" int printf(byte* format, ...);

public class Person
{
    public String Name { get; }
    public int Age { get; }
    public String Team { get; }

    public Person(String name, int age, String team)
    {
        Name = name;
        Age = age;
        Team = team;
    }
}

void Show(String label, String value)
{
    Console.WriteLine(label + " " + value);
}

int Main()
{
    var numbers = [5, 3, 9, 1, 7, 3];

    // ----------------------------------------------------------- inference

    // T from the array; R from the body of the lambda, which can only be bound
    // once T has given it a parameter type.
    var doubled = Select(numbers, n => n * 2);
    var spelled = Select(numbers, n => "<" + Text.FromInteger((long)n) + ">");
    var halved = Select(numbers, n => (double)n / 2.0);

    printf("doubled  = %d %d\n", doubled[0u], doubled[1u]);
    Show("spelled ", spelled[0u] + spelled[1u]);
    printf("halved   = %.1f\n", halved[0u]);

    // A from the seed, so the fold's lambda has everything it needs up front.
    long total = Aggregate(numbers, (long)0, (sum, n) => sum + (long)n);
    String run = Aggregate(numbers, "", (text, n) => text + Text.FromInteger((long)n));

    printf("total    = %lld\n", total);
    Show("run     ", run);

    // ---------------------------------------------------------- the rest

    var odd = Where(numbers, n => n % 2 == 1);
    printf("odd      = %llu\n", (ulong)odd.Count);

    printf("any>8    = %d\n", Any(numbers, n => n > 8));
    printf("any>9    = %d\n", Any(numbers, n => n > 9));
    printf("all>0    = %d\n", All(numbers, n => n > 0));
    printf("all>3    = %d\n", All(numbers, n => n > 3));
    printf("count<5  = %llu\n", (ulong)Count(numbers, n => n < 5));
    printf("first>4  = %d\n", FirstOrDefault(numbers, n => n > 4, -1));
    printf("first>99 = %d\n", FirstOrDefault(numbers, n => n > 99, -1));
    printf("index>8  = %llu\n", (ulong)FindIndex(numbers, n => n > 8).GetValueOrDefault(99u));
    printf("index>99 = %d\n", FindIndex(numbers, n => n > 99).IsEmpty);
    printf("find>4   = %d\n", Find(numbers, n => n > 4).GetValueOrDefault(-1));

    printf("take3    = %llu\n", (ulong)Take(numbers, 3u).Count);
    printf("skip4    = %llu\n", (ulong)Skip(numbers, 4u).Count);
    printf("takeAll  = %llu\n", (ulong)Take(numbers, 99u).Count);

    var seen = new AtomicCounter();
    ForEach(numbers, n => seen.Add(n));
    printf("forEach  = %lld\n", seen.Total());

    // An empty input: All is true of it, Any is false.
    var none = new int[0];
    printf("emptyAll = %d\n", All(none, n => n > 0));
    printf("emptyAny = %d\n", Any(none, n => n > 0));

    // ------------------------------------------------------------ ordering

    // Long enough to go through the merge rather than the short-run path.
    var many = new int[100];
    for (nuint i = 0u; i < many.Length; i++)
    {
        many[i] = (int)((i * 37u) % 100u);
    }

    Sort(many);
    printf("sorted   = %d\n", InOrder(many));
    printf("smallest = %d\n", many[0u]);
    printf("largest  = %d\n", many[many.Length - 1u]);

    // A comparer sorts what implements nothing, and sorts it any way it likes.
    // Ages and teams deliberately cut across each other, so that ordering by
    // one and then the other is a different answer from ordering by the second
    // alone. That is what makes the next assertion mean something.
    var people = [
        new Person("Ada", 36, "red"),
        new Person("Grace", 45, "blue"),
        new Person("Alan", 41, "red"),
        new Person("Edsger", 40, "blue"),
    ];

    Sort(people, (a, b) => a.Age - b.Age);
    Show("byAge   ", Aggregate(people, "", (text, p) => text + p.Name + " "));

    // Stability, which is the property worth paying a scratch array for:
    // sorting by team now must leave each team's people in the age order the
    // previous sort put them in. Sorting by two keys is exactly this, and it
    // only works if the second sort does not disturb the first.
    Sort(people, (a, b) => a.Team.CompareTo(b.Team));
    Show("byTeam  ", Aggregate(people, "", (text, p) => text + p.Name + " "));

    // Descending, which is the same comparer the other way round.
    var counted = [5, 3, 9, 1, 7];
    Sort(counted, (a, b) => b - a);
    printf("descend  = %d %d\n", counted[0u], counted[4u]);

    // Sorting a slice leaves the rest alone.
    var partial = [9, 8, 7, 6, 5];
    Sort(partial[1:4]);
    printf("slice    = %d %d %d %d %d\n",
           partial[0u], partial[1u], partial[2u], partial[3u], partial[4u]);

    // A list sorts through the interface and comes back ordered.
    var list = new List<int>();
    list.Add(4); list.Add(2); list.Add(8); list.Add(6);
    Sort(list);
    printf("list     = %d %d\n", list[0u], list[3u]);

    Sort(list, (a, b) => b - a);
    printf("listDesc = %d %d\n", list[0u], list[3u]);

    // ------------------------------------------------------------ searching

    var ordered = [10, 20, 30, 40, 50];
    printf("find30   = %llu\n", (ulong)BinarySearch(ordered, 30));
    printf("find10   = %llu\n", (ulong)BinarySearch(ordered, 10));
    printf("find50   = %llu\n", (ulong)BinarySearch(ordered, 50));
    printf("find35   = %llu\n", (ulong)BinarySearch(ordered, 35));
    printf("bound35  = %llu\n", (ulong)FindLowerBound(ordered, 35));
    printf("bound0   = %llu\n", (ulong)FindLowerBound(ordered, 0));
    printf("bound99  = %llu\n", (ulong)FindLowerBound(ordered, 99));

    // ---------------------------------------------------- over a sequence

    // The IEnumerable overloads, reached through a List rather than an array.
    var names = new List<String>();
    names.Add("alpha"); names.Add("be"); names.Add("gamma");

    printf("longNames = %llu\n", (ulong)Where(names, n => n.ByteLength() > 2u).Count);
    Show("upper    ", Aggregate(names, "", (text, n) => text + n.ToUpperAscii() + " "));
    printf("anyShort  = %d\n", Any(names, n => n.ByteLength() < 3u));

    var lengths = Select(names, n => (long)n.ByteLength());
    printf("lengths   = %lld %lld\n", lengths[0u], lengths[1u]);

    // ------------------------------------------------------------- cursors

    // Each of these walks its container in place rather than building a list
    // first. What is checked is the order each one hands things back in.

    var queue = new Queue<int>();
    queue.Enqueue(1); queue.Enqueue(2); queue.Enqueue(3);
    Show("queue   ", Aggregate(ToList(queue), "", (text, n) => text + Text.FromInteger((long)n)));

    // Dequeuing first moves the ring's head off zero, which is the case a
    // cursor that walked the array rather than the ring would get wrong.
    queue.Dequeue();
    queue.Enqueue(4);
    Show("wrapped ", Aggregate(ToList(queue), "", (text, n) => text + Text.FromInteger((long)n)));

    var stack = new Stack<int>();
    stack.Push(1); stack.Push(2); stack.Push(3);
    Show("stack   ", Aggregate(ToList(stack), "", (text, n) => text + Text.FromInteger((long)n)));

    var chain = new LinkedList<int>();
    chain.AddLast(1); chain.AddLast(2); chain.AddFirst(0);
    Show("chain   ", Aggregate(ToList(chain), "", (text, n) => text + Text.FromInteger((long)n)));

    // A set has no order to promise, so the total is what is checked.
    var set = new HashSet<int>();
    set.Add(4); set.Add(9); set.Add(4); set.Add(16);
    printf("setCount  = %llu\n", (ulong)ToList(set).Count);
    printf("setTotal  = %lld\n", Aggregate(ToList(set), (long)0, (sum, n) => sum + (long)n));

    var byKey = new SortedList<int, String>();
    byKey.SetValue(3, "c"); byKey.SetValue(1, "a"); byKey.SetValue(2, "b");
    Show("sorted  ", Aggregate(ToList(byKey), "", (text, p) => text + p.Value));

    printf("done\n");
    return 0;
}

/// Whether a slice is ordered smallest first.
bool InOrder(int[:] items)
{
    for (nuint i = 1u; i < items.Length; i++)
    {
        if (items[i - 1u] > items[i])
            return false;
    }
    return true;
}

/// Something for `ForEach` to reach, since a lambda captures by value and an
/// action returns nothing.
public class AtomicCounter
{
    long _total;

    public AtomicCounter() => _total = 0;

    public void Add(int value) => _total += (long)value;
    public long Total() => _total;
}
