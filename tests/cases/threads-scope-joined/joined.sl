// SPDX-License-Identifier: 0BSD
module ScopeJoined;

import Standard.Console;
import Standard.Threading;

void Work(byte* argument)
{
}

public int Main()
{
    var scope = new TaskScope();
    scope.Run(Work, null);
    scope.Join();
    Console.WriteLine("joined");
    scope.Run(Work, null);
    Console.WriteLine("not reached");
    return 0;
}
