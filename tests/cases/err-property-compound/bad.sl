// SPDX-License-Identifier: 0BSD
module Bad;

public class Counter {
    public int Value { get; set; }
    public Counter() { Value = 0; }
}

Counter Make() { return new Counter(); }

int Main() {
    // The getter and the setter would each call Make(), on different objects.
    Make().Value += 1;
    return 0;
}
