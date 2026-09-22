// SPDX-License-Identifier: 0BSD
//
// Input larger than a pipe, given to a child that writes while it reads.
//
// A parent that writes all of its input before reading any output waits on a
// child whose output pipe is full, and that child waits on the parent to read
// it. Both `Run` and `Open` MUST feed the input while they drain the output.
//
// The child is this program again, echoing line by line.
module Filter;

import Standard.Console;
import Standard.Env;
import Standard.Process;
import Standard.Collections;

void Echo()
{
    var line = Console.ReadLine();
    while (line != null)
    {
        Console.WriteLine((String)line);
        line = Console.ReadLine();
    }
}

String Input()
{
    var piece = new StringBuilder();
    for (int i = 0; i < 100; i++)
        piece.Append("0123456789");
    piece.Append("\n");

    String line = piece.ToText();
    var all = new StringBuilder();
    for (int i = 0; i < 820; i++)
        all.Append(line);
    return all.ToText();
}

public int Main(String[] args)
{
    if (args.Length > 0u && args[0u] == "echo")
    {
        Echo();
        return 0;
    }
    if (args.Length > 0u)
        return 0;

    String input = Input();

    var ran = Run(Env.Program(), ["echo"], input);
    if (ran.Ok)
        Console.WriteLine($"run   same={ran.Value.Output == input} code={ran.Value.ExitCode}");
    else
        Console.WriteLine($"run   refused why={(int)ran.Error}");

    var opened = Open(Env.Program(), ["echo"], input);
    if (opened.Ok)
    {
        var child = opened.Value;
        var text = new StringBuilder();
        while (child.Read())
        {
            text.Append(child.TakeOutput());
            child.TakeErrors();
        }
        Console.WriteLine($"open  same={text.ToText() == input} code={child.Wait().ValueOr(-1)}");
    }
    else
        Console.WriteLine($"open  refused why={(int)opened.Error}");

    // A child that exits without reading. The unwritten input is dropped.
    var deaf = Run(Env.Program(), ["deaf"], input);
    if (deaf.Ok)
        Console.WriteLine($"deaf  code={deaf.Value.ExitCode}");

    return 0;
}
