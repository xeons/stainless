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

module Standard;

/// Storage for a value that may not be there yet, at no cost beside it.
///
///     Slot<String>[] room = new Slot<String>[8];
///     room[0] = "first";
///     String held = room[0].Value;
///     room[0].Clear();
///
/// `new String[n]` is refused, because its elements would start as nulls
/// where a `String` has none. A slot's zero is empty, so an array of them may
/// be made at any length; it is what a collection keeps spare capacity in.
///
/// When `T` has a zero value a slot is laid out as a `T`, and an empty one
/// reads as that zero. When `T` has none a slot is an `Optional<T>`, which is
/// as wide as `T` because a never-null reference leaves its null spare, and
/// reading an empty one stops the program.
public struct Slot<T>
{
    // The compiler gives this its type: `T`, or `Optional<T>` when `T` has no
    // zero value. It is reached through `Value` and nothing else.
    private T _value;

    /// What the slot holds. When `T` has no zero value an empty slot aborts;
    /// otherwise it reads as the zero of `T`.
    public T Value => Value;

    /// Empties the slot, releasing what it held.
    public void Clear()
    {
        this = default;
    }

    /// The values of slots that are all full, as a new array of that many.
    ///
    /// @param filled  the slots; each MUST hold a value when `T` has no zero value
    /// @returns the array
    public static T[] ToArray(ReadOnlySpan<Slot<T>> filled) =>
        Array.Create<T>(filled.Length, (i) => filled[i].Value);

    /// Fills slots from values, in order from the start of `destination`.
    ///
    /// @param source       the values
    /// @param destination  where they go; aborts when it is shorter than `source`
    public static void Copy(ReadOnlySpan<T> source, Span<Slot<T>> destination)
    {
        Span<Slot<T>> target = destination[:source.Length];
        for (nuint i = 0u; i < source.Length; i++)
            target[i] = source[i];
    }
}
