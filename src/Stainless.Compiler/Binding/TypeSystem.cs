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
    Void, Bool, Char, Char16, Char32,
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

    /// <summary>
    /// True for an <c>interface</c> or a <c>com interface</c>: a type that
    /// declares signatures and holds nothing.
    ///
    /// The two are laid out differently and counted differently, and neither
    /// has fields, a constructor, a destructor, member bodies, private members
    /// or overloads -- one slot per method is what rules the last one out. Every
    /// check about those is about this, and not about which kind it is.
    /// </summary>
    public virtual bool IsContract => false;

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

    /// <summary>
    /// True for <c>char</c>, <c>char16</c> and <c>char32</c>: the three code
    /// unit types.
    ///
    /// They are integers and behave as such against every other integer, but
    /// not against each other -- see <c>Binder.ClassifyConversion</c>. A
    /// <c>char</c> is one eighth of a UTF-8 scalar at worst and a
    /// <c>char16</c> one half of a UTF-16 one, so widening one to another is a
    /// re-encoding and never a conversion.
    /// </summary>
    public bool IsCodeUnit => Kind is PrimitiveKind.Char or PrimitiveKind.Char16 or PrimitiveKind.Char32;

    /// <summary>Bit width used for integer conversions and LLVM types.</summary>
    public int Bits => Size * 8;

    public static readonly PrimitiveTypeSymbol Void = new(PrimitiveKind.Void, "void", 0);
    public static readonly PrimitiveTypeSymbol Bool = new(PrimitiveKind.Bool, "bool", 1);
    public static readonly PrimitiveTypeSymbol Char = new(PrimitiveKind.Char, "char", 1);
    public static readonly PrimitiveTypeSymbol Char16 = new(PrimitiveKind.Char16, "char16", 2);
    public static readonly PrimitiveTypeSymbol Char32 = new(PrimitiveKind.Char32, "char32", 4);
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
        Void, Bool, Char, Char16, Char32, SByte, Short, Int, Long, NInt,
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

/// <summary>
/// <c>T[N]</c>: N elements laid out end to end, inside whatever contains them.
///
/// This is C's array and not C#'s. A <see cref="ArrayTypeSymbol"/> is a
/// reference to a counted heap object; this one <em>is</em> its elements, so a
/// struct holding one is exactly as wide as the C struct it mirrors and
/// <c>sizeof</c> includes every element.
/// </summary>
public sealed class FixedArrayTypeSymbol(TypeSymbol element, int length) : TypeSymbol
{
    public TypeSymbol Element { get; } = element;

    /// <summary>How many elements. Always at least one.</summary>
    public int Length { get; } = length;

    public override string Name => $"{Element.Name}[{Length}]";

    /// <summary>Every element, with no header and no padding between them.</summary>
    public override int Size => Element.Size * Length;

    /// <summary>An array is aligned as its element is, which is C's rule.</summary>
    public override int Alignment => Element.Alignment;

    public override bool Equals(object? obj) =>
        obj is FixedArrayTypeSymbol other &&
        Element.Equals(other.Element) && Length == other.Length;
    public override int GetHashCode() => HashCode.Combine("fixed", Element, Length);
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

public static class AnonymousMembers
{
    /// <summary>
    /// The infix the parser gives the type a nameless <c>struct { }</c> or
    /// <c>union { }</c> member becomes. It carries a <c>$</c>, which no source
    /// identifier may, so nothing a program wrote can be mistaken for one.
    /// </summary>
    public const string Infix = "$anon";

    /// <summary>
    /// True for such a type. It is reachable only through the field it became,
    /// so nothing that describes a program's surface -- a C header, module
    /// metadata -- should name it.
    /// </summary>
    public static bool IsGenerated(TypeSymbol type) =>
        type is NamedTypeSymbol named &&
        named.SimpleName.Contains(Infix, StringComparison.Ordinal);
}

public sealed class FieldSymbol(string name, TypeSymbol type, NamedTypeSymbol containingType, int index)
{
    /// <summary>Attributes written on this field.</summary>
    public List<AppliedAttribute> Attributes { get; } = [];

