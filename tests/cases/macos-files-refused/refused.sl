// SPDX-License-Identifier: 0BSD
//
// A write the system refuses, as files-full-disk asks of Linux through
// /dev/full. macOS has no /dev/full, so the refusal is made with a file size
// limit of one byte: every write past it fails with EFBIG, and with SIGXFSZ
// ignored that is an error rather than the end of the process. A small write
// only reaches the file when the buffer is flushed, which is at the close.
module MacFilesRefused;

import Standard.Collections;
import Standard.Console;
import Standard.File;
import Standard.IO;

struct Limit
{
    public ulong Current;
    public ulong Maximum;
}

extern "C"
{
    int getrlimit(int resource, Limit* limit);
    int setrlimit(int resource, Limit* limit);
    byte* signal(int number, byte* handler);
}

const int FileSizeLimit = 1;        // RLIMIT_FSIZE
const int FileSizeExceeded = 25;    // SIGXFSZ

void Say(String what, IOError error)
{
    Console.WriteLine($"{what}: {IO.DescribeIOError(error)}");
}

int Main()
{
    signal(FileSizeExceeded, (byte*)(nuint)1);    // SIG_IGN

    Limit limit;
    getrlimit(FileSizeLimit, &limit);
    limit.Current = 1u;
    setrlimit(FileSizeLimit, &limit);

    String path = "/tmp/stainless-files-refused.bin";

    Say("text", File.WriteAllText(path, "hi"));
    Say("append", File.AppendAllText(path, "hi"));

    var small = new byte[4];
    Say("bytes", File.WriteAllBytes(path, small));

    var lines = new List<String>();
    lines.Add("alpha");
    lines.Add("beta");
    Say("lines", File.WriteAllLines(path, lines));

    // Larger than any stdio buffer, so the write itself comes up short.
    var large = new byte[1048576];
    var opened = FileStream.Create(path);
    if (opened.Ok)
    {
        var stream = opened.Value;
        nuint written = stream.Write(large, 0u, large.Length);
        Console.WriteLine($"short: {written < large.Length}");
        Say("large", stream.Error);
        stream.Close();
    }

    File.Delete(path);
    return 0;
}
