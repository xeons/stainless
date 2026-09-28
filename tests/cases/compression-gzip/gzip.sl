// SPDX-License-Identifier: 0BSD
module CompressionGZip;

import Standard.Console;
import Standard.IO;
import Standard.IO.Compression;

// Streams made by other implementations, decompressed here. data/fixtures.py
// made every one of them on Linux: `gzip -9` and `gzip -1` of the text below,
// two `gzip -6` members of its halves one after the other, Python's zlib in
// both the zlib format and raw deflate, and a member with every optional
// header field and the header CRC set. The text is made here as it was made
// there, so nothing but the compressed forms is checked in.

[Embed("data/text9.gz")]
static readonly byte[] Text9;

[Embed("data/text1.gz")]
static readonly byte[] Text1;

[Embed("data/two.gz")]
static readonly byte[] TwoMembers;

[Embed("data/text.zlib")]
static readonly byte[] TextZLib;

[Embed("data/text.deflate")]
static readonly byte[] TextDeflate;

[Embed("data/fields.gz")]
static readonly byte[] Fields;

// About 70 KB of words from twenty, chosen by a linear congruential
// generator: more than the decoder's 64 KiB ring, so it wraps.
byte[] MakeText(nuint size)
{
    String[] words = ["the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog",
                      "stream", "window", "deflate", "huffman", "code", "length",
                      "distance", "block", "literal", "match", "inflate", "gzip"];
    var text = new MemoryStream();
    uint state = 12345;
    while (text.Length < (long)size)
    {
        state = state * 1103515245u + 12345u;
        text.WriteText(words[(state >> 16) % 20u]);
        text.WriteText(((state >> 8) & 15u) != 0u ? " " : "\n");
    }
    return text.ToArray();
}

bool Same(byte[] a, byte[] b)
{
    if (a.Length != b.Length)
        return false;
    for (nuint i = 0; i < a.Length; i++)
    {
        if (a[i] != b[i])
            return false;
    }
    return true;
}

void CheckDecoded(String label, Result<byte[], CompressionError> result, byte[] expected)
{
    if (!result.Ok)
    {
        Console.WriteLine($"{label} WRONG: refused {(int)result.Error}");
        return;
    }
    if (!Same(result.Value, expected))
    {
        Console.WriteLine($"{label} WRONG: {result.Value.Length} bytes, " +
                          $"expected {expected.Length}");
        return;
    }
    Console.WriteLine(label + " ok");
}

// The same through a stream, read in pieces of `piece`.
void CheckStream(String label, IStream stream, byte[] expected, nuint piece)
{
    var output = new MemoryStream();
    var buffer = new byte[piece];
    for (;;)
    {
        nuint got = stream.Read(buffer, 0, piece);
        if (got == 0)
            break;
        output.Write(buffer, 0, got);
    }

    bool passed = stream.Error == IOError.None && Same(output.ToArray(), expected);
    Console.WriteLine(passed ? label + " ok" : label + " WRONG");
}

void Main()
{
    byte[] text = MakeText(70000);

    CheckDecoded("gzip-9", Compression.DecompressGZip(Text9), text);
    CheckDecoded("gzip-1", Compression.DecompressGZip(Text1), text);
    CheckDecoded("gzip-two-members", Compression.DecompressGZip(TwoMembers), text);
    CheckDecoded("python-zlib", Compression.DecompressZLib(TextZLib), text);
    CheckDecoded("python-deflate", Compression.DecompressDeflate(TextDeflate), text);
    CheckDecoded("gzip-header-fields", Compression.DecompressGZip(Fields), text[0:1000].ToArray());

    var decompress = CompressionMode.Decompress;
    CheckStream("stream-gzip-9", new GZipStream(new MemoryStream(Text9), decompress), text, 7);
    CheckStream("stream-two-members", new GZipStream(new MemoryStream(TwoMembers), decompress),
                text, 4096);
    CheckStream("stream-zlib", new ZLibStream(new MemoryStream(TextZLib), decompress),
                text, 65536);
    CheckStream("stream-deflate", new DeflateStream(new MemoryStream(TextDeflate), decompress),
                text, 1000);

    // A header CRC that does not match is refused as a bad header.
    byte[] damaged = Fields[0:].ToArray();
    damaged[4] ^= 1;
    var refused = Compression.DecompressGZip(damaged);
    Console.WriteLine(!refused.Ok && refused.Error == CompressionError.InvalidHeader
                      ? "gzip-header-crc ok" : "gzip-header-crc WRONG");

    // Trailing bytes that do not start a member are ignored, as gzip does.
    byte[] trailing = [..Text9, 0, 0, 0, 0];
    CheckDecoded("gzip-trailing-zeros", Compression.DecompressGZip(trailing), text);

    // And a second member that starts and then breaks is not ignored.
    byte[] broken = [..Text9, 0x1F, 0x8B, 8];
    var cut = Compression.DecompressGZip(broken);
    Console.WriteLine(!cut.Ok && cut.Error == CompressionError.Truncated
                      ? "gzip-broken-member ok" : "gzip-broken-member WRONG");
}
