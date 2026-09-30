// SPDX-License-Identifier: 0BSD
//
// A library that allocates what its consumer releases, and writes between
// the consumer's lines.
module Library.Boxes;

import Standard.Console;

public class Box
{
    public int Value;

    public Box(int value)
    {
        Value = value;
    }

    public static Box Make(int value)
    {
        Console.WriteLine("made in the library");
        return new Box(value);
    }
}
