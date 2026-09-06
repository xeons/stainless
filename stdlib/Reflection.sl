// Stainless - an experimental systems language.
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

// Reading the metadata the compiler laid down.
//
// There is no runtime machinery behind this: a reflected type's fields and
// attributes are `const` tables in the binary, and everything below is a typed
// view over them. That is why reflection works in a natively compiled language
// at all -- it is a layout agreement, not a virtual machine.
//
// A type carries metadata only when it is marked [Reflect]. Nothing else does,
// so nothing else pays for it.
module Standard.Reflection;

/// Marks a class or struct to carry field metadata in the binary.
public attribute Reflect { }

// The runtime accessors. Handles are raw pointers into static tables, which is
// why they are never freed and never counted.
extern "C" {
    byte*  sl_type_name(byte* type);
    nuint  sl_type_size(byte* type);
    nuint  sl_type_field_count(byte* type);
    byte*  sl_type_field(byte* type, nuint index);
    nuint  sl_type_attribute_count(byte* type);
    byte*  sl_type_attribute(byte* type, nuint index);

    byte*  sl_field_name(byte* field);
    nuint  sl_field_offset(byte* field);
    uint   sl_field_kind(byte* field);
    byte*  sl_field_type(byte* field);
    nuint  sl_field_attribute_count(byte* field);
    byte*  sl_field_attribute(byte* field, nuint index);

    byte*  sl_attribute_name(byte* handle);
    nuint  sl_attribute_value_count(byte* handle);
    uint   sl_attribute_value_kind(byte* handle, nuint index);
    long   sl_attribute_value_number(byte* handle, nuint index);
    byte*  sl_attribute_value_text(byte* handle, nuint index);

    long   sl_read_integer(byte* instance, byte* field);
    double sl_read_double(byte* instance, byte* field);
    bool   sl_read_bool(byte* instance, byte* field);
    byte*  sl_read_reference(byte* instance, byte* field);

    void   sl_write_integer(byte* instance, byte* field, long value);
    void   sl_write_double(byte* instance, byte* field, double value);
    void   sl_write_bool(byte* instance, byte* field, bool value);
    void   sl_write_text(byte* instance, byte* field, byte* bytes, nuint length);
    void   sl_write_reference(byte* instance, byte* field, byte* value);

    byte*  sl_type_make(byte* type);
    void   sl_release(byte* object);

    uint   sl_field_element_kind(byte* field);
    byte*  sl_field_element_type(byte* field);
    nuint  sl_field_element_size(byte* field);

    byte*  sl_array_data(byte* array);
    nuint  sl_array_length(byte* array);

    long   sl_read_at_integer(byte* address, uint kind);
    double sl_read_at_double(byte* address, uint kind);
    bool   sl_read_at_bool(byte* address);
    byte*  sl_read_at_reference(byte* address);

    void   sl_write_at_integer(byte* address, uint kind, long value);
    void   sl_write_at_double(byte* address, uint kind, double value);
    void   sl_write_at_bool(byte* address, bool value);
    void   sl_write_at_text(byte* address, byte* bytes, nuint length);
}

/// What a field holds. Kept in step with enum SlKind in the runtime.
public const int KindNone      = 0;
public const int KindBool      = 1;
public const int KindChar      = 2;
public const int KindSByte     = 3;
public const int KindShort     = 4;
public const int KindInt       = 5;
public const int KindLong      = 6;
public const int KindNInt      = 7;
public const int KindByte      = 8;
public const int KindUShort    = 9;
public const int KindUInt      = 10;
public const int KindULong     = 11;
public const int KindNUInt     = 12;
public const int KindFloat     = 13;
public const int KindDouble    = 14;
public const int KindPointer   = 15;
public const int KindString    = 16;
public const int KindClass     = 17;
public const int KindInterface = 18;
public const int KindStruct    = 19;
public const int KindArray     = 20;
public const int KindChar16    = 21;
public const int KindChar32    = 22;

// ---------------------------------------------------------------- attributes

/// One attribute as written on a declaration, with the constants it was given.
public struct Attribute {
    public byte* Handle;

    public String Name() { return Text.FromNullTerminated(sl_attribute_name(Handle)); }

