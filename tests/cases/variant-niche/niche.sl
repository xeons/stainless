// SPDX-License-Identifier: 0BSD
//
// A variant whose first case carries nothing and whose second carries a
// reference that is never null needs no tag: the first case is that reference
// being null. Optional<String> is then a pointer wide, and everything a
// variant does -- testing, switching, binding, copying and dropping -- has to
// read the null in place of the tag.
module VariantNiche;

import Standard.Console;
import Standard.Collections;

public class Tracked
{
    public static int Dropped = 0;
    public String Name { get; }
    public Tracked(String name) => Name = name;
    ~Tracked()
    {
        Dropped++;
    }
}

public struct Entry
{
    public int Id;
    public String Name;
    public Entry(int id, String name)
    {
        Id = id;
        Name = name;
    }
}

[Packed]
public struct Squeezed
{
    public byte Flag;
    public String Name;
    public Squeezed(byte flag, String name)
    {
        Flag = flag;
        Name = name;
    }
}

public variant Labelled
{
    Blank;
    Named(String Name);
}

// The empty case second: its zero would be a 'Named' holding a null, so it
// keeps its tag.
public variant Backwards
{
    Named(String Name);
    Blank;
}

String Yes(bool value) => value ? "yes" : "no";

String Describe(Optional<String> value)
{
    switch (value)
    {
        case Some held: return "some " + held.Value;
        case None: return "none";
    }
}

String DescribeNested(Optional<Optional<String>> value)
{
    if (value is Some outer)
    {
        if (outer.Value is Some inner)
            return "some some " + inner.Value;
        return "some none";
    }
    return "none";
}

String DescribeEntry(Optional<Entry> value) =>
    value is Some held ? $"entry {held.Value.Id} {held.Value.Name}" : "no entry";

String DescribeSqueezed(Optional<Squeezed> value) =>
    value is Some held ? $"squeezed {held.Value.Flag} {held.Value.Name}" : "no squeezed";

void ShowSizes()
{
    nuint word = sizeof(nuint);
    Console.WriteLine("Optional<String> is a word: " + Yes(sizeof(Optional<String>) == word));
    Console.WriteLine("Optional<Entry> is an Entry: " + Yes(sizeof(Optional<Entry>) == sizeof(Entry)));
    Console.WriteLine("Optional<Squeezed> is a Squeezed: " +
        Yes(sizeof(Optional<Squeezed>) == sizeof(Squeezed)));
    Console.WriteLine("Optional<Optional<String>> is two words: " +
        Yes(sizeof(Optional<Optional<String>>) == 2u * word));
    Console.WriteLine("Optional<Func<int, int>> is a Func: " +
        Yes(sizeof(Optional<Func<int, int>>) == sizeof(Func<int, int>)));
    Console.WriteLine("Labelled is a word: " + Yes(sizeof(Labelled) == word));
    Console.WriteLine("Backwards is two words: " + Yes(sizeof(Backwards) == 2u * word));
    Console.WriteLine("Optional<int> keeps its tag: " + Yes(sizeof(Optional<int>) == 8u));
}

void ShowCases()
{
    Optional<String> nothing = None;
    Optional<String> promoted = "promoted";
    Optional<String> zero = default;
    Console.WriteLine(Describe(nothing) + ", " + Describe(promoted) + ", " + Describe(zero));
    Console.WriteLine("has: " + Yes(promoted.HasValue) + " " + Yes(nothing.HasValue) +
                      " fallback: " + nothing.GetValueOrDefault("fallback"));

    Optional<Optional<String>> outerNone = None;
    Optional<Optional<String>> innerNone = Some(nothing);
    Optional<Optional<String>> both = Some(promoted);
    Console.WriteLine(DescribeNested(outerNone) + ", " + DescribeNested(innerNone) + ", " +
                      DescribeNested(both));

    Console.WriteLine(DescribeEntry(new Entry(7, "seven")) + ", " + DescribeEntry(None));
    Console.WriteLine(DescribeSqueezed(new Squeezed(3, "three")) + ", " + DescribeSqueezed(None));

    Labelled blank = Blank;
    Labelled named = Named("label");
    Console.WriteLine("labelled: " + Yes(blank.Blank) + " " + Yes(named.Named));
    if (named.Named)
        Console.WriteLine("named " + named.Name);

    Backwards back = Blank;
    Console.WriteLine("backwards blank: " + Yes(back.Blank));

    Optional<Func<int, int>> doubling = Some((int x) => x * 2);
    Optional<Func<int, int>> absent = None;
    if (doubling is Some f)
        Console.WriteLine("func: " + Text.FromInteger(f.Value(21)) + " absent: " + Yes(absent.IsEmpty));
}

void ShowCounting()
{
    var list = new List<Optional<Tracked>>();
    list.Add(new Tracked("a"));
    list.Add(None);
    list.Add(new Tracked("b"));

    Optional<Tracked> copy = list[0u];
    list.RemoveAt(0u);
    Console.WriteLine("after removing a copied one: " + Text.FromInteger(Tracked.Dropped));
    copy = None;
    Console.WriteLine("after dropping the copy: " + Text.FromInteger(Tracked.Dropped));

    var map = new Dictionary<String, Optional<String>>();
    map.SetValue("one", "uno");
    map.SetValue("none", None);
    Console.WriteLine("map: " + Describe(map.GetValue("one")) + " " + Describe(map.GetValue("none")));

    list.Clear();
    Console.WriteLine("after clearing: " + Text.FromInteger(Tracked.Dropped));
}

int Main()
{
    ShowSizes();
    ShowCases();
    ShowCounting();
    return 0;
}
