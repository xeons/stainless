// SPDX-License-Identifier: 0BSD
module Graph;

extern "C" int printf(byte* format, ...);

class Node
{
    int _id;
    Node? _next;

    Node(int n) => _id = n;
    ~Node() { printf("~Node(%d)\n", _id); }

    public int Id => _id;
    public void Link(Node other) => _next = other;
}

Node Build()
{
    var head = new Node(1);
    var tail = new Node(2);
    head.Link(tail);
    return head;
}

int Main()
{
    printf("build\n");
    {
        var chain = Build();
        printf("head=%d\n", chain.Id);
        printf("scope end\n");
    }
    printf("released\n");

    // Each iteration must destroy its own object, not accumulate them.
    for (int i = 0; i < 3; i = i + 1)
    {
        var temp = new Node(100 + i);
        printf("iter %d\n", temp.Id);
    }
    printf("loop done\n");
    return 0;
}