    public nuint ValueCount() { return sl_attribute_value_count(Handle); }
    public int ValueKind(nuint index) { return (int)sl_attribute_value_kind(Handle, index); }

    /// The value as text. Only meaningful when ValueKind is KindString.
    public String AsText(nuint index) {
        return Text.FromNullTerminated(sl_attribute_value_text(Handle, index));
    }

    public long Number(nuint index) { return sl_attribute_value_number(Handle, index); }
}

// -------------------------------------------------------------------- fields

public struct Field {
    public byte* Handle;

    public String Name() { return Text.FromNullTerminated(sl_field_name(Handle)); }
    public nuint Offset() { return sl_field_offset(Handle); }
    public int Kind() { return (int)sl_field_kind(Handle); }

    public nuint AttributeCount() { return sl_field_attribute_count(Handle); }

    public Attribute AttributeAt(nuint index) {
        Attribute result;
        result.Handle = sl_field_attribute(Handle, index);
        return result;
    }

    /// True when an attribute of this name is written on the field.
    public bool Has(String name) {
        for (nuint i = 0; i < AttributeCount(); i = i + 1) {
            if (AttributeAt(i).Name() == name) { return true; }
        }
        return false;
    }

    /// The named attribute, if it is present. Check Has first.
    public Attribute Get(String name) {
        for (nuint i = 0; i < AttributeCount(); i = i + 1) {
            var candidate = AttributeAt(i);
            if (candidate.Name() == name) { return candidate; }
        }
        return AttributeAt(0);
    }

    /// True for a field whose value can be read as a whole number.
    ///
    /// The two code unit kinds were added after the numbering was fixed, so
    /// they sit past KindArray rather than beside KindChar and a range test
    /// alone no longer reaches them.
    public bool IsInteger() {
        var kind = Kind();
        if (kind == KindChar16 || kind == KindChar32) { return true; }
        return kind >= KindChar && kind <= KindNUInt;
    }

    public bool IsFloating() { return Kind() == KindFloat || Kind() == KindDouble; }

    /// True for a field this module can read and write by value: a number, a
    /// bool or a String. Everything else is an aggregate, reached through
    /// `TypeOf()` and walked rather than copied.
    public bool IsSimple() {
        return IsInteger() || IsFloating() || Kind() == KindBool || Kind() == KindString;
    }

    /// The type of a field that holds one, or a handle of null.
    ///
    /// Set for a class, an interface and a struct; null for a primitive, whose
    /// `Kind()` is the whole of what there is to know. It is what makes a
    /// nested object reachable: with the address of the field and the type of
    /// what is in it, the walk continues without any of it being typed.
    public Type TypeOf() {
        Type result;
        result.Handle = sl_field_type(Handle);
        return result;
    }

    /// True when this field holds something with fields of its own.
    public bool IsAggregate() {
        var kind = Kind();
        return kind == KindClass || kind == KindStruct;
    }

    /// What an array field's elements are. `KindNone` for anything else.
    public int ElementKind() { return (int)sl_field_element_kind(Handle); }

    /// The type of an array's elements, when they have one.
    public Type ElementType() {
        Type result;
        result.Handle = sl_field_element_type(Handle);
        return result;
    }

    /// How far apart an array's elements sit, in bytes. Zero for a field that
    /// is not an array.
    public nuint ElementSize() { return sl_field_element_size(Handle); }

    /// True when this field is an array whose elements can be read one by one.
    ///
    /// A slice answers false: it is three words rather than a reference, so
    /// its elements are not where this arithmetic would look.
    public bool IsArray() { return Kind() == KindArray && ElementSize() > 0u; }

    /// True when this field can be walked into: it holds an aggregate, and
    /// that aggregate carries field metadata of its own.
    ///
    /// The second half is what tells a `[Reflect]` type from a `List<T>`.
    /// Both are classes; only one has anything to walk, and a walk into the
    /// other finds no fields and reports an empty object -- which is a lie
    /// about a list that had things in it.
    public bool IsWalkable() {
        if (!IsAggregate()) { return false; }
        var inner = TypeOf();
        return inner.Exists() && inner.Has("Reflect");
    }
}

