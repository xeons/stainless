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

/// Walks anything that can be counted and indexed, so one enumerator serves
/// every list rather than each list writing its own.
///
/// @typeparam T  the element type of the list being walked
public class ListEnumerator<T> : IEnumerator<T>
{
    IReadOnlyList<T> _source;
    nuint _next;

    /// A cursor over `items`, positioned before the first one.
    ///
    /// The list is held by reference rather than copied, so adding to it or
    /// removing from it while this cursor is live changes what the cursor
    /// walks. The count is read on every `MoveNext`, so a removal can end the
    /// walk early and an insertion can extend it.
    public ListEnumerator(IReadOnlyList<T> items)
    {
        _source = items;
        _next = 0;
    }

    /// Advances, answering false at the end.
    public bool MoveNext()
    {
        if (_next >= _source.Count)
            return false;
        _next++;
        return true;
    }

    /// The item the last `MoveNext` landed on.
    public T Current => _source[_next - 1];
}
