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

using Stainless.Source;

namespace Stainless.Syntax;

public abstract record SyntaxNode(SourceSpan Span);

// ---------------------------------------------------------------- names

/// <summary>A dotted name such as <c>App.Math</c> or <c>Buffer</c>.</summary>
public sealed record QualifiedName(SourceSpan Span, IReadOnlyList<string> Parts) : SyntaxNode(Span)
{
    public string Text => string.Join('.', Parts);
    public string Last => Parts[^1];
    public override string ToString() => Text;
}

// ---------------------------------------------------------------- types

public abstract record TypeSyntax(SourceSpan Span) : SyntaxNode(Span);

/// <summary>A built-in type keyword: <c>int</c>, <c>double</c>, <c>void</c>, …</summary>
public sealed record PrimitiveTypeSyntax(SourceSpan Span, TokenKind Keyword) : TypeSyntax(Span);

/// <summary>
/// A user-declared type referenced by name, with type arguments when the type
/// is generic: <c>Box</c>, <c>Box&lt;int&gt;</c>, <c>Pair&lt;int, String&gt;</c>.
/// </summary>
public sealed record NamedTypeSyntax(
    SourceSpan Span,
    QualifiedName Name,
    IReadOnlyList<TypeSyntax> TypeArguments) : TypeSyntax(Span)
{
    public NamedTypeSyntax(SourceSpan span, QualifiedName name) : this(span, name, []) { }
}

/// <summary><c>T*</c> — a raw, unmanaged, C-compatible pointer.</summary>
public sealed record PointerTypeSyntax(SourceSpan Span, TypeSyntax Element) : TypeSyntax(Span);

/// <summary><c>T[]</c> — a counted array of T.</summary>
public sealed record ArrayTypeSyntax(SourceSpan Span, TypeSyntax Element) : TypeSyntax(Span);

/// <summary><c>T[:]</c> - part of an array, named as a value of its own.</summary>
public sealed record SliceTypeSyntax(SourceSpan Span, TypeSyntax Element) : TypeSyntax(Span);

/// <summary>
/// <c>T[N]</c>: an inline fixed-size array, laid out where it is written rather
/// than pointed at. The length is an expression so that a named constant can be
/// used; it is folded when the type is resolved.
/// </summary>
public sealed record FixedArrayTypeSyntax(
    SourceSpan Span, TypeSyntax Element, ExpressionSyntax Length) : TypeSyntax(Span);

/// <summary><c>T?</c> — an optional class reference.</summary>
public sealed record NullableTypeSyntax(SourceSpan Span, TypeSyntax Element) : TypeSyntax(Span);

/// <summary><c>(int, String)</c> as a type.</summary>
public sealed record TupleTypeSyntax(
    SourceSpan Span, IReadOnlyList<TypeSyntax> Elements) : TypeSyntax(Span);

/// <summary><c>weak T?</c> — a non-owning reference that nulls out on death.</summary>
public sealed record WeakTypeSyntax(SourceSpan Span, TypeSyntax Element) : TypeSyntax(Span);

// ---------------------------------------------------------------- declarations

[Flags]
public enum Modifiers
{
    None = 0,
    Public = 1 << 0,
    Private = 1 << 1,
    Const = 1 << 2,

    /// <summary>
    /// Visible to this type and to anything deriving from it, wherever that is.
    /// It is the one visibility that crosses a module boundary without being
    /// public, and it exists because a base class has to be able to hand its
    /// derived classes something the rest of the program may not touch.
    /// </summary>
    Protected = 1 << 3,

    /// <summary>May be overridden: the call goes through the object's vtable.</summary>
    Virtual = 1 << 4,

    /// <summary>
    /// On an interface or a class, one laid out the way COM lays them out: the
    /// reference points at a vtable pointer rather than at an object header,
    /// and lifetime runs through <c>IUnknown</c> rather than through
    /// <c>sl_retain</c>. See docs/com.md.
    /// </summary>
    Com = 1 << 8,

    /// <summary>Replaces an inherited <c>virtual</c> or <c>abstract</c> member.</summary>
    Override = 1 << 5,

    /// <summary>
    /// On a class, one that cannot be instantiated. On a member, one with no
    /// body that every concrete derived class must supply.
    /// </summary>
    Abstract = 1 << 6,

    /// <summary>
    /// On a class, one nothing may derive from. On an <c>override</c>, one
    /// nothing may override further.
    /// </summary>
    Sealed = 1 << 7,

    /// <summary>
    /// On a member, one that belongs to the type rather than to an instance of
    /// it: no receiver, and so no access to a field. On a module-level
    /// declaration, <c>static readonly</c> storage.
    /// </summary>
    Static = 1 << 9,

    /// <summary>
    /// On a type, one whose author says every operation on it synchronizes
    /// itself, so more than one thread may hold it at once. An assertion, not
    /// something the compiler can check.
    /// </summary>
    Threadsafe = 1 << 10,
}

/// <summary>
/// <c>using Handle = void*;</c>: a second name for a type.
///
/// The word is free here because <c>import</c> took the job C# gives it, and it
/// means what a C# programmer expects it to mean. The alias is exactly the type
/// it names -- there is no wrapper and no conversion -- so what it buys is that
/// a signature says what it is for. Distinctness comes from the type it names
/// being distinct, which is what an opaque struct is for.
/// </summary>
public sealed record AliasDeclSyntax(
    SourceSpan Span,
    Modifiers Modifiers,
    string Name,
    TypeSyntax Target) : Declaration(Span, Modifiers);

/// <summary>How a declaration crosses the language boundary.</summary>
public enum LinkageKind
{
    /// <summary>Ordinary Stainless linkage: the symbol name is mangled.</summary>
    Stainless,
    /// <summary>Declared elsewhere in C; imported by its unmangled name.</summary>
    ExternC,
    /// <summary>Defined here but emitted unmangled so C can call it.</summary>
    ExportC,

    /// <summary>Declared elsewhere in C++; imported by its mangled name.</summary>
    ExternCpp,

    /// <summary>Defined here but mangled the C++ way so C++ can call it.</summary>
    ExportCpp,
}

/// <summary>Whether a linkage kind names something outside this program.</summary>
public static class LinkageKinds
{
    public static bool IsImport(this LinkageKind linkage) =>
        linkage is LinkageKind.ExternC or LinkageKind.ExternCpp;

    public static bool IsCpp(this LinkageKind linkage) =>
        linkage is LinkageKind.ExternCpp or LinkageKind.ExportCpp;

