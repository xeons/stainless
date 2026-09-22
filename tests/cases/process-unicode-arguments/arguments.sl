// SPDX-License-Identifier: 0BSD
//
// Arguments outside ASCII arrive as the UTF-8 they are.
//
// Windows hands a narrow main() its arguments in the active code page, where
// "café" is one byte short and "日本" is question marks. Checked twice: as the
// harness passes them, and as `Run` passes them to this program again.
module Arguments;

import Standard.Console;
import Standard.Env;
import Standard.Process;

void Check(String label, String[] args, nuint first)
{
    bool cafe = args.Length > first && args[first] == "café";
    bool japan = args.Length > first + 1u && args[first + 1u] == "日本";
    bool spaced = args.Length > first + 2u && args[first + 2u] == "a \"b\" c";
    Console.WriteLine($"{label} cafe={cafe} japan={japan} spaced={spaced}");
}

public int Main(String[] args)
{
    if (args.Length > 0u && args[0u] == "child")
    {
        Check("child ", args, 1u);
        Check("env   ", Env.GetArguments(), 1u);
        return 0;
    }

    Check("main  ", args, 0u);

    var ran = RunProcess(Env.ProgramPath(), ["child", "café", "日本", "a \"b\" c"]);
    if (ran.Ok)
        Console.Write(ran.Value.Output);
    return 0;
}
