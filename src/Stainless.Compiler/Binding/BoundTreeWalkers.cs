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

/// <summary>
/// Marks a property holding a node that is also reached through another child,
/// so a walk MUST NOT visit it a second time.
/// </summary>
[AttributeUsage(AttributeTargets.Property)]
public sealed class SharedSubtreeAttribute : Attribute;

/// <summary>
/// Visits a bound tree: every child of every node, each exactly once, in the
/// order it is evaluated.
///
/// A walk overrides <see cref="Visit(BoundExpression?)"/> or
/// <see cref="Visit(BoundStatement?)"/>, handles the nodes it is about, and
/// calls the base to go on into the children. <see cref="VisitChildren(BoundExpression)"/>
/// is the one place that knows what a node's children are, and it throws on a
/// node it does not know, so a new node kind cannot be skipped by accident.
/// A unit test holds every node type to it.
/// </summary>
public abstract class BoundTreeWalker
{
    public virtual void Visit(BoundStatement? statement)
    {
        if (statement is not null)
            VisitChildren(statement);
    }

    public virtual void Visit(BoundExpression? expression)
    {
        if (expression is not null)
            VisitChildren(expression);
    }

    public virtual void Visit(BoundPattern? pattern)
    {
        if (pattern is not null)
            VisitChildren(pattern);
    }

    protected void VisitAll(IReadOnlyList<BoundExpression> expressions)
    {
        foreach (var expression in expressions)
            Visit(expression);
    }

    public void VisitChildren(BoundStatement statement)
    {
        switch (statement)
        {
            case BoundBlock block:
                foreach (var inner in block.Statements)
                    Visit(inner);
                break;

            case BoundLocalDeclaration declaration:
                Visit(declaration.Initializer);
                break;

            case BoundExpressionStatement expression:
                Visit(expression.Expression);
                break;

            case BoundDeconstruct taken:
                foreach (var declaration in taken.Declarations)
                    Visit(declaration);
                Visit(taken.Expression);
                break;

            case BoundIf branch:
                Visit(branch.Condition);
                Visit(branch.Then);
                Visit(branch.Else);
                break;

            case BoundWhile loop:
                Visit(loop.Condition);
                Visit(loop.Body);
                break;

            case BoundDoWhile loop:
                Visit(loop.Body);
                Visit(loop.Condition);
                break;

            case BoundFor loop:
                Visit(loop.Initializer);
                Visit(loop.Condition);
                Visit(loop.Body);
                Visit(loop.Step);
                break;

            case BoundForEach loop:
                Visit(loop.Collection);
                Visit(loop.Value);
                Visit(loop.Deconstruction);
                Visit(loop.Body);
                break;

            case BoundSwitch chosen:
                Visit(chosen.Subject);
                foreach (var section in chosen.Sections)
                {
                    foreach (var label in section.Labels)
                    {
                        Visit(label.Pattern);
                        Visit(label.Guard);
                    }

                    Visit(section.Body);
                }
                break;

            case BoundSwitchDispatch dispatch:
                Visit(dispatch.Value);
                break;

            case BoundAsm assembly:
                foreach (var operand in assembly.Operands)
                    Visit(operand.Value);
                break;

            case BoundParallel parallel:
                Visit(parallel.Body);
                break;

            case BoundSpawn spawn:
                Visit(spawn.Target);
                Visit(spawn.Call);
                break;

            case BoundParallelFor loop:
                Visit(loop.Start);
                Visit(loop.Limit);
                Visit(loop.Stride);
                Visit(loop.Body);
                break;

            case BoundReturn returned:
                Visit(returned.Value);
                break;

            case BoundLabel or BoundGoto or BoundBreak or BoundContinue:
                break;

            default:
                throw Unknown(statement, statement.Span);
        }
    }

