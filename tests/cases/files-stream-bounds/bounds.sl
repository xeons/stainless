// SPDX-License-Identifier: 0BSD
//
// A count so large that `offset + count` wraps past zero is still past the end
// of the buffer, and is refused rather than read into.
module StreamBounds;

import Standard.Console;
import Standard.Env;
import Standard.File;
import Standard.IO;
import Standard.Path;

int Main()
{
    nuint huge = ~(nuint)0u;
    var buffer = new byte[4];

    var memory = new MemoryStream(new byte[8]);
    Console.WriteLine($"memory read: {memory.Read(buffer, 2u, huge)}");
    Console.WriteLine($"memory write: {memory.Write(buffer, 2u, huge)}");
    Console.WriteLine($"memory length: {memory.Length}");

    var temp = Env.GetVariableOrDefault("TEMP", Env.GetVariableOrDefault("TMPDIR", "/tmp"));
    var path = Path.Join(temp, "stainless-files-stream-bounds.bin");
    File.WriteAllBytes(path, new byte[8]);

    var opened = FileStream.Open(path, FileMode.Open, FileAccess.ReadWrite);
    if (opened.Ok)
    {
        var file = opened.Value;
        Console.WriteLine($"file read: {file.Read(buffer, 2u, huge)} {IO.DescribeIOError(file.Error)}");
        Console.WriteLine($"file write: {file.Write(buffer, 2u, huge)} {IO.DescribeIOError(file.Error)}");
        Console.WriteLine($"file read past: {file.Read(buffer, 5u, 0u)}");
        file.Close();
    }

    Console.WriteLine($"file length: {File.GetSize(path)}");
    File.Delete(path);
    return 0;
}
