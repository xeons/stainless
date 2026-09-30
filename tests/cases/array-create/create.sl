// `Array.Create` and `Array.Repeat`, which make an array whole, and the
// `Slot<T>` array a collection keeps spare capacity in.
module ArrayCreate;

import Standard.Console;

public class Item
{
    public int Id;
    public Item(int id) => Id = id;
}

int Main()
{
    String[] names = Array.Create(3u, (i) => $"item {i}");
    foreach (var name in names)
        Console.WriteLine(name);

    Item[] items = Array.Create(2u, (i) => new Item((int)i * 10));
    Console.WriteLine($"{items[0].Id} {items[1].Id}");

    int[] sevens = Array.Repeat(7, 4u);
    Console.WriteLine($"{sevens.Length} {sevens[3]}");

    String[] words = Array.Repeat("w", 2u);
    Console.WriteLine(words[0] + words[1]);

    String[] none = Array.Create(0u, (i) => "never");
    Console.WriteLine($"{none.Length}");

    Slot<String>[] slots = new Slot<String>[2u];
    slots[0] = "a";
    slots[1] = "b";
    slots[1].Clear();
    slots[1] = "c";
    Console.WriteLine(slots[0].Value + slots[1].Value);
    return 0;
}
