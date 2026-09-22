// SPDX-License-Identifier: 0BSD
//
// One stream opened for both, turned from reading to writing and back. C
// requires a seek between the two directions on one FILE*, and without it the
// write went nowhere and reported success.
module ReadThenWrite;

import Standard.Console;
import Standard.Env;
import Standard.File;
import Standard.IO;
import Standard.Path;

String Scratch()
{
    var temp = Env.GetOr("TEMP", Env.GetOr("TMPDIR", "/tmp"));
    return Path.Join(temp, "stainless-files-read-then-write.txt");
}

int Main()
{
    var path = Scratch();
    File.WriteAllText(path, "ABCDEFGH");

    var opened = FileStream.Open(path, FileMode.Open, FileAccess.ReadWrite);
    if (!opened.Ok)
    {
        Console.WriteLine("open failed");
        return 1;
    }

    var stream = opened.Value;
    var two = new byte[2];
    Console.WriteLine($"read {stream.Read(two, 0u, 2u)}");

    var xy = new byte[2];
    xy[0u] = 120;
    xy[1u] = 121;
    nuint written = stream.Write(xy, 0u, 2u);
    Console.WriteLine($"wrote {written}, error {IO.Describe(stream.Error)}");

    // And back to reading, which needs the same seek.
    Console.WriteLine($"read {stream.Read(two, 0u, 2u)} {Text.FromBytes(&two[0u], 2u)}");
    stream.Close();

    var after = File.ReadAllText(path);
    Console.WriteLine($"file {after.GetValueOrDefault("?")}");

    File.Delete(path);
    return 0;
}
