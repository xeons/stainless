// SPDX-License-Identifier: 0BSD
//
// A child started while another's pipes are open does not inherit them.
//
// `Open` keeps the write end of its child's input open while the input is
// still being fed. A second child that inherited a copy would hold that pipe
// open, and the first would never read end of input until the second exited.
module Inherited;

import Standard.Console;
import Standard.Env;
import Standard.Process;
import Standard.Threading;

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
    var all = new StringBuilder();
    for (int i = 0; i < 4000; i++)
        all.Append("0123456789012345678901234567890123456789012345678\n");
    return all.ToText();
}

public int Main(String[] args)
{
    if (args.Length > 0u)
    {
        if (args[0u] == "echo")
            Echo();
        else
            Sleep(20000u);
        return 0;
    }

    String input = Input();

    var opened = OpenProcess(Env.ProgramPath(), ["echo"], input);
    var bystander = Process.Start(Env.ProgramPath(), ["sleep"]);
    if (!opened.Ok || !bystander.Ok)
        return 1;

    var child = opened.Value;
    var text = new StringBuilder();
    while (child.ReadAvailableOutput())
    {
        text.Append(child.TakeOutput());
        child.TakeErrors();
    }
    child.Wait();

    var other = bystander.Value;
    Console.WriteLine($"echoed {text.ToText() == input} before the bystander ended {other.Finished.IsEmpty}");

    other.Kill();
    other.Wait();
    return 0;
}
