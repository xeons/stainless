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

using Stainless.Binding;

namespace Stainless.Lowering;

/// <summary>
/// A property written or stepped, as the calls to its accessors.
///
/// <para>
/// A read already is one: binding makes it the getter's call. A write is the
/// setter's, and an assignment is an expression whose value is what it
/// stored, so where that value is read the receiver, the indices and the
/// value are each held in a name, the setter called, and the value handed on.
/// Where nothing reads it -- a statement, a <c>for</c>'s step, a sequence's
/// earlier parts, what a <c>let</c> is evaluated for -- it is the call alone,
/// which evaluates them in the same order and holds nothing.
/// </para>
/// <para>
/// <c>++</c> and <c>--</c> call the getter and then the setter on one
/// receiver and one set of indices, each evaluated once.
/// </para>
/// <para>
/// So whether an expression's value is read decides how it lowers, and the
/// statements and expressions that drop a value lower it through
/// <see cref="Discarded"/>.
/// </para>
/// </summary>
public sealed partial class Lowerer
{
    /// <summary>A statement that drops a value, or null for any other.</summary>
    private BoundStatement? LowerDropping(BoundStatement statement)
    {
        switch (statement)
        {
            case BoundExpressionStatement evaluated:
            {
                var expression = Discarded(evaluated.Expression);
                return ReferenceEquals(expression, evaluated.Expression)
                    ? evaluated
                    : new BoundExpressionStatement(evaluated.Span, expression);
            }

            case BoundFor { Step: { } step } loop:
            {
                var initializer = RewriteOptional(loop.Initializer);
                var condition = RewriteOptional(loop.Condition);
                var body = Rewrite(loop.Body);
                var stepped = Discarded(step);

                if (ReferenceEquals(initializer, loop.Initializer) && ReferenceEquals(condition, loop.Condition) &&
                    ReferenceEquals(body, loop.Body) && ReferenceEquals(stepped, step))
                    return loop;

                var rebuilt = new BoundFor(loop.Span, initializer, condition, stepped, body);
                rebuilt.Locals.AddRange(loop.Locals);
                return rebuilt;
            }

            case BoundDeconstruct taken:
            {
                var declarations = taken.Declarations.Select(d => (BoundLocalDeclaration)Rewrite(d)).ToList();
                var expression = Discarded(taken.Expression);
                return ReferenceEquals(expression, taken.Expression) &&
                       declarations.SequenceEqual(taken.Declarations)
                    ? taken
                    : new BoundDeconstruct(taken.Span, declarations, expression);
            }

            default:
                return null;
        }
    }

    /// <summary>A sequence whose earlier parts are evaluated for what they do, rebuilt only if they changed.</summary>
    private BoundSequence Sequence(BoundSequence sequence, BoundExpression value)
    {
        List<BoundExpression>? before = null;
        for (int i = 0; i < sequence.Before.Count; i++)
        {
            var side = Discarded(sequence.Before[i]);
            if (before is null && !ReferenceEquals(side, sequence.Before[i]))
                before = [.. sequence.Before.Take(i)];
            before?.Add(side);
        }

        return before is null && ReferenceEquals(value, sequence.Value)
            ? sequence
            : new BoundSequence(sequence.Span, before ?? sequence.Before, value);
    }

    /// <summary>An expression evaluated for what it does, its value dropped.</summary>
    private BoundExpression Discarded(BoundExpression expression) => expression switch
    {
        BoundCompoundAssignment compound => LowerCompoundAssignment(compound, discarded: true),

        BoundPropertyAssignment written => DiscardedPropertyAssignment(written),

        BoundPropertyIncrement stepped => LowerPropertyIncrement(stepped, discarded: true),

        BoundDeconstruction taken => LowerDeconstruction(taken, discarded: true),

        BoundSequence sequence => Sequence(sequence, Discarded(sequence.Value)),

        BoundLet held => Let(held),

        _ => Rewrite(expression),
    };

    private BoundLet Let(BoundLet held)
    {
        var value = Rewrite(held.Value);
        var body = Discarded(held.Body);
        return ReferenceEquals(value, held.Value) && ReferenceEquals(body, held.Body)
            ? held
            : new BoundLet(held.Span, held.Local, value, body) { IsOwned = held.IsOwned };
    }

    /// <summary>
    /// <c>let r = receiver in let i = index in let v = value in (set(r, i, v), v)</c>:
    /// what an assignment is where its value is read.
    /// </summary>
    private BoundExpression LowerPropertyAssignment(BoundPropertyAssignment written)
    {
        var span = written.Span;
        var kept = new List<HeldValue>();
        var receiver = KeptWhileStoring(written, kept);
        var held = new List<(LocalSymbol Local, BoundExpression Value)>();

        receiver = receiver is null ? null : Held(Rewrite(receiver), "receiver", held);
        var indices = RewriteAll(written.Indices).Select(index => Held(index, "index", held)).ToList();
        var value = Held(Rewrite(written.Value), "stored", held);

        var set = new BoundCall(span, written.Property.Setter!, receiver, [.. indices, value])
        {
            IsNonVirtual = written.IsNonVirtual,
        };

        return Places.WithHeld(span, kept, Around(span, held, new BoundSequence(span, [set], value)));
    }

