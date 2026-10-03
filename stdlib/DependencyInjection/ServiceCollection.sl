// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This file is part of the Stainless runtime library. It is free
// software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any
// later version.
//
// It is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// As an additional permission under section 7 of that License, compiling
// a program with Stainless does not by itself place that program under
// the GNU General Public License. See LICENSE.RUNTIME.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

module Standard.DependencyInjection;

import Standard.Collections;

/// The registrations a provider is built from. .NET's `IServiceCollection`.
///
/// Registering a type twice keeps both: `GetService` answers the later one and
/// `GetServices` both, in the order they were added. `TryAdd` registers only a
/// type nothing has registered yet.
public sealed class ServiceCollection
{
    List<IServiceDescriptor> _descriptors = new List<IServiceDescriptor>();

    /// What a library keeps beside these registrations while they are made,
    /// by a key of its choosing -- `Standard.Options` keeps each type's
    /// builder here, so configuring a type twice adds to one.
    public Dictionary<int, IServiceCollectionState> State = new Dictionary<int, IServiceCollectionState>();

    /// How many registrations there are.
    public nuint Count => _descriptors.Count;

    /// The registrations, in the order they were added.
    public List<IServiceDescriptor> Descriptors => _descriptors;

    /// Whether anything is registered as a `TService`.
    public bool Contains<TService>()
        where TService : class
    {
        int key = ServiceKey<TService>.Id;
        for (nuint i = 0u; i < _descriptors.Count; i++)
        {
            if (_descriptors[i].Key == key)
                return true;
        }
        return false;
    }

    // --------------------------------------------------------- singleton

    /// One `TImplementation` for the provider's life, answered for `TService`.
    public ServiceCollection AddSingleton<TService, TImplementation>()
        where TService : class
        where TImplementation : class, TService
        => AddMade<TService, TImplementation>(ServiceLifetime.Singleton);

    /// One `TService` for the provider's life: a class registered as itself.
    public ServiceCollection AddSingleton<TService>()
        where TService : class
        => AddMade<TService, TService>(ServiceLifetime.Singleton);

    /// One `TService` for the provider's life, made by `factory` the first
    /// time it is asked for.
    public ServiceCollection AddSingleton<TService>(Func<ServiceProvider, TService> factory)
        where TService : class
        => AddFactory<TService>(ServiceLifetime.Singleton, factory);

    /// `instance`, answered for `TService`. A provider does not dispose what it
    /// was given.
    public ServiceCollection AddSingletonInstance<TService>(TService instance)
        where TService : class
    {
        var descriptor = new ServiceDescriptor<TService>(
            ServiceLifetime.Singleton, RuntimeHelpers.GetTypeName<TService>(),
            new List<ServiceDependency>(), null, instance);
        return Add(descriptor);
    }

    // ------------------------------------------------------------ scoped

    /// One `TImplementation` per scope, answered for `TService`.
    public ServiceCollection AddScoped<TService, TImplementation>()
        where TService : class
        where TImplementation : class, TService
        => AddMade<TService, TImplementation>(ServiceLifetime.Scoped);

    /// One `TService` per scope.
    public ServiceCollection AddScoped<TService>()
        where TService : class
        => AddMade<TService, TService>(ServiceLifetime.Scoped);

    /// One `TService` per scope, made by `factory`.
    public ServiceCollection AddScoped<TService>(Func<ServiceProvider, TService> factory)
        where TService : class
        => AddFactory<TService>(ServiceLifetime.Scoped, factory);

    // --------------------------------------------------------- transient

    /// A new `TImplementation` each time a `TService` is asked for.
    public ServiceCollection AddTransient<TService, TImplementation>()
        where TService : class
        where TImplementation : class, TService
        => AddMade<TService, TImplementation>(ServiceLifetime.Transient);

    /// A new `TService` each time.
    public ServiceCollection AddTransient<TService>()
        where TService : class
        => AddMade<TService, TService>(ServiceLifetime.Transient);

    /// A new `TService` from `factory` each time.
    public ServiceCollection AddTransient<TService>(Func<ServiceProvider, TService> factory)
        where TService : class
        => AddFactory<TService>(ServiceLifetime.Transient, factory);

    // ----------------------------------------------------------- try add

    /// `AddSingleton<TService, TImplementation>`, unless a `TService` is registered.
    public ServiceCollection TryAddSingleton<TService, TImplementation>()
        where TService : class
        where TImplementation : class, TService
    {
        if (!Contains<TService>())
            AddSingleton<TService, TImplementation>();
        return this;
    }

    /// `AddScoped<TService, TImplementation>`, unless a `TService` is registered.
    public ServiceCollection TryAddScoped<TService, TImplementation>()
        where TService : class
        where TImplementation : class, TService
    {
        if (!Contains<TService>())
            AddScoped<TService, TImplementation>();
        return this;
    }

    /// `AddTransient<TService, TImplementation>`, unless a `TService` is registered.
    public ServiceCollection TryAddTransient<TService, TImplementation>()
        where TService : class
        where TImplementation : class, TService
    {
        if (!Contains<TService>())
            AddTransient<TService, TImplementation>();
        return this;
    }

    /// `AddSingleton<TService>(factory)`, unless a `TService` is registered.
    public ServiceCollection TryAddSingleton<TService>(Func<ServiceProvider, TService> factory)
        where TService : class
    {
        if (!Contains<TService>())
            AddSingleton<TService>(factory);
        return this;
    }

    // ------------------------------------------------------------- build

    /// A provider over these registrations, after checking that every
    /// constructor's needs are registered, that no singleton depends on a
    /// scoped service, and that nothing depends on itself. What fails is a
    /// `ServiceProviderError` listing every problem found.
    public Result<ServiceProvider, ServiceProviderError> BuildServiceProvider() =>
        BuildServiceProvider(true);

    /// The same, with the checks skipped when `validateOnBuild` is false, as
    /// .NET's option of that name does.
    public Result<ServiceProvider, ServiceProviderError> BuildServiceProvider(bool validateOnBuild)
    {
        var registry = new ServiceRegistry(_descriptors);
        if (validateOnBuild)
        {
            var problems = registry.FindRegistrationProblems();
            if (problems.Count > 0)
                return Fail(new ServiceProviderError(problems));
        }
        return Ok(new ServiceProvider(registry, null));
    }

    // ------------------------------------------------------------ shared

    ServiceCollection AddMade<TService, TImplementation>(ServiceLifetime lifetime)
        where TService : class
        where TImplementation : class, TService
    {
        var visitor = new ServiceDependencyVisitor();
        int parameters = ActivatorUtilities.VisitDependencies<TImplementation>(visitor);
        var descriptor = new ServiceDescriptor<TService>(
            lifetime, RuntimeHelpers.GetTypeName<TImplementation>(), visitor.Found,
            (ServiceProvider provider) => ActivatorUtilities.CreateInstance<TImplementation>(provider),
            null);
        return Add(descriptor);
    }

    ServiceCollection AddFactory<TService>(ServiceLifetime lifetime, Func<ServiceProvider, TService> factory)
        where TService : class
    {
        var descriptor = new ServiceDescriptor<TService>(
            lifetime, RuntimeHelpers.GetTypeName<TService>(), new List<ServiceDependency>(),
            factory, null);
        return Add(descriptor);
    }

    ServiceCollection Add<TService>(ServiceDescriptor<TService> descriptor)
        where TService : class
    {
        descriptor.Index = (int)_descriptors.Count;
        _descriptors.Add(descriptor);
        return this;
    }
}
