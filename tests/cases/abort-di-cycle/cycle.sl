// SPDX-License-Identifier: 0BSD
//
// A cycle that only the factories reveal, which BuildServiceProvider cannot
// see, stops the program when it is first walked rather than looping or
// deadlocking.
module AbortDiCycle;

import Standard.Console;
import Standard.DependencyInjection;

public sealed class Egg
{
    public Egg(Chicken chicken) { }
}

public sealed class Chicken
{
    public Chicken(Egg egg) { }
}

public int Main()
{
    var services = new ServiceCollection();
    services.AddSingleton<Egg>((ServiceProvider p) => new Egg(p.GetRequiredService<Chicken>()));
    services.AddSingleton<Chicken>((ServiceProvider p) => new Chicken(p.GetRequiredService<Egg>()));
    var built = services.BuildServiceProvider();
    Console.WriteLine($"built {built.Ok}");
    if (!built.Ok)
        return 1;
    built.Value.GetRequiredService<Egg>();
    Console.WriteLine("unreachable");
    return 0;
}
