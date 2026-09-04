// Stainless - an experimental systems language.
// Copyright (C) 2026 Brandon Scott
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

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

    /// <summary>True for a class or interface: something a reference can point at.</summary>
    public virtual bool IsReferenceType => false;

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

/// <summary>
/// <c>T[]</c>: a counted array. Like a class it is a reference counted object,
/// so ARC, optionals and the calling convention apply unchanged; its elements
/// live inline after a length, the same shape String uses for its bytes.
/// </summary>
public sealed class ArrayTypeSymbol(TypeSymbol element) : TypeSymbol
{
    /// <summary>strong, weak, TypeInfo*, length. Elements start here.</summary>
    public const int HeaderSize = 32;

    public TypeSymbol Element { get; } = element;
    public override string Name => Element.Name + "[]";
    public override int Size => 8;
    public override int Alignment => 8;
    public override bool IsManaged => true;
    public override bool IsReferenceType => true;

    public override bool Equals(object? obj) =>
        obj is ArrayTypeSymbol other && Element.Equals(other.Element);
    public override int GetHashCode() => HashCode.Combine("array", Element);
}

/// <summary><c>C?</c>: an optional reference. Same representation, may be null.</summary>
public sealed class OptionalTypeSymbol(TypeSymbol element) : TypeSymbol
{
    public TypeSymbol Element { get; } = element;
    public override string Name => Element.Name + "?";
    public override int Size => 8;
    public override int Alignment => 8;
    public override bool IsManaged => true;

    public override bool Equals(object? obj) =>
        obj is OptionalTypeSymbol other && Element.Equals(other.Element);
    public override int GetHashCode() => HashCode.Combine("opt", Element);
}

/// <summary><c>weak C?</c>: a non-owning reference that reads as null once the object dies.</summary>
public sealed class WeakTypeSymbol(TypeSymbol element) : TypeSymbol
{
    public TypeSymbol Element { get; } = element;
    public override string Name => "weak " + Element.Name + "?";
    public override int Size => 8;
    public override int Alignment => 8;

    public override bool Equals(object? obj) =>
        obj is WeakTypeSymbol other && Element.Equals(other.Element);
    public override int GetHashCode() => HashCode.Combine("weak", Element);
}

/// <summary>
/// One attribute as applied to a declaration: which attribute, and the constant
/// arguments it was given. Both go into the binary when the owner is reflected.
/// </summary>
public sealed record AppliedAttribute(
    AttributeTypeSymbol Type,
    IReadOnlyList<object?> Values);

public sealed class FieldSymbol(string name, TypeSymbol type, NamedTypeSymbol containingType, int index)
{
    /// <summary>Attributes written on this field.</summary>
    public List<AppliedAttribute> Attributes { get; } = [];

    public string Name { get; } = name;
    public TypeSymbol Type { get; } = type;
    public NamedTypeSymbol ContainingType { get; } = containingType;
    public int Index { get; } = index;
    public bool IsPublic { get; init; }

    /// <summary>
    /// True for the hidden storage of an automatic property. It is laid out,
    /// destroyed and reflected exactly like any other field; it simply has no
    /// name the source can reach, because the property is that name.
    /// </summary>
    public bool IsBackingField { get; init; }

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

    /// <summary>
    /// Where the declaration was written, or null for one this compilation did
    /// not see the source of: a built-in such as <c>String</c>, or a type read
    /// back from a referenced library's metadata.
    /// </summary>
    public Source.SourceSpan? Span { get; init; }

    public List<FieldSymbol> Fields { get; } = [];
    public List<FunctionSymbol> Methods { get; } = [];

    /// <summary>
    /// Properties, whose accessors also appear in <see cref="Methods"/>. This
    /// list is what makes <c>x.Name</c> resolve; the methods are what makes it
    /// dispatch.
    /// </summary>
    public List<PropertySymbol> Properties { get; } = [];

    /// <summary>
    /// Methods with type parameters of their own. They stay templates until a
    /// call says what those parameters are, the same way a generic type does.
    /// </summary>
    public List<GenericFunctionTemplate> GenericMethods { get; } = [];

