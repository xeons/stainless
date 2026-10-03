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
