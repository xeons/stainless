// SPDX-License-Identifier: 0BSD
module Bad;

public struct Counter
{
    public int Count;

    public Counter(int count) { Count = count; }

    public int Limit { get; set; }

    public void Bump() { Count++; }

    // Writes only through another method, which is a write all the same.
    public void BumpTwice() { Bump(); Bump(); }

    public int Peek() => Count;
}

static readonly Counter s_shared = new Counter(0);

void Direct(in Counter c) { c.Bump(); }
void Indirect(in Counter c) { c.BumpTwice(); }
void Setter(in Counter c) { c.Limit = 3; }
void Reads(in Counter c) { int n = c.Peek(); }

int Main()
{
    s_shared.BumpTwice();

    Counter[] counters = new Counter[2];
    ReadOnlySpan<Counter> seen = counters;
    seen[0].Bump();
    return 0;
}
