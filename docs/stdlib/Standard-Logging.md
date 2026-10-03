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

<sub>[stdlib/Logging/ConsoleLoggerProvider.sl:33](../../stdlib/Logging/ConsoleLoggerProvider.sl#L33)</sub>

#### CreateLogger *method*

```
ILogger CreateLogger(String category)
```

*No documentation.*

<sub>[stdlib/Logging/ConsoleLoggerProvider.sl:42](../../stdlib/Logging/ConsoleLoggerProvider.sl#L42)</sub>

### ILogger *interface*

```
interface ILogger
```

Writes messages for one category. .NET's `ILogger`, with its extension
methods as default members.

<sub>[stdlib/Logging/ILogger.sl:26](../../stdlib/Logging/ILogger.sl#L26)</sub>

#### Log *method*

```
void Log(LogLevel level, String message)
```

Writes `message` if `level` is enabled.

<sub>[stdlib/Logging/ILogger.sl:29](../../stdlib/Logging/ILogger.sl#L29)</sub>

#### IsEnabled *method*

```
bool IsEnabled(LogLevel level)
```

Whether a message at `level` would be written.

<sub>[stdlib/Logging/ILogger.sl:32](../../stdlib/Logging/ILogger.sl#L32)</sub>

#### LogTrace *method*

```
void LogTrace(String message)
```

*No documentation.*

<sub>[stdlib/Logging/ILogger.sl:34](../../stdlib/Logging/ILogger.sl#L34)</sub>

#### LogDebug *method*

```
void LogDebug(String message)
```

*No documentation.*

<sub>[stdlib/Logging/ILogger.sl:35](../../stdlib/Logging/ILogger.sl#L35)</sub>

#### LogInformation *method*

```
void LogInformation(String message)
```

*No documentation.*

<sub>[stdlib/Logging/ILogger.sl:36](../../stdlib/Logging/ILogger.sl#L36)</sub>

#### LogWarning *method*

```
void LogWarning(String message)
```

*No documentation.*

<sub>[stdlib/Logging/ILogger.sl:37](../../stdlib/Logging/ILogger.sl#L37)</sub>

#### LogError *method*

```
void LogError(String message)
```

*No documentation.*

<sub>[stdlib/Logging/ILogger.sl:38](../../stdlib/Logging/ILogger.sl#L38)</sub>

#### LogCritical *method*

```
void LogCritical(String message)
```

*No documentation.*

<sub>[stdlib/Logging/ILogger.sl:39](../../stdlib/Logging/ILogger.sl#L39)</sub>

### ILogger&lt;T&gt; *interface*

```
interface ILogger<T> : ILogger
```

An `ILogger` whose category is `T`'s name, for a service to ask for by
its own type. Made by `GetService` with nothing registered.

<sub>[stdlib/Logging/ILoggerOfT.sl:28](../../stdlib/Logging/ILoggerOfT.sl#L28)</sub>

### ILoggerFactory *interface*

```
interface ILoggerFactory
```

Makes a logger for each category, from every provider it has.
.NET's `ILoggerFactory`.

<sub>[stdlib/Logging/ILoggerFactory.sl:26](../../stdlib/Logging/ILoggerFactory.sl#L26)</sub>

#### CreateLogger *method*

```
ILogger CreateLogger(String category)
```

A logger writing under `category` to every provider.

<sub>[stdlib/Logging/ILoggerFactory.sl:29](../../stdlib/Logging/ILoggerFactory.sl#L29)</sub>

### ILoggerProvider *interface*

```
interface ILoggerProvider
```

Writes messages somewhere: the console, a file, a test's list.
.NET's `ILoggerProvider`.

<sub>[stdlib/Logging/ILoggerProvider.sl:26](../../stdlib/Logging/ILoggerProvider.sl#L26)</sub>

#### CreateLogger *method*

```
ILogger CreateLogger(String category)
```

A logger for `category`, which the factory has already filtered.

<sub>[stdlib/Logging/ILoggerProvider.sl:29](../../stdlib/Logging/ILoggerProvider.sl#L29)</sub>

### LogLevel *enum*

```
enum LogLevel
```

How much a message matters, least first. .NET's `LogLevel`.

<sub>[stdlib/Logging/LogLevel.sl:25](../../stdlib/Logging/LogLevel.sl#L25)</sub>

#### Trace *case*

```
Trace
```

*No documentation.*

<sub>[stdlib/Logging/LogLevel.sl:27](../../stdlib/Logging/LogLevel.sl#L27)</sub>

#### Debug *case*

```
Debug
```

*No documentation.*

<sub>[stdlib/Logging/LogLevel.sl:28](../../stdlib/Logging/LogLevel.sl#L28)</sub>

#### Information *case*

```
Information
```

*No documentation.*

<sub>[stdlib/Logging/LogLevel.sl:29](../../stdlib/Logging/LogLevel.sl#L29)</sub>

#### Warning *case*

```
Warning
```

*No documentation.*

<sub>[stdlib/Logging/LogLevel.sl:30](../../stdlib/Logging/LogLevel.sl#L30)</sub>

#### Error *case*

```
Error
```

*No documentation.*

<sub>[stdlib/Logging/LogLevel.sl:31](../../stdlib/Logging/LogLevel.sl#L31)</sub>

#### Critical *case*

```
Critical
```

*No documentation.*

<sub>[stdlib/Logging/LogLevel.sl:32](../../stdlib/Logging/LogLevel.sl#L32)</sub>

#### None *case*

```
None
```

Above every message: a minimum of `None` writes nothing.

<sub>[stdlib/Logging/LogLevel.sl:35](../../stdlib/Logging/LogLevel.sl#L35)</sub>

### Logger&lt;T&gt; *class*

```
sealed class Logger<T> : ILogger<T>
```

The `ILogger<T>` a provider makes: a logger from the factory, under `T`'s
name.

<sub>[stdlib/Logging/Logger.sl:26](../../stdlib/Logging/Logger.sl#L26)</sub>

#### Log *method*

```
void Log(LogLevel level, String message)
```

*No documentation.*

<sub>[stdlib/Logging/Logger.sl:35](../../stdlib/Logging/Logger.sl#L35)</sub>

#### IsEnabled *method*

```
bool IsEnabled(LogLevel level)
```

*No documentation.*

<sub>[stdlib/Logging/Logger.sl:37](../../stdlib/Logging/Logger.sl#L37)</sub>

### LoggerFactory *class*

```
threadsafe sealed class LoggerFactory : ILoggerFactory
```

Makes a logger for each category from its providers, the minimum level
fixed when the logger is made. .NET's `LoggerFactory`.

<sub>[stdlib/Logging/LoggerFactory.sl:29](../../stdlib/Logging/LoggerFactory.sl#L29)</sub>

#### CreateLogger *method*

```
ILogger CreateLogger(String category)
```

*No documentation.*

<sub>[stdlib/Logging/LoggerFactory.sl:42](../../stdlib/Logging/LoggerFactory.sl#L42)</sub>

### LoggingBuilder *class*

```
sealed class LoggingBuilder
```

What a `LoggerFactory` is made from: providers, and the minimum level for
each category. .NET's `ILoggingBuilder`.

<sub>[stdlib/Logging/LoggingBuilder.sl:29](../../stdlib/Logging/LoggingBuilder.sl#L29)</sub>

#### AddConsole *method*

```
LoggingBuilder AddConsole()
```

Writes to standard output, as .NET's console logger does.

<sub>[stdlib/Logging/LoggingBuilder.sl:36](../../stdlib/Logging/LoggingBuilder.sl#L36)</sub>

#### AddProvider *method*

```
LoggingBuilder AddProvider(ILoggerProvider provider)
```

Writes to `provider` as well.

<sub>[stdlib/Logging/LoggingBuilder.sl:39](../../stdlib/Logging/LoggingBuilder.sl#L39)</sub>

#### ClearProviders *method*

```
LoggingBuilder ClearProviders()
```

Forgets every provider added so far, for a program that wants none of
the defaults.

<sub>[stdlib/Logging/LoggingBuilder.sl:47](../../stdlib/Logging/LoggingBuilder.sl#L47)</sub>

#### SetMinimumLevel *method*

```
LoggingBuilder SetMinimumLevel(LogLevel level)
```

The least a message must matter to be written, where no rule says
otherwise. `Information` unless set.

<sub>[stdlib/Logging/LoggingBuilder.sl:55](../../stdlib/Logging/LoggingBuilder.sl#L55)</sub>

#### AddFilter *method*

```
LoggingBuilder AddFilter(String category, LogLevel level)
```

The least a message must matter in every category starting with
`category`; the longest matching prefix wins.

<sub>[stdlib/Logging/LoggingBuilder.sl:63](../../stdlib/Logging/LoggingBuilder.sl#L63)</sub>

#### AddConfiguration *method*

```
LoggingBuilder AddConfiguration(IConfiguration section)
```

The levels a configuration section names, as .NET reads `Logging`:
`LogLevel:Default` is the minimum, and every other key below `LogLevel`
a category prefix. A name that is not a level is skipped.

<sub>[stdlib/Logging/LoggingBuilder.sl:75](../../stdlib/Logging/LoggingBuilder.sl#L75)</sub>

#### Build *method*

```
LoggerFactory Build()
```

The factory these settings describe.

<sub>[stdlib/Logging/LoggingBuilder.sl:95](../../stdlib/Logging/LoggingBuilder.sl#L95)</sub>

## Functions

### AddLogging *function*

```
ServiceCollection AddLogging(ServiceCollection services, Action<LoggingBuilder> configure)
```

Registers `ILoggerFactory`, made from the settings `configure` gives; call
it as `services.AddLogging(...)`. `ILogger<T>` needs no registration.

<sub>[stdlib/Logging/LoggerFactory.sl:72](../../stdlib/Logging/LoggerFactory.sl#L72)</sub>

### CreateLogger *function*

```
ILogger<T> CreateLogger<T>(ILoggerFactory factory)
```

A logger under `T`'s name from `factory`; call it as
`factory.CreateLogger<T>()`.

<sub>[stdlib/Logging/Logging.sl:42](../../stdlib/Logging/Logging.sl#L42)</sub>