    public string Name { get; } = name;
    public TypeSymbol Type { get; } = type;
    public NamedTypeSymbol ContainingType { get; } = containingType;
    public int Index { get; } = index;
    public bool IsPublic { get; init; }

    /// <summary>Visible to this type and anything deriving from it.</summary>
    public bool IsProtected { get; init; }

    /// <summary>
    /// True for the hidden storage of an automatic property. It is laid out,
    /// destroyed and reflected exactly like any other field; it simply has no
    /// name the source can reach, because the property is that name.
    /// </summary>
    public bool IsBackingField { get; init; }

    /// <summary>
    /// True for the field a nameless <c>struct { }</c> or <c>union { }</c>
    /// member became. It is laid out like any other field -- that is what makes
    /// the offsets C's -- but its name is generated, and a member of the type
    /// inside is reached as though it belonged to the type outside.
    /// </summary>
    public bool IsAnonymous { get; init; }

    /// <summary>Byte offset from the start of the value (structs) or of the fields area (classes).</summary>
    public int Offset { get; internal set; }

    /// <summary>
    /// How many bits this field is, or null when it is the whole of its type.
    ///
    /// A bit-field is read and written through the storage unit it sits in,
    /// which starts at <see cref="Offset"/> and is <see cref="Type"/>-sized;
    /// <see cref="BitOffset"/> says where in that unit it begins. Which bits a
    /// unit holds is decided by the target's C rules, and those differ between
    /// Microsoft's compilers and everyone else's — see the layout pass.
    /// </summary>
    public int? BitWidth { get; internal set; }

    /// <summary>Where in its storage unit a bit-field starts, counted from the low bit.</summary>
    public int BitOffset { get; internal set; }

    public bool IsBitField => BitWidth is not null;

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
    /// Operators this type declares: <c>public static Money operator +(Money,
    /// Money)</c>.
    ///
    /// Kept apart from <see cref="Methods"/> deliberately. An operator has no
    /// receiver, so it is not dispatched and needs no vtable slot; and it is
    /// reached by writing <c>a + b</c> rather than by name, so putting it where
    /// ordinary lookup would find it would let somebody call <c>op_Add</c>
    /// directly -- which is the lowering, not the language.
    /// </summary>
    public List<FunctionSymbol> Operators { get; } = [];

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
    /// True when the type was marked <c>[Packed]</c>: laid out with no padding
    /// between fields and none at the end, and aligned to one byte unless
    /// <c>[Align]</c> says otherwise.
    /// </summary>
    public bool IsPacked { get; set; }

    /// <summary>
    /// The alignment <c>[Align(N)]</c> asked for, or null. It raises the
    /// natural one and never lowers it, so the two are combined with a max.
    /// </summary>
    public int? RequestedAlignment { get; set; }

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
    public virtual FieldSymbol? FindField(string name) =>
        Fields.FirstOrDefault(f => f.Name == name && !f.IsBackingField);

    /// <summary>Any field at all, hidden storage included. Used for name clashes.</summary>
    public virtual FieldSymbol? FindStorage(string name) => Fields.FirstOrDefault(f => f.Name == name);

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

        // The mode is part of the signature: a 'ref int' and an 'int' are
        // passed differently and mean different things to the caller.
        return !parameters.Where(
            (p, i) => !p.Type.Equals(Signature[i].Type) || p.Mode != Signature[i].Mode).Any();
    }

    public string SignatureText =>
        $"{ReturnType.Name}({string.Join(", ", Signature.Select(Spelled))})";

    private static string Spelled(ParameterSymbol parameter) =>
        (parameter.Mode == Syntax.ParameterMode.Ref ? "ref " :
         parameter.Mode == Syntax.ParameterMode.In ? "in " : "") + parameter.Type.Name;
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