    public void VisitChildren(BoundExpression expression)
    {
        switch (expression)
        {
            case BoundErrorExpression or BoundLiteral or BoundStringLiteral or BoundUtf8Literal
                or BoundNullLiteral or BoundLocalAccess or BoundParameterAccess or BoundStaticAccess
                or BoundConstantAccess or BoundDefault or BoundSizeof or BoundAlignof or BoundOffsetof
                or BoundTypeof or BoundIidof or BoundEmbed or BoundThis or BoundFunctionReference
                or BoundUnmatchedSwitch or BoundOutDraft or BoundLambda or BoundPlaceholder:
                break;

            case BoundInterpolatedString interpolated: VisitAll(interpolated.Parts); break;
            case BoundFieldAccess field: Visit(field.Receiver); break;

            case BoundCall call:
                Visit(call.Receiver);
                VisitAll(call.Arguments);
                break;

            case BoundUnary unary: Visit(unary.Operand); break;

            case BoundBinary binary:
                Visit(binary.Left);
                Visit(binary.Right);
                break;

            case BoundIncrement stepped: Visit(stepped.Target); break;

            case BoundPropertyIncrement stepped:
                Visit(stepped.Receiver);
                VisitAll(stepped.Arguments);
                break;

            case BoundAssignment assignment:
                Visit(assignment.Target);
                Visit(assignment.Value);
                break;

            case BoundPropertyAssignment written:
                Visit(written.Receiver);
                VisitAll(written.Indices);
                Visit(written.Value);
                break;

            case BoundLet held:
                Visit(held.Value);
                Visit(held.Body);
                break;

            case BoundSequence sequence:
                VisitAll(sequence.Before);
                Visit(sequence.Value);
                break;

            case BoundObjectInitializer initialized:
                Visit(initialized.Creation);
                VisitAll(initialized.Writes);
                break;

            case BoundWith copied:
                Visit(copied.Target);
                foreach (var assignment in copied.Assignments)
                    Visit(assignment.Value);
                break;

            case BoundCompoundAssignment compound:
                Visit(compound.Target);
                Visit(compound.Combined);
                break;

            case BoundConditionalAccess asked:
                Visit(asked.Receiver);
                Visit(asked.Access);
                Visit(asked.WhenNothing);
                break;

            case BoundNullFallback fallback:
                Visit(fallback.Value);
                Visit(fallback.Fallback);
                break;

            case BoundConditional conditional:
                Visit(conditional.Condition);
                Visit(conditional.WhenTrue);
                Visit(conditional.WhenFalse);
                break;

            case BoundFunctionGroup group: Visit(group.Receiver); break;
            case BoundArrayDraft draft: VisitAll(draft.Elements); break;
            case BoundSpread spread: Visit(spread.Source); break;
            case BoundArrayLiteral literal: VisitAll(literal.Elements); break;

            case BoundCollection collection:
                VisitAll(collection.Parts);
                Visit(collection.Capacity);
                break;

            case BoundCollectionSpread spread:
                Visit(spread.Source);
                Visit(spread.Count);
                VisitAll(spread.Elements);
                break;

            case BoundTupleCreate tuple: VisitAll(tuple.Elements); break;
            case BoundTupleDraft tuple: VisitAll(tuple.Elements); break;
            case BoundVariantConstruction built: VisitAll(built.Arguments); break;
            case BoundVariantDraft built: VisitAll(built.Arguments); break;
            case BoundNewDraft created: VisitAll(created.Arguments); break;

            case BoundTry attempt:
                Visit(attempt.Operand);
                Visit(attempt.Test);
                Visit(attempt.OnFailure);
                Visit(attempt.OnSuccess);
                break;

            case BoundVariantTest test: Visit(test.Value); break;
            case BoundVariantPayload payload: Visit(payload.Receiver); break;

            case BoundClosure closure:
                foreach (var (_, value) in closure.Captures)
                    Visit(value);
                break;

            case BoundIndirectCall call:
                Visit(call.Target);
                VisitAll(call.Arguments);
                break;

            case BoundClosureCreate created: Visit(created.Receiver); break;

            case BoundClosureEqual same:
                Visit(same.Left);
                Visit(same.Right);
                break;

            case BoundClosureCall call:
                Visit(call.Target);
                VisitAll(call.Arguments);
                break;

            case BoundTypeTest test: Visit(test.Value); break;
            case BoundIsPattern matched:
                Visit(matched.Subject);
                Visit(matched.Pattern);
                break;

            case BoundSwitchExpression chosen:
                Visit(chosen.Subject);
                foreach (var arm in chosen.Arms)
                {
                    Visit(arm.Pattern);
                    Visit(arm.Guard);
                    Visit(arm.Value);
                }
                break;
            case BoundConversion conversion: Visit(conversion.Operand); break;
            case BoundNew created: VisitAll(created.Arguments); break;
            case BoundStructNew filled: VisitAll(filled.Arguments); break;
            case BoundDereference dereference: Visit(dereference.Operand); break;
            case BoundAddressOf address: Visit(address.Operand); break;
            case BoundNewArray array: Visit(array.Length); break;

            case BoundSlice slice:
                Visit(slice.Target);
                Visit(slice.Start);
                Visit(slice.End);
                break;

            case BoundArrayLength length: Visit(length.Array); break;

            case BoundIndex index:
                Visit(index.Target);
                Visit(index.Index);
                break;

            default:
                throw Unknown(expression, expression.Span);
        }
    }

