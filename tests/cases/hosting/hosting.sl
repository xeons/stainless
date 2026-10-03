// SPDX-License-Identifier: 0BSD
//
// Standard.Hosting: hosted services started in order and stopped in reverse,
// a BackgroundService on its own thread asking the host to stop and setting
// the exit code, and the lifetime's tokens.
module HostingCase;

import Standard.Console;
import Standard.DependencyInjection;
import Standard.Hosting;
import Standard.Logging;
import Standard.Threading;

public sealed class Greeter : IHostedService
{
    ILogger<Greeter> _logger;

    public Greeter(ILogger<Greeter> logger)
    {
        _logger = logger;
    }

    public void Start(CancellationToken token) => _logger.LogInformation("greeter started");

    public void Stop(CancellationToken token) => _logger.LogInformation("greeter stopped");
}

public sealed class Ticker : BackgroundService
{
    IHostApplicationLifetime _lifetime;
    ILogger<Ticker> _logger;

    public Ticker(IHostApplicationLifetime lifetime, ILogger<Ticker> logger)
    {
        _lifetime = lifetime;
        _logger = logger;
    }

    protected override void Execute(CancellationToken stopping)
    {
        int ticks = 0;
        while (!stopping.WaitFor(5u))
        {
            ticks++;
            if (ticks == 3)
            {
                _logger.LogInformation("three ticks; stopping the host");
                _lifetime.ExitCode = 7;
                _lifetime.StopApplication();
            }
        }
        _logger.LogInformation("ticker finished");
    }
}

public int Main(String[] args)
{
    var builder = Host.CreateApplicationBuilder(args);
    builder.Logging.AddFilter("Standard.Hosting", LogLevel.Warning);
    builder.Services.AddHostedService<Greeter>();
    builder.Services.AddHostedService<Ticker>();

    var built = builder.Build();
    if (!built.Ok)
    {
        Console.WriteLine(built.Error);
        return 1;
    }
    var host = built.Value;
    var lifetime = host.Services.GetRequiredService<IHostApplicationLifetime>();
    lifetime.ApplicationStarted.Register(() => Console.WriteLine("lifetime: started"));
    lifetime.ApplicationStopping.Register(() => Console.WriteLine("lifetime: stopping"));
    lifetime.ApplicationStopped.Register(() => Console.WriteLine("lifetime: stopped"));

    int code = host.Run();
    Console.WriteLine($"exit {code}");
    return 0;
}
