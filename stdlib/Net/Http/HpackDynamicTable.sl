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

module Standard.Net.Http;

import Standard.Collections;

/// The dynamic table: newest entry first, evicted from the oldest end as
/// it outgrows its size (RFC 7541 §4).
internal sealed class HpackDynamicTable
{
    private List<HpackField> _entries = new List<HpackField>();
    private nuint _size = 0u;
    private nuint _maxSize;

    internal HpackDynamicTable(nuint maxSize) => _maxSize = maxSize;

    internal nuint Count => _entries.Count;

    /// The sum of the entries' sizes.
    internal nuint Size => _size;

    internal nuint MaxSize => _maxSize;

    /// Entry `index`, counting the newest as 1.
    internal HpackField GetHpackEntry(nuint index) => _entries[index - 1u];

    /// Changes the size limit, evicting what no longer fits.
    internal void ResizeHpackTable(nuint maxSize)
    {
        _maxSize = maxSize;
        EvictHpackEntries(0u);
    }

    /// Adds `field` as the newest entry. One larger than the whole table
    /// empties it and is not added (RFC 7541 §4.4).
    internal void AddHpackEntry(HpackField field)
    {
        nuint size = field.Size;
        if (size > _maxSize)
        {
            _entries.Clear();
            _size = 0u;
            return;
        }
        EvictHpackEntries(size);
        _entries.Insert(0u, field);
        _size += size;
    }

    /// The newest entry that is exactly `name: value`, counting from 1, or
    /// zero.
    internal nuint FindHpackEntry(String name, String value)
    {
        for (nuint i = 0u; i < _entries.Count; i++)
        {
            HpackField entry = _entries[i];
            if (entry.Name == name && entry.Value == value)
                return i + 1u;
        }
        return 0u;
    }

    /// The newest entry named `name`, counting from 1, or zero.
    internal nuint FindHpackEntryName(String name)
    {
        for (nuint i = 0u; i < _entries.Count; i++)
        {
            if (_entries[i].Name == name)
                return i + 1u;
        }
        return 0u;
    }

    private void EvictHpackEntries(nuint room)
    {
        while (_entries.Count > 0u && _size + room > _maxSize)
        {
            nuint last = _entries.Count - 1u;
            _size -= _entries[last].Size;
            _entries.RemoveAt(last);
        }
    }
}
