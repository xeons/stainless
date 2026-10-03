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

<sub>[stdlib/Configuration/Configuration.sl:121](../../stdlib/Configuration/Configuration.sl#L121)</sub>

#### GetValue *method*

```
String? GetValue(String key)
```

*No documentation.*

<sub>[stdlib/Configuration/Configuration.sl:136](../../stdlib/Configuration/Configuration.sl#L136)</sub>

#### GetValueOrDefault *method*

```
String GetValueOrDefault(String key, String fallback)
```

The value at `key`, or `fallback` when there is none.

**Parameters**

- `key` -- a path, its parts joined with `:`
- `fallback` -- what to answer instead

<sub>[stdlib/Configuration/Configuration.sl:142](../../stdlib/Configuration/Configuration.sl#L142)</sub>

#### GetSection *method*

```
ConfigurationSection GetSection(String key)
```

*No documentation.*

<sub>[stdlib/Configuration/Configuration.sl:150](../../stdlib/Configuration/Configuration.sl#L150)</sub>

#### GetChildren *method*

```
List<ConfigurationSection> GetChildren()
```

*No documentation.*

<sub>[stdlib/Configuration/Configuration.sl:152](../../stdlib/Configuration/Configuration.sl#L152)</sub>

#### GetKeys *method*

```
List<String> GetKeys()
```

Every key with a value, as first spelled, in the order first written.

<sub>[stdlib/Configuration/Configuration.sl:162](../../stdlib/Configuration/Configuration.sl#L162)</sub>

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

<sub>[stdlib/Configuration/ConfigurationBuilder.sl:31](../../stdlib/Configuration/ConfigurationBuilder.sl#L31)</sub>

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

<sub>[stdlib/Configuration/ConfigurationBuilder.sl:41](../../stdlib/Configuration/ConfigurationBuilder.sl#L41)</sub>

#### AddEnvironmentVariables *method*

```
ConfigurationBuilder AddEnvironmentVariables(String prefix)
```

Every environment variable whose name starts with `prefix`, without
it, `__` in a name standing for `:`. With no prefix, every variable.

**Parameters**

- `prefix` -- what a name MUST start with, compared without regard to ASCII case

<sub>[stdlib/Configuration/ConfigurationBuilder.sl:51](../../stdlib/Configuration/ConfigurationBuilder.sl#L51)</sub>

#### AddCommandLine *method*

```
ConfigurationBuilder AddCommandLine(String[] arguments)
```

Settings written on the command line: `--key=value`, `--key value`,
`/key=value`, `/key value` and `key=value`. An argument of none of those
shapes is skipped.

**Parameters**

- `arguments` -- the program's arguments, without its own name

<sub>[stdlib/Configuration/ConfigurationBuilder.sl:62](../../stdlib/Configuration/ConfigurationBuilder.sl#L62)</sub>

#### AddInMemoryCollection *method*

```
ConfigurationBuilder AddInMemoryCollection(Dictionary<String, String> values)
```

The keys and values of `values`, as they are.

**Parameters**

- `values` -- keys joined with `:`, and their values

<sub>[stdlib/Configuration/ConfigurationBuilder.sl:71](../../stdlib/Configuration/ConfigurationBuilder.sl#L71)</sub>

#### Build *method*

```
Result<Configuration, ConfigurationError> Build()
```

Reads every source, in order.

**Returns** &nbsp; the configuration, or the first source that could not be read: a required file that is missing or is not a JSON object

<sub>[stdlib/Configuration/ConfigurationBuilder.sl:81](../../stdlib/Configuration/ConfigurationBuilder.sl#L81)</sub>

### ConfigurationError *class*

```
sealed class ConfigurationError
```

Why a configuration could not be built or bound.

<sub>[stdlib/Configuration/Configuration.sl:217](../../stdlib/Configuration/Configuration.sl#L217)</sub>

#### Message *field*

```
String Message
```

What went wrong, naming the file or the key.

<sub>[stdlib/Configuration/Configuration.sl:220](../../stdlib/Configuration/Configuration.sl#L220)</sub>

### ConfigurationSection *class*

```
sealed class ConfigurationSection : IConfiguration
```

The part of a configuration below one key. .NET's `IConfigurationSection`.

<sub>[stdlib/Configuration/Configuration.sl:172](../../stdlib/Configuration/Configuration.sl#L172)</sub>

#### Path *property*

```
String Path { get; }
```

The whole path from the root: `Logging:LogLevel`.

<sub>[stdlib/Configuration/Configuration.sl:184](../../stdlib/Configuration/Configuration.sl#L184)</sub>

#### Key *property*

```
String Key { get; }
```

The last part of the path: `LogLevel`.

<sub>[stdlib/Configuration/Configuration.sl:187](../../stdlib/Configuration/Configuration.sl#L187)</sub>

#### Value *property*

```
String? Value { get; }
```

The value at this section's own key, or null.

<sub>[stdlib/Configuration/Configuration.sl:197](../../stdlib/Configuration/Configuration.sl#L197)</sub>

#### Exists *property*

```
bool Exists { get; }
```

Whether this section has a value or anything below it.

<sub>[stdlib/Configuration/Configuration.sl:200](../../stdlib/Configuration/Configuration.sl#L200)</sub>

#### GetValue *method*

```
String? GetValue(String key)
```

*No documentation.*

<sub>[stdlib/Configuration/Configuration.sl:202](../../stdlib/Configuration/Configuration.sl#L202)</sub>

#### GetSection *method*

```
ConfigurationSection GetSection(String key)
```

*No documentation.*

<sub>[stdlib/Configuration/Configuration.sl:204](../../stdlib/Configuration/Configuration.sl#L204)</sub>

#### GetChildren *method*

```
List<ConfigurationSection> GetChildren()
```

*No documentation.*

<sub>[stdlib/Configuration/Configuration.sl:206](../../stdlib/Configuration/Configuration.sl#L206)</sub>

### IConfiguration *interface*

```
interface IConfiguration
```

What both a whole configuration and a section of it answer.
.NET's `IConfiguration`.

<sub>[stdlib/Configuration/Configuration.sl:102](../../stdlib/Configuration/Configuration.sl#L102)</sub>

#### GetValue *method*

```
String? GetValue(String key)
```

The value at `key`, below this one, or null.

**Parameters**

- `key` -- a path, its parts joined with `:`

<sub>[stdlib/Configuration/Configuration.sl:107](../../stdlib/Configuration/Configuration.sl#L107)</sub>

#### GetSection *method*

```
ConfigurationSection GetSection(String key)
```

The section at `key`, below this one. A section nothing is under exists
all the same, and answers null for every value.

**Parameters**

- `key` -- a path, its parts joined with `:`

<sub>[stdlib/Configuration/Configuration.sl:113](../../stdlib/Configuration/Configuration.sl#L113)</sub>

#### GetChildren *method*

```
List<ConfigurationSection> GetChildren()
```

The sections directly below this one, in the order first written.

<sub>[stdlib/Configuration/Configuration.sl:116](../../stdlib/Configuration/Configuration.sl#L116)</sub>

