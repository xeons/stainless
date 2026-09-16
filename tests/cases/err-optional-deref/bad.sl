// SPDX-License-Identifier: 0BSD
module Bad;

class Node
{
    int _id;
    Node? _next;
    Node(int n) => _id = n;
    public int Peek() => _next._id; // next may be null
}

int Main() => 0;
