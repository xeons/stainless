// SPDX-License-Identifier: 0BSD
//
// `Standard.Json` at the edges of RFC 8259: what it must refuse, what it must
// never write, and what a reader fills when the document is not what the type
// expected.
module JsonStrictTest;

import Standard.Json;
import Standard.Console;
import Standard.Collections;
import Standard.Math;
import Standard.Reflection;

void Say(String label, String value)
{
    Console.WriteLine(label + " = " + value);
}

/// Every code point of the text, in decimal, so a U+FFFD is visible.
String Points(String text)
{
    var built = new StringBuilder();
    nuint at = 0u;
    while (at < text.ByteLength())
    {
        if (at > 0u)
            built.Append(" ");
        char32 point = text.GetCodePointAt(at);
        built.Append(Text.FromInteger((long)(uint)point));
        at = at + (nuint)Text.FromChar(point).ByteLength();
    }
    return built.ToText();
}

void Decode(String label, String text)
{
    var parsed = Json.Parse(text);
    if (!parsed.Ok)
    {
        Say(label, "failed: " + Json.DescribeJsonError(parsed.Error));
        return;
    }
    Say(label, Points(Json.GetTextOrDefault(parsed.Value, "?")));
}

/// A document read and written back, or why it could not be read.
String Rewrite(String text)
{
    var parsed = Json.Parse(text);
    if (!parsed.Ok)
        return "failed: " + Json.DescribeJsonError(parsed.Error);
    return Json.ToJsonText(parsed.Value);
}

/// A document read as a whole number, or the fallback.
long IntegerIn(String text, long fallback)
{
    var parsed = Json.Parse(text);
    if (!parsed.Ok)
        return fallback;
    return Json.GetIntegerOrDefault(parsed.Value, fallback);
}

void Refuse(String label, String text)
{
    var parsed = Json.Parse(text);
    if (parsed.Ok)
    {
        Say(label, "accepted, and should not have been: " + Json.ToJsonText(parsed.Value));
        return;
    }
    Say(label, Json.DescribeJsonError(parsed.Error));
}

[Reflect]
public class Item
{
    public String Label;
    public int Size;

    public Item()
    {
        Label = "";
        Size = 0;
    }
}

[Reflect]
public class Holder
{
    public String Name;
    public Item[] Items;
    public String[] Tags;
    public long Big;
    public int Small;

    public Holder() => Name = "kept";
}

[Reflect]
public class Measured
{
    public double Value;
    public Measured() => Value = 0.0;
}

public int Main()
{
    // ------------------------------------------------------------ numbers
    // A numeral past what a double holds is not a number JSON can carry.
    Refuse("overflow", "1e400");
    Refuse("overflow-negative", "[-1e400]");
    Say("underflow", Rewrite("1e-400"));

    double zero = 0.0;
    var odd = Json.CreateJsonArray();
    Json.GetItems(odd).Add(JsonValue.Number(1.0 / zero));
    Json.GetItems(odd).Add(JsonValue.Number(-1.0 / zero));
    Json.GetItems(odd).Add(JsonValue.Number(Math.Sqrt(-1.0)));
    Say("non-finite", Json.ToJsonText(odd));

    var measured = new Measured();
    measured.Value = 1.0 / zero;
    Say("non-finite-field", Json.Serialize(measured));

    // Past what a long holds, and so past what any cast may be asked for.
    Say("huge-write", Rewrite("[1e300,-1e300,1e19]"));
    Say("huge-integer", Text.FromInteger(IntegerIn("1e300", -7)));
    Say("edge-integer", Text.FromInteger(IntegerIn("-9223372036854775808", -7)));

    // ---------------------------------------------------------- surrogates
    // An escape after an unpaired high surrogate is read for what it is.
    Decode("high-then-letter", "\"\\ud800\\u0041\"");
    Decode("high-then-pair", "\"\\ud83d\\ud83d\\ude00\"");
    Decode("high-then-escape", "\"\\ud800\\n\"");
    Decode("pair", "\"\\ud83d\\ude00\"");
    Decode("low-alone", "\"\\ude00x\"");

    // ---------------------------------------------------- control characters
    Refuse("raw-tab", "\"a\tb\"");
    Refuse("raw-newline", "\"a\nb\"");
    Refuse("raw-unit", "\"\u0001\"");
    Refuse("raw-in-name", "{\"a\u001fb\":1}");
    Decode("escaped-tab", "\"a\\tb\"");
    Decode("delete-is-fine", "\"\u007f\"");

    // --------------------------------------------------------- the mapping
    // A null array is made at the document's length; every element of it
    // is a real value of its type, whatever the document held there.
    var holder = new Holder();
    var failure = Json.PopulateObject(holder,
        "{\"Items\":[{\"Label\":\"a\",\"Size\":1},7,{\"Size\":3}]," +
        "\"Tags\":[\"x\",4,null]}");
    Say("populate", Json.DescribeJsonError(failure));
    Say("items", Json.Serialize(holder));
    Say("item-label", holder.Items[1u].Label + "|" + holder.Items[2u].Label + "|");
    Say("tag-lengths", Text.FromInteger((long)holder.Tags[1u].ByteLength())
        + "/" + Text.FromInteger((long)holder.Tags[2u].ByteLength()));

    // A number past the field's reach is skipped, as a wrong type is.
    var ranged = new Holder();
    ranged.Big = 5;
    ranged.Small = 6;
    Json.PopulateObject(ranged, "{\"Big\":1e300,\"Small\":-1e300}");
    Say("out-of-range", Text.FromInteger(ranged.Big) + "/" + Text.FromInteger((long)ranged.Small));

    return 0;
}
