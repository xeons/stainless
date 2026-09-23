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

module Standard.Json;

import Standard.Collections;
import Standard.Reflection;
import Standard.Convert;
import Standard.Math;

// ------------------------------------------------------------------ objects

/// The members of a JSON object, in the order they were written.
///
/// An `OrderedDictionary` rather than a `Dictionary`: order is what makes a
/// document read back the way it was written, which matters for a file a
/// person edits. The cost is that a lookup is a scan -- see the note there.
public class JsonObject
{
    OrderedDictionary<String, JsonValue> _members;

    /// An object with no members.
    public JsonObject() => _members = new OrderedDictionary<String, JsonValue>();

    /// How many members there are. Members rather than distinct names: a
    /// repeated name is kept, so this can exceed the number of names.
    public nuint Count => _members.Count;

    /// The name at a position, in the order the document wrote them.
    public String GetNameAt(nuint index) => _members.GetKeyAt(index);

    /// The value at a position, pairing with `GetNameAt` at the same index.
    ///
    /// @see JsonObject.GetNameAt
    public JsonValue GetValueAt(nuint index) => _members.GetValueAt(index);

    /// Adds a member. A repeated name is kept rather than replaced, because
    /// that is what the document said; `GetValueOrNull` answers with the first.
    ///
    /// @see JsonObject.GetValueOrNull
    public void Add(String name, JsonValue value) => _members.Add(name, value);

    /// Replaces the value of a name, or adds it.
    public void SetValue(String name, JsonValue value) => _members.SetValue(name, value);

    /// Where a name is, or `None`. One lookup rather than the two that asking
    /// whether it is there and then asking for it would cost.
    public Optional<nuint> IndexOf(String name) => _members.IndexOf(name);

    /// Whether a member of that name is there. A scan, so `IndexOf` once
    /// beats this followed by a lookup.
    ///
    /// @see JsonObject.IndexOf
    public bool ContainsKey(String name) => _members.ContainsKey(name);

    /// The value of a name, or `Null` when it is not there. A document that
    /// does not mention a field and one that says `null` are the same thing to
    /// a reader that has a default already.
    public JsonValue GetValueOrNull(String name) =>
        _members.GetValueOrDefault(name, JsonValue.Null);

    /// Removes the first member of that name, answering whether there was one.
    public bool Remove(String name) => _members.Remove(name);
}
