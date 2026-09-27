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

namespace Stainless.Binding;

public enum BoundBinaryOp
{
    Add, Subtract, Multiply, Divide, Remainder,
    BitAnd, BitOr, BitXor, ShiftLeft, ShiftRight, UnsignedShiftRight,
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
    /// The reference an <c>as</c> proved, as the optional it answers with.
    ///
    /// Emits nothing at all. It is the same pointer, and the test that decided
    /// which arm of the conditional runs is the whole of the check -- unlike
    /// <see cref="Downcast"/>, which is asked for where nothing has been proved
    /// and so has to ask the object itself.
    /// </summary>
    TestedReference,

    /// <summary>
    /// <c>T[]</c> -> <c>Span&lt;T&gt;</c>: the whole array, as a slice of it. Implicit,
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

/// <summary>
/// An expression only the semantic tree holds, which lowering takes away.
/// Each counts itself as it is made, so binding can tell a body that has none
/// and lowering can hand such a body on as it is.
/// </summary>
public abstract class BoundSemanticExpression : BoundExpression
{
    protected BoundSemanticExpression(SourceSpan span, TypeSymbol type) : base(span, type) => SemanticNodes.Made++;
}

/// <inheritdoc cref="BoundSemanticExpression"/>
public abstract class BoundSemanticStatement : BoundStatement
{
    protected BoundSemanticStatement(SourceSpan span) : base(span) => SemanticNodes.Made++;
}

/// <summary>
/// How many semantic nodes have been made on this thread. A compilation binds
/// on one thread, so the count before and after a body says whether it made any.
/// </summary>
internal static class SemanticNodes
{
    [ThreadStatic]
    private static int t_made;

