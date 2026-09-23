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

/// Shared access. There is no `SetValue`, which is the point.
///
/// @typeparam T  what the lock guards, taken from the lock rather than chosen here
public class ReadGuard<T>
{
    ReaderWriterLock<T> _owner;

    ReadGuard(ReaderWriterLock<T> held) => _owner = held;

    ~ReadGuard() { _owner.ExitReadLock(); }

    /// What the lock guards, shared with every other reader. Treat it as
    /// read-only: nothing stops a `T` with mutating methods being mutated
    /// through this, and doing so races with the other readers.
    public T Value => _owner.Held;
}
