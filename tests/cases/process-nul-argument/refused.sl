// SPDX-License-Identifier: 0BSD
//
// An argument holding a NUL is refused rather than cut short at it, where
// "secret\0.log" would reach the child as "secret".
module ProcessNulArgument;

import Standard.Console;
import Standard.Env;
import Standard.Process;

public int Main(String[] args)
{
    if (args.Length > 0u)
    {
        Console.WriteLine("child ran");
        return 0;
    }

    var ran = RunProcess(Env.GetProcessPath(), ["secret\0.log"]);
    Console.WriteLine($"run refused {!ran.Ok && ran.Error == ProcessError.InvalidArgument}");

    var started = Process.Start(Env.GetProcessPath(), ["a\0b"]);
    Console.WriteLine($"start refused {!started.Ok && started.Error == ProcessError.InvalidArgument}");
    return 0;
}