    /// <summary>True when the name crosses to another language and is not mangled by us.</summary>
    public static bool IsForeign(this LinkageKind linkage) => linkage != LinkageKind.Stainless;
}

/// <summary>
/// How a function passes its arguments and who cleans up after the call.
///
/// <para>
/// There is one answer on every 64-bit target, and <c>__vectorcall</c> is the
/// only name that means anything there. On x86 the choice is real and visible
/// in the linker symbol: <c>__stdcall</c> is what Win32 uses, and the name
/// carries the number of bytes its arguments occupy.
/// </para>
/// </summary>
public enum CallingConvention
{
    /// <summary>None written. The platform's default, which is <c>Cdecl</c>
    /// everywhere this compiler targets.</summary>
    Default,

    /// <summary>
    /// <c>__cdecl</c>: the caller pushes the arguments and the caller removes
    /// them, which is what makes a variadic call possible at all.
    /// </summary>
    Cdecl,

    /// <summary>
    /// <c>__stdcall</c>: the callee removes the arguments, so a call site and a
    /// declaration that disagree about how many there are corrupt the stack.
    /// That is why the byte count is in the name -- the linker catches it.
    /// </summary>
    Stdcall,

    /// <summary><c>__fastcall</c>: the first two integer arguments in ECX and
    /// EDX, the rest on the stack, and the callee cleans up.</summary>
    Fastcall,

    /// <summary>
    /// <c>__vectorcall</c>: <c>__fastcall</c> extended with vector registers
    /// for floating-point arguments. The one convention that still differs on
    /// x64.
    /// </summary>
    Vectorcall,
}

public abstract record Declaration(SourceSpan Span, Modifiers Modifiers) : SyntaxNode(Span)
{
    /// <summary>
    /// The <c>///</c> block written above this declaration, or null.
    ///
    /// An <c>init</c> property rather than a positional parameter, because
    /// every declaration has one and none of them constructs it: the parser
    /// takes it from the first token of the declaration and applies it to
    /// whatever came back, in one place.
    /// </summary>
    public string? Documentation { get; init; }
}

/// <summary>
/// How a parameter is passed.
///
/// <c>Value</c> is a copy, and is everything the language had. <c>Ref</c> and
/// <c>In</c> both pass the caller's storage rather than a copy of it; the
/// difference is that the callee may write through a <c>ref</c> and may not
/// write through an <c>in</c>. Both are exactly a <c>T*</c> at the ABI, which
/// is why they cross <c>extern "C"</c> with nothing in between.
/// </summary>
/// <summary>
/// How a parameter travels. <c>Ref</c>, <c>In</c> and <c>Out</c> are all one
/// pointer at the ABI; what separates them is who may write and who must.
/// </summary>
public enum ParameterMode { Value, Ref, In, Out }

/// <param name="Default">
/// The <c>= value</c> a caller may leave out, or null when there is none. It
/// stays syntax here because a signature is resolved before any constant is
/// folded; what it is worth is settled in a pass of its own.
/// </param>
public sealed record ParameterSyntax(
    SourceSpan Span,
    TypeSyntax Type,
    string Name,
    ParameterMode Mode = ParameterMode.Value,
    ExpressionSyntax? Default = null) : SyntaxNode(Span);

/// <summary>
/// <c>ref x</c> at a call. Written at the call as well as the declaration,
/// because a caller reading the line should be able to see that the value may
/// come back changed.
/// </summary>
public sealed record RefArgumentSyntax(SourceSpan Span, ExpressionSyntax Value)
    : ExpressionSyntax(Span);

/// <summary>
/// <c>out x</c> at a call, and the two forms that declare what they name:
/// <c>out int x</c> and <c>out var x</c>.
///
/// Declaring at the call is most of why <c>out</c> is worth having over
/// <c>ref</c> — the variable exists to catch the answer, and a line above
/// saying so is a line about the mechanism.
/// </summary>
/// <param name="DeclaredType">
/// The type in <c>out int x</c>, null for <c>out var x</c>, and unused when
/// <see cref="Value"/> names something that already exists.
/// </param>
/// <summary>
/// <c>name: value</c> at a call.
///
/// It says which parameter the value is for, so a call with several arguments
/// of one type reads as what it means rather than as a count. Named arguments
/// come after the positional ones: mixing the two orders freely would make a
/// reader work out the mapping to see what a call does.
/// </summary>
public sealed record NamedArgumentSyntax(
    SourceSpan Span,
    string Name,
    SourceSpan NameSpan,
    ExpressionSyntax Value) : ExpressionSyntax(Span);

public sealed record OutArgumentSyntax(
    SourceSpan Span,
    ExpressionSyntax? Value,
    TypeSyntax? DeclaredType,
    string? DeclaredName,
    SourceSpan NameSpan) : ExpressionSyntax(Span);

public sealed record FunctionDeclSyntax(
    SourceSpan Span,
    Modifiers Modifiers,
    LinkageKind Linkage,
    TypeSyntax ReturnType,
    string Name,
    IReadOnlyList<string> TypeParameters,
    IReadOnlyList<WhereClauseSyntax> Constraints,
    IReadOnlyList<ParameterSyntax> Parameters,
    bool IsVariadic,
    BlockSyntax? Body) : Declaration(Span, Modifiers)
{
    /// <summary>
    /// The enclosing C++ namespace, outermost first, from a name written as
    /// <c>geometry::inner::Name</c>. Empty for global scope, and for everything
    /// that is not C++.
    /// </summary>
    public IReadOnlyList<string> Namespace { get; init; } = [];

    /// <summary>
    /// True for <c>static T operator +(...)</c>. The name is already the
    /// lowered one -- <c>op_Add</c> -- and this is what says it was written as
    /// an operator rather than called that.
    /// </summary>
    public bool IsOperator { get; init; }

    /// <summary>Which operator, for the checks that depend on which.</summary>
    public TokenKind OperatorToken { get; init; }

    /// <summary>
    /// True for <c>static implicit operator Money(long)</c> and its explicit
    /// twin. A conversion is an operator whose name is a type rather than a
    /// punctuation mark, which is why it is a flag here rather than another
    /// entry in <see cref="OperatorNames"/>.
    /// </summary>
    public bool IsConversion { get; init; }

    /// <summary>True when the conversion was written <c>implicit</c>.</summary>
    public bool IsImplicitConversion { get; init; }

    /// <summary>
    /// The convention written before the return type, or
    /// <see cref="CallingConvention.Default"/>.
    /// </summary>
    public CallingConvention CallingConvention { get; init; }
}

