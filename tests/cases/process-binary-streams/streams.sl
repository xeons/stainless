// SPDX-License-Identifier: 0BSD
//
// The standard streams carry bytes unchanged when they are a pipe.
//
// Windows' C runtime starts them in text mode, where LF is written as CR LF,
// CR LF is read as LF, and a Ctrl-Z ends the input. The harness normalises
// line endings, so the child is this program again and the parent compares
// what came back byte for byte.
module Streams;

import Standard.Console;
import Standard.Env;
import Standard.Process;

public int Main(String[] args)
{
    if (args.Length > 0u)
    {
        if (args[0u] == "cat")
            Console.Write(Console.ReadToEnd());
        else if (args[0u] == "write")
        {
            Console.Write("a\nb\n");
            Console.WriteError("e");
        }
        return 0;
    }

    String input = "a\r\nb\x1Ac\n";
    var echoed = RunProcess(Env.GetProcessPath(), ["cat"], input);
    if (echoed.Ok)
        Console.WriteLine($"in    same={echoed.Value.StandardOutput == input} bytes={echoed.Value.StandardOutput.ByteLength()}");

    var written = RunProcess(Env.GetProcessPath(), ["write"]);
    if (written.Ok)
    {
        var done = written.Value;
        Console.WriteLine($"out   same={done.StandardOutput == "a\nb\n"} bytes={done.StandardOutput.ByteLength()}");
        Console.WriteLine($"err   same={done.StandardError == "e\n"} bytes={done.StandardError.ByteLength()}");
    }
    return 0;
}
