// SPDX-License-Identifier: 0BSD
//
// `TextReader` and `TextWriter`, and the four that are one.
//
// What is pinned is the line handling, because that is where a reader is
// usually wrong: a CRLF is one terminator and not a line ending plus a
// character, a blank line is a line, and text that stops without a terminator
// still ends with a line.
//
// The last case is the one that decided the design. `StreamReader` decodes the
// whole stream before splitting it, rather than scanning bytes for a newline,
// because in UTF-16 the byte 0x0A occurs inside ordinary characters -- so a
// byte-wise reader would cut "世" in half.
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

    return 0;
}
