// SPDX-License-Identifier: 0BSD
//
// Reading text: a UTF-8 byte order mark is a marker and not part of the first
// line, and a stream that fails is not a stream that ended.
module TextReading;

import Standard.Collections;
import Standard.Console;
import Standard.Env;
import Standard.File;
import Standard.IO;
import Standard.Path;

/// A stream whose first read fails.
class BrokenStream : IStream
{
    IOError _error = IOError.None;

    public bool CanRead => true;
    public bool CanWrite => false;
    public bool CanSeek => false;

    public nuint Read(byte[] buffer, nuint offset, nuint count)
    {
        _error = IOError.Unknown;
        return 0u;
    }

    public nuint Write(byte[] buffer, nuint offset, nuint count) => 0u;
    public long Position => -1;
    public long Length => -1;
    public bool Seek(long offset, SeekOrigin origin) => false;
    public void Flush() { }
    public void Close() { }
    public IOError Error => _error;
}

byte[] MarkedText()
{
    // EF BB BF, then "hi\n\xEF\xBB\xBFx": the second mark is text.
    byte[] bytes = new byte[10];
    bytes[0u] = 0xEF;
    bytes[1u] = 0xBB;
    bytes[2u] = 0xBF;
    bytes[3u] = 104;
    bytes[4u] = 105;
    bytes[5u] = 10;
    bytes[6u] = 0xEF;
    bytes[7u] = 0xBB;
    bytes[8u] = 0xBF;
    bytes[9u] = 120;
    return bytes;
}

int Main()
{
    var temp = Env.GetEnvironmentVariableOrDefault("TEMP", Env.GetEnvironmentVariableOrDefault("TMPDIR", "/tmp"));
    var path = Path.Join(temp, "stainless-files-text-reading.txt");
    File.WriteAllBytes(path, MarkedText());

    var text = File.ReadAllText(path);
    Console.WriteLine($"all text: {text.GetValueOrDefault("?").ByteLength()} bytes, starts hi {text.GetValueOrDefault("?").StartsWith("hi")}");

    var lines = File.ReadAllLines(path);
    if (lines.Ok)
        Console.WriteLine($"first line is hi: {lines.Value[0u] == "hi"}, second {lines.Value[1u].ByteLength()} bytes");

    Console.WriteLine($"bytes kept: {File.ReadAllBytes(path).GetValueOrDefault(new byte[0]).Length}");

    var reader = new StreamReader(new MemoryStream(MarkedText()));
    var first = reader.ReadLine();
    Console.WriteLine($"reader first line is hi: {first != null && (String)first == "hi"}");
    Console.WriteLine($"reader rest: {reader.ReadToEnd().ByteLength()} bytes");
    Console.WriteLine($"reader error: {IO.DescribeIOError(reader.Error)}");

    var broken = new StreamReader(new BrokenStream());
    Console.WriteLine($"broken line is null: {broken.ReadLine() == null}");
    Console.WriteLine($"broken error: {IO.DescribeIOError(broken.Error)}");

    File.Delete(path);
    return 0;
}
