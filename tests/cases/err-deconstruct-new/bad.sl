// SPDX-License-Identifier: 0BSD
module Bad;

// A 'new(...)' taken apart gets its type from the Deconstruct that takes it,
// and what that type cannot make is still an error.

struct Range
{
    public int Low;
}

void Deconstruct(Range range, out int low, out int high)
{
    low = range.Low;
    high = 2;
}

int Main()
{
    var (x, y) = new (3);                       // SLC0008
    return x + y;
}
