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

/// Part of an array, as a value, which may be written through. C#'s
/// `System.Span<T>`.
///
///     Span<int> middle = numbers[1:4];
///     middle.Fill(0);
///
/// The compiler knows this struct: indexing, `Length`, cutting with `[a:b]`
/// or `[a..b]`, `foreach`, and the conversions from an array and to a
/// `ReadOnlySpan<T>` are its own, and the members here are the rest. Unlike
/// C#'s it holds the array it views, so it may be stored and returned and
/// cannot dangle.
///
/// The searching C# puts in `MemoryExtensions` -- `IndexOf`, `Contains`,
/// `SequenceEqual`, `Sort` and the rest -- is in `Standard.Collections`, as
/// free functions taking a `ReadOnlySpan<T>` or a `Span<T>`, and a call written
/// on a span reaches them.
///
/// @typeparam T  the element type; nothing is asked of it
/// @see ReadOnlySpan
public struct Span<T>
{
    // The compiler reaches these by position, so the order MUST NOT change.
    // The array is null in the empty span, whose length says it is never read.
    private T[]? _array;
    private nuint _offset;
    private nuint _length;

    /// The whole of `array`.
    ///
    /// @param array  the array to view
    public Span(T[] array)
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
    public Span(T[] array, nuint start, nuint length)
    {
        Span<T> part = array[start:][:length];
        _array = part._array;
        _offset = part._offset;
        _length = part._length;
    }

    /// A span of nothing.
    public static Span<T> Empty => default(Span<T>);

    /// Whether it has no elements.
    public bool IsEmpty => _length == 0u;

    /// Sets every element to `default(T)`, releasing whatever they held.
    ///
    /// Only for a `T` with a zero value: a span of `String` has no `Clear`,
    /// since there is nothing its elements could be set to.
    public void Clear() where T : zeroable
    {
        if (_length == 0u)
            return;

        if (!RuntimeHelpers.IsReferenceOrContainsReferences<T>())
        {
            memset((byte*)&_array![_offset], 0, _length * sizeof(T));
        }
        else
        {
            for (nuint i = 0u; i < _length; i++)
                this[i] = default(T);
        }
    }

    /// Sets every element to `value`.
    ///
    /// @param value  what each element becomes
    public void Fill(T value)
    {
        if (_length == 0u)
            return;

        if (!RuntimeHelpers.IsReferenceOrContainsReferences<T>())
        {
            // The first element, then what is filled so far copied after
            // itself, doubling each time.
            this[0u] = value;
            var start = (byte*)&_array![_offset];
            if (sizeof(T) == 1u)
            {
                memset(start, (int)*start, _length);
                return;
            }

            nuint filled = 1u;
            while (filled < _length)
            {
                nuint step = filled < _length - filled ? filled : _length - filled;
                memmove(start + filled * sizeof(T), start, step * sizeof(T));
                filled += step;
            }
        }
        else
        {
            for (nuint i = 0u; i < _length; i++)
                this[i] = value;
        }
    }

    /// Copies every element into the start of `destination`, aborting when it
    /// is shorter. The two may overlap: the elements land as they were before
    /// the copy began.
    ///
    /// @param destination  where the elements go
    /// @see Span.TryCopyTo
    public void CopyTo(Span<T> destination)
    {
        ReadOnlySpan<T> source = this;
        source.CopyTo(destination);
    }

    /// Copies every element into the start of `destination` when it is long
    /// enough, and answers whether it was.
    ///
    /// @param destination  where the elements go
    /// @returns true when the elements were copied
    public bool TryCopyTo(Span<T> destination)
    {
        ReadOnlySpan<T> source = this;
        return source.TryCopyTo(destination);
    }

    /// The elements from `start` to the end, aborting when `start` is past it.
    ///
    /// @param start  the first element of the result
    public Span<T> Slice(nuint start) => this[start:];

    /// `length` elements from `start`, aborting when they run past the end.
    ///
    /// @param start   the first element of the result
    /// @param length  how many elements it covers
    public Span<T> Slice(nuint start, nuint length) => this[start:][:length];

    /// A new array holding a copy of the elements.
    public T[] ToArray()
    {
        ReadOnlySpan<T> source = this;
        return source.ToArray();
    }

    /// Whether the two view any element in common.
    ///
    /// @param other  the span to compare with
    public bool Overlaps(ReadOnlySpan<T> other)
    {
        ReadOnlySpan<T> source = this;
        return source.Overlaps(other);
    }

    /// Whether the two view any element in common, and where `other` starts
    /// relative to this, in elements -- negative when it starts before.
    ///
    /// @param other          the span to compare with
    /// @param elementOffset  where `other` starts, counted from this one's start
    public bool Overlaps(ReadOnlySpan<T> other, out nint elementOffset)
    {
        ReadOnlySpan<T> source = this;
        return source.Overlaps(other, out elementOffset);
    }

    /// Whether the two are the same elements of the same array: C#'s rule,
    /// which compares where they are rather than what they hold.
    public static bool operator ==(Span<T> left, Span<T> right)
    {
        ReadOnlySpan<T> first = left;
        return first == right;
    }

    /// Whether the two are not the same elements of the same array.
    public static bool operator !=(Span<T> left, Span<T> right) => !(left == right);
}
