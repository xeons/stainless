// SPDX-License-Identifier: 0BSD
module Bad;

// Taking apart names exactly as many things as there are, only what has a
// tuple's shape or a Deconstruct can be taken apart, a declaration belongs to
// a statement, a foreach declares what it takes apart into, and a tuple whose
// element waits for a type needs somewhere to get one.

class Plain { }

class Two
{
    public void Deconstruct(out int a, out int b)
    {
        a = 1;
        b = 2;
    }
}

int Main()
{
    int a = 0;
    int b = 0;
    var pair = (1, "one");

    (a, b) = (1, 2, 3);                     // SLF0031
    (a, b) = new Plain();                   // SLF0030
    var (x, y, z) = new Two();              // SLF0030
    var n = (int p, int q) = pair;          // SLF0040
    var (u, v) = (null, 1);                 // SLT0061
    var loose = (null, 1);                  // SLT0076

    (int, int)[] pairs = [(1, 2)];
    foreach ((a, var w) in pairs) { }       // SLF0041

    var (same, same) = pair;                // SLN0008
    return 0;
}
