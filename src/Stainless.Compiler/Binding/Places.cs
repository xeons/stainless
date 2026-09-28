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

/// <summary>A value an assignment evaluates once and names again.</summary>
internal readonly record struct HeldValue(LocalSymbol Local, BoundExpression Value, bool IsOwned);

/// <summary>
/// A place, a receiver or a value made safe to name twice: what naming it
/// again would evaluate is held in a <see cref="BoundLet"/> first. Lowering
/// holds; binding asks only whether reading something again is free.
/// </summary>
/// <param name="newLocal">Makes the local a held value lives in, from a hint and a type.</param>
internal sealed class Places(Func<string, TypeSymbol, LocalSymbol> newLocal)
{
    /// <summary>
    /// A place rewritten so that naming it again evaluates nothing, and
    /// reaches the same storage whatever runs in between.
    ///
    /// With <paramref name="everything"/>, every receiver and index is held,
    /// in the order written. Without it, only the object or array the store
    /// lands in is held, which is what an assignment whose value runs code
    /// needs: that code may release the object's last other owner.
    /// </summary>
    public BoundExpression HoldPlace(
        BoundExpression place, List<HeldValue> held, bool everything)
    {
        switch (place)
        {
            case BoundFieldAccess { Receiver: { } receiver } field:
                return new BoundFieldAccess(field.Span,
                    field.Field.ContainingType is StructTypeSymbol
                        ? HoldPlace(receiver, held, everything)
                        : HoldContainer(receiver, held, everything),
                    field.Field);

            case BoundIndex { Target.Type: FixedArrayTypeSymbol } element:
                return new BoundIndex(element.Span, element.Type,
                    HoldPlace(element.Target, held, everything),
                    HoldValue(element.Index, held, everything))
                    { Origin = element.Origin };

            case BoundIndex element:
                return new BoundIndex(element.Span, element.Type,
                    element.Target.Type is ArrayTypeSymbol
                        ? HoldContainer(element.Target, held, everything)
                        : HoldValue(element.Target, held, everything),
                    HoldValue(element.Index, held, everything))
                    { Origin = element.Origin };

            case BoundDereference dereference:
                return new BoundDereference(dereference.Span, dereference.Type,
                    HoldValue(dereference.Operand, held, everything));

            // A variable: naming it again names the same storage.
            default:
                return place;
        }
    }

    /// <summary>
    /// A property's receiver, held as <see cref="HoldPlace"/> holds a place:
    /// a struct through its storage, an object as the reference.
    /// </summary>
    public BoundExpression HoldReceiver(
        BoundExpression receiver, List<HeldValue> held, bool everything) =>
        receiver is BoundAddressOf { Operand: { IsLValue: true } storage } address
            ? new BoundAddressOf(address.Span, address.Type, HoldPlace(storage, held, everything))
            : HoldContainer(receiver, held, everything);

    /// <summary>
    /// The reference to what a store lands in. Held even when nothing else
    /// is, unless it is a local or a parameter, which nothing but this
    /// statement's own assignments could change.
    /// </summary>
    public BoundExpression HoldContainer(
        BoundExpression container, List<HeldValue> held, bool everything) =>
        everything || container is not (BoundLocalAccess or BoundParameterAccess)
            ? HoldValue(container, held, everything: true)
            : container;

    /// <summary>
    /// A value evaluated now and read back later. A reference this statement
    /// did not make is owned while held, since what runs in between may drop
    /// every other reference to it.
    /// </summary>
    public BoundExpression HoldValue(
        BoundExpression value, List<HeldValue> held, bool everything)
    {
        if (!everything || IsFixed(value)) return value;

        var local = newLocal("held", value.Type);
        bool made = value is BoundCall or BoundNew or BoundIndirectCall or BoundClosureCall;
        held.Add(new HeldValue(local, value, value.Type.NeedsArc() && !made));
        return new BoundLocalAccess(value.Span, local);
    }

    /// <summary>Whether a value is the same wherever and however often it is read.</summary>
    public static bool IsFixed(BoundExpression expression) => expression switch
    {
        BoundLiteral or BoundStringLiteral or BoundUtf8Literal or BoundNullLiteral => true,
        BoundConstantAccess => true,
        BoundSizeof or BoundAlignof or BoundOffsetof or BoundThis => true,
        BoundConversion conversion => IsFixed(conversion.Operand),
        _ => false,
    };

    /// <summary>Binds each held value around what follows it, in the order held.</summary>
    public static BoundExpression WithHeld(
        SourceSpan span, List<HeldValue> held, BoundExpression body)
    {
        for (int i = held.Count - 1; i >= 0; i--)
            body = new BoundLet(span, held[i].Local, held[i].Value, body) { IsOwned = held[i].IsOwned };

        return body;
    }

    /// <summary>
    /// True when evaluating this expression again has no consequences: it reads
    /// storage or computes from constants, rather than doing anything.
    ///
    /// A call is deliberately absent, which is what makes this useful: it is
    /// exactly the question a lowering has to ask before naming its operand
    /// twice.
    /// </summary>
    public static bool IsRepeatable(BoundExpression expression) => expression switch
    {
        BoundLiteral or BoundStringLiteral or BoundUtf8Literal or BoundNullLiteral => true,
        BoundConstantAccess or BoundDefault => true,
        BoundLocalAccess or BoundParameterAccess or BoundThis or BoundStaticAccess or BoundPlaceholder => true,
        BoundFieldAccess field => field.Receiver is null || IsRepeatable(field.Receiver),
        BoundIndex element => IsRepeatable(element.Target) && IsRepeatable(element.Index),
        BoundDereference dereference => IsRepeatable(dereference.Operand),
        BoundAddressOf address => IsRepeatable(address.Operand),
        BoundConversion conversion => IsRepeatable(conversion.Operand),
        BoundUnary unary => IsRepeatable(unary.Operand),
        BoundBinary binary => IsRepeatable(binary.Left) && IsRepeatable(binary.Right),
        BoundConditional chosen => IsRepeatable(chosen.Condition) && IsRepeatable(chosen.WhenTrue) &&
                                   IsRepeatable(chosen.WhenFalse),
        _ => false,
    };
}