// --------------------------------------------------------------------- types

public struct Type {
    public byte* Handle;

    public String Name() { return Text.FromNullTerminated(sl_type_name(Handle)); }
    public nuint Size() { return sl_type_size(Handle); }

    public nuint FieldCount() { return sl_type_field_count(Handle); }

    public Field FieldAt(nuint index) {
        Field result;
        result.Handle = sl_type_field(Handle, index);
        return result;
    }

    public nuint AttributeCount() { return sl_type_attribute_count(Handle); }

    public Attribute AttributeAt(nuint index) {
        Attribute result;
        result.Handle = sl_type_attribute(Handle, index);
        return result;
    }

    /// True when this handle names a type at all. A `TypeOf()` on a primitive
    /// field answers false.
    public bool Exists() { return Handle != null; }

    /// The field of that name, or a handle of null. Names are compared whole,
    /// so a serializer looking up what a document named does one pass.
    public Field FindField(String name) {
        for (nuint i = 0u; i < FieldCount(); i = i + 1u) {
            var field = FieldAt(i);
            if (field.Name() == name) { return field; }
        }

        Field missing;
        missing.Handle = null;
        return missing;
    }

    /// True when the type carries an attribute of that name.
    public bool Has(String name) {
        for (nuint i = 0u; i < AttributeCount(); i = i + 1u) {
            if (AttributeAt(i).Name() == name) { return true; }
        }
        return false;
    }
}

// ------------------------------------------------------------------ reading

/// Reads a whole-number field from an instance.
public long ReadInteger(byte* instance, Field field) {
    return sl_read_integer(instance, field.Handle);
}

public double ReadDouble(byte* instance, Field field) {
    return sl_read_double(instance, field.Handle);
}

public bool ReadBool(byte* instance, Field field) {
    return sl_read_bool(instance, field.Handle);
}

/// Reads a String field. The instance still owns it.
public String ReadText(byte* instance, Field field) {
    var raw = sl_read_reference(instance, field.Handle);
    if (raw == null) { return ""; }
    return Text.FromNullTerminated(raw + 32);
}

/// The address of a field that holds an aggregate, for walking into it.
///
/// A class field holds a reference, so the address is what it points at; a
/// struct field *is* its bytes, so the address is where it sits. Null for a
/// class field holding nothing, which is the one case a caller has to check.
public byte* ReadAggregate(byte* instance, Field field) {
    if (field.Kind() == KindStruct) { return instance + field.Offset(); }
    if (field.Kind() == KindClass || field.Kind() == KindInterface) {
        return sl_read_reference(instance, field.Handle);
    }
    return null;
}

// ------------------------------------------------------------------ writing

// Each writer narrows to the field's own width, so a value too large for it
// wraps there rather than writing over its neighbour -- which is C's rule for
// an assignment of the same shape, and the only one that cannot corrupt the
// object silently.
//
// None of them checks that the field belongs to the instance's type. Nothing
// here could: an instance is a `byte*` by the time it arrives, which is what
// makes the walk possible at all. Read the field out of the type you are
// holding and it is right by construction.

/// Writes a whole-number field.
public void WriteInteger(byte* instance, Field field, long value) {
    sl_write_integer(instance, field.Handle, value);
}

public void WriteDouble(byte* instance, Field field, double value) {
    sl_write_double(instance, field.Handle, value);
}

public void WriteBool(byte* instance, Field field, bool value) {
    sl_write_bool(instance, field.Handle, value);
}

/// Writes a String field, releasing whatever it held.
///
/// The bytes cross rather than the String, which is what keeps a counted
/// reference out of the runtime's ABI -- the same bargain `ReadText` makes in
/// the other direction. The field ends up owning a copy.
public void WriteText(byte* instance, Field field, String value) {
    sl_write_text(instance, field.Handle, value.ToPointer(), value.ByteLength());
}

/// Makes a zeroed instance of a type, for a reader that has a type and no
/// constructor to call.
///
/// **Every reference field starts null**, including one whose type says it
/// cannot be. What comes back is safe to fill and unsafe to hand out until it
/// has been: prefer making the object the ordinary way and filling it, which
/// is what `Json.Populate` does and why it is the one that needs no warning.
public byte* Make(Type type) {
    return sl_type_make(type.Handle);
}

