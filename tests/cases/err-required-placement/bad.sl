// SPDX-License-Identifier: 0BSD
//
// Only a field or a property of an object can be required.
module Bad;

public class Holder
{
    public required void Run() { }
    public static required int Count = 0;
}

int Main() => 0;
