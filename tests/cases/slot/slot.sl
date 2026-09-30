// SPDX-License-Identifier: 0BSD
//
// A Slot<T> is storage for a T that may not be there yet. An array of them may
// be made at any length, because an empty slot is its zero. For a T with a
// zero value a slot is a T; for one without, it is an Optional<T>, which is
// the same size, and what it held is released when it is cleared or dropped.
module SlotCase;

import Standard.Console;

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

String Yes(bool value) => value ? "yes" : "no";

void ShowSizes()
{
    Console.WriteLine("Slot<String> is a String: " + Yes(sizeof(Slot<String>) == sizeof(String)));
    Console.WriteLine("Slot<int> is an int: " + Yes(sizeof(Slot<int>) == sizeof(int)));
    Console.WriteLine("Slot<Entry> is an Entry: " + Yes(sizeof(Slot<Entry>) == sizeof(Entry)));
    Console.WriteLine("Slot<Optional<int>> is an Optional<int>: " +
        Yes(sizeof(Slot<Optional<int>>) == sizeof(Optional<int>)));
}

void ShowReadsAndWrites()
{
    Slot<String>[] room = new Slot<String>[4];
    room[0] = "first";
    room[1] = "second";
    Console.WriteLine(room[0].Value + " " + room[1].Value);

    room[0] = room[1];
    room[1].Clear();
    Console.WriteLine("moved: " + room[0].Value);

    // A zeroable element reads its zero from an empty slot.
    Slot<int>[] numbers = new Slot<int>[3];
    numbers[1] = 5;
    Console.WriteLine("numbers: " + Text.FromInteger(numbers[0].Value) + " " +
                      Text.FromInteger(numbers[1].Value));

    Slot<Entry>[] entries = new Slot<Entry>[2];
    entries[1] = new Entry(7, "seven");
    Console.WriteLine("entry: " + Text.FromInteger(entries[1].Value.Id) + " " + entries[1].Value.Name);
}

void ShowCounting()
{
    Slot<Tracked>[] tracked = new Slot<Tracked>[3];
    tracked[0] = new Tracked("a");
    tracked[1] = new Tracked("b");
    tracked[2] = new Tracked("c");

    tracked[0].Clear();
    Console.WriteLine("after clearing one: " + Text.FromInteger(Tracked.Dropped));

    tracked[1] = new Tracked("d");
    Console.WriteLine("after overwriting one: " + Text.FromInteger(Tracked.Dropped));
}

void ShowCopies()
{
    String[] words = ["one", "two", "three"];
    Slot<String>[] room = new Slot<String>[5];
    Slot<String>.Copy(words, room[1:]);

    String[] back = Slot<String>.ToArray(room[1:4]);
    Console.WriteLine("back: " + back[0] + " " + back[1] + " " + back[2] + " of " +
                      Text.FromInteger((long)back.Length));
}

int Main()
{
    ShowSizes();
    ShowReadsAndWrites();
    ShowCounting();
    Console.WriteLine("after the array went: " + Text.FromInteger(Tracked.Dropped));
    ShowCopies();
    return 0;
}
