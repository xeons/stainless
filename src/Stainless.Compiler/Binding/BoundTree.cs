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

namespace Stainless.Binding;

public enum BoundBinaryOp
{
    Add, Subtract, Multiply, Divide, Remainder,
    BitAnd, BitOr, BitXor, ShiftLeft, ShiftRight,
    Equal, NotEqual, Less, LessEqual, Greater, GreaterEqual,
    LogicalAnd, LogicalOr,
}

public enum BoundUnaryOp { Negate, LogicalNot, BitwiseNot }

/// <summary>
/// How a value changes representation. Resolved during binding so the emitter
/// never has to reason about types, only about instructions.
/// </summary>
public enum ConversionKind
{
    Identity,
    IntegerWiden,       // sext or zext, chosen by the source's signedness
    IntegerNarrow,      // trunc
    IntToFloat,
    FloatToInt,
    FloatResize,        // fpext or fptrunc
    PointerCast,        // bitcast between pointer types (a no-op with opaque pointers)
    PointerToInteger,
    IntegerToPointer,
    BoolToInteger,
    NullToReference,    // null literal adopting an optional/pointer type
    ReferenceToOptional, // C -> C?
    ClassToInterface,   // C -> I; the same pointer, since dispatch goes via TypeInfo

    /// <summary>
    /// A string literal used where a <c>byte*</c> is expected. Safe only for a
    /// literal, whose bytes are static and NUL-terminated; a String held in a
    /// variable must go through ToPointer(), where the lifetime is visible.
    /// </summary>
    StringLiteralToPointer,
}

// ---------------------------------------------------------------- expressions

public abstract class BoundExpression(SourceSpan span, TypeSymbol type)
{
    public SourceSpan Span { get; } = span;
    public TypeSymbol Type { get; } = type;

    /// <summary>True when this expression designates storage that can be assigned to.</summary>
    public virtual bool IsLValue => false;
}

public sealed class BoundErrorExpression(SourceSpan span)
    : BoundExpression(span, ErrorTypeSymbol.Instance);

/// <summary>An integer, float, bool or char constant. <c>Value</c> is ulong/double/bool/char.</summary>
public sealed class BoundLiteral(SourceSpan span, TypeSymbol type, object? value)
    : BoundExpression(span, type)
{
    public object? Value { get; } = value;
}

/// <summary>A NUL-terminated UTF-8 string constant with static lifetime; type is <c>byte*</c>.</summary>
public sealed class BoundStringLiteral(SourceSpan span, TypeSymbol type, string value)
    : BoundExpression(span, type)
{
    public string Value { get; } = value;
}

public sealed class BoundNullLiteral(SourceSpan span, TypeSymbol type)
    : BoundExpression(span, type);

public sealed class BoundLocalAccess(SourceSpan span, LocalSymbol local)
    : BoundExpression(span, local.Type)
{
    public LocalSymbol Local { get; } = local;
    public override bool IsLValue => !Local.IsConst;
}

public sealed class BoundParameterAccess(SourceSpan span, ParameterSymbol parameter)
    : BoundExpression(span, parameter.Type)
{
    public ParameterSymbol Parameter { get; } = parameter;
    public override bool IsLValue => true;
}

/// <summary>Reads module-level storage. Never an lvalue: a static is readonly.</summary>
public sealed class BoundStaticAccess(SourceSpan span, StaticSymbol symbol)
    : BoundExpression(span, symbol.Type)
{
    public StaticSymbol Static { get; } = symbol;
}

public sealed class BoundConstantAccess(SourceSpan span, ConstantSymbol constant)
    : BoundExpression(span, constant.Type)
{
    public ConstantSymbol Constant { get; } = constant;
}

/// <summary>
/// Field access. For a class receiver the field lives past the object header;
/// for a struct receiver it is an offset into the value itself.
/// </summary>
public sealed class BoundFieldAccess(SourceSpan span, BoundExpression? receiver, FieldSymbol field)
    : BoundExpression(span, field.Type)
{
    public BoundExpression? Receiver { get; } = receiver;
    public FieldSymbol Field { get; } = field;
    public override bool IsLValue => true;
}

