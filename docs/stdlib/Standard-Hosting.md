# Standard.Hosting

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

A program that runs services until it is told to stop. .NET's Generic
Host, `Microsoft.Extensions.Hosting`.

    public int Main(String[] args)
    {
        var builder = Host.CreateApplicationBuilder(args);
        builder.Services.AddHostedService<Worker>();
        var host = try builder.Build();
        return host.Run();
    }

`Run` starts every `IHostedService` in the order registered, waits for
Ctrl-C, `SIGTERM` or `StopApplication`, stops them in the reverse order
within `ShutdownTimeout`, lets go of every service, and answers the exit
code for `Main` to return. There is no `async`: a `BackgroundService` runs
on a thread of its own, and a `CancellationToken` asks it to finish.

## Contents

**Types** &nbsp; [BackgroundService](#backgroundservice-class) &middot; [Host](#host-class) &middot; [HostApplicationBuilder](#hostapplicationbuilder-class) &middot; [HostApplicationLifetime](#hostapplicationlifetime-class) &middot; [HostEnvironment](#hostenvironment-class) &middot; [IHostApplicationLifetime](#ihostapplicationlifetime-interface) &middot; [IHostEnvironment](#ihostenvironment-interface) &middot; [IHostedService](#ihostedservice-interface)

**Functions** &nbsp; [AddHostedService](#addhostedservice-function)

## Types

### BackgroundService *class*

```
abstract class BackgroundService : IHostedService
```

A hosted service whose work is one long `Execute` on a thread of its own.
.NET's `BackgroundService`.

    public sealed class Worker : BackgroundService
    {
        ILogger<Worker> _logger;
        public Worker(ILogger<Worker> logger) { _logger = logger; }

        protected override void Execute(CancellationToken stopping)
        {
            while (!stopping.WaitFor(1000u))
                _logger.LogInformation("working");
        }
    }

<sub>[stdlib/Hosting/BackgroundService.sl:40](../../stdlib/Hosting/BackgroundService.sl#L40)</sub>

#### Start *method*

```
virtual void Start(CancellationToken token)
```

Starts `Execute` on a thread of its own, and returns at once.

<sub>[stdlib/Hosting/BackgroundService.sl:51](../../stdlib/Hosting/BackgroundService.sl#L51)</sub>

#### Stop *method*

```
virtual void Stop(CancellationToken token)
```

Cancels `Execute`'s token and waits for it to return, or for `token`
to be cancelled. A thread still running then is let go of rather than
waited for.

<sub>[stdlib/Hosting/BackgroundService.sl:69](../../stdlib/Hosting/BackgroundService.sl#L69)</sub>

### Host *class*

```
sealed class Host
```

A built host. .NET's `IHost`.

<sub>[stdlib/Hosting/Host.sl:31](../../stdlib/Hosting/Host.sl#L31)</sub>

#### ShutdownTimeout *field*

```
TimeSpan ShutdownTimeout
```

How long hosted services have to stop before the host lets go of them.

<sub>[stdlib/Hosting/Host.sl:38](../../stdlib/Hosting/Host.sl#L38)</sub>

#### CreateApplicationBuilder *method*

```
static HostApplicationBuilder CreateApplicationBuilder(String[] arguments)
```

A builder with the defaults: configuration from `appsettings.json`, the
environment and `arguments`, and logging to the console.

**Parameters**

- `arguments` -- the program's command line, read as configuration

<sub>[stdlib/Hosting/Host.sl:51](../../stdlib/Hosting/Host.sl#L51)</sub>

#### Services *property*

```
ServiceProvider Services { get; }
```

What the host made, and makes.

<sub>[stdlib/Hosting/Host.sl:55](../../stdlib/Hosting/Host.sl#L55)</sub>

#### Run *method*

```
int Run()
```

Starts every hosted service, waits until Ctrl-C, `SIGTERM` or
`StopApplication`, stops them in the reverse order, and lets go of every
service.

**Returns** &nbsp; the exit code a service set on the lifetime, 0 by default

<sub>[stdlib/Hosting/Host.sl:62](../../stdlib/Hosting/Host.sl#L62)</sub>

### HostApplicationBuilder *class*

```
sealed class HostApplicationBuilder
```

The services, their configuration and their logging, built into a host.
.NET's `HostApplicationBuilder`.

<sub>[stdlib/Hosting/HostApplicationBuilder.sl:32](../../stdlib/Hosting/HostApplicationBuilder.sl#L32)</sub>

#### Services *field*

```
ServiceCollection Services
```

What the host will make. Register hosted services here.

<sub>[stdlib/Hosting/HostApplicationBuilder.sl:37](../../stdlib/Hosting/HostApplicationBuilder.sl#L37)</sub>

#### Configuration *field*

```
Configuration Configuration
```

The settings, read when the builder was made: `appsettings.json`, then
`appsettings.{EnvironmentName}.json`, both optional, then environment
variables, then the command line.

<sub>[stdlib/Hosting/HostApplicationBuilder.sl:42](../../stdlib/Hosting/HostApplicationBuilder.sl#L42)</sub>

#### Logging *field*

```
LoggingBuilder Logging
```

Where log messages go, and at what level. The console, with the levels
the `Logging` section of the configuration names, unless changed.

<sub>[stdlib/Hosting/HostApplicationBuilder.sl:46](../../stdlib/Hosting/HostApplicationBuilder.sl#L46)</sub>

#### Environment *field*

```
HostEnvironment Environment
```

Where the host runs.

<sub>[stdlib/Hosting/HostApplicationBuilder.sl:49](../../stdlib/Hosting/HostApplicationBuilder.sl#L49)</sub>

#### Build *method*

```
Result<Host, String> Build()
```

The host, its services checked as `BuildServiceProvider` checks them.

**Returns** &nbsp; the host, or every problem with the configuration files or the registrations, one per line

<sub>[stdlib/Hosting/HostApplicationBuilder.sl:80](../../stdlib/Hosting/HostApplicationBuilder.sl#L80)</sub>

### HostApplicationLifetime *class*

```
threadsafe sealed class HostApplicationLifetime : IHostApplicationLifetime
```

The lifetime a host registers.

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:27](../../stdlib/Hosting/HostApplicationLifetime.sl#L27)</sub>

#### ApplicationStarted *property*

```
CancellationToken ApplicationStarted { get; }
```

*No documentation.*

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:34](../../stdlib/Hosting/HostApplicationLifetime.sl#L34)</sub>

#### ApplicationStopping *property*

```
CancellationToken ApplicationStopping { get; }
```

*No documentation.*

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:35](../../stdlib/Hosting/HostApplicationLifetime.sl#L35)</sub>

#### ApplicationStopped *property*

```
CancellationToken ApplicationStopped { get; }
```

*No documentation.*

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:36](../../stdlib/Hosting/HostApplicationLifetime.sl#L36)</sub>

#### StopApplication *method*

```
void StopApplication()
```

*No documentation.*

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:38](../../stdlib/Hosting/HostApplicationLifetime.sl#L38)</sub>

#### ExitCode *property*

```
int ExitCode { get; set; }
```

*No documentation.*

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:40](../../stdlib/Hosting/HostApplicationLifetime.sl#L40)</sub>

### HostEnvironment *class*

```
sealed class HostEnvironment : IHostEnvironment
```

The environment a host registers.

<sub>[stdlib/Hosting/HostEnvironment.sl:25](../../stdlib/Hosting/HostEnvironment.sl#L25)</sub>

#### EnvironmentName *property*

```
String EnvironmentName { get; }
```

*No documentation.*

<sub>[stdlib/Hosting/HostEnvironment.sl:38](../../stdlib/Hosting/HostEnvironment.sl#L38)</sub>

#### ContentRootPath *property*

```
String ContentRootPath { get; }
```

*No documentation.*

<sub>[stdlib/Hosting/HostEnvironment.sl:39](../../stdlib/Hosting/HostEnvironment.sl#L39)</sub>

#### ApplicationName *property*

```
String ApplicationName { get; }
```

*No documentation.*

<sub>[stdlib/Hosting/HostEnvironment.sl:40](../../stdlib/Hosting/HostEnvironment.sl#L40)</sub>

#### IsDevelopment *property*

```
bool IsDevelopment { get; }
```

Whether this is the `Development` environment.

<sub>[stdlib/Hosting/HostEnvironment.sl:43](../../stdlib/Hosting/HostEnvironment.sl#L43)</sub>

#### IsProduction *property*

```
bool IsProduction { get; }
```

Whether this is the `Production` environment.

<sub>[stdlib/Hosting/HostEnvironment.sl:46](../../stdlib/Hosting/HostEnvironment.sl#L46)</sub>

### IHostApplicationLifetime *interface*

```
interface IHostApplicationLifetime
```

When the host has started, is stopping and has stopped, and how to ask it
to stop. .NET's `IHostApplicationLifetime`.

<sub>[stdlib/Hosting/IHostApplicationLifetime.sl:28](../../stdlib/Hosting/IHostApplicationLifetime.sl#L28)</sub>

#### ApplicationStarted *property*

```
CancellationToken ApplicationStarted { get; }
```

Cancelled once every hosted service has started.

<sub>[stdlib/Hosting/IHostApplicationLifetime.sl:31](../../stdlib/Hosting/IHostApplicationLifetime.sl#L31)</sub>

#### ApplicationStopping *property*

```
CancellationToken ApplicationStopping { get; }
```

Cancelled when the host begins to stop.

<sub>[stdlib/Hosting/IHostApplicationLifetime.sl:34](../../stdlib/Hosting/IHostApplicationLifetime.sl#L34)</sub>

#### ApplicationStopped *property*

```
CancellationToken ApplicationStopped { get; }
```

Cancelled once every hosted service has stopped.

<sub>[stdlib/Hosting/IHostApplicationLifetime.sl:37](../../stdlib/Hosting/IHostApplicationLifetime.sl#L37)</sub>

#### StopApplication *method*

```
void StopApplication()
```

Asks the host to stop, as Ctrl-C does. `Run` returns once it has.

<sub>[stdlib/Hosting/IHostApplicationLifetime.sl:40](../../stdlib/Hosting/IHostApplicationLifetime.sl#L40)</sub>

#### ExitCode *property*

```
int ExitCode { get; set; }
```

What `Run` answers, for `Main` to return: 0 unless something sets it.

<sub>[stdlib/Hosting/IHostApplicationLifetime.sl:43](../../stdlib/Hosting/IHostApplicationLifetime.sl#L43)</sub>

### IHostEnvironment *interface*

```
interface IHostEnvironment
```

Where the host runs. .NET's `IHostEnvironment`.

<sub>[stdlib/Hosting/IHostEnvironment.sl:25](../../stdlib/Hosting/IHostEnvironment.sl#L25)</sub>

#### EnvironmentName *property*

```
String EnvironmentName { get; }
```

`Production` unless `STAINLESS_ENVIRONMENT` says otherwise:
`Development` and `Staging` are the other names in use.

<sub>[stdlib/Hosting/IHostEnvironment.sl:29](../../stdlib/Hosting/IHostEnvironment.sl#L29)</sub>

#### ContentRootPath *property*

```
String ContentRootPath { get; }
```

The directory configuration files are read from: the working
directory when the host was built.

<sub>[stdlib/Hosting/IHostEnvironment.sl:33](../../stdlib/Hosting/IHostEnvironment.sl#L33)</sub>

#### ApplicationName *property*

```
String ApplicationName { get; }
```

The program's name, from its path.

<sub>[stdlib/Hosting/IHostEnvironment.sl:36](../../stdlib/Hosting/IHostEnvironment.sl#L36)</sub>

### IHostedService *interface*

```
interface IHostedService
```

Something the host starts and stops. .NET's `IHostedService`.

<sub>[stdlib/Hosting/IHostedService.sl:27](../../stdlib/Hosting/IHostedService.sl#L27)</sub>

#### Start *method*

```
void Start(CancellationToken token)
```

Starts the service, and returns once it has: the host starts the next
one when this returns. `token` is cancelled if starting is abandoned.

<sub>[stdlib/Hosting/IHostedService.sl:31](../../stdlib/Hosting/IHostedService.sl#L31)</sub>

#### Stop *method*

```
void Stop(CancellationToken token)
```

Stops the service, and returns once it has, or once `token` is
cancelled because the shutdown timeout ran out.

<sub>[stdlib/Hosting/IHostedService.sl:35](../../stdlib/Hosting/IHostedService.sl#L35)</sub>

## Functions

### AddHostedService *function*

```
ServiceCollection AddHostedService<T>(ServiceCollection services)
    where T : class, IHostedService
```

Registers `T` as a hosted service, made when the host starts; call it as
`services.AddHostedService<T>()`.

**Type parameters**

- `T` -- the service, made as any registered class is

<sub>[stdlib/Hosting/Hosting.sl:46](../../stdlib/Hosting/Hosting.sl#L46)</sub>

