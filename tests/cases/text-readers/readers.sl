// SPDX-License-Identifier: 0BSD
//
// `TextReader` and `TextWriter`, and the four that are one.
//
// What is pinned is the line handling, because that is where a reader is
// usually wrong: a CRLF is one terminator and not a line ending plus a
// character, a blank line is a line, and text that stops without a terminator
// still ends with a line.
//
// The second half is the buffering. `StreamReader` reads 1024 bytes at a time
// and decodes each buffer through an `IDecoder` that keeps whatever character
// the buffer ended in the middle of, so what is checked there is a character
// placed across that boundary on purpose, in every encoding that can cut one.
module TextReaders;

import Standard.Console;
import Standard.Text;
import Standard.IO;
import Standard.Encoding;

void Say(String what, String value)
{
    Console.WriteLine(what + " [" + value + "]");
}

void Count(String what, nuint value)
{
    Console.WriteLine(what + " " + Text.FromInteger(value));
}

int Main()
{
    // ---------------------------------------------------------- the lines

    var mixed = new StringReader("alpha\nbeta\r\ngamma\n");
    Say("first", mixed.ReadLine() ?? "<null>");
    Say("crlf", mixed.ReadLine() ?? "<null>");
    Say("last", mixed.ReadLine() ?? "<null>");
    Say("past", mixed.ReadLine() ?? "<null>");

    // Text that stops without a terminator still ends with a line.
    Count("ragged", new StringReader("one\ntwo").ReadLines().Length);

    // A blank line is a line, at the start and in the middle.
    var blanks = new StringReader("\n\na\n").ReadLines();
    Count("blanks", blanks.Length);
    Say("blank0", blanks[0u]);
    Say("blank2", blanks[2u]);

    // Nothing at all is no lines rather than one empty one.
    Count("empty", new StringReader("").ReadLines().Length);

    // What is left after a line, terminators and all.
    var partly = new StringReader("head\ntail rest");
    partly.ReadLine();
    Say("rest", partly.ReadToEnd());
    Say("restagain", partly.ReadToEnd());

    // --------------------------------------------------------- the writer

    var written = new StringWriter();
    written.Write("no newline");
    written.WriteLine(" then one");
    written.NewLine = "\r\n";
    written.WriteLine("crlf");
    Count("bytes", written.ToText().ByteLength());
    Count("lines", written.ToText().SplitLines().Length);

    // --------------------------------------------------------- the stream

    var memory = new MemoryStream();
    var writer = new StreamWriter(memory);
    writer.WriteLine("first");
    writer.WriteLine("second");
    writer.Write("third");
    writer.Flush();
    Count("streambytes", (nuint)memory.Length);

    memory.Seek(0, SeekOrigin.Start);
    var read = new StreamReader(memory).ReadLines();
    Count("streamlines", read.Length);
    Say("stream0", read[0u]);
    Say("stream2", read[2u]);

    // An encoding whose bytes a newline scan would cut a character in half in.
    var wide = new MemoryStream();
    var wideWriter = new StreamWriter(wide, Utf16());
    wideWriter.WriteLine("世界");
    wideWriter.WriteLine("second");
    wideWriter.Flush();

    wide.Seek(0, SeekOrigin.Start);
    var wideLines = new StreamReader(wide, Utf16()).ReadLines();
    Count("utf16lines", wideLines.Length);
    Say("utf16first", wideLines[0u]);
    Say("utf16second", wideLines[1u]);

    // ------------------------------------------------------ across a buffer

    // Three bytes, at each offset the boundary can fall inside them.
    Intact("utf8/1021", Utf8(), 1021u, "世");
    Intact("utf8/1022", Utf8(), 1022u, "世");
    Intact("utf8/1023", Utf8(), 1023u, "世");

    // Four bytes: a scalar outside the basic plane.
    Intact("utf8/astral", Utf8(), 1022u, "𝄞");

    // UTF-16 cuts at an odd byte, and between the halves of a surrogate pair.
    Intact("utf16/plain", Utf16(), 511u, "世");
    Intact("utf16/pair", Utf16(), 510u, "𝄞");
    Intact("utf16be/pair", Utf16BigEndian(), 511u, "𝄞");

    // UTF-32 puts four bytes on every scalar, so every boundary cuts one.
    Intact("utf32", Utf32(), 255u, "世");

    // And a line longer than the buffer is still one line.
    var spanning = new MemoryStream();
    var spanningWriter = new StreamWriter(spanning);
    spanningWriter.WriteLine(Padded(1023u, "世"));
    spanningWriter.WriteLine("after");
    spanningWriter.Flush();

    spanning.Seek(0, SeekOrigin.Start);
    var spanningLines = new StreamReader(spanning).ReadLines();
    Count("longlines", spanningLines.Length);
    Count("longfirst", spanningLines[0u].ByteLength());
    Say("longsecond", spanningLines[1u]);

    return 0;
}

/// `pad` ASCII bytes, then `middle`, then a marker -- so that `middle` lands
/// across the reader's buffer boundary rather than safely inside a buffer.
String Padded(nuint pad, String middle)
{
    var built = new StringBuilder();
    for (nuint i = 0u; i < pad; i++)
        built.AppendByte(0x61);
    built.Append(middle);
    built.Append("|end");
    return built.ToText();
}

/// Writes that text in an encoding, reads it back, and says whether the
/// character that straddled the boundary came through whole.
void Intact(String what, IEncoding encoding, nuint pad, String middle)
{
    String wanted = Padded(pad, middle);

    var stream = new MemoryStream();
    var writer = new StreamWriter(stream, encoding);
    writer.Write(wanted);
    writer.Flush();

    stream.Seek(0, SeekOrigin.Start);
    String got = new StreamReader(stream, encoding).ReadToEnd();

    Console.WriteLine(what + " " + (got == wanted ? "intact" : "MANGLED"));
}
