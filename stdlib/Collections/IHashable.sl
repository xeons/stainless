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

module Standard.Collections;

/// A value that can be a key in a hash table.
///
/// Two values that are `Equals` each other must return the same `GetHashCode`;
/// two that are not may still collide, and the table handles it. A type that
/// implements this should implement `IEquatable<T>` as well, since a hash on
/// its own only narrows the search.
public interface IHashable
{
    /// A number standing in for this value. The same value must give the same
    /// number for as long as it is a key in a table, which means hashing only
    /// the parts a key is not going to have changed under it.
    nuint GetHashCode();
}
