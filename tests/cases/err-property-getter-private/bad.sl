// SPDX-License-Identifier: 0BSD
module Bad;

public class Person {
    // The getter is what the property's visibility means, so it cannot differ.
    public int Age { private get; set; }
}

int Main() { return 0; }
