// SPDX-License-Identifier: 0BSD
//
// A struct method that only reads is called in place on storage that may not
// be written, and a copy is where a change to such storage belongs.
module ReadOnlyReceivers;

import Standard.Console;
import Standard.Text;

public struct Vector
{
    public int X;
    public int Y;

    public Vector(int x, int y) { X = x; Y = y; }

    public int LengthSquared => X * X + Y * Y;

    public int Dot(Vector other) => X * other.X + Y * other.Y;

    // Reads through another method, and so only reads.
    public int Twice() => 2 * Dot(this);

    public void Scale(int by) { X *= by; Y *= by; }
}

static readonly Vector s_unit = new Vector(1, 0);

int Measure(in Vector v) => v.LengthSquared + v.Twice();

int Main()
{
    var v = new Vector(3, 4);
    Console.WriteLine(Text.FromInteger(Measure(v)));
    Console.WriteLine(Text.FromInteger(s_unit.Dot(v)));

    Vector[] vectors = [new Vector(1, 1), new Vector(2, 2)];
    ReadOnlySpan<Vector> seen = vectors;
    Console.WriteLine(Text.FromInteger(seen[1].LengthSquared));

    Vector copy = seen[1];
    copy.Scale(10);
    Console.WriteLine(Text.FromInteger(copy.X) + " " + Text.FromInteger(vectors[1].X));
    return 0;
}
