// SPDX-License-Identifier: 0BSD
//
// /dev/full accepts an open and refuses every write with ENOSPC. A small write
// only reaches it when the buffer is flushed, which is at the close, so this
// is what a full disk looks like to a program that writes a little.
module FullDisk;

import Standard.Collections;
import Standard.Console;
import Standard.File;
import Standard.IO;

void Say(String what, IOError error)
{
    Console.WriteLine($"{what}: {IO.DescribeIOError(error)}");
}

int Main()
{
    Say("text", File.WriteAllText("/dev/full", "hi"));
    Say("append", File.AppendAllText("/dev/full", "hi"));

    var small = new byte[4];
    Say("bytes", File.WriteAllBytes("/dev/full", small));

    var lines = new List<String>();
    lines.Add("alpha");
    lines.Add("beta");
    Say("lines", File.WriteAllLines("/dev/full", lines));

    // Larger than any stdio buffer, so the write itself comes up short.
    var large = new byte[1048576];
    var opened = FileStream.Create("/dev/full");
    if (opened.Ok)
    {
        var stream = opened.Value;
        nuint written = stream.Write(large, 0u, large.Length);
        Console.WriteLine($"short: {written < large.Length}");
        Say("large", stream.Error);
        stream.Close();
    }
    return 0;
}
