# Standard.DependencyInjection

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

A container that makes a program's services and hands each what its
constructor asks for. .NET's `Microsoft.Extensions.DependencyInjection`.

    var services = new ServiceCollection();
    services.AddSingleton<IClock, SystemClock>();
    services.AddScoped<IRepository, SqlRepository>();   // SqlRepository(IClock clock)
    var provider = try services.BuildServiceProvider();
    var repository = provider.CreateScope().ServiceProvider
        .GetRequiredService<IRepository>();

**The compiler writes the constructor calls.** A registration names an
implementation type, and `ActivatorUtilities.CreateInstance<T>` becomes
`new T(...)` with one argument per constructor parameter, each asked of the
provider by its type -- so a class with no usable constructor is a compile
error, not a failure on first use.

**A missing registration is found when the provider is built.** Each
registration records what its constructor needs, and
`BuildServiceProvider` checks that all of it is registered, that no
singleton depends on a scoped service, and that nothing depends on itself.

**There are no exceptions.** Asking `GetRequiredService` for what is not
registered stops the program, naming the type; `GetService` answers null.

**Services are released with their scope.** A scope ending drops what it
made, and ARC frees it; a service that is `IDisposable` is disposed first,
the latest made first. Singletons go with the root provider.

## Contents

**Types** &nbsp; [ActivatorUtilities](#activatorutilities-class) &middot; [DefaultImplementation](#defaultimplementation-attribute) &middot; [IServiceDescriptor](#iservicedescriptor-interface) &middot; [ServiceCollection](#servicecollection-class) &middot; [ServiceDependency](#servicedependency-struct) &middot; [ServiceDependencyVisitor](#servicedependencyvisitor-class) &middot; [ServiceDescriptor&lt;T&gt;](#servicedescriptort-class) &middot; [ServiceKey&lt;T&gt;](#servicekeyt-class) &middot; [ServiceLifetime](#servicelifetime-enum) &middot; [ServiceProvider](#serviceprovider-class) &middot; [ServiceProviderError](#serviceprovidererror-class) &middot; [ServiceScope](#servicescope-class)

## Types

### ActivatorUtilities *class*

```
class ActivatorUtilities
```

What the compiler writes for a container: each call below is replaced,
where it is bound, with code for its type argument. .NET's
`ActivatorUtilities`, done at compile time.

The constructor used is the class's public one; with several, the one
with most parameters, and two of that many are an error. A class that
declares none has the parameterless one. Each parameter is asked of the
provider by its type: `T` with `GetRequiredService<T>`, `T?` with
`GetService<T>`, `T[]` with `GetServices<T>`. A parameter of any other
kind -- a number, a struct, `ref`, `params`, one with a default -- is an
error saying to register a factory instead.

<sub>[stdlib/DependencyInjection/ActivatorUtilities.sl:35](../../stdlib/DependencyInjection/ActivatorUtilities.sl#L35)</sub>

#### CreateInstance *method*

```
static T CreateInstance<T>(ServiceProvider provider)
    where T : class
```

`new T(...)`, every argument asked of `provider`.

**Parameters**

- `provider` -- what the arguments are asked of

**Type parameters**

- `T` -- the class to make; MUST NOT be abstract

<sub>[stdlib/DependencyInjection/ActivatorUtilities.sl:41](../../stdlib/DependencyInjection/ActivatorUtilities.sl#L41)</sub>

#### VisitDependencies *method*

```
static int VisitDependencies<T>(ServiceDependencyVisitor visitor)
    where T : class
```

Calls `visitor.Visit<P>(required)` for each parameter of the constructor
`CreateInstance<T>` would call, in order, and answers how many there were.

**Parameters**

- `visitor` -- what each parameter is reported to

**Type parameters**

- `T` -- the class whose constructor is read

<sub>[stdlib/DependencyInjection/ActivatorUtilities.sl:50](../../stdlib/DependencyInjection/ActivatorUtilities.sl#L50)</sub>

#### CreateDefault *method*

```
static T? CreateDefault<T>(ServiceProvider provider)
    where T : class
```

What `GetService<T>` makes when nothing is registered: for an
instantiation of an interface marked `[DefaultImplementation]`, the class
it names, made as `CreateInstance` makes one; null for anything else.

**Parameters**

- `provider` -- what the made class's arguments are asked of

**Type parameters**

- `T` -- the service asked for

<sub>[stdlib/DependencyInjection/ActivatorUtilities.sl:60](../../stdlib/DependencyInjection/ActivatorUtilities.sl#L60)</sub>

#### HasDefault *method*

```
static bool HasDefault<T>()
    where T : class
```

Whether `CreateDefault<T>` makes anything: a constant per `T`.

**Type parameters**

- `T` -- the service asked about

<sub>[stdlib/DependencyInjection/ActivatorUtilities.sl:67](../../stdlib/DependencyInjection/ActivatorUtilities.sl#L67)</sub>

### DefaultImplementation *attribute*

```
attribute DefaultImplementation
```

Says which class `GetService` makes for an instantiation of a generic
interface that nothing registered: `[DefaultImplementation("App.Logger")]`
on `ILogger<T>` makes `App.Logger<T>` for any `T`. The class MUST take the
interface's type parameters in the same order.

It is how one declaration serves every instantiation, which .NET does by
registering an open generic -- impossible here, where an instantiation is
made by the compiler.

<sub>[stdlib/DependencyInjection/DependencyInjection.sl:80](../../stdlib/DependencyInjection/DependencyInjection.sl#L80)</sub>

### IServiceDescriptor *interface*

```
interface IServiceDescriptor
```

What a `ServiceCollection` holds for each registration, whatever its type.

<sub>[stdlib/DependencyInjection/ServiceDescriptor.sl:46](../../stdlib/DependencyInjection/ServiceDescriptor.sl#L46)</sub>

#### Key *property*

```
int Key { get; }
```

The registered service type's `ServiceKey<T>.Id`.

<sub>[stdlib/DependencyInjection/ServiceDescriptor.sl:49](../../stdlib/DependencyInjection/ServiceDescriptor.sl#L49)</sub>

#### ServiceName *property*

```
String ServiceName { get; }
```

The registered service type's name.

<sub>[stdlib/DependencyInjection/ServiceDescriptor.sl:52](../../stdlib/DependencyInjection/ServiceDescriptor.sl#L52)</sub>

#### ImplementationName *property*

```
String ImplementationName { get; }
```

What is made, for messages: the implementation type, or the service
type itself for a factory or an instance.

<sub>[stdlib/DependencyInjection/ServiceDescriptor.sl:56](../../stdlib/DependencyInjection/ServiceDescriptor.sl#L56)</sub>

#### Lifetime *property*

```
ServiceLifetime Lifetime { get; }
```

*No documentation.*

<sub>[stdlib/DependencyInjection/ServiceDescriptor.sl:58](../../stdlib/DependencyInjection/ServiceDescriptor.sl#L58)</sub>

#### Dependencies *property*

```
List<ServiceDependency> Dependencies { get; }
```

What the implementation's constructor asks for. Empty for a factory,
whose needs are not known until it runs.

<sub>[stdlib/DependencyInjection/ServiceDescriptor.sl:62](../../stdlib/DependencyInjection/ServiceDescriptor.sl#L62)</sub>

### ServiceCollection *class*

```
sealed class ServiceCollection
```

The registrations a provider is built from. .NET's `IServiceCollection`.

Registering a type twice keeps both: `GetService` answers the later one and
`GetServices` both, in the order they were added. `TryAdd` registers only a
type nothing has registered yet.

<sub>[stdlib/DependencyInjection/ServiceCollection.sl:31](../../stdlib/DependencyInjection/ServiceCollection.sl#L31)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many registrations there are.

<sub>[stdlib/DependencyInjection/ServiceCollection.sl:36](../../stdlib/DependencyInjection/ServiceCollection.sl#L36)</sub>

#### Descriptors *property*

```
List<IServiceDescriptor> Descriptors { get; }
```

The registrations, in the order they were added.

<sub>[stdlib/DependencyInjection/ServiceCollection.sl:39](../../stdlib/DependencyInjection/ServiceCollection.sl#L39)</sub>

#### Contains *method*

```
bool Contains<TService>()
    where TService : class
```

Whether anything is registered as a `TService`.

<sub>[stdlib/DependencyInjection/ServiceCollection.sl:42](../../stdlib/DependencyInjection/ServiceCollection.sl#L42)</sub>

#### AddSingleton *method*

```
ServiceCollection AddSingleton<TService, TImplementation>()
    where TService : class
    where TImplementation : class, TService
```

One `TImplementation` for the provider's life, answered for `TService`.

<sub>[stdlib/DependencyInjection/ServiceCollection.sl:57](../../stdlib/DependencyInjection/ServiceCollection.sl#L57)</sub>

#### AddSingleton *method*

```
ServiceCollection AddSingleton<TService>()
    where TService : class
```

One `TService` for the provider's life: a class registered as itself.

<sub>[stdlib/DependencyInjection/ServiceCollection.sl:63](../../stdlib/DependencyInjection/ServiceCollection.sl#L63)</sub>

#### AddSingleton *method*

```
ServiceCollection AddSingleton<TService>(Func<ServiceProvider, TService> factory)
    where TService : class
```

One `TService` for the provider's life, made by `factory` the first
time it is asked for.

<sub>[stdlib/DependencyInjection/ServiceCollection.sl:69](../../stdlib/DependencyInjection/ServiceCollection.sl#L69)</sub>

#### AddSingletonInstance *method*

```
ServiceCollection AddSingletonInstance<TService>(TService instance)
    where TService : class
```

`instance`, answered for `TService`. A provider does not dispose what it
was given.

<sub>[stdlib/DependencyInjection/ServiceCollection.sl:75](../../stdlib/DependencyInjection/ServiceCollection.sl#L75)</sub>

#### AddScoped *method*

```
ServiceCollection AddScoped<TService, TImplementation>()
    where TService : class
    where TImplementation : class, TService
```

One `TImplementation` per scope, answered for `TService`.

<sub>[stdlib/DependencyInjection/ServiceCollection.sl:87](../../stdlib/DependencyInjection/ServiceCollection.sl#L87)</sub>

#### AddScoped *method*

```
ServiceCollection AddScoped<TService>()
    where TService : class
```

One `TService` per scope.

<sub>[stdlib/DependencyInjection/ServiceCollection.sl:93](../../stdlib/DependencyInjection/ServiceCollection.sl#L93)</sub>

#### AddScoped *method*

```
ServiceCollection AddScoped<TService>(Func<ServiceProvider, TService> factory)
    where TService : class
```

One `TService` per scope, made by `factory`.

<sub>[stdlib/DependencyInjection/ServiceCollection.sl:98](../../stdlib/DependencyInjection/ServiceCollection.sl#L98)</sub>

#### AddTransient *method*

```
ServiceCollection AddTransient<TService, TImplementation>()
    where TService : class
    where TImplementation : class, TService
```

A new `TImplementation` each time a `TService` is asked for.

<sub>[stdlib/DependencyInjection/ServiceCollection.sl:105](../../stdlib/DependencyInjection/ServiceCollection.sl#L105)</sub>

#### AddTransient *method*

```
ServiceCollection AddTransient<TService>()
    where TService : class
```

A new `TService` each time.

<sub>[stdlib/DependencyInjection/ServiceCollection.sl:111](../../stdlib/DependencyInjection/ServiceCollection.sl#L111)</sub>

#### AddTransient *method*

```
ServiceCollection AddTransient<TService>(Func<ServiceProvider, TService> factory)
    where TService : class
```

A new `TService` from `factory` each time.

<sub>[stdlib/DependencyInjection/ServiceCollection.sl:116](../../stdlib/DependencyInjection/ServiceCollection.sl#L116)</sub>

#### TryAddSingleton *method*

```
ServiceCollection TryAddSingleton<TService, TImplementation>()
    where TService : class
    where TImplementation : class, TService
```

`AddSingleton<TService, TImplementation>`, unless a `TService` is registered.

<sub>[stdlib/DependencyInjection/ServiceCollection.sl:123](../../stdlib/DependencyInjection/ServiceCollection.sl#L123)</sub>

#### TryAddScoped *method*

```
ServiceCollection TryAddScoped<TService, TImplementation>()
    where TService : class
    where TImplementation : class, TService
```

`AddScoped<TService, TImplementation>`, unless a `TService` is registered.

<sub>[stdlib/DependencyInjection/ServiceCollection.sl:133](../../stdlib/DependencyInjection/ServiceCollection.sl#L133)</sub>

#### TryAddTransient *method*

```
ServiceCollection TryAddTransient<TService, TImplementation>()
    where TService : class
    where TImplementation : class, TService
```

`AddTransient<TService, TImplementation>`, unless a `TService` is registered.

<sub>[stdlib/DependencyInjection/ServiceCollection.sl:143](../../stdlib/DependencyInjection/ServiceCollection.sl#L143)</sub>

#### TryAddSingleton *method*

```
ServiceCollection TryAddSingleton<TService>(Func<ServiceProvider, TService> factory)
    where TService : class
```

`AddSingleton<TService>(factory)`, unless a `TService` is registered.

<sub>[stdlib/DependencyInjection/ServiceCollection.sl:153](../../stdlib/DependencyInjection/ServiceCollection.sl#L153)</sub>

#### BuildServiceProvider *method*

```
Result<ServiceProvider, ServiceProviderError> BuildServiceProvider()
```

A provider over these registrations, after checking that every
constructor's needs are registered, that no singleton depends on a
scoped service, and that nothing depends on itself. What fails is a
`ServiceProviderError` listing every problem found.

<sub>[stdlib/DependencyInjection/ServiceCollection.sl:167](../../stdlib/DependencyInjection/ServiceCollection.sl#L167)</sub>

#### BuildServiceProvider *method*

```
Result<ServiceProvider, ServiceProviderError> BuildServiceProvider(bool validateOnBuild)
```

The same, with the checks skipped when `validateOnBuild` is false, as
.NET's option of that name does.

<sub>[stdlib/DependencyInjection/ServiceCollection.sl:172](../../stdlib/DependencyInjection/ServiceCollection.sl#L172)</sub>

### ServiceDependency *struct*

```
struct ServiceDependency
```

One constructor parameter of a registered implementation: the service it
asks for, and whether the provider must have one.

<sub>[stdlib/DependencyInjection/ServiceDescriptor.sl:28](../../stdlib/DependencyInjection/ServiceDescriptor.sl#L28)</sub>

#### Key *field*

```
int Key
```

The service's `ServiceKey<T>.Id`.

<sub>[stdlib/DependencyInjection/ServiceDescriptor.sl:31](../../stdlib/DependencyInjection/ServiceDescriptor.sl#L31)</sub>

#### Name *field*

```
String Name
```

The service type's name, for messages.

<sub>[stdlib/DependencyInjection/ServiceDescriptor.sl:34](../../stdlib/DependencyInjection/ServiceDescriptor.sl#L34)</sub>

#### IsRequired *field*

```
bool IsRequired
```

True for a `T` parameter, false for a `T?` or a `T[]`, which can be
answered with null or nothing.

<sub>[stdlib/DependencyInjection/ServiceDescriptor.sl:38](../../stdlib/DependencyInjection/ServiceDescriptor.sl#L38)</sub>

#### HasDefault *field*

```
bool HasDefault
```

Whether `GetService` makes one even unregistered, as it does for an
interface marked `[DefaultImplementation]`.

<sub>[stdlib/DependencyInjection/ServiceDescriptor.sl:42](../../stdlib/DependencyInjection/ServiceDescriptor.sl#L42)</sub>

### ServiceDependencyVisitor *class*

```
sealed class ServiceDependencyVisitor
```

Collects what a constructor asks for, through `ActivatorUtilities.VisitDependencies`.

<sub>[stdlib/DependencyInjection/ServiceDescriptor.sl:118](../../stdlib/DependencyInjection/ServiceDescriptor.sl#L118)</sub>

#### Found *field*

```
List<ServiceDependency> Found
```

What has been visited, in parameter order.

<sub>[stdlib/DependencyInjection/ServiceDescriptor.sl:121](../../stdlib/DependencyInjection/ServiceDescriptor.sl#L121)</sub>

#### Visit *method*

```
void Visit<T>(bool required)
    where T : class
```

Records a parameter of type `T`: required for a `T`, not for a `T?` or
a `T[]`.

**Parameters**

- `required` -- whether the provider must have one

**Type parameters**

- `T` -- the service the parameter asks for

<sub>[stdlib/DependencyInjection/ServiceDescriptor.sl:128](../../stdlib/DependencyInjection/ServiceDescriptor.sl#L128)</sub>

### ServiceDescriptor&lt;T&gt; *class*

```
sealed class ServiceDescriptor<T> : IServiceDescriptor
    where T : class
```

A registration of a `T`: made by a factory, or given as an instance.

<sub>[stdlib/DependencyInjection/ServiceDescriptor.sl:66](../../stdlib/DependencyInjection/ServiceDescriptor.sl#L66)</sub>

#### Key *property*

```
int Key { get; }
```

*No documentation.*

<sub>[stdlib/DependencyInjection/ServiceDescriptor.sl:90](../../stdlib/DependencyInjection/ServiceDescriptor.sl#L90)</sub>

#### ServiceName *property*

```
String ServiceName { get; }
```

*No documentation.*

<sub>[stdlib/DependencyInjection/ServiceDescriptor.sl:92](../../stdlib/DependencyInjection/ServiceDescriptor.sl#L92)</sub>

#### ImplementationName *property*

```
String ImplementationName { get; }
```

*No documentation.*

<sub>[stdlib/DependencyInjection/ServiceDescriptor.sl:94](../../stdlib/DependencyInjection/ServiceDescriptor.sl#L94)</sub>

#### Lifetime *property*

```
ServiceLifetime Lifetime { get; }
```

*No documentation.*

<sub>[stdlib/DependencyInjection/ServiceDescriptor.sl:96](../../stdlib/DependencyInjection/ServiceDescriptor.sl#L96)</sub>

#### Dependencies *property*

```
List<ServiceDependency> Dependencies { get; }
```

*No documentation.*

<sub>[stdlib/DependencyInjection/ServiceDescriptor.sl:98](../../stdlib/DependencyInjection/ServiceDescriptor.sl#L98)</sub>

### ServiceKey&lt;T&gt; *class*

```
sealed class ServiceKey<T>
```

The number a service type is known by. Each instantiation has its own,
handed out before `Main` runs, so a type is a key with no reflection.

<sub>[stdlib/DependencyInjection/DependencyInjection.sl:64](../../stdlib/DependencyInjection/DependencyInjection.sl#L64)</sub>

### ServiceLifetime *enum*

```
enum ServiceLifetime
```

How long a made service is kept.

<sub>[stdlib/DependencyInjection/ServiceLifetime.sl:25](../../stdlib/DependencyInjection/ServiceLifetime.sl#L25)</sub>

#### Singleton *case*

```
Singleton
```

One for the whole provider and every scope made from it.

<sub>[stdlib/DependencyInjection/ServiceLifetime.sl:28](../../stdlib/DependencyInjection/ServiceLifetime.sl#L28)</sub>

#### Scoped *case*

```
Scoped
```

One per scope; asking the root provider for one stops the program.

<sub>[stdlib/DependencyInjection/ServiceLifetime.sl:31](../../stdlib/DependencyInjection/ServiceLifetime.sl#L31)</sub>

#### Transient *case*

```
Transient
```

A new one every time it is asked for.

<sub>[stdlib/DependencyInjection/ServiceLifetime.sl:34](../../stdlib/DependencyInjection/ServiceLifetime.sl#L34)</sub>

### ServiceProvider *class*

```
threadsafe sealed class ServiceProvider : IDisposable
```

Makes and keeps services. .NET's `IServiceProvider`, with
`ServiceProviderServiceExtensions` as methods.

The root provider keeps singletons; a scope from `CreateScope` keeps its
own scoped services and asks the root for singletons. Every one may be used
from several threads: a service is made once even when two ask at once.

**Dispose, or drop the last reference, to end it.** What it made is let go,
`IDisposable` ones disposed first, the latest made first. A singleton that
keeps the provider it was made by would otherwise keep both alive for ever,
which `Dispose` breaks.

<sub>[stdlib/DependencyInjection/ServiceProvider.sl:38](../../stdlib/DependencyInjection/ServiceProvider.sl#L38)</sub>

#### IsScope *property*

```
bool IsScope { get; }
```

Whether this is a scope rather than the root.

<sub>[stdlib/DependencyInjection/ServiceProvider.sl:59](../../stdlib/DependencyInjection/ServiceProvider.sl#L59)</sub>

#### GetService *method*

```
TService? GetService<TService>()
    where TService : class
```

The last `TService` registered, made if it has to be; or the default
`[DefaultImplementation]` names; or null.

A `ServiceProvider` is answered with this provider itself.

<sub>[stdlib/DependencyInjection/ServiceProvider.sl:65](../../stdlib/DependencyInjection/ServiceProvider.sl#L65)</sub>

#### GetRequiredService *method*

```
TService GetRequiredService<TService>()
    where TService : class
```

The same, stopping the program, with the type's name, when there is none.

<sub>[stdlib/DependencyInjection/ServiceProvider.sl:78](../../stdlib/DependencyInjection/ServiceProvider.sl#L78)</sub>

#### GetServices *method*

```
TService[] GetServices<TService>()
    where TService : class
```

Every `TService` registered, in the order they were added.

<sub>[stdlib/DependencyInjection/ServiceProvider.sl:89](../../stdlib/DependencyInjection/ServiceProvider.sl#L89)</sub>

#### CreateScope *method*

```
ServiceScope CreateScope()
```

A scope: scoped services asked of it are its own, and go when it does.

<sub>[stdlib/DependencyInjection/ServiceProvider.sl:99](../../stdlib/DependencyInjection/ServiceProvider.sl#L99)</sub>

#### Dispose *method*

```
void Dispose()
```

Lets go of everything this provider made, disposing what is
`IDisposable`, the latest made first. A second call does nothing.

<sub>[stdlib/DependencyInjection/ServiceProvider.sl:107](../../stdlib/DependencyInjection/ServiceProvider.sl#L107)</sub>

### ServiceProviderError *class*

```
sealed class ServiceProviderError
```

What `BuildServiceProvider` found wrong, every problem at once.

<sub>[stdlib/DependencyInjection/ServiceCollection.sl:218](../../stdlib/DependencyInjection/ServiceCollection.sl#L218)</sub>

#### Problems *field*

```
List<String> Problems
```

One sentence per problem.

<sub>[stdlib/DependencyInjection/ServiceCollection.sl:221](../../stdlib/DependencyInjection/ServiceCollection.sl#L221)</sub>

#### Message *property*

```
String Message { get; }
```

Every problem, one per line.

<sub>[stdlib/DependencyInjection/ServiceCollection.sl:229](../../stdlib/DependencyInjection/ServiceCollection.sl#L229)</sub>

### ServiceScope *class*

```
sealed class ServiceScope : IDisposable
```

A scope's provider, and the end of it. .NET's `IServiceScope`.

<sub>[stdlib/DependencyInjection/ServiceProvider.sl:204](../../stdlib/DependencyInjection/ServiceProvider.sl#L204)</sub>

#### ServiceProvider *property*

```
ServiceProvider ServiceProvider { get; }
```

What to ask for this scope's services.

<sub>[stdlib/DependencyInjection/ServiceProvider.sl:214](../../stdlib/DependencyInjection/ServiceProvider.sl#L214)</sub>

#### Dispose *method*

```
void Dispose()
```

Ends the scope: what it made is disposed and let go.

<sub>[stdlib/DependencyInjection/ServiceProvider.sl:217](../../stdlib/DependencyInjection/ServiceProvider.sl#L217)</sub>

