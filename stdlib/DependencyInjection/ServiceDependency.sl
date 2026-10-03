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
