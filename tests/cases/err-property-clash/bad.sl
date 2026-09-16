// SPDX-License-Identifier: 0BSD
module Bad;

public class Person
{
    public int _Age { get; set; }

    // The automatic property already owns storage called Age.
    int _Age;
}

int Main() => 0;