    public static int Made
    {
        get => t_made;
        set => t_made = value;
    }
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
/// The bytes of <c>"..."u8</c>, as a <c>byte[]</c> in read-only storage with
/// an immortal count. The binder wraps it in the conversion to <c>ReadOnlySpan&lt;byte&gt;</c>,
/// which is the literal's type.
/// </summary>
public sealed class BoundUtf8Literal(SourceSpan span, TypeSymbol type, string value)
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

/// <summary>
/// Reads static storage, of a module or of a type. Storage either way, so an
/// lvalue unless it was declared <c>readonly</c>.
/// </summary>
public sealed class BoundStaticAccess(SourceSpan span, StaticSymbol symbol)
    : BoundExpression(span, symbol.Type)
{
    public StaticSymbol Static { get; } = symbol;

    public override bool IsLValue => !Static.IsReadonly;
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

    /// <summary>
    /// A field of an object is storage wherever the reference came from. A
    /// field of a struct is storage only when the struct is, because a struct
    /// a call answered is a copy that nothing will read again.
    /// </summary>
    public override bool IsLValue =>
        Receiver is null || Field.ContainingType is not StructTypeSymbol || Receiver.IsLValue;
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

    /// <summary>
    /// The order to evaluate <see cref="Arguments"/> in, as indices into it,
    /// when the call named them in an order other than the declared one. Null
    /// when the two agree.
    /// </summary>
    public IReadOnlyList<int>? EvaluationOrder { get; init; }
}

public sealed class BoundUnary(
    SourceSpan span, TypeSymbol type, BoundUnaryOp op, BoundExpression operand)
    : BoundExpression(span, type)
{
    public BoundUnaryOp Operator { get; } = op;
    public BoundExpression Operand { get; } = operand;

    /// <summary>Written inside <c>checked</c>: negating the minimum aborts.</summary>
    public bool IsChecked { get; init; }
}

public sealed class BoundBinary(
    SourceSpan span, TypeSymbol type,
    BoundExpression left, BoundBinaryOp op, BoundExpression right)
    : BoundExpression(span, type)
{
    public BoundExpression Left { get; } = left;
    public BoundBinaryOp Operator { get; } = op;
    public BoundExpression Right { get; } = right;

    /// <summary>
    /// Written inside <c>checked</c>, so an overflow of <c>+</c>, <c>-</c> or
    /// <c>*</c> aborts rather than wrapping.
    ///
    /// Wrapping is the default and is defined (§9), so this is opt-in per
    /// expression rather than a mode the whole program is compiled in.
    /// </summary>
    public bool IsChecked { get; init; }
}

/// <summary>
/// <c>++x</c>, <c>x++</c>, <c>--x</c> and <c>x--</c> over a place that is not a
/// property.
///
/// The target is addressed once and then loaded, changed and stored, which is
/// what separates this from an assignment to <c>x + 1</c>: <c>a[Next()]++</c>
/// must call <c>Next</c> exactly one time.
/// </summary>
public sealed class BoundIncrement(
    SourceSpan span, BoundExpression target, bool isPrefix, bool isIncrement)
    : BoundExpression(span, target.Type)
{
    public BoundExpression Target { get; } = target;

    /// <summary>True for <c>++x</c>: the value is the one after the change.</summary>
    public bool IsPrefix { get; } = isPrefix;
    public bool IsIncrement { get; } = isIncrement;
    public bool IsChecked { get; init; }
}

/// <summary>
/// The same over a property, where the place is a getter and a setter rather
/// than an address.
///
/// The receiver is held once, for the reason
/// <see cref="BoundPropertyAssignment"/> holds one: <c>Next().Count++</c> must
/// read and write the same object.
/// </summary>
public sealed class BoundPropertyIncrement(
    SourceSpan span,
    BoundExpression? receiver,
    PropertySymbol property,
    bool isPrefix,
    bool isIncrement,
    IReadOnlyList<BoundExpression>? arguments = null) : BoundSemanticExpression(span, property.Type)
{
    public BoundExpression? Receiver { get; } = receiver;
    public PropertySymbol Property { get; } = property;
    public bool IsPrefix { get; } = isPrefix;
    public bool IsIncrement { get; } = isIncrement;
    public bool IsChecked { get; init; }

    /// <summary>
    /// The indices, when the property is an indexer. <c>grid[4]++</c> reaches
    /// <c>get_Item(grid, 4)</c> and <c>set_Item(grid, 4, value)</c>, so the
    /// index belongs to the node as much as the receiver does — and is
    /// evaluated once for the same reason, so <c>grid[Next()]++</c> calls
    /// <c>Next</c> a single time.
    /// </summary>
    public IReadOnlyList<BoundExpression> Arguments { get; } = arguments ?? [];
}

public sealed class BoundAssignment(SourceSpan span, BoundExpression target, BoundExpression value)
    : BoundExpression(span, target.Type)
{
    public BoundExpression Target { get; } = target;
    public BoundExpression Value { get; } = value;

    /// <summary>
    /// The local this assignment brings into being, or null: a name a pattern
    /// binds is declared by the store that gives it its value, because no
    /// statement declares it.
    /// </summary>
    public LocalSymbol? DeclaresLocal { get; init; }

    /// <summary>
    /// True when lowering knows the target holds nothing yet: a local declared
    /// without a value and given one once on any path. The store then has
    /// nothing to release.
    /// </summary>
    public bool IsInitialization { get; init; }
}

/// <summary>
/// <c>a.b = v</c> or <c>a[i] = v</c> where the value runs code before the
/// store. That code may drop the last other reference to what the store lands
/// in, so lowering holds it -- the object, or the array -- while it runs.
/// </summary>
public sealed class BoundMemberAssignment(SourceSpan span, BoundExpression target, BoundExpression value)
    : BoundSemanticExpression(span, target.Type)
{
    public BoundExpression Target { get; } = target;
    public BoundExpression Value { get; } = value;
}

/// <summary>
/// <c>x as C</c>: the value asked once whether it is a <c>C</c>, and that
/// same reference, as a <c>C?</c>, where it is.
/// </summary>
public sealed class BoundAs(SourceSpan span, TypeSymbol type, BoundExpression value, NamedTypeSymbol wanted)
    : BoundSemanticExpression(span, type)
{
    public BoundExpression Value { get; } = value;
    public NamedTypeSymbol Wanted { get; } = wanted;
}

/// <summary>
/// <c>new T(...) { X = 1, Y = 2 }</c> or <c>new T { a, b }</c>: an object made,
/// then written to or added to entry by entry, and then the value.
/// </summary>
public sealed class BoundObjectInitializer(
    SourceSpan span, TypeSymbol type, BoundExpression creation, BoundPlaceholder made,
    IReadOnlyList<BoundExpression> writes) : BoundSemanticExpression(span, type)
{
    public BoundExpression Creation { get; } = creation;

    /// <summary>The object made, as each write names it.</summary>
    public BoundPlaceholder Made { get; } = made;

    /// <summary>Each entry: an assignment to a member, or a call to <c>Add</c>.</summary>
    public IReadOnlyList<BoundExpression> Writes { get; } = writes;
}

/// <summary>
/// <c>record with { X = 1 }</c>: a copy of a record, made by its clone, with
/// the properties named given new values.
/// </summary>
public sealed class BoundWith(
    SourceSpan span, ClassTypeSymbol record, BoundExpression target, FunctionSymbol clone,
    IReadOnlyList<BoundWithAssignment> assignments) : BoundSemanticExpression(span, record)
{
    public ClassTypeSymbol Record { get; } = record;
    public BoundExpression Target { get; } = target;

    /// <summary>The copy, dispatched, so a derived record comes back whole.</summary>
    public FunctionSymbol Clone { get; } = clone;

    public IReadOnlyList<BoundWithAssignment> Assignments { get; } = assignments;
}

/// <summary>One property a <c>with</c> gives a new value, already converted to its type.</summary>
public sealed class BoundWithAssignment(SourceSpan span, PropertySymbol property, BoundExpression value)
{
    public SourceSpan Span { get; } = span;
    public PropertySymbol Property { get; } = property;
    public BoundExpression Value { get; } = value;
}

/// <summary>
/// <c>x op= y</c> and <c>x ??= y</c>, on a place or on a property: the place
/// read, combined with the value, and written back.
///
/// Lowering names the place, or the property's receiver and indices, once:
/// held where naming it again could evaluate something or reach elsewhere.
/// </summary>
public sealed class BoundCompoundAssignment(
    SourceSpan span, TypeSymbol type, BoundExpression target, BoundPlaceholder current,
    BoundExpression value, BoundExpression combined, bool isFallback) : BoundSemanticExpression(span, type)
{
    /// <summary>The place, or for a property the call to its getter that read it.</summary>
    public BoundExpression Target { get; } = target;

    /// <summary>The property written, or null for a place.</summary>
    public PropertySymbol? Property { get; init; }

    /// <summary>What the place holds before the write, as <see cref="Combined"/> names it.</summary>
    public BoundPlaceholder Current { get; } = current;

    /// <summary>The right side as written. <see cref="Combined"/> holds it too.</summary>
    [SharedSubtree]
    public BoundExpression Value { get; } = value;

    /// <summary>
    /// What is written: <c>x op y</c> converted back to the place's type, or
    /// for <c>??=</c> the value alone, written only where the place held
    /// nothing.
    /// </summary>
    public BoundExpression Combined { get; } = combined;

    /// <summary>True for <c>??=</c>.</summary>
    public bool IsFallback { get; } = isFallback;
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
    SourceSpan span, BoundExpression? receiver, PropertySymbol property, BoundExpression value)
    : BoundSemanticExpression(span, property.Type)
{
    /// <summary>Null for a static property, which is written by naming its type.</summary>
    public BoundExpression? Receiver { get; } = receiver;
    public PropertySymbol Property { get; } = property;
    public BoundExpression Value { get; } = value;

    /// <summary>
    /// True for <c>base.P = x</c>: the setter this class replaced, reached
    /// directly rather than through the vtable, which would find the override
    /// again.
    /// </summary>
    public bool IsNonVirtual { get; init; }

    /// <summary>
    /// What went between the brackets, for <c>a[i] = v</c>. Empty for an
    /// ordinary property, which is the only thing separating the two: an
    /// indexer's setter takes its indices before <c>value</c>.
    /// </summary>
    public IReadOnlyList<BoundExpression> Indices { get; init; } = [];

    /// <summary>
    /// True for a write as the source has it, whose receiver lowering holds
    /// while a value that runs code is evaluated, for the reason a
    /// <see cref="BoundMemberAssignment"/> holds its object.
    /// </summary>
    public bool HoldsReceiver { get; init; }
}

/// <summary>
/// <c>condition ? whenTrue : whenFalse</c>. Kept as a node rather than lowered
/// to an <c>if</c>, because only the chosen arm may be evaluated and the result
/// is a value, not a statement.
/// </summary>
/// <summary>
/// A value held in a fresh local for the duration of an expression.
///
/// It exists because some expressions have to name what they are working on
/// twice -- <c>a?.b</c> asks whether <c>a</c> is there and then reads through
/// it -- and evaluating it twice would call whatever produced it twice. There
/// is nowhere in an expression to put a statement, so the binding is an
/// expression too.
///
/// The local borrows: whatever made the value is already a temporary the
/// statement will drop, and this only reads it in the meantime.
/// </summary>
public sealed class BoundLet(
    SourceSpan span, LocalSymbol local, BoundExpression value, BoundExpression body)
    : BoundExpression(span, body.Type)
{
    public LocalSymbol Local { get; } = local;
    public BoundExpression Value { get; } = value;
    public BoundExpression Body { get; } = body;

    /// <summary>
    /// True when the local holds its own reference until the statement ends.
    /// An assignment sets it on the object it stores into, because the value
    /// it evaluates in between may release that object's last other owner.
    /// </summary>
    public bool IsOwned { get; init; }
}

/// <summary>
/// <c>a?.m</c>, <c>a?.M(x)</c>, <c>a?[i]</c>: the receiver asked whether it is
/// there, and reached through only if it is -- with <c>?? b</c> after it,
/// <see cref="WhenNothing"/> is <c>b</c>.
///
/// Lowering holds the receiver once, because it is read twice: once to ask,
/// once to reach through. Without that, <c>Next()?.Name</c> would call
/// <c>Next</c> twice and ask about one object while reading another.
/// </summary>
public sealed class BoundConditionalAccess(
    SourceSpan span, TypeSymbol type, BoundExpression receiver, BoundPlaceholder present,
    BoundExpression access, BoundExpression whenNothing) : BoundSemanticExpression(span, type)
{
    /// <summary>The optional asked about.</summary>
    public BoundExpression Receiver { get; } = receiver;

    /// <summary>The receiver known to be there, as <see cref="Access"/> names it.</summary>
    public BoundPlaceholder Present { get; } = present;

    public BoundExpression Access { get; } = access;

    /// <summary>What the whole is when the receiver was nothing: null, or what <c>??</c> said.</summary>
    public BoundExpression WhenNothing { get; } = whenNothing;
}

/// <summary>
/// <c>a ?? b</c>: <c>a</c> where it is something, and <c>b</c>, evaluated only
/// then, where it is nothing. The type is <c>a</c>'s element when <c>b</c> is
/// not optional, since there is then something either way.
/// </summary>
public sealed class BoundNullFallback(
    SourceSpan span, TypeSymbol type, BoundExpression value, BoundExpression fallback)
    : BoundSemanticExpression(span, type)
{
    public BoundExpression Value { get; } = value;

    /// <summary>Already converted to the type of the whole.</summary>
    public BoundExpression Fallback { get; } = fallback;
}

/// <summary>
/// Several expressions evaluated in order, the last of which is the value.
///
/// It exists for the lowering of an object initializer, where a construction
/// has to be followed by the writes it asked for and still be an expression.
/// Everything before the last one is evaluated for what it does.
/// </summary>
public sealed class BoundSequence(
    SourceSpan span, IReadOnlyList<BoundExpression> before, BoundExpression value)
    : BoundExpression(span, value.Type)
{
    public IReadOnlyList<BoundExpression> Before { get; } = before;
    public BoundExpression Value { get; } = value;
}

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

