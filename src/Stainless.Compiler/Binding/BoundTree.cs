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

    /// <summary>
    /// <c>C</c> or <c>C?</c> -> <c>weak C?</c>. The pointer is unchanged; what
    /// differs is the slot it lands in, which counts weakly rather than
    /// strongly. That is the whole of what a weak reference is, and it is why
    /// this conversion emits nothing.
    /// </summary>
    ReferenceToWeak,
    ClassToInterface,   // C -> I; the same pointer, since dispatch goes via TypeInfo

    /// <summary>
    /// <c>Derived</c> -> <c>Base</c>. Emits nothing at all: with single
    /// inheritance the base subobject is a prefix of the derived one, so the two
    /// references are the same address. It is the property that keeps reference
    /// identity equal to pointer identity, and <c>sl_retain</c> taking the
    /// object's own address.
    /// </summary>
    Upcast,

    /// <summary>
    /// <c>Base</c> -> <c>Derived</c>, explicit and checked. The pointer is
    /// unchanged; what it costs is a walk up the object's base chain, and a
    /// program that ends if the object was not one of those. There being no
    /// exceptions, <c>is</c> is how a cast is asked before it is made.
    /// </summary>
    Downcast,

    /// <summary>
    /// <c>T[]</c> -> <c>T[:]</c>: the whole array, as a slice of it. Implicit,
    /// because a slice of everything is what an array already is and asking for
    /// a cast would put punctuation in front of every call that takes one.
    /// </summary>
    ArrayToSlice,

    /// <summary>
    /// A string literal used where a <c>byte*</c> is expected. Safe only for a
    /// literal, whose bytes are static and NUL-terminated; a String held in a
    /// variable must go through ToPointer(), where the lifetime is visible.
    /// </summary>
    StringLiteralToPointer,

    /// <summary>
    /// <c>IDerived</c> -> <c>IBase</c>, between com interfaces. Emits nothing:
    /// a COM vtable begins with its base's slots, so the same pointer already
    /// satisfies the base's contract. It is the same property that makes a
    /// class <see cref="Upcast"/> free, arrived at from the other direction --
    /// there the object is a prefix, here the table is.
    /// </summary>
    ComUpcast,

    /// <summary>
    /// <c>IBase</c> -> <c>IDerived</c>, explicit and checked: a QueryInterface,
    /// and a program that ends if the object does not answer.
    ///
    /// Unlike a class <see cref="Downcast"/> this is not a walk over something
    /// the compiler laid out. The object decides, at run time, in code that may
    /// not be ours -- so a com cast is a call, and its answer is a reference the
    /// caller owns.
    /// </summary>
    ComQuery,

    /// <summary>
    /// <c>C?</c> -> <c>C</c>, where a check has established that it is not
    /// null. Emits nothing: the two are the same pointer, and the whole of the
    /// difference is what the compiler will let you do with it.
    ///
    /// Told apart from <see cref="PointerCast"/>, which is the same move made
    /// by an explicit cast, because this one has to be undone where the value
    /// is written rather than read -- a narrowed <c>x</c> is still a <c>C?</c>
    /// when it is on the left of an assignment.
    /// </summary>
    NarrowOptional,

    /// <summary>
    /// <c>byte*</c> -> a com interface, explicit: adopting a reference that COM
    /// activation wrote through a <c>void**</c>.
    ///
    /// Unchecked, because a raw pointer says nothing about what is behind it,
    /// and the language has no better answer to offer -- this is the boundary
    /// where an object made elsewhere enters ARC's care. The pointer is
    /// unchanged; what the conversion does is start counting it.
    /// </summary>
    ComAdopt,

    /// <summary>
    /// A <c>com class</c> -> one of the com interfaces it presents.
    ///
    /// The one conversion here that is not free. A COM pointer must point at a
    /// vtable pointer, so what the caller gets is the address of the tear-off
    /// inside the object rather than the object itself: one add, at a constant
    /// offset the layout fixed.
    /// </summary>
    ComTearOff,
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

