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
/// Deconstruction, in C#'s order: the targets' receivers and indices left to
/// right, then every value on the right, then the stores left to right.
/// </summary>
public sealed partial class Lowerer
{
    /// <summary>
    /// A value evaluated before any store: a let when it has a
    /// <see cref="Local"/>, otherwise an expression run for what it does.
    /// </summary>
    private readonly record struct DeconstructionStep(LocalSymbol? Local, BoundExpression Value, bool IsOwned);

    private BoundExpression LowerDeconstruction(BoundDeconstruction taken, bool discarded)
    {
        var spelled = SpellDeconstruction(taken);
        return discarded ? Discarded(spelled) : Rewrite(spelled);
    }

    /// <summary>
    /// The lets and stores a deconstruction is, before what they hold is
    /// lowered: held receivers and indices around held values around the
    /// stores, which are a sequence ending in the last, or for a
    /// deconstruction that is read, in the tuple of what was stored.
    /// </summary>
    private BoundExpression SpellDeconstruction(BoundDeconstruction taken)
    {
        var span = taken.Span;
        var held = new List<HeldValue>();
        var steps = new List<DeconstructionStep>();
        var target = SupplyDeconstruction(HoldDeconstructionTargets(taken.Target, held), steps, []);

        var writes = new List<BoundExpression>();
        WriteDeconstruction(target, writes);

        BoundExpression body;
        if (taken.IsValue)
        {
            var result = DeconstructedValue(target);
            body = writes.Count == 0 ? result : new BoundSequence(span, writes, result);
        }
        else if (writes.Count == 0)
        {
            // Every element was a discard, and the values are evaluated for
            // what they do.
            body = new BoundLiteral(span, PrimitiveTypeSymbol.Bool, true);
        }
        else
        {
            body = new BoundSequence(span, writes.Take(writes.Count - 1).ToList(), writes[^1]);
        }

        for (int i = steps.Count - 1; i >= 0; i--)
        {
            var step = steps[i];
            body = step.Local is null
                ? new BoundSequence(span, [step.Value], body)
                : new BoundLet(span, step.Local, step.Value, body) { IsOwned = step.IsOwned };
        }

        return Places.WithHeld(span, held, body);
    }

    /// <summary>Every receiver and index a store will need, held left to right.</summary>
    private BoundDeconstructionTarget HoldDeconstructionTargets(
        BoundDeconstructionTarget target, List<HeldValue> held)
    {
        switch (target.Kind)
        {
            case DeconstructionKind.Place:
                return target with { Place = Holds.HoldPlace(target.Place!, held, everything: true) };

            case DeconstructionKind.Property:
            {
                var receiver = target.Receiver is null
                    ? null
                    : Holds.HoldReceiver(target.Receiver, held, everything: true);
                var indices = target.Indices.Select(index => Holds.HoldValue(index, held, everything: true)).ToList();
                return target with { Receiver = receiver, Indices = indices };
            }

            case DeconstructionKind.Nested:
                return target with
                {
                    Elements = target.Elements.Select(e => HoldDeconstructionTargets(e, held)).ToList(),
                };

            default:
                return target;
        }
    }

    /// <summary>
    /// Each element's value, as what its store reads: held in
    /// <paramref name="steps"/> unless reading it again is free and nothing
    /// stored before it can change it.
    /// </summary>
    /// <param name="wholes">What each enclosing tuple's placeholder stands for.</param>
    private BoundDeconstructionTarget SupplyDeconstruction(
        BoundDeconstructionTarget target, List<DeconstructionStep> steps,
        List<(BoundPlaceholder Whole, BoundExpression Value)> wholes)
    {
        if (target.Kind != DeconstructionKind.Nested)
        {
            var value = Substituted(target.Value!, wholes);
            return target with
            {
                Value = target.IsStable && Places.IsRepeatable(value) ? value : HoldTaken(value, steps),
            };
        }

        switch (target.Supply)
        {
            case DeconstructionSupply.Tuple:
            {
                var value = Substituted(target.Value!, wholes);
                wholes = [.. wholes, (target.Whole!, target.IsStable ? value : HoldTaken(value, steps))];
                break;
            }

            case DeconstructionSupply.Deconstruct:
                steps.Add(new DeconstructionStep(null, Substituted(target.Value!, wholes), IsOwned: false));
                break;
        }

        return target with { Elements = target.Elements.Select(e => SupplyDeconstruction(e, steps, wholes)).ToList() };
    }

    private static BoundExpression Substituted(
        BoundExpression value, List<(BoundPlaceholder Whole, BoundExpression Value)> wholes)
    {
        foreach (var (whole, stands) in wholes)
            value = Replace(value, whole, stands);
        return value;
    }

    /// <summary>
    /// A value read now and stored later. A copy is owned unless the value
    /// is one this statement made, because a store before it is read may drop
    /// what it came from.
    /// </summary>
    private BoundExpression HoldTaken(BoundExpression value, List<DeconstructionStep> steps)
    {
        if (Places.IsFixed(value))
            return value;

        var local = Synthetic("taken", value.Type);
        bool owned = !BoundValues.IsMade(value) &&
                     (value.Type.NeedsArc() || value.Type is StructTypeSymbol or FixedArrayTypeSymbol);
        steps.Add(new DeconstructionStep(local, value, owned));
        return new BoundLocalAccess(value.Span, local);
    }

    /// <summary>The stores, left to right.</summary>
    private static void WriteDeconstruction(BoundDeconstructionTarget target, List<BoundExpression> writes)
    {
        switch (target.Kind)
        {
            case DeconstructionKind.Nested:
                foreach (var element in target.Elements)
                    WriteDeconstruction(element, writes);
                break;

            case DeconstructionKind.Declare:
                writes.Add(new BoundAssignment(target.Span,
                    new BoundLocalAccess(target.NameSpan, target.Local!), target.Value!));
                break;

            case DeconstructionKind.Place:
                writes.Add(new BoundAssignment(target.Span, target.Place!, target.Value!));
                break;

            case DeconstructionKind.Property:
                writes.Add(new BoundPropertyAssignment(target.Span, target.Receiver, target.Property!, target.Value!)
                {
                    Indices = target.Indices,
                    IsNonVirtual = target.IsNonVirtual,
                });
                break;
        }
    }

    /// <summary>What <c>(a, b) = t</c> evaluates to: the tuple of what was stored.</summary>
    private static BoundExpression DeconstructedValue(BoundDeconstructionTarget target) =>
        target.Kind == DeconstructionKind.Nested
            ? new BoundTupleCreate(target.Span, (TupleTypeSymbol)target.Type!,
                target.Elements.Select(DeconstructedValue).ToList())
            : target.Value!;
}