    /// <summary>
    /// The object <c>obj.Method</c> named, which only a closure can carry.
    /// Null for a bare function name.
    /// </summary>
    public BoundExpression? Receiver { get; init; }
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
/// <c>..source</c> in an array literal, waiting with the literal to be told
/// what it becomes. Its type is the element type of <see cref="Source"/>, which
/// is what the literal's own elements are compared with. Never emitted.
/// </summary>
public sealed class BoundSpread(SourceSpan span, TypeSymbol elementType, BoundExpression source)
    : BoundExpression(span, elementType)
{
    public BoundExpression Source { get; } = source;
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

    /// <summary>
    /// True for the array behind a <c>params Span&lt;T&gt;</c> call: it lives in the
    /// caller's frame for the statement, and is checked on the way out for a
    /// reference anything kept.
    /// </summary>
    public bool OnStack { get; init; }
}

/// <summary>
/// What a call gave its <c>params</c> parameter element by element,
/// gathered: into a <c>T[]</c> made for the call, or for a <c>Span&lt;T&gt;</c>, into
/// an array the slice views.
/// </summary>
public sealed class BoundParamsArray(
    SourceSpan span, TypeSymbol type, ArrayTypeSymbol array, IReadOnlyList<BoundExpression> elements)
    : BoundSemanticExpression(span, type)
{
    /// <summary>The array made: the parameter's own type, or the one its slice views.</summary>
    public ArrayTypeSymbol Array { get; } = array;

    /// <summary>Each converted to the element type.</summary>
    public IReadOnlyList<BoundExpression> Elements { get; } = elements;

    /// <summary>
    /// True where the array lives in the caller's frame for the statement,
    /// which a <c>Span&lt;T&gt;</c> is given unless the call outlives the statement.
    /// </summary>
    public bool InFrame { get; set; }
}

/// <summary>How a <see cref="BoundCollection"/> makes what it becomes.</summary>
public enum CollectionForm
{
    /// <summary>An array or an inline array, every spread an inline one, written out.</summary>
    Literal,

    /// <summary>An array made once at the size every spread says, and filled from the front.</summary>
    Filled,

    /// <summary>An array gathered into an <c>ArrayBuilder</c>, for a spread that cannot say its count.</summary>
    Gathered,

