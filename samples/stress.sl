// SPDX-License-Identifier: 0BSD
module Stress;

extern "C" int printf(byte* format, ...);

class Node
{
    int _id;
    Node? _next;

    Node(int n) => _id = n;

    ~Node() { printf("  ~Node(%d)\n", _id); }

    public int Id => _id;
    public void Link(Node other) => _next = other;
}

int Fib(int n)
{
    if (n < 2)
        return n;
    return Fib(n - 1) + Fib(n - 2);
}

int Main()
{
    printf("fib(20)     = %d\n", Fib(20));

    var total = 0;
    for (int i = 0; i < 10; i++)
    {
        if (i == 3)
            continue;
        if (i == 8)
            break;
        total += i;
    }
    printf("loop total  = %d (0+1+2+4+5+6+7 = 25)\n", total);

    var j = 0;
    var doubled = 0;
    while (j < 5)
    {
        doubled += j * 2;
        j++;
    }
    printf("while total = %d\n", doubled);
    printf("guard(0)    = %d\n", Guard(0));

    printf("building chain\n");
    {
        var a = new Node(1);
        var b = new Node(2);
        a.Link(b);
        printf("  a=%d b=%d\n", a.Id, b.Id);
        printf("  leaving inner scope\n");
    }
    printf("chain released\n");
    return 0;
}

// The right operand must not run when the left already decides the answer.
int Guard(int d)
{
    if (d != 0 && 100 / d > 1)
        return 1;
    return 0;
}
