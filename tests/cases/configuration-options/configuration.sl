// SPDX-License-Identifier: 0BSD
//
// Standard.Configuration from a JSON file, the environment and the command
// line, the later winning; ConfigurationBinder onto a [Reflect] class; and
// Standard.Options through a service provider.
module ConfigurationOptions;

import Standard.Console;
import Standard.Collections;
import Standard.Configuration;
import Standard.DependencyInjection;
import Standard.Env;
import Standard.File;
import Standard.Options;
import Standard.Reflection;

public enum Mode
{
    Slow,
    Fast,
}

[Reflect]
public class Limits
{
    public int Connections { get; set; } = 1;
}

[Reflect]
public class ServerOptions
{
    public String Name { get; set; } = "unnamed";
    public int Port { get; set; } = 80;
    public bool Debug { get; set; } = false;
    public Mode Mode { get; set; } = Mode.Slow;
    public double Ratio { get; set; } = 0.5;
    public Limits Limits { get; set; } = new Limits();
}

void ShowOptions(String label, ServerOptions options)
{
    Console.WriteLine($"{label}: {options.Name} {options.Port} {options.Debug} {options.Mode} {options.Ratio} {options.Limits.Connections}");
}

public int Main(String[] args)
{
    String path = "configuration-options.json";
    WriteAllText(path, """
        {
            "Server": {
                "Name": "main",
                "Port": 8080,
                "Debug": true,
                "Mode": "fast",
                "Ratio": 0.25,
                "Hosts": [ "a", "b" ],
                "Limits": { "Connections": 16 }
            }
        }
        """);
    SetEnvironmentVariable("CFGTEST_Server__Name", "from-environment");

    var built = new ConfigurationBuilder()
        .AddJsonFile(path)
        .AddJsonFile("missing.json", optional: true)
        .AddEnvironmentVariables("CFGTEST_")
        .AddCommandLine(args)
        .Build();
    Delete(path);
    if (!built.Ok)
    {
        Console.WriteLine(built.Error.Message);
        return 1;
    }
    var configuration = built.Value;

    Console.WriteLine($"port {configuration.GetValue("Server:Port") ?? "none"}");
    Console.WriteLine($"name {configuration.GetValue("server:name") ?? "none"}");
    Console.WriteLine($"host {configuration.GetValue("Server:Hosts:1") ?? "none"}");
    Console.WriteLine($"extra {configuration.GetValue("Extra") ?? "none"}");
    var section = configuration.GetSection("Server");
    var children = section.GetChildren();
    String keys = "";
    for (nuint i = 0u; i < children.Count; i++)
        keys = keys + children[i].Key + " ";
    Console.WriteLine("children " + keys);

    var options = new ServerOptions();
    var bound = ConfigurationBinder.Bind<ServerOptions>(section, options);
    Console.WriteLine($"bound {bound.Ok}");
    ShowOptions("options", options);

    var wrong = new Dictionary<String, String>();
    wrong.SetValue("Server:Port", "eighty");
    var bad = new ConfigurationBuilder().AddInMemoryCollection(wrong).Build();
    if (bad.Ok)
    {
        var failed = ConfigurationBinder.Bind<ServerOptions>(bad.Value.GetSection("Server"), new ServerOptions());
        if (!failed.Ok)
            Console.WriteLine(failed.Error.Message);
    }

    var services = new ServiceCollection();
    services.Configure<ServerOptions>(section);
    services.AddOptions<ServerOptions>()
        .Configure((ServerOptions o) => o.Name = o.Name + "!")
        .Validate((ServerOptions o) => o.Port > 0, "the port must be positive");
    var provider = services.BuildServiceProvider();
    if (provider.Ok)
    {
        var made = provider.Value.GetRequiredService<IOptions<ServerOptions>>();
        ShowOptions("service", made.Value);
        Console.WriteLine($"same {made.Value == provider.Value.GetRequiredService<IOptions<ServerOptions>>().Value}");
    }
    return 0;
}
