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

<sub>[stdlib/Hosting/Hosting.sl:70](../../stdlib/Hosting/Hosting.sl#L70)</sub>

#### Start *method*

```
virtual void Start(CancellationToken token)
```

Starts `Execute` on a thread of its own, and returns at once.

<sub>[stdlib/Hosting/Hosting.sl:81](../../stdlib/Hosting/Hosting.sl#L81)</sub>

#### Stop *method*

```
virtual void Stop(CancellationToken token)
```

Cancels `Execute`'s token and waits for it to return, or for `token`
to be cancelled. A thread still running then is let go of rather than
waited for.

<sub>[stdlib/Hosting/Hosting.sl:99](../../stdlib/Hosting/Hosting.sl#L99)</sub>

### Host *class*

```
sealed class Host
```

A built host. .NET's `IHost`.

<sub>[stdlib/Hosting/Host.sl:106](../../stdlib/Hosting/Host.sl#L106)</sub>

#### ShutdownTimeout *field*

```
TimeSpan ShutdownTimeout
```

How long hosted services have to stop before the host lets go of them.

<sub>[stdlib/Hosting/Host.sl:113](../../stdlib/Hosting/Host.sl#L113)</sub>

#### CreateApplicationBuilder *method*

```
static HostApplicationBuilder CreateApplicationBuilder(String[] arguments)
```

A builder with the defaults: configuration from `appsettings.json`, the
environment and `arguments`, and logging to the console.

**Parameters**

- `arguments` -- the program's command line, read as configuration

<sub>[stdlib/Hosting/Host.sl:126](../../stdlib/Hosting/Host.sl#L126)</sub>

#### Services *property*

```
ServiceProvider Services { get; }
```

What the host made, and makes.

<sub>[stdlib/Hosting/Host.sl:130](../../stdlib/Hosting/Host.sl#L130)</sub>

#### Run *method*

```
int Run()
```

Starts every hosted service, waits until Ctrl-C, `SIGTERM` or
`StopApplication`, stops them in the reverse order, and lets go of every
service.

**Returns** &nbsp; the exit code a service set on the lifetime, 0 by default

<sub>[stdlib/Hosting/Host.sl:137](../../stdlib/Hosting/Host.sl#L137)</sub>

### HostApplicationBuilder *class*

```
sealed class HostApplicationBuilder
```

The services, their configuration and their logging, built into a host.
.NET's `HostApplicationBuilder`.

<sub>[stdlib/Hosting/Host.sl:36](../../stdlib/Hosting/Host.sl#L36)</sub>

#### Services *field*

```
ServiceCollection Services
```

What the host will make. Register hosted services here.

<sub>[stdlib/Hosting/Host.sl:41](../../stdlib/Hosting/Host.sl#L41)</sub>

#### Configuration *field*

```
Configuration Configuration
```

The settings, read when the builder was made: `appsettings.json`, then
`appsettings.{EnvironmentName}.json`, both optional, then environment
variables, then the command line.

<sub>[stdlib/Hosting/Host.sl:46](../../stdlib/Hosting/Host.sl#L46)</sub>

#### Logging *field*

```
LoggingBuilder Logging
```

Where log messages go, and at what level. The console, with the levels
the `Logging` section of the configuration names, unless changed.

<sub>[stdlib/Hosting/Host.sl:50](../../stdlib/Hosting/Host.sl#L50)</sub>

#### Environment *field*

```
HostEnvironment Environment
```

Where the host runs.

<sub>[stdlib/Hosting/Host.sl:53](../../stdlib/Hosting/Host.sl#L53)</sub>

#### Build *method*

```
Result<Host, String> Build()
```

The host, its services checked as `BuildServiceProvider` checks them.

**Returns** &nbsp; the host, or every problem with the configuration files or the registrations, one per line

<sub>[stdlib/Hosting/Host.sl:84](../../stdlib/Hosting/Host.sl#L84)</sub>

### HostApplicationLifetime *class*

```
threadsafe sealed class HostApplicationLifetime : IHostApplicationLifetime
```

The lifetime a host registers.

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:47](../../stdlib/Hosting/HostApplicationLifetime.sl#L47)</sub>

#### ApplicationStarted *property*

```
CancellationToken ApplicationStarted { get; }
```

*No documentation.*

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:54](../../stdlib/Hosting/HostApplicationLifetime.sl#L54)</sub>

#### ApplicationStopping *property*

```
CancellationToken ApplicationStopping { get; }
```

*No documentation.*

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:55](../../stdlib/Hosting/HostApplicationLifetime.sl#L55)</sub>

#### ApplicationStopped *property*

```
CancellationToken ApplicationStopped { get; }
```

*No documentation.*

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:56](../../stdlib/Hosting/HostApplicationLifetime.sl#L56)</sub>

#### StopApplication *method*

```
void StopApplication()
```

*No documentation.*

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:58](../../stdlib/Hosting/HostApplicationLifetime.sl#L58)</sub>

#### ExitCode *property*

```
int ExitCode { get; set; }
```

*No documentation.*

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:60](../../stdlib/Hosting/HostApplicationLifetime.sl#L60)</sub>

### HostEnvironment *class*

```
sealed class HostEnvironment : IHostEnvironment
```

The environment a host registers.

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:86](../../stdlib/Hosting/HostApplicationLifetime.sl#L86)</sub>

#### EnvironmentName *property*

```
String EnvironmentName { get; }
```

*No documentation.*

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:99](../../stdlib/Hosting/HostApplicationLifetime.sl#L99)</sub>

#### ContentRootPath *property*

```
String ContentRootPath { get; }
```

*No documentation.*

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:100](../../stdlib/Hosting/HostApplicationLifetime.sl#L100)</sub>

#### ApplicationName *property*

```
String ApplicationName { get; }
```

*No documentation.*

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:101](../../stdlib/Hosting/HostApplicationLifetime.sl#L101)</sub>

#### IsDevelopment *property*

```
bool IsDevelopment { get; }
```

Whether this is the `Development` environment.

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:104](../../stdlib/Hosting/HostApplicationLifetime.sl#L104)</sub>

#### IsProduction *property*

```
bool IsProduction { get; }
```

Whether this is the `Production` environment.

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:107](../../stdlib/Hosting/HostApplicationLifetime.sl#L107)</sub>

### IHostApplicationLifetime *interface*

```
interface IHostApplicationLifetime
```

When the host has started, is stopping and has stopped, and how to ask it
to stop. .NET's `IHostApplicationLifetime`.

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:28](../../stdlib/Hosting/HostApplicationLifetime.sl#L28)</sub>

#### ApplicationStarted *property*

```
CancellationToken ApplicationStarted { get; }
```

Cancelled once every hosted service has started.

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:31](../../stdlib/Hosting/HostApplicationLifetime.sl#L31)</sub>

#### ApplicationStopping *property*

```
CancellationToken ApplicationStopping { get; }
```

Cancelled when the host begins to stop.

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:34](../../stdlib/Hosting/HostApplicationLifetime.sl#L34)</sub>

#### ApplicationStopped *property*

```
CancellationToken ApplicationStopped { get; }
```

Cancelled once every hosted service has stopped.

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:37](../../stdlib/Hosting/HostApplicationLifetime.sl#L37)</sub>

#### StopApplication *method*

```
void StopApplication()
```

Asks the host to stop, as Ctrl-C does. `Run` returns once it has.

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:40](../../stdlib/Hosting/HostApplicationLifetime.sl#L40)</sub>

#### ExitCode *property*

```
int ExitCode { get; set; }
```

What `Run` answers, for `Main` to return: 0 unless something sets it.

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:43](../../stdlib/Hosting/HostApplicationLifetime.sl#L43)</sub>

### IHostEnvironment *interface*

```
interface IHostEnvironment
```

Where the host runs. .NET's `IHostEnvironment`.

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:71](../../stdlib/Hosting/HostApplicationLifetime.sl#L71)</sub>

#### EnvironmentName *property*

```
String EnvironmentName { get; }
```

`Production` unless `STAINLESS_ENVIRONMENT` says otherwise:
`Development` and `Staging` are the other names in use.

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:75](../../stdlib/Hosting/HostApplicationLifetime.sl#L75)</sub>

#### ContentRootPath *property*

```
String ContentRootPath { get; }
```

The directory configuration files are read from: the working
directory when the host was built.

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:79](../../stdlib/Hosting/HostApplicationLifetime.sl#L79)</sub>

#### ApplicationName *property*

```
String ApplicationName { get; }
```

The program's name, from its path.

<sub>[stdlib/Hosting/HostApplicationLifetime.sl:82](../../stdlib/Hosting/HostApplicationLifetime.sl#L82)</sub>

### IHostedService *interface*

```
interface IHostedService
```

Something the host starts and stops. .NET's `IHostedService`.

<sub>[stdlib/Hosting/Hosting.sl:45](../../stdlib/Hosting/Hosting.sl#L45)</sub>

#### Start *method*

```
void Start(CancellationToken token)
```

Starts the service, and returns once it has: the host starts the next
one when this returns. `token` is cancelled if starting is abandoned.

<sub>[stdlib/Hosting/Hosting.sl:49](../../stdlib/Hosting/Hosting.sl#L49)</sub>

#### Stop *method*

```
void Stop(CancellationToken token)
```

Stops the service, and returns once it has, or once `token` is
cancelled because the shutdown timeout ran out.

<sub>[stdlib/Hosting/Hosting.sl:53](../../stdlib/Hosting/Hosting.sl#L53)</sub>

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

<sub>[stdlib/Hosting/Hosting.sl:126](../../stdlib/Hosting/Hosting.sl#L126)</sub>

