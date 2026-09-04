// UTF-8 to UTF-16 and back, which is what a platform speaking wide text needs
// in both directions. Nothing here is Windows-specific: the transcoder is the
// runtime's own and is compiled everywhere.
module Utf16RoundTrip;

import Standard.Console;

extern "C" {
    void* malloc(nuint size);
    void  free(void* block);
}

void Round(String text) {
    var wide = text.ToUtf16();
    Console.WriteLine(Text.FromInteger(wide.UnitCount()) + " units  " + wide.ToText());
}

int Main() {
    // One, two, three and four byte scalars, the last of which is a surrogate
    // pair on the way out and has to be rejoined on the way back.
    Round("ascii");
    Round("héllo");
    Round("日本語");
    Round("🌍 earth");
    Round("");

    // The pointer-and-length form, which is what a wide API writes into a
    // caller's buffer rather than into an object.
    var wide = "mixed: é 日 🌍".ToUtf16();
    Console.WriteLine(Text.FromUtf16(wide.ToPointer(), wide.UnitCount()));
    Console.WriteLine(Text.FromNullTerminatedUtf16(wide.ToPointer()));

    // A prefix that cuts the buffer short, to show the length is honoured
    // rather than the terminator being found.
    Console.WriteLine("[" + Text.FromUtf16(wide.ToPointer(), 5u) + "]");

    // A lone high surrogate is not valid UTF-16 and must not produce invalid
    // UTF-8. It becomes U+FFFD, which is three bytes.
    char16* broken = (char16*)malloc(6u);
    broken[0] = 0x0041u;      // 'A'
    broken[1] = 0xD800u;      // a lead with no trail
    broken[2] = 0x0042u;      // 'B'
    var repaired = Text.FromUtf16(broken, 3u);
    Console.WriteLine(Text.FromInteger(repaired.ByteLength()) + " bytes from a lone surrogate");
    free((void*)broken);

    // A null pointer is an empty string rather than a crash, because a wide API
    // that failed leaves the caller holding one.
    Console.WriteLine("[" + Text.FromNullTerminatedUtf16(null) + "]");
    return 0;
}
