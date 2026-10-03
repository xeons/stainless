// SPDX-License-Identifier: 0BSD
//
// Signals.WaitForInterrupt wakes on SIGTERM. The case starts itself as a
// child, waits until the child is watching, stops it, and reads back how the
// child ended: woken by the signal, then returning from Main as usual.
module SignalsWait;

import Standard.Console;
import Standard.Env;
import Standard.Process;

int RunChild()
{
    Signals.StartWatching();
    Console.WriteLine("watching");
    Console.Flush();
    bool interrupted = Signals.WaitForInterrupt(20000u);
    Console.WriteLine($"interrupted {interrupted}");
    return 3;
}

public int Main()
{
    if (ArgumentCount() > 0u && GetArgument(0u) == "child")
        return RunChild();

    Console.WriteLine($"before watching {Signals.WaitForInterrupt(5000u)}");

    var opened = OpenProcess(GetProcessPath(), ["child"]);
    if (!opened.Ok)
    {
        Console.WriteLine("could not start the child");
        return 1;
    }
    var child = opened.Value;

    String output = "";
    bool stopped = false;
    while (child.ReadAvailableOutput())
    {
        output = output + child.TakeOutput();
        if (!stopped && output.Contains("watching"))
        {
            stopped = child.Stop();
        }
    }
    output = output + child.TakeOutput();

    var exit = child.WaitForExit();
    Console.Write(output);
    Console.WriteLine($"stopped {stopped}, exit {exit.Ok && exit.Value == 3}");
    return 0;
}
