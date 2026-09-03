// SPDX-License-Identifier: 0BSD
module Bad;

static readonly int Limit = 64;

// A struct property setter writes the receiver's own storage, so through a
// static it is the same write a field would be.
public struct Point { public int X { get; set; } }

Point Start() { Point p; p.X = 1; return p; }
static readonly Point Origin = Start();

int Main() {
    Limit = 128;        // every static is readonly
    Origin.X = 9;       // and a property is no way around that
    return Limit;
}
