// SPDX-License-Identifier: 0BSD
module Bad;

import Standard.Collections;

// `?.` and `?[` read. A write that happens only when the receiver is there is
// an `if`, and is written as one.

class Node
{
    public int Weight;
}

public int Main()
{
    Node? node = null;
    node?.Weight = 4;
    List<int>? numbers = new List<int> { 1 };
    numbers?[0] = 3;
    numbers?[0]++;
    return 0;
}