    /// <summary>A property written where nothing reads the write: the setter's call alone.</summary>
    private BoundExpression DiscardedPropertyAssignment(BoundPropertyAssignment written)
    {
        var kept = new List<HeldValue>();
        var receiver = KeptWhileStoring(written, kept);

        return Places.WithHeld(written.Span, kept, new BoundCall(written.Span, written.Property.Setter!,
            RewriteOptional(receiver),
            [.. RewriteAll(written.Indices), Rewrite(written.Value)])
        {
            IsNonVirtual = written.IsNonVirtual,
        });
    }

    /// <summary>
    /// The receiver of a write the source made, held in <paramref name="kept"/>
    /// while a value that runs code is evaluated: that code may drop its last
    /// other owner. What is held is lowered here, before anything that reads it.
    /// </summary>
    private BoundExpression? KeptWhileStoring(BoundPropertyAssignment written, List<HeldValue> kept)
    {
        if (!written.HoldsReceiver || written.Receiver is not { } receiver || Places.IsRepeatable(written.Value))
            return written.Receiver;

        receiver = Holds.HoldReceiver(receiver, kept, everything: false);
        for (int i = 0; i < kept.Count; i++)
            kept[i] = kept[i] with { Value = Rewrite(kept[i].Value) };
        return receiver;
    }

    /// <summary>
    /// The getter, one more or one less, the setter: on one receiver and one
    /// set of indices, and with the value before or after as the result.
    /// </summary>
    private BoundExpression LowerPropertyIncrement(BoundPropertyIncrement stepped, bool discarded)
    {
        var span = stepped.Span;
        var property = stepped.Property;
        var held = new List<(LocalSymbol Local, BoundExpression Value)>();

        var receiver = stepped.Receiver is null ? null : Held(Rewrite(stepped.Receiver), "receiver", held);
        var indices = RewriteAll(stepped.Arguments).Select(index => Held(index, "index", held)).ToList();

        var read = new BoundCall(span, property.Getter!, receiver, indices);
        BoundCall Set(BoundExpression value) => new(span, property.Setter!, receiver, [.. indices, value]);

        if (discarded)
            return Around(span, held, Set(Step(read, stepped)));

        // `++x` is the value after; `x++` the value before, which the step is made from.
        var kept = Synthetic(stepped.IsPrefix ? "now" : "was", property.Type);
        var named = new BoundLocalAccess(span, kept);

        var body = stepped.IsPrefix
            ? new BoundLet(span, kept, Step(read, stepped), new BoundSequence(span, [Set(named)], named))
            : new BoundLet(span, kept, read, new BoundSequence(span, [Set(Step(named, stepped))], named));

        return Around(span, held, body);
    }

    /// <summary>One more, or one less: a pointer by an element, a float by 1.0, an integer by 1.</summary>
    private static BoundBinary Step(BoundExpression value, BoundPropertyIncrement stepped)
    {
        var span = stepped.Span;
        var op = stepped.IsIncrement ? BoundBinaryOp.Add : BoundBinaryOp.Subtract;

        BoundExpression one = value.Type switch
        {
            PointerTypeSymbol => new BoundLiteral(span, PrimitiveTypeSymbol.Int, 1UL),
            PrimitiveTypeSymbol { IsFloat: true } => new BoundLiteral(span, value.Type, 1.0),
            _ => new BoundLiteral(span, value.Type, 1UL),
        };

        return new BoundBinary(span, value.Type, value, op, one) { IsChecked = stepped.IsChecked };
    }

    /// <summary>A value named once for what follows, unless it is a constant that reads the same anywhere.</summary>
    private BoundExpression Held(BoundExpression value, string hint, List<(LocalSymbol Local, BoundExpression Value)> held)
    {
        if (Places.IsFixed(value))
            return value;

        var local = Synthetic(hint, value.Type);
        held.Add((local, value));
        return new BoundLocalAccess(value.Span, local);
    }

    /// <summary>Each held value around what follows it, in the order held. Each borrows.</summary>
    private static BoundExpression Around(
        Source.SourceSpan span, List<(LocalSymbol Local, BoundExpression Value)> held, BoundExpression body)
    {
        for (int i = held.Count - 1; i >= 0; i--)
            body = new BoundLet(span, held[i].Local, held[i].Value, body);

        return body;
    }
}