public sealed record FieldDeclSyntax(
    SourceSpan Span,
    Modifiers Modifiers,
    TypeSyntax Type,
    string Name,
    ExpressionSyntax? Initializer,
    IReadOnlyList<AttributeSyntax> Attributes) : Declaration(Span, Modifiers)
{
    /// <summary><c>int flags : 3;</c> — how many bits, or null for a whole field.</summary>
    public ExpressionSyntax? BitWidth { get; init; }

    /// <summary>
    /// What <c>extern "C"</c> or <c>export "C"</c> was written in front of this,
    /// or <see cref="LinkageKind.Stainless"/> for an ordinary field.
    ///
    /// A field inside a type ignores it -- a struct's member has no linkage of
    /// its own, only the struct does. At module scope it is the whole of what
    /// makes <c>extern "C" int errno;</c> a declaration of C's variable rather
    /// than an error.
    /// </summary>
    public LinkageKind Linkage { get; init; }

    /// <summary>
    /// True for the field a nameless <c>struct { }</c> or <c>union { }</c>
    /// member becomes. The field is real and holds the layout; the name is
    /// generated and unwritable, and lookup reaches through it so that the
    /// members inside read as if they were the parent's own.
    /// </summary>
    public bool IsAnonymous { get; init; }

    public FieldDeclSyntax(
        SourceSpan span, Modifiers modifiers, TypeSyntax type, string name,
        ExpressionSyntax? initializer)
        : this(span, modifiers, type, name, initializer, []) { }
}

/// <summary>
/// One accessor of a property.
///
/// A null <see cref="Body"/> is <c>get;</c> written bare. On a class or struct
/// that asks for the compiler-generated backing field; on an interface it is
/// the whole declaration, because an interface has no bodies at all.
/// </summary>
public sealed record AccessorSyntax(
    SourceSpan Span,
    Modifiers Modifiers,
    bool IsGetter,
    BlockSyntax? Body) : SyntaxNode(Span);

/// <summary>
/// <c>public int Age { get; private set; }</c> — a property.
///
/// A property is a pair of methods that reads like a field. Written bare it
/// also owns a hidden field to keep the value in; written with bodies it owns
/// no storage at all and names whatever the type already has.
/// </summary>
public sealed record PropertyDeclSyntax(
    SourceSpan Span,
    Modifiers Modifiers,
    TypeSyntax Type,
    string Name,
    IReadOnlyList<AccessorSyntax> Accessors,
    IReadOnlyList<AttributeSyntax> Attributes) : Declaration(Span, Modifiers)
{
    /// <summary>
    /// What goes between the brackets of an indexer, and empty for an ordinary
    /// property. An indexer is a property that takes arguments, so this is the
    /// only thing that separates the two.
    /// </summary>
    public IReadOnlyList<ParameterSyntax> Indices { get; init; } = [];

    public bool IsIndexer => Indices.Count > 0;

    /// <summary>
    /// The <c>= value</c> after the accessor list, or null. Only an automatic
    /// property may have one: it is the storage that is being given a value,
    /// and a property with written accessors owns none.
    /// </summary>
    public ExpressionSyntax? Initializer { get; init; }
}

/// <summary>
/// <c>public event Notify Fired;</c> — a list of subscribers that reads like a
/// closure.
///
/// It owns hidden storage the way an automatic property does, and the two
/// methods that reach it are what <c>+=</c> and <c>-=</c> lower to. What it is
/// not is a field: from outside the declaring type those two operators are the
/// only things that can be written, which is the whole reason the word exists
/// rather than a public field of closure type.
/// </summary>
public sealed record EventDeclSyntax(
    SourceSpan Span,
    Modifiers Modifiers,
    TypeSyntax Type,
    string Name,
    IReadOnlyList<AttributeSyntax> Attributes) : Declaration(Span, Modifiers);

public sealed record ConstructorDeclSyntax(
    SourceSpan Span,
    Modifiers Modifiers,
    string TypeName,
    IReadOnlyList<ParameterSyntax> Parameters,
    BlockSyntax Body) : Declaration(Span, Modifiers);

public sealed record DestructorDeclSyntax(
    SourceSpan Span,
    string TypeName,
    BlockSyntax Body) : Declaration(Span, Modifiers.None);

/// <summary>
/// <c>where T : Shape, Named</c> — the interfaces a type argument must
/// implement. Verified when the generic is instantiated.
/// </summary>
public sealed record WhereClauseSyntax(
    SourceSpan Span,
    string TypeParameter,
    IReadOnlyList<ConstraintSyntax> Constraints) : SyntaxNode(Span);

/// <summary>What one constraint after the colon demands of a type parameter.</summary>
public enum ConstraintKind
{
    /// <summary>An interface to implement, a class to derive from, or another
    /// type parameter to be.</summary>
    Type,

    /// <summary><c>class</c>: a reference type, so it may be null and is counted.</summary>
    Class,

    /// <summary><c>struct</c>: a value type, so it is copied and never null.</summary>
    Struct,

    /// <summary><c>new()</c>: something the body may construct with no arguments.</summary>
    New,

    /// <summary>
    /// <c>threadsafe</c>: something more than one thread may hold. The one
    /// constraint that is a hard error where the same fact is only a warning
    /// at a <c>spawn</c> -- because here a library author has asked for it in
    /// their own signature, rather than a compiler having guessed.
    /// </summary>
    Threadsafe,
}

/// <summary>
/// One constraint: <c>IComparable&lt;T&gt;</c>, <c>class</c>, <c>struct</c> or
/// <c>new()</c>.
///
/// A kind rather than four record types, because every consumer switches on
/// all of them and the payload is at most a type.
/// </summary>
public sealed record ConstraintSyntax(
    SourceSpan Span,
    ConstraintKind Kind,
    TypeSyntax? Type) : SyntaxNode(Span);

/// <summary>
/// An attribute applied to a declaration: <c>[JsonName("id")]</c>. Arguments
/// must be constants, because the values are written into the binary.
/// </summary>
public sealed record AttributeSyntax(
    SourceSpan Span,
    QualifiedName Name,
    IReadOnlyList<ExpressionSyntax> Arguments) : SyntaxNode(Span);

