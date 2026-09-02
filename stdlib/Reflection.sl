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
    public bool IsInteger() {
        var kind = Kind();
        return kind >= KindChar && kind <= KindNUInt;
    }

    public bool IsFloating() { return Kind() == KindFloat || Kind() == KindDouble; }
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