public sealed class BoundCall(
    SourceSpan span,
    FunctionSymbol function,
    BoundExpression? receiver,
    IReadOnlyList<BoundExpression> arguments)
    : BoundExpression(span, function.ReturnType)
{
    public FunctionSymbol Function { get; } = function;
    public BoundExpression? Receiver { get; } = receiver;
    public IReadOnlyList<BoundExpression> Arguments { get; } = arguments;
}

public sealed class BoundUnary(
    SourceSpan span, TypeSymbol type, BoundUnaryOp op, BoundExpression operand)
    : BoundExpression(span, type)
{
    public BoundUnaryOp Operator { get; } = op;
    public BoundExpression Operand { get; } = operand;
}

public sealed class BoundBinary(
    SourceSpan span, TypeSymbol type,
    BoundExpression left, BoundBinaryOp op, BoundExpression right)
    : BoundExpression(span, type)
{
    public BoundExpression Left { get; } = left;
    public BoundBinaryOp Operator { get; } = op;
    public BoundExpression Right { get; } = right;
}

public sealed class BoundAssignment(SourceSpan span, BoundExpression target, BoundExpression value)
    : BoundExpression(span, target.Type)
{
    public BoundExpression Target { get; } = target;
    public BoundExpression Value { get; } = value;
}

/// <summary>
/// Writes a property.
///
/// A property read is simply a <see cref="BoundCall"/> to the getter, so it
/// needs no node of its own. A write needs one only because an assignment
/// yields the value it stored and a setter returns nothing: the emitter has to
/// hold on to the value it just passed.
/// </summary>
public sealed class BoundPropertyAssignment(
    SourceSpan span, BoundExpression receiver, PropertySymbol property, BoundExpression value)
    : BoundExpression(span, property.Type)
{
    public BoundExpression Receiver { get; } = receiver;
    public PropertySymbol Property { get; } = property;
    public BoundExpression Value { get; } = value;
}

/// <summary>
/// <c>condition ? whenTrue : whenFalse</c>. Kept as a node rather than lowered
/// to an <c>if</c>, because only the chosen arm may be evaluated and the result
/// is a value, not a statement.
/// </summary>
public sealed class BoundConditional(
    SourceSpan span, TypeSymbol type,
    BoundExpression condition, BoundExpression whenTrue, BoundExpression whenFalse)
    : BoundExpression(span, type)
{
    public BoundExpression Condition { get; } = condition;
    public BoundExpression WhenTrue { get; } = whenTrue;
    public BoundExpression WhenFalse { get; } = whenFalse;
}

/// <summary>
/// A bare function name before it is known which delegate it is becoming. It is
/// never emitted: binding either converts it to a delegate or reports that it
/// could not.
/// </summary>
public sealed class BoundFunctionGroup(
    SourceSpan span, TypeSymbol type, string name, IReadOnlyList<FunctionSymbol> candidates)
    : BoundExpression(span, type)
{
    public string Name { get; } = name;
    public IReadOnlyList<FunctionSymbol> Candidates { get; } = candidates;
}

/// <summary>
/// A lambda before it is known what it becomes. Like a function name it has no
/// type of its own, and binding either converts it or reports that it could not.
/// </summary>
public sealed class BoundLambda(SourceSpan span, TypeSymbol type, Syntax.LambdaSyntax syntax)
    : BoundExpression(span, type)
{
    public Syntax.LambdaSyntax Syntax { get; } = syntax;
}

/// <summary>
/// Creates a closure: an instance of a compiler-generated class that implements
/// the target interface, with one field per captured value.
///
/// Capture is **by value**, taken when the closure is made. A captured
/// reference is retained into the field and released when the closure dies, so
/// a closure may outlive the scope that built it without any lifetime question
/// arising.
/// </summary>
public sealed class BoundClosure(
    SourceSpan span,
    TypeSymbol type,
    ClassTypeSymbol closureType,
    IReadOnlyList<(FieldSymbol Field, BoundExpression Value)> captures)
    : BoundExpression(span, type)
{
    public ClassTypeSymbol ClosureType { get; } = closureType;
    public IReadOnlyList<(FieldSymbol Field, BoundExpression Value)> Captures { get; } = captures;
}

/// <summary>A function's address, typed as a delegate.</summary>
public sealed class BoundFunctionReference(
    SourceSpan span, TypeSymbol type, FunctionSymbol function)
    : BoundExpression(span, type)
{
    public FunctionSymbol Function { get; } = function;
}