    /// <summary>
    /// True for a type written <c>struct HWND__;</c>: declared here, laid out
    /// somewhere else, and never completed.
    ///
    /// This is C's incomplete type, and it exists so that a binding can have
    /// handles that are told apart. <c>HWND__*</c> and <c>HDC__*</c> are
    /// different types because they point at different things, so passing one
    /// where the other belongs is caught -- and at no cost at all, since neither
    /// type is ever laid out, emitted, or present at run time.
    /// </summary>
    public bool IsOpaque { get; set; }
}

/// <summary>
/// A <c>union</c>: every member at offset zero, as in C.
///
/// It exists for the same reason <c>extern "C"</c> does. A great many C headers
/// describe a value that is one of several things and say which somewhere else
/// -- a tag in the enclosing struct, a length, a protocol -- and none of them
/// can be bound without a type of this shape. It is the untagged half of what a
/// <c>variant</c> does: a variant knows which member is there and will not let
/// you read another, and a union knows nothing and will let you read any of
/// them.
///
/// **No member may hold a counted reference.** Which one is live is exactly
/// what a union does not record, so a copy could not know what to retain and a
/// drop could not know what to release. That is not a restriction added for
/// safety; it is the thing a union cannot be asked.
/// </summary>
public sealed class UnionTypeSymbol : StructTypeSymbol
{
}

/// <summary>
/// <c>T[:]</c>: part of an array, as a value.
///
/// Three words -- the array, where in it this starts, and how many elements it
/// runs for -- and it is a struct, in the type system as at runtime. So it
/// copies, is passed, is returned and is laid out by everything that already
/// knew how to do those to a struct, and it holds the array the way any struct
/// field holds a reference: retained on a copy, released on a drop. A slice
/// cannot dangle, because what it points into is alive for as long as it is.
///
/// What that costs is a reference count per copy, and being a value C cannot be
/// handed. What it buys is that there are no lifetimes to explain: a slice is
/// safe by the same rule everything else here is safe by.
/// </summary>
public sealed class SliceTypeSymbol : StructTypeSymbol
{
    public required TypeSymbol Element { get; init; }

    /// <summary>The three fields, which the source cannot name.</summary>
    public const string ArrayFieldName = "$array";
    public const string OffsetFieldName = "$offset";
    public const string LengthFieldName = "$length";

    public override string Name => Element.Name + "[:]";
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

    /// <summary>The payload field, or null when no case carries anything.</summary>
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
    public override bool IsContract => true;
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

/// <summary>
/// <c>com interface IFoo : IUnknown</c>: a COM interface.
///
/// This is not <see cref="InterfaceTypeSymbol"/> with a flag on it. The two
/// are different things in memory, and every difference follows from where the
/// reference points:
///
/// <list type="bullet">
/// <item>A Stainless interface reference points at the object header, and the
/// vtable is reached through it -- <c>obj+16</c> to the TypeInfo, <c>+24</c> to
/// the interface tables, then the interface's id and the method's slot. Four
/// loads, and it needs the object to have been allocated by the runtime.</item>
/// <item>A COM interface reference points at the vtable pointer itself, which
/// is field zero of whatever the object is. Two loads, and it needs nothing of
/// the object at all.</item>
/// </list>
///
/// So a com interface can name something another language allocated, which is
/// the point, and cannot carry a Stainless object header, which is the cost.
/// Reference counting goes through <c>IUnknown</c>'s AddRef and Release rather
/// than through <c>sl_retain</c>, and ARC drives them: see docs/com.md.
/// </summary>
public sealed class ComInterfaceTypeSymbol : NamedTypeSymbol
{
    /// <summary>QueryInterface, AddRef, Release: every COM vtable starts here.</summary>
    public const int UnknownSlots = 3;

    public override bool IsContract => true;

    /// <summary>A reference is one pointer, to the object's vtable pointer.</summary>
    public override int Size => 8;
    public override int Alignment => 8;

