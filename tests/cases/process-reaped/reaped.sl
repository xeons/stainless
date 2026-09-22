// SPDX-License-Identifier: 0BSD
//
// A child whose handle is dropped while it runs is reaped when it exits.
//
// Dropping a `Process` or a `Running` does not stop the child, and it MUST
// NOT leave a zombie behind once the child has finished. Whatever is left for
// waitpid(-1) afterwards is exactly what was not reaped.
module Reaped;

import Standard.Console;
import Standard.Process;
import Standard.Threading;

extern "C" int waitpid(int pid, int* status, int options);

const int NoHang = 1;

void StartAndDrop()
{
    var started = Process.Start("sleep", ["0.2"]);
    Console.WriteLine($"start  {started.Ok}");
}

void OpenAndDrop()
{
    var opened = Open("sleep", ["0.2"]);
    Console.WriteLine($"open   {opened.Ok}");
}

public int Main()
{
    StartAndDrop();
    OpenAndDrop();

    Sleep(1000u);

    int status = 0;
    int left = waitpid(-1, &status, NoHang);
    Console.WriteLine($"zombie {left > 0}");
    return 0;
}
