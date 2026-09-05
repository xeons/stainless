// SPDX-License-Identifier: 0BSD
module Bad;

// One operand has to be the declaring type, so that reading `a + b` says where
// to look for what it means. Otherwise a type could give `int + int` a meaning.
public struct Money {
    public long Cents;
    public static int operator +(int a, int b) { return a + b; }
}

int Main() { return 0; }
