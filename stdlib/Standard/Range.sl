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

/// The half-open run of positions between two `Index`es. What `a..b` makes
/// when it is kept rather than used at once, as C#'s `System.Range` is.
///
///     Range inner = 1..^1;
///     Span<int> middle = numbers[inner];
///
/// Either end may be left out: `..b` starts at the start and `a..` runs to
/// the end.
public struct Range
{
    private Index _start;
    private Index _end;

    /// @param start  the first position in the run
    /// @param end    the position just past the last
    public Range(Index start, Index end)
    {
        _start = start;
        _end = end;
    }

    /// The first position in the run.
    public Index Start => _start;

    /// The position just past the last.
    public Index End => _end;

    /// Every position, `..`.
    public static Range All => new Range(Index.Start, Index.End);

    /// Where the run begins in a sequence of `length` elements, and how many
    /// elements it covers. Aborts when it runs backwards or past the end, as a
    /// slice does.
    public (nuint, nuint) GetOffsetAndLength(nuint length)
    {
        nuint from = _start.GetOffset(length);
        nuint to = _end.GetOffset(length);
        if (from > to || to > length)
            sl_slice_bounds_fail(from, to, length);
        return (from, to - from);
    }
}

extern "C" void sl_slice_bounds_fail(nuint from, nuint to, nuint length);
