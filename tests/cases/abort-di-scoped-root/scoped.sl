// SPDX-License-Identifier: 0BSD
//
// A scoped service asked of the root provider stops the program: the root
// would keep it for ever, which is what a scope exists to prevent.
module AbortDiScopedRoot;

import Standard.Console;
import Standard.DependencyInjection;

public sealed class Unit
{
}

public int Main()
{
    var services = new ServiceCollection();
    services.AddScoped<Unit>();
    var built = services.BuildServiceProvider();
    if (!built.Ok)
        return 1;
    var root = built.Value;
    var scope = root.CreateScope();
    Console.WriteLine($"from a scope {scope.ServiceProvider.GetService<Unit>() != null}");
    root.GetService<Unit>();
    Console.WriteLine("unreachable");
    return 0;
}