    /// <summary>A class made and added to.</summary>
    Added,
}

/// <summary>
/// A collection expression settled against its target, where it is more than
/// an array literal: <c>[a, ..b]</c> as an array or an inline array, or
/// <c>[a, b]</c> as a class with <c>Add</c>.
///
/// Where a spread is among the parts, every part is evaluated in the order
/// written, and held, before anything is made.
/// </summary>
public sealed class BoundCollection(
    SourceSpan span, TypeSymbol type, TypeSymbol elementType, CollectionForm form,
    IReadOnlyList<BoundExpression> parts) : BoundSemanticExpression(span, type)
{
    public TypeSymbol ElementType { get; } = elementType;
    public CollectionForm Form { get; } = form;

    /// <summary>Each element converted to <see cref="ElementType"/>, or a <see cref="BoundCollectionSpread"/>.</summary>
    public IReadOnlyList<BoundExpression> Parts { get; } = parts;

    /// <summary>What is made and added to: the class, or the <c>ArrayBuilder</c>.</summary>
    public ClassTypeSymbol? Builder { get; init; }

    public FunctionSymbol? Constructor { get; init; }
    public FunctionSymbol? Add { get; init; }

    /// <summary>The builder's <c>ToArray</c>, for <see cref="CollectionForm.Gathered"/>.</summary>
    public FunctionSymbol? Finish { get; init; }

    /// <summary>How many elements there will be, as <see cref="Capacity"/> names it.</summary>
    public BoundPlaceholder? Total { get; init; }

    /// <summary>The argument to a constructor that takes a capacity, or null.</summary>
    public BoundExpression? Capacity { get; init; }
}

/// <summary>
/// <c>..source</c> in a <see cref="BoundCollection"/>: walked by a function
/// of <c>ArrayBuilder.sl</c>, or, for an inline array, written out.
/// </summary>
public sealed class BoundCollectionSpread(
    SourceSpan span, TypeSymbol elementType, BoundExpression source, BoundPlaceholder walked)
    : BoundSemanticExpression(span, elementType)
{
    public BoundExpression Source { get; } = source;

    /// <summary>The source, as <see cref="Count"/> and <see cref="Elements"/> name it.</summary>
    public BoundPlaceholder Walked { get; } = walked;

    /// <summary>How many it yields, as a <c>nuint</c>; null where that is not asked.</summary>
    public BoundExpression? Count { get; init; }

    /// <summary>The function that walks it into what is made; null for an inline array.</summary>
    public FunctionSymbol? Walk { get; init; }

    /// <summary>An inline array's elements, each read and converted.</summary>
    public IReadOnlyList<BoundExpression> Elements { get; init; } = [];
}

public sealed class BoundLambda(SourceSpan span, TypeSymbol type, Syntax.LambdaSyntax syntax)
    : BoundExpression(span, type)
{
    public Syntax.LambdaSyntax Syntax { get; } = syntax;

    /// <summary>
    /// The local function this lambda stands for, when it was written as a
    /// name rather than as a lambda.
    /// </summary>
    public string? LocalFunction { get; init; }
}

/// <summary>
/// A finished <c>Ok(x)</c> or <c>Shape.Circle(2.0)</c>: the variant value it
/// builds, with each argument already converted to the field it is stored in.
///
/// The type is the variant, which is why this node only ever exists after
/// something has said which variant was meant.
/// </summary>
/// <summary>
/// <c>(a, b)</c> — a tuple written out.
///
/// Its own node rather than a struct literal, because there is no struct
/// literal: a struct is otherwise filled in field by field. What it emits is
/// exactly that, all at once.
/// </summary>
public sealed class BoundTupleCreate(
    SourceSpan span, TupleTypeSymbol type, IReadOnlyList<BoundExpression> elements)
    : BoundExpression(span, type)
{
    public TupleTypeSymbol Tuple { get; } = type;
    public IReadOnlyList<BoundExpression> Elements { get; } = elements;
}

/// <summary>
/// <c>var (a, b) = t;</c> and <c>(int a, b) = t;</c> — a deconstruction that
/// declares some of what it names.
///
/// The locals belong to the enclosing block rather than to a block of their
/// own, so they are declared here with no value and then written by
/// <see cref="Expression"/>, which is the deconstruction itself.
/// </summary>
public sealed class BoundDeconstruct(
    SourceSpan span,
    IReadOnlyList<BoundLocalDeclaration> declarations,
    BoundExpression expression) : BoundStatement(span)
{
    public IReadOnlyList<BoundLocalDeclaration> Declarations { get; } = declarations;
    public BoundExpression Expression { get; } = expression;
}

/// <summary>
/// <c>(a, b) = (b, a)</c>, <c>var (x, y) = point</c>, and a <c>foreach</c>'s
/// element taken apart: what each element of the left side is, and what it
/// is given.
///
/// Lowering evaluates in C#'s order: the targets' receivers and indices left
/// to right, then every value on the right, then the stores left to right.
/// Nothing is stored until everything has been read, which is what makes a
/// swap a swap.
/// </summary>
public sealed class BoundDeconstruction(
    SourceSpan span, TypeSymbol type, BoundDeconstructionTarget target, bool isValue)
    : BoundSemanticExpression(span, type)
{
    public BoundDeconstructionTarget Target { get; } = target;

    /// <summary>True where the whole is read: its value is the tuple of what was stored.</summary>
    public bool IsValue { get; } = isValue;
}

public enum DeconstructionKind { Discard, Declare, Place, Property, Nested }

/// <summary>How a nested target's elements are given their values.</summary>
public enum DeconstructionSupply
{
    /// <summary><c>(a, b) = (x, y)</c>: each element its own value, and no tuple made.</summary>
    Elements,

    /// <summary>A tuple, each element given one of its fields.</summary>
    Tuple,

    /// <summary>Anything else, taken apart by its <c>Deconstruct</c>.</summary>
    Deconstruct,
}

/// <summary>One element of the left side of a <see cref="BoundDeconstruction"/>, and what it is given.</summary>
public sealed record BoundDeconstructionTarget
{
    public BoundDeconstructionTarget(SourceSpan span, DeconstructionKind kind, TypeSymbol? type)
    {
        Span = span;
        Kind = kind;
        Type = type;
    }

    public SourceSpan Span { get; }
    public DeconstructionKind Kind { get; }

    /// <summary>
    /// What an element is stored as; for a nested target whose whole is
    /// read, the tuple of what it stored, and otherwise null.
    /// </summary>
    public TypeSymbol? Type { get; }

    /// <summary>What a <see cref="DeconstructionKind.Declare"/> declares, and where its name is.</summary>
    public LocalSymbol? Local { get; init; }

    public SourceSpan NameSpan { get; init; }

    /// <summary>The storage a <see cref="DeconstructionKind.Place"/> writes.</summary>
    public BoundExpression? Place { get; init; }

    public BoundExpression? Receiver { get; init; }
    public PropertySymbol? Property { get; init; }
    public IReadOnlyList<BoundExpression> Indices { get; init; } = [];
    public bool IsNonVirtual { get; init; }

    public IReadOnlyList<BoundDeconstructionTarget> Elements { get; init; } = [];

    public DeconstructionSupply Supply { get; init; }

    /// <summary>
    /// What this is given: for an element, the value converted to
    /// <see cref="Type"/>; for a nested target, the tuple or the call to
    /// <c>Deconstruct</c>, and null for <see cref="DeconstructionSupply.Elements"/>.
    /// </summary>
    public BoundExpression? Value { get; init; }

    /// <summary>
    /// True when <see cref="Value"/> reads what no store here can reach, so it
    /// need not be held unless reading it again does something.
    /// </summary>
    public bool IsStable { get; init; }

    /// <summary>A tuple, as its elements' values read it.</summary>
    public BoundPlaceholder? Whole { get; init; }

