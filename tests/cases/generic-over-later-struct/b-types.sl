module Seam;

/// Four bytes, and the size the whole test is about.
public struct Colour
{
    public byte R;
    public byte G;
    public byte B;
    public byte A;

    public static Colour Of(byte r, byte g, byte b)
    {
        Colour made;
        made.R = r;
        made.G = g;
        made.B = b;
        made.A = 255;
        return made;
    }
}

/// A second one, reached only through the interface, to check that the
/// deferral covers what an instantiation names indirectly too.
public struct Pair
{
    public int First;
    public int Second;

    public static Pair Of(int first, int second)
    {
        Pair made;
        made.First = first;
        made.Second = second;
        return made;
    }
}
