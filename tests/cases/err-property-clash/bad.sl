// SPDX-License-Identifier: 0BSD
module Bad;

public class Person {
    public int Age { get; set; }

    // The automatic property already owns storage called Age.
    int Age;
}

int Main() { return 0; }