/// Points a reference field at an object made by `Make`, releasing whatever it
/// held. The field takes a reference of its own, so the caller still owns
/// theirs.
public void WriteAggregate(byte* instance, Field field, byte* value) {
    sl_write_reference(instance, field.Handle, value);
}

/// Makes an object of a class field's own type and stores it in that field,
/// answering its address. Null when the field is not a class, or its type
/// carries no metadata.
///
/// **The object is zeroed**, so every reference field in it starts null --
/// including one whose type says it cannot be. That is the whole hazard: an
/// object made this way is not yet a value of its type, and is only safe once
/// whatever fills it has filled the fields that may not be null.
///
/// It exists because a deserializer holding a document for a nested object,
/// and a field holding nothing, otherwise has nowhere to put it. Use it where
/// the document is the thing that decides, and prefer a constructor that made
/// the object already: `Json.Populate` fills in place and only reaches for
/// this where a field is marked to say so.
public byte* MakeInto(byte* instance, Field field) {
    if (field.Kind() != KindClass) { return null; }

    var inner = field.TypeOf();
    if (!inner.Exists()) { return null; }

    byte* made = sl_type_make(inner.Handle);
    if (made == null) { return null; }

    // The field takes a reference of its own; this one was the allocation's,
    // and letting it go leaves the field the only owner.
    sl_write_reference(instance, field.Handle, made);
    sl_release(made);
    return made;
}

// ------------------------------------------------------------------- arrays

// An array is a counted object whose elements sit after its header, so
// reaching one is the data pointer plus a stride. Everything below takes the
// element's address rather than a field, because an element has no
// `Field` of its own -- it has a kind and a width, which is what
// `ElementKind()` and `ElementSize()` are for.

/// The array a field holds, or null. The instance still owns it.
public byte* ReadArray(byte* instance, Field field) {
    if (field.Kind() != KindArray) { return null; }
    return sl_read_reference(instance, field.Handle);
}

/// How many elements an array has. Zero for null.
public nuint ArrayLength(byte* array) {
    if (array == null) { return 0u; }
    return sl_array_length(array);
}

/// The address of one element, or null when the array is null or the index is
/// past its end. Checked rather than trusted: the caller is walking metadata,
/// and an index that came from a document is not the program's.
public byte* ElementAt(byte* array, Field field, nuint index) {
    if (array == null) { return null; }
    if (index >= sl_array_length(array)) { return null; }
    return sl_array_data(array) + index * field.ElementSize();
}

/// Reads an element of a whole-number array.
public long ReadIntegerAt(byte* address, Field field) {
    return sl_read_at_integer(address, (uint)field.ElementKind());
}

public double ReadDoubleAt(byte* address, Field field) {
    return sl_read_at_double(address, (uint)field.ElementKind());
}

public bool ReadBoolAt(byte* address) { return sl_read_at_bool(address); }

/// Reads a String element. The array still owns it.
public String ReadTextAt(byte* address) {
    var raw = sl_read_at_reference(address);
    if (raw == null) { return ""; }
    return Text.FromNullTerminated(raw + 32);
}

/// The address of an aggregate element: what a class element points at, or
/// where a struct element sits.
public byte* ReadAggregateAt(byte* address, Field field) {
    if (field.ElementKind() == KindStruct) { return address; }
    if (field.ElementKind() == KindClass || field.ElementKind() == KindInterface) {
        return sl_read_at_reference(address);
    }
    return null;
}

/// Writes an element of a whole-number array, narrowed to its width.
public void WriteIntegerAt(byte* address, Field field, long value) {
    sl_write_at_integer(address, (uint)field.ElementKind(), value);
}

public void WriteDoubleAt(byte* address, Field field, double value) {
    sl_write_at_double(address, (uint)field.ElementKind(), value);
}

public void WriteBoolAt(byte* address, bool value) { sl_write_at_bool(address, value); }

/// Writes a String element, releasing whatever it held.
public void WriteTextAt(byte* address, String value) {
    sl_write_at_text(address, value.ToPointer(), value.ByteLength());
}
