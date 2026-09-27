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

/// <summary><c>x op= y</c> and <c>x ??= y</c>: a place read and written back, named once.</summary>
public sealed partial class Lowerer
{
    private Places Holds => new((hint, type) => Synthetic(hint, type));

    private BoundExpression LowerCompoundAssignment(BoundCompoundAssignment compound, bool discarded)
    {
        var span = compound.Span;
        var target = Rewrite(compound.Target);
        var held = new List<HeldValue>();

        if (compound.Property is { } property)
            return Places.WithHeld(span, held,
                LowerPropertyCompound(compound, property, (BoundCall)target, held, discarded));

        // The place is held only when naming it again could differ, which is
        // when something here has an effect.
        var stable = Places.IsRepeatable(target) && Places.IsRepeatable(compound.Value)
            ? target
            : Holds.HoldPlace(target, held, everything: true);

        if (!compound.IsFallback)
            return Places.WithHeld(span, held, new BoundAssignment(span, stable,
                Rewrite(Replace(compound.Combined, compound.Current, stable))));

        var absent = new BoundBinary(span, PrimitiveTypeSymbol.Bool,
            stable, BoundBinaryOp.Equal, new BoundNullLiteral(span, target.Type));

        return Places.WithHeld(span, held, new BoundConditional(span, target.Type, absent,
            new BoundAssignment(span, stable, Rewrite(compound.Combined)),
            stable));
    }

    /// <summary>
    /// The getter and then the setter, on one receiver and one set of
    /// indices; for <c>??=</c>, the getter once and the setter only when it
    /// answered nothing.
    /// </summary>
    private BoundExpression LowerPropertyCompound(
        BoundCompoundAssignment compound, PropertySymbol property, BoundCall read, List<HeldValue> held,
        bool discarded)
    {
        var span = compound.Span;
        var receiver = read.Receiver;
        var indices = property.IsIndexer ? read.Arguments : [];

        if (!(receiver is null || Places.IsRepeatable(receiver)) || !indices.All(Places.IsRepeatable) ||
            !Places.IsRepeatable(compound.Value))
        {
            if (receiver is not null) receiver = Holds.HoldReceiver(receiver, held, everything: true);
            indices = indices.Select(index => Holds.HoldValue(index, held, everything: true)).ToList();
        }

        var reread = new BoundCall(read.Span, read.Function, receiver, indices) { IsNonVirtual = read.IsNonVirtual };

        if (!compound.IsFallback)
        {
            var written = new BoundPropertyAssignment(span, receiver, property,
                Replace(compound.Combined, compound.Current, reread))
            {
                Indices = indices,
                IsNonVirtual = read.IsNonVirtual,
            };
            return discarded ? Discarded(written) : LowerPropertyAssignment(written);
        }

        var was = Synthetic("was", property.Type);
        var wasRead = new BoundLocalAccess(span, was);

        return new BoundLet(span, was, reread,
            new BoundConditional(span, property.Type,
                new BoundBinary(span, PrimitiveTypeSymbol.Bool, wasRead,
                    BoundBinaryOp.Equal, new BoundNullLiteral(span, property.Type)),
                LowerPropertyAssignment(new BoundPropertyAssignment(span, receiver, property, compound.Combined)
                {
                    Indices = indices,
                    IsNonVirtual = read.IsNonVirtual,
                }),
                wasRead));
    }

    /// <summary>
    /// <c>let held = a in held.b = v</c>: what the store lands in, held while
    /// the value runs, unless it is a variable only this statement could change.
    /// </summary>
    private BoundExpression LowerMemberAssignment(BoundMemberAssignment assignment)
    {
        var held = new List<HeldValue>();
        var place = Holds.HoldPlace(assignment.Target, held, everything: false);
        return Rewrite(Places.WithHeld(assignment.Span, held,
            new BoundAssignment(assignment.Span, place, assignment.Value)));
    }

    /// <summary>
    /// <c>let held = x in (held is C ? (C?)held : null)</c>. The name borrows:
    /// whatever made the value is a temporary the statement will drop.
    /// </summary>
    private BoundExpression LowerAs(BoundAs asked)
    {
        var span = asked.Span;
        var value = Rewrite(asked.Value);
        var held = Synthetic("as", value.Type, isConst: true);
        var reading = new BoundLocalAccess(asked.Value.Span, held);

        return new BoundLet(span, held, value,
            new BoundConditional(span, asked.Type,
                new BoundTypeTest(span, PrimitiveTypeSymbol.Bool, reading, asked.Wanted),
                new BoundConversion(span, asked.Type, reading, ConversionKind.TestedReference),
                new BoundNullLiteral(span, asked.Type)));
    }

    /// <summary>
    /// <c>let held = target in let made = held.Clone() in (made.X = 1, ..., made)</c>.
    /// The target is held, so <c>Compute() with { X = 1 }</c> calls
    /// <c>Compute</c> once.
    /// </summary>
    private BoundExpression LowerWith(BoundWith copied)
    {
        var span = copied.Span;
        var held = Synthetic("changed", copied.Record);
        BoundExpression made = new BoundCall(span, copied.Clone, new BoundLocalAccess(span, held), []);

        // The clone is the target's own type or one derived from it, so this
        // narrows nothing that needs asking.
        if (!ReferenceEquals(copied.Clone.ReturnType, copied.Record))
            made = new BoundConversion(span, copied.Record, made, ConversionKind.PointerCast);

        var target = Rewrite(copied.Target);
        if (copied.Assignments.Count == 0)
            return new BoundLet(span, held, target, made);

        var copy = Synthetic("made", copied.Record, isConst: true);
        var named = new BoundLocalAccess(span, copy);

        var steps = copied.Assignments
            .Select(w => Discarded(new BoundPropertyAssignment(w.Span, named, w.Property, w.Value)))
            .ToList();

        return new BoundLet(span, held, target,
            new BoundLet(span, copy, made, new BoundSequence(span, steps, named)));
    }

    /// <summary>
    /// <c>let made = new T() in (made.X = 1, ..., made)</c>: the object held in
    /// a name, because every entry works on it, and handed on as the value.
    /// </summary>
    private BoundExpression LowerObjectInitializer(BoundObjectInitializer initialized)
    {
        var span = initialized.Span;
        var held = Synthetic("made", initialized.Type, isConst: true);
        var reading = new BoundLocalAccess(span, held);

        var writes = initialized.Writes
            .Select(write => Discarded(Replace(write, initialized.Made, reading)))
            .ToList();

        return new BoundLet(span, held, Rewrite(initialized.Creation),
            new BoundSequence(span, writes, reading));
    }
}
