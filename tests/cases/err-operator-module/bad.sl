// SPDX-License-Identifier: 0BSD
module Bad;

public struct Money
{
    public int Cents;
}

// An operator belongs to the type it is for; one at module level would give
// somebody else's type a meaning from a distance.
public static Money operator +(Money a, Money b) => a;

int Main() => 0;
