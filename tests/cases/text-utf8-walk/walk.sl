// SPDX-License-Identifier: 0BSD
//
// Walking malformed UTF-8 with `CodePointAt` and `NextCodePoint`.
//
// A `String` made by `FromBytes` is not validated, so the walk is what decides
// what the bytes mean. Every step either reads one well-formed sequence or
// consumes one byte as U+FFFD, and `CodePointCount` counts the same steps.
// An overlong form, a surrogate and a value past U+10FFFF are malformed.
module TextUtf8Walk;

import Standard.Console;
import Standard.Text;

String Bytes(byte[] data) => Text.FromBytes(&data[0], data.Length);

void ShowWalk(String label, String text)
{
    var built = new StringBuilder();
    built.Append(label);
    nuint steps = 0;

    for (nuint at = 0; at < text.ByteLength(); at = text.NextCodePoint(at))
    {
        built.Append(" ");
        built.AppendInteger((long)(uint)text.CodePointAt(at));
        steps++;
    }

    built.Append(" | ");
    built.AppendInteger((long)steps);
    built.Append(" ");
    built.AppendInteger((long)text.CodePointCount());
    Console.WriteLine(built.ToText());
}

void ShowUnits(String label, Utf16String text)
{
    var built = new StringBuilder();
    built.Append(label);

    for (nuint at = 0; at < text.UnitCount(); at = text.NextCodePoint(at))
    {
        built.Append(" ");
        built.AppendInteger((long)(uint)text.CodePointAt(at));
    }
    Console.WriteLine(built.ToText());
}

int Main()
{
    ShowWalk("valid", "hé€");
    ShowWalk("astral", Bytes([0xF0, 0x9F, 0x98, 0x80, 0x41]));

    ShowWalk("bad-continuation", Bytes([0xC3, 0x41, 0x42]));
    ShowWalk("truncated", Bytes([0x78, 0xE2, 0x41]));
    ShowWalk("truncated-end", Bytes([0x78, 0xE2]));
    ShowWalk("stray", Bytes([0x41, 0x80, 0x42]));

    ShowWalk("surrogate", Bytes([0xED, 0xA0, 0x80, 0x41]));
    ShowWalk("past-max", Bytes([0xF4, 0x90, 0x80, 0x80]));
    ShowWalk("overlong-2", Bytes([0xC0, 0x80]));
    ShowWalk("overlong-3", Bytes([0xE0, 0x80, 0xAE]));
    ShowWalk("overlong-4", Bytes([0xF0, 0x80, 0x80, 0xAF]));
    ShowWalk("f5-lead", Bytes([0xF5, 0x80, 0x80, 0x80]));

    ShowWalk("edge-low", Bytes([0xC2, 0x80, 0xE0, 0xA0, 0x80, 0xF0, 0x90, 0x80, 0x80]));
    ShowWalk("edge-high", Bytes([0xED, 0x9F, 0xBF, 0xEE, 0x80, 0x80, 0xF4, 0x8F, 0xBF, 0xBF]));

    // A high surrogate followed by something that is not a low one is one
    // unit of U+FFFD, and the unit after it is its own character.
    var wide = "😀AB".ToUtf16();
    var units = wide.ToPointer();
    units[1] = (char16)0x41;
    ShowUnits("utf16-lone-high", wide);
    ShowUnits("utf16-pair", "😀A".ToUtf16());

    // ToUtf16 applies the same rules.
    ShowUnits("to-utf16-truncated", Bytes([0x78, 0xE2, 0x41]).ToUtf16());
    ShowUnits("to-utf16-surrogate", Bytes([0xED, 0xA0, 0x80, 0x41]).ToUtf16());
    ShowUnits("to-utf16-overlong", Bytes([0xC0, 0xAF]).ToUtf16());
    ShowUnits("to-utf16-past-max", Bytes([0xF4, 0x90, 0x80, 0x80]).ToUtf16());
    ShowUnits("to-utf16-astral", Bytes([0xF0, 0x9F, 0x98, 0x80]).ToUtf16());
    return 0;
}
