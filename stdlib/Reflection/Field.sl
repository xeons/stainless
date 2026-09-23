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

// -------------------------------------------------------------------- fields

/// One field of a type: where it sits, what it holds, and what was written on
/// it.
///
/// A field is the storage. Writing one goes straight past any setter, which is
/// what a serializer filling plain data wants and what a type with behaviour in
/// its accessors does not -- see `IsPropertyStorage` and `Type.FindProperty`.
///
/// @see Type.FindProperty
/// @seealso Property
public struct Field
{
    /// The runtime's record for this field, or null for one that was looked up
    /// and not found. `Type.FindField` is what answers with a null one.
    public byte* Handle;

    /// The field's name. For an automatic property's storage this is the
    /// property's name, which is why `IsPropertyStorage` has to exist.
    public String Name => Text.FromNullTerminated(sl_field_name(Handle));

    /// How many bytes from the start of the instance the field sits. Add it to
    /// an instance pointer to reach the storage directly.
    public nuint Offset => sl_field_offset(Handle);

    /// What the field holds, as one of the `Kind` constants.
    public int Kind => (int)sl_field_kind(Handle);

    /// How many attributes are written on the field.
    public nuint AttributeCount => sl_field_attribute_count(Handle);

    /// The attribute at `index`, in the order they were written.
    public Attribute GetAttributeAt(nuint index)
    {
        Attribute result;
        result.Handle = sl_field_attribute(Handle, index);
        return result;
    }

    /// True when this field is an automatic property's storage rather than a
    /// field the type declared.
    ///
    /// **It is named after the property**, so without this a walk over the
    /// field table cannot tell `Left` the storage from `Left` the property,
    /// and writing it goes straight past the setter. Which one is right
    /// depends on what is being filled: plain data wants the field, and
    /// anything whose setter does work -- a control that re-lays-out when it
    /// moves -- wants `Type.FindProperty` instead.
    ///
    /// @see Type.FindProperty
    public bool IsPropertyStorage => (sl_field_flags(Handle) & 1u) != 0u;

    /// True when an attribute of this name is written on the field.
    public bool HasAttribute(String name)
    {
        for (nuint i = 0; i < AttributeCount; i++)
        {
            if (GetAttributeAt(i).Name == name)
                return true;
        }
        return false;
    }

    /// The named attribute, if it is present. Check Has first.
    public Attribute GetAttribute(String name)
    {
        for (nuint i = 0; i < AttributeCount; i++)
        {
            var candidate = GetAttributeAt(i);
            if (candidate.Name == name)
                return candidate;
        }
        return GetAttributeAt(0);
    }

    /// True for a field whose value can be read as a whole number.
    ///
    /// The two code unit kinds were added after the numbering was fixed, so
    /// they sit past KindArray rather than beside KindChar and a range test
    /// alone no longer reaches them.
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

    /// True for a field whose value can be read as a `double` -- a `float` or
    /// a `double`. An integer field is not one: `ReadDouble` on it answers
    /// zero rather than converting.
    public bool IsFloating => Kind == KindFloat || Kind == KindDouble;

    /// True for a field this module can read and write by value: a number, a
    /// bool or a String. Everything else is an aggregate, reached through
    /// `FieldType` and walked rather than copied.
    public bool IsSimple
    {
        get
        {
            return IsInteger || IsFloating || Kind == KindBool || Kind == KindString;
        }
    }

    /// The type of a field that holds one, or a handle of null.
    ///
    /// Set for a class, an interface and a struct; null for a primitive, whose
    /// `Kind` is the whole of what there is to know. It is what makes a
    /// nested object reachable: with the address of the field and the type of
    /// what is in it, the walk continues without any of it being typed.
    public Type FieldType
    {
        get
        {
            Type result;
            result.Handle = sl_field_type(Handle);
            return result;
        }
    }

    /// True when this field holds something with fields of its own.
    public bool IsAggregate
    {
        get
        {
            var kind = Kind;
            return kind == KindClass || kind == KindStruct;
        }
    }

    /// What an array field's elements are. `KindNone` for anything else.
    public int ElementKind => (int)sl_field_element_kind(Handle);

    /// The type of an array's elements, when they have one.
    public Type ElementType
    {
        get
        {
            Type result;
            result.Handle = sl_field_element_type(Handle);
            return result;
        }
    }

    /// How far apart an array's elements sit, in bytes. Zero for a field that
    /// is not an array.
    public nuint ElementSize => sl_field_element_size(Handle);

    /// True when this field is an array whose elements can be read one by one.
    ///
    /// A slice answers false: it is three words rather than a reference, so
    /// its elements are not where this arithmetic would look.
    public bool IsArray => Kind == KindArray && ElementSize > 0u;

    /// True when this field can be walked into: it holds an aggregate, and
    /// that aggregate carries field metadata of its own.
    ///
    /// The second half is what tells a `[Reflect]` type from a `List<T>`.
    /// Both are classes; only one has anything to walk, and a walk into the
    /// other finds no fields and reports an empty object -- which is a lie
    /// about a list that had things in it.
    public bool IsWalkable
    {
        get
        {
            if (!IsAggregate)
                return false;
            var inner = FieldType;
            return inner.Exists && inner.HasAttribute("Reflect");
        }
    }
}
