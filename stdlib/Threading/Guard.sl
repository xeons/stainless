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

/// Proof that a lock is held, and the only route to what it guards.
///
/// A guard keeps its mutex alive, so the lock cannot be freed while it is
/// held. Releasing is the destructor's job; there is no `Exit` to forget.
///
/// @typeparam T  what the mutex guards, taken from the mutex rather than chosen here
public class Guard<T>
{
    Mutex<T> _owner;

    Guard(Mutex<T> held) => _owner = held;

    ~Guard() { _owner.Exit(); }

    /// What the lock guards.
    ///
    /// See the hole described on `Mutex`: what this hands back must not
    /// outlive the guard, and nothing yet enforces it.
    public T Value => _owner.ReadValue();

    /// Replaces the guarded value. For a class `T` this swaps which object is
    /// guarded; mutating the one `Value` gave back is the usual thing.
    public void SetValue(T updated) => _owner.WriteValue(updated);
}
