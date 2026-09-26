// SPDX-License-Identifier: 0BSD
module Bad;

public closure int Transform(int value);
public closure int Pair(int a, int b);

int Next() => 1;

int Main()
{
    // A result written out is the target's, not converted to it.
    Transform wrong = long (x) => x;

    // A default is seen only through the lambda's own type.
    Transform unseen = (int x = 4) => x;

    // And it is a constant, as a function's is.
    var running = (int x = Next()) => x;

    // Two discards are not names.
    Pair both = (_, _) => _;

    // Returns that agree on nothing give the lambda no type.
    var mixed = (bool flag) => { if (flag) { return 1; } return "one"; };
    return 0;
}
