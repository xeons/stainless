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
    ExpressionSyntax? Initializer) : Declaration(Span, Modifiers);

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

public enum TypeDeclKind { Struct, Class, Interface }

public sealed record TypeDeclSyntax(
    SourceSpan Span,
    Modifiers Modifiers,
    TypeDeclKind Kind,
    string Name,
    IReadOnlyList<string> TypeParameters,
    IReadOnlyList<WhereClauseSyntax> Constraints,
    IReadOnlyList<TypeSyntax> Implements,
    IReadOnlyList<Declaration> Members) : Declaration(Span, Modifiers);

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

public sealed record CastSyntax(SourceSpan Span, TypeSyntax Type, ExpressionSyntax Operand)
    : ExpressionSyntax(Span);

public sealed record SizeofSyntax(SourceSpan Span, TypeSyntax Type) : ExpressionSyntax(Span);
