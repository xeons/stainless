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

/// One constructor parameter of a registered implementation: the service it
/// asks for, and whether the provider must have one.
public struct ServiceDependency
{
    /// The service's `ServiceKey<T>.Id`.
    public int Key;

    /// The service type's name, for messages.
    public String Name;

    /// True for a `T` parameter, false for a `T?` or a `T[]`, which can be
    /// answered with null or nothing.
    public bool IsRequired;

    /// Whether `GetService` makes one even unregistered, as it does for an
    /// interface marked `[DefaultImplementation]`.
    public bool HasDefault;
}

/// What a `ServiceCollection` holds for each registration, whatever its type.
public interface IServiceDescriptor
{
    /// The registered service type's `ServiceKey<T>.Id`.
    int Key { get; }

    /// The registered service type's name.
    String ServiceName { get; }

    /// What is made, for messages: the implementation type, or the service
    /// type itself for a factory or an instance.
    String ImplementationName { get; }

    ServiceLifetime Lifetime { get; }

    /// What the implementation's constructor asks for. Empty for a factory,
    /// whose needs are not known until it runs.
    List<ServiceDependency> Dependencies { get; }
}

/// A registration of a `T`: made by a factory, or given as an instance.
public sealed class ServiceDescriptor<T> : IServiceDescriptor
    where T : class
{
    ServiceLifetime _lifetime;
    String _implementation;
    List<ServiceDependency> _dependencies;
    Func<ServiceProvider, T>? _factory;
    T? _instance;

    /// Where this registration is in its collection, which is what a provider
    /// keys what it made by.
    internal int Index;

    internal ServiceDescriptor(
        ServiceLifetime lifetime, String implementation, List<ServiceDependency> dependencies,
        Func<ServiceProvider, T>? factory, T? instance)
    {
        _lifetime = lifetime;
        _implementation = implementation;
        _dependencies = dependencies;
        _factory = factory;
        _instance = instance;
    }

    public int Key => ServiceKey<T>.Id;

    public String ServiceName => RuntimeHelpers.GetTypeName<T>();

    public String ImplementationName => _implementation;

    public ServiceLifetime Lifetime => _lifetime;

    public List<ServiceDependency> Dependencies => _dependencies;

    /// Whether this registration was given its object rather than told how to
    /// make one. A provider does not dispose what it was given.
    internal bool IsInstance => _instance != null;

    /// Makes the service, or answers the instance it was given.
    internal T Make(ServiceProvider provider)
    {
        T? instance = _instance;
        if (instance != null)
            return instance;
        Func<ServiceProvider, T>? factory = _factory;
        if (factory != null)
            return factory(provider);
        sl_fail("a service registration has neither a factory nor an instance");
    }
}

/// Collects what a constructor asks for, through `ActivatorUtilities.VisitDependencies`.
public sealed class ServiceDependencyVisitor
{
    /// What has been visited, in parameter order.
    public List<ServiceDependency> Found = new List<ServiceDependency>();

    /// Records a parameter of type `T`: required for a `T`, not for a `T?` or
    /// a `T[]`.
    ///
    /// @typeparam T  the service the parameter asks for
    /// @param required  whether the provider must have one
    public void Visit<T>(bool required)
        where T : class
    {
        ServiceDependency dependency;
        dependency.Key = ServiceKey<T>.Id;
        dependency.Name = RuntimeHelpers.GetTypeName<T>();
        dependency.IsRequired = required;
        dependency.HasDefault = ActivatorUtilities.HasDefault<T>();
        Found.Add(dependency);
    }
}