    /// <summary>
    /// For a class, the interfaces it implements. For an interface, the ones it
    /// extends. Both are the same relation, so both live here.
    /// </summary>
    public List<InterfaceTypeSymbol> Interfaces { get; } = [];

    /// <summary>Attributes written on this type.</summary>
    public List<AppliedAttribute> Attributes { get; } = [];

    /// <summary>
    /// True when the type was marked [Reflect] and so carries field metadata in
    /// the binary. Nothing else does, which is why reflection costs nothing
    /// unless it is asked for.
    /// </summary>
    public bool IsReflected { get; set; }

    /// <summary>
    /// For an instantiated generic, the template it came from and the arguments
    /// it was built with. Inference reads these to match a pattern such as
    /// <c>IReadOnlyList&lt;T&gt;</c> against a concrete <c>List&lt;Money&gt;</c>.
    /// </summary>
    public GenericTypeTemplate? Template { get; init; }
    public IReadOnlyList<TypeSymbol> TypeArguments { get; init; } = [];

    /// <summary>This type's interfaces, and theirs, without duplicates.</summary>
    public IEnumerable<InterfaceTypeSymbol> AllInterfaces()
    {
        var seen = new HashSet<InterfaceTypeSymbol>();
        var pending = new Stack<InterfaceTypeSymbol>(Interfaces);

        while (pending.Count > 0)
        {
            var current = pending.Pop();
            if (!seen.Add(current)) continue;

            yield return current;
            foreach (var inherited in current.Interfaces) pending.Push(inherited);
        }
    }

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

    /// <summary>
    /// A field the source may name. A property's backing field is deliberately
    /// not one: reaching it directly would bypass the accessors, and on an
    /// interface implementation that would bypass dispatch as well.
    /// </summary>
    public FieldSymbol? FindField(string name) =>
        Fields.FirstOrDefault(f => f.Name == name && !f.IsBackingField);

    /// <summary>Any field at all, hidden storage included. Used for name clashes.</summary>
    public FieldSymbol? FindStorage(string name) => Fields.FirstOrDefault(f => f.Name == name);

    public virtual PropertySymbol? FindProperty(string name) =>
        Properties.FirstOrDefault(p => p.Name == name);

    /// <summary>
    /// Finds a method on this type or, for an interface, on one it extends. The
    /// result keeps its own <c>ContainingType</c>, so a call through
    /// <c>IList</c> to a method declared on <c>IReadOnlyList</c> dispatches
    /// through the latter's table, which the object also carries.
    /// </summary>
    public virtual FunctionSymbol? FindMethod(string name) =>
        Methods.FirstOrDefault(m => m.Name == name);

    /// <summary>
    /// Every method of this name. Methods overload, so a name alone does not
    /// name one: a call picks by argument types, and an interface requirement
    /// picks by parameter types.
    /// </summary>
    public virtual IEnumerable<FunctionSymbol> FindMethods(string name) =>
        Methods.Where(m => m.Name == name);

    /// <summary>
    /// The method that implements an interface requirement, or null.
    ///
    /// A class may implement two instantiations of one generic interface —
    /// <c>IEquatable&lt;int&gt;</c> and <c>IEquatable&lt;String&gt;</c> — and
    /// then two methods share a name and differ only in parameters. Each
    /// interface has its own dispatch table, so this is what decides which
    /// method goes in which slot.
    /// </summary>
    public FunctionSymbol? FindImplementation(FunctionSymbol required)
    {
        var wanted = required.ParameterTypes.ToList();
        var overloads = FindMethods(required.Name).ToList();

        // Falling back to a lone candidate is deliberate: when only one method
        // could have been meant, the mismatch is the useful diagnostic, and
        // "does not implement" would hide it.
        return overloads.FirstOrDefault(m => m.Accepts(wanted))
            ?? (overloads.Count == 1 ? overloads[0] : null);
    }
}

/// <summary>
/// An <c>attribute</c> declaration. It has fields but no methods and is never a
/// value: it exists purely to be written on other declarations, so keeping it a
/// separate kind stops it drifting into runtime code.
/// </summary>
public sealed class AttributeTypeSymbol : NamedTypeSymbol
{
    public override int Size => 0;
    public override int Alignment => 1;
}

