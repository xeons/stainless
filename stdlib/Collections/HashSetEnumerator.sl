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

/// Walks a set's table, skipping the empty slots.
///
/// The same shape as `DictionaryEnumerator`, and for the same reason: the
/// materialising version built a whole `List<T>` before the first `MoveNext`,
/// so iterating a set allocated as much again as the set held.
///
/// @typeparam T  the item type of the set being walked, equatable and hashable
///               as that set requires
/// @see HashSet.GetEnumerator
/// @seealso DictionaryEnumerator
public class HashSetEnumerator<T> : IEnumerator<T> where T : IEquatable<T>, IHashable
{
    HashSet<T> _source;
    nuint _at;
    nuint _scanned;

    /// A cursor over `set`, positioned before the first item. The set is held
    /// by reference and must not be written to while the cursor is live.
    public HashSetEnumerator(HashSet<T> set)
    {
        _source = set;
        _at = 0;
        _scanned = 0;
    }

    /// Advances to the next occupied slot, answering false at the end.
    public bool MoveNext()
    {
        while (_scanned < _source.SlotCount)
        {
            _at = _scanned;
            _scanned++;
            if (_source.IsSlotFilled(_at))
                return true;
        }
        return false;
    }

    /// The item the last `MoveNext` landed on.
    public T Current => _source.GetSlotValue(_at);
}