/// <summary>A call through a delegate rather than to a known symbol.</summary>
public sealed class BoundIndirectCall(
    SourceSpan span,
    DelegateTypeSymbol delegateType,
    BoundExpression target,
    IReadOnlyList<BoundExpression> arguments)
    : BoundExpression(span, delegateType.ReturnType)
{
    public DelegateTypeSymbol DelegateType { get; } = delegateType;
    public BoundExpression Target { get; } = target;
    public IReadOnlyList<BoundExpression> Arguments { get; } = arguments;
}

public sealed class BoundConversion(
    SourceSpan span, TypeSymbol type, BoundExpression operand, ConversionKind kind)
    : BoundExpression(span, type)
{
    public BoundExpression Operand { get; } = operand;
    public ConversionKind Kind { get; } = kind;
}

/// <summary>Allocates, zeroes and constructs a class instance; yields a +1 reference.</summary>
public sealed class BoundNew(
    SourceSpan span,
    ClassTypeSymbol classType,
    FunctionSymbol? constructor,
    IReadOnlyList<BoundExpression> arguments)
    : BoundExpression(span, classType)
{
    public ClassTypeSymbol ClassType { get; } = classType;
    public FunctionSymbol? Constructor { get; } = constructor;
    public IReadOnlyList<BoundExpression> Arguments { get; } = arguments;
}

/// <summary><c>*p</c></summary>
public sealed class BoundDereference(SourceSpan span, TypeSymbol type, BoundExpression operand)
    : BoundExpression(span, type)
{
    public BoundExpression Operand { get; } = operand;
    public override bool IsLValue => true;
}

/// <summary><c>&amp;x</c></summary>
public sealed class BoundAddressOf(SourceSpan span, TypeSymbol type, BoundExpression operand)
    : BoundExpression(span, type)
{
    public BoundExpression Operand { get; } = operand;
}

/// <summary>Allocates a zeroed array of <paramref name="Length"/> elements; yields +1.</summary>
public sealed class BoundNewArray(SourceSpan span, ArrayTypeSymbol type, BoundExpression length)
    : BoundExpression(span, type)
{
    public ArrayTypeSymbol ArrayType { get; } = type;
    public BoundExpression Length { get; } = length;
}

/// <summary><c>array.Length</c>, read straight out of the object header.</summary>
public sealed class BoundArrayLength(SourceSpan span, TypeSymbol type, BoundExpression array)
    : BoundExpression(span, type)
{
    public BoundExpression Array { get; } = array;
}

/// <summary><c>p[i]</c>, which is pointer arithmetic exactly as in C.</summary>
public sealed class BoundIndex(
    SourceSpan span, TypeSymbol type, BoundExpression target, BoundExpression index)
    : BoundExpression(span, type)
{
    public BoundExpression Target { get; } = target;
    public BoundExpression Index { get; } = index;
    public override bool IsLValue => true;
}

public sealed class BoundSizeof(SourceSpan span, TypeSymbol type, TypeSymbol measuredType)
    : BoundExpression(span, type)
{
    public TypeSymbol MeasuredType { get; } = measuredType;
}

/// <summary>
/// <c>typeof(T)</c>: a handle to T's static metadata. It is a constant, so this
/// costs one pointer and no work at run time.
/// </summary>
public sealed class BoundTypeof(SourceSpan span, TypeSymbol type, NamedTypeSymbol measuredType)
    : BoundExpression(span, type)
{
    public NamedTypeSymbol MeasuredType { get; } = measuredType;
}

public sealed class BoundThis(SourceSpan span, TypeSymbol type, ParameterSymbol parameter)
    : BoundExpression(span, type)
{
    public ParameterSymbol Parameter { get; } = parameter;
}

// ---------------------------------------------------------------- statements

public abstract class BoundStatement(SourceSpan span)
{
    public SourceSpan Span { get; } = span;
}

public sealed class BoundBlock(SourceSpan span, IReadOnlyList<BoundStatement> statements)
    : BoundStatement(span)
{
    public IReadOnlyList<BoundStatement> Statements { get; } = statements;

    /// <summary>Locals declared directly in this block, in declaration order.</summary>
    public List<LocalSymbol> Locals { get; } = [];
}

public sealed class BoundLocalDeclaration(
    SourceSpan span, LocalSymbol local, BoundExpression? initializer)
    : BoundStatement(span)
{
    public LocalSymbol Local { get; } = local;
    public BoundExpression? Initializer { get; } = initializer;
}