/// <summary>
/// A <c>delegate</c>: a named function pointer, and nothing more.
///
/// It is one pointer using the platform C calling convention, so it is exactly
/// a C function pointer and crosses <c>extern "C"</c> in both directions with
/// no glue. That also means it captures nothing: it refers to a function, not
/// to a function plus an environment. Closures need a heap object to hold what
/// they captured and are a separate feature.
/// </summary>
public sealed class DelegateTypeSymbol : NamedTypeSymbol
{
    public TypeSymbol ReturnType { get; set; } = PrimitiveTypeSymbol.Void;

    /// <summary>The signature's parameters. Never includes a receiver.</summary>
    public List<ParameterSymbol> Signature { get; } = [];

    public override int Size => 8;
    public override int Alignment => 8;

    /// <summary>True when <paramref name="function"/> can be stored in this delegate.</summary>
    public bool Accepts(FunctionSymbol function)
    {
        if (function.IsVariadic) return false;

        var parameters = function.Parameters.Where(p => !p.IsThis).ToList();
        if (parameters.Count != Signature.Count) return false;
        if (!function.ReturnType.Equals(ReturnType)) return false;

        return !parameters.Where((p, i) => !p.Type.Equals(Signature[i].Type)).Any();
    }

    public string SignatureText =>
        $"{ReturnType.Name}({string.Join(", ", Signature.Select(p => p.Type.Name))})";
}

/// <summary>One named constant of an <c>enum</c>.</summary>
public sealed class EnumMemberSymbol(string name, EnumTypeSymbol declaringEnum, ulong value)
{
    public string Name { get; } = name;
    public EnumTypeSymbol DeclaringEnum { get; } = declaringEnum;

    /// <summary>The constant, stored as raw bits of the underlying type.</summary>
    public ulong Value { get; } = value;

    public override string ToString() => $"{DeclaringEnum.Name}.{Name}";
}

/// <summary>
/// An <c>enum</c>: a distinct type over an integer, and distinct is the point.
/// It never converts to or from a number implicitly, so an enum cannot be
/// mistaken for the count it happens to be represented by. An explicit cast in
/// either direction is still available for interop and serialization.
///
/// Representation is exactly the underlying type, so a Stainless enum is the
/// same bytes as the C enum or integer it corresponds to.
/// </summary>
public sealed class EnumTypeSymbol : NamedTypeSymbol
{
    public PrimitiveTypeSymbol UnderlyingType { get; set; } = PrimitiveTypeSymbol.Int;

    public List<EnumMemberSymbol> Members { get; } = [];

    public override int Size => UnderlyingType.Size;
    public override int Alignment => UnderlyingType.Alignment;

    public EnumMemberSymbol? FindMember(string name) =>
        Members.FirstOrDefault(m => m.Name == name);
}

public class StructTypeSymbol : NamedTypeSymbol
{
    public override int Size => FieldsSize;
    public override int Alignment => FieldsAlignment;
}

/// <summary>
/// One case of a <c>variant</c>: a name, a tag, and the fields it carries.
///
/// The fields live in a struct of their own rather than on the case, so
/// everything that already knows how to lay out, copy, retain and describe a
/// struct works on a payload without being told what a variant is. The case is
/// then a name for that struct plus the number written in the tag.
/// </summary>
public sealed class VariantCaseSymbol
{
    public required string Name { get; init; }
    public required VariantTypeSymbol DeclaringVariant { get; init; }

    /// <summary>The value in the tag field. Assigned in declaration order.</summary>
    public required int Tag { get; init; }

    public required Source.SourceSpan Span { get; init; }

    /// <summary>The struct holding this case's fields, or null when it carries none.</summary>
    public StructTypeSymbol? Payload { get; set; }

    public IReadOnlyList<FieldSymbol> Fields => Payload?.Fields ?? [];

    public FieldSymbol? FindField(string name) =>
        Payload?.Fields.FirstOrDefault(f => f.Name == name);

