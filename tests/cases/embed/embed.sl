// `[Embed]`: a file's bytes as an immortal `byte[]` the linker places, named
// by the static it is written on.
//
// table.bin holds the bytes a text-mode reader would get wrong — a NUL, 0xFF,
// a CRLF, a lone LF and CR, and bytes past 0x7F — so printing every one of
// them proves the file arrived as it is on disk. It sits in a subdirectory,
// which is found relative to this file rather than to wherever the build was
// started. x86-embed builds this same file for 32-bit.
module EmbedCase;

import Standard.Console;

/// What a pointer to the stub is called as: no arguments, an int in eax.
public delegate int Answer();

/// A module-level static takes the attribute exactly as a type's field does,
/// and the two share one object when they name the same file the same way.
[Embed("data/table.bin")]
static readonly byte[] Shared;

public static class Blobs
{
    /// Read-only, in the target's read-only data section.
    [Embed("data/table.bin")]
    public static readonly byte[] Table;

    /// The same file, section and access: the same object.
    [Embed("data/table.bin")]
    public static readonly byte[] Again;

    /// Writable, so a different object from `Table` although the file is the same.
    [Embed("data/table.bin", Access = "rw")]
    public static byte[] Scratch;

    /// `mov eax, 42; ret`, which means the same thing on x86 and on x86-64.
    [Embed("stub.bin", Section = ".stub", Access = "rx")]
    public static readonly byte[] Stub;

    /// The path, the section and the access written positionally, in the order
    /// the attribute declares its fields — the same object as `Scratch`.
    [Embed("data/table.bin", ".data", "rw")]
    public static byte[] Positional;

    [Embed("data/empty.bin")]
    public static readonly byte[] Empty;
}

int Main()
{
    byte[] table = Blobs.Table;
    Console.WriteLine($"length {table.Length}");

    var bytes = new StringBuilder();
    uint sum = 0u;
    for (nuint i = 0u; i < table.Length; i++)
    {
        bytes.Append($" {table[i]}");
        sum = sum * 31u + (uint)table[i];
    }
    Console.WriteLine($"bytes{bytes.ToText()}");
    Console.WriteLine($"checksum {sum}");

    // One object however many times it is named, and wherever: a module-level
    // static and a class's field get the same address.
    Console.WriteLine($"same object {(void*)Blobs.Again == (void*)table}");
    Console.WriteLine($"same from a module static {(void*)Shared == (void*)table}");
    Console.WriteLine($"writable is another {(void*)Blobs.Scratch != (void*)table}");
    Console.WriteLine($"positional is the same {(void*)Blobs.Positional == (void*)Blobs.Scratch}");

    // The first element is the first byte of the file: the header is in front
    // of it, where it is in any array.
    byte* first = &table[0];
    Console.WriteLine($"through a pointer {first[0]} {first[1]}");

    // Written and read back, through the static and through the second static
    // holding the same writable object.
    Blobs.Scratch[0] = (byte)200;
    Blobs.Scratch[12] = (byte)201;
    Console.WriteLine($"written {Blobs.Positional[0]} {Blobs.Positional[12]}, " +
                      $"read-only still {table[0]} {table[12]}");

    // Counted like any reference, and immortal, so none of it reaches the
    // allocator: copied into a local, dropped, and still there.
    {
        byte[] held = Blobs.Stub;
        Console.WriteLine($"stub length {held.Length}");
    }

    var answer = (Answer)(void*)&Blobs.Stub[0];
    Console.WriteLine($"called {answer()}");

    Console.WriteLine($"empty {Blobs.Empty.Length}");
    return 0;
}
