// SPDX-License-Identifier: 0BSD
module Bad;

public class Sink {
    int value;

    // Something that can only be written is a method, not a property.
    public int Value { set { value = 0; } }
}

int Main() { return 0; }
