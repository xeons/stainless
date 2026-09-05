// SPDX-License-Identifier: 0BSD
module Bad;

// An operator only this module could write is a method with a strange spelling.
public struct Money {
    public long Cents;
    static Money operator +(Money a, Money b) { return a; }
}

int Main() { return 0; }
