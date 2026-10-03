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

/// A container that makes a program's services and hands each what its
/// constructor asks for. .NET's `Microsoft.Extensions.DependencyInjection`.
///
///     var services = new ServiceCollection();
///     services.AddSingleton<IClock, SystemClock>();
///     services.AddScoped<IRepository, SqlRepository>();   // SqlRepository(IClock clock)
///     var provider = try services.BuildServiceProvider();
///     var repository = provider.CreateScope().ServiceProvider
///         .GetRequiredService<IRepository>();
///
/// **The compiler writes the constructor calls.** A registration names an
/// implementation type, and `ActivatorUtilities.CreateInstance<T>` becomes
/// `new T(...)` with one argument per constructor parameter, each asked of the
/// provider by its type -- so a class with no usable constructor is a compile
/// error, not a failure on first use.
///
/// **A missing registration is found when the provider is built.** Each
/// registration records what its constructor needs, and
/// `BuildServiceProvider` checks that all of it is registered, that no
/// singleton depends on a scoped service, and that nothing depends on itself.
///
/// **There are no exceptions.** Asking `GetRequiredService` for what is not
/// registered stops the program, naming the type; `GetService` answers null.
///
/// **Services are released with their scope.** A scope ending drops what it
/// made, and ARC frees it; a service that is `IDisposable` is disposed first,
/// the latest made first. Singletons go with the root provider.
module Standard.DependencyInjection;

import Standard.Threading;

[DoesNotReturn]
extern "C" void sl_fail(byte* message);

/// The last service key handed out. Not `readonly`, which would make it
/// immortal: torn down at exit, it is not reported as still alive.
static AtomicInt s_lastServiceKey = new AtomicInt(0);

int TakeServiceKey() => s_lastServiceKey.Increment();
