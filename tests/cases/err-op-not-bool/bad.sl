// SPDX-License-Identifier: 0BSD
module Bad;

// A comparison answers a question, so it returns bool.
public struct Money {
    public long Cents;
    public static int operator ==(Money a, Money b) { return 0; }
    public static int operator !=(Money a, Money b) { return 1; }
}

int Main() { return 0; }
