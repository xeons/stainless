// SPDX-License-Identifier: 0BSD
//
// Standard.Logging: ILogger<T> made with nothing registered, under its type's
// name; the minimum level and category prefixes, from code and from a
// configuration section; a provider of the program's own beside the console.
module LoggingCase;

import Standard.Console;
import Standard.Collections;
import Standard.Configuration;
import Standard.DependencyInjection;
import Standard.Logging;

public sealed class Worker
{
    ILogger<Worker> _logger;

    public Worker(ILogger<Worker> logger)
    {
        _logger = logger;
    }

    public void Run()
    {
        _logger.LogTrace("too quiet to see");
        _logger.LogDebug("debugging");
        _logger.LogInformation("working\non two lines");
        _logger.LogWarning("careful");
    }
}

public sealed class Noisy
{
    public ILogger<Noisy> Logger;

    public Noisy(ILogger<Noisy> logger)
    {
        Logger = logger;
    }
}

/// Keeps what it is given, so the case can read it back.
public sealed threadsafe class ListProvider : ILoggerProvider
{
    public List<String> Lines = new List<String>();

    public ILogger CreateLogger(String category) => new ListLogger(category, Lines);
}

public sealed class ListLogger : ILogger
{
    String _category;
    List<String> _lines;

    public ListLogger(String category, List<String> lines)
    {
        _category = category;
        _lines = lines;
    }

    public bool IsEnabled(LogLevel level) => true;

    public void Log(LogLevel level, String message) => _lines.Add($"{level} {_category}: {message}");
}

public int Main()
{
    var settings = new Dictionary<String, String>();
    settings.SetValue("Logging:LogLevel:Default", "Debug");
    settings.SetValue("Logging:LogLevel:LoggingCase.Noisy", "Error");
    var configuration = new ConfigurationBuilder().AddInMemoryCollection(settings).Build();
    if (!configuration.Ok)
        return 1;
    var loggingSection = configuration.Value.GetSection("Logging");

    var captured = new ListProvider();
    var services = new ServiceCollection();
    services.AddLogging((LoggingBuilder logging) =>
    {
        logging.AddConsole()
            .AddProvider(captured)
            .AddConfiguration(loggingSection);
    });
    services.AddTransient<Worker>();
    services.AddTransient<Noisy>();

    var built = services.BuildServiceProvider();
    if (!built.Ok)
    {
        Console.WriteLine(built.Error.Message);
        return 1;
    }
    var provider = built.Value;
    provider.GetRequiredService<Worker>().Run();

    var noisy = provider.GetRequiredService<Noisy>().Logger;
    noisy.LogWarning("filtered out");
    noisy.LogError("let through");
    Console.WriteLine($"noisy warning enabled {noisy.IsEnabled(LogLevel.Warning)}");

    var direct = provider.GetRequiredService<ILoggerFactory>().CreateLogger("Direct");
    direct.LogCritical("from the factory");

    Console.WriteLine("captured:");
    for (nuint i = 0u; i < captured.Lines.Count; i++)
        Console.WriteLine("  " + captured.Lines[i]);
    return 0;
}
