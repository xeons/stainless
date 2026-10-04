// Stainless - an experimental general-purpose language.
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

namespace Stainless.Bindgen;

/// <summary>What a declaration says about the macOS it needs.</summary>
public sealed record Availability(string? Introduced, string? Deprecated, bool Unavailable)
{
    public static readonly Availability Always = new(null, null, false);
}

/// <summary>A declaration at file scope, and the header it was written in.</summary>
public abstract record CDecl(string Name, string File)
{
    public Availability Availability { get; init; } = Availability.Always;
}

public sealed record CParameter(string? Name, CType Type)
{
    public Nullability Nullability { get; init; }

    /// <summary>Spelled <c>__autoreleasing</c>: an object the callee stores for the caller, as an <c>NSError **</c> is.</summary>
    public bool IsAutoreleasing { get; init; }

    /// <summary><c>ns_consumed</c> or <c>cf_consumed</c>: the callee takes a reference it was given.</summary>
    public bool IsConsumed { get; init; }
}

public sealed record CFunctionDecl(
    string Name, string File, CType Result, IReadOnlyList<CParameter> Parameters, bool Variadic)
    : CDecl(Name, File)
{
    public Nullability ResultNullability { get; init; }

    /// <summary>True for <c>ns_returns_retained</c> or <c>cf_returns_retained</c>, false for their opposites, null for neither.</summary>
    public bool? ReturnsRetained { get; init; }

    /// <summary><c>static inline</c>: its body is in the header and nothing exports it.</summary>
    public bool IsInline { get; init; }

    /// <summary>An <c>asm</c> label, which links it under another name.</summary>
    public string? AsmLabel { get; init; }
}

public sealed record CField(string? Name, CType Type, int? BitWidth)
{
    /// <summary>A nameless struct or union whose members belong to the enclosing one.</summary>
    public CRecordDecl? Inline { get; init; }

    /// <summary>What <c>__attribute__((aligned))</c> on the field asks for, or null.</summary>
    public int? Alignment { get; init; }
}

public sealed record CRecordDecl(string Name, string File, CTagKind Kind) : CDecl(Name, File)
{
    /// <summary>False for <c>struct __CFString;</c>, which is only ever pointed at.</summary>
    public bool IsComplete { get; init; }

    public bool IsPacked { get; init; }

    /// <summary>Bridged to an Objective-C class, as every toll-free Core Foundation type is.</summary>
    public bool IsBridged { get; init; }

    public int? Alignment { get; init; }

    public List<CField> Fields { get; } = [];

    /// <summary>For a record with no tag, where clang placed it, which is how its type names it.</summary>
    public string? AnonymousAt { get; init; }

    /// <summary>True when the name is a typedef's, given to a record with no tag; C has no <c>struct Name</c>.</summary>
    public bool IsTypedefName { get; init; }

    /// <summary>True when it was declared under a <c>#pragma pack</c>, whose value the dump does not say.</summary>
    public bool HasPragmaPack { get; init; }

    /// <summary>The most a field is aligned to under that pragma, once clang has been asked.</summary>
    public int? Pack { get; set; }

    /// <summary>How C names it: its tag, or the typedef that named it.</summary>
    public string CSpelling => IsTypedefName ? Name : $"{(Kind == CTagKind.Union ? "union" : "struct")} {Name}";
}

/// <param name="IsWritten">
/// True when clang folded a value written for it; false for one that follows
/// the last, or one whose expression did not compile.
/// </param>
public sealed record CEnumMember(string Name, System.Numerics.BigInteger Value, bool IsWritten = true);

public sealed record CEnumDecl(string Name, string File) : CDecl(Name, File)
{
    /// <summary>The type written after the colon, or null for an int-sized enum.</summary>
    public CType? Underlying { get; init; }

    public bool IsFlags { get; init; }

    public List<CEnumMember> Members { get; } = [];

    public string? AnonymousAt { get; init; }
}

public sealed record CTypedefDecl(string Name, string File, CType Type) : CDecl(Name, File)
{
    /// <summary><c>const struct __CFString *</c>: what a Core Foundation type's immutable typedef points at.</summary>
    public bool PointsToConst { get; init; }
}

public sealed record CVariableDecl(string Name, string File, CType Type) : CDecl(Name, File)
{
    public Nullability Nullability { get; init; }
}