    public void VisitChildren(BoundPattern pattern)
    {
        switch (pattern)
        {
            case BoundDiscardPattern:
                break;

            case BoundDeclarationPattern named: Visit(named.Value); break;
            case BoundTestPattern test: Visit(test.Test); break;

            case BoundReadPattern read:
                Visit(read.Read);
                Visit(read.Pattern);
                break;

            case BoundEffectPattern effect: Visit(effect.Effect); break;

            case BoundAndPattern both:
                foreach (var part in both.Parts)
                    Visit(part);
                break;

            case BoundOrPattern either:
                Visit(either.Left);
                Visit(either.Right);
                break;

            case BoundNotPattern negated: Visit(negated.Operand); break;

            default:
                throw Unknown(pattern, pattern.Span);
        }
    }

    private static InternalCompilerError Unknown(object node, SourceSpan span) =>
        new($"the bound tree walker has no case for {node.GetType().Name}", span);
}

/// <summary>Finds the statics an initializer reads, so they can be ordered first.</summary>
internal sealed class StaticReferenceWalker : BoundTreeWalker
{
    public HashSet<StaticSymbol> Found { get; } = [];

    public override void Visit(BoundExpression? expression)
    {
        switch (expression)
        {
            case BoundStaticAccess access:
                Found.Add(access.Static);
                break;

            // A static automatic property's getter reads its storage, so
            // reading the property is reading the static.
            case BoundCall { Function.Accessor.StaticBacking: { } storage }:
                Found.Add(storage);
                break;
        }

        base.Visit(expression);
    }
}

/// <summary>
/// Finds what a <c>for parallel</c> body reaches outside itself.
///
/// Anything declared within the body belongs to one iteration and is ignored.
/// Everything else is captured by address, so the chunks share the parent's
/// storage rather than a copy — which is the point for an array being written
/// through, and a race for a variable being assigned. Assignments are collected
/// separately so the binder can reject exactly those.
/// </summary>
internal sealed class CaptureWalker(LocalSymbol loopVariable) : BoundTreeWalker
{
    private readonly HashSet<object> _declared = [loopVariable];
    private readonly HashSet<object> _seen = [];
    private readonly List<object> _captures = [];

    public IReadOnlyList<object> Captures => _captures;

    public List<(object Symbol, SourceSpan Span, string Name)> Assignments { get; } = [];

    private void Capture(object symbol)
    {
        if (_declared.Contains(symbol) || !_seen.Add(symbol))
            return;
        _captures.Add(symbol);
    }

    private void Assigned(BoundExpression target)
    {
        switch (target)
        {
            case BoundLocalAccess local when !_declared.Contains(local.Local):
                Assignments.Add((local.Local, local.Span, local.Local.Name));
                break;

            case BoundParameterAccess parameter when !_declared.Contains(parameter.Parameter):
                Assignments.Add((parameter.Parameter, parameter.Span, parameter.Parameter.Name));
                break;
        }
    }

    public override void Visit(BoundStatement? statement)
    {
        switch (statement)
        {
            case BoundBlock block:
                _declared.UnionWith(block.Locals);
                break;

            case BoundLocalDeclaration declaration:
                _declared.Add(declaration.Local);
                break;

            case BoundFor loop:
                _declared.UnionWith(loop.Locals);
                break;

            case BoundForEach loop:
                _declared.Add(loop.Variable);
                break;

            case BoundParallelFor nested:
                _declared.Add(nested.Variable);
                break;

            // An output is an assignment to its place, and every chunk of a
            // `for parallel` storing into one outside variable is the race the
            // rule exists for.
            case BoundAsm assembly:
                foreach (var operand in assembly.Operands)
                    if (operand.IsOutput)
                        Assigned(operand.Value);
                break;
        }

        base.Visit(statement);
    }

    public override void Visit(BoundExpression? expression)
    {
        switch (expression)
        {
            case BoundLocalAccess local:
                Capture(local.Local);
                break;

            case BoundParameterAccess parameter:
                Capture(parameter.Parameter);
                break;

            case BoundThis self:
                Capture(self.Parameter);
                break;

            // A name a pattern declared belongs to the iteration that ran it.
            case BoundAssignment assignment:
                if (assignment.DeclaresLocal is { } declared)
                    _declared.Add(declared);
                Assigned(assignment.Target);
                break;

            case BoundIncrement stepped:
                Assigned(stepped.Target);
                break;

            case BoundCompoundAssignment { Property: null } compound:
                Assigned(compound.Target);
                break;

            // Held for the length of one expression, so it belongs to the
            // iteration that evaluates it.
            case BoundLet held:
                _declared.Add(held.Local);
                break;

            case BoundTry attempt:
                _declared.Add(attempt.Slot);
                break;

            case BoundAddressOf { DeclaresLocal: { } introduced }:
                _declared.Add(introduced);
                break;
        }

        base.Visit(expression);
    }

    // A name a pattern declared belongs to the iteration that matched it.
    public override void Visit(BoundPattern? pattern)
    {
        if (pattern is BoundDeclarationPattern named)
            _declared.Add(named.Local);

        base.Visit(pattern);
    }
}

