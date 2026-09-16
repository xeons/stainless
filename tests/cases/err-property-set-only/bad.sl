// SPDX-License-Identifier: 0BSD
module Bad;

public class Sink
{
    int _value;

    // Something that can only be written is a method, not a property.
    public int Value { set { _value = 0; } }
}

int Main() => 0;
