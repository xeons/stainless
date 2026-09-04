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

public abstract record Declaration(SourceSpan Span, Modifiers Modifiers) : SyntaxNode(Span);

/// <summary>
/// How a parameter is passed.
///
/// <c>Value</c> is a copy, and is everything the language had. <c>Ref</c> and
/// <c>In</c> both pass the caller's storage rather than a copy of it; the
/// difference is that the callee may write through a <c>ref</c> and may not
/// write through an <c>in</c>. Both are exactly a <c>T*</c> at the ABI, which
/// is why they cross <c>extern "C"</c> with nothing in between.
/// </summary>
public enum ParameterMode { Value, Ref, In }

public sealed record ParameterSyntax(
    SourceSpan Span,
    TypeSyntax Type,
    string Name,
    ParameterMode Mode = ParameterMode.Value) : SyntaxNode(Span);

/// <summary>
/// <c>ref x</c> at a call. Written at the call as well as the declaration,
/// because a caller reading the line should be able to see that the value may
/// come back changed.
/// </summary>
public sealed record RefArgumentSyntax(SourceSpan Span, ExpressionSyntax Value)
    : ExpressionSyntax(Span);

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
    IReadOnlyList<TypeSyntax> Constraints) : SyntaxNode(Span);

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
public sealed record DelegateDeclSyntax(
    SourceSpan Span,
    Modifiers Modifiers,
    string Name,
    TypeSyntax ReturnType,
    IReadOnlyList<ParameterSyntax> Parameters) : Declaration(Span, Modifiers);

/// <summary>One <c>enum</c> member, with the constant it was given if any.</summary>
public sealed record EnumMemberSyntax(SourceSpan Span, string Name, ExpressionSyntax? Value)
    : SyntaxNode(Span);

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
    IReadOnlyList<ParameterSyntax> Parameters) : SyntaxNode(Span);

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
/// storage, initialized once before <c>Main</c>.
///
/// There is no <c>static</c> without <c>readonly</c>: a plainly mutable global
/// is shared state that nothing synchronizes, and that is the bug this language
/// would rather not have. Mutation goes through a type that says how it is safe.
/// </summary>
public sealed record StaticDeclSyntax(
    SourceSpan Span,
    Modifiers Modifiers,
    TypeSyntax Type,
    string Name,
    ExpressionSyntax Value) : Declaration(Span, Modifiers);

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
    IReadOnlyList<string> Libraries) : SyntaxNode(Span);

// ---------------------------------------------------------------- statements

public abstract record StatementSyntax(SourceSpan Span) : SyntaxNode(Span);

public sealed record BlockSyntax(SourceSpan Span, IReadOnlyList<StatementSyntax> Statements)
    : StatementSyntax(Span);

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
/// <c>parallel for (int i = 0; i &lt; n; i = i + 1) { ... }</c> — the loop's
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
/// <c>spawn f(x);</c> or <c>spawn result = f(x);</c> — queues a call on the
/// enclosing <c>parallel</c> scope. The assignment happens on the worker, into
/// storage the parent still owns.
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

// ---------------------------------------------------------------- expressions

public abstract record ExpressionSyntax(SourceSpan Span) : SyntaxNode(Span);

public sealed record LiteralSyntax(SourceSpan Span, TokenKind Kind, object? Value)
    : ExpressionSyntax(Span);

public sealed record NameSyntax(SourceSpan Span, QualifiedName Name) : ExpressionSyntax(Span);

public sealed record ThisSyntax(SourceSpan Span) : ExpressionSyntax(Span);

public sealed record UnarySyntax(SourceSpan Span, TokenKind Operator, ExpressionSyntax Operand)
    : ExpressionSyntax(Span);

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
public sealed record TypeTestSyntax(
    SourceSpan Span,
    ExpressionSyntax Value,
    TypeSyntax Tested) : ExpressionSyntax(Span);

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
    IReadOnlyList<ExpressionSyntax> Arguments) : ExpressionSyntax(Span);

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

public sealed record SizeofSyntax(SourceSpan Span, TypeSyntax Type) : ExpressionSyntax(Span);

/// <summary><c>alignof(T)</c>: the alignment C would compute for T.</summary>
public sealed record AlignofSyntax(SourceSpan Span, TypeSyntax Type) : ExpressionSyntax(Span);

/// <summary><c>offsetof(T, Field)</c>: where a field sits inside its type.</summary>
public sealed record OffsetofSyntax(
    SourceSpan Span, TypeSyntax Type, string Field, SourceSpan FieldSpan)
    : ExpressionSyntax(Span);

/// <summary><c>typeof(T)</c> — the reflection handle for a type, resolved at compile time.</summary>
public sealed record TypeofSyntax(SourceSpan Span, TypeSyntax Type) : ExpressionSyntax(Span);