    /// <summary>
    /// Counted, so ARC applies -- but through AddRef and Release rather than
    /// through sl_retain, which is what <c>NeedsComArc</c> tells the emitter.
    /// </summary>
    public override bool IsManaged => true;
    public override bool IsReferenceType => true;

    /// <summary>
    /// The interface this one extends, or null for <c>IUnknown</c> itself.
    ///
    /// Single, and not a list: a COM vtable is one array, a derived interface's
    /// slots come after its base's, and two bases would mean two vtables and
    /// therefore two pointers where the ABI has room for one.
    /// </summary>
    public ComInterfaceTypeSymbol? BaseInterface { get; set; }

    /// <summary>
    /// The IID, from <c>[Guid("...")]</c>. Null until pass 6 folds it, and an
    /// interface that never got one cannot be asked for by QueryInterface.
    /// </summary>
    public Guid? Iid { get; set; }

    /// <summary>
    /// Every method in slot order: the base's table, then this interface's own
    /// declarations in the order they were written.
    ///
    /// Filled in pass 5 and emitted verbatim. Root-down numbering is what makes
    /// a derived reference usable as a base one with no conversion, exactly as
    /// it does for class inheritance.
    /// </summary>
    public List<FunctionSymbol> VirtualTable { get; } = [];

    /// <summary>This interface, then the one it extends, and so on to IUnknown.</summary>
    public IEnumerable<ComInterfaceTypeSymbol> SelfAndBases()
    {
        for (var current = this; current is not null; current = current.BaseInterface)
            yield return current;
    }

    /// <summary>True when <paramref name="other"/> is this interface or one it extends.</summary>
    public bool DerivesFrom(ComInterfaceTypeSymbol other) => SelfAndBases().Contains(other);

    /// <summary>Position of a method in the vtable, or -1.</summary>
    public int SlotOf(FunctionSymbol method) => VirtualTable.IndexOf(method);

    // A derived interface's members are its own and its base's, nearest first,
    // which is the same rule a derived class follows.

    public override FunctionSymbol? FindMethod(string name) =>
        SelfAndBases().Select(i => i.Methods.FirstOrDefault(m => m.Name == name))
            .FirstOrDefault(m => m is not null);

    public override IEnumerable<FunctionSymbol> FindMethods(string name) =>
        SelfAndBases().SelectMany(i => i.Methods.Where(m => m.Name == name));

    public override PropertySymbol? FindProperty(string name) =>
        SelfAndBases().Select(i => i.Properties.FirstOrDefault(p => p.Name == name))
            .FirstOrDefault(p => p is not null);
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

    /// <summary>
    /// Where a com class's tear-offs begin: after the header and the fields,
    /// rounded up so each vtable pointer is aligned.
    /// </summary>
    public int TearOffsStart => (HeaderSize + FieldsSize + 7) & ~7;

    /// <summary>A vtable pointer and the distance back to the object.</summary>
    public const int TearOffSize = 16;

    /// <summary>Where the tear-off for one presented interface sits.</summary>
    public int TearOffOffset(ComInterfaceTypeSymbol presented) =>
        TearOffsStart + ComInterfaces.IndexOf(presented) * TearOffSize;

    /// <summary>
    /// Total heap allocation: header, fields (the base's included), and, for a
    /// com class, one tear-off per interface it presents.
    /// </summary>
    public int InstanceSize => IsCom && ComInterfaces.Count > 0
        ? TearOffsStart + ComInterfaces.Count * TearOffSize
        : HeaderSize + FieldsSize;

    public List<FunctionSymbol> Constructors { get; } = [];
    public FunctionSymbol? Destructor { get; set; }

    /// <summary>
    /// The class this one derives from, or null.
    ///
    /// Single inheritance is what keeps the object model intact: the base
    /// subobject starts where the derived object does, so an upcast is the same
    /// pointer, reference identity stays pointer identity, and <c>sl_retain</c>
    /// goes on taking the object's own address. Multiple inheritance would end
    /// all three at once; see TODO.md.
    /// </summary>
    public ClassTypeSymbol? BaseClass { get; set; }

