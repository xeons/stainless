// SPDX-License-Identifier: 0BSD
//
// `x!` says a `C?` holds something. When it does not, the program stops there,
// before the null is stored where a `C` is trusted.
module AbortNullAsserted;

import Standard.Console;

class Node
{
    public int Value;
    public Node(int value) { Value = value; }
}

Node? Find(int wanted) => wanted == 1 ? new Node(1) : null;

int Main()
{
    Node found = Find(1)!;
    Console.WriteLine($"found {found.Value}");
    Node missing = Find(2)!;
    Console.WriteLine($"never {missing.Value}");
    return 0;
}
