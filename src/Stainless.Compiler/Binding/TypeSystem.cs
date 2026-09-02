namespace Stainless.Binding;

public enum PrimitiveKind
{
    Void, Bool, Char,
    SByte, Short, Int, Long, NInt,
    Byte, UShort, UInt, ULong, NUInt,
    Float, Double,
}

/// <summary>
/// A Stainless type. Layout follows the platform C rules exactly, which is the
/// whole point of the ABI guarantee: a Stainless struct is a C struct.
/// </summary>
public abstract class TypeSymbol
{
    public abstract string Name { get; }

    /// <summary>Size in bytes, or 0 for <c>void</c>.</summary>
    public abstract int Size { get; }

    /// <summary>Required alignment in bytes.</summary>
    public abstract int Alignment { get; }

    /// <summary>True for types managed by ARC, i.e. class references.</summary>
    public virtual bool IsManaged => false;

    public override string ToString() => Name;
}

public sealed class ErrorTypeSymbol : TypeSymbol
{
    public static readonly ErrorTypeSymbol Instance = new();
    private ErrorTypeSymbol() { }
    public override string Name => "<error>";
    public override int Size => 0;
    public override int Alignment => 1;
}

public sealed class PrimitiveTypeSymbol : TypeSymbol
{
    public PrimitiveKind Kind { get; }
    public override string Name { get; }
    public override int Size { get; }
    public override int Alignment => Size == 0 ? 1 : Size;

    private PrimitiveTypeSymbol(PrimitiveKind kind, string name, int size)
    {
        Kind = kind;
        Name = name;
        Size = size;
    }

    public bool IsInteger => Kind is >= PrimitiveKind.Char and <= PrimitiveKind.NUInt;
    public bool IsFloat => Kind is PrimitiveKind.Float or PrimitiveKind.Double;
    public bool IsSigned => Kind is PrimitiveKind.SByte or PrimitiveKind.Short
        or PrimitiveKind.Int or PrimitiveKind.Long or PrimitiveKind.NInt;
    public bool IsNumeric => IsInteger || IsFloat;

    /// <summary>Bit width used for integer conversions and LLVM types.</summary>
    public int Bits => Size * 8;

    public static readonly PrimitiveTypeSymbol Void = new(PrimitiveKind.Void, "void", 0);
    public static readonly PrimitiveTypeSymbol Bool = new(PrimitiveKind.Bool, "bool", 1);
    public static readonly PrimitiveTypeSymbol Char = new(PrimitiveKind.Char, "char", 1);
    public static readonly PrimitiveTypeSymbol SByte = new(PrimitiveKind.SByte, "sbyte", 1);
    public static readonly PrimitiveTypeSymbol Short = new(PrimitiveKind.Short, "short", 2);
    public static readonly PrimitiveTypeSymbol Int = new(PrimitiveKind.Int, "int", 4);
    public static readonly PrimitiveTypeSymbol Long = new(PrimitiveKind.Long, "long", 8);
    public static readonly PrimitiveTypeSymbol NInt = new(PrimitiveKind.NInt, "nint", 8);
    public static readonly PrimitiveTypeSymbol Byte = new(PrimitiveKind.Byte, "byte", 1);
    public static readonly PrimitiveTypeSymbol UShort = new(PrimitiveKind.UShort, "ushort", 2);
    public static readonly PrimitiveTypeSymbol UInt = new(PrimitiveKind.UInt, "uint", 4);
    public static readonly PrimitiveTypeSymbol ULong = new(PrimitiveKind.ULong, "ulong", 8);
    public static readonly PrimitiveTypeSymbol NUInt = new(PrimitiveKind.NUInt, "nuint", 8);
    public static readonly PrimitiveTypeSymbol Float = new(PrimitiveKind.Float, "float", 4);
    public static readonly PrimitiveTypeSymbol Double = new(PrimitiveKind.Double, "double", 8);

    public static readonly IReadOnlyList<PrimitiveTypeSymbol> All =
    [
        Void, Bool, Char, SByte, Short, Int, Long, NInt,
        Byte, UShort, UInt, ULong, NUInt, Float, Double,
    ];
}

/// <summary><c>T*</c>: a raw, unmanaged pointer, identical to C's.</summary>
public sealed class PointerTypeSymbol(TypeSymbol element) : TypeSymbol
{
    public TypeSymbol Element { get; } = element;
    public override string Name => Element.Name + "*";
    public override int Size => 8;
    public override int Alignment => 8;

    public override bool Equals(object? obj) =>
        obj is PointerTypeSymbol other && Element.Equals(other.Element);
    public override int GetHashCode() => HashCode.Combine("ptr", Element);
}

/// <summary><c>C?</c>: an optional class reference. Same representation, may be null.</summary>
public sealed class OptionalTypeSymbol(ClassTypeSymbol element) : TypeSymbol
{
    public ClassTypeSymbol Element { get; } = element;
    public override string Name => Element.Name + "?";
    public override int Size => 8;
    public override int Alignment => 8;
    public override bool IsManaged => true;

