// SPDX-License-Identifier: 0BSD
module Bad;

// `default(void)` names no value, `void` being the absence of one. And a
// uniform call still has to find something: `x.F(y)` is `F(x, y)` only where
// such an `F` is in scope and takes an `x` first.

int Length(String text) { return (int)text.ByteLength(); }

int Main() {
    var nothing = default(void);

    // No member, and no function of the name at all.
    var missing = "text".Reverse();

    // A function of the name, but its first parameter is not a String.
    var wrong = "text".Widen();
    return 0;
}

int Widen(int n) { return n * 2; }
