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

/// Walks a linked list head first, following the links rather than flattening
/// them. `At` is O(n) from the head, so a cursor that used it would make
/// iterating O(n squared); this keeps the node it reached.
///
/// @typeparam T  the value type of the list being walked
/// @see LinkedList.GetEnumerator
public class LinkedListEnumerator<T> : IEnumerator<T>
{
    LinkedList<T> _source;
    nint _at;
    bool _started;

    /// A cursor over `list`, positioned before the head.
    public LinkedListEnumerator(LinkedList<T> list)
    {
        _source = list;
        _at = -1;
        _started = false;
    }

    /// Follows one link, answering false past the tail.
    public bool MoveNext()
    {
        if (!_started)
        {
            _started = true;
            _at = _source.FirstNode;
        }
        else if (_at >= 0)
        {
            _at = _source.GetNodeAfter(_at);
        }

        return _at >= 0;
    }

    /// The value in the node the last `MoveNext` reached.
    public T Current => _source.GetNodeValue(_at);
}
