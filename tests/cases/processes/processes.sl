// SPDX-License-Identifier: 0BSD
//
// Running another program.
//
// **There is no shell.** The program and its arguments are a list, so a `>`, a
// `|` or a space in a filename is a character the child receives rather than
// something a shell acts on. That is the whole of shell injection, designed
// out rather than warned about.
//
// Two things here are the reason the runtime is written the way it is:
//
// **A pipe holds about 64KB**, so a parent that waits for the child before
// reading waits forever on a child that writes more. Both streams are drained
// *while* it runs.
//
// **A failed exec cannot be reported as an exit code.** 127 is the shell's
// convention for "could not run it" and is also a perfectly ordinary code a
// real program might return. So the child reports through a close-on-exec pipe
// instead, and "no such program" and "ran and answered 127" stay apart -- which
// this case checks, because otherwise `ProcessError.NotFound` would be a lie.
module Processes;

import Standard.Console;
import Standard.Process;

// The programs differ; everything asked of them does not.
#if UNIX
String Shell() => "sh";
String Flag() => "-c";
#else
String Shell() => "cmd";
String Flag() => "/c";
#endif

/// Runs it and reports one line, so the checking happens in one place.
void Show(String label, String program, String[] arguments)
{
    var answer = Run(program, arguments);

    if (!answer.Ok)
    {
        Console.WriteLine($"{label} refused, why={(int)answer.Error}");
        return;
    }

    var done = answer.Value;
    Console.WriteLine(
        $"{label} code={done.ExitCode} ok={done.Ok()} " +
        $"out=[{done.Output.Trim()}] err=[{done.Errors.Trim()}]");
}

public int Main()
{
    // What it wrote, and what it returned.
    Show("echo    ", Shell(), [Flag(), "echo hello"]);
    Show("code    ", Shell(), [Flag(), "exit 3"]);

    // The two streams stay apart, so a program that prints progress to one
    // does not corrupt what was captured from the other.
#if UNIX
    Show("split   ", Shell(), [Flag(), "echo out; echo err 1>&2"]);
#else
    Show("split   ", Shell(), [Flag(), "echo out& echo err 1>&2"]);
#endif

    // A program that could not be started at all, which is an error rather
    // than an outcome -- 1 is ProcessError.NotFound.
    Show("missing ", "/no/such/program-that-exists", []);

    // And the case the report pipe exists for: a program that really did run
    // and really did answer 127. Not NotFound.
    Show("ran127  ", Shell(), [Flag(), "exit 127"]);

    // Input written to it, and the pipe closed, so a program reading to
    // end-of-input stops rather than waiting. `sort` is the one filter both
    // platforms ship, which is why it and not `wc`.
    var sorted = Run(Shell(), [Flag(), "sort"], "gamma\nalpha\nbeta\n");
    if (sorted.Ok)
    {
        var order = sorted.Value.Output.SplitLines();
        Console.WriteLine($"stdin    [{order[0u].Trim()} {order[1u].Trim()} {order[2u].Trim()}]");
    }

    // More output than a pipe holds, which is what would deadlock a reader
    // that waited first.
#if UNIX
    var big = Run(Shell(), [Flag(), "head -c 200000 /dev/zero"]);
#else
    var big = Run(Shell(), [Flag(), "for /L %i in (1,1,4000) do @echo tttttttttttttttttttttttttttttttttttttttttttttttttt"]);
#endif
    if (big.Ok)
{
        Console.WriteLine($"big      past a pipe: {big.Value.Output.ByteLength() > 100000u}");
    }

    // Started without waiting, then waited for.
    var started = Process.Start(Shell(), [Flag(), "exit 7"]);
    if (started.Ok)
    {
        var child = started.Value;
        Console.WriteLine($"started  named={child.Id > 0L} waited={child.Wait().ValueOr(-1)}");
        Console.WriteLine($"again    {child.Wait().ValueOr(-1)}");
    }

    // Started, seen to be running, and stopped.
    var slow = Process.Start(Shell(), [Flag(), "sleep 30"]);
    if (slow.Ok)
    {
        var child = slow.Value;
        Console.WriteLine($"running  {child.Finished.IsEmpty()}");
        child.Kill();
        Console.WriteLine($"stopped  {child.Wait().Ok}");
    }

    // Interrupts are noticed rather than delivered, so this asks.
    Console.WriteLine($"signals  watching={Signals.Watch()} seen={Signals.Interrupted}");
    return 0;
}
