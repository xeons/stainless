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

module Standard.Xml;

import Standard.Collections;
import Standard.Reflection;
import Standard.Convert;
import Standard.Math;

// --------------------------------------------------------------- attributes

/// An element's attributes, in the order they were written.
///
/// The same `OrderedDictionary` a JSON object's members are, and for the same
/// reason: an attribute list that came back reordered is a document nobody
/// wrote.
public class XmlAttributes
{
    OrderedDictionary<String, String> _entries;

    /// An empty attribute list.
    public XmlAttributes() => _entries = new OrderedDictionary<String, String>();

    /// How many attributes there are.
    public nuint Count => _entries.Count;

    /// The name at a position, in the order they were written.
    public String GetNameAt(nuint index) => _entries.GetKeyAt(index);

    /// The value at a position, pairing with `GetNameAt` at the same index.
    ///
    /// @see XmlAttributes.GetNameAt
    public String GetValueAt(nuint index) => _entries.GetValueAt(index);

    /// Appends an attribute without looking for the name first. A parsed
    /// document cannot reach here with a repeat -- that is
    /// `XmlError.DuplicateAttribute` -- so this is for building one.
    ///
    /// @param name   the attribute name
    /// @param value  the text it carries, unescaped
    /// @see XmlError.DuplicateAttribute
    public void Add(String name, String value) => _entries.Add(name, value);

    /// Sets the value of a name, adding it if it is new. A replaced name keeps
    /// the position it had.
    ///
    /// @param name   the attribute name
    /// @param value  the text it is to carry, unescaped
    public void SetValue(String name, String value) => _entries.SetValue(name, value);

    /// Where a name is, or `None`.
    public Optional<nuint> IndexOf(String name) => _entries.IndexOf(name);

    /// Whether an attribute of that name is there.
    public bool ContainsKey(String name) => _entries.ContainsKey(name);

    /// The value of an attribute, or the fallback when it is not there.
    ///
    /// @param name      the attribute to look for
    /// @param fallback  what to answer when there is no such attribute
    public String GetValueOrDefault(String name, String fallback) =>
        _entries.GetValueOrDefault(name, fallback);

    /// Removes an attribute, answering whether it was there.
    public bool Remove(String name) => _entries.Remove(name);
}
