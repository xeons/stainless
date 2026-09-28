// SPDX-License-Identifier: 0BSD
module CompressionDeflate;

import Standard.Console;
import Standard.Convert;
import Standard.IO;
import Standard.IO.Compression;

// The checksums are published values: CRC-32's check value, Wikipedia's
// Adler-32 example, and zlib's answers for the two long inputs. The
// hand-built streams were written bit by bit and checked against zlib, which
// accepts the first two and refuses the rest for the same reasons.

byte[] Hex(String text) => Convert.FromHexString(text).GetValueOrDefault(new byte[0]);

void Check(String label, bool passed)
{
    Console.WriteLine(passed ? label + " ok" : label + " WRONG");
}

void CheckText(String label, String actual, String expected)
{
    if (actual == expected)
    {
        Console.WriteLine(label + " ok");
        return;
    }
    Console.WriteLine(label + " WRONG");
    Console.WriteLine("  got      " + actual);
    Console.WriteLine("  expected " + expected);
}

String DescribeFailure(Result<byte[], CompressionError> result)
{
    if (result.Ok)
        return "accepted " + Convert.ToHexString(result.Value);
    return $"refused {(int)result.Error}";
}

void CheckRefused(String label, Result<byte[], CompressionError> result, CompressionError why)
{
    CheckText(label, DescribeFailure(result), $"refused {(int)why}");
}

