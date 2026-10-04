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
/// Rebuilds a bound tree: every child of every node, each exactly once, in the
/// order <see cref="BoundTreeWalker"/> visits them.
///
/// A rewrite overrides <see cref="Rewrite(BoundExpression)"/> or
/// <see cref="Rewrite(BoundStatement)"/>, replaces the nodes it is about, and
/// calls the base for the rest. <see cref="RewriteChildren(BoundExpression)"/>
/// is the one place that knows how to rebuild a node around new children, and
/// it throws on a node it does not know. A node none of whose children changed
/// is handed back as it was, so a tree a rewrite has nothing to say about is
/// not copied. A unit test holds every node type to it, and holds every other
/// property to surviving the rebuild.
/// </summary>
public abstract class BoundTreeRewriter
{
    public virtual BoundStatement Rewrite(BoundStatement statement) => RewriteChildren(statement);

    public virtual BoundExpression Rewrite(BoundExpression expression) => RewriteChildren(expression);

    public virtual BoundPattern Rewrite(BoundPattern pattern) => RewriteChildren(pattern);

    protected BoundStatement? RewriteOptional(BoundStatement? statement) =>
        statement is null ? null : Rewrite(statement);

    protected BoundExpression? RewriteOptional(BoundExpression? expression) =>
        expression is null ? null : Rewrite(expression);

    /// <summary>Every expression in a list; the list itself when none changed.</summary>
    protected IReadOnlyList<BoundExpression> RewriteAll(IReadOnlyList<BoundExpression> expressions)
    {
        List<BoundExpression>? rebuilt = null;

        for (int i = 0; i < expressions.Count; i++)
        {
            var rewritten = Rewrite(expressions[i]);
            if (rebuilt is null && !ReferenceEquals(rewritten, expressions[i]))
                rebuilt = [.. expressions.Take(i)];
            rebuilt?.Add(rewritten);
        }

        return rebuilt ?? expressions;
    }

    /// <inheritdoc cref="RewriteAll(IReadOnlyList{BoundExpression})"/>
    protected IReadOnlyList<BoundStatement> RewriteAll(IReadOnlyList<BoundStatement> statements)
    {
        List<BoundStatement>? rebuilt = null;

        for (int i = 0; i < statements.Count; i++)
        {
            var rewritten = Rewrite(statements[i]);
            if (rebuilt is null && !ReferenceEquals(rewritten, statements[i]))
                rebuilt = [.. statements.Take(i)];
            rebuilt?.Add(rewritten);
        }

        return rebuilt ?? statements;
    }

    private IReadOnlyList<BoundPattern> RewriteAll(IReadOnlyList<BoundPattern> patterns)
    {
        List<BoundPattern>? rebuilt = null;

        for (int i = 0; i < patterns.Count; i++)
        {
            var rewritten = Rewrite(patterns[i]);
            if (rebuilt is null && !ReferenceEquals(rewritten, patterns[i]))
                rebuilt = [.. patterns.Take(i)];
            rebuilt?.Add(rewritten);
        }

        return rebuilt ?? patterns;
    }

    private static bool Same<T>(T before, T after) where T : class? => ReferenceEquals(before, after);

    /// <summary>A deconstruction's receivers and indices, in the order <see cref="BoundTreeWalker"/> visits them.</summary>
    private BoundDeconstructionTarget RewriteTargets(BoundDeconstructionTarget target)
    {
        var place = RewriteOptional(target.Place);
        var receiver = RewriteOptional(target.Receiver);
        var indices = RewriteAll(target.Indices);
        var elements = RewriteElements(target.Elements, RewriteTargets);

        return Same(target.Place, place) && Same(target.Receiver, receiver) && Same(target.Indices, indices) &&
               Same(target.Elements, elements)
            ? target
            : target with { Place = place, Receiver = receiver, Indices = indices, Elements = elements };
    }

    /// <summary>A deconstruction's values, after its targets.</summary>
    private BoundDeconstructionTarget RewriteValues(BoundDeconstructionTarget target)
    {
        var value = RewriteOptional(target.Value);
        var elements = RewriteElements(target.Elements, RewriteValues);

        return Same(target.Value, value) && Same(target.Elements, elements)
            ? target
            : target with { Value = value, Elements = elements };
    }

    private static IReadOnlyList<BoundDeconstructionTarget> RewriteElements(
        IReadOnlyList<BoundDeconstructionTarget> elements,
        Func<BoundDeconstructionTarget, BoundDeconstructionTarget> rewrite)
    {
        List<BoundDeconstructionTarget>? rebuilt = null;
        for (int i = 0; i < elements.Count; i++)
        {
            var rewritten = rewrite(elements[i]);
            if (rebuilt is null && !ReferenceEquals(rewritten, elements[i]))
                rebuilt = [.. elements.Take(i)];
            rebuilt?.Add(rewritten);
        }

        return rebuilt ?? elements;
    }

