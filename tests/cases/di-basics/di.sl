// SPDX-License-Identifier: 0BSD
//
// Standard.DependencyInjection: lifetimes, scopes, constructor injection
// written by the compiler, factories and instances, disposal order, a default
// implementation for a generic interface, and the checks BuildServiceProvider
// makes.
module DiBasics;

import Standard.Console;
import Standard.Collections;
import Standard.DependencyInjection;

public interface IClock
{
    int Now();
}

public sealed class FixedClock : IClock
{
    static int s_made = 0;
    public int Number;

    public FixedClock()
    {
        s_made++;
        Number = s_made;
    }

    public int Now() => 42;
}

public interface IGreeter
{
    String Greet();
}

public sealed class Greeter : IGreeter
{
    IClock _clock;
    ITracer? _tracer;
    IPlugin[] _plugins;

    public Greeter(IClock clock, ITracer? tracer, IPlugin[] plugins)
    {
        _clock = clock;
        _tracer = tracer;
        _plugins = plugins;
    }

    public String Greet()
    {
        String names = "";
        for (nuint i = 0u; i < _plugins.Length; i++)
            names = names + _plugins[i].Name;
        return $"hello at {_clock.Now()}, traced {_tracer != null}, plugins {names}";
    }
}

public interface ITracer
{
}

public interface IPlugin
{
    String Name { get; }
}

public sealed class PluginA : IPlugin
{
    public String Name => "A";
}

public sealed class PluginB : IPlugin
{
    public String Name => "B";
}

public sealed class Resource : IDisposable
{
    String _name;
    List<String> _log;

    public Resource(String name, List<String> log)
    {
        _name = name;
        _log = log;
    }

    public void Dispose()
    {
        _log.Add("disposed " + _name);
    }
}

public sealed class Counter
{
    static int s_made = 0;
    public int Number;

    public Counter()
    {
        s_made++;
        Number = s_made;
    }
}

[DefaultImplementation("DiBasics.Named")]
public interface INamed<T>
{
    String Name { get; }
}

public sealed class Named<T> : INamed<T>
{
    IClock _clock;

    public Named(IClock clock)
    {
        _clock = clock;
    }

    public String Name => RuntimeHelpers.GetTypeName<T>() + " at " + $"{_clock.Now()}";
}

public sealed class UsesNamed
{
    public INamed<Greeter> Named;

    public UsesNamed(INamed<Greeter> named)
    {
        Named = named;
    }
}

public sealed class NeedsMissing
{
    public NeedsMissing(ITracer tracer) { }
}

public sealed class SingletonNeedsScoped
{
    public SingletonNeedsScoped(Counter counter) { }
}

public sealed class LoopA
{
    public LoopA(LoopB b) { }
}

public sealed class LoopB
{
    public LoopB(LoopA a) { }
}

void CheckLifetimes(ServiceProvider provider)
{
    var first = provider.GetRequiredService<IClock>();
    var second = provider.GetRequiredService<IClock>();
    Console.WriteLine($"singleton same {first == second}");

    var scope = provider.CreateScope();
    var inScope = scope.ServiceProvider;
    var counter = inScope.GetRequiredService<Counter>();
    var again = inScope.GetRequiredService<Counter>();
    var other = provider.CreateScope().ServiceProvider.GetRequiredService<Counter>();
    Console.WriteLine($"scoped same {counter == again}, other scope differs {counter != other}");

    var made = inScope.GetRequiredService<IPlugin>();
    var madeAgain = inScope.GetRequiredService<IPlugin>();
    Console.WriteLine($"transient differs {made != madeAgain}, last wins {made.Name}");
    Console.WriteLine($"singleton from a scope is the root's {inScope.GetRequiredService<IClock>() == first}");
}

void CheckInjection(ServiceProvider provider)
{
    Console.WriteLine(provider.GetRequiredService<IGreeter>().Greet());
    Console.WriteLine($"unregistered {provider.GetService<ITracer>() == null}");
    var plugins = provider.GetServices<IPlugin>();
    Console.WriteLine($"plugins {plugins.Length}, {plugins[0].Name}{plugins[1].Name}");
    Console.WriteLine($"itself {provider.GetRequiredService<ServiceProvider>() == provider}");
    Console.WriteLine(provider.GetRequiredService<UsesNamed>().Named.Name);
}

void CheckDisposal()
{
    var log = new List<String>();
    var services = new ServiceCollection();
    services.AddScoped<Resource>((ServiceProvider p) => new Resource("first", log));
    services.AddTransient<IDisposable>((ServiceProvider p) => new Resource("second", log));
    services.AddSingletonInstance<Resource>(new Resource("given", log));
    var built = services.BuildServiceProvider();
    if (!built.Ok)
        return;
    var provider = built.Value;
    {
        var scope = provider.CreateScope();
        scope.ServiceProvider.GetServices<Resource>();
        scope.ServiceProvider.GetRequiredService<IDisposable>();
        scope.Dispose();
        scope.Dispose();
    }
    provider.Dispose();
    Console.WriteLine(", ".Join(log.ToArray()));
}

void CheckValidation()
{
    var services = new ServiceCollection();
    services.AddSingleton<NeedsMissing>();
    services.AddScoped<Counter>();
    services.AddSingleton<SingletonNeedsScoped>();
    services.AddTransient<LoopA>();
    services.AddTransient<LoopB>();
    var built = services.BuildServiceProvider();
    Console.WriteLine($"built {built.Ok}");
    if (!built.Ok)
        Console.WriteLine(built.Error.Message);
}

public int Main()
{
    var services = new ServiceCollection();
    services.AddSingleton<IClock, FixedClock>();
    services.TryAddSingleton<IClock, FixedClock>();
    services.AddScoped<Counter>();
    services.AddTransient<IPlugin, PluginA>();
    services.AddTransient<IPlugin, PluginB>();
    services.AddSingleton<IGreeter, Greeter>();
    services.AddTransient<UsesNamed>();
    Console.WriteLine($"registered {services.Count}");

    var built = services.BuildServiceProvider();
    if (!built.Ok)
    {
        Console.WriteLine(built.Error.Message);
        return 1;
    }
    var provider = built.Value;
    CheckLifetimes(provider);
    CheckInjection(provider);
    CheckDisposal();
    CheckValidation();
    return 0;
}
