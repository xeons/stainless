// SPDX-License-Identifier: 0BSD
//
// The clause and the statement are two spellings of one call, so writing both
// asks for the base to be built twice.
module ChainTwice;

class Root
{
    public int N;
    public Root(int n) { N = n; }
}

class Twice : Root
{
    public Twice() : base(1)
    {
        base(2);
    }
}

int Main() { return 0; }