/// <summary>
/// <c>delegate int Comparison(int a, int b);</c> — a named function pointer
/// type. It is one pointer with the platform C calling convention, so it is the
/// same value a C function pointer is.
/// </summary>
/// <param name="CarriesReceiver">
/// True when this was written <c>closure</c> rather than <c>delegate</c>: two
/// words, a function and the object it is bound to, rather than one. Delphi
/// spells the same distinction <c>of object</c>.
/// </param>
public sealed record DelegateDeclSyntax(
    SourceSpan Span,
    Modifiers Modifiers,
    string Name,
    TypeSyntax ReturnType,
    IReadOnlyList<ParameterSyntax> Parameters,
    bool CarriesReceiver = false,
    IReadOnlyList<string>? TypeParameters = null,
    CallingConvention Convention = CallingConvention.Default)
    : Declaration(Span, Modifiers)
{
    /// <summary>
    /// <c>delegate __stdcall int Callback(int value);</c>, or
    /// <see cref="CallingConvention.Default"/>.
    ///
    /// A delegate is the only type that needs one. Everywhere else the
    /// convention belongs to a symbol -- a function declares it and the linker
    /// name carries it -- but a delegate names no symbol: it is a pointer, and
    /// what it points at was compiled by somebody else. So the convention has
    /// to be part of the type, or the call through it cannot be emitted
    /// correctly.
    ///
    /// It matters on x86 and nowhere else. The x64 and ARM64 ABIs have one
    /// convention, so this is ignored there -- which is exactly why a program
    /// that omits it works on the machine it was written on and corrupts the
    /// stack on the 32-bit build.
    /// </summary>
    public CallingConvention Convention { get; init; } = Convention;

    /// <summary>
    /// The names in <c>closure R Apply&lt;T, R&gt;(T value);</c>, or empty.
    ///
    /// A generic closure is what lets a library take "something to call" over a
    /// type it does not know -- which is the whole of why
    /// <c>Standard.Collections</c> had five one-method interfaces before this
    /// existed.
    /// </summary>
    public IReadOnlyList<string> TypeParameters { get; init; } = TypeParameters ?? [];
}

/// <summary>One <c>enum</c> member, with the constant it was given if any.</summary>
public sealed record EnumMemberSyntax(SourceSpan Span, string Name, ExpressionSyntax? Value)
    : SyntaxNode(Span)
{
    /// <summary>The <c>///</c> block written above this case, or null.</summary>
    public string? Documentation { get; init; }
}

/// <summary>
/// <c>enum Color { Red, Green }</c>, optionally over a chosen integer type as in
/// <c>enum Level : byte { ... }</c>.
/// </summary>
public sealed record EnumDeclSyntax(
    SourceSpan Span,
    Modifiers Modifiers,
    string Name,
    TypeSyntax? UnderlyingType,
    IReadOnlyList<EnumMemberSyntax> Members,
    IReadOnlyList<AttributeSyntax> Attributes) : Declaration(Span, Modifiers);

public enum TypeDeclKind { Struct, Class, Interface, Attribute, Variant, Union }

/// <summary>
/// One case of a <c>variant</c>: <c>Circle(double radius);</c>, or
/// <c>Empty;</c> for one that carries nothing.
///
/// The parameters are the payload's fields rather than a signature. A case is
/// how the value is built and how it is matched, so the names are reachable in
/// both directions and are not documentation the way a delegate's are.
/// </summary>
public sealed record VariantCaseSyntax(
    SourceSpan Span,
    string Name,
    IReadOnlyList<ParameterSyntax> Parameters) : SyntaxNode(Span)
{
    /// <summary>The <c>///</c> block written above this case, or null.</summary>
    public string? Documentation { get; init; }
}

/// <summary>
/// A type declaration. <c>IsOpaque</c> marks one written <c>struct HWND__;</c>,
/// with no body at all: a type whose layout is declared somewhere else and is
/// never known here. It is C's incomplete type, and the only thing that can be
/// done with one is point at it.
/// </summary>
public sealed record TypeDeclSyntax(
    SourceSpan Span,
    Modifiers Modifiers,
    TypeDeclKind Kind,
    string Name,
    IReadOnlyList<string> TypeParameters,
    IReadOnlyList<WhereClauseSyntax> Constraints,
    IReadOnlyList<TypeSyntax> Implements,
    IReadOnlyList<Declaration> Members,
    IReadOnlyList<AttributeSyntax> Attributes) : Declaration(Span, Modifiers)
{
    /// <summary>A variant's cases; empty for every other kind of declaration.</summary>
    public IReadOnlyList<VariantCaseSyntax> Cases { get; init; } = [];

    /// <summary>True for one written with no body at all: <c>struct HWND__;</c>.</summary>
    public bool IsOpaque { get; init; }
}

/// <summary>
/// <c>public static readonly List&lt;String&gt; Registry = ...;</c> — module-level
/// storage, initialized once before <c>Main</c>, and the same shape written
/// inside a type.
///
/// There is no <c>static</c> without <c>readonly</c>: a plainly mutable global
/// is shared state that nothing synchronizes, and that is the bug this language
/// would rather not have. Mutation goes through a type that says how it is safe.
/// </summary>
/// <param name="Value">
/// The initializer, or null where none was written. Null is a mistake in every
/// case but one — <c>[Embed]</c>, whose object the linker makes, so there is
/// nothing for an initializer to do — and which of the two it is is a question
/// only the binder can answer.
/// </param>
public sealed record StaticDeclSyntax(
    SourceSpan Span,
    Modifiers Modifiers,
    TypeSyntax Type,
    string Name,
    ExpressionSyntax? Value,
    bool IsReadonly,
    IReadOnlyList<AttributeSyntax> Attributes) : Declaration(Span, Modifiers);

/// <summary>
/// <c>static Name() { ... }</c> inside a type: the block that runs before the
/// type's statics are read.
///
/// C# runs one lazily, before first use, behind a guard checked on every
/// access. This one runs in the same order the static initializers do -- the
/// whole program is compiled together, so the order is known -- which costs
/// nothing per access and turns a cycle into a compile error.
/// </summary>
public sealed record StaticConstructorDeclSyntax(
    SourceSpan Span,
    string TypeName,
    BlockSyntax Body) : Declaration(Span, Modifiers.Static);

/// <summary>A module-level <c>const</c>.</summary>
public sealed record GlobalConstDeclSyntax(
    SourceSpan Span,
    Modifiers Modifiers,
    TypeSyntax? Type,
    string Name,
    ExpressionSyntax Value) : Declaration(Span, Modifiers);