/// <summary>
/// <c>$"a {b} c"</c>, as the String-valued pieces it is made of.
///
/// Every part is already a String by the time it gets here -- the binder put
/// the conversion in -- so the emitter's job is only to put them end to end.
/// It does that in one allocation rather than one per part, which is the
/// difference between this and the chain of <c>+</c> it replaces.
/// </summary>
public sealed class BoundInterpolatedString(
    SourceSpan span, TypeSymbol type, IReadOnlyList<BoundExpression> parts)
    : BoundExpression(span, type)
{
    public IReadOnlyList<BoundExpression> Parts { get; } = parts;
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

    /// <summary>
    /// True when this call names the function rather than asking the object.
    ///
    /// It is what <c>base.M()</c> means, and the only way an override can reach
    /// what it replaced -- through the vtable it would find itself, for ever. A
    /// constructor chain is the same thing: the base's constructor is the one
    /// being run, not whichever the object would dispatch to.
    /// </summary>
    public bool IsNonVirtual { get; init; }
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

    /// <summary>
    /// What went between the brackets, for <c>a[i] = v</c>. Empty for an
    /// ordinary property, which is the only thing separating the two: an
    /// indexer's setter takes its indices before <c>value</c>.
    /// </summary>
    public IReadOnlyList<BoundExpression> Indices { get; init; } = [];
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
/// <summary>
/// An array literal whose type nothing has settled yet. Every element is bound,
/// because they are what a <c>var</c> would infer from; none is converted,
/// because what to convert them to is not known.
/// </summary>
public sealed class BoundArrayDraft(
    SourceSpan span, TypeSymbol type, IReadOnlyList<BoundExpression> elements)
    : BoundExpression(span, type)
{
    public IReadOnlyList<BoundExpression> Elements { get; } = elements;
}

/// <summary>
/// A settled array literal: the array it builds, with every element already
/// converted to the element type.
/// </summary>
public sealed class BoundArrayLiteral(
    SourceSpan span, TypeSymbol type, TypeSymbol elementType,
    IReadOnlyList<BoundExpression> elements)
    : BoundExpression(span, type)
{
    public TypeSymbol ElementType { get; } = elementType;
    public IReadOnlyList<BoundExpression> Elements { get; } = elements;
}

public sealed class BoundLambda(SourceSpan span, TypeSymbol type, Syntax.LambdaSyntax syntax)
    : BoundExpression(span, type)
{
    public Syntax.LambdaSyntax Syntax { get; } = syntax;
}

/// <summary>
/// A finished <c>Ok(x)</c> or <c>Shape.Circle(2.0)</c>: the variant value it
/// builds, with each argument already converted to the field it is stored in.
///
/// The type is the variant, which is why this node only ever exists after
/// something has said which variant was meant.
/// </summary>
public sealed class BoundVariantConstruction(
    SourceSpan span,
    TypeSymbol type,
    VariantCaseSymbol variantCase,
    IReadOnlyList<BoundExpression> arguments) : BoundExpression(span, type)
{
    public VariantCaseSymbol Case { get; } = variantCase;
    public IReadOnlyList<BoundExpression> Arguments { get; } = arguments;
}

/// <summary>
/// <c>r.Ok</c> — whether a variant is holding a particular case. It is one load
/// and one comparison, and it is what a narrowing is proved from.
/// </summary>
public sealed class BoundVariantTest(
    SourceSpan span, TypeSymbol type, BoundExpression value, VariantCaseSymbol variantCase)
    : BoundExpression(span, type)
{
    public BoundExpression Value { get; } = value;
    public VariantCaseSymbol Case { get; } = variantCase;
}

/// <summary>
/// One field of a variant's payload, reached through the case it belongs to.
///
/// The binder only ever produces this where it has already established that the
/// case is the one present, so the emitter does not check the tag again.
/// </summary>
public sealed class BoundVariantPayload(
    SourceSpan span, BoundExpression receiver, VariantCaseSymbol variantCase, FieldSymbol? field)
    : BoundExpression(span, field?.Type ?? variantCase.Payload!)
{
    public BoundExpression Receiver { get; } = receiver;
    public VariantCaseSymbol Case { get; } = variantCase;

    /// <summary>
    /// The field being read, or null for the whole payload — which is what
    /// <c>case Circle c:</c> binds, and what makes <c>c</c> an ordinary struct
    /// value that copies, retains and drops like any other.
    /// </summary>
    public FieldSymbol? Field { get; } = field;
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

/// <summary>
/// <c>value is Type</c>. Answers by walking the object's base chain for a class,
/// or by looking in its dispatch table for an interface -- and by comparing
/// against null first, since an optional may hold nothing and nothing is not an
/// instance of anything.
/// </summary>
public sealed class BoundTypeTest(
    SourceSpan span, TypeSymbol type, BoundExpression value, NamedTypeSymbol tested)
    : BoundExpression(span, type)
{
    public BoundExpression Value { get; } = value;
    public NamedTypeSymbol Tested { get; } = tested;
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

    /// <summary>
    /// True when the source wrote <c>ref x</c> at a call, rather than the
    /// binder taking an address of its own accord. Overload resolution reads it:
    /// a <c>ref</c> parameter takes only an argument that said <c>ref</c>, and no
    /// other parameter takes one that did.
    /// </summary>
    public bool FromRefKeyword { get; init; }
}

/// <summary>Allocates a zeroed array of <paramref name="Length"/> elements; yields +1.</summary>
public sealed class BoundNewArray(SourceSpan span, ArrayTypeSymbol type, BoundExpression length)
    : BoundExpression(span, type)
{
    public ArrayTypeSymbol ArrayType { get; } = type;
    public BoundExpression Length { get; } = length;
}

/// <summary><c>array.Length</c>, read straight out of the object header.</summary>
/// <summary>
/// <c>a[from:to]</c>. Either end may be absent, and the emitter reads the
/// beginning or the length of what is being sliced in its place.
/// </summary>
public sealed class BoundSlice(
    SourceSpan span,
    SliceTypeSymbol type,
    BoundExpression target,
    BoundExpression? start,
    BoundExpression? end) : BoundExpression(span, type)
{
    public BoundExpression Target { get; } = target;
    public BoundExpression? Start { get; } = start;
    public BoundExpression? End { get; } = end;
}

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

/// <summary><c>alignof(T)</c>. Like sizeof, the type is kept and read at emit
/// time, because layout is settled in a later pass than binding.</summary>
public sealed class BoundAlignof(SourceSpan span, TypeSymbol type, TypeSymbol measuredType)
    : BoundExpression(span, type)
{
    public TypeSymbol MeasuredType { get; } = measuredType;
}

/// <summary>
/// <c>offsetof(T, Field)</c>. The field symbol is kept rather than its offset,
/// for the same reason: the number is not known until layout has run.
/// </summary>
public sealed class BoundOffsetof(
    SourceSpan span, TypeSymbol type, NamedTypeSymbol owner, FieldSymbol field)
    : BoundExpression(span, type)
{
    public NamedTypeSymbol Owner { get; } = owner;
    public FieldSymbol Field { get; } = field;
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

/// <summary>
/// <c>iidof(IFoo)</c>. The address of a 16-byte constant in static storage, so
/// this costs nothing at run time and the same expression twice is the same
/// pointer.
/// </summary>
public sealed class BoundIidof(
    SourceSpan span, TypeSymbol type, ComInterfaceTypeSymbol named)
    : BoundExpression(span, type)
{
    public ComInterfaceTypeSymbol Named { get; } = named;
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

/// <summary>
/// One arm of a switch: the constants that reach it, and what it runs. The
/// labels are folded literals, so the emitter can put them straight into an
/// LLVM <c>switch</c> without evaluating anything.
/// </summary>
public sealed class BoundSwitchSection(
    SourceSpan span, IReadOnlyList<BoundExpression> labels, bool isDefault, BoundStatement body)
{
    public SourceSpan Span { get; } = span;
    public IReadOnlyList<BoundExpression> Labels { get; } = labels;
    public bool IsDefault { get; } = isDefault;
    public BoundStatement Body { get; } = body;

    /// <summary>
    /// For a switch over a variant: the cases that reach this section. They take
    /// the place of <see cref="Labels"/>, which stays empty, because a case is
    /// a tag rather than a value the switched expression could equal.
    /// </summary>
    public IReadOnlyList<VariantCaseSymbol> Cases { get; init; } = [];

    /// <summary>
    /// The local a matched case's payload is copied into, for <c>case Circle
    /// c:</c>. Null for <c>case Circle:</c>, which narrows the switched value
    /// instead and needs no second name for it.
    /// </summary>
    public LocalSymbol? Binding { get; init; }
}

/// <summary>
/// A switch. Kept in the bound tree rather than lowered to a chain of ifs for
/// two reasons: an integer switch becomes one LLVM <c>switch</c>, which decides
/// for itself whether a jump table beats comparisons; and <c>break</c> has to
/// mean this construct rather than an enclosing loop, which a lowering to ifs
/// would lose.
/// </summary>
public sealed class BoundSwitch(
    SourceSpan span, BoundExpression value, IReadOnlyList<BoundSwitchSection> sections)
    : BoundStatement(span)
{
    public BoundExpression Value { get; } = value;
    public IReadOnlyList<BoundSwitchSection> Sections { get; } = sections;

    /// <summary>
    /// True when the sections between them cover every case of a variant, so
    /// nothing can fall past the switch even without a <c>default</c>. It is
    /// what lets a function end on one and still be seen to return.
    /// </summary>
    public bool IsExhaustive { get; init; }
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
