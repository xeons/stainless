// SPDX-License-Identifier: 0BSD
//
// Nothing but `base(...)` and `this(...)` may follow the colon. C++ puts a
// field initializer list there and C# puts nothing else either; a field here
// is initialized where it is declared or in the body.
module ChainJunk;

class Root
{
    public int N;
    public Root(int n) { N = n; }
}

class Odd : Root
{
    public Odd() : other(1) { }
}

int Main() { return 0; }
