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

namespace Stainless.Binding;

/// <summary>
/// What a bound value is, asked by binding and by lowering alike: whether it
/// names a declaration, whether reading it again is free, whether this
/// statement made it.
/// </summary>
internal static class BoundValues
{
    /// <summary>
    /// The declaration a narrowed fact can be attached to.
    ///
    /// Only a plain local or parameter qualifies. A field or a call result is
    /// refused for the reason a compound assignment refuses a computed receiver:
    /// the compiler would be proving something about one evaluation and letting
    /// it be read from another. Putting the Result in a local first is the fix,
    /// and it is what the code wants to say anyway.
    /// </summary>
    public static object? NarrowableSubject(BoundExpression expression) => expression switch
    {
        BoundLocalAccess local => local.Local,
        BoundParameterAccess parameter => parameter.Parameter,
        _ => null,
    };

    /// <summary>Whether reading this again costs a load and cannot find something else.</summary>
    public static bool IsSteadyRead(BoundExpression value) => value switch
    {
        BoundLocalAccess or BoundParameterAccess or BoundThis or BoundPlaceholder => true,
        BoundLiteral or BoundNullLiteral or BoundConstantAccess => true,
        BoundConversion { Kind: ConversionKind.NarrowOptional } narrowed => IsSteadyRead(narrowed.Operand),
        BoundVariantPayload payload => IsSteadyRead(payload.Receiver),
        BoundFieldAccess { Receiver: { } receiver } field =>
            receiver.Type is StructTypeSymbol && IsSteadyRead(receiver) && !field.Field.IsBitField,
        BoundArrayLength length => IsSteadyRead(length.Array),
        _ => false,
    };

    /// <summary>A view of a steady value under another type, which borrows what it views.</summary>
    public static bool IsSteadyConversion(BoundExpression value) =>
        value is BoundConversion { Kind: ConversionKind.Upcast or ConversionKind.Downcast
                                   or ConversionKind.ClassToInterface } conversion &&
        IsSteadyRead(conversion.Operand);

    /// <summary>Whether a value is a temporary this statement made and will drop.</summary>
    public static bool IsMade(BoundExpression value) => value switch
    {
        BoundCall or BoundNew or BoundIndirectCall or BoundClosureCall => true,
        BoundTupleCreate or BoundStructNew or BoundVariantConstruction => true,
        BoundLet held => IsMade(held.Body),
        BoundSequence sequence => IsMade(sequence.Value),
        BoundDeconstruction taken => taken.IsValue,
        BoundRangeSlice sliced => IsMade(sliced.Access),
        _ => false,
    };
}
