// char, char16 and char32: three code unit types, one scalar literal.
//
// A character literal is one Unicode scalar. Which type it becomes is decided
// by what can hold it in a single unit -- one UTF-8 byte, one UTF-16 unit, or
// one of anything -- and the three do not convert to each other on their own,
// because widening a unit re-encodes nothing and produces a unit that means
// something else. That rule is what err-code-units checks; this checks that
// everything the rule allows works, and that the values are right.
module CodeUnits;

import Standard.Console;
import Standard.Text;

/// The scalar behind each literal, as a number, so the value is checked and
/// not just the fact that it compiled.
void Show(String label, long scalar) {
    Console.WriteLine(label + " = " + Text.FromInteger(scalar));
}

public void Main() {
    // --- one scalar, three widths -------------------------------------
    char    ascii     = 'A';            // U+0041, one UTF-8 byte
    char16  accented  = 'é';            // U+00E9, two bytes but one UTF-16 unit
    char32  cjk       = '日';           // U+65E5, three bytes and still one unit
    char32  astral    = '😀';           // U+1F600, a surrogate pair in the source

    Show("ascii", (long)ascii);
    Show("accented", (long)accented);
    Show("cjk", (long)cjk);
    Show("astral", (long)astral);

    // --- escapes ------------------------------------------------------
    //
    // \u takes four hex digits and \U eight, which is the only way to write a
    // scalar above U+FFFF. \x is a byte and says nothing about Unicode.
    char16 escaped16 = '\u65E5';
    char32 escaped32 = '\U0001F600';
    char   tab       = '\t';

    Show("escaped16", (long)escaped16);
    Show("escaped32", (long)escaped32);
    Show("tab", (long)tab);

    // A character literal still initializes an ordinary integer constant,
    // which is what `const int Newline = '\n';` has always meant.
    const int Newline = '\n';
    Show("newline", (long)Newline);

    // --- sizes --------------------------------------------------------
    Console.WriteLine("sizes " + Text.FromInteger((long)sizeof(char)) +
                      " " + Text.FromInteger((long)sizeof(char16)) +
                      " " + Text.FromInteger((long)sizeof(char32)));

    // --- a cast is how the encodings meet -----------------------------
    //
    // Allowed, and says at the call site that a re-encoding was not what was
    // wanted: 'A' is the same number in all three.
    char16 fromNarrow = (char16)ascii;
    char   toNarrow   = (char)accented;     // truncates, and looks like it
    Show("fromNarrow", (long)fromNarrow);
    Show("toNarrow", (long)toNarrow);

    // --- against other integers they are integers ---------------------
    ushort asNumber = accented;
    char16 back     = asNumber;
    Show("asNumber", (long)asNumber);
    Show("back", (long)back);

    int sum = (int)ascii + 1;
    Show("sum", (long)sum);

    // --- arrays and pointers ------------------------------------------
    char16[4] buffer;
    buffer[0] = 'h';
    buffer[1] = 'é';
    buffer[2] = '!';
    buffer[3] = '\0';

    // The buffer is UTF-16, so the wide reader is the one that takes it, and
    // its parameter is char16* rather than a bare 16-bit pointer.
    Console.WriteLine("buffer: " + Text.FromNullTerminatedUtf16(&buffer[0]));

    // --- the round trip through Utf16String ---------------------------
    var wide = "héllo 日本".ToUtf16();
    char16* units = wide.ToPointer();
    Show("first unit", (long)units[0]);
    Show("second unit", (long)units[1]);
    Console.WriteLine("back: " + wide.ToText());
}
