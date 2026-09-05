// StringBuilder and Utf16String, and the ASCII questions a byte can answer.
//
// A builder's bytes are a growable allocation that moves, so unlike String it
// hands out no pointer: reading and editing go through the runtime one byte at
// a time. That is what `ByteAt`, `Insert` and `Remove` are for, and everything
// else here is written on top of them in Stainless.
module TextBuilder;

import Standard.Console;
import Standard.Text;
import Standard.Ascii;

void Say(String label, String value) {
    Console.WriteLine(label + " " + value);
}

void SayNumber(String label, long value) {
    Console.WriteLine(label + " " + Text.FromInteger(value));
}

void SayBool(String label, bool value) {
    Console.WriteLine(label + " " + Text.FromBool(value));
}

int Main() {
    // ------------------------------------------------------------ appending
    var built = new StringBuilder();
    built.Append("count=");
    built.AppendInteger(42);
    built.Append(" ok=");
    built.Append(true);
    Say("appended", built.ToText());

    var scalars = new StringBuilder();
    scalars.AppendCodePoint((char32)97);        // a
    scalars.AppendCodePoint((char32)233);       // é, two bytes
    scalars.AppendCodePoint((char32)8364);      // €, three bytes
    scalars.AppendCodePoint((char32)128512);    // an emoji, four bytes
    Say("scalars", scalars.ToText());
    SayNumber("scalar-bytes", (long)scalars.ByteLength());
    SayNumber("scalar-points", (long)scalars.ToText().CodePointCount());

    // A surrogate is not a scalar and cannot be encoded, so it becomes the
    // replacement character rather than corrupting the builder.
    var lone = new StringBuilder();
    lone.AppendCodePoint((char32)0xD800);
    SayNumber("lone-surrogate", (long)(uint)lone.ToText().CodePointAt(0u));

    var joined = new StringBuilder();
    joined.AppendJoined(", ", ["one", "two", "three"]);
    Say("joined", joined.ToText());

    // -------------------------------------------------------------- reading
    var read = new StringBuilder();
    read.Append("hello world");
    SayNumber("byte-at", (long)read.ByteAt(0u));
    SayNumber("index-of", read.IndexOf("world"));
    SayNumber("index-missing", read.IndexOf("nope"));
    SayBool("contains", read.Contains("lo wo"));
    SayBool("has-content", read.HasContent());

    // -------------------------------------------------------------- editing
    var edited = new StringBuilder();
    edited.Append("hello world");
    edited.Insert(5u, ",");
    Say("inserted", edited.ToText());

    edited.Remove(0u, 6u);
    Say("removed", edited.ToText());

    edited.Truncate(3u);
    Say("truncated", edited.ToText());

    var replaced = new StringBuilder();
    replaced.Append("one two one two");
    SayNumber("replaced-all", (long)replaced.ReplaceAll("one", "1"));
    Say("replaced", replaced.ToText());

    var grow = new StringBuilder();
    grow.Append("aaa");
    SayNumber("grow-count", (long)grow.ReplaceAll("a", "aa"));
    Say("grow", grow.ToText());

    var first = new StringBuilder();
    first.Append("x-x-x");
    SayBool("replaced-first", first.ReplaceFirst("-", "+"));
    Say("first", first.ToText());

    var setter = new StringBuilder();
    setter.Append("cat");
    setter.SetByteAt(0u, (byte)'b');
    Say("set-byte", setter.ToText());

    // ---------------------------------------------------------- Utf16String
    var wide = "aé€".ToUtf16();
    SayNumber("utf16-units", (long)wide.UnitCount());
    SayBool("utf16-empty", wide.IsEmpty());
    SayNumber("utf16-unit-at", (long)(uint)wide.UnitAt(0u));
    SayNumber("utf16-point", (long)(uint)wide.CodePointAt(1u));
    Say("utf16-round-trip", wide.ToText());

    // An emoji is a surrogate pair: two units, one character.
    var pair = "😀".ToUtf16();
    SayNumber("pair-units", (long)pair.UnitCount());
    SayNumber("pair-point", (long)(uint)pair.CodePointAt(0u));
    SayNumber("pair-next", (long)pair.NextCodePoint(0u));

    SayBool("utf16-equals", "abc".ToUtf16().Equals("abc".ToUtf16()));
    SayBool("utf16-differs", "abc".ToUtf16().Equals("abd".ToUtf16()));

    var raw = "ab".ToUtf16().ToBytes();
    SayNumber("utf16-bytes", (long)raw.Length);
    SayNumber("utf16-byte-0", (long)raw[0]);
    SayNumber("utf16-byte-1", (long)raw[1]);

    // ---------------------------------------------------------------- ASCII
    SayBool("digit", Ascii.IsDigit((byte)'7'));
    SayBool("digit-no", Ascii.IsDigit((byte)'x'));
    SayBool("letter", Ascii.IsLetter((byte)'x'));
    SayBool("hex", Ascii.IsHexDigit((byte)'f'));
    SayBool("space", Ascii.IsWhiteSpace((byte)' '));
    SayBool("control", Ascii.IsControl((byte)10));
    SayNumber("upper", (long)Ascii.ToUpper((byte)'a'));
    SayNumber("lower", (long)Ascii.ToLower((byte)'A'));
    SayNumber("hex-value", (long)Ascii.HexValue((byte)'e'));
    SayNumber("hex-value-no", (long)Ascii.HexValue((byte)'z'));
    SayNumber("hex-digit", (long)Ascii.HexDigit(11));
    SayNumber("hex-digit-upper", (long)Ascii.HexDigitUpper(11));

    return 0;
}
