// SPDX-License-Identifier: 0BSD
module Bad;

public class Person {
    // Half a hidden field is not a thing: the written setter has no storage to
    // name, and the automatic getter has one nothing else can reach.
    public int Age { get; set { } }
}

int Main() { return 0; }
