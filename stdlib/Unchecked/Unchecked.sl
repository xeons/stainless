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

/// Storage whose slots are not values yet: the one way to hold room for a
/// `T` that has no zero value.
///
/// A `String` is never null, so `new String[n]` is refused -- its elements
/// would start as nulls. A collection still needs spare capacity, and a slot
/// it has vacated still has to let go of what it held. These two functions are
/// that, and nothing else: an array whose slots are zero bytes, and a slot
/// put back to zero bytes.
///
/// **The obligation moves to whoever imports this.** A slot MUST be written
/// before it is read, and SHOULD be cleared when it is vacated so that what it
/// held is released. Nothing checks either. Reading a slot that was never
/// written hands out a null where the type says there is none, which is the
/// hole the rest of the language closes. `Array.Create` and `Array.Repeat` are
/// what a program that is not a collection wants instead.
///
/// Each compiles to exactly what `new T[n]` and `default(T)` compile to for a
/// type that has a zero value: one allocation, zeroed, and one store.
module Standard.Unchecked;

/// An array of `length` slots holding zero bytes, which are not yet values of
/// `T` unless `T` has a zero value.
///
/// @param length  how many slots
/// @typeparam T   the element type; nothing is asked of it
/// @returns the array, every slot zero bytes
public T[] NewUninitializedArray<T>(nuint length) => new T[length];

/// Releases what a slot holds and puts it back to zero bytes, so the array no
/// longer keeps it alive. The slot MUST be written again before it is read.
///
/// @param array  the array the slot is in
/// @param index  which slot; aborts when it is past the end
/// @typeparam T  the element type; nothing is asked of it
public void ClearElement<T>(T[] array, nuint index)
{
    array[index] = default(T);
}