String ZeroBytes(nuint count)
{
    String text = "";
    for (nuint i = 0; i < count; i++)
        text = text + "00";
    return text;
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

byte[] Filled(nuint size, byte value)
{
    var data = new byte[size];
    for (nuint i = 0; i < size; i++)
        data[i] = value;
    return data;
}

// A linear congruential generator's top bytes: no pattern deflate can use.
byte[] Noise(nuint size)
{
    var data = new byte[size];
    uint state = 1;
    for (nuint i = 0; i < size; i++)
    {
        state = state * 1664525u + 1013904223u;
        data[i] = (byte)(state >> 24);
    }
    return data;
}

// Runs of noise, of one byte, of a small alphabet, and of repeats from a
// kilobyte back, a megabyte of them: something like a real file.
byte[] Mixed(nuint size)
{
    var data = new byte[size];
    uint state = 12345;
    nuint at = 0;
    while (at < size)
    {
        state = state * 1103515245u + 12345u;
        uint kind = (state >> 16) % 4u;
        nuint run = (nuint)((state >> 8) % 200u) + 1;
        for (nuint i = 0; i < run && at < size; i++)
        {
            state = state * 1103515245u + 12345u;
            switch (kind)
            {
                case 0u: data[at] = (byte)(state >> 24); break;
                case 1u: data[at] = (byte)'a'; break;
                case 2u: data[at] = (byte)(97u + (state >> 24) % 6u); break;
                default: data[at] = at >= 1000u ? data[at - 1000] : (byte)'x'; break;
            }
            at++;
        }
    }
    return data;
}

void Checksums()
{
    CheckText("crc32-check", $"{Crc32.Compute("123456789"u8):x8}", "cbf43926");
    CheckText("adler32-wikipedia", $"{Adler32.Compute("Wikipedia"u8):x8}", "11e60398");
    CheckText("crc32-empty", $"{Crc32.Compute(new byte[0]):x8}", "00000000");
    CheckText("adler32-empty", $"{Adler32.Compute(new byte[0]):x8}", "00000001");

    // Long enough that Adler-32's sums wrap many times between reductions.
    byte[] ones = Filled(1000000, 0xFF);
    CheckText("crc32-long", $"{Crc32.Compute(ones):x8}", "13fbda0d");
    CheckText("adler32-long", $"{Adler32.Compute(ones):x8}", "3843e1be");

    byte[] noise = Noise(200000);
    var crc = new Crc32();
    var adler = new Adler32();
    crc.Append(noise[0:1]);
    crc.Append(noise[1:77777]);
    crc.Append(noise[77777:]);
    adler.Append(noise[0:5552]);
    adler.Append(noise[5552:5553]);
    adler.Append(noise[5553:]);
    CheckText("crc32-pieces", $"{crc.Value:x8}", "b4a0335b");
    CheckText("adler32-pieces", $"{adler.Value:x8}", "cf540271");

    crc.Reset();
    crc.Append("123456789"u8);
    CheckText("crc32-reset", $"{crc.Value:x8}", "cbf43926");
}

void HandBuilt()
{
    var stored = Compression.DecompressDeflate(Hex("010500faff68656c6c6f"));
    CheckText("inflate-stored", DescribeFailure(stored), "accepted 68656c6c6f");

    var fixedBlock = Compression.DecompressDeflate(Hex("4b4c4a862300"));
    CheckText("inflate-fixed", DescribeFailure(fixedBlock),
              "accepted 616263616263616263616263");

    // Four two-bit literal codes, and one distance code of one bit, which is
    // incomplete and allowed: "aba", then three more at distance one. Every
    // length is sent as itself, four bits each, hence the zeros.
    String header = "0de00190244992244902" + ZeroBytes(48);
    var dynamicBlock =
        Compression.DecompressDeflate(Hex(header + "11" + ZeroBytes(78) + "1021b200"));
    CheckText("inflate-dynamic", DescribeFailure(dynamicBlock),
              "accepted 616261616161");

    CheckRefused("refuse-block-type", Compression.DecompressDeflate(Hex("07")),
                 CompressionError.InvalidBlockType);
    CheckRefused("refuse-stored-length", Compression.DecompressDeflate(Hex("0105000000")),
                 CompressionError.StoredLengthMismatch);
    CheckRefused("refuse-truncated-stored", Compression.DecompressDeflate(Hex("010500faff6865")),
                 CompressionError.Truncated);
    CheckRefused("refuse-truncated-fixed", Compression.DecompressDeflate(Hex("4b4c4a86")),
                 CompressionError.Truncated);
    CheckRefused("refuse-distance", Compression.DecompressDeflate(Hex("4b044200")),
                 CompressionError.InvalidDistance);
    CheckRefused("refuse-length-286", Compression.DecompressDeflate(Hex("4b1c0300")),
                 CompressionError.InvalidCode);
    CheckRefused("refuse-distance-30", Compression.DecompressDeflate(Hex("4b043e00")),
                 CompressionError.InvalidCode);
    CheckRefused("refuse-repeat-first", Compression.DecompressDeflate(Hex("05e00304000000000004")),
                 CompressionError.InvalidCodeLengths);

    // The same header as the last block but for its final bit and the
    // lengths of 'a', 'b' and end-of-block.
    header = "05e00190244992244902" + ZeroBytes(48);
    CheckRefused("refuse-oversubscribed",
                 Compression.DecompressDeflate(Hex(header + "22" + ZeroBytes(78) + "2002")),
                 CompressionError.InvalidCodeLengths);
    CheckRefused("refuse-incomplete",
                 Compression.DecompressDeflate(Hex(header + "11" + ZeroBytes(78) + "1002")),
                 CompressionError.InvalidCodeLengths);
    CheckRefused("refuse-no-end-of-block",
                 Compression.DecompressDeflate(Hex(header + "22" + ZeroBytes(79) + "02")),
                 CompressionError.InvalidCodeLengths);
}

void RoundTrips()
{
    CompressionLevel[] levels = [CompressionLevel.NoCompression, CompressionLevel.Fastest,
                                 CompressionLevel.Optimal, CompressionLevel.SmallestSize];
    String[] levelNames = ["none", "fastest", "optimal", "smallest"];

    byte[][] inputs = [new byte[0], Filled(1, 42), Filled(300000, 7), Noise(200000),
                       Mixed(1048576)];
    String[] inputNames = ["empty", "one-byte", "repetitive", "noise", "mixed"];

    for (nuint i = 0; i < inputs.Length; i++)
    {
        byte[] data = inputs[i];
        for (nuint l = 0; l < levels.Length; l++)
        {
            String label = "round-trip-" + inputNames[i] + "-" + levelNames[l];
            byte[] raw = Compression.CompressDeflate(data, levels[l]);
            byte[] gzip = Compression.CompressGZip(data, levels[l]);
            byte[] zlib = Compression.CompressZLib(data, levels[l]);

            var fromRaw = Compression.DecompressDeflate(raw);
            var fromGZip = Compression.DecompressGZip(gzip);
            var fromZLib = Compression.DecompressZLib(zlib);
            bool same = fromRaw.Ok && Same(fromRaw.Value, data) &&
                        fromGZip.Ok && Same(fromGZip.Value, data) &&
                        fromZLib.Ok && Same(fromZLib.Value, data);

            // Incompressible data falls back to stored blocks, five bytes of
            // overhead for each; Huffman coding it would cost far more.
            nuint ceiling = data.Length + data.Length / 1024 + 16;
            bool bounded = raw.Length <= ceiling && gzip.Length == raw.Length + 18 &&
                           zlib.Length == raw.Length + 6;
            Check(label, same && bounded);
        }
    }

    Check("repetitive-compresses",
          Compression.CompressDeflate(inputs[2], CompressionLevel.Fastest).Length < 3000u);
    Check("mixed-compresses",
          Compression.CompressDeflate(inputs[4], CompressionLevel.Optimal).Length < 450000u);
    Check("smallest-is-smallest",
          Compression.CompressDeflate(inputs[4], CompressionLevel.SmallestSize).Length <=
          Compression.CompressDeflate(inputs[4], CompressionLevel.Optimal).Length);
}

// Written in uneven pieces with flushes between, read back in uneven pieces.
void Streams()
{
    byte[] data = Mixed(300000);
    var packed = new MemoryStream();
    var writer = new GZipStream(packed, CompressionLevel.Optimal, true);
    nuint at = 0;
    nuint piece = 1;
    while (at < data.Length)
    {
        nuint taking = piece < data.Length - at ? piece : data.Length - at;
        writer.Write(data, at, taking);
        at += taking;
        piece = piece * 3 + 1;
        if (piece > 70000u)
        {
            writer.Flush();
            piece = 5;
        }
    }
    Check("stream-can-write", writer.CanWrite && !writer.CanRead && !writer.CanSeek);
    writer.Close();
    Check("stream-closed", !writer.CanWrite && writer.Write(data, 0, 1) == 0 &&
          writer.Error == IOError.Closed);
    Check("stream-left-open", packed.Length > 0);

    packed.Seek(0, SeekOrigin.Start);
    var reader = new GZipStream(packed, CompressionMode.Decompress);
    Check("stream-can-read", reader.CanRead && !reader.CanWrite);
    var output = new byte[data.Length];
    nuint length = 0;
    nuint want = 1;
    for (;;)
    {
        nuint asking = want < output.Length - length ? want : output.Length - length;
        nuint got = reader.Read(output, length, asking);
        if (got == 0)
            break;
        length += got;
        want = want * 2 + 1;
        if (want > 100000u)
            want = 3;
    }
    Check("stream-round-trip", length == data.Length && Same(output, data) &&
          reader.Error == IOError.None);
    Check("stream-at-end", reader.Read(output, 0, 10) == 0 && reader.Error == IOError.None);
    Check("stream-wrong-way", reader.Write(data, 0, 1) == 0 && reader.Error == IOError.Invalid);

    var deflated = new MemoryStream();
    var deflate = new DeflateStream(deflated, CompressionMode.Compress, true);
    deflate.Write(data, 0, data.Length);
    deflate.Close();
    deflated.Seek(0, SeekOrigin.Start);
    var inflated = IO.ReadToEnd(new DeflateStream(deflated, CompressionMode.Decompress));
    Check("stream-deflate", inflated.Ok && Same(inflated.Value, data));

    var zlibbed = new MemoryStream();
    var zlib = new ZLibStream(zlibbed, CompressionLevel.SmallestSize, true);
    zlib.Write(data, 0, data.Length);
    zlib.Close();
    zlibbed.Seek(0, SeekOrigin.Start);
    var unzlibbed = IO.ReadToEnd(new ZLibStream(zlibbed, CompressionMode.Decompress));
    Check("stream-zlib", unzlibbed.Ok && Same(unzlibbed.Value, data));

    // No bytes at all is an empty stream, as .NET reads one.
    var nothing = IO.ReadToEnd(new GZipStream(new MemoryStream(), CompressionMode.Decompress));
    Check("stream-empty-source", nothing.Ok && nothing.Value.Length == 0);
}

void Corruption()
{
    byte[] data = Mixed(100000);

    byte[] gzip = Compression.CompressGZip(data);
    gzip[gzip.Length - 8] ^= 1;
    CheckRefused("refuse-gzip-crc", Compression.DecompressGZip(gzip),
                 CompressionError.ChecksumMismatch);
    gzip[gzip.Length - 8] ^= 1;
    gzip[gzip.Length - 1] ^= 1;
    CheckRefused("refuse-gzip-length", Compression.DecompressGZip(gzip),
                 CompressionError.LengthMismatch);
    gzip[gzip.Length - 1] ^= 1;
    gzip[0] = 0x1E;
    CheckRefused("refuse-gzip-magic", Compression.DecompressGZip(gzip),
                 CompressionError.InvalidHeader);
    gzip[0] = 0x1F;
    CheckRefused("refuse-gzip-truncated", Compression.DecompressGZip(gzip[0:gzip.Length - 3]),
                 CompressionError.Truncated);
    Check("gzip-restored", Compression.DecompressGZip(gzip).Ok);

    byte[] zlib = Compression.CompressZLib(data);
    zlib[zlib.Length - 1] ^= 0x80;
    CheckRefused("refuse-zlib-checksum", Compression.DecompressZLib(zlib),
                 CompressionError.ChecksumMismatch);
    zlib[zlib.Length - 1] ^= 0x80;
    CheckRefused("refuse-zlib-dictionary", Compression.DecompressZLib(Hex("78bb0000000000")),
                 CompressionError.DictionaryRequired);
    CheckRefused("refuse-zlib-header", Compression.DecompressZLib(Hex("789d0300000001")),
                 CompressionError.InvalidHeader);
    Check("zlib-restored", Compression.DecompressZLib(zlib).Ok);

    // Through a stream: the rounded error, and the exact one beside it.
    zlib[zlib.Length - 2] ^= 0x10;
    var reader = new ZLibStream(new MemoryStream(zlib), CompressionMode.Decompress);
    var all = IO.ReadToEnd(reader);
    Check("stream-invalid-data", !all.Ok && all.Error == IOError.InvalidData &&
          reader.CompressionErrorCode == CompressionError.ChecksumMismatch);
    Check("stream-stays-failed", reader.Read(new byte[10], 0, 10) == 0 &&
          reader.Error == IOError.InvalidData);

    // Every truncation of a small stream is refused, and none of them is
    // anything but truncation.
    byte[] small = Compression.CompressZLib(data[0:5000]);
    bool allTruncated = true;
    for (nuint cut = 1; cut < small.Length; cut++)
    {
        var result = Compression.DecompressZLib(small[0:cut]);
        if (result.Ok || result.Error != CompressionError.Truncated)
            allTruncated = false;
    }
    Check("refuse-every-truncation", allTruncated);

    // Every single-byte change is refused, or changes nothing the data
    // depends on — the padding after the last block. None stops the program
    // or hangs it.
    bool noneWrong = true;
    for (nuint at = 0; at < small.Length; at++)
    {
        byte[] broken = small[0:].ToArray();
        broken[at] ^= (byte)(at * 7 + 1);
        var result = Compression.DecompressZLib(broken);
        if (result.Ok && !Same(result.Value, data[0:5000].ToArray()))
            noneWrong = false;
    }
    Check("refuse-every-corruption", noneWrong);
}

void Main()
{
    Checksums();
    HandBuilt();
    RoundTrips();
    Streams();
    Corruption();
}
