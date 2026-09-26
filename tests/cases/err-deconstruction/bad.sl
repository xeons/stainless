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

    (a, b) = (1, 2, 3);                     // SL0609
    (a, b) = new Plain();                   // SL0608
    var (x, y, z) = new Two();              // SL0608
    var n = (int p, int q) = pair;          // SL0771
    var (u, v) = (null, 1);                 // SL0553
    var loose = (null, 1);                  // SL0773

    (int, int)[] pairs = [(1, 2)];
    foreach ((a, var w) in pairs) { }       // SL0772

    var (same, same) = pair;                // SL0218
    return 0;
}