    /// <summary>The storage every <see cref="DeconstructionKind.Place"/> here writes, left to right.</summary>
    public IEnumerable<BoundExpression> WrittenPlaces =>
        Kind == DeconstructionKind.Nested ? Elements.SelectMany(e => e.WrittenPlaces)
        : Place is { } place ? [place]
        : [];
}

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
/// <c>try e</c>, as the three pieces the emitter needs.
///
/// The operand is evaluated once into <see cref="Slot"/>, which both paths
/// then read: <see cref="OnFailure"/> is an ordinary <c>return</c> of a
/// <c>Fail</c> carrying its error, and <see cref="OnSuccess"/> reads its
/// value. Building the failure path as a real return is what makes it behave
/// like one -- reference counts, scope releases and a struct return through
/// sret are all the emitter's existing code, not a second copy of it.
/// </summary>
public sealed class BoundTry(
    SourceSpan span, TypeSymbol type, LocalSymbol slot, BoundExpression operand,
    BoundExpression test, BoundStatement onFailure, BoundExpression onSuccess)
    : BoundExpression(span, type)
{
    public LocalSymbol Slot { get; } = slot;
    public BoundExpression Operand { get; } = operand;

    /// <summary>Whether the slot is holding <c>Ok</c>.</summary>
    public BoundExpression Test { get; } = test;

    public BoundStatement OnFailure { get; } = onFailure;
    public BoundExpression OnSuccess { get; } = onSuccess;
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

    /// <summary>As <see cref="BoundCall.EvaluationOrder"/>.</summary>
    public IReadOnlyList<int>? EvaluationOrder { get; init; }
}

/// <summary>
/// Binding a method to an object: the two words of a closure.
///
/// <paramref name="receiver"/> is null for a plain function, which has no
/// object to carry. The call still passes something as argument zero -- the
/// shape has to be uniform or every call would need a branch -- so a thunk
/// that ignores it stands in, and the receiver word holds null.
/// </summary>
public sealed class BoundClosureCreate(
    SourceSpan span,
    ClosureTypeSymbol closureType,
    FunctionSymbol function,
    BoundExpression? receiver)
    : BoundExpression(span, closureType)
{
    public ClosureTypeSymbol ClosureType { get; } = closureType;
    public FunctionSymbol Function { get; } = function;
    public BoundExpression? Receiver { get; } = receiver;
}

/// <summary>
/// Two closures compared: the same method on the same object.
///
/// A node of its own rather than two field comparisons joined by <c>&amp;&amp;</c>,
/// because each side must be evaluated once — <c>Make() == other</c> would
/// otherwise call <c>Make</c> twice, once per word.
///
/// This is what makes a closure removable from a list of them. It is also why
/// Delphi's method pointers are values rather than objects: two mentions of
/// <c>this.Handler</c> are equal, where two generated adapters would not have
/// been.
/// </summary>
public sealed class BoundClosureEqual(
    SourceSpan span,
    ClosureTypeSymbol closureType,
    BoundExpression left,
    BoundExpression right,
    bool negated)
    : BoundExpression(span, PrimitiveTypeSymbol.Bool)
{
    public ClosureTypeSymbol ClosureType { get; } = closureType;
    public BoundExpression Left { get; } = left;
    public BoundExpression Right { get; } = right;
    public bool Negated { get; } = negated;
}

/// <summary>
/// A call through a closure: the function it holds, given the object it holds
/// as argument zero and then the arguments written.
///
/// That the receiver goes first is not a convention invented here. A method
/// already takes its <c>this</c> in that position, so a bound method needs no
/// thunk and no shuffling -- the closure is the address of the method itself.
/// </summary>
public sealed class BoundClosureCall(
    SourceSpan span,
    ClosureTypeSymbol closureType,
    BoundExpression target,
    IReadOnlyList<BoundExpression> arguments)
    : BoundExpression(span, closureType.ReturnType)
{
    public ClosureTypeSymbol ClosureType { get; } = closureType;
    public BoundExpression Target { get; } = target;
    public IReadOnlyList<BoundExpression> Arguments { get; } = arguments;

    /// <summary>As <see cref="BoundCall.EvaluationOrder"/>.</summary>
    public IReadOnlyList<int>? EvaluationOrder { get; init; }
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

/// <summary>
/// <c>value is pattern</c>, and what a condition built on it can learn.
///
/// Lowering turns it into the tests the pattern asks. The rest is for the
/// binder: which names the pattern assigned when it matched and when it did
/// not, and what it proved about <see cref="Subject"/> either way.
/// </summary>
public sealed class BoundIsPattern(
    SourceSpan span, BoundExpression subject, BoundPlaceholder input, BoundPattern pattern)
    : BoundSemanticExpression(span, PrimitiveTypeSymbol.Bool)
{
    /// <summary>The value tested, as written.</summary>
    public BoundExpression Subject { get; } = subject;

    /// <summary>How the pattern names <see cref="Subject"/>.</summary>
    public BoundPlaceholder Input { get; } = input;

    public BoundPattern Pattern { get; } = pattern;

    /// <summary>
    /// True when the pattern names its subject with nothing but a type test
    /// first, so the name keeps a reference of its own before anything could
    /// release the one the subject borrowed.
    /// </summary>
    public bool BindsAtOnce { get; init; }

    public IReadOnlyList<LocalSymbol> AssignedWhenTrue { get; init; } = [];
    public IReadOnlyList<LocalSymbol> AssignedWhenFalse { get; init; } = [];

    /// <summary>The case the subject holds where the test was true, or false.</summary>
    public VariantCaseSymbol? CaseWhenTrue { get; init; }
    public VariantCaseSymbol? CaseWhenFalse { get; init; }

    public bool NotNullWhenTrue { get; init; }
    public bool NotNullWhenFalse { get; init; }
}

/// <summary>
/// <c>value switch { pattern when guard =&gt; result, ... }</c>.
///
/// Every arm's value is already converted to <see cref="BoundExpression.Type"/>.
/// Lowering decides how the arms are reached.
/// </summary>
public sealed class BoundSwitchExpression(
    SourceSpan span, TypeSymbol type, BoundExpression subject, BoundPlaceholder input,
    IReadOnlyList<BoundSwitchArm> arms)
    : BoundSemanticExpression(span, type)
{
    public BoundExpression Subject { get; } = subject;

    /// <summary>How every arm's pattern names <see cref="Subject"/>.</summary>
    public BoundPlaceholder Input { get; } = input;

    public IReadOnlyList<BoundSwitchArm> Arms { get; } = arms;

    /// <summary>
    /// True when the arms cover every value, so the last is reached only by
    /// what it matches. False when they cover an enum only by naming every
    /// member, which leaves a value that is none of them.
    /// </summary>
    public bool IsTotal { get; init; }
}

/// <summary>One arm of a switch expression.</summary>
public sealed class BoundSwitchArm(
    SourceSpan span, BoundPattern pattern, BoundExpression? guard, BoundExpression value)
{
    public SourceSpan Span { get; } = span;
    public BoundPattern Pattern { get; } = pattern;

    /// <summary>The <c>when</c>, which reads what the pattern named.</summary>
    public BoundExpression? Guard { get; } = guard;

    public BoundExpression Value { get; } = value;
}

/// <summary>
/// What a <c>switch</c> expression over an enum evaluates when the value is
/// none of the members its arms named: the end of the program, with a message.
/// The type is the switch's own, so the arm has somewhere to be.
/// </summary>
public sealed class BoundUnmatchedSwitch(SourceSpan span, TypeSymbol type, TypeSymbol subject)
    : BoundExpression(span, type)
{
    /// <summary>The enum the value was supposed to be a member of.</summary>
    public TypeSymbol Subject { get; } = subject;
}

public sealed class BoundConversion(
    SourceSpan span, TypeSymbol type, BoundExpression operand, ConversionKind kind)
    : BoundExpression(span, type)
{
    public BoundExpression Operand { get; } = operand;
    public ConversionKind Kind { get; } = kind;

    /// <summary>
    /// Written inside <c>checked</c>: a numeric conversion whose value does not
    /// fit the target aborts rather than truncating or saturating.
    /// </summary>
    public bool IsChecked { get; init; }
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

    /// <summary>As <see cref="BoundCall.EvaluationOrder"/>.</summary>
    public IReadOnlyList<int>? EvaluationOrder { get; init; }
}

/// <summary>
/// Zeroes a slot and runs a struct's constructor over it; yields the value.
///
/// Nothing is allocated: a struct is a value, so the slot is the temporary the
/// expression already needed. The zeroing is what makes a field the
/// constructor did not write the zero it would have been in <c>T value;</c>,
/// which is the only answer that keeps the two ways of making one agreeing.
/// </summary>
public sealed class BoundStructNew(
    SourceSpan span,
    StructTypeSymbol structType,
    FunctionSymbol constructor,
    IReadOnlyList<BoundExpression> arguments)
    : BoundExpression(span, structType)
{
    public StructTypeSymbol StructType { get; } = structType;
    public FunctionSymbol Constructor { get; } = constructor;
    public IReadOnlyList<BoundExpression> Arguments { get; } = arguments;

    /// <summary>As <see cref="BoundCall.EvaluationOrder"/>.</summary>
    public IReadOnlyList<int>? EvaluationOrder { get; init; }
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

    /// <summary>
    /// True when the source wrote <c>out x</c>. Read for the same reason: an
    /// <c>out</c> parameter takes only an argument that said <c>out</c>.
    /// </summary>
    public bool FromOutKeyword { get; init; }

    /// <summary>
    /// The local an <c>out var x</c> brought into being, or null.
    ///
    /// The emitter needs it to give the variable a slot before the call rather
    /// than after: nothing declared it, so nothing else would.
    /// </summary>
    public LocalSymbol? DeclaresLocal { get; init; }
}

/// <summary>
/// <c>out var x</c> or <c>out int x</c> at a call, before an overload has been
/// chosen.
///
/// It has no address yet because it has no variable yet, and it has no variable
/// yet because <c>out var</c> is waiting to be told the type. Kept as a draft
/// for the same reason an array literal is: it must not vote on which overload
/// was meant, having said nothing about it.
/// </summary>
public sealed class BoundOutDraft(
    SourceSpan span, TypeSymbol type, string name, SourceSpan nameSpan)
    : BoundExpression(span, type)
{
    public string Name { get; } = name;
    public SourceSpan NameSpan { get; } = nameSpan;

    /// <summary>True for <c>out var x</c>, where the parameter decides.</summary>
    public bool NeedsType => Type.IsError();
}

/// <summary>
/// <c>default(T)</c>: the value a type's storage holds before anything is put
/// in it. Zero for a number, false, null for a reference or pointer, and every
/// field of a struct the same way down.
/// </summary>
public sealed class BoundDefault(SourceSpan span, TypeSymbol type)
    : BoundExpression(span, type);

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

    /// <summary>What <see cref="Start"/> counts from.</summary>
    public IndexOrigin StartOrigin { get; init; }

    /// <summary>What <see cref="End"/> counts from.</summary>
    public IndexOrigin EndOrigin { get; init; }
}

/// <summary>
/// <c>x[a..b]</c> where the range is taken apart as it runs: an array or a
/// slice by a <c>Range</c> value, or a type with a <c>Count</c> or
/// <c>Length</c> and a <c>Slice(start, length)</c>.
///
/// Lowering evaluates, in order and each once, what is sliced, its count,
/// the range and the offset the run starts at, and then
/// <see cref="Access"/>, which names each by its placeholder.
/// </summary>
public sealed class BoundRangeSlice(SourceSpan span, TypeSymbol type, BoundExpression access)
    : BoundSemanticExpression(span, type)
{
    /// <summary>What is sliced, where <see cref="Access"/> names it as <see cref="Receiver"/>.</summary>
    public BoundExpression? Target { get; init; }

    public BoundPlaceholder? Receiver { get; init; }

    /// <summary>The count of what is sliced, as a <c>nuint</c>, named as <see cref="Counted"/>.</summary>
    public BoundExpression? Length { get; init; }

    public BoundPlaceholder? Counted { get; init; }

    /// <summary>A range known only as it runs, named as <see cref="Whole"/>.</summary>
    public BoundExpression? Range { get; init; }

    public BoundPlaceholder? Whole { get; init; }

    /// <summary>Where the run starts, as a <c>nuint</c>, named as <see cref="From"/>.</summary>
    public BoundExpression? Start { get; init; }

    public BoundPlaceholder? From { get; init; }

    /// <summary>The slice, or the call to <c>Slice</c>.</summary>
    public BoundExpression Access { get; } = access;
}

/// <summary>
/// A value read more than once, evaluated where it first stands: the
/// receiver of <c>x[^1]</c> on a type with a <c>Count</c>, which the count
/// then reads again as <see cref="Name"/>.
/// </summary>
public sealed class BoundNamedValue(SourceSpan span, BoundExpression value, BoundPlaceholder name)
    : BoundSemanticExpression(span, value.Type)
{
    public BoundExpression Value { get; } = value;

    /// <summary>What reads it after.</summary>
    public BoundPlaceholder Name { get; } = name;
}

/// <summary>What a position in an array, a slice or an inline array counts from.</summary>
public enum IndexOrigin
{
    /// <summary>An integer, from the start.</summary>
    Start,

