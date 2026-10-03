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

/// The registrations, shared by a root provider and its scopes and never
/// changed once built.
internal sealed threadsafe class ServiceRegistry
{
    List<IServiceDescriptor> _descriptors;
    Dictionary<int, List<IServiceDescriptor>> _byKey = new Dictionary<int, List<IServiceDescriptor>>();

    public ServiceRegistry(List<IServiceDescriptor> descriptors)
    {
        _descriptors = new List<IServiceDescriptor>();
        for (nuint i = 0u; i < descriptors.Count; i++)
        {
            var descriptor = descriptors[i];
            _descriptors.Add(descriptor);
            var existing = _byKey.TryGetValue(descriptor.Key);
            if (existing.HasValue)
            {
                existing.GetValue().Add(descriptor);
            }
            else
            {
                var registered = new List<IServiceDescriptor>();
                registered.Add(descriptor);
                _byKey.SetValue(descriptor.Key, registered);
            }
        }
    }

    public IServiceDescriptor? FindLast(int key)
    {
        var found = _byKey.TryGetValue(key);
        if (!found.HasValue)
            return null;
        var registered = found.GetValue();
        return registered[registered.Count - 1u];
    }

    public List<IServiceDescriptor> FindAll(int key)
    {
        var found = _byKey.TryGetValue(key);
        if (!found.HasValue)
            return new List<IServiceDescriptor>();
        return found.GetValue();
    }

    /// Every unregistered dependency, singleton holding a scoped service, and
    /// cycle, each as a sentence.
    public List<String> FindRegistrationProblems()
    {
        var problems = new List<String>();
        int self = ServiceKey<ServiceProvider>.Id;

        for (nuint i = 0u; i < _descriptors.Count; i++)
        {
            var descriptor = _descriptors[i];
            var dependencies = descriptor.Dependencies;
            for (nuint j = 0u; j < dependencies.Count; j++)
            {
                var dependency = dependencies[j];
                if (dependency.Key == self)
                    continue;
                IServiceDescriptor? target = FindLast(dependency.Key);
                if (target == null)
                {
                    if (dependency.IsRequired && !dependency.HasDefault)
                        problems.Add("'" + descriptor.ImplementationName + "' needs '" + dependency.Name +
                                     "', and nothing is registered as one");
                    continue;
                }
                if (descriptor.Lifetime == ServiceLifetime.Singleton &&
                    target.Lifetime == ServiceLifetime.Scoped)
                    problems.Add("'" + descriptor.ImplementationName + "' is a singleton and needs '" +
                                 dependency.Name + "', which is scoped: it would keep one scope's " +
                                 "for the life of the program");
            }
        }

        var state = new int[_descriptors.Count];
        var path = new List<String>();
        for (nuint i = 0u; i < _descriptors.Count; i++)
            FindCycleFrom(_descriptors[i], state, path, problems);
        return problems;
    }

    /// Depth first over each registration's last-registered dependencies:
    /// state 1 is on the path, 2 is finished.
    void FindCycleFrom(IServiceDescriptor descriptor, int[] state, List<String> path, List<String> problems)
    {
        nuint index = IndexOf(descriptor);
        if (state[index] == 2)
            return;
        if (state[index] == 1)
        {
            path.Add(descriptor.ImplementationName);
            problems.Add("a cycle: " + " -> ".Join(path.ToArray()));
            path.RemoveAt(path.Count - 1u);
            return;
        }
        state[index] = 1;
        path.Add(descriptor.ImplementationName);
        var dependencies = descriptor.Dependencies;
        for (nuint j = 0u; j < dependencies.Count; j++)
        {
            IServiceDescriptor? target = FindLast(dependencies[j].Key);
            if (target != null)
                FindCycleFrom(target, state, path, problems);
        }
        path.RemoveAt(path.Count - 1u);
        state[index] = 2;
    }

    nuint IndexOf(IServiceDescriptor descriptor)
    {
        for (nuint i = 0u; i < _descriptors.Count; i++)
        {
            if (_descriptors[i] == descriptor)
                return i;
        }
        return 0u;
    }
}
