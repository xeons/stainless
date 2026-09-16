// SPDX-License-Identifier: 0BSD
//
// A library whose signatures have defaults. What crosses is the *value*: a
// default may name a const of the library's own, and the consumer has no way
// to read that -- so the metadata carries the number it folded to.
module Library.Paint;

public const int Standard = 7;

public enum Shade { Pale, Deep }

public class Brush
{
    public String Name;
    public int Width;

    public Brush(String name, int width = Standard)
    {
        Name = name;
        Width = width;
    }

    public String Stroke(int length = 3, Shade shade = Shade.Deep)
    {
        return Name + " " + Text.FromInteger(length) + " " + Text.FromInteger((int)shade);
    }
}

public String Label(String text, String suffix = " (std)", bool upper = false)
{
    String made = text + suffix;
    return upper ? made.ToUpperAscii() : made;
}
