// SPDX-License-Identifier: 0BSD
module Bad;

// `==` and `!=` come together. A type that answers one and not the other is a
// question nobody can ask twice, and the missing half fails at a call site far
// from the declaration that forgot it.
public struct Money {
    public long Cents;
    public static bool operator ==(Money a, Money b) { return a.Cents == b.Cents; }
}

int Main() { return 0; }