    public override bool Equals(object? obj) =>
        obj is OptionalTypeSymbol other && Element.Equals(other.Element);
    public override int GetHashCode() => HashCode.Combine("opt", Element);
}

/// <summary><c>weak C?</c>: a non-owning reference that reads as null once the object dies.</summary>
public sealed class WeakTypeSymbol(ClassTypeSymbol element) : TypeSymbol
{
    public ClassTypeSymbol Element { get; } = element;
    public override string Name => "weak " + Element.Name + "?";
    public override int Size => 8;
    public override int Alignment => 8;

    public override bool Equals(object? obj) =>
        obj is WeakTypeSymbol other && Element.Equals(other.Element);
    public override int GetHashCode() => HashCode.Combine("weak", Element);
}

public sealed class FieldSymbol(string name, TypeSymbol type, NamedTypeSymbol containingType, int index)
{
    public string Name { get; } = name;
    public TypeSymbol Type { get; } = type;
    public NamedTypeSymbol ContainingType { get; } = containingType;
    public int Index { get; } = index;
    public bool IsPublic { get; init; }

    /// <summary>Byte offset from the start of the value (structs) or of the fields area (classes).</summary>
    public int Offset { get; internal set; }

    public override string ToString() => $"{ContainingType.Name}.{Name}";
}

/// <summary>A user-declared <c>struct</c> or <c>class</c>.</summary>
public abstract class NamedTypeSymbol : TypeSymbol
{
    public required string SimpleName { get; init; }
    public required string ModuleName { get; init; }
    public bool IsPublic { get; init; }

    public List<FieldSymbol> Fields { get; } = [];
    public List<FunctionSymbol> Methods { get; } = [];

    /// <summary>Fully qualified: <c>App.Math.Vector</c>.</summary>
    public string QualifiedName =>
        string.IsNullOrEmpty(ModuleName) ? SimpleName : ModuleName + "." + SimpleName;

    public override string Name => SimpleName;

    internal bool LayoutComputed;
    private int _size;
    private int _alignment = 1;

    internal void SetLayout(int size, int alignment)
    {
        _size = size;
        _alignment = alignment;
        LayoutComputed = true;
    }

    /// <summary>Size of the field area, ignoring any object header.</summary>
    public int FieldsSize => _size;
    public int FieldsAlignment => _alignment;

    public FieldSymbol? FindField(string name) => Fields.FirstOrDefault(f => f.Name == name);
    public FunctionSymbol? FindMethod(string name) => Methods.FirstOrDefault(m => m.Name == name);
}

public sealed class StructTypeSymbol : NamedTypeSymbol
{
    public override int Size => FieldsSize;
    public override int Alignment => FieldsAlignment;
}

public sealed class ClassTypeSymbol : NamedTypeSymbol
{
    /// <summary>
    /// True for a class the runtime implements, such as <c>String</c>. The
    /// compiler emits no TypeInfo or destroy hook for these, because the
    /// runtime already defines them.
    /// </summary>
    public bool IsIntrinsic { get; init; }

    /// <summary>strong count, weak count, TypeInfo pointer. See docs/abi.md.</summary>
    public const int HeaderSize = 24;

    /// <summary>A class reference is pointer-sized; the object itself lives on the heap.</summary>
    public override int Size => 8;
    public override int Alignment => 8;
    public override bool IsManaged => true;

    /// <summary>Total heap allocation: header plus fields.</summary>
    public int InstanceSize => HeaderSize + FieldsSize;

    public List<FunctionSymbol> Constructors { get; } = [];
    public FunctionSymbol? Destructor { get; set; }
}

public static class TypeExtensions
{
    /// <summary>True when values of this type participate in retain/release.</summary>
    public static bool NeedsArc(this TypeSymbol type) =>
        type is ClassTypeSymbol or OptionalTypeSymbol;

    /// <summary>The class a reference type points at, or null.</summary>
    public static ClassTypeSymbol? AsClass(this TypeSymbol type) => type switch
    {
        ClassTypeSymbol c => c,
        OptionalTypeSymbol o => o.Element,
        WeakTypeSymbol w => w.Element,
        _ => null,
    };

    public static bool IsVoid(this TypeSymbol type) =>
        type is PrimitiveTypeSymbol { Kind: PrimitiveKind.Void };

    public static bool IsBool(this TypeSymbol type) =>
        type is PrimitiveTypeSymbol { Kind: PrimitiveKind.Bool };

    public static bool IsError(this TypeSymbol type) => type is ErrorTypeSymbol;

    /// <summary>Rounds <paramref name="value"/> up to the next multiple of <paramref name="alignment"/>.</summary>
    public static int AlignTo(int value, int alignment) =>
        alignment <= 1 ? value : (value + alignment - 1) / alignment * alignment;
}