/// <summary>An Objective-C method, named by its selector.</summary>
public sealed record CObjCMethod(string Selector, bool IsInstance, CType Result, IReadOnlyList<CParameter> Parameters)
{
    public Nullability ResultNullability { get; init; }

    public bool IsVariadic { get; init; }

    /// <summary>A protocol member under <c>@optional</c>.</summary>
    public bool IsOptional { get; init; }

    /// <summary>As on a function: what a returns-retained attribute said, or null.</summary>
    public bool? ReturnsRetained { get; init; }

    public Availability Availability { get; init; } = Availability.Always;

    public int Line { get; init; }
}

/// <summary>An Objective-C property: a getter, and a setter unless it is read-only.</summary>
public sealed record CObjCProperty(string Name, CType Type)
{
    public Nullability Nullability { get; init; }

    public bool IsClass { get; init; }

    public bool IsReadOnly { get; init; }

    public string? Getter { get; init; }

    public string? Setter { get; init; }

    public bool IsOptional { get; init; }

    public Availability Availability { get; init; } = Availability.Always;

    public string GetterSelector => Getter ?? Name;

    public string SetterSelector => Setter ?? $"set{char.ToUpperInvariant(Name[0])}{Name[1..]}:";
}

/// <summary>What a class, a category and a protocol all hold.</summary>
public abstract record CObjCContainer(string Name, string File) : CDecl(Name, File)
{
    public List<string> Protocols { get; } = [];

    public List<CObjCMethod> Methods { get; } = [];

    public List<CObjCProperty> Properties { get; } = [];

    /// <summary>A generic's parameters, <c>ObjectType</c>, which a binding erases to <c>id</c>.</summary>
    public List<string> TypeParameters { get; } = [];

    /// <summary>False for <c>@class X;</c> or <c>@protocol X;</c>, which say only that it exists.</summary>
    public bool IsDefinition { get; init; } = true;
}

public sealed record CObjCInterface(string Name, string File) : CObjCContainer(Name, File)
{
    public string? Super { get; init; }
}

public sealed record CObjCProtocol(string Name, string File) : CObjCContainer(Name, File);

/// <summary>A category: more of <see cref="Class"/>, from wherever it was written.</summary>
public sealed record CObjCCategory(string Name, string File, string Class) : CObjCContainer(Name, File);

/// <summary>Everything one translation unit declared at file scope, in order.</summary>
public sealed class Translation
{
    public List<CDecl> Declarations { get; } = [];

    /// <summary>Every typedef by name, wherever it was declared.</summary>
    public Dictionary<string, CTypedefDecl> Typedefs { get; } = new(StringComparer.Ordinal);

    /// <summary>Every complete struct and union by tag, and the first declaration of each opaque one.</summary>
    public Dictionary<(CTagKind, string), CRecordDecl> Records { get; } = [];

    public Dictionary<string, CEnumDecl> Enums { get; } = new(StringComparer.Ordinal);

    /// <summary>Every Objective-C class and protocol by name: the definition, where there is one.</summary>
    public Dictionary<string, CObjCInterface> Interfaces { get; } = new(StringComparer.Ordinal);

    public Dictionary<string, CObjCProtocol> Protocols { get; } = new(StringComparer.Ordinal);

    /// <summary>Struct tags bridged to an Objective-C class somewhere, which makes them Core Foundation types.</summary>
    public HashSet<string> BridgedRecords { get; } = new(StringComparer.Ordinal);

    /// <summary>Every <c>XGetTypeID</c> taking nothing: a Core Foundation type's, by the name of the type.</summary>
    public HashSet<string> TypeIDFunctions { get; } = new(StringComparer.Ordinal);

    /// <summary>A record or enum with no tag, by where clang placed it.</summary>
    public Dictionary<string, CDecl> Anonymous { get; } = new(StringComparer.Ordinal);
}

/// <summary>
/// An object-like <c>#define</c> from a framework's header, with what clang
/// made of it as an expression: its type, and its value when that is an
/// integer constant.
/// </summary>
public sealed record CMacro(string Name, string File, string Body) : CDecl(Name, File)
{
    public CType? Type { get; init; }

    public System.Numerics.BigInteger? Value { get; init; }
}
