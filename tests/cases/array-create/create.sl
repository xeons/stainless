// `Array.Create` and `Array.Repeat`, which make an array whole, and the
// `Standard.Unchecked` pair a collection keeps spare capacity with.
module ArrayCreate;

import Standard.Console;
import Standard.Unchecked;

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

    String[] slots = NewUninitializedArray<String>(2u);
    slots[0] = "a";
    slots[1] = "b";
    ClearElement(slots, 1u);
    slots[1] = "c";
    Console.WriteLine(slots[0] + slots[1]);
    return 0;
}
