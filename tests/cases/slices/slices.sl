// SPDX-License-Identifier: 0BSD
module Slices;

import Standard.Console;
import Standard.Collections;

public class Trace {
    public String Name { get; }
    public Trace(String name) { Name = name; }
    ~Trace() { Console.WriteLine("~" + Name); }
}

int Sum(int[:] values) {
    int total = 0;
    for (nuint i = 0; i < values.Length; i = i + 1) { total = total + values[i]; }
    return total;
}

int SumEach(int[:] values) {
    int total = 0;
    foreach (int v in values) { total = total + v; }
    return total;
}

// A slice is a view, so writing through one writes the array it came from.
void Fill(int[:] values, int with) {
    for (nuint i = 0; i < values.Length; i = i + 1) { values[i] = with; }
}

String Show(int[] values) {
    String text = "";
    foreach (int v in values) { text = text + Text.FromInteger(v) + " "; }
    return text;
}

// The array outlives the function that made it, because the slice holds it.
Trace[:] Middle() {
    var traces = new Trace[3];
    traces[0] = new Trace("a");
    traces[1] = new Trace("b");
    traces[2] = new Trace("c");
    return traces[1:2];
}

int Main() {
    var numbers = new int[6];
    for (nuint i = 0; i < numbers.Length; i = i + 1) { numbers[i] = (int)i + 1; }

    // An array is a slice of the whole of itself, so no cast is needed.
    Console.WriteLine(Text.FromInteger(Sum(numbers)));

    // All four forms; either end may be left out.
    Console.WriteLine(Text.FromInteger(Sum(numbers[1:4])));
    Console.WriteLine(Text.FromInteger(Sum(numbers[3:])));
    Console.WriteLine(Text.FromInteger(Sum(numbers[:2])));
    Console.WriteLine(Text.FromInteger(Sum(numbers[:])));
    Console.WriteLine(Text.FromInteger(SumEach(numbers[2:5])));

    int[:] window = numbers[1:5];
    Console.WriteLine(Text.FromInteger((int)window.Length) + " " +
                      Text.FromInteger(window[0]));

    // Slicing a slice narrows it: the same array, further in.
    int[:] narrower = window[1:3];
    Console.WriteLine(Text.FromInteger(narrower[0]) + " " +
                      Text.FromInteger((int)narrower.Length));

    Fill(numbers[2:4], 0);
    Console.WriteLine(Show(numbers));

    // Three words: the array, where it starts, and how far it runs.
    Console.WriteLine("sizeof=" + Text.FromInteger((int)sizeof(int[:])));

    Console.WriteLine("--- sorting ---");
    var values = new int[6];
    values[0] = 5; values[1] = 3; values[2] = 9;
    values[3] = 1; values[4] = 7; values[5] = 2;

    Sort(values[1:4]);
    Console.WriteLine(Show(values));
    Sort(values);
    Console.WriteLine(Show(values));
    Reverse(values[2:5]);
    Console.WriteLine(Show(values));

    var words = new String[3];
    words[0] = "pear";
    words[1] = "apple";
    words[2] = "fig";
    Sort(words);
    Console.WriteLine(words[0] + "," + words[1] + "," + words[2]);

    Console.WriteLine("--- lifetime ---");
    {
        // The array the slice came from is gone from the source, and alive.
        Trace[:] kept = Middle();
        Console.WriteLine(kept[0].Name);
        Console.WriteLine("leaving");
    }
    Console.WriteLine("left");

    return 0;
}
