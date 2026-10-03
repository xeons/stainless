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

/// What the compiler writes for a container: each call below is replaced,
/// where it is bound, with code for its type argument. .NET's
/// `ActivatorUtilities`, done at compile time.
///
/// The constructor used is the class's public one; with several, the one
/// with most parameters, and two of that many are an error. A class that
/// declares none has the parameterless one. Each parameter is asked of the
/// provider by its type: `T` with `GetRequiredService<T>`, `T?` with
/// `GetService<T>`, `T[]` with `GetServices<T>`. A parameter of any other
/// kind -- a number, a struct, `ref`, `params`, one with a default -- is an
/// error saying to register a factory instead.
public static class ActivatorUtilities
{
    /// `new T(...)`, every argument asked of `provider`.
    ///
    /// @typeparam T  the class to make; MUST NOT be abstract
    /// @param provider  what the arguments are asked of
    public static T CreateInstance<T>(ServiceProvider provider)
        where T : class
        => CreateInstance<T>(provider);

    /// Calls `visitor.Visit<P>(required)` for each parameter of the constructor
    /// `CreateInstance<T>` would call, in order, and answers how many there were.
    ///
    /// @typeparam T  the class whose constructor is read
    /// @param visitor  what each parameter is reported to
    public static int VisitDependencies<T>(ServiceDependencyVisitor visitor)
        where T : class
        => VisitDependencies<T>(visitor);

    /// What `GetService<T>` makes when nothing is registered: for an
    /// instantiation of an interface marked `[DefaultImplementation]`, the class
    /// it names, made as `CreateInstance` makes one; null for anything else.
    ///
    /// @typeparam T  the service asked for
    /// @param provider  what the made class's arguments are asked of
    public static T? CreateDefault<T>(ServiceProvider provider)
        where T : class
        => CreateDefault<T>(provider);

    /// Whether `CreateDefault<T>` makes anything: a constant per `T`.
    ///
    /// @typeparam T  the service asked about
    public static bool HasDefault<T>()
        where T : class
        => HasDefault<T>();
}