    /// <summary>
    /// Declared <c>com class</c>: an ordinary Stainless object, reference
    /// counted and destroyed as usual, that also presents COM vtables so other
    /// languages can hold it.
    ///
    /// The header and fields are unchanged. What is added is one tear-off per
    /// implemented interface, laid out after the fields, each holding a vtable
    /// pointer and its own distance back to the object -- which is how a
    /// Release arriving through any of them finds the header.
    /// </summary>
    public bool IsCom { get; set; }

    /// <summary>The com interfaces this class presents, in tear-off order.</summary>
    public List<ComInterfaceTypeSymbol> ComInterfaces { get; } = [];

    /// <summary>Declared <c>abstract</c>: <c>new</c> refuses it.</summary>
    public bool IsAbstract { get; set; }

    /// <summary>Declared <c>sealed</c>: nothing may derive from it.</summary>
    public bool IsSealed { get; set; }

    /// <summary>
    /// This class's dispatch table, in slot order: every virtual method it
    /// inherits, with its overrides in place, then the ones it adds. Filled in
    /// pass 5, and emitted verbatim.
    /// </summary>
    public List<FunctionSymbol> VirtualTable { get; } = [];

    /// <summary>This class, then its base, then its base's base.</summary>
    public IEnumerable<ClassTypeSymbol> SelfAndBases()
    {
        for (var current = this; current is not null; current = current.BaseClass)
            yield return current;
    }

    /// <summary>True when <paramref name="other"/> is this class or one it derives from.</summary>
    public bool DerivesFrom(ClassTypeSymbol other) => SelfAndBases().Contains(other);

    /// <summary>Where this class's own fields begin, after everything it inherited.</summary>
    public int InheritedFieldsSize => BaseClass?.FieldsSize ?? 0;

    // ------------------------------------------------------------- lookup
    //
    // A derived class's members are its own and its base's. Every one of these
    // searches nearest first, so a name declared here wins over the same name
    // further up -- which is what naming a member through the derived type has
    // always meant.

    public override FieldSymbol? FindField(string name) =>
        SelfAndBases().Select(c => c.Fields
            .FirstOrDefault(f => f.Name == name && !f.IsBackingField))
            .FirstOrDefault(f => f is not null);

    public override FieldSymbol? FindStorage(string name) =>
        SelfAndBases().Select(c => c.Fields.FirstOrDefault(f => f.Name == name))
            .FirstOrDefault(f => f is not null);

    public override PropertySymbol? FindProperty(string name) =>
        SelfAndBases().Select(c => c.Properties.FirstOrDefault(p => p.Name == name))
            .FirstOrDefault(p => p is not null);

    public override FunctionSymbol? FindMethod(string name) =>
        SelfAndBases().Select(c => c.Methods.FirstOrDefault(m => m.Name == name))
            .FirstOrDefault(m => m is not null);

    /// <summary>
    /// Every method of this name, nearest first, with an inherited one dropped
    /// once a nearer declaration has the same parameters -- which is exactly
    /// when the nearer one is the override of it.
    /// </summary>
    public override IEnumerable<FunctionSymbol> FindMethods(string name)
    {
        var seen = new List<FunctionSymbol>();

        foreach (var candidate in SelfAndBases().SelectMany(c => c.Methods.Where(m => m.Name == name)))
        {
            var signature = candidate.ParameterTypes.ToList();
            if (seen.Any(m => m.Accepts(signature))) continue;

            seen.Add(candidate);
            yield return candidate;
        }
    }

    /// <summary>Every field laid out in an instance, base's first, in offset order.</summary>
    public IEnumerable<FieldSymbol> AllFields() =>
        SelfAndBases().Reverse().SelectMany(c => c.Fields);
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
