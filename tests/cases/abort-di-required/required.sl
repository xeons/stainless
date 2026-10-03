// SPDX-License-Identifier: 0BSD
//
// GetRequiredService for what nothing registered stops the program, naming
// the type: there is no exception to throw.
module AbortDiRequired;

import Standard.Console;
import Standard.DependencyInjection;

public interface IMissing
{
}

public int Main()
{
    var built = new ServiceCollection().BuildServiceProvider();
    if (!built.Ok)
        return 1;
    Console.WriteLine($"optional {built.Value.GetService<IMissing>() == null}");
    built.Value.GetRequiredService<IMissing>();
    Console.WriteLine("unreachable");
    return 0;
}
