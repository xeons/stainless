// SPDX-License-Identifier: 0BSD
//
// What the encodings do with input that is not what it claims to be.
//
// A lossy UTF-8 decode refuses what the strict one refuses, one U+FFFD per
// byte: an overlong form is how "/" and "." get past a filter that checked the
// bytes. An encode sizes its output by the same walk it fills it with, so a
// `String` of unvalidated bytes cannot overrun or leave zeros behind.
module TextEncodingMalformed;

import Standard.Console;
import Standard.Text;
import Standard.Encoding;

String Bytes(byte[] data) => Text.FromBytes(&data[0], data.Length);

void ShowScalars(String label, String text)
{
    var built = new StringBuilder();
    built.Append(label);

    for (nuint at = 0; at < text.ByteLength(); at = text.NextCodePoint(at))
    {
        built.Append(" ");
        built.AppendInteger((long)(uint)text.CodePointAt(at));
    }
    Console.WriteLine(built.ToText());
}

void ShowBytes(String label, byte[] data)
{
    var built = new StringBuilder();
    built.Append(label);
    built.Append(" [");
    built.AppendInteger((long)data.Length);
    built.Append("]");

    for (nuint i = 0; i < data.Length; i++)
    {
        built.Append(" ");
        built.AppendInteger((long)data[i]);
    }
    Console.WriteLine(built.ToText());
}

int Main()
{
    var utf8 = Encoding.Utf8();
    ShowScalars("utf8-overlong-slash", utf8.GetString([0xC0, 0xAF]));
    ShowScalars("utf8-overlong-dot", utf8.GetString([0xE0, 0x80, 0xAE]));
    ShowScalars("utf8-overlong-nul", utf8.GetString([0xC0, 0x80]));
    ShowScalars("utf8-overlong-4", utf8.GetString([0xF0, 0x80, 0x80, 0xAF]));
    ShowScalars("utf8-surrogate", utf8.GetString([0xED, 0xA0, 0x80, 0x41]));
    ShowScalars("utf8-past-max", utf8.GetString([0xF4, 0x90, 0x80, 0x80]));
    ShowScalars("utf8-edges", utf8.GetString([0xC2, 0x80, 0xED, 0x9F, 0xBF, 0xF4, 0x8F, 0xBF, 0xBF]));

    var cp1252 = Encoding.Windows1252();
    Console.WriteLine("cp1252-can-fffd " + Text.FromBool(cp1252.CanRepresent((char32)0xFFFD)));
    ShowBytes("cp1252-fffd", cp1252.GetBytes(Bytes([0x41, 0xEF, 0xBF, 0xBD])));
    ShowScalars("cp1252-81", cp1252.GetString([0x81]));

    var loose = Bytes([0x41, 0x80]);
    ShowBytes("latin1-loose", Encoding.Latin1().GetBytes(loose));
    Console.WriteLine("latin1-loose-count "
        + Text.FromInteger((long)Encoding.Latin1().GetByteCount(loose)));
    ShowBytes("utf32-loose", Encoding.Utf32().GetBytes(loose));
    Console.WriteLine("utf32-loose-count "
        + Text.FromInteger((long)Encoding.Utf32().GetByteCount(loose)));
    ShowBytes("utf32-cut", Encoding.Utf32().GetBytes(Bytes([0xC3, 0x41, 0xE2])));

    // A trailing part of a unit is malformed, like any other.
    ShowScalars("utf32-tail", Encoding.Utf32().GetString([0x41, 0x00, 0x00, 0x00, 0x42]));
    return 0;
}
