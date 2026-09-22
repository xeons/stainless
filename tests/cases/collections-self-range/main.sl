// A list given itself.
module Main;

import Standard.Console;
import Standard.Collections;
import Standard.Text;

void Say(String what, bool passed)
{
    Console.WriteLine((passed ? "ok   " : "FAIL ") + what);
}

int Main()
{
    var list = new List<int>();
    list.Add(1);
    list.Add(2);
    list.Add(3);
    list.AddRange(list);
    Say("a list added to itself doubles", list.Count == 6u && list[5u] == 3);

    list.InsertRange(1u, list);
    Say("and inserted into itself, in order", list.Count == 12u && list[0u] == 1
        && list[1u] == 1 && list[6u] == 3 && list[7u] == 2 && list[11u] == 3);

    var empty = new List<int>();
    list.InsertRange(12u, empty);
    Say("an empty range changes nothing", list.Count == 12u);

    return 0;
}
