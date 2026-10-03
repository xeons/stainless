# Standard.Logging

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Messages from a program's parts, filtered by level and category and
written by providers. .NET's `Microsoft.Extensions.Logging`.

    services.AddLogging((LoggingBuilder logging) => logging.AddConsole());
    // ...
    public Worker(ILogger<Worker> logger) { logger.LogInformation("started"); }

**A category is a type's name.** `ILogger<Worker>` writes under
`App.Worker`, and filters match a category by its prefix, so a rule for
`App` covers it. Nothing registers `ILogger<T>`: the interface names
`Logger<T>` as its default implementation, which a provider makes for
every `T`.

**A message is text.** Interpolation builds it where it is written, so a
call below the minimum level still pays for building it; `IsEnabled` asks
first where that matters. There are no message templates or scopes.

## Contents

**Types** &nbsp; [ConsoleLoggerProvider](#consoleloggerprovider-class) &middot; [ILogger](#ilogger-interface) &middot; [ILogger&lt;T&gt;](#iloggert-interface) &middot; [ILoggerFactory](#iloggerfactory-interface) &middot; [ILoggerProvider](#iloggerprovider-interface) &middot; [LogLevel](#loglevel-enum) &middot; [Logger&lt;T&gt;](#loggert-class) &middot; [LoggerFactory](#loggerfactory-class) &middot; [LoggingBuilder](#loggingbuilder-class)

**Functions** &nbsp; [AddLogging](#addlogging-function) &middot; [CreateLogger](#createlogger-function)

## Types

### ConsoleLoggerProvider *class*

```
threadsafe sealed class ConsoleLoggerProvider : ILoggerProvider
```

Writes to standard output in .NET's simple console format:

    info: App.Worker[0]
          Started.

The level is coloured at a terminal and plain in a file or a pipe. Each
message is one write, so two threads' messages never interleave.

<sub>[stdlib/Logging/ConsoleLogger.sl:33](../../stdlib/Logging/ConsoleLogger.sl#L33)</sub>

#### CreateLogger *method*

```
ILogger CreateLogger(String category)
```

*No documentation.*

<sub>[stdlib/Logging/ConsoleLogger.sl:42](../../stdlib/Logging/ConsoleLogger.sl#L42)</sub>

### ILogger *interface*

```
interface ILogger
```

Writes messages for one category. .NET's `ILogger`, with its extension
methods as default members.

<sub>[stdlib/Logging/Logging.sl:58](../../stdlib/Logging/Logging.sl#L58)</sub>

#### Log *method*

```
void Log(LogLevel level, String message)
```

Writes `message` if `level` is enabled.

<sub>[stdlib/Logging/Logging.sl:61](../../stdlib/Logging/Logging.sl#L61)</sub>

#### IsEnabled *method*

```
bool IsEnabled(LogLevel level)
```

Whether a message at `level` would be written.

<sub>[stdlib/Logging/Logging.sl:64](../../stdlib/Logging/Logging.sl#L64)</sub>

#### LogTrace *method*

```
void LogTrace(String message)
```

*No documentation.*

<sub>[stdlib/Logging/Logging.sl:66](../../stdlib/Logging/Logging.sl#L66)</sub>

#### LogDebug *method*

```
void LogDebug(String message)
```

*No documentation.*

<sub>[stdlib/Logging/Logging.sl:67](../../stdlib/Logging/Logging.sl#L67)</sub>

#### LogInformation *method*

```
void LogInformation(String message)
```

*No documentation.*

<sub>[stdlib/Logging/Logging.sl:68](../../stdlib/Logging/Logging.sl#L68)</sub>

#### LogWarning *method*

```
void LogWarning(String message)
```

*No documentation.*

<sub>[stdlib/Logging/Logging.sl:69](../../stdlib/Logging/Logging.sl#L69)</sub>

#### LogError *method*

```
void LogError(String message)
```

*No documentation.*

<sub>[stdlib/Logging/Logging.sl:70](../../stdlib/Logging/Logging.sl#L70)</sub>

#### LogCritical *method*

```
void LogCritical(String message)
```

*No documentation.*

<sub>[stdlib/Logging/Logging.sl:71](../../stdlib/Logging/Logging.sl#L71)</sub>

### ILogger&lt;T&gt; *interface*

```
interface ILogger<T> : ILogger
```

An `ILogger` whose category is `T`'s name, for a service to ask for by
its own type. Made by `GetService` with nothing registered.

<sub>[stdlib/Logging/Logging.sl:76](../../stdlib/Logging/Logging.sl#L76)</sub>

### ILoggerFactory *interface*

```
interface ILoggerFactory
```

Makes a logger for each category, from every provider it has.
.NET's `ILoggerFactory`.

<sub>[stdlib/Logging/Logging.sl:99](../../stdlib/Logging/Logging.sl#L99)</sub>

#### CreateLogger *method*

```
ILogger CreateLogger(String category)
```

A logger writing under `category` to every provider.

<sub>[stdlib/Logging/Logging.sl:102](../../stdlib/Logging/Logging.sl#L102)</sub>

### ILoggerProvider *interface*

```
interface ILoggerProvider
```

Writes messages somewhere: the console, a file, a test's list.
.NET's `ILoggerProvider`.

<sub>[stdlib/Logging/Logging.sl:107](../../stdlib/Logging/Logging.sl#L107)</sub>

#### CreateLogger *method*

```
ILogger CreateLogger(String category)
```

A logger for `category`, which the factory has already filtered.

<sub>[stdlib/Logging/Logging.sl:110](../../stdlib/Logging/Logging.sl#L110)</sub>

### LogLevel *enum*

```
enum LogLevel
```

How much a message matters, least first. .NET's `LogLevel`.

<sub>[stdlib/Logging/Logging.sl:43](../../stdlib/Logging/Logging.sl#L43)</sub>

#### Trace *case*

```
Trace
```

*No documentation.*

<sub>[stdlib/Logging/Logging.sl:45](../../stdlib/Logging/Logging.sl#L45)</sub>

#### Debug *case*

```
Debug
```

*No documentation.*

<sub>[stdlib/Logging/Logging.sl:46](../../stdlib/Logging/Logging.sl#L46)</sub>

#### Information *case*

```
Information
```

*No documentation.*

<sub>[stdlib/Logging/Logging.sl:47](../../stdlib/Logging/Logging.sl#L47)</sub>

#### Warning *case*

```
Warning
```

*No documentation.*

<sub>[stdlib/Logging/Logging.sl:48](../../stdlib/Logging/Logging.sl#L48)</sub>

#### Error *case*

```
Error
```

*No documentation.*

<sub>[stdlib/Logging/Logging.sl:49](../../stdlib/Logging/Logging.sl#L49)</sub>

#### Critical *case*

```
Critical
```

*No documentation.*

<sub>[stdlib/Logging/Logging.sl:50](../../stdlib/Logging/Logging.sl#L50)</sub>

#### None *case*

```
None
```

Above every message: a minimum of `None` writes nothing.

<sub>[stdlib/Logging/Logging.sl:53](../../stdlib/Logging/Logging.sl#L53)</sub>

### Logger&lt;T&gt; *class*

```
sealed class Logger<T> : ILogger<T>
```

The `ILogger<T>` a provider makes: a logger from the factory, under `T`'s
name.

<sub>[stdlib/Logging/Logging.sl:83](../../stdlib/Logging/Logging.sl#L83)</sub>

#### Log *method*

```
void Log(LogLevel level, String message)
```

*No documentation.*

<sub>[stdlib/Logging/Logging.sl:92](../../stdlib/Logging/Logging.sl#L92)</sub>

#### IsEnabled *method*

```
bool IsEnabled(LogLevel level)
```

*No documentation.*

<sub>[stdlib/Logging/Logging.sl:94](../../stdlib/Logging/Logging.sl#L94)</sub>

### LoggerFactory *class*

```
threadsafe sealed class LoggerFactory : ILoggerFactory
```

Makes a logger for each category from its providers, the minimum level
fixed when the logger is made. .NET's `LoggerFactory`.

<sub>[stdlib/Logging/LoggerFactory.sl:122](../../stdlib/Logging/LoggerFactory.sl#L122)</sub>

#### CreateLogger *method*

```
ILogger CreateLogger(String category)
```

*No documentation.*

<sub>[stdlib/Logging/LoggerFactory.sl:135](../../stdlib/Logging/LoggerFactory.sl#L135)</sub>

### LoggingBuilder *class*

```
sealed class LoggingBuilder
```

What a `LoggerFactory` is made from: providers, and the minimum level for
each category. .NET's `ILoggingBuilder`.

<sub>[stdlib/Logging/LoggerFactory.sl:37](../../stdlib/Logging/LoggerFactory.sl#L37)</sub>

#### AddConsole *method*

```
LoggingBuilder AddConsole()
```

Writes to standard output, as .NET's console logger does.

<sub>[stdlib/Logging/LoggerFactory.sl:44](../../stdlib/Logging/LoggerFactory.sl#L44)</sub>

#### AddProvider *method*

```
LoggingBuilder AddProvider(ILoggerProvider provider)
```

Writes to `provider` as well.

<sub>[stdlib/Logging/LoggerFactory.sl:47](../../stdlib/Logging/LoggerFactory.sl#L47)</sub>

#### ClearProviders *method*

```
LoggingBuilder ClearProviders()
```

Forgets every provider added so far, for a program that wants none of
the defaults.

<sub>[stdlib/Logging/LoggerFactory.sl:55](../../stdlib/Logging/LoggerFactory.sl#L55)</sub>

#### SetMinimumLevel *method*

```
LoggingBuilder SetMinimumLevel(LogLevel level)
```

The least a message must matter to be written, where no rule says
otherwise. `Information` unless set.

<sub>[stdlib/Logging/LoggerFactory.sl:63](../../stdlib/Logging/LoggerFactory.sl#L63)</sub>

#### AddFilter *method*

```
LoggingBuilder AddFilter(String category, LogLevel level)
```

The least a message must matter in every category starting with
`category`; the longest matching prefix wins.

<sub>[stdlib/Logging/LoggerFactory.sl:71](../../stdlib/Logging/LoggerFactory.sl#L71)</sub>

#### AddConfiguration *method*

```
LoggingBuilder AddConfiguration(IConfiguration section)
```

The levels a configuration section names, as .NET reads `Logging`:
`LogLevel:Default` is the minimum, and every other key below `LogLevel`
a category prefix. A name that is not a level is skipped.

<sub>[stdlib/Logging/LoggerFactory.sl:83](../../stdlib/Logging/LoggerFactory.sl#L83)</sub>

#### Build *method*

```
LoggerFactory Build()
```

The factory these settings describe.

<sub>[stdlib/Logging/LoggerFactory.sl:103](../../stdlib/Logging/LoggerFactory.sl#L103)</sub>

## Functions

### AddLogging *function*

```
ServiceCollection AddLogging(ServiceCollection services, Action<LoggingBuilder> configure)
```

Registers `ILoggerFactory`, made from the settings `configure` gives; call
it as `services.AddLogging(...)`. `ILogger<T>` needs no registration.

<sub>[stdlib/Logging/LoggerFactory.sl:188](../../stdlib/Logging/LoggerFactory.sl#L188)</sub>

### CreateLogger *function*

```
ILogger<T> CreateLogger<T>(ILoggerFactory factory)
```

A logger under `T`'s name from `factory`; call it as
`factory.CreateLogger<T>()`.

<sub>[stdlib/Logging/Logging.sl:115](../../stdlib/Logging/Logging.sl#L115)</sub>

