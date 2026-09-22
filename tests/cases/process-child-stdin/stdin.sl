// SPDX-License-Identifier: 0BSD
//
// A child run without input reads end of input, not the parent's stdin.
//
// Otherwise a child that reads would take what the parent was given, and one
// that waits for input would wait on a terminal nobody is typing into.
module ChildStdin;

import Standard.Console;
import Standard.Env;
import Standard.Process;

public int Main(String[] args)
{
    if (args.Length > 0u)
    {
        Console.Write($"read {Console.ReadToEnd().ByteLength()}");
        return 0;
    }

    var ran = Run(Env.Program(), ["read"]);
    if (ran.Ok)
        Console.WriteLine($"run    {ran.Value.Output}");

    var opened = Open(Env.Program(), ["read"]);
    if (opened.Ok)
    {
        var child = opened.Value;
        var text = new StringBuilder();
        while (child.Read())
            text.Append(child.TakeOutput());
        Console.WriteLine($"open   {text.ToText()}");
    }

    Console.WriteLine($"parent {Console.ReadToEnd().Trim()}");
    return 0;
}