    /// <summary>How the case reads in a diagnostic: <c>Circle(double radius)</c>.</summary>
    public string Signature => Fields.Count == 0
        ? Name
        : $"{Name}({string.Join(", ", Fields.Select(f => f.Type.Name + " " + f.Name))})";

    public override string ToString() => $"{DeclaringVariant.Name}.{Name}";
}

/// <summary>
/// A <c>variant</c>: a value that is exactly one of its cases, and says which.
///
/// It is a struct — literally, in the type system — because that is what it is
/// at runtime: a tag, then enough storage for the largest case, laid out by the
/// same C rules as everything else. Nothing allocates, and a variant crosses
/// <c>extern "C"</c> on the same terms as any other struct: freely if no case
/// holds a reference, and not at all if one does.
///
/// Being a struct is also what keeps the change small. Copying, passing,
/// returning, <c>sizeof</c>, generics and the Win64 classifier all reached
/// their answers through <see cref="StructTypeSymbol"/> already, and reach the
/// same ones here. Only two things need to know a variant from a struct: which
/// member may be read, which is a rule about proof rather than about layout,
/// and reference counting, which has to ask the tag which case is really there.
/// </summary>
public sealed class VariantTypeSymbol : StructTypeSymbol
{
    /// <summary>
    /// The two hidden fields. They are spelled with a character no identifier
    /// may contain, and marked as backing storage, so the source cannot reach
    /// past a case to the representation underneath.
    /// </summary>
    public const string TagFieldName = "$tag";
    public const string PayloadFieldName = "$payload";

    public List<VariantCaseSymbol> Cases { get; } = [];

    /// <summary>The filler that reserves the payload area, or null when no case carries one.</summary>
    public StructTypeSymbol? PayloadStorage { get; set; }

    public FieldSymbol TagField => Fields[0];
    public FieldSymbol? PayloadField => PayloadStorage is null ? null : Fields[1];

    public VariantCaseSymbol? FindCase(string name) =>
        Cases.FirstOrDefault(c => c.Name == name);

    /// <summary>
    /// True when some case holds a counted reference, and so when copying and
    /// dropping a value of this type has to consult the tag.
    /// </summary>
    public bool CasesCarryReferences =>
        Cases.Any(c => c.Payload is not null && c.Payload.Fields
            .Any(f => f.Type.CarriesReferences()));

    /// <summary>The cases not covered by <paramref name="covered"/>, in declaration order.</summary>
    public IEnumerable<VariantCaseSymbol> Uncovered(IEnumerable<VariantCaseSymbol> covered)
    {
        var seen = covered.ToHashSet();
        return Cases.Where(c => !seen.Contains(c));
    }
}

/// <summary>
/// An <c>interface</c>: a set of method signatures and nothing else. An
/// interface reference is a plain object pointer, exactly like a class
/// reference, so ARC, optionals, weak references and the calling convention all
/// apply unchanged. Dispatch goes through the object's TypeInfo; see
/// <see cref="Emit.LlvmEmitter"/> and docs/abi.md.
/// </summary>
public sealed class InterfaceTypeSymbol : NamedTypeSymbol
{
    public override int Size => 8;
    public override int Alignment => 8;
    public override bool IsManaged => true;
    public override bool IsReferenceType => true;

    /// <summary>Program-wide index, used to key the per-class dispatch table.</summary>
    public int Id { get; internal set; } = -1;

    /// <summary>Position of a method in this interface's vtable.</summary>
    public int SlotOf(FunctionSymbol method) => Methods.IndexOf(method);

    /// <summary>Also searches extended interfaces, nearest first.</summary>
    public override FunctionSymbol? FindMethod(string name) =>
        Methods.FirstOrDefault(m => m.Name == name)
        ?? AllInterfaces().Select(i => i.FindMethod(name)).FirstOrDefault(m => m is not null);

