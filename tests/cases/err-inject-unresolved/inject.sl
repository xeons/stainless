// SPDX-License-Identifier: 0BSD
//
// A constructor parameter whose type does not resolve is reported once, for
// the type, and not again as something a container cannot be asked for.
// Found by the fuzzer, as an internal compiler error.
module ErrInjectUnresolved;

import Standard.DependencyInjection;

class Worker
{
    public Worker(Missing logger)       // SLN0017
    {
    }
}

int Main()
{
    var services = new ServiceCollection();
    services.AddTransient<Worker>();
    return 0;
}