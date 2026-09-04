// SPDX-License-Identifier: 0BSD
module Arrays;

import Standard.Console;

class Tracker {
    int id;
    Tracker(int n) { id = n; }
    ~Tracker() { Console.WriteLine("~Tracker " + Text.FromInteger(id)); }
    public int Id() { return id; }
}

int Sum(int[] values) {
    var total = 0;
    for (int i = 0; i < (int)values.Length; i = i + 1) { total = total + values[i]; }
    return total;
}

int Main() {
    var numbers = new int[5];
    for (int i = 0; i < 5; i = i + 1) { numbers[i] = i * i; }

    Console.WriteLine("length=" + Text.FromInteger(numbers.Length));
    Console.WriteLine("sum=" + Text.FromInteger(Sum(numbers)));
    Console.WriteLine("zeroed=" + Text.FromInteger(new int[3][0]));

    // Arrays of struct values store them inline.
    var flags = new bool[2];
    flags[1] = true;
    Console.WriteLine("flags=" + Text.FromBool(flags[0]) + "," + Text.FromBool(flags[1]));

    // Arrays of references retain their elements and release them on death.
    {
        var tracked = new Tracker[2];
        tracked[0] = new Tracker(1);
        tracked[1] = new Tracker(2);
        Console.WriteLine("ids=" + Text.FromInteger(tracked[0].Id() + tracked[1].Id()));
        Console.WriteLine("dropping array");
    }
    Console.WriteLine("done");
    return 0;
}