public sealed class BoundExpressionStatement(SourceSpan span, BoundExpression expression)
    : BoundStatement(span)
{
    public BoundExpression Expression { get; } = expression;
}

public sealed class BoundIf(
    SourceSpan span, BoundExpression condition, BoundStatement then, BoundStatement? otherwise)
    : BoundStatement(span)
{
    public BoundExpression Condition { get; } = condition;
    public BoundStatement Then { get; } = then;
    public BoundStatement? Else { get; } = otherwise;
}

public sealed class BoundWhile(SourceSpan span, BoundExpression condition, BoundStatement body)
    : BoundStatement(span)
{
    public BoundExpression Condition { get; } = condition;
    public BoundStatement Body { get; } = body;
}

/// <summary>
/// Kept in the bound tree rather than lowered to a while loop, so that
/// <c>continue</c> still runs the step expression.
/// </summary>
public sealed class BoundFor(
    SourceSpan span,
    BoundStatement? initializer,
    BoundExpression? condition,
    BoundExpression? step,
    BoundStatement body) : BoundStatement(span)
{
    public BoundStatement? Initializer { get; } = initializer;
    public BoundExpression? Condition { get; } = condition;
    public BoundExpression? Step { get; } = step;
    public BoundStatement Body { get; } = body;

    /// <summary>A local declared by the initializer, scoped to the loop.</summary>
    public List<LocalSymbol> Locals { get; } = [];
}

/// <summary>
/// A fork-join scope. The emitter opens a runtime scope before the body and
/// joins it after, so nothing spawned inside can outlive the block.
/// </summary>
public sealed class BoundParallel(SourceSpan span, BoundStatement body) : BoundStatement(span)
{
    public BoundStatement Body { get; } = body;
}

/// <summary>
/// One queued call. The arguments are evaluated by the parent at the point the
/// <c>spawn</c> is written, then copied into a block the worker unpacks, so a
/// spawn in a loop sees that iteration's values rather than the last.
/// </summary>
public sealed class BoundSpawn(
    SourceSpan span,
    BoundExpression? target,
    BoundCall call) : BoundStatement(span)
{
    /// <summary>Where the result is stored, or null when it is discarded.</summary>
    public BoundExpression? Target { get; } = target;

    public BoundCall Call { get; } = call;
}

/// <summary>
/// A counted loop whose iterations are split across the pool.
///
/// The trip count is computed once, up front, from the recognised
/// <c>start</c>/<c>limit</c>/<c>stride</c> form: a general C-style <c>for</c>
/// cannot be chunked, because there is no way to know how many times it runs.
/// </summary>
public sealed class BoundParallelFor(
    SourceSpan span,
    LocalSymbol variable,
    BoundExpression start,
    BoundExpression limit,
    BoundExpression stride,
    bool inclusive,
    BoundStatement body,
    IReadOnlyList<object> captures) : BoundStatement(span)
{
    /// <summary>The loop variable, private to each chunk.</summary>
    public LocalSymbol Variable { get; } = variable;

    public BoundExpression Start { get; } = start;
    public BoundExpression Limit { get; } = limit;
    public BoundExpression Stride { get; } = stride;

    /// <summary>True when the condition was <c>&lt;=</c> rather than <c>&lt;</c>.</summary>
    public bool Inclusive { get; } = inclusive;

    public BoundStatement Body { get; } = body;

    /// <summary>
    /// The enclosing locals and parameters the body reads, captured by address.
    /// Each is a <see cref="LocalSymbol"/> or a <see cref="ParameterSymbol"/>.
    /// </summary>
    public IReadOnlyList<object> Captures { get; } = captures;
}

public sealed class BoundReturn(SourceSpan span, BoundExpression? value) : BoundStatement(span)
{
    public BoundExpression? Value { get; } = value;
}

public sealed class BoundBreak(SourceSpan span) : BoundStatement(span);

public sealed class BoundContinue(SourceSpan span) : BoundStatement(span);

/// <summary>A fully bound function ready for emission.</summary>
public sealed class BoundFunction(FunctionSymbol symbol, BoundBlock body)
{
    public FunctionSymbol Symbol { get; } = symbol;
    public BoundBlock Body { get; } = body;
}