    private static bool Same<T>(IReadOnlyList<T> before, IReadOnlyList<T> after) =>
        ReferenceEquals(before, after);

    // ------------------------------------------------------------ statements

    public BoundStatement RewriteChildren(BoundStatement statement)
    {
        switch (statement)
        {
            case BoundBlock block:
            {
                var statements = RewriteAll(block.Statements);
                if (Same(block.Statements, statements))
                    return block;

                var rebuilt = new BoundBlock(block.Span, statements);
                rebuilt.Locals.AddRange(block.Locals);
                return rebuilt;
            }

            case BoundLocalDeclaration declaration:
            {
                var initializer = RewriteOptional(declaration.Initializer);
                return Same(declaration.Initializer, initializer)
                    ? declaration
                    : new BoundLocalDeclaration(declaration.Span, declaration.Local, initializer)
                    {
                        IsBorrowed = declaration.IsBorrowed,
                    };
            }

            case BoundExpressionStatement expression:
            {
                var rewritten = Rewrite(expression.Expression);
                return Same(expression.Expression, rewritten)
                    ? expression
                    : new BoundExpressionStatement(expression.Span, rewritten);
            }

            case BoundDeconstruct taken:
            {
                var declarations = new List<BoundLocalDeclaration>();
                bool changed = false;
                foreach (var declaration in taken.Declarations)
                {
                    var rewritten = Rewrite(declaration) as BoundLocalDeclaration
                        ?? throw Unexpected(declaration, "a local declaration");
                    changed |= !Same(declaration, rewritten);
                    declarations.Add(rewritten);
                }

                var expression = Rewrite(taken.Expression);
                return !changed && Same(taken.Expression, expression)
                    ? taken
                    : new BoundDeconstruct(taken.Span, declarations, expression);
            }

            case BoundIf branch:
            {
                var condition = Rewrite(branch.Condition);
                var then = Rewrite(branch.Then);
                var otherwise = RewriteOptional(branch.Else);
                return Same(branch.Condition, condition) && Same(branch.Then, then) &&
                       Same(branch.Else, otherwise)
                    ? branch
                    : new BoundIf(branch.Span, condition, then, otherwise);
            }

            case BoundWhile loop:
            {
                var condition = Rewrite(loop.Condition);
                var body = Rewrite(loop.Body);
                return Same(loop.Condition, condition) && Same(loop.Body, body)
                    ? loop
                    : new BoundWhile(loop.Span, condition, body);
            }

            case BoundDoWhile loop:
            {
                var body = Rewrite(loop.Body);
                var condition = Rewrite(loop.Condition);
                return Same(loop.Body, body) && Same(loop.Condition, condition)
                    ? loop
                    : new BoundDoWhile(loop.Span, body, condition);
            }

            case BoundFor loop:
            {
                var initializer = RewriteOptional(loop.Initializer);
                var condition = RewriteOptional(loop.Condition);
                var body = Rewrite(loop.Body);
                var step = RewriteOptional(loop.Step);
                if (Same(loop.Initializer, initializer) && Same(loop.Condition, condition) &&
                    Same(loop.Body, body) && Same(loop.Step, step))
                    return loop;

                var rebuilt = new BoundFor(loop.Span, initializer, condition, step, body);
                rebuilt.Locals.AddRange(loop.Locals);
                return rebuilt;
            }

            case BoundForEach loop:
            {
                var collection = Rewrite(loop.Collection);
                var value = Rewrite(loop.Value);
                var deconstruction = RewriteOptional(loop.Deconstruction);
                var body = Rewrite(loop.Body);
                return Same(loop.Collection, collection) && Same(loop.Value, value) &&
                       Same(loop.Deconstruction, deconstruction) && Same(loop.Body, body)
                    ? loop
                    : new BoundForEach(loop.Span, collection, loop.Variable, loop.Element, value,
                        deconstruction, body)
                    {
                        GetEnumerator = loop.GetEnumerator,
                        MoveNext = loop.MoveNext,
                        Current = loop.Current,
                    };
            }

            case BoundSwitch chosen:
            {
                var subject = Rewrite(chosen.Subject);
                var sections = new List<BoundSwitchSection>();
                bool changed = !Same(chosen.Subject, subject);

                foreach (var section in chosen.Sections)
                {
                    var labels = new List<BoundSwitchLabel>();
                    bool labelsChanged = false;

                    foreach (var label in section.Labels)
                    {
                        var pattern = Rewrite(label.Pattern);
                        var guard = RewriteOptional(label.Guard);
                        bool same = Same(label.Pattern, pattern) && Same(label.Guard, guard);
                        labelsChanged |= !same;
                        labels.Add(same ? label : new BoundSwitchLabel(label.Span, pattern, guard));
                    }

                    var body = Rewrite(section.Body);
                    if (!labelsChanged && Same(section.Body, body))
                    {
                        sections.Add(section);
                        continue;
                    }

                    changed = true;
                    sections.Add(new BoundSwitchSection(section.Span, labels, section.IsDefault, body)
                    {
                        Entry = section.Entry,
                    });
                }

                return changed
                    ? new BoundSwitch(chosen.Span, subject, chosen.Input, sections)
                    {
                        IsExhaustive = chosen.IsExhaustive,
                    }
                    : chosen;
            }

            case BoundSwitchDispatch dispatch:
            {
                var value = Rewrite(dispatch.Value);
                return Same(dispatch.Value, value)
                    ? dispatch
                    : new BoundSwitchDispatch(dispatch.Span, value, dispatch.Arms, dispatch.Default);
            }

            case BoundAsm assembly:
            {
                var operands = new List<BoundAsmOperand>();
                bool changed = false;
                foreach (var operand in assembly.Operands)
                {
                    var value = Rewrite(operand.Value);
                    if (Same(operand.Value, value))
                    {
                        operands.Add(operand);
                        continue;
                    }

                    changed = true;
                    operands.Add(new BoundAsmOperand(
                        operand.Span, operand.Direction, operand.Register, operand.Constraint, value));
                }

                return changed
                    ? new BoundAsm(assembly.Span, assembly.Text, assembly.TextSpan, operands, assembly.Clobbers)
                    {
                        IsIncomplete = assembly.IsIncomplete,
                    }
                    : assembly;
            }

            case BoundParallel parallel:
            {
                var body = Rewrite(parallel.Body);
                return Same(parallel.Body, body) ? parallel : new BoundParallel(parallel.Span, body);
            }

            case BoundSpawn spawn:
            {
                var target = RewriteOptional(spawn.Target);
                var call = Rewrite(spawn.Call) as BoundCall ?? throw Unexpected(spawn.Call, "a call");
                return Same(spawn.Target, target) && Same(spawn.Call, call)
                    ? spawn
                    : new BoundSpawn(spawn.Span, target, call);
            }

            case BoundParallelFor loop:
            {
                var start = Rewrite(loop.Start);
                var limit = Rewrite(loop.Limit);
                var stride = Rewrite(loop.Stride);
                var body = Rewrite(loop.Body);
                return Same(loop.Start, start) && Same(loop.Limit, limit) &&
                       Same(loop.Stride, stride) && Same(loop.Body, body)
                    ? loop
                    : new BoundParallelFor(loop.Span, loop.Variable, start, limit, stride,
                        loop.Inclusive, body, loop.Captures);
            }

            case BoundReturn returned:
            {
                var value = RewriteOptional(returned.Value);
                return Same(returned.Value, value) ? returned : new BoundReturn(returned.Span, value);
            }

            case BoundLabel or BoundGoto or BoundBreak or BoundContinue:
                return statement;

            default:
                throw Unknown(statement, statement.Span);
        }
    }

