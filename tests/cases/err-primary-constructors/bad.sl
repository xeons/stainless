// SPDX-License-Identifier: 0BSD
//
// Every other constructor runs the primary one, a static member has no
// instance to read a kept parameter from, and a parameter that is the
// caller's storage cannot be kept.
module Bad;

public class Service(int size)
{
    public Service() { }

    public static int Twice() => size * 2;
}

public class Counter(ref int total)
{
    public int Read() => total;
}

int Main() => 0;
