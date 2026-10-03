// SPDX-License-Identifier: 0BSD
//
// A host stopped by SIGTERM shuts down as StopApplication would: the case
// starts itself as a child host, waits until its worker is running, stops it,
// and reads back the graceful shutdown and the exit code.
module HostingSignals;

import Standard.Console;
import Standard.DependencyInjection;
import Standard.Env;
import Standard.Hosting;
import Standard.Logging;
import Standard.Process;
import Standard.Threading;

public sealed class Worker : BackgroundService
{
    IHostApplicationLifetime _lifetime;

    public Worker(IHostApplicationLifetime lifetime)
    {
        _lifetime = lifetime;
    }

    protected override void Execute(CancellationToken stopping)
    {
        Console.WriteLine("worker running");
        Console.Flush();
        stopping.Wait();
        Console.WriteLine("worker stopped");
        _lifetime.ExitCode = 5;
    }
}

int RunHost()
{
    var builder = Host.CreateApplicationBuilder([]);
    builder.Logging.ClearProviders();
    builder.Services.AddHostedService<Worker>();
    var built = builder.Build();
    if (!built.Ok)
        return 1;
    return built.Value.Run();
}

public int Main()
{
    if (ArgumentCount() > 0u && GetArgument(0u) == "host")
        return RunHost();

    var opened = OpenProcess(GetProcessPath(), ["host"]);
    if (!opened.Ok)
        return 1;
    var child = opened.Value;

    String output = "";
    bool stopped = false;
    while (child.ReadAvailableOutput())
    {
        output = output + child.TakeOutput();
        if (!stopped && output.Contains("worker running"))
            stopped = child.Stop();
    }
    output = output + child.TakeOutput();
    var exit = child.WaitForExit();
    Console.Write(output);
    Console.WriteLine($"stopped {stopped}, exit {exit.Ok && exit.Value == 5}");
    return 0;
}