    // ------------------------------------------------------------ expressions

    public BoundExpression RewriteChildren(BoundExpression expression)
    {
        switch (expression)
        {
            case BoundErrorExpression or BoundLiteral or BoundStringLiteral or BoundUtf8Literal
                or BoundNullLiteral or BoundLocalAccess or BoundParameterAccess or BoundStaticAccess
                or BoundConstantAccess or BoundDefault or BoundSizeof or BoundAlignof or BoundOffsetof
                or BoundTypeof or BoundIidof or BoundEmbed or BoundThis or BoundFunctionReference
                or BoundUnmatchedSwitch or BoundOutDraft or BoundLambda or BoundPlaceholder:
                return expression;

            // The commonest nodes first: a switch over types asks them in order.
            case BoundCall call:
            {
                var receiver = RewriteOptional(call.Receiver);
                var arguments = RewriteAll(call.Arguments);
                return Same(call.Receiver, receiver) && Same(call.Arguments, arguments)
                    ? call
                    : new BoundCall(call.Span, call.Function, receiver, arguments)
                    {
                        IsNonVirtual = call.IsNonVirtual,
                        EvaluationOrder = call.EvaluationOrder,
                        ClassReceiver = call.ClassReceiver,
                    };
            }

            case BoundFieldAccess field:
            {
                var receiver = RewriteOptional(field.Receiver);
                return Same(field.Receiver, receiver)
                    ? field
                    : new BoundFieldAccess(field.Span, receiver, field.Field);
            }

            case BoundConversion conversion:
            {
                var operand = Rewrite(conversion.Operand);
                return Same(conversion.Operand, operand)
                    ? conversion
                    : new BoundConversion(conversion.Span, conversion.Type, operand, conversion.Kind)
                    {
                        IsChecked = conversion.IsChecked,
                    };
            }

            case BoundBinary binary:
            {
                var left = Rewrite(binary.Left);
                var right = Rewrite(binary.Right);
                return Same(binary.Left, left) && Same(binary.Right, right)
                    ? binary
                    : new BoundBinary(binary.Span, binary.Type, left, binary.Operator, right)
                    {
                        IsChecked = binary.IsChecked,
                    };
            }

            case BoundAssignment assignment:
            {
                var target = Rewrite(assignment.Target);
                var value = Rewrite(assignment.Value);
                return Same(assignment.Target, target) && Same(assignment.Value, value)
                    ? assignment
                    : new BoundAssignment(assignment.Span, target, value)
                    {
                        DeclaresLocal = assignment.DeclaresLocal,
                        IsInitialization = assignment.IsInitialization,
                    };
            }

            case BoundUnary unary:
            {
                var operand = Rewrite(unary.Operand);
                return Same(unary.Operand, operand)
                    ? unary
                    : new BoundUnary(unary.Span, unary.Type, unary.Operator, operand)
                    {
                        IsChecked = unary.IsChecked,
                    };
            }

            case BoundIndex index:
            {
                var target = Rewrite(index.Target);
                var position = Rewrite(index.Index);
                return Same(index.Target, target) && Same(index.Index, position)
                    ? index
                    : new BoundIndex(index.Span, index.Type, target, position) { Origin = index.Origin };
            }

            case BoundLet held:
            {
                var value = Rewrite(held.Value);
                var body = Rewrite(held.Body);
                return Same(held.Value, value) && Same(held.Body, body)
                    ? held
                    : new BoundLet(held.Span, held.Local, value, body) { IsOwned = held.IsOwned };
            }

            case BoundSequence sequence:
            {
                var before = RewriteAll(sequence.Before);
                var value = Rewrite(sequence.Value);
                return Same(sequence.Before, before) && Same(sequence.Value, value)
                    ? sequence
                    : new BoundSequence(sequence.Span, before, value);
            }

            case BoundConditional conditional:
            {
                var condition = Rewrite(conditional.Condition);
                var whenTrue = Rewrite(conditional.WhenTrue);
                var whenFalse = Rewrite(conditional.WhenFalse);
                return Same(conditional.Condition, condition) && Same(conditional.WhenTrue, whenTrue) &&
                       Same(conditional.WhenFalse, whenFalse)
                    ? conditional
                    : new BoundConditional(conditional.Span, conditional.Type, condition, whenTrue, whenFalse);
            }

            case BoundAddressOf address:
            {
                var operand = Rewrite(address.Operand);
                return Same(address.Operand, operand)
                    ? address
                    : new BoundAddressOf(address.Span, address.Type, operand)
                    {
                        FromRefKeyword = address.FromRefKeyword,
                        FromOutKeyword = address.FromOutKeyword,
                        DeclaresLocal = address.DeclaresLocal,
                    };
            }

            case BoundArrayLength length:
            {
                var array = Rewrite(length.Array);
                return Same(length.Array, array)
                    ? length
                    : new BoundArrayLength(length.Span, length.Type, array);
            }

            case BoundInterpolatedString interpolated:
            {
                var parts = RewriteAll(interpolated.Parts);
                return Same(interpolated.Parts, parts)
                    ? interpolated
                    : new BoundInterpolatedString(interpolated.Span, interpolated.Type, parts);
            }

            case BoundIncrement stepped:
            {
                var target = Rewrite(stepped.Target);
                return Same(stepped.Target, target)
                    ? stepped
                    : new BoundIncrement(stepped.Span, target, stepped.IsPrefix, stepped.IsIncrement)
                    {
                        IsChecked = stepped.IsChecked,
                    };
            }

            case BoundPropertyIncrement stepped:
            {
                var receiver = RewriteOptional(stepped.Receiver);
                var arguments = RewriteAll(stepped.Arguments);
                return Same(stepped.Receiver, receiver) && Same(stepped.Arguments, arguments)
                    ? stepped
                    : new BoundPropertyIncrement(stepped.Span, receiver, stepped.Property,
                        stepped.IsPrefix, stepped.IsIncrement, arguments)
                    {
                        IsChecked = stepped.IsChecked,
                    };
            }

            case BoundPropertyAssignment written:
            {
                var receiver = RewriteOptional(written.Receiver);
                var indices = RewriteAll(written.Indices);
                var value = Rewrite(written.Value);
                return Same(written.Receiver, receiver) && Same(written.Indices, indices) &&
                       Same(written.Value, value)
                    ? written
                    : new BoundPropertyAssignment(written.Span, receiver, written.Property, value)
                    {
                        IsNonVirtual = written.IsNonVirtual,
                        Indices = indices,
                        HoldsReceiver = written.HoldsReceiver,
                    };
            }

            case BoundRangeSlice sliced:
            {
                var target = RewriteOptional(sliced.Target);
                var length = RewriteOptional(sliced.Length);
                var range = RewriteOptional(sliced.Range);
                var start = RewriteOptional(sliced.Start);
                var access = Rewrite(sliced.Access);
                return Same(sliced.Target, target) && Same(sliced.Length, length) && Same(sliced.Range, range) &&
                       Same(sliced.Start, start) && Same(sliced.Access, access)
                    ? sliced
                    : new BoundRangeSlice(sliced.Span, sliced.Type, access)
                    {
                        Target = target,
                        Receiver = sliced.Receiver,
                        Length = length,
                        Counted = sliced.Counted,
                        Range = range,
                        Whole = sliced.Whole,
                        Start = start,
                        From = sliced.From,
                    };
            }

            case BoundNamedValue named:
            {
                var value = Rewrite(named.Value);
                return Same(named.Value, value) ? named : new BoundNamedValue(named.Span, value, named.Name);
            }

            case BoundDeconstruction taken:
            {
                var target = RewriteValues(RewriteTargets(taken.Target));
                return Same(taken.Target, target)
                    ? taken
                    : new BoundDeconstruction(taken.Span, taken.Type, target, taken.IsValue);
            }

            case BoundMemberAssignment assignment:
            {
                var target = Rewrite(assignment.Target);
                var value = Rewrite(assignment.Value);
                return Same(assignment.Target, target) && Same(assignment.Value, value)
                    ? assignment
                    : new BoundMemberAssignment(assignment.Span, target, value);
            }

            case BoundAs asked:
            {
                var value = Rewrite(asked.Value);
                return Same(asked.Value, value) ? asked : new BoundAs(asked.Span, asked.Type, value, asked.Wanted);
            }

            case BoundObjectInitializer initialized:
            {
                var creation = Rewrite(initialized.Creation);
                var writes = RewriteAll(initialized.Writes);
                return Same(initialized.Creation, creation) && Same(initialized.Writes, writes)
                    ? initialized
                    : new BoundObjectInitializer(initialized.Span, initialized.Type, creation,
                        initialized.Made, writes);
            }

            case BoundWith copied:
            {
                var target = Rewrite(copied.Target);
                var assignments = new List<BoundWithAssignment>();
                bool changed = !Same(copied.Target, target);
                foreach (var assignment in copied.Assignments)
                {
                    var value = Rewrite(assignment.Value);
                    if (Same(assignment.Value, value))
                    {
                        assignments.Add(assignment);
                        continue;
                    }

                    changed = true;
                    assignments.Add(new BoundWithAssignment(assignment.Span, assignment.Property, value));
                }

                return changed
                    ? new BoundWith(copied.Span, copied.Record, target, copied.Clone, assignments)
                    : copied;
            }

            case BoundCompoundAssignment compound:
            {
                var target = Rewrite(compound.Target);
                var combined = Rewrite(compound.Combined);
                return Same(compound.Target, target) && Same(compound.Combined, combined)
                    ? compound
                    : new BoundCompoundAssignment(compound.Span, compound.Type, target, compound.Current,
                        compound.Value, combined, compound.IsFallback)
                    {
                        Property = compound.Property,
                    };
            }

            case BoundConditionalAccess asked:
            {
                var receiver = Rewrite(asked.Receiver);
                var access = Rewrite(asked.Access);
                var whenNothing = Rewrite(asked.WhenNothing);
                return Same(asked.Receiver, receiver) && Same(asked.Access, access) &&
                       Same(asked.WhenNothing, whenNothing)
                    ? asked
                    : new BoundConditionalAccess(asked.Span, asked.Type, receiver, asked.Present, access, whenNothing);
            }

            case BoundNullFallback fallback:
            {
                var value = Rewrite(fallback.Value);
                var otherwise = Rewrite(fallback.Fallback);
                return Same(fallback.Value, value) && Same(fallback.Fallback, otherwise)
                    ? fallback
                    : new BoundNullFallback(fallback.Span, fallback.Type, value, otherwise);
            }

            case BoundFunctionGroup group:
            {
                var receiver = RewriteOptional(group.Receiver);
                return Same(group.Receiver, receiver)
                    ? group
                    : new BoundFunctionGroup(group.Span, group.Type, group.Name, group.Candidates)
                    {
                        Receiver = receiver,
                    };
            }

            case BoundArrayDraft draft:
            {
                var elements = RewriteAll(draft.Elements);
                return Same(draft.Elements, elements)
                    ? draft
                    : new BoundArrayDraft(draft.Span, draft.Type, elements);
            }

            case BoundSpread spread:
            {
                var source = Rewrite(spread.Source);
                return Same(spread.Source, source)
                    ? spread
                    : new BoundSpread(spread.Span, spread.Type, source);
            }

            case BoundArrayLiteral literal:
            {
                var elements = RewriteAll(literal.Elements);
                return Same(literal.Elements, elements)
                    ? literal
                    : new BoundArrayLiteral(literal.Span, literal.Type, literal.ElementType, elements)
                    {
                        OnStack = literal.OnStack,
                    };
            }

            case BoundParamsArray gathered:
            {
                var elements = RewriteAll(gathered.Elements);
                return Same(gathered.Elements, elements)
                    ? gathered
                    : new BoundParamsArray(gathered.Span, gathered.Type, gathered.Array, elements)
                    {
                        InFrame = gathered.InFrame,
                    };
            }

            case BoundCollection collection:
            {
                var parts = RewriteAll(collection.Parts);
                var capacity = RewriteOptional(collection.Capacity);
                return Same(collection.Parts, parts) && Same(collection.Capacity, capacity)
                    ? collection
                    : new BoundCollection(collection.Span, collection.Type, collection.ElementType,
                        collection.Form, parts)
                    {
                        Builder = collection.Builder,
                        Constructor = collection.Constructor,
                        Add = collection.Add,
                        Finish = collection.Finish,
                        Total = collection.Total,
                        Capacity = capacity,
                    };
            }

            case BoundCollectionSpread spread:
            {
                var source = Rewrite(spread.Source);
                var count = RewriteOptional(spread.Count);
                var elements = RewriteAll(spread.Elements);
                return Same(spread.Source, source) && Same(spread.Count, count) && Same(spread.Elements, elements)
                    ? spread
                    : new BoundCollectionSpread(spread.Span, spread.Type, source, spread.Walked)
                    {
                        Count = count,
                        Walk = spread.Walk,
                        Elements = elements,
                    };
            }

            case BoundTupleCreate tuple:
            {
                var elements = RewriteAll(tuple.Elements);
                return Same(tuple.Elements, elements)
                    ? tuple
                    : new BoundTupleCreate(tuple.Span, tuple.Tuple, elements);
            }

            case BoundVectorNew made:
            {
                var parts = RewriteAll(made.Parts);
                return Same(made.Parts, parts) ? made : new BoundVectorNew(made.Span, made.Vector, parts);
            }

            case BoundVaStart started:
                return started;

            case BoundVaArg read:
            {
                var list = Rewrite(read.List);
                return Same(read.List, list) ? read : new BoundVaArg(read.Span, read.Type, list);
            }

            case BoundVectorFunction called:
            {
                var arguments = RewriteAll(called.Arguments);
                return Same(called.Arguments, arguments)
                    ? called
                    : new BoundVectorFunction(called.Span, called.Type, called.Function, called.Vector, arguments);
            }

            case BoundVectorShuffle shuffle:
            {
                var vector = Rewrite(shuffle.Vector);
                return Same(shuffle.Vector, vector)
                    ? shuffle
                    : new BoundVectorShuffle(shuffle.Span, (VectorTypeSymbol)shuffle.Type, vector, shuffle.Lanes);
            }

            case BoundSwizzleAssignment written:
            {
                var target = (BoundVectorShuffle)Rewrite(written.Target);
                var value = Rewrite(written.Value);
                return Same(written.Target, target) && Same(written.Value, value)
                    ? written
                    : new BoundSwizzleAssignment(written.Span, target, value);
            }

            case BoundTupleDraft tuple:
            {
                var elements = RewriteAll(tuple.Elements);
                return Same(tuple.Elements, elements) ? tuple : new BoundTupleDraft(tuple.Span, elements);
            }

            case BoundVariantConstruction built:
            {
                var arguments = RewriteAll(built.Arguments);
                return Same(built.Arguments, arguments)
                    ? built
                    : new BoundVariantConstruction(built.Span, built.Type, built.Case, arguments);
            }

            case BoundVariantDraft built:
            {
                var arguments = RewriteAll(built.Arguments);
                return Same(built.Arguments, arguments)
                    ? built
                    : new BoundVariantDraft(built.Span, built.Case, arguments);
            }

            case BoundNewDraft created:
            {
                var arguments = RewriteAll(created.Arguments);
                return Same(created.Arguments, arguments)
                    ? created
                    : new BoundNewDraft(created.Span, created.Syntax, [.. arguments]);
            }

            case BoundTry attempt:
            {
                var operand = Rewrite(attempt.Operand);
                var test = Rewrite(attempt.Test);
                var onFailure = Rewrite(attempt.OnFailure);
                var onSuccess = Rewrite(attempt.OnSuccess);
                return Same(attempt.Operand, operand) && Same(attempt.Test, test) &&
                       Same(attempt.OnFailure, onFailure) && Same(attempt.OnSuccess, onSuccess)
                    ? attempt
                    : new BoundTry(attempt.Span, attempt.Type, attempt.Slot, operand, test, onFailure, onSuccess);
            }

            case BoundVariantTest test:
            {
                var value = Rewrite(test.Value);
                return Same(test.Value, value)
                    ? test
                    : new BoundVariantTest(test.Span, test.Type, value, test.Case);
            }

            case BoundSlotValue read:
            {
                var receiver = Rewrite(read.Receiver);
                return Same(read.Receiver, receiver)
                    ? read
                    : new BoundSlotValue(read.Span, read.Slot, receiver);
            }

            case BoundSlotFill fill:
            {
                var value = Rewrite(fill.Value);
                return Same(fill.Value, value)
                    ? fill
                    : new BoundSlotFill(fill.Span, fill.Slot, value);
            }

            case BoundVariantPayload payload:
            {
                var receiver = Rewrite(payload.Receiver);
                return Same(payload.Receiver, receiver)
                    ? payload
                    : new BoundVariantPayload(payload.Span, receiver, payload.Case, payload.Field);
            }

            case BoundClosure closure:
            {
                var captures = new List<(FieldSymbol Field, BoundExpression Value)>();
                bool changed = false;
                foreach (var (field, value) in closure.Captures)
                {
                    var rewritten = Rewrite(value);
                    changed |= !Same(value, rewritten);
                    captures.Add((field, rewritten));
                }

                return changed
                    ? new BoundClosure(closure.Span, closure.Type, closure.ClosureType, captures)
                    : closure;
            }

            case BoundIndirectCall call:
            {
                var target = Rewrite(call.Target);
                var arguments = RewriteAll(call.Arguments);
                return Same(call.Target, target) && Same(call.Arguments, arguments)
                    ? call
                    : new BoundIndirectCall(call.Span, call.DelegateType, target, arguments)
                    {
                        EvaluationOrder = call.EvaluationOrder,
                    };
            }

            case BoundClosureCreate created:
            {
                var receiver = RewriteOptional(created.Receiver);
                return Same(created.Receiver, receiver)
                    ? created
                    : new BoundClosureCreate(created.Span, created.ClosureType, created.Function, receiver);
            }

            case BoundClosureEqual same:
            {
                var left = Rewrite(same.Left);
                var right = Rewrite(same.Right);
                return Same(same.Left, left) && Same(same.Right, right)
                    ? same
                    : new BoundClosureEqual(same.Span, same.ClosureType, left, right, same.Negated);
            }

            case BoundClosureCall call:
            {
                var target = Rewrite(call.Target);
                var arguments = RewriteAll(call.Arguments);
                return Same(call.Target, target) && Same(call.Arguments, arguments)
                    ? call
                    : new BoundClosureCall(call.Span, call.ClosureType, target, arguments)
                    {
                        EvaluationOrder = call.EvaluationOrder,
                    };
            }

            case BoundTypeTest test:
            {
                var value = Rewrite(test.Value);
                return Same(test.Value, value)
                    ? test
                    : new BoundTypeTest(test.Span, test.Type, value, test.Tested);
            }

            case BoundIsPattern matched:
            {
                var subject = Rewrite(matched.Subject);
                var pattern = Rewrite(matched.Pattern);
                return Same(matched.Subject, subject) && Same(matched.Pattern, pattern)
                    ? matched
                    : new BoundIsPattern(matched.Span, subject, matched.Input, pattern)
                    {
                        AssignedWhenTrue = matched.AssignedWhenTrue,
                        AssignedWhenFalse = matched.AssignedWhenFalse,
                        CaseWhenTrue = matched.CaseWhenTrue,
                        CaseWhenFalse = matched.CaseWhenFalse,
                        NotNullWhenTrue = matched.NotNullWhenTrue,
                        NotNullWhenFalse = matched.NotNullWhenFalse,
                        BindsAtOnce = matched.BindsAtOnce,
                    };
            }

            case BoundSwitchExpression chosen:
            {
                var subject = Rewrite(chosen.Subject);
                var arms = new List<BoundSwitchArm>();
                bool changed = !Same(chosen.Subject, subject);

                foreach (var arm in chosen.Arms)
                {
                    var pattern = Rewrite(arm.Pattern);
                    var guard = RewriteOptional(arm.Guard);
                    var value = Rewrite(arm.Value);
                    if (Same(arm.Pattern, pattern) && Same(arm.Guard, guard) && Same(arm.Value, value))
                    {
                        arms.Add(arm);
                        continue;
                    }

                    changed = true;
                    arms.Add(new BoundSwitchArm(arm.Span, pattern, guard, value));
                }

                return changed
                    ? new BoundSwitchExpression(chosen.Span, chosen.Type, subject, chosen.Input, arms)
                    {
                        IsTotal = chosen.IsTotal,
                    }
                    : chosen;
            }

            case BoundNew created:
            {
                var arguments = RewriteAll(created.Arguments);
                return Same(created.Arguments, arguments)
                    ? created
                    : new BoundNew(created.Span, created.ClassType, created.Constructor, arguments)
                    {
                        EvaluationOrder = created.EvaluationOrder,
                    };
            }

            case BoundStructNew filled:
            {
                var arguments = RewriteAll(filled.Arguments);
                return Same(filled.Arguments, arguments)
                    ? filled
                    : new BoundStructNew(filled.Span, filled.StructType, filled.Constructor, arguments)
                    {
                        EvaluationOrder = filled.EvaluationOrder,
                    };
            }

            case BoundDereference dereference:
            {
                var operand = Rewrite(dereference.Operand);
                return Same(dereference.Operand, operand)
                    ? dereference
                    : new BoundDereference(dereference.Span, dereference.Type, operand);
            }

            case BoundArrayCreate created:
            {
                var count = Rewrite(created.Count);
                var make = Rewrite(created.Make);
                return Same(created.Count, count) && Same(created.Make, make)
                    ? created
                    : new BoundArrayCreate(created.Span, created.ArrayType, count, make);
            }

            case BoundArrayFill fill:
            {
                var count = Rewrite(fill.Count);
                var make = Rewrite(fill.Make);
                var element = Rewrite(fill.Element);
                return Same(fill.Count, count) && Same(fill.Make, make) && Same(fill.Element, element)
                    ? fill
                    : new BoundArrayFill(fill.Span, fill.ArrayType, count, make,
                        fill.MakeLocal, fill.AtLocal, element);
            }

            case BoundNewArray array:
            {
                var length = Rewrite(array.Length);
                return Same(array.Length, length)
                    ? array
                    : new BoundNewArray(array.Span, array.ArrayType, length);
            }

            case BoundSlice slice:
            {
                var target = Rewrite(slice.Target);
                var start = RewriteOptional(slice.Start);
                var end = RewriteOptional(slice.End);
                return Same(slice.Target, target) && Same(slice.Start, start) && Same(slice.End, end)
                    ? slice
                    : new BoundSlice(slice.Span, (SliceTypeSymbol)slice.Type, target, start, end)
                    {
                        StartOrigin = slice.StartOrigin,
                        EndOrigin = slice.EndOrigin,
                    };
            }

            default:
                throw Unknown(expression, expression.Span);
        }
    }

