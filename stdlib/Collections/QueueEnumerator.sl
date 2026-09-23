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

/// Walks a queue oldest first, without copying it.
///
/// The materialising version this replaced built a whole `List<T>` before the
/// first `MoveNext`, so iterating a queue allocated as much again as the queue
/// held. A cursor over the ring costs nothing.
///
/// @typeparam T  the element type of the queue being walked
/// @see Queue.GetEnumerator
public class QueueEnumerator<T> : IEnumerator<T>
{
    Queue<T> _source;
    nuint _next;

    /// A cursor over `queue`, positioned before the oldest item.
    public QueueEnumerator(Queue<T> queue)
    {
        _source = queue;
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
    public T Current => _source.GetItemAt(_next - 1);
}
