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
    var echoed = RunProcess(Env.ProgramPath(), ["cat"], input);
    if (echoed.Ok)
        Console.WriteLine($"in    same={echoed.Value.Output == input} bytes={echoed.Value.Output.ByteLength()}");

    var written = RunProcess(Env.ProgramPath(), ["write"]);
    if (written.Ok)
    {
        var done = written.Value;
        Console.WriteLine($"out   same={done.Output == "a\nb\n"} bytes={done.Output.ByteLength()}");
        Console.WriteLine($"err   same={done.Errors == "e\n"} bytes={done.Errors.ByteLength()}");
    }
    return 0;
}