/// <summary>
/// Whether evaluating a tree certainly writes a parameter — by assignment, or by
/// handing it on as somebody else's <c>out</c> — and each <c>try</c> that can
/// return before it has.
///
/// The walk is in evaluation order. What only some paths run — the arms of a
/// conditional, the right of <c>&amp;&amp;</c> and <c>||</c> — is looked into
/// for a <c>try</c>, and what it writes is forgotten again afterwards.
/// </summary>
internal sealed class OutWriteTracker(ParameterSymbol target, bool written) : BoundTreeWalker
{
    public bool Written { get; private set; } = written;

    public List<SourceSpan> EarlyReturns { get; } = [];

    public override void Visit(BoundExpression? expression)
    {
        switch (expression)
        {
            case BoundAssignment { Target: BoundParameterAccess assigned } assignment
                when ReferenceEquals(assigned.Parameter, target):
                Visit(assignment.Value);
                Written = true;
                return;

            case BoundCompoundAssignment { Target: BoundParameterAccess assigned, IsFallback: false } compound
                when ReferenceEquals(assigned.Parameter, target):
                Visit(compound.Combined);
                Written = true;
                return;

            // `Inner(out mine)` is a write, because Inner is held to the same
            // promise this function is.
            case BoundAddressOf { FromOutKeyword: true, Operand: BoundParameterAccess passed }
                when ReferenceEquals(passed.Parameter, target):
                Written = true;
                return;

            case BoundConditional conditional:
                Visit(conditional.Condition);
                Sometimes(conditional.WhenTrue);
                Sometimes(conditional.WhenFalse);
                return;

            case BoundBinary { Operator: BoundBinaryOp.LogicalAnd or BoundBinaryOp.LogicalOr } logical:
                Visit(logical.Left);
                Sometimes(logical.Right);
                return;

            // The failure is a return, taken once the operand has been
            // evaluated and before anything after it.
            case BoundTry attempt:
                Visit(attempt.Operand);
                if (!Written)
                    EarlyReturns.Add(attempt.Span);
                Visit(attempt.Test);
                Visit(attempt.OnSuccess);
                return;
        }

        base.Visit(expression);
    }

    private void Sometimes(BoundExpression expression)
    {
        bool before = Written;
        Visit(expression);
        Written = before;
    }
}

/// <summary>Every field a tree reads, through any receiver.</summary>
internal sealed class FieldReadCollector(HashSet<FieldSymbol> into) : BoundTreeWalker
{
    public override void Visit(BoundExpression? expression)
    {
        if (expression is BoundFieldAccess field)
            into.Add(field.Field);

        base.Visit(expression);
    }
}

/// <summary>
/// Whether a function holds somewhere a jump can land from after it: a label,
/// or a switch section a <c>goto case</c> names. A label lowering made is
/// reached only from before it, and does not count.
/// </summary>
internal sealed class LabelFinder : BoundTreeWalker
{
    public bool Found { get; private set; }

    public static bool Contains(BoundStatement statement)
    {
        var finder = new LabelFinder();
        finder.Visit(statement);
        return finder.Found;
    }

    public override void Visit(BoundStatement? statement)
    {
        if (Found)
            return;

        switch (statement)
        {
            case BoundLabel { Label.IsForwardOnly: false }:
            case BoundSwitch chosen when chosen.Sections.Any(s => s.Entry is not null):
                Found = true;
                return;
        }

        base.Visit(statement);
    }
}

/// <summary>
/// Whether a tree replaces what a local holds: assigns the whole of it, or
/// hands its address to something that may.
/// </summary>
internal sealed class LocalWriteFinder(LocalSymbol local) : BoundTreeWalker
{
    public bool Found { get; private set; }

    public static bool Writes(BoundExpression expression, LocalSymbol local)
    {
        var finder = new LocalWriteFinder(local);
        finder.Visit(expression);
        return finder.Found;
    }

    public override void Visit(BoundExpression? expression)
    {
        if (Found)
            return;

        switch (expression)
        {
            case BoundAssignment { Target: BoundLocalAccess written } when ReferenceEquals(written.Local, local):
            case BoundAddressOf { Operand: BoundLocalAccess lent } when ReferenceEquals(lent.Local, local):
                Found = true;
                return;
        }

        base.Visit(expression);
    }
}

/// <summary>How many times a tree names a local, reading or writing it.</summary>
internal sealed class LocalUseCounter(LocalSymbol local) : BoundTreeWalker
{
    public int Count { get; private set; }

    public static int Uses(BoundExpression expression, LocalSymbol local)
    {
        var counter = new LocalUseCounter(local);
        counter.Visit(expression);
        return counter.Count;
    }

    public override void Visit(BoundExpression? expression)
    {
        if (expression is BoundLocalAccess named && ReferenceEquals(named.Local, local))
            Count++;

        base.Visit(expression);
    }
}
