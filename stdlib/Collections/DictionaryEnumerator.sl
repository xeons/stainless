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

/// Walks a dictionary's slots, skipping the empty ones.
///
/// The order is the table's own and says nothing about insertion order; adding
/// or removing during a walk invalidates it, as it does in C#.
///
/// @typeparam TKey    the key type of the dictionary being walked, equatable
///                    and hashable as that dictionary requires
/// @typeparam TValue  its value type
/// @see Dictionary.GetEnumerator
public class DictionaryEnumerator<TKey, TValue> : IEnumerator<KeyValuePair<TKey, TValue>>
    where TKey : IEquatable<TKey>, IHashable
{
    Dictionary<TKey, TValue> _source;
    nuint _at;
    nuint _scanned;

    /// A cursor over `dictionary`, positioned before the first entry. The
    /// dictionary is held by reference and must not be written to while the
    /// cursor is live.
    public DictionaryEnumerator(Dictionary<TKey, TValue> dictionary)
    {
        _source = dictionary;
        _at = 0;
        _scanned = 0;
    }

    /// Advances to the next occupied slot, answering false at the end. Each
    /// call skips however many empty slots lie between, so a walk costs
    /// O(capacity) overall rather than O(count).
    public bool MoveNext()
    {
        while (_scanned < _source.Capacity)
        {
            _at = _scanned;
            _scanned++;
            if (_source.IsOccupied(_at))
                return true;
        }
        return false;
    }

    /// The entry the last `MoveNext` landed on, as a freshly built `KeyValuePair`.
    public KeyValuePair<TKey, TValue> Current => _source.GetPairAt(_at);
}
