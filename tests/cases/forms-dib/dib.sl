// A DIB off the clipboard, read by the Win32 backend's own decoder.
//
// `biClrUsed` puts a colour table between the header and the pixels at any
// depth, including those whose pixels do not index it. A decoder that looks
// for a table only below nine bits reads the table as the first pixels.
module FormsDib;

import Standard.Console;
import Forms.Platform;
#if WINDOWS
import Forms.Platform.Win32;

void PutUInt(byte[] into, nuint at, uint value)
{
    into[at] = (byte)(value & 0xFFu);
    into[at + 1u] = (byte)((value >> 8) & 0xFFu);
    into[at + 2u] = (byte)((value >> 16) & 0xFFu);
    into[at + 3u] = (byte)((value >> 24) & 0xFFu);
}

/// Two 24-bit pixels, one row, behind a table of three colours.
byte[] TwoPixelsBehindATable()
{
    nuint header = 40u;
    nuint table = 3u * 4u;
    nuint row = 8u;
    var dib = new byte[header + table + row];
    PutUInt(dib, 0u, 40u);
    PutUInt(dib, 4u, 2u);
    PutUInt(dib, 8u, 1u);
    dib[12u] = (byte)1;
    dib[14u] = (byte)24;
    PutUInt(dib, 32u, 3u);

    for (nuint i = 0u; i < table; i++)
        dib[header + i] = (byte)0xEE;

    nuint at = header + table;
    dib[at] = (byte)10;
    dib[at + 1u] = (byte)20;
    dib[at + 2u] = (byte)30;
    dib[at + 3u] = (byte)40;
    dib[at + 4u] = (byte)50;
    dib[at + 5u] = (byte)60;
    return dib;
}

String Describe(ClipboardImage? found)
{
    if (found == null)
        return "nothing";
    var image = (ClipboardImage)found;
    var pixels = image.Pixels;
    var text = new StringBuilder();
    text.Append(Text.FromInteger((long)image.Width) + "x" + Text.FromInteger((long)image.Height));
    for (nuint i = 0u; i < pixels.Length; i++)
        text.Append(" " + Text.FromInteger((long)pixels[i]));
    return text.ToText();
}

int Main()
{
    Console.WriteLine("24 bits behind a table: "
        + Describe(Forms.Platform.Win32.DecodeDib(TwoPixelsBehindATable())));
    return 0;
}

#else

int Main() => 0;

#endif