    // ------------------------------------------------------------ patterns

    public BoundPattern RewriteChildren(BoundPattern pattern)
    {
        switch (pattern)
        {
            case BoundDiscardPattern:
                return pattern;

            case BoundDeclarationPattern named:
            {
                var value = Rewrite(named.Value);
                return Same(named.Value, value)
                    ? named
                    : new BoundDeclarationPattern(named.Span, named.Local, value);
            }

            case BoundTestPattern test:
            {
                var condition = Rewrite(test.Test);
                return Same(test.Test, condition)
                    ? test
                    : new BoundTestPattern(test.Span, test.Input, condition, test.Key);
            }

            case BoundReadPattern read:
            {
                var value = Rewrite(read.Read);
                var inner = Rewrite(read.Pattern);
                return Same(read.Read, value) && Same(read.Pattern, inner)
                    ? read
                    : new BoundReadPattern(read.Span, read.Input, value, inner);
            }

            case BoundEffectPattern effect:
            {
                var done = Rewrite(effect.Effect);
                return Same(effect.Effect, done)
                    ? effect
                    : new BoundEffectPattern(effect.Span, done);
            }

            case BoundAndPattern both:
            {
                var parts = RewriteAll(both.Parts);
                return Same(both.Parts, parts) ? both : new BoundAndPattern(both.Span, parts);
            }

            case BoundOrPattern either:
            {
                var left = Rewrite(either.Left);
                var right = Rewrite(either.Right);
                return Same(either.Left, left) && Same(either.Right, right)
                    ? either
                    : new BoundOrPattern(either.Span, left, right);
            }

            case BoundNotPattern negated:
            {
                var operand = Rewrite(negated.Operand);
                return Same(negated.Operand, operand)
                    ? negated
                    : new BoundNotPattern(negated.Span, operand);
            }

            default:
                throw Unknown(pattern, pattern.Span);
        }
    }

    private static InternalCompilerError Unknown(object node, SourceSpan span) =>
        new($"the bound tree rewriter has no case for {node.GetType().Name}", span);

    private static InternalCompilerError Unexpected(object node, string wanted) =>
        new($"a rewrite made {node.GetType().Name} where {wanted} has to stay one");
}
