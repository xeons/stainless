// SPDX-License-Identifier: 0BSD
module ForEach;

import Standard.Collections;
import Standard.Console;

extern "C" int printf(byte* format, ...);

class Item {
    String name;
    Item(String n) { name = n; }
    public String Name() { return name; }
}

// A type that is iterable without implementing any interface: foreach finds
// GetEnumerator by name.
class Countdown {
    int from;
    Countdown(int start) { from = start; }
    public CountdownCursor GetEnumerator() { return new CountdownCursor(from); }
}

class CountdownCursor {
    int value;
    CountdownCursor(int start) { value = start + 1; }
    public bool MoveNext() {
        value = value - 1;
        return value > 0;
    }
    public int Current() { return value; }
}

int Main() {
    // An array iterates by index; no allocation, no dispatch.
    var numbers = new int[4];
    numbers[0] = 5; numbers[1] = 6; numbers[2] = 7; numbers[3] = 8;

    int total = 0;
    foreach (int n in numbers) { total = total + n; }
    printf("total=%d\n", total);

    // `var` infers the element type.
    int doubled = 0;
    foreach (var n in numbers) { doubled = doubled + n * 2; }
    printf("doubled=%d\n", doubled);

    // break and continue behave as in any other loop.
    int firstOdd = 0;
    foreach (int n in numbers) {
        if (n % 2 == 0) { continue; }
        firstOdd = n;
        break;
    }
    printf("firstOdd=%d\n", firstOdd);

    // A managed element: each is retained for the iteration and released after.
    var items = new Item[2];
    items[0] = new Item("alpha");
    items[1] = new Item("beta");
    foreach (Item item in items) { Console.WriteLine(item.Name()); }

    // A List<T> goes through IEnumerator<T>.
    var list = new List<int>();
    list.Add(10);
    list.Add(20);
    list.Add(30);

    int listTotal = 0;
    foreach (int n in list) { listTotal = listTotal + n; }
    printf("listTotal=%d\n", listTotal);

    // Duck typing: Countdown implements no interface at all.
    var ticks = 0;
    foreach (int n in new Countdown(3)) { ticks = ticks * 10 + n; }
    printf("ticks=%d\n", ticks);

    // Nested, over the same array.
    int pairs = 0;
    foreach (int a in numbers) {
        foreach (int b in numbers) { pairs = pairs + 1; }
    }
    printf("pairs=%d\n", pairs);

    printf("done\n");
    return 0;
}