// ---------------------------------------------------------------- compilation unit

public sealed record ImportSyntax(SourceSpan Span, QualifiedName Name, string? Alias) : SyntaxNode(Span);

public sealed record CompilationUnitSyntax(
    SourceSpan Span,
    SourceText File,
    QualifiedName? ModuleName,
    IReadOnlyList<ImportSyntax> Imports,
    IReadOnlyList<Declaration> Declarations,
    IReadOnlyList<string> Libraries) : SyntaxNode(Span)
{
    /// <summary>
    /// The <c>///</c> block written above <c>module X;</c>, or null.
    ///
    /// A module may span files, so several units can each carry one; what reads
    /// them decides what to do with more than one. The standard library writes
    /// it in whichever file is the module's centre and leaves the rest silent.
    /// </summary>
    public string? Documentation { get; init; }
}

// ---------------------------------------------------------------- statements

public abstract record StatementSyntax(SourceSpan Span) : SyntaxNode(Span);

public sealed record BlockSyntax(SourceSpan Span, IReadOnlyList<StatementSyntax> Statements)
    : StatementSyntax(Span);

/// <summary>
/// <c>var (count, name) = Split(line);</c> — a tuple taken apart into locals.
///
/// The names are here rather than in the type, because this is where a name is
/// actually wanted: a tuple's own fields are <c>Item1</c> upwards, and what
/// they mean is a property of the call that produced them.
/// </summary>
public sealed record DeconstructSyntax(
    SourceSpan Span,
    IReadOnlyList<string> Names,
    IReadOnlyList<SourceSpan> NameSpans,
    ExpressionSyntax Value) : StatementSyntax(Span);

/// <summary>A local declaration. A null <see cref="Type"/> means <c>var</c>.</summary>
public sealed record LocalDeclSyntax(
    SourceSpan Span,
    TypeSyntax? Type,
    string Name,
    ExpressionSyntax? Initializer,
    bool IsConst) : StatementSyntax(Span);

public sealed record ExpressionStatementSyntax(SourceSpan Span, ExpressionSyntax Expression)
    : StatementSyntax(Span);

public sealed record IfSyntax(
    SourceSpan Span,
    ExpressionSyntax Condition,
    StatementSyntax Then,
    StatementSyntax? Else) : StatementSyntax(Span);

public sealed record WhileSyntax(SourceSpan Span, ExpressionSyntax Condition, StatementSyntax Body)
    : StatementSyntax(Span);

/// <summary>
/// <c>do { ... } while (c);</c> -- a loop whose body runs before its condition
/// is first asked, which is the whole of the difference from <c>while</c>.
/// </summary>
public sealed record DoWhileSyntax(
    SourceSpan Span, StatementSyntax Body, ExpressionSyntax Condition) : StatementSyntax(Span);

public sealed record ForSyntax(
    SourceSpan Span,
    StatementSyntax? Initializer,
    ExpressionSyntax? Condition,
    ExpressionSyntax? Step,
    StatementSyntax Body) : StatementSyntax(Span);

/// <summary>
/// <c>foreach (T item in collection) body</c>. A null <see cref="Type"/> means
/// <c>var</c>, and the element type comes from the collection.
/// </summary>
public sealed record ForEachSyntax(
    SourceSpan Span,
    TypeSyntax? Type,
    string Name,
    ExpressionSyntax Collection,
    StatementSyntax Body) : StatementSyntax(Span);

/// <summary>
/// <c>parallel { ... }</c> — a fork-join scope. Every <c>spawn</c> inside it has
/// finished by the closing brace, which is what lets a job borrow the enclosing
/// function's locals.
/// </summary>
public sealed record ParallelSyntax(SourceSpan Span, BlockSyntax Body) : StatementSyntax(Span);

/// <summary>
/// <c>for parallel (int i = 0; i &lt; n; i = i + 1) { ... }</c> — the loop's
/// iterations split into chunks across the pool. It opens and joins its own
/// scope, so it needs no enclosing <c>parallel</c>.
/// </summary>
public sealed record ParallelForSyntax(
    SourceSpan Span,
    StatementSyntax Initializer,
    ExpressionSyntax Condition,
    ExpressionSyntax Step,
    StatementSyntax Body) : StatementSyntax(Span);

/// <summary>
/// <c>spawn f(x);</c> or <c>result = spawn f(x);</c> — queues a call on the
/// enclosing <c>parallel</c> scope. The assignment happens on the worker, into
/// storage the parent still owns, which is why <c>Target</c> is held apart from
/// the call rather than left as an assignment the worker would have to run.
/// </summary>
public sealed record SpawnSyntax(
    SourceSpan Span,
    ExpressionSyntax? Target,
    ExpressionSyntax Call) : StatementSyntax(Span);

/// <summary>
/// One labelled section of a <c>switch</c>. Several labels may stack onto one
/// body, and <c>default</c> is one of them — spelled as a flag rather than an
/// expression, because it matches by position rather than by value.
/// </summary>
public sealed record SwitchSectionSyntax(
    SourceSpan Span,
    IReadOnlyList<ExpressionSyntax> Labels,
    bool HasDefault,
    IReadOnlyList<StatementSyntax> Statements) : SyntaxNode(Span)
{
    /// <summary>
    /// The patterns this section's labels were written as, one per label.
    ///
    /// Every label is a pattern; <see cref="Labels"/> is the subset that are
    /// plain constants, kept because a switch all of whose labels are constants
    /// becomes one LLVM <c>switch</c> instruction and a jump table, and that is
    /// most switches.
    /// </summary>
    public IReadOnlyList<PatternSyntax> Patterns { get; init; } = [];

    /// <summary>
    /// The <c>when</c> a label carried, one per pattern and null where there
    /// was none.
    /// </summary>
    public IReadOnlyList<ExpressionSyntax?> Guards { get; init; } = [];

    /// <summary>
    /// The <c>case Circle c:</c> labels, which name a variant's case and bind
    /// its payload.
    ///
    /// <c>case Circle:</c> without a binding is not here: it parses as an
    /// ordinary expression label, because at that point nothing knows whether
    /// <c>Circle</c> is a variant's case or a constant. The binder settles it,
    /// which is where the switched type is known.
    /// </summary>
    public IReadOnlyList<CaseBindingSyntax> Bindings { get; init; } = [];
}

/// <summary><c>case Circle c:</c> — a variant case, and a name for its payload.</summary>
public sealed record CaseBindingSyntax(SourceSpan Span, string Case, string Name)
    : SyntaxNode(Span);

