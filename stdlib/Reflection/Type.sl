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

// --------------------------------------------------------------------- types

/// One type, and the way into everything it declares.
///
/// Got from `typeof(T)`, from `FindType` by name, or from a field's `FieldType` or a
/// property's `PropertyType`. Only a class or struct marked `[Reflect]` carries
/// metadata, and what it carries is its fields, properties, public events and
/// attributes; methods are not described, so there is nothing here to call.
///
/// **An enum is described where a reflected field or property names it**: its
/// members, and its attributes, which is where `[Flags]` is read.
///
/// @see FindType
public struct Type
{
    /// The runtime's record for this type, or null for one that was looked up
    /// and not found. `Exists` is the check.
    public byte* Handle;

    /// The type's name, qualified by its module.
    public String Name => Text.FromNullTerminated(sl_type_name(Handle));

    /// How many bytes an instance occupies -- the struct's own size, or for a
    /// class the size of the object including its header.
    public nuint Size => sl_type_size(Handle);

    /// How many fields the type has, inherited ones included, and automatic
    /// properties' storage among them.
    public nuint FieldCount => sl_type_field_count(Handle);

    /// The field at `index`, in declaration order with inherited fields first.
    public Field GetFieldAt(nuint index)
    {
        Field result;
        result.Handle = sl_type_field(Handle, index);
        return result;
    }

    /// How many attributes are written on the type.
    public nuint AttributeCount => sl_type_attribute_count(Handle);

    /// The attribute at `index`, in the order they were written.
    public Attribute GetAttributeAt(nuint index)
    {
        Attribute result;
        result.Handle = sl_type_attribute(Handle, index);
        return result;
    }

    /// True when this handle names a type at all. A `FieldType` on a primitive
    /// field answers false.
    public bool Exists => Handle != null;

    /// The field of that name, or a handle of null. Names are compared whole,
    /// so a serializer looking up what a document named does one pass.
    public Field FindField(String name)
    {
        for (nuint i = 0u; i < FieldCount; i++)
        {
            var field = GetFieldAt(i);
            if (field.Name == name)
                return field;
        }

        Field missing;
        missing.Handle = null;
        return missing;
    }

    /// True when the type carries an attribute of that name.
    public bool HasAttribute(String name)
    {
        for (nuint i = 0u; i < AttributeCount; i++)
        {
            if (GetAttributeAt(i).Name == name)
                return true;
        }
        return false;
    }

    /// How many properties the type has, inherited ones included.
    ///
    /// A derived class lists everything it inherited, and a virtual property
    /// it overrode appears once, at the position the base gave it, with the
    /// **derived** accessors. What that does not do is dispatch: reaching an
    /// object through `typeof(Base)` and setting a property the derived class
    /// overrode calls the base's setter, where `.Left = x` in the language
    /// would not.
    public nuint PropertyCount => sl_type_property_count(Handle);

    /// The property at `index`. An overridden property appears once, at the
    /// position the base gave it, carrying the derived accessors.
    public Property GetPropertyAt(nuint index)
    {
        Property result;
        result.Handle = sl_type_property(Handle, index);
        return result;
    }

    /// Whether this is an enum, whose members `EnumMemberCount` and the two
    /// after it describe.
    public bool IsEnum => sl_type_is_enum(Handle);

    /// How many members an enum has; zero for anything else.
    public nuint EnumMemberCount => sl_type_enum_count(Handle);

    /// An enum member's name, in declaration order.
    public String GetEnumMemberName(nuint index) =>
        Text.FromNullTerminated(sl_type_enum_name(Handle, index));

    /// An enum member's value. A property of the enum's type is read and
    /// written with `GetInteger` and `SetInteger`.
    public long GetEnumMemberValue(nuint index) => sl_type_enum_value(Handle, index);

    /// How many public events a class has, inherited ones included.
    public nuint EventCount => sl_type_event_count(Handle);

    /// The event at `index`, a base's before its derived class's.
    public Event GetEventAt(nuint index)
    {
        Event result;
        result.Type = Handle;
        result.Index = index;
        return result;
    }

    /// The property of that name, or a handle of null.
    public Property FindProperty(String name)
    {
        for (nuint i = 0u; i < PropertyCount; i++)
        {
            var property = GetPropertyAt(i);
            if (property.Name == name)
                return property;
        }

        Property missing;
        missing.Handle = null;
        return missing;
    }
}
