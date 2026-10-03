# Standard.Configuration

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Settings gathered from files, the environment and the command line into one
tree of text. .NET's `Microsoft.Extensions.Configuration`.

    var configuration = try new ConfigurationBuilder()
        .AddJsonFile("appsettings.json", optional: true)
        .AddEnvironmentVariables("APP_")
        .AddCommandLine(GetArguments())
        .Build();
    String? level = configuration.GetValue("Logging:LogLevel:Default");

**A key is a path**, its parts joined with `:`; a JSON object's members and
an array's indexes become parts, and an environment variable's `__` is one.
Keys are compared without regard to ASCII case, as .NET compares them.

**Every value is text.** A number from a JSON file is written back as text,
and `ConfigurationBinder.Bind` parses it onto the property it is for.

**A later source wins**: a value from the command line replaces the same key
from the environment, which replaces the file's.

## Contents

**Types** &nbsp; [Configuration](#configuration-class) &middot; [ConfigurationBinder](#configurationbinder-class) &middot; [ConfigurationBuilder](#configurationbuilder-class) &middot; [ConfigurationError](#configurationerror-class) &middot; [ConfigurationSection](#configurationsection-class) &middot; [IConfiguration](#iconfiguration-interface)

## Types

### Configuration *class*

```
sealed class Configuration : IConfiguration
```

A built configuration: every source's keys and values, the later winning.
.NET's `IConfigurationRoot`.

<sub>[stdlib/Configuration/Configuration.sl:47](../../stdlib/Configuration/Configuration.sl#L47)</sub>

#### GetValue *method*

```
String? GetValue(String key)
```

*No documentation.*

<sub>[stdlib/Configuration/Configuration.sl:62](../../stdlib/Configuration/Configuration.sl#L62)</sub>

#### GetValueOrDefault *method*

```
String GetValueOrDefault(String key, String fallback)
```

The value at `key`, or `fallback` when there is none.

**Parameters**

- `key` -- a path, its parts joined with `:`
- `fallback` -- what to answer instead

<sub>[stdlib/Configuration/Configuration.sl:68](../../stdlib/Configuration/Configuration.sl#L68)</sub>

#### GetSection *method*

```
ConfigurationSection GetSection(String key)
```

*No documentation.*

<sub>[stdlib/Configuration/Configuration.sl:76](../../stdlib/Configuration/Configuration.sl#L76)</sub>

#### GetChildren *method*

```
List<ConfigurationSection> GetChildren()
```

*No documentation.*

<sub>[stdlib/Configuration/Configuration.sl:78](../../stdlib/Configuration/Configuration.sl#L78)</sub>

#### GetKeys *method*

```
List<String> GetKeys()
```

Every key with a value, as first spelled, in the order first written.

<sub>[stdlib/Configuration/Configuration.sl:88](../../stdlib/Configuration/Configuration.sl#L88)</sub>

### ConfigurationBinder *class*

```
class ConfigurationBinder
```

Sets an object's properties from a section's values. .NET's
`ConfigurationBinder`.

<sub>[stdlib/Configuration/ConfigurationBinder.sl:29](../../stdlib/Configuration/ConfigurationBinder.sl#L29)</sub>

#### Bind *method*

```
static Result<bool, ConfigurationError> Bind<T>(IConfiguration section, T target)
    where T : class
```

Sets each writable property of `target` whose name a key below `section`
matches, without regard to ASCII case, parsing the text for its type:
an integer, a floating number, `true` or `false`, a `String`, or an
enum's member name. A property that is a `[Reflect]` class is bound in
place from the section below it, so its object MUST already exist --
made by the constructor. A property no key names keeps its value.

**Parameters**

- `section` -- where the values are
- `target` -- what to set

**Type parameters**

- `T` -- a `[Reflect]` class

**Returns** &nbsp; true, or the first value that does not parse, naming its key

<sub>[stdlib/Configuration/ConfigurationBinder.sl:42](../../stdlib/Configuration/ConfigurationBinder.sl#L42)</sub>

### ConfigurationBuilder *class*

```
sealed class ConfigurationBuilder
```

Where a configuration is read from, in the order added: a later source's
value for a key replaces an earlier one's. .NET's `ConfigurationBuilder`.

<sub>[stdlib/Configuration/ConfigurationBuilder.sl:28](../../stdlib/Configuration/ConfigurationBuilder.sl#L28)</sub>

#### AddJsonFile *method*

```
ConfigurationBuilder AddJsonFile(String path, bool optional)
```

The members of the JSON object in the file at `path`, flattened to
keys: `{ "Logging": { "Level": "Debug" } }` is `Logging:Level`, and an
array's elements are `Items:0`, `Items:1`.

**Parameters**

- `path` -- the file, relative to the working directory
- `optional` -- whether a missing file is skipped rather than an error

<sub>[stdlib/Configuration/ConfigurationBuilder.sl:38](../../stdlib/Configuration/ConfigurationBuilder.sl#L38)</sub>

#### AddEnvironmentVariables *method*

```
ConfigurationBuilder AddEnvironmentVariables(String prefix)
```

Every environment variable whose name starts with `prefix`, without
it, `__` in a name standing for `:`. With no prefix, every variable.

**Parameters**

- `prefix` -- what a name MUST start with, compared without regard to ASCII case

<sub>[stdlib/Configuration/ConfigurationBuilder.sl:48](../../stdlib/Configuration/ConfigurationBuilder.sl#L48)</sub>

#### AddCommandLine *method*

```
ConfigurationBuilder AddCommandLine(String[] arguments)
```

Settings written on the command line: `--key=value`, `--key value`,
`/key=value`, `/key value` and `key=value`. An argument of none of those
shapes is skipped.

**Parameters**

- `arguments` -- the program's arguments, without its own name

<sub>[stdlib/Configuration/ConfigurationBuilder.sl:59](../../stdlib/Configuration/ConfigurationBuilder.sl#L59)</sub>

#### AddInMemoryCollection *method*

```
ConfigurationBuilder AddInMemoryCollection(Dictionary<String, String> values)
```

The keys and values of `values`, as they are.

**Parameters**

- `values` -- keys joined with `:`, and their values

<sub>[stdlib/Configuration/ConfigurationBuilder.sl:68](../../stdlib/Configuration/ConfigurationBuilder.sl#L68)</sub>

#### Build *method*

```
Result<Configuration, ConfigurationError> Build()
```

Reads every source, in order.

**Returns** &nbsp; the configuration, or the first source that could not be read: a required file that is missing or is not a JSON object

<sub>[stdlib/Configuration/ConfigurationBuilder.sl:78](../../stdlib/Configuration/ConfigurationBuilder.sl#L78)</sub>

### ConfigurationError *class*

```
sealed class ConfigurationError
```

Why a configuration could not be built or bound.

<sub>[stdlib/Configuration/ConfigurationError.sl:25](../../stdlib/Configuration/ConfigurationError.sl#L25)</sub>

#### Message *field*

```
String Message
```

What went wrong, naming the file or the key.

<sub>[stdlib/Configuration/ConfigurationError.sl:28](../../stdlib/Configuration/ConfigurationError.sl#L28)</sub>

### ConfigurationSection *class*

```
sealed class ConfigurationSection : IConfiguration
```

The part of a configuration below one key. .NET's `IConfigurationSection`.

<sub>[stdlib/Configuration/ConfigurationSection.sl:27](../../stdlib/Configuration/ConfigurationSection.sl#L27)</sub>

#### Path *property*

```
String Path { get; }
```

The whole path from the root: `Logging:LogLevel`.

<sub>[stdlib/Configuration/ConfigurationSection.sl:39](../../stdlib/Configuration/ConfigurationSection.sl#L39)</sub>

#### Key *property*

```
String Key { get; }
```

The last part of the path: `LogLevel`.

<sub>[stdlib/Configuration/ConfigurationSection.sl:42](../../stdlib/Configuration/ConfigurationSection.sl#L42)</sub>

#### Value *property*

```
String? Value { get; }
```

The value at this section's own key, or null.

<sub>[stdlib/Configuration/ConfigurationSection.sl:52](../../stdlib/Configuration/ConfigurationSection.sl#L52)</sub>

#### Exists *property*

```
bool Exists { get; }
```

Whether this section has a value or anything below it.

<sub>[stdlib/Configuration/ConfigurationSection.sl:55](../../stdlib/Configuration/ConfigurationSection.sl#L55)</sub>

#### GetValue *method*

```
String? GetValue(String key)
```

*No documentation.*

<sub>[stdlib/Configuration/ConfigurationSection.sl:57](../../stdlib/Configuration/ConfigurationSection.sl#L57)</sub>

#### GetSection *method*

```
ConfigurationSection GetSection(String key)
```

*No documentation.*

<sub>[stdlib/Configuration/ConfigurationSection.sl:59](../../stdlib/Configuration/ConfigurationSection.sl#L59)</sub>

#### GetChildren *method*

```
List<ConfigurationSection> GetChildren()
```

*No documentation.*

<sub>[stdlib/Configuration/ConfigurationSection.sl:61](../../stdlib/Configuration/ConfigurationSection.sl#L61)</sub>

### IConfiguration *interface*

```
interface IConfiguration
```

What both a whole configuration and a section of it answer.
.NET's `IConfiguration`.

<sub>[stdlib/Configuration/IConfiguration.sl:28](../../stdlib/Configuration/IConfiguration.sl#L28)</sub>

#### GetValue *method*

```
String? GetValue(String key)
```

The value at `key`, below this one, or null.

**Parameters**

- `key` -- a path, its parts joined with `:`

<sub>[stdlib/Configuration/IConfiguration.sl:33](../../stdlib/Configuration/IConfiguration.sl#L33)</sub>

#### GetSection *method*

```
ConfigurationSection GetSection(String key)
```

The section at `key`, below this one. A section nothing is under exists
all the same, and answers null for every value.

**Parameters**

- `key` -- a path, its parts joined with `:`

<sub>[stdlib/Configuration/IConfiguration.sl:39](../../stdlib/Configuration/IConfiguration.sl#L39)</sub>

#### GetChildren *method*

```
List<ConfigurationSection> GetChildren()
```

The sections directly below this one, in the order first written.

<sub>[stdlib/Configuration/IConfiguration.sl:42](../../stdlib/Configuration/IConfiguration.sl#L42)</sub>