// ---------------------------------------------------------------- patterns

/// <summary>
/// What a value is matched against: in a <c>case</c> label, in a <c>switch</c>
/// expression's arm, and in <c>is</c>.
///
/// A pattern is not an expression. It asks a question about a value rather than
/// producing one, and some of them -- a type pattern with a name -- put
/// something in scope where the question was answered yes.
/// </summary>
public abstract record PatternSyntax(SourceSpan Span) : SyntaxNode(Span);

/// <summary>
/// <c>case 3:</c>, <c>case "text":</c>, <c>case Level.Low:</c> -- and
/// <c>case Circle:</c>, which is a bare name that nothing here can tell from a
/// constant. The binder settles that, where the switched type is known.
/// </summary>
public sealed record ConstantPatternSyntax(SourceSpan Span, ExpressionSyntax Value)
    : PatternSyntax(Span);

/// <summary><c>case &gt; 5:</c> -- one comparison against a constant.</summary>
public sealed record RelationalPatternSyntax(
    SourceSpan Span, TokenKind Operator, ExpressionSyntax Value) : PatternSyntax(Span);

/// <summary>
/// <c>case Square:</c> and <c>case Square s:</c> -- what the value really is,
/// and a name for it. Over a variant the type is one of its cases and the name
/// is what that case carries.
/// </summary>
public sealed record TypePatternSyntax(
    SourceSpan Span, TypeSyntax Type, string? Binding, SourceSpan BindingSpan)
    : PatternSyntax(Span);

/// <summary><c>_</c> -- anything at all, and nothing named.</summary>
public sealed record DiscardPatternSyntax(SourceSpan Span) : PatternSyntax(Span);

/// <summary><c>1 or 2</c>, <c>&gt; 0 and &lt; 10</c>.</summary>
public sealed record BinaryPatternSyntax(
    SourceSpan Span, PatternSyntax Left, bool IsOr, PatternSyntax Right) : PatternSyntax(Span);

/// <summary><c>not null</c>, <c>not 0</c>.</summary>
public sealed record NotPatternSyntax(SourceSpan Span, PatternSyntax Operand)
    : PatternSyntax(Span);

/// <summary>
/// One arm of a <c>switch</c> expression: <c>pattern =&gt; value</c>, with an
/// optional <c>when</c> between them.
/// </summary>
public sealed record SwitchArmSyntax(
    SourceSpan Span,
    PatternSyntax Pattern,
    ExpressionSyntax? Guard,
    ExpressionSyntax Value) : SyntaxNode(Span);

/// <summary>
/// <c>value switch { pattern =&gt; result, ... }</c>.
///
/// The expression form of the statement, and the one that has to be exhaustive:
/// a statement that matches nothing falls past itself, and an expression that
/// matched nothing would have no value to be.
/// </summary>
public sealed record SwitchExpressionSyntax(
    SourceSpan Span,
    ExpressionSyntax Value,
    IReadOnlyList<SwitchArmSyntax> Arms) : ExpressionSyntax(Span);

/// <summary>
/// <c>switch (value) { case 1: ... break; default: ... break; }</c>.
///
/// Sections do not fall through: each one has to end by leaving, as in C#. The
/// gain is that the reader never has to check whether a missing <c>break</c>
/// was deliberate.
/// </summary>
public sealed record SwitchSyntax(
    SourceSpan Span,
    ExpressionSyntax Value,
    IReadOnlyList<SwitchSectionSyntax> Sections) : StatementSyntax(Span);

public sealed record ReturnSyntax(SourceSpan Span, ExpressionSyntax? Value) : StatementSyntax(Span);

public sealed record BreakSyntax(SourceSpan Span) : StatementSyntax(Span);

public sealed record ContinueSyntax(SourceSpan Span) : StatementSyntax(Span);

/// <summary>
/// <c>name:</c> -- somewhere a <c>goto</c> can name.
///
/// A label is a statement rather than a modifier on one, so that a label at the
/// very end of a block has nothing it must be attached to.
/// </summary>
public sealed record LabelSyntax(SourceSpan Span, string Name) : StatementSyntax(Span);

/// <summary><c>goto name;</c></summary>
public sealed record GotoSyntax(SourceSpan Span, string Label, SourceSpan LabelSpan)
    : StatementSyntax(Span);

/// <summary>
/// <c>checked { ... }</c> and <c>unchecked { ... }</c>: whether the integer
/// arithmetic written inside is asked to notice that it overflowed.
/// </summary>
public sealed record CheckedBlockSyntax(
    SourceSpan Span, BlockSyntax Body, bool IsChecked) : StatementSyntax(Span);

/// <summary>Which way an <c>asm</c> operand's value travels.</summary>
public enum AsmDirection
{
    /// <summary>Into the register before the block runs.</summary>
    In,

    /// <summary>Out of the register after the block has run.</summary>
    Out,

    /// <summary>Both: the place is read into the register and written back from it.</summary>
    InOut,
}

/// <summary>
/// <c>in rcx = count</c>, <c>out rax = low</c> or <c>inout rdx = total</c>:
/// one register and the value or place it is paired with. The register is a
/// name here and nothing more, because which names are registers depends on
/// the target and the target is the binder's to know.
/// </summary>
public sealed record AsmOperandSyntax(
    SourceSpan Span,
    AsmDirection Direction,
    string Register,
    SourceSpan RegisterSpan,
    ExpressionSyntax Value) : SyntaxNode(Span);

/// <summary>
/// <c>asm (operands) { text }</c> — instructions for the target's assembler,
/// written inside a function.
///
/// <see cref="Text"/> is what was between the braces, untouched; the lexer
/// captured it as one token, since assembly is not Stainless and cutting it
/// into Stainless tokens would lose it. <see cref="TextSpan"/> covers the
/// braces as well, which is what lets a complaint from the assembler be put
/// back on the line it was about.
/// </summary>
public sealed record AsmSyntax(
    SourceSpan Span,
    IReadOnlyList<AsmOperandSyntax> Operands,
    string Text,
    SourceSpan TextSpan) : StatementSyntax(Span);

// ---------------------------------------------------------------- expressions

public abstract record ExpressionSyntax(SourceSpan Span) : SyntaxNode(Span);

