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

module Standard.Reflection;

// ---------------------------------------------------------------- properties

/// A property: a name and a pair of functions, rather than a place.
///
/// This is the other half of what a type carries, and the difference from a
/// `Field` is the whole reason it exists. A field is an offset, so writing one
/// stores bytes. A property is its accessors, so writing one **runs the
/// setter** -- which is what a control that re-lays-out when it moves needs,
/// and what a serializer filling plain data does not.
///
/// Reading and writing go through `sl_property_*` in the runtime, where the
/// cast from a stored pointer to the prototype the kind implies lives. That
/// cast is the unsafe part of reflection and it is written once there.
///
/// **Indexers and static properties are not here.** An indexer's accessors
/// take arguments nothing could supply, and a static one has no instance.
///
/// @see Field
/// @seealso Type.FindProperty
public struct Property
{
    /// The runtime's record for this property, or null for one that was looked
    /// up and not found. `Exists` is the check.
    public byte* Handle;

    /// The property's name.
    public String Name => Text.FromNullTerminated(sl_property_name(Handle));

    /// What the property's type is, as one of the `Kind` constants.
    public int Kind => (int)sl_property_kind(Handle);

    /// True when this handle names a property at all; `FindProperty` answers
    /// with a null one when there is no such name.
    public bool Exists => Handle != null;

    /// Whether any code may reach it, rather than its own class and module
    /// only. The table lists both.
    public bool IsPublic => (sl_property_flags(Handle) & 1u) != 0u;

    /// False for a write-only property, and for one whose getter this build
    /// did not emit.
    public bool CanRead => sl_property_can_read(Handle);

    /// False for a read-only property -- `public int Left { get; }` -- which
    /// is worth checking before a loader decides a document was ignored.
    public bool CanWrite => sl_property_can_write(Handle);

    /// The type of an aggregate property, for walking into it. A handle of
    /// null for a primitive.
    public Type PropertyType
    {
        get
        {
            Type result;
            result.Handle = sl_property_type(Handle);
            return result;
        }
    }

    /// How many attributes are written on the property.
    public nuint AttributeCount => sl_property_attribute_count(Handle);

    /// The attribute at `index`, in the order they were written.
    public Attribute GetAttributeAt(nuint index)
    {
        Attribute result;
        result.Handle = sl_property_attribute(Handle, index);
        return result;
    }

    /// True when an attribute of this name is written on the property.
    public bool HasAttribute(String name)
    {
        for (nuint i = 0u; i < AttributeCount; i++)
        {
            if (GetAttributeAt(i).Name == name)
                return true;
        }
        return false;
    }

    /// The same three questions a `Field` answers about its kind.
    ///
    /// @value true for a property whose value can be read as a whole number
    /// @see Field.IsInteger
    public bool IsInteger
    {
        get
        {
            var kind = Kind;
            if (kind == KindChar16 || kind == KindChar32)
                return true;
            return kind >= KindChar && kind <= KindNUInt;
        }
    }

    /// True for a `float` or a `double` property.
    public bool IsFloating => Kind == KindFloat || Kind == KindDouble;

    /// True for a `String` property.
    public bool IsText => Kind == KindString;
}
