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

module Standard.Threading;

/// A closure with an address.
///
/// The runtime starts a thread from a `Job` and a `byte*`, which is C's shape
/// and cannot hold a receiver. Boxing the closure in an object gives it one,
/// and the object's address is the `byte*`. One non-generic base serves both
/// `Thread` and `Future<T>`, so there is one trampoline rather than one per
/// instantiation.
///
/// **The box owns a reference, and the trampoline drops it.** The starter
/// retains the box and hands that count to the thread; `RunBoxed` releases it
/// when the body returns. Nothing else keeps it alive -- which is what makes
/// `Detach` safe, since the box outlives the `Thread` object rather than
/// belonging to it.
class Boxed
{
    public virtual void Run() { }
}
