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
}

/// <summary>How a declaration crosses the language boundary.</summary>
public enum LinkageKind
{
    /// <summary>Ordinary Stainless linkage: the symbol name is mangled.</summary>
    Stainless,
    /// <summary>Declared elsewhere in C; imported by its unmangled name.</summary>
    ExternC,
    /// <summary>Defined here but emitted unmangled so C can call it.</summary>
    ExportC,
}

public abstract record Declaration(SourceSpan Span, Modifiers Modifiers) : SyntaxNode(Span);

public sealed record ParameterSyntax(SourceSpan Span, TypeSyntax Type, string Name) : SyntaxNode(Span);

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
    BlockSyntax? Body) : Declaration(Span, Modifiers);

public sealed record FieldDeclSyntax(
    SourceSpan Span,
    Modifiers Modifiers,
    TypeSyntax Type,
    string Name,
    ExpressionSyntax? Initializer,
    IReadOnlyList<AttributeSyntax> Attributes) : Declaration(Span, Modifiers)
{
    public FieldDeclSyntax(
        SourceSpan span, Modifiers modifiers, TypeSyntax type, string name,
        ExpressionSyntax? initializer)
        : this(span, modifiers, type, name, initializer, []) { }
}

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

public enum TypeDeclKind { Struct, Class, Interface, Attribute }

public sealed record TypeDeclSyntax(
    SourceSpan Span,
    Modifiers Modifiers,
    TypeDeclKind Kind,
    string Name,
    IReadOnlyList<string> TypeParameters,
    IReadOnlyList<WhereClauseSyntax> Constraints,
    IReadOnlyList<TypeSyntax> Implements,
    IReadOnlyList<Declaration> Members,
    IReadOnlyList<AttributeSyntax> Attributes) : Declaration(Span, Modifiers);

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
    IReadOnlyList<Declaration> Declarations) : SyntaxNode(Span);

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

public sealed record MemberAccessSyntax(
    SourceSpan Span,
    ExpressionSyntax Target,
    string Member) : ExpressionSyntax(Span);

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

/// <summary><c>typeof(T)</c> — the reflection handle for a type, resolved at compile time.</summary>
public sealed record TypeofSyntax(SourceSpan Span, TypeSyntax Type) : ExpressionSyntax(Span);