/// <summary>
/// A literal, and the text it was written as.
///
/// <c>Text</c> is there for the one thing the value cannot say: an integer's
/// <c>u</c> and <c>l</c> suffixes decide its type and are not part of its
/// magnitude, so <c>20u</c> and <c>20</c> arrive here with the same
/// <c>Value</c> and must not arrive with the same type. It is empty for a
/// literal the parser invented rather than read.
/// </summary>
public sealed record LiteralSyntax(SourceSpan Span, TokenKind Kind, object? Value,
                                   string Text = "")
    : ExpressionSyntax(Span);

/// <summary>
/// <c>$"a {b} c"</c>, as alternating literal text and expressions.
///
/// A part with a null <c>Value</c> is literal text; one with a null
/// <c>Literal</c> is a hole. The two alternate but not strictly -- adjacent
/// holes have no text between them, and a string may start or end with either.
/// </summary>
public sealed record InterpolatedStringSyntax(
    SourceSpan Span, IReadOnlyList<InterpolatedPartSyntax> Parts) : ExpressionSyntax(Span);

public sealed record InterpolatedPartSyntax(string? Literal, ExpressionSyntax? Value);

public sealed record NameSyntax(SourceSpan Span, QualifiedName Name) : ExpressionSyntax(Span);

/// <summary>
/// <c>(a, b)</c> — several values written as one.
///
/// One element is not a tuple but a parenthesised expression, which is why the
/// parser only builds this where it found a comma.
/// </summary>
public sealed record TupleSyntax(
    SourceSpan Span, IReadOnlyList<ExpressionSyntax> Elements) : ExpressionSyntax(Span);

/// <summary>
/// <c>try e</c>: the value if it succeeded, and otherwise a return from the
/// enclosing function carrying the failure on.
/// </summary>
public sealed record TrySyntax(SourceSpan Span, ExpressionSyntax Operand)
    : ExpressionSyntax(Span);

/// <summary>
/// <c>spawn f(x)</c> in expression position. It is only ever a statement —
/// <c>spawn f(x);</c> or <c>result = spawn f(x);</c> — and the parser folds
/// those two shapes into a <see cref="SpawnSyntax"/>. This node exists so that
/// a <c>spawn</c> written anywhere else parses and is then reported against,
/// rather than failing as a syntax error some distance from the word.
/// </summary>
public sealed record SpawnExpressionSyntax(SourceSpan Span, ExpressionSyntax Operand)
    : ExpressionSyntax(Span);

public sealed record ThisSyntax(SourceSpan Span) : ExpressionSyntax(Span);

public sealed record UnarySyntax(SourceSpan Span, TokenKind Operator, ExpressionSyntax Operand)
    : ExpressionSyntax(Span);

/// <summary>
/// <c>++x</c>, <c>x++</c>, <c>--x</c> and <c>x--</c>.
///
/// It is not an <see cref="AssignmentSyntax"/> to <c>x + 1</c>, because the
/// target has to be evaluated exactly once -- <c>a[Next()]++</c> calls
/// <c>Next</c> one time, not two -- and because the postfix form yields the
/// value from before the write.
/// </summary>
public sealed record IncrementSyntax(
    SourceSpan Span,
    ExpressionSyntax Operand,
    bool IsPrefix,
    bool IsIncrement) : ExpressionSyntax(Span);

/// <summary>
/// <c>nameof(x)</c> -- the last identifier in what was written, as a
/// <c>String</c>, checked to be something that exists.
/// </summary>
public sealed record NameofSyntax(SourceSpan Span, ExpressionSyntax Operand)
    : ExpressionSyntax(Span);

/// <summary>
/// <c>default(T)</c> — the zeroed value of a type.
///
/// It exists for generic code, which cannot write a literal for a type it does
/// not know. Everything it produces was already reachable: a fresh array is
/// zeroed, so <c>new T[1][0]</c> was the spelling before this, and the library
/// kept exactly such an array around to blank a vacated slot with.
/// </summary>
public sealed record DefaultSyntax(SourceSpan Span, TypeSyntax Type) : ExpressionSyntax(Span);

/// <summary><c>checked(e)</c> and <c>unchecked(e)</c>.</summary>
public sealed record CheckedSyntax(
    SourceSpan Span, ExpressionSyntax Operand, bool IsChecked) : ExpressionSyntax(Span);

public sealed record BinarySyntax(
    SourceSpan Span,
    ExpressionSyntax Left,
    TokenKind Operator,
    ExpressionSyntax Right) : ExpressionSyntax(Span);

/// <summary>
/// Assignment. <paramref name="Operator"/> is <see cref="TokenKind.Equals"/> for a
/// plain assignment, or the compound form such as <see cref="TokenKind.PlusEquals"/>.
/// </summary>
public sealed record AssignmentSyntax(
    SourceSpan Span,
    ExpressionSyntax Target,
    TokenKind Operator,
    ExpressionSyntax Value) : ExpressionSyntax(Span);

public sealed record CallSyntax(
    SourceSpan Span,
    ExpressionSyntax Callee,
    IReadOnlyList<ExpressionSyntax> Arguments) : ExpressionSyntax(Span);

/// <summary>
/// <c>base</c>: this object, seen as the class it derives from.
///
/// It is never a value on its own. As the target of a call it names the base
/// implementation and takes the call off the vtable, which is the only way an
/// override can reach the method it replaced; as the callee of a call it is the
/// base constructor.
/// </summary>
public sealed record BaseSyntax(SourceSpan Span) : ExpressionSyntax(Span);

/// <summary>
/// <c>value is Type</c>: whether the object really is one of those.
///
/// The right side is a type rather than an expression, which is why this is not
/// a <see cref="BinarySyntax"/>. It answers for a class by walking the object's
/// base chain and for an interface by looking in its dispatch table, and it is
/// how a downcast is made safe -- there being no exception for one to throw.
/// </summary>
/// <param name="Binding">
/// The name in <c>value is Circle c</c>, or null when the test only asks. It is
/// in scope where the test succeeded and nowhere else, which is why it is
/// carried here rather than being a declaration of its own: the statement that
/// declares it is built by whatever the condition belongs to.
/// </param>
public sealed record TypeTestSyntax(
    SourceSpan Span,
    ExpressionSyntax Value,
    TypeSyntax Tested,
    string? Binding,
    SourceSpan BindingSpan) : ExpressionSyntax(Span)
{
    public TypeTestSyntax(SourceSpan span, ExpressionSyntax value, TypeSyntax tested)
        : this(span, value, tested, null, span) { }
}

