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

/// Reading the metadata the compiler laid down.
///
/// There is no runtime machinery behind this: a reflected type's fields and
/// attributes are `const` tables in the binary, and everything below is a typed
/// view over them. That is why reflection works in a natively compiled language
/// at all -- it is a layout agreement, not a virtual machine.
///
/// A type carries metadata only when it is marked [Reflect]. Nothing else does,
/// so nothing else pays for it.
module Standard.Reflection;

/// Marks a class or struct to carry field metadata in the binary.
public attribute Reflect { }

// The runtime accessors. Handles are raw pointers into static tables, which is
// why they are never freed and never counted.
extern "C"
{
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

    byte*  sl_string_data(byte* text);
    nuint  sl_string_byte_length(byte* text);

    uint   sl_field_element_kind(byte* field);
    byte*  sl_field_element_type(byte* field);
    nuint  sl_field_element_size(byte* field);
    byte*  sl_field_new_array(byte* field, nuint length);

    uint   sl_field_flags(byte* field);

    nuint  sl_type_property_count(byte* type);
    byte*  sl_type_property(byte* type, nuint index);

    byte*  sl_property_name(byte* property);
    uint   sl_property_kind(byte* property);
    byte*  sl_property_type(byte* property);
    bool   sl_property_can_read(byte* property);
    bool   sl_property_can_write(byte* property);
    nuint  sl_property_attribute_count(byte* property);
    byte*  sl_property_attribute(byte* property, nuint index);

    long   sl_property_get_integer(byte* instance, byte* property);
    double sl_property_get_double(byte* instance, byte* property);
    bool   sl_property_get_bool(byte* instance, byte* property);
    byte*  sl_property_get_reference(byte* instance, byte* property);

    void   sl_property_set_integer(byte* instance, byte* property, long value);
    void   sl_property_set_double(byte* instance, byte* property, double value);
    void   sl_property_set_bool(byte* instance, byte* property, bool value);
    void   sl_property_set_reference(byte* instance, byte* property, byte* value);

    byte*  sl_type_find(byte* name);

    uint   sl_property_flags(byte* property);

    bool   sl_type_is_enum(byte* type);
    nuint  sl_type_enum_count(byte* type);
    byte*  sl_type_enum_name(byte* type, nuint index);
    long   sl_type_enum_value(byte* type, nuint index);

    nuint  sl_type_event_count(byte* type);
    byte*  sl_type_event_name(byte* type, nuint index);
    byte*  sl_type_event_handler_type(byte* type, nuint index);

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
/// A `bool`.
public const int KindBool      = 1;
/// A `char`: one UTF-8 code unit.
public const int KindChar      = 2;
/// An `sbyte`.
public const int KindSByte     = 3;
/// A `short`.
public const int KindShort     = 4;
/// An `int`.
public const int KindInt       = 5;
/// A `long`.
public const int KindLong      = 6;
/// An `nint`: pointer-wide and signed.
public const int KindNInt      = 7;
/// A `byte`.
public const int KindByte      = 8;
/// A `ushort`.
public const int KindUShort    = 9;
/// A `uint`.
public const int KindUInt      = 10;
/// A `ulong`.
public const int KindULong     = 11;
/// An `nuint`: pointer-wide and unsigned.
public const int KindNUInt     = 12;
/// A `float`.
public const int KindFloat     = 13;
/// A `double`.
public const int KindDouble    = 14;
/// A raw pointer. Nothing here follows one -- what it
/// points at carries no metadata.
public const int KindPointer   = 15;
/// A `String`. Read and written by value, through
/// `ReadText` and `WriteText`.
public const int KindString    = 16;
/// A class reference. `FieldType` gives the type to walk
/// into, and the value can be null.
public const int KindClass     = 17;
/// An interface reference, walked like a class.
public const int KindInterface = 18;
/// A struct, stored inline rather than referenced -- so
/// its address is where it sits, and it is never null.
public const int KindStruct    = 19;
/// An array. `ElementKind` says what is in it.
public const int KindArray     = 20;
/// A `char16`: one UTF-16 code unit. Numbered past
/// `KindArray` because it was added after the numbering was fixed, which is
/// why `IsInteger` tests it separately.
public const int KindChar16    = 21;
/// A `char32`: one Unicode scalar, with the same
/// numbering story as `KindChar16`.
public const int KindChar32    = 22;

// ------------------------------------------------- reading and writing them

/// Calls the getter. Zero when the property cannot be read, or when its kind
/// is not a whole number -- rather than reading the wrong four bytes.
public long GetInteger(byte* instance, Property property)
{
    return sl_property_get_integer(instance, property.Handle);
}

/// Calls the getter of a `float` or `double` property. Zero when it cannot be
/// read, or when its kind is not a floating one.
public double GetDouble(byte* instance, Property property)
{
    return sl_property_get_double(instance, property.Handle);
}

/// Calls the getter of a `bool` property. False when it cannot be read, or
/// when its kind is not `KindBool` -- which is indistinguishable from a real
/// false, so check `CanRead` and `Kind` where it matters.
public bool GetBool(byte* instance, Property property)
{
    return sl_property_get_bool(instance, property.Handle);
}

/// Calls the getter of a String property, and answers a copy of what it gave.
/// Empty when the property cannot be read or its kind is not `KindString`.
public String GetText(byte* instance, Property property)
{
    if (property.Kind != KindString)
        return "";

    var raw = sl_property_get_reference(instance, property.Handle);
    if (raw == null)
        return "";

    var copy = CopyCountedText(raw);
    sl_release(raw);
    return copy;
}

/// The object a class or interface property holds, for walking into it.
/// Null where it holds nothing, which a caller has to check.
///
/// The answer is borrowed from the instance, as `ReadAggregate`'s is. The
/// property MUST be one that holds its object: a getter that makes a new
/// object on each call answers one nothing else owns, and it is freed before
/// this returns.
///
/// @see ReadAggregate
/// @seealso SetAggregate
public byte* GetAggregate(byte* instance, Property property)
{
    var kind = property.Kind;
    if (kind != KindClass && kind != KindInterface && kind != KindArray)
        return null;

    var raw = sl_property_get_reference(instance, property.Handle);
    sl_release(raw);
    return raw;
}

/// Calls the setter, narrowing to the property's own width. Does nothing when
/// there is no setter, which `CanWrite` is how to find out in advance.
public void SetInteger(byte* instance, Property property, long value)
{
    sl_property_set_integer(instance, property.Handle, value);
}

/// Calls the setter of a floating property, narrowing to `float` where that
/// is its width. Does nothing when there is no setter.
public void SetDouble(byte* instance, Property property, double value)
{
    sl_property_set_double(instance, property.Handle, value);
}

/// Calls the setter of a `bool` property. Does nothing when there is no
/// setter, which `CanWrite` is how to find out in advance.
public void SetBool(byte* instance, Property property, bool value)
{
    sl_property_set_bool(instance, property.Handle, value);
}

/// Calls the setter of a String property.
///
/// The setter retains what it stores, so the caller still owns `value`
/// afterwards.
public void SetText(byte* instance, Property property, String value)
{
    sl_property_set_reference(instance, property.Handle, (byte*)value);
}

/// Points a class or interface property at an object, on the same terms.
public void SetAggregate(byte* instance, Property property, byte* value)
{
    sl_property_set_reference(instance, property.Handle, value);
}

// ------------------------------------------------------------------ reading

/// Reads a whole-number field from an instance.
///
/// @returns the value widened to a `long`, sign-extended from a signed kind and
///          zero-extended from an unsigned one. Zero for a field whose kind is
///          not a whole number. A `ulong` past the range of `long` comes back
///          negative, with its bits unchanged.
/// @see WriteInteger
public long ReadInteger(byte* instance, Field field)
{
    return sl_read_integer(instance, field.Handle);
}

/// Reads a `float` or `double` field from an instance. Zero when the field's
/// kind is not a floating one -- no conversion from an integer field.
///
/// @see WriteDouble
public double ReadDouble(byte* instance, Field field)
{
    return sl_read_double(instance, field.Handle);
}

/// Reads a `bool` field from an instance. False when the field's kind is not
/// `KindBool`, which reads the same as a real false.
///
/// @see WriteBool
public bool ReadBool(byte* instance, Field field)
{
    return sl_read_bool(instance, field.Handle);
}

/// Reads a String field, as a copy of all its bytes. Empty when the field's
/// kind is not `KindString`.
///
/// @see WriteText
public String ReadText(byte* instance, Field field)
{
    if (field.Kind != KindString)
        return "";

    var raw = sl_read_reference(instance, field.Handle);
    if (raw == null)
        return "";
    return CopyCountedText(raw);
}

// A copy of a String reached as a raw pointer. Its length is the byte length
// the String records, so an embedded NUL does not end it.
String CopyCountedText(byte* raw)
{
    return Text.FromBytes(sl_string_data(raw), sl_string_byte_length(raw));
}

/// The address of a field that holds an aggregate, for walking into it.
///
/// A class field holds a reference, so the address is what it points at; a
/// struct field *is* its bytes, so the address is where it sits. Null for a
/// class field holding nothing, which is the one case a caller has to check.
///
/// @see WriteAggregate
public byte* ReadAggregate(byte* instance, Field field)
{
    if (field.Kind == KindStruct)
        return instance + field.Offset;
    if (field.Kind == KindClass || field.Kind == KindInterface)
    {
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
///
/// @see ReadInteger
public void WriteInteger(byte* instance, Field field, long value)
{
    sl_write_integer(instance, field.Handle, value);
}

/// Writes a floating field, narrowed to `float` where that is its width.
///
/// @see ReadDouble
public void WriteDouble(byte* instance, Field field, double value)
{
    sl_write_double(instance, field.Handle, value);
}

/// Writes a `bool` field.
///
/// @see ReadBool
public void WriteBool(byte* instance, Field field, bool value)
{
    sl_write_bool(instance, field.Handle, value);
}

/// Writes a String field, releasing whatever it held.
///
/// The bytes cross rather than the String, which is what keeps a counted
/// reference out of the runtime's ABI -- the same bargain `ReadText` makes in
/// the other direction. The field ends up owning a copy.
///
/// @see ReadText
public void WriteText(byte* instance, Field field, String value)
{
    sl_write_text(instance, field.Handle, value.ToPointer(), value.ByteLength());
}

/// The type of that **qualified** name -- "App.Button", as `Type.Name`
/// spells it -- or a handle of null.
///
/// This is the one thing in reflection that is a search rather than a
/// constant, and it exists for the case `typeof` cannot serve: a document
/// naming the type it wants. Every `[Reflect]` type in the binary is in a
/// sorted table registered before `Main` runs, and each library the program
/// loaded contributes its own, so the lookup is a binary search per binary.
///
/// **Only reflected types are findable.** A program that could name any type
/// at run time would be a program whose linker could drop nothing, which is
/// the trade `[Reflect]` exists to make explicit.
///
///     var type = FindType("App.Button");
///     if (type.Exists) { byte* made = CreateInstance(type); }
public Type FindType(String name)
{
    Type result;
    result.Handle = sl_type_find(name.ToPointer());
    return result;
}

/// Makes a zeroed instance of a type, for a reader that has a type and no
/// constructor to call.
///
/// **Every reference field starts null**, including one whose type says it
/// cannot be. What comes back is safe to fill and unsafe to hand out until it
/// has been: prefer making the object the ordinary way and filling it, which
/// is what `Json.PopulateObject` does and why it is the one that needs no warning.
///
/// @see CreateInstanceInto
public byte* CreateInstance(Type type)
{
    return sl_type_make(type.Handle);
}

/// Points a reference field at an object made by `CreateInstance`, releasing whatever it
/// held. The field takes a reference of its own, so the caller still owns
/// theirs.
///
/// @see CreateInstance
/// @seealso ReadAggregate
public void WriteAggregate(byte* instance, Field field, byte* value)
{
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
/// the object already: `Json.PopulateObject` fills in place and only reaches for
/// this where a field is marked to say so.
///
/// @see CreateInstance
public byte* CreateInstanceInto(byte* instance, Field field)
{
    if (field.Kind != KindClass)
        return null;

    var inner = field.FieldType;
    if (!inner.Exists)
        return null;

    byte* made = sl_type_make(inner.Handle);
    if (made == null)
        return null;

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
// `ElementKind` and `ElementSize` are for.

/// The array a field holds, or null. The instance still owns it.
public byte* ReadArray(byte* instance, Field field)
{
    if (field.Kind != KindArray)
        return null;
    return sl_read_reference(instance, field.Handle);
}

/// Makes an array of `count` elements for an array field and stores it there,
/// answering its address.
///
/// **The one thing about an array that could not be done here.** Elements
/// could be read and written, and the stride made that possible without
/// knowing the element type -- but there was no way to *make* one, so a
/// document that said how many elements it had could only be read into an
/// array that already happened to be that long. That is the whole of why a
/// reader could round-trip an array and not fill one.
///
/// The elements are zero, which for a reference means null, so the array is
/// safe to write into in any order and safe to abandon half-filled.
///
/// **It stores the array rather than handing it over**, for the reason
/// `CreateInstanceInto` does: the reference an allocation answers with is
/// owned by whoever received it, this module keeps `sl_release` to itself, and
/// so a caller outside it had no way to let go of what `CreateArray` gave
/// them. Writing it into the field here, and dropping the allocation's
/// reference here, leaves the field the only owner and the caller nothing to
/// remember.
///
/// Null for a field that is not an array, and for one whose array type the
/// build recorded nothing for.
///
/// @see CreateInstanceInto
/// @seealso WriteAggregate
public byte* CreateArrayInto(byte* instance, Field field, nuint count)
{
    if (field.Kind != KindArray)
        return null;

    byte* made = sl_field_new_array(field.Handle, count);
    if (made == null)
        return null;

    // The field takes a reference of its own; this one was the allocation's,
    // and letting it go leaves the field the only owner.
    sl_write_reference(instance, field.Handle, made);
    sl_release(made);
    return made;
}

/// How many elements an array has. Zero for null.
public nuint GetArrayLength(byte* array)
{
    if (array == null)
        return 0u;
    return sl_array_length(array);
}

/// The address of one element, or null when the array is null or the index is
/// past its end. Checked rather than trusted: the caller is walking metadata,
/// and an index that came from a document is not the program's.
///
/// @param array  the array itself, as `ReadArray` answers it
/// @param field  the array field, which supplies the stride between elements
/// @param index  which element, counted from zero
public byte* GetElementAddress(byte* array, Field field, nuint index)
{
    if (array == null)
        return null;
    if (index >= sl_array_length(array))
        return null;
    return sl_array_data(array) + index * field.ElementSize;
}

/// Reads an element of a whole-number array.
///
/// @param address  where the element sits, from `GetElementAddress`
/// @param field    the array field, which supplies the element kind
/// @see WriteIntegerAt
public long ReadIntegerAt(byte* address, Field field)
{
    return sl_read_at_integer(address, (uint)field.ElementKind);
}

/// Reads an element of a floating array. `field` supplies the element kind,
/// which is what says whether the four or the eight bytes at `address` are the
/// value.
public double ReadDoubleAt(byte* address, Field field)
{
    return sl_read_at_double(address, (uint)field.ElementKind);
}

/// Reads an element of a `bool` array. Takes no field, a `bool` being one byte
/// whatever array it is in.
public bool ReadBoolAt(byte* address) => sl_read_at_bool(address);

/// Reads a String element, as a copy of all its bytes.
public String ReadTextAt(byte* address)
{
    var raw = sl_read_at_reference(address);
    if (raw == null)
        return "";
    return CopyCountedText(raw);
}

/// The address of an aggregate element: what a class element points at, or
/// where a struct element sits.
public byte* ReadAggregateAt(byte* address, Field field)
{
    if (field.ElementKind == KindStruct)
        return address;
    if (field.ElementKind == KindClass || field.ElementKind == KindInterface)
    {
        return sl_read_at_reference(address);
    }
    return null;
}

/// Writes an element of a whole-number array, narrowed to its width.
///
/// @see ReadIntegerAt
public void WriteIntegerAt(byte* address, Field field, long value)
{
    sl_write_at_integer(address, (uint)field.ElementKind, value);
}

/// Writes an element of a floating array, narrowed to the element's width.
public void WriteDoubleAt(byte* address, Field field, double value)
{
    sl_write_at_double(address, (uint)field.ElementKind, value);
}

/// Writes an element of a `bool` array.
public void WriteBoolAt(byte* address, bool value) => sl_write_at_bool(address, value);

/// Writes a String element, releasing whatever it held.
public void WriteTextAt(byte* address, String value)
{
    sl_write_at_text(address, value.ToPointer(), value.ByteLength());
}