    /// <summary><c>^n</c>: an integer, back from the length.</summary>
    End,

    /// <summary>A <c>Standard.Index</c>, which carries which of the two it is.</summary>
    Written,
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

    /// <summary>What <see cref="Index"/> counts from. Only a pointer is always from the start.</summary>
    public IndexOrigin Origin { get; init; }

    /// <summary>
    /// An element of an array, a slice or a pointer is storage. An element of
    /// an inline array is part of the value holding it, so it is storage only
    /// when that value is.
    /// </summary>
    public override bool IsLValue => Target.Type is not FixedArrayTypeSymbol || Target.IsLValue;
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

/// <summary>
/// What an <c>[Embed]</c> static holds: the address of an immortal
/// <c>byte[]</c> the linker placed, so it costs nothing at run time and the
/// same file embedded twice the same way is the same object.
///
/// It is only ever a static's initializer — there is no expression that
/// produces one — which is what makes it a constant the global can be born
/// holding rather than something the entry point has to run.
/// </summary>
public sealed class BoundEmbed(SourceSpan span, TypeSymbol type, EmbeddedFile file)
    : BoundExpression(span, type)
{
    public EmbeddedFile File { get; } = file;
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

    /// <summary>
    /// True when binding the statement made nothing lowering takes away, so
    /// lowering hands it on as it is. A statement rebuilt around new children
    /// is not marked, and is walked.
    /// </summary>
    internal bool IsCore { get; set; }
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

    /// <summary>
    /// True for a local of lowering's own that reads a value something else
    /// keeps alive for as long as the local is in scope, and so counts nothing.
    /// The initializer MUST be a value that is borrowed or needs no count.
    /// </summary>
    public bool IsBorrowed { get; init; }
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
/// <c>do { ... } while (c);</c>. Kept rather than lowered to a <c>while</c>
/// with a copy of the body, because a copy would emit the body twice and would
/// give <c>continue</c> two places to go.
/// </summary>
public sealed class BoundDoWhile(SourceSpan span, BoundStatement body, BoundExpression condition)
    : BoundStatement(span)
{
    public BoundStatement Body { get; } = body;
    public BoundExpression Condition { get; } = condition;
}

/// <summary>Somewhere a <c>goto</c> in the same function can name.</summary>
public sealed class BoundLabel(SourceSpan span, LabelSymbol label) : BoundStatement(span)
{
    public LabelSymbol Label { get; } = label;
}

/// <summary>
/// A jump to a <see cref="BoundLabel"/> in the same function, or to a switch
/// section's <see cref="BoundSwitchSection.Entry"/>.
/// </summary>
public sealed class BoundGoto(SourceSpan span, LabelSymbol label) : BoundStatement(span)
{
    /// <summary>
    /// Settable because <c>goto case</c> may name a section the binder has not
    /// reached yet, and is pointed at it once the whole switch is bound.
    /// </summary>
    public LabelSymbol Label { get; set; } = label;
}

/// <summary>
/// <c>foreach (T x in collection) body</c>: the element each pass names, and
/// the value <see cref="Variable"/> is given from it.
///
/// Lowering makes the loop: an index over an array or a slice, or the
/// enumerator's <c>MoveNext</c> and <c>Current</c> for anything else. The
/// collection is evaluated once, which fixes what is iterated and keeps it
/// alive for the whole loop.
/// </summary>
public sealed class BoundForEach(
    SourceSpan span, BoundExpression collection, LocalSymbol variable, BoundPlaceholder element,
    BoundExpression value, BoundStatement? deconstruction, BoundStatement body) : BoundSemanticStatement(span)
{
    public BoundExpression Collection { get; } = collection;

    /// <summary>The loop variable, one per pass.</summary>
    public LocalSymbol Variable { get; } = variable;

    /// <summary>The element as the collection yields it, as <see cref="Value"/> names it.</summary>
    public BoundPlaceholder Element { get; } = element;

    /// <summary>What the variable is given from the element, converted to its type.</summary>
    public BoundExpression Value { get; } = value;

    /// <summary><c>foreach (var (a, b) in pairs)</c>: the variable taken apart, or null.</summary>
    public BoundStatement? Deconstruction { get; } = deconstruction;

    public BoundStatement Body { get; } = body;

    /// <summary>The enumerator's methods; null for an array or a slice, which are indexed.</summary>
    public FunctionSymbol? GetEnumerator { get; init; }

    public FunctionSymbol? MoveNext { get; init; }
    public FunctionSymbol? Current { get; init; }
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
/// One register of an <c>asm</c> statement and what it is paired with.
/// </summary>
/// <param name="value">
/// For <c>in</c>, the value, already converted where a literal had to be; for
/// <c>out</c> and <c>inout</c>, the place, which has an address.
/// </param>
/// <param name="constraint">The register as LLVM is to be told it.</param>
public sealed class BoundAsmOperand(
    SourceSpan span, Syntax.AsmDirection direction, AsmRegister register, string constraint,
    BoundExpression value)
{
    public SourceSpan Span { get; } = span;
    public Syntax.AsmDirection Direction { get; } = direction;
    public AsmRegister Register { get; } = register;
    public string Constraint { get; } = constraint;
    public BoundExpression Value { get; } = value;

    public bool IsInput => Direction != Syntax.AsmDirection.Out;
    public bool IsOutput => Direction != Syntax.AsmDirection.In;
}

/// <summary>
/// <c>asm (operands) { text }</c>: one LLVM inline-assembly call.
///
/// The clobbers are decided here rather than by the emitter, because they are
/// the rule the language states — every register a C call may change, and
/// every operand's register — and the binder is where the target is known in
/// the terms that rule is written in.
/// </summary>
public sealed class BoundAsm(
    SourceSpan span, string text, SourceSpan textSpan, IReadOnlyList<BoundAsmOperand> operands,
    IReadOnlyList<string> clobbers) : BoundStatement(span)
{
    /// <summary>The instructions, exactly as written between the braces.</summary>
    public string Text { get; } = text;

    /// <summary>The braces and what is between them, in the source.</summary>
    public SourceSpan TextSpan { get; } = textSpan;

    public IReadOnlyList<BoundAsmOperand> Operands { get; } = operands;

    /// <summary>Every register the block is assumed to change, in LLVM's spelling.</summary>
    public IReadOnlyList<string> Clobbers { get; } = clobbers;

    /// <summary>
    /// True when an operand was refused and left out, which is an error already
    /// reported. The flow analysis takes such a block to have written
    /// everything, so that one mistake is not also reported as an 'out' left
    /// unwritten.
    /// </summary>
    public bool IsIncomplete { get; init; }
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
/// One label of a switch section: <c>case pattern when guard:</c>. A constant
/// label is a pattern too, the one that asks for equality.
/// </summary>
public sealed class BoundSwitchLabel(SourceSpan span, BoundPattern pattern, BoundExpression? guard)
{
    public SourceSpan Span { get; } = span;
    public BoundPattern Pattern { get; } = pattern;

    /// <summary>The <c>when</c>, which reads what the pattern named.</summary>
    public BoundExpression? Guard { get; } = guard;
}

/// <summary>One section of a switch: the labels that reach it, and what it runs.</summary>
public sealed class BoundSwitchSection(
    SourceSpan span, IReadOnlyList<BoundSwitchLabel> labels, bool isDefault, BoundStatement body)
{
    public SourceSpan Span { get; } = span;
    public IReadOnlyList<BoundSwitchLabel> Labels { get; } = labels;
    public bool IsDefault { get; } = isDefault;
    public BoundStatement Body { get; } = body;

    /// <summary>
    /// Where a <c>goto case</c> or <c>goto default</c> lands, or null when
    /// nothing jumps to this section.
    /// </summary>
    public LabelSymbol? Entry { get; set; }
}

/// <summary>
/// A switch statement: one value, and sections reached by the patterns on
/// their labels, or by <c>default</c> where none matched.
///
/// Lowering decides how a section is reached -- one LLVM <c>switch</c> over
/// constants or a variant's tag where it can, a tree of tests where it cannot
/// -- and what <c>break</c> means inside one.
/// </summary>
public sealed class BoundSwitch(
    SourceSpan span, BoundExpression subject, BoundPlaceholder input,
    IReadOnlyList<BoundSwitchSection> sections)
    : BoundSemanticStatement(span)
{
    public BoundExpression Subject { get; } = subject;

    /// <summary>How every label's pattern names <see cref="Subject"/>.</summary>
    public BoundPlaceholder Input { get; } = input;

    public IReadOnlyList<BoundSwitchSection> Sections { get; } = sections;

    /// <summary>
    /// True when the sections between them cover every case of a variant, so
    /// nothing can fall past the switch even without a <c>default</c>. It is
    /// what lets a function end on one and still be seen to return.
    /// </summary>
    public bool IsExhaustive { get; init; }
}

/// <summary>One destination of a <see cref="BoundSwitchDispatch"/>.</summary>
/// <param name="Value">The folded constant, for a dispatch over an integer, a char, a bool or an enum.</param>
/// <param name="Case">The case, for a dispatch over a variant's tag.</param>
public sealed record BoundDispatchArm(ulong Value, VariantCaseSymbol? Case, LabelSymbol Target);

/// <summary>
/// A jump to one of several labels by a value: one LLVM <c>switch</c>, which
/// decides for itself whether a jump table beats comparisons. Lowering makes
/// it from a run of tests of one value against constants, or of one variant
/// against its cases; nothing is written as one.
/// </summary>
public sealed class BoundSwitchDispatch(
    SourceSpan span, BoundExpression value, IReadOnlyList<BoundDispatchArm> arms, LabelSymbol otherwise)
    : BoundStatement(span)
{
    /// <summary>The value, or the variant whose tag is asked.</summary>
    public BoundExpression Value { get; } = value;

    public IReadOnlyList<BoundDispatchArm> Arms { get; } = arms;

    /// <summary>Where a value no arm names goes.</summary>
    public LabelSymbol Default { get; } = otherwise;
}

public sealed class BoundReturn(SourceSpan span, BoundExpression? value) : BoundStatement(span)
{
    public BoundExpression? Value { get; } = value;
}

public sealed class BoundBreak(SourceSpan span) : BoundStatement(span);

public sealed class BoundContinue(SourceSpan span) : BoundStatement(span);

// ---------------------------------------------------------------- patterns

/// <summary>
/// A value a construct names before lowering decides what holds it: the
/// value a pattern is asked of, a loop's element, a receiver asked whether it
/// is there. Lowering puts in its place whatever holds that value where the
/// expression runs.
/// </summary>
public sealed class BoundPlaceholder(SourceSpan span, TypeSymbol type) : BoundExpression(span, type)
{
    /// <summary>
    /// Whether what stands for it is storage: a name for the value, or a read
    /// as steady as one. False where it is a value seen as another type.
    /// </summary>
    public bool IsStorage { get; init; } = true;

    public override bool IsLValue => IsStorage;
}

/// <summary>
/// A pattern: a question about a value, the values read from it to ask
/// further questions of, and the names it gives them. It says what matching
/// means and nothing about how, which is lowering's to decide.
/// </summary>
public abstract class BoundPattern(SourceSpan span)
{
    public SourceSpan Span { get; } = span;
}

/// <summary><c>_</c>, and anything that asks nothing.</summary>
public sealed class BoundDiscardPattern(SourceSpan span) : BoundPattern(span);

/// <summary><c>var x</c>, and the name after a type or a list: the value, under a name.</summary>
public sealed class BoundDeclarationPattern(SourceSpan span, LocalSymbol local, BoundExpression value)
    : BoundPattern(span)
{
    public LocalSymbol Local { get; } = local;

    /// <summary>What the name is given, read from the inputs around it.</summary>
    public BoundExpression Value { get; } = value;
}

/// <summary>What a test asks, where two tests can be told to ask the same thing.</summary>
public enum PatternTestKind
{
    /// <summary>Whether a variant holds a case. Two cases exclude each other.</summary>
    Case,

    /// <summary>Whether a value equals a constant. Two constants exclude each other.</summary>
    Constant,

    /// <summary>Whether a reference or an optional is null.</summary>
    Null,

    /// <summary>Whether an object is of a class or an interface.</summary>
    Type,
}

/// <param name="Value">
/// The case, the folded constant -- a <c>ulong</c>, or the text of a string --
/// or the type; null for <see cref="PatternTestKind.Null"/>.
/// </param>
/// <param name="Negated">True when the test is true where the question's answer is no.</param>
public sealed record PatternTestKey(PatternTestKind Kind, object? Value, bool Negated = false);

/// <summary>
/// <c>3</c>, <c>&gt; 0</c>, <c>null</c>, <c>Circle</c>, <c>Square</c>: a
/// question about <see cref="Input"/>, as a <c>bool</c> expression over it.
/// </summary>
public sealed class BoundTestPattern(
    SourceSpan span, BoundPlaceholder input, BoundExpression test, PatternTestKey? key)
    : BoundPattern(span)
{
    /// <summary>The value asked about.</summary>
    public BoundPlaceholder Input { get; } = input;

    public BoundExpression Test { get; } = test;

    /// <summary>What the test asks, or null for one no other test can be compared with.</summary>
    public PatternTestKey? Key { get; } = key;
}

/// <summary>
/// A value read from the inputs -- a field, a payload, a property, an
/// element, the object as the class it was found to be -- and the pattern it
/// has to match.
/// </summary>
public sealed class BoundReadPattern(
    SourceSpan span, BoundPlaceholder input, BoundExpression read, BoundPattern pattern)
    : BoundPattern(span)
{
    /// <summary>How <see cref="Pattern"/> names the value read.</summary>
    public BoundPlaceholder Input { get; } = input;

    public BoundExpression Read { get; } = read;
    public BoundPattern Pattern { get; } = pattern;
}

/// <summary>
/// Something done for what it leaves behind: the <c>Deconstruct</c> call a
/// positional pattern makes, whose <c>out</c> locals the positions then read.
/// </summary>
public sealed class BoundEffectPattern(SourceSpan span, BoundExpression effect) : BoundPattern(span)
{
    public BoundExpression Effect { get; } = effect;
}

/// <summary><c>p and q</c>, and the parts of a pattern that all have to match, in order.</summary>
public sealed class BoundAndPattern(SourceSpan span, IReadOnlyList<BoundPattern> parts)
    : BoundPattern(span)
{
    public IReadOnlyList<BoundPattern> Parts { get; } = parts;
}

/// <summary><c>p or q</c>.</summary>
public sealed class BoundOrPattern(SourceSpan span, BoundPattern left, BoundPattern right)
    : BoundPattern(span)
{
    public BoundPattern Left { get; } = left;
    public BoundPattern Right { get; } = right;
}

/// <summary><c>not p</c>.</summary>
public sealed class BoundNotPattern(SourceSpan span, BoundPattern operand) : BoundPattern(span)
{
    public BoundPattern Operand { get; } = operand;
}

/// <summary>A fully bound function ready for emission.</summary>
public sealed class BoundFunction(FunctionSymbol symbol, BoundBlock body)
{
    public FunctionSymbol Symbol { get; } = symbol;
    public BoundBlock Body { get; } = body;

    /// <summary>
    /// False when binding the body made nothing lowering takes away, so the
    /// body is already the core and lowering hands it on as it is.
    /// </summary>
    public bool NeedsLowering { get; init; } = true;
}
