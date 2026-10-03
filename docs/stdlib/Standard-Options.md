# Standard.Options

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Settings as a typed object a service asks for. .NET's
`Microsoft.Extensions.Options`.

    [Reflect]
    public class MailOptions
    {
        public String Host { get; set; } = "localhost";
        public int Port { get; set; } = 25;
    }

    services.Configure<MailOptions>(configuration.GetSection("Mail"));
    // ...
    public Mailer(IOptions<MailOptions> options) { _host = options.Value.Host; }

The object is made by its parameterless constructor, which sets the
defaults, and then bound from the section and passed to each `Configure`
action in the order they were registered, the first time it is asked for.
A value that does not parse, or a `Validate` that fails, stops the program
with the message, as .NET's `OptionsValidationException` would end it.

## Contents

**Types** &nbsp; [IOptions&lt;T&gt;](#ioptionst-interface) &middot; [Options&lt;T&gt;](#optionst-class) &middot; [OptionsBuilder&lt;T&gt;](#optionsbuildert-class)

**Functions** &nbsp; [AddOptions](#addoptions-function) &middot; [Configure](#configure-function) &middot; [Configure](#configure-function)

## Types

### IOptions&lt;T&gt; *interface*

```
interface IOptions<T>
```

A `T` made from configuration. .NET's `IOptions<T>`.

<sub>[stdlib/Options/Options.sl:51](../../stdlib/Options/Options.sl#L51)</sub>

#### Value *property*

```
T Value { get; }
```

The settings, made the first time any service asked for them.

<sub>[stdlib/Options/Options.sl:54](../../stdlib/Options/Options.sl#L54)</sub>

### Options&lt;T&gt; *class*

```
sealed class Options<T> : IOptions<T>
    where T : class
```

The `IOptions<T>` a provider makes.

<sub>[stdlib/Options/Options.sl:58](../../stdlib/Options/Options.sl#L58)</sub>

#### Value *property*

```
T Value { get; }
```

*No documentation.*

<sub>[stdlib/Options/Options.sl:68](../../stdlib/Options/Options.sl#L68)</sub>

### OptionsBuilder&lt;T&gt; *class*

```
sealed class OptionsBuilder<T> : IServiceCollectionState
    where T : new
```

How a `T` is made: the sections to bind, the actions to run, the checks to
make, in the order they were given. .NET's `OptionsBuilder<T>`.

<sub>[stdlib/Options/Options.sl:73](../../stdlib/Options/Options.sl#L73)</sub>

#### Bind *method*

```
OptionsBuilder<T> Bind(IConfiguration section)
```

Binds `section` onto the object, after any earlier step.

<sub>[stdlib/Options/Options.sl:82](../../stdlib/Options/Options.sl#L82)</sub>

#### Configure *method*

```
OptionsBuilder<T> Configure(Action<T> configure)
```

Runs `configure` on the object, after any earlier step.

<sub>[stdlib/Options/Options.sl:90](../../stdlib/Options/Options.sl#L90)</sub>

#### Validate *method*

```
OptionsBuilder<T> Validate(Predicate<T> check, String message)
```

Stops the program with `message` when `check` is false of the made
object.

<sub>[stdlib/Options/Options.sl:98](../../stdlib/Options/Options.sl#L98)</sub>

## Functions

### AddOptions *function*

```
OptionsBuilder<T> AddOptions<T>(ServiceCollection services)
    where T : new
```

Registers `IOptions<T>` and answers the builder that says how it is made;
call it as `services.AddOptions<T>()`. A second call answers the same
builder, so every step for a type adds to one.

**Type parameters**

- `T` -- a `[Reflect]` class with a parameterless constructor

<sub>[stdlib/Options/Options.sl:138](../../stdlib/Options/Options.sl#L138)</sub>

### Configure *function*

```
ServiceCollection Configure<T>(ServiceCollection services, IConfiguration section)
    where T : new
```

`T`'s settings from `section`; call it as `services.Configure<T>(section)`.

**Type parameters**

- `T` -- a `[Reflect]` class with a parameterless constructor

<sub>[stdlib/Options/Options.sl:156](../../stdlib/Options/Options.sl#L156)</sub>

### Configure *function*

```
ServiceCollection Configure<T>(ServiceCollection services, Action<T> configure)
    where T : new
```

`T`'s settings set by `configure`; call it as `services.Configure<T>(...)`.

**Type parameters**

- `T` -- a class with a parameterless constructor

<sub>[stdlib/Options/Options.sl:166](../../stdlib/Options/Options.sl#L166)</sub>