    /// <summary>
    /// Also searches extended interfaces, nearest first.
    ///
    /// An interface that restates a method it inherits declares the same
    /// signature twice, and a call would then have two candidates it could not
    /// tell apart. The nearest declaration wins, which is what naming a method
    /// through the derived interface has always meant.
    /// </summary>
    public override IEnumerable<FunctionSymbol> FindMethods(string name)
    {
        var seen = new List<FunctionSymbol>();

        foreach (var candidate in Methods.Where(m => m.Name == name)
                     .Concat(AllInterfaces().SelectMany(i => i.Methods.Where(m => m.Name == name))))
        {
            var signature = candidate.ParameterTypes.ToList();
            if (seen.Any(m => m.Accepts(signature))) continue;

            seen.Add(candidate);
            yield return candidate;
        }
    }

    /// <summary>Also searches extended interfaces, nearest first.</summary>
    public override PropertySymbol? FindProperty(string name) =>
        Properties.FirstOrDefault(p => p.Name == name)
        ?? AllInterfaces().Select(i => i.FindProperty(name)).FirstOrDefault(p => p is not null);
}

public sealed class ClassTypeSymbol : NamedTypeSymbol
{
    /// <summary>
    /// For a runtime-provided class, the C function that constructs one. When
    /// set, <c>new</c> calls it rather than allocating and running a constructor.
    /// </summary>
    public string? RuntimeFactory { get; init; }

    public override bool IsReferenceType => true;

    /// <summary>
    /// True for a class the runtime implements, such as <c>String</c>. The
    /// compiler emits no TypeInfo or destroy hook for these, because the
    /// runtime already defines them.
    /// </summary>
    public bool IsIntrinsic { get; init; }

    /// <summary>
    /// For a class from a referenced library, the TypeInfo symbol to allocate
    /// through. The table lives in the library, so an object made here still
    /// gets the destructor the library compiled.
    /// </summary>
    public string? ExternalTypeInfo { get; init; }

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
        type.IsReferenceType || type is OptionalTypeSymbol;

    /// <summary>
    /// True for any slot the emitter must maintain a count in: a strong
    /// reference, an optional one, or a weak one.
    /// </summary>
    public static bool IsManagedSlot(this TypeSymbol type) =>
        type.NeedsArc() || type is WeakTypeSymbol;

    /// <summary>
    /// True when a value of this type contains references the emitter must
    /// count: either because it is one, or because it is a struct with a field
    /// that is.
    ///
    /// A struct of plain data answers false, which is what keeps it free: it is
    /// copied as raw bytes, exactly as C would, with no reference traffic at
    /// all. Only a struct that actually holds a reference pays for one, and it
    /// is then no longer a type that may cross <c>extern "C"</c>.
    ///
    /// The recursion terminates because a struct may not contain itself; that
    /// cycle is rejected during layout (SL0216).
    /// </summary>
    public static bool CarriesReferences(this TypeSymbol type) => type switch
    {
        // A variant's own fields are a tag and a blob of bytes, which carry
        // nothing; what it holds is decided by the case the tag names.
        VariantTypeSymbol variant => variant.CasesCarryReferences,
        StructTypeSymbol structType => structType.Fields.Any(f => f.Type.CarriesReferences()),
        _ => type.IsManagedSlot(),
    };

    /// <summary>The type a reference points at, or null.</summary>
    public static TypeSymbol? AsReference(this TypeSymbol type) => type switch
    {
        OptionalTypeSymbol o => o.Element,
        WeakTypeSymbol w => w.Element,
        _ when type.IsReferenceType => type,
        _ => null,
    };

    /// <summary>The class a reference type points at, or null for an interface.</summary>
    public static ClassTypeSymbol? AsClass(this TypeSymbol type) => type.AsReference() as ClassTypeSymbol;

    public static bool IsVoid(this TypeSymbol type) =>
        type is PrimitiveTypeSymbol { Kind: PrimitiveKind.Void };

    public static bool IsBool(this TypeSymbol type) =>
        type is PrimitiveTypeSymbol { Kind: PrimitiveKind.Bool };

    public static bool IsError(this TypeSymbol type) => type is ErrorTypeSymbol;

    /// <summary>Rounds <paramref name="value"/> up to the next multiple of <paramref name="alignment"/>.</summary>
    public static int AlignTo(int value, int alignment) =>
        alignment <= 1 ? value : (value + alignment - 1) / alignment * alignment;
}
