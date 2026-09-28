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

import Standard.Unchecked;

/// Part of an array, as a value, which refuses a write through it. C#'s
/// `System.ReadOnlySpan<T>`, and what a function that only reads takes: an
/// array and a `Span<T>` both convert to one.
///
///     int Sum(ReadOnlySpan<int> values) { ... }
///
/// Assigning an element, lending one by `ref` or `out`, and calling a struct
/// method that writes one are refused where they are written. The array
/// underneath is not frozen: a `Span<T>` over the same elements still writes
/// them, and this sees the change.
///
/// @typeparam T  the element type; nothing is asked of it
/// @see Span
public struct ReadOnlySpan<T>
{
    // The compiler reaches these by position, so the order MUST NOT change.
    // The array is null in the empty span, whose length says it is never read.
    private T[]? _array;
    private nuint _offset;
    private nuint _length;

    /// The whole of `array`.
    ///
    /// @param array  the array to view
    public ReadOnlySpan(T[] array)
    {
        _array = array;
        _offset = 0u;
        _length = array.Length;
    }

    /// `length` elements of `array` from `start`, aborting when they run past
    /// its end.
    ///
    /// @param array   the array to view
    /// @param start   the first element in the view
    /// @param length  how many elements it covers
    public ReadOnlySpan(T[] array, nuint start, nuint length)
    {
        ReadOnlySpan<T> part = array[start:][:length];
        _array = part._array;
        _offset = part._offset;
        _length = part._length;
    }

    /// A span of nothing.
    public static ReadOnlySpan<T> Empty => default(ReadOnlySpan<T>);

    /// Whether it has no elements.
    public bool IsEmpty => _length == 0u;

    /// Copies every element into the start of `destination`, aborting when it
    /// is shorter. The two may overlap: the elements land as they were before
    /// the copy began.
    ///
    /// **Elements that hold no counted reference move as one `memmove`**;
    /// the rest are copied one at a time, so every count stays right.
    ///
    /// @param destination  where the elements go
    /// @see ReadOnlySpan.TryCopyTo
    public void CopyTo(Span<T> destination)
    {
        Span<T> target = destination[:_length];
        if (_length == 0u)
            return;

        if (!RuntimeHelpers.IsReferenceOrContainsReferences<T>())
        {
            memmove((byte*)&target._array![target._offset], (byte*)&_array![_offset],
                _length * sizeof(T));
        }
        else if (target._array == _array && target._offset > _offset)
        {
            // Front to back would overwrite what is still to be read when the
            // target starts inside the source.
            for (nuint i = _length; i > 0u; i--)
                target[i - 1u] = this[i - 1u];
        }
        else
        {
            for (nuint i = 0u; i < _length; i++)
                target[i] = this[i];
        }
    }

    /// Copies every element into the start of `destination` when it is long
    /// enough, and answers whether it was.
    ///
    /// @param destination  where the elements go
    /// @returns true when the elements were copied
    public bool TryCopyTo(Span<T> destination)
    {
        if (destination.Length < _length)
            return false;
        CopyTo(destination);
        return true;
    }

    /// The elements from `start` to the end, aborting when `start` is past it.
    ///
    /// @param start  the first element of the result
    public ReadOnlySpan<T> Slice(nuint start) => this[start:];

    /// `length` elements from `start`, aborting when they run past the end.
    ///
    /// @param start   the first element of the result
    /// @param length  how many elements it covers
    public ReadOnlySpan<T> Slice(nuint start, nuint length) => this[start:][:length];

    /// A new array holding a copy of the elements.
    public T[] ToArray()
    {
        var copy = NewUninitializedArray<T>(_length);
        CopyTo(copy);
        return copy;
    }

    /// Whether the two view any element in common.
    ///
    /// @param other  the span to compare with
    public bool Overlaps(ReadOnlySpan<T> other) =>
        _length != 0u && other._length != 0u && _array == other._array &&
        _offset < other._offset + other._length && other._offset < _offset + _length;

    /// Whether the two view any element in common, and where `other` starts
    /// relative to this, in elements -- negative when it starts before.
    ///
    /// @param other          the span to compare with
    /// @param elementOffset  where `other` starts, counted from this one's start
    public bool Overlaps(ReadOnlySpan<T> other, out nint elementOffset)
    {
        if (!Overlaps(other))
        {
            elementOffset = 0;
            return false;
        }

        elementOffset = (nint)other._offset - (nint)_offset;
        return true;
    }

    /// Whether the two are the same elements of the same array: C#'s rule,
    /// which compares where they are rather than what they hold.
    public static bool operator ==(ReadOnlySpan<T> left, ReadOnlySpan<T> right) =>
        left._array == right._array && left._offset == right._offset &&
        left._length == right._length;

    /// Whether the two are not the same elements of the same array.
    public static bool operator !=(ReadOnlySpan<T> left, ReadOnlySpan<T> right) =>
        !(left == right);
}
