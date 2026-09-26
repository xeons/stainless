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

/// A position in a sequence, counted from its start or back from its end.
/// What `^n` makes when it is kept rather than used at once, as C#'s
/// `System.Index` is.
///
///     Index last = ^1;
///     int x = numbers[last];
///
/// **The count is a `nuint`**, as every length here is, where C# has `int`.
/// `^n` takes any integer and converts it the way an index does, so a
/// negative one becomes a position no sequence has.
public struct Index
{
    private nuint _value;
    private bool _fromEnd;

    /// @param value    how far from the start, or back from the end
    /// @param fromEnd  whether `value` counts back from the end
    public Index(nuint value, bool fromEnd = false)
    {
        _value = value;
        _fromEnd = fromEnd;
    }

    /// How far from the start, or back from the end.
    public nuint Value => _value;

    /// Whether `Value` counts back from the end: `^1` is the last element.
    public bool IsFromEnd => _fromEnd;

    /// The first position, `0`.
    public static Index Start => new Index(0u);

    /// One past the last position, `^0`.
    public static Index End => new Index(0u, true);

    /// The position this is in a sequence of `length` elements. Nothing is
    /// checked here; the index or slice that uses the answer checks it.
    public nuint GetOffset(nuint length) => _fromEnd ? length - _value : _value;

    /// A position counted from the start, so `Index i = 3;` reads as it does in C#.
    public static implicit operator Index(nuint value) => new Index(value);
}
