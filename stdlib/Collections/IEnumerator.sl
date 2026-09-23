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

// **A primitive, an enum and a String implement all three without saying so.**
// None of them can carry a declaration -- a primitive is not a class, an enum
// is its integer, and String belongs to the runtime -- but they are exactly the
// types people sort by and use as keys. The compiler recognises `CompareTo`,
// `Equals` and `GetHashCode` on them and lowers each to a comparison or a runtime
// call, so `Sort(numbers)` works on a `List<int>` and `Dictionary<String, V>`
// needs nothing extra.

// -------------------------------------------------------------- enumeration

/// A cursor over a sequence. `MoveNext` advances and reports whether there was
/// anything to advance to; `Current` returns what it landed on.
///
/// `foreach` does not require this interface -- it looks for the methods by
/// name, so any type with a `GetEnumerator()` can be iterated. Naming the shape
/// is still worth doing, because it lets a sequence be passed around.
///
/// @typeparam T  what the cursor lands on; nothing is asked of it
public interface IEnumerator<T>
{
    /// Advances to the next item and reports whether there was one. Must be
    /// called before the first `Current`: a fresh enumerator sits before the
    /// start rather than on the first item.
    bool MoveNext();

    /// What the last `MoveNext` landed on. Calling this before the first
    /// `MoveNext`, or after one that answered false, is a mistake the
    /// enumerator is not required to catch.
    T Current { get; }
}
