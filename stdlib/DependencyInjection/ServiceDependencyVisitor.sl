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
