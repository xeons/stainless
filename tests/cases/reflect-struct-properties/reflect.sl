// SPDX-License-Identifier: 0BSD
//
// A struct property is read and written through reflection, whatever its
// size and however the target passes it: in one register, in two, in
// registers wider than it, or in memory.
module ReflectStructs;

import Standard.Console;
import Standard.Reflection;
import Standard.Text;

public struct Rgba
{
    public byte R;
    public byte G;
    public byte B;
    public byte A;
}

public struct Triple
{
    public int X;
    public int Y;
    public int Z;
}

public struct Pair
{
    public double First;
    public double Second;
}

public struct Mixed
{
    public long Count;
    public double Ratio;
}

public struct Large
{
    public long A;
    public long B;
    public long C;
    public long D;
    public long E;
}

public struct Labelled
{
    public String? Label;
}

[Reflect]
public class Holder
{
    public int Sets;
    Rgba _colour;

    public Rgba Colour
    {
        get => _colour;
        set
        {
            _colour = value;
            Sets++;
        }
    }

    public Triple Where { get; set; }
    public Pair Range { get; set; }
    public Mixed Measure { get; set; }
    public Large Big { get; set; }
    public Labelled Tag { get; set; }
    public String[] Names { get; set; } = [];
    public Triple[]? Points { get; set; }

    /// Made for each call, so reading it MUST NOT borrow from it.
    public String[] Fresh => ["made", "each", "time"];
}

Property Find(String name) => typeof(Holder).FindProperty(name);

int Main()
{
    var holder = new Holder();
    byte* raw = (byte*)holder;

    Rgba colour;
    colour.R = 10;
    colour.G = 20;
    colour.B = 30;
    colour.A = 255;
    SetStruct(raw, Find("Colour"), (byte*)&colour);
    Rgba readColour;
    GetStruct(raw, Find("Colour"), (byte*)&readColour);
    Console.WriteLine("colour " + Text.FromInteger(readColour.R) + " " + Text.FromInteger(readColour.G) + " " +
                      Text.FromInteger(readColour.B) + " " + Text.FromInteger(readColour.A) +
                      ", set " + Text.FromInteger(holder.Sets) + " time");

    Triple where;
    where.X = 1;
    where.Y = -2;
    where.Z = 3;
    SetStruct(raw, Find("Where"), (byte*)&where);
    Triple readWhere;
    GetStruct(raw, Find("Where"), (byte*)&readWhere);
    Console.WriteLine("where " + Text.FromInteger(readWhere.X) + " " + Text.FromInteger(readWhere.Y) + " " +
                      Text.FromInteger(readWhere.Z));

    Pair range;
    range.First = 0.5;
    range.Second = 2.25;
    SetStruct(raw, Find("Range"), (byte*)&range);
    Pair readRange;
    GetStruct(raw, Find("Range"), (byte*)&readRange);
    Console.WriteLine("range " + Text.FromDouble(readRange.First) + " " + Text.FromDouble(readRange.Second));

    Mixed measure;
    measure.Count = 7;
    measure.Ratio = 1.5;
    SetStruct(raw, Find("Measure"), (byte*)&measure);
    Mixed readMeasure;
    GetStruct(raw, Find("Measure"), (byte*)&readMeasure);
    Console.WriteLine("measure " + Text.FromInteger(readMeasure.Count) + " " + Text.FromDouble(readMeasure.Ratio));

    Large big;
    big.A = 1;
    big.B = 2;
    big.C = 3;
    big.D = 4;
    big.E = 5;
    SetStruct(raw, Find("Big"), (byte*)&big);
    Large readBig;
    GetStruct(raw, Find("Big"), (byte*)&readBig);
    Console.WriteLine("big " + Text.FromInteger(readBig.A + readBig.B + readBig.C + readBig.D + readBig.E));

    // Read straight from the object, so a thunk that wrote the wrong bytes
    // shows here and not only in its own answer.
    Console.WriteLine("stored " + Text.FromInteger(holder.Where.Y) + " " + Text.FromDouble(holder.Measure.Ratio) +
                      " " + Text.FromInteger(holder.Big.E));

    var tag = Find("Tag");
    Console.WriteLine("a struct holding a String: read " + (tag.CanRead ? "yes" : "no") +
                      ", write " + (tag.CanWrite ? "yes" : "no"));

    Console.WriteLine("elements: names " + (Find("Names").ElementKind == KindString ? "String" : "?") +
                      ", points " + (Find("Points").ElementKind == KindStruct ? "struct" : "?") +
                      ", colour " + (Find("Colour").ElementKind == KindNone ? "none" : "?"));

    holder.Names = ["one", "two"];
    var names = GetTextArray(raw, Find("Names"));
    var fresh = GetTextArray(raw, Find("Fresh"));
    Console.WriteLine("names " + Text.FromInteger((long)names.Length) + ": " + names[0u] + " " + names[1u] +
                      "; fresh " + fresh[0u] + " " + fresh[1u] + " " + fresh[2u] +
                      "; not text " + Text.FromInteger((long)GetTextArray(raw, Find("Points")).Length));
    return 0;
}
