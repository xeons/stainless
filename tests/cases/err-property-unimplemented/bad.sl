// SPDX-License-Identifier: 0BSD
module Bad;

public interface ICounted {
    int Count { get; set; }
}

// A field of the right name is not a property: the interface wants accessors.
public class Bag : ICounted {
    public int Count;
}

int Main() { return 0; }
