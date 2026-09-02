module Strings;

import Standard.Console;

extern "C" int printf(byte* format, ...);

int Main() {
    // A literal is a String. It lives in static storage and never allocates.
    String greeting = "Hello";
    String subject  = "Stainless";

    Console.WriteLine(greeting + ", " + subject + "!");

    Console.Write("byteLength      = ");
    Console.WriteLine(Text.FromInteger(greeting.ByteLength()));

    // UTF-8: bytes and code points differ.
    String accented = "n\u00e4ive caf\u00e9";
    Console.WriteLine(accented);
    printf("bytes=%llu codePoints=%llu\n",
           accented.ByteLength(), accented.CodePointCount());

    // Value equality, not reference equality.
    String built = "Stain" + "less";
    printf("built == subject : %d\n", built == subject);
    printf("built != greeting: %d\n", built != greeting);

    // Handing text to C is a copy-free pointer into the String.
    printf("via ToPointer     : %s\n", subject.ToPointer());

    Console.WriteLine(subject.Substring(0, 5));

    // UTF-16 for platform wide APIs, always an explicit conversion.
    var wide = accented.ToUtf16();
    printf("utf16 units       = %llu\n", wide.UnitCount());

    printf("empty             = %d\n", Text.FromBytes(null, 0).IsEmpty());
    return 0;
}
