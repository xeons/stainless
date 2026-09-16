// SPDX-License-Identifier: 0BSD
//
// What a type is called when it crosses a library boundary. Every shape the
// metadata writer can produce has to be one the reader accepts: a name only
// one of them knows is silent on both sides, which is how a `char16` field
// came to be described by a library and refused by its consumer.
module Library.Names;

public struct Units
{
    public char Byte;
    public char16 Utf16;
    public char32 Scalar;
    public float Ratio;
    public nuint Count;
}

public struct Point
{
    public int X;
    public int Y;
}

// A slice and a tuple are structural but named, so the consumer has to reach
// the very same symbol its own source resolves to rather than a second copy.
public int[:] Tail(int[] numbers) { return numbers[1:]; }
public (int, String) Pair(int n) { return (n, "pair"); }
public (Point, int[:]) Both(int[] numbers)
{
    Point p;
    p.X = 1;
    p.Y = 2;
    return (p, numbers[2:]);
}

public Units Measure()
{
    Units u;
    u.Byte = 'a';
    u.Utf16 = '\u00E9';
    u.Scalar = '\U0001F600';
    u.Ratio = 0.5f;
    u.Count = 3;
    return u;
}

public int[] Squares(nuint n)
{
    var made = new int[n];
    for (nuint i = 0; i < n; i++) made[i] = (int)(i * i);
    return made;
}
