// SPDX-License-Identifier: 0BSD
//
// `String`: what it is, and what it does.
//
// One string type, always UTF-8, immutable and reference counted. Its layout
// belongs to the runtime; everything below the first section is written in
// Stainless, in stdlib/Text.sl, as a second declaration of the same type.
module Strings;

import Standard.Console;
import Standard.Ascii;
import Standard.Convert;

extern "C" int printf(byte* format, ...);

void Show(String label, String value) {
    Console.WriteLine(label + " " + value);
}

void ShowNumber(String label, long value) {
    Console.WriteLine(label + " " + Text.FromInteger(value));
}

int Main() {
    // ------------------------------------------------------------ the basics

    // A literal is a String. It lives in static storage and never allocates.
    String greeting = "Hello";
    String subject  = "Stainless";

    Console.WriteLine(greeting + ", " + subject + "!");

    // Value equality, not reference equality.
    String built = "Stain" + "less";
    printf("built == subject : %d\n", built == subject);

    // Handing text to C is a copy-free pointer into the String.
    printf("via ToPointer    : %s\n", subject.ToPointer());

    // --------------------------------------------------------------- UTF-8

    // Bytes and characters are different questions, and both are answerable.
    String accented = "näive café";
    Console.WriteLine(accented);
    ShowNumber("bytes           ", (long)accented.ByteLength());
    ShowNumber("code points     ", (long)accented.CodePointCount());

    // Walking it properly: CodePointAt reads one character, NextCodePoint
    // steps over it. A `for` over bytes would land inside one.
    var scalars = new StringBuilder();
    for (nuint at = 0u; at < accented.ByteLength(); at = accented.NextCodePoint(at)) {
        scalars.AppendInteger((long)(uint)accented.CodePointAt(at));
        scalars.Append(" ");
    }
    Show("scalars         ", scalars.ToText().TrimEnd());

    // ------------------------------------------------------------ searching

    String line = "  name = Ada Lovelace  ";

    Show("trimmed         ", "[" + line.Trim() + "]");
    Show("key             ", line.Before("=").Trim());
    Show("value           ", line.After("=").Trim());
    ShowNumber("indexOf =       ", line.IndexOf("="));
    ShowNumber("not there       ", line.IndexOf("@"));      // Text.NotFound, which is -1

    printf("startsWith       : %d\n", line.Trim().StartsWith("name"));
    printf("contains         : %d\n", line.Contains("Ada"));

    // ------------------------------------------------------------- rebuilding

    Show("upper           ", subject.ToUpperAscii());
    Show("replaced        ", "one two one".Replace("one", "1"));
    Show("repeated        ", "ab".Repeat(3u));
    Show("padded          ", "[" + "7".PadLeft(4u) + "]");

    // Split and Join are inverses: joining what Split produced gives the
    // original back, empty parts and all.
    var fields = "alpha,beta,,delta".Split(',');
    ShowNumber("fields          ", (long)fields.Length);
    Show("joined          ", " | ".Join(fields));

    var lines = "one\ntwo\r\nthree\n".SplitLines();
    ShowNumber("lines           ", (long)lines.Length);   // three: the last \n adds none

    // ------------------------------------------------------------- comparing

    // Ordinal, by bytes -- which orders by code point as well, because UTF-8
    // was designed so that it would. It is not a linguistic ordering.
    ShowNumber("apple vs banana ", (long)"apple".CompareTo("banana"));
    printf("ignoring case    : %d\n", "HELLO".EqualsIgnoreCaseAscii("hello"));

    // --------------------------------------------------------- the neighbours

    // One byte's worth of question, when ASCII is the honest answer.
    printf("'7' is a digit   : %d\n", Ascii.IsDigit((byte)'7'));

    // And text that arrived as characters becoming something else.
    var port = Convert.ToInt("8080");
    switch (port) {
        case Ok ok:  ShowNumber("parsed          ", (long)ok.Value); break;
        case Fail:   Show("parsed          ", "not a number"); break;
    }

    Show("in hex          ", Convert.FromLong(255, 16u));
    Show("base64          ", Convert.ToBase64Text("Hello"));

    // ------------------------------------------------------------- UTF-16

    // For a wide platform API, and always an explicit conversion.
    var wide = accented.ToUtf16();
    ShowNumber("utf16 units     ", (long)wide.UnitCount());
    Show("round trip      ", wide.ToText());

    return 0;
}
