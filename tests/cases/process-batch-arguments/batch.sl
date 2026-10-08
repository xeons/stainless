// SPDX-License-Identifier: 0BSD
//
// A batch file's arguments reach it as text, never as cmd.exe syntax.
//
// Windows runs a .bat through `cmd.exe /c`, which would otherwise read `&` as
// a second command and `%NAME%` as a variable. The script prints each
// argument as cmd hands it over; `pwned` and the value of PATH must not
// appear on a line of their own.
module ProcessBatchArguments;

import Standard.Console;
import Standard.Env;
import Standard.File;
import Standard.Path;
import Standard.Process;

void Show(Result<ProcessResult, ProcessError> ran)
{
    if (ran.Ok)
        Console.Write(ran.Value.StandardOutput);
    else
        Console.WriteLine($"refused {ran.Error == ProcessError.InvalidArgument}");
}

int Main()
{
    var temp = Env.GetEnvironmentVariableOrDefault("TEMP", ".");
    var script = Path.Join(temp, "stainless-process-batch.bat");
    File.WriteAllText(script, "@echo off\r\necho 1=%1\r\necho 2=%2\r\necho 3=%3\r\necho 4=%4\r\n");

    Show(RunProcess(script, ["x & echo pwned", "100%PATH%", "a\"b", "plain"]));
    Show(RunProcess(script, ["two\r\nlines"]));

    File.Delete(script);
    return 0;
}