public sealed record MemberAccessSyntax(
    SourceSpan Span,
    ExpressionSyntax Target,
    string Member) : ExpressionSyntax(Span)
{
    /// <summary>
    /// True when this was written <c>p->m</c> rather than <c>p.m</c>.
    ///
    /// Both reach through a pointer, and have since before the arrow existed;
    /// the difference is what they refuse. A <c>-&gt;</c> insists there was a
    /// pointer to follow, so writing one over a value is caught rather than
    /// quietly meaning the same thing.
    /// </summary>
    public bool ThroughPointer { get; init; }

    /// <summary>
    /// True when this was written <c>a?.m</c>: the member is reached only if
    /// the receiver is there, and the whole thing is nothing if it is not.
    /// </summary>
    public bool Conditional { get; init; }
}

/// <summary>
/// <c>a[from:to]</c>, and the three shorter forms it has. Either end may be
/// left out, and means the beginning or the end of what is being sliced.
/// </summary>
public sealed record SliceSyntax(
    SourceSpan Span,
    ExpressionSyntax Target,
    ExpressionSyntax? Start,
    ExpressionSyntax? End) : ExpressionSyntax(Span);

public sealed record IndexSyntax(SourceSpan Span, ExpressionSyntax Target, ExpressionSyntax Index)
    : ExpressionSyntax(Span);

public sealed record NewSyntax(
    SourceSpan Span,
    TypeSyntax Type,
    IReadOnlyList<ExpressionSyntax> Arguments) : ExpressionSyntax(Span)
{
    /// <summary>
    /// The <c>{ ... }</c> after the arguments, or null. It is either a list of
    /// <c>Name = value</c> members or a list of elements to add, and which one
    /// is decided by what is in it.
    /// </summary>
    public ObjectInitializerSyntax? Initializer { get; init; }
}

/// <summary>
/// <c>new Panel { Width = 3 }</c> or <c>new List&lt;int&gt; { 1, 2 }</c>.
///
/// Both are the same shape -- a braced list after a construction -- and what
/// separates them is whether the entries are named. Mixing the two is refused
/// rather than guessed at.
/// </summary>
public sealed record ObjectInitializerSyntax(
    SourceSpan Span, IReadOnlyList<InitializerEntrySyntax> Entries) : SyntaxNode(Span);

/// <summary>One entry: <c>Name = value</c>, or a value on its own.</summary>
public sealed record InitializerEntrySyntax(
    SourceSpan Span, string? Name, SourceSpan NameSpan, ExpressionSyntax Value) : SyntaxNode(Span);

/// <summary>
/// <c>[a, b, c]</c> — an array written out.
///
/// It has no type of its own. What it becomes is decided by where it is going,
/// the way a lambda and a variant case name are (§2.14, §2.6): a <c>T[]</c>, a
/// <c>T[N]</c> of matching length, or a <c>T[:]</c>. With nothing to go on, the
/// elements decide, so <c>var xs = [1, 2, 3];</c> is an <c>int[]</c>.
/// </summary>
public sealed record ArrayLiteralSyntax(
    SourceSpan Span,
    IReadOnlyList<ExpressionSyntax> Elements) : ExpressionSyntax(Span);

/// <summary><c>new T[n]</c> — allocates a zeroed array of n elements.</summary>
public sealed record NewArraySyntax(
    SourceSpan Span,
    TypeSyntax ElementType,
    ExpressionSyntax Length) : ExpressionSyntax(Span);

/// <summary>
/// <c>condition ? whenTrue : whenFalse</c>. Both arms must reach a common type,
/// and only the chosen one is evaluated.
/// </summary>
public sealed record ConditionalSyntax(
    SourceSpan Span,
    ExpressionSyntax Condition,
    ExpressionSyntax WhenTrue,
    ExpressionSyntax WhenFalse) : ExpressionSyntax(Span);

/// <summary>
/// One lambda parameter. A null <see cref="Type"/> means it is taken from the
/// interface or delegate the lambda is being converted to.
/// </summary>
public sealed record LambdaParameterSyntax(SourceSpan Span, TypeSyntax? Type, string Name)
    : SyntaxNode(Span);

/// <summary>
/// <c>(int a, int b) => a + b</c> — a lambda.
///
/// It has no type of its own: what it becomes is decided by what it is assigned
/// to, which is also where its parameter types come from when they are omitted.
/// </summary>
public sealed record LambdaSyntax(
    SourceSpan Span,
    IReadOnlyList<LambdaParameterSyntax> Parameters,
    ExpressionSyntax? Expression,
    BlockSyntax? Block) : ExpressionSyntax(Span);

public sealed record CastSyntax(SourceSpan Span, TypeSyntax Type, ExpressionSyntax Operand)
    : ExpressionSyntax(Span);

/// <summary>
/// <c>value as Type</c>: the value as one of those, or null.
///
/// The same question <see cref="TypeTestSyntax"/> asks, wanting the answer as a
/// value rather than as a branch. A cast ends the program when it was wrong and
/// <c>is</c> only says yes or no, so this is what a chain of maybes is written
/// with: <c>Parent() as Frame</c> passed straight on, or stored.
///
/// The type written is the one the object would be, and the result is that type
/// optional -- <c>x as Frame</c> is a <c>Frame?</c>, because "or null" is the
/// whole of what this adds.
/// </summary>
public sealed record AsCastSyntax(SourceSpan Span, ExpressionSyntax Value, TypeSyntax Tested)
    : ExpressionSyntax(Span);

public sealed record SizeofSyntax(SourceSpan Span, TypeSyntax Type) : ExpressionSyntax(Span);

/// <summary><c>alignof(T)</c>: the alignment C would compute for T.</summary>
public sealed record AlignofSyntax(SourceSpan Span, TypeSyntax Type) : ExpressionSyntax(Span);

/// <summary><c>offsetof(T, Field)</c>: where a field sits inside its type.</summary>
public sealed record OffsetofSyntax(
    SourceSpan Span, TypeSyntax Type, string Field, SourceSpan FieldSpan)
    : ExpressionSyntax(Span);

/// <summary><c>typeof(T)</c> — the reflection handle for a type, resolved at compile time.</summary>
public sealed record TypeofSyntax(SourceSpan Span, TypeSyntax Type) : ExpressionSyntax(Span);

/// <summary><c>iidof(IFoo)</c>: a com interface's IID, as a <c>Guid*</c>.</summary>
public sealed record IidofSyntax(SourceSpan Span, TypeSyntax Type) : ExpressionSyntax(Span);
