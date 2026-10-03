// SPDX-License-Identifier: 0BSD
//
// A worker service: a host that runs one background service until Ctrl-C.
//
//     cd samples/hosting
//     stainless run worker.sl
//     stainless run worker.sl -- --Worker:Greeting=hi --Worker:IntervalMilliseconds=250
//
// What it shows, in .NET's shape: constructor injection the compiler writes
// (Worker asks for its logger, its options and the lifetime by type),
// settings from appsettings.json, the environment and the command line bound
// onto a [Reflect] class, and a shutdown that lets the worker finish what it
// was doing. Run it from this directory so appsettings.json is found; from
// anywhere else the defaults below apply.
module WorkerSample;

import Standard.DependencyInjection;
import Standard.Hosting;
import Standard.Logging;
import Standard.Options;
import Standard.Reflection;
import Standard.Threading;

/// The `Worker` section of the configuration.
[Reflect]
public class WorkerOptions
{
    public String Greeting { get; set; } = "hello";
    public int IntervalMilliseconds { get; set; } = 1000;
    public int StopAfter { get; set; } = 0;
}

public sealed class Worker : BackgroundService
{
    ILogger<Worker> _logger;
    WorkerOptions _options;
    IHostApplicationLifetime _lifetime;

    public Worker(ILogger<Worker> logger, IOptions<WorkerOptions> options, IHostApplicationLifetime lifetime)
    {
        _logger = logger;
        _options = options.Value;
        _lifetime = lifetime;
    }

    protected override void Execute(CancellationToken stopping)
    {
        int beats = 0;
        while (!stopping.WaitFor((ulong)_options.IntervalMilliseconds))
        {
            beats++;
            _logger.LogInformation($"{_options.Greeting} #{beats}");

            // A run that ends itself, for trying it without a terminal.
            if (_options.StopAfter > 0 && beats >= _options.StopAfter)
                _lifetime.StopApplication();
        }
        _logger.LogInformation($"stopping after {beats} beats");
    }
}

public int Main(String[] args)
{
    var builder = Host.CreateApplicationBuilder(args);
    builder.Services.Configure<WorkerOptions>(builder.Configuration.GetSection("Worker"));
    builder.Services.AddHostedService<Worker>();

    var built = builder.Build();
    if (!built.Ok)
    {
        builder.Logging.Build().CreateLogger("WorkerSample").LogCritical(built.Error);
        return 1;
    }
    return built.Value.Run();
}
