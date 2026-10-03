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
import Standard.Threading;

/// Makes and keeps services. .NET's `IServiceProvider`, with
/// `ServiceProviderServiceExtensions` as methods.
///
/// The root provider keeps singletons; a scope from `CreateScope` keeps its
/// own scoped services and asks the root for singletons. Every one may be used
/// from several threads: a service is made once even when two ask at once.
///
/// **Dispose, or drop the last reference, to end it.** What it made is let go,
/// `IDisposable` ones disposed first, the latest made first. A singleton that
/// keeps the provider it was made by would otherwise keep both alive for ever,
/// which `Dispose` breaks.
public sealed threadsafe class ServiceProvider : IDisposable
{
    ServiceRegistry _registry;
    ServiceProvider? _root;
    Monitor<int> _lock = new Monitor<int>(0);

    /// What this provider has made, by registration index.
    Dictionary<int, IServiceSlot> _made = new Dictionary<int, IServiceSlot>();

    List<IDisposable> _disposables = new List<IDisposable>();
    bool _disposed;

    internal ServiceProvider(ServiceRegistry registry, ServiceProvider? root)
    {
        _registry = registry;
        _root = root;
    }

    ~ServiceProvider() { Dispose(); }

    /// Whether this is a scope rather than the root.
    public bool IsScope => _root != null;

    /// The last `TService` registered, made if it has to be; or the default
    /// `[DefaultImplementation]` names; or null.
    ///
    /// A `ServiceProvider` is answered with this provider itself.
    public TService? GetService<TService>()
        where TService : class
    {
        if (ServiceKey<TService>.Id == ServiceKey<ServiceProvider>.Id)
            return this as TService;

        IServiceDescriptor? found = _registry.FindLast(ServiceKey<TService>.Id);
        if (found == null)
            return ActivatorUtilities.CreateDefault<TService>(this);
        return ResolveService<TService>((ServiceDescriptor<TService>)found);
    }

    /// The same, stopping the program, with the type's name, when there is none.
    public TService GetRequiredService<TService>()
        where TService : class
    {
        TService? found = GetService<TService>();
        if (found != null)
            return found;
        sl_fail(("no service of type '" + RuntimeHelpers.GetTypeName<TService>() +
                 "' is registered").ToPointer());
    }

    /// Every `TService` registered, in the order they were added.
    public TService[] GetServices<TService>()
        where TService : class
    {
        var found = _registry.FindAll(ServiceKey<TService>.Id);
        var provider = this;
        return Array.Create<TService>(found.Count, (nuint i) =>
            provider.ResolveService<TService>((ServiceDescriptor<TService>)found[i]));
    }

    /// A scope: scoped services asked of it are its own, and go when it does.
    public ServiceScope CreateScope()
    {
        ServiceProvider? root = _root;
        return new ServiceScope(new ServiceProvider(_registry, root ?? this));
    }

    /// Lets go of everything this provider made, disposing what is
    /// `IDisposable`, the latest made first. A second call does nothing.
    public void Dispose()
    {
        List<IDisposable> disposables;
        {
            var held = _lock.Enter();
            if (_disposed)
                return;
            _disposed = true;
            disposables = _disposables;
            _disposables = new List<IDisposable>();
            _made = new Dictionary<int, IServiceSlot>();
        }
        for (nuint i = disposables.Count; i > 0u; i--)
            disposables[i - 1u].Dispose();
    }

    // -------------------------------------------------------------- making

    TService ResolveService<TService>(ServiceDescriptor<TService> descriptor)
        where TService : class
    {
        switch (descriptor.Lifetime)
        {
            case ServiceLifetime.Transient:
                return Track<TService>(descriptor, descriptor.Make(this));
            case ServiceLifetime.Singleton:
            {
                ServiceProvider? root = _root;
                if (root != null)
                    return root.GetOrMake<TService>(descriptor);
                return GetOrMake<TService>(descriptor);
            }
            default:
                if (_root == null)
                    sl_fail(("'" + descriptor.ServiceName + "' is scoped, and was asked of the root " +
                             "provider; ask a scope from CreateScope instead").ToPointer());
                return GetOrMake<TService>(descriptor);
        }
    }

    /// The one this provider made for `descriptor`, made now if it has not been.
    /// Made outside the lock, so making it may ask for others; a second thread
    /// asking meanwhile waits for it, and the same thread asking again is a
    /// cycle, which stops the program.
    TService GetOrMake<TService>(ServiceDescriptor<TService> descriptor)
        where TService : class
    {
        int index = descriptor.Index;
        nuint me = CurrentId();
        {
            var held = _lock.Enter();
            while (true)
            {
                var slot = _made.TryGetValue(index);
                if (!slot.HasValue)
                    break;
                var made = (ServiceSlot<TService>)slot.GetValue();
                TService? value = made.Value;
                if (value != null)
                    return value;
                if (made.Maker == me)
                    sl_fail(("'" + descriptor.ImplementationName + "' depends on itself: making it " +
                             "asked for '" + descriptor.ServiceName + "' again").ToPointer());
                held.Wait();
            }
            _made.SetValue(index, new ServiceSlot<TService>(me));
        }

        TService service = descriptor.Make(this);
        Track<TService>(descriptor, service);
        {
            var held = _lock.Enter();
            var slot = _made.TryGetValue(index);
            if (slot.HasValue)
                ((ServiceSlot<TService>)slot.GetValue()).Value = service;
            held.PulseAll();
        }
        return service;
    }

    /// Keeps `service` for disposal if it is `IDisposable` and was made here.
    TService Track<TService>(ServiceDescriptor<TService> descriptor, TService service)
        where TService : class
    {
        if (descriptor.IsInstance)
            return service;
        IDisposable? disposable = service as IDisposable;
        if (disposable != null)
        {
            var held = _lock.Enter();
            _disposables.Add(disposable);
        }
        return service;
    }
}
