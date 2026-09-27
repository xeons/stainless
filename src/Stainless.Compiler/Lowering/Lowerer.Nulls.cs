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

/// <summary><c>?.</c> and <c>??</c>: a value held once, asked whether it is there, and chosen on.</summary>
public sealed partial class Lowerer
{
    /// <summary>
    /// <c>let held = a in (held != null ? m(held) : nothing)</c>. The name
    /// borrows: the receiver is already a temporary the statement will drop,
    /// and this only reads it in the meantime.
    /// </summary>
    private BoundExpression LowerConditionalAccess(BoundConditionalAccess asked)
    {
        var receiver = Rewrite(asked.Receiver);
        var held = Synthetic("asked", receiver.Type);
        var reading = new BoundLocalAccess(asked.Receiver.Span, held);

        var present = new BoundBinary(asked.Span, PrimitiveTypeSymbol.Bool,
            reading, BoundBinaryOp.NotEqual, new BoundNullLiteral(asked.Span, receiver.Type));

        var narrowed = new BoundConversion(
            asked.Receiver.Span, asked.Present.Type, reading, ConversionKind.NarrowOptional);

        return new BoundLet(asked.Span, held, receiver,
            new BoundConditional(asked.Span, asked.Type, present,
                Rewrite(Replace(asked.Access, asked.Present, narrowed)),
                Rewrite(asked.WhenNothing)));
    }

    /// <summary>
    /// <c>let held = a in (held != null ? held : b)</c>, which is the shape
    /// the emitter hands the left's own +1 on through.
    /// </summary>
    private BoundExpression LowerNullFallback(BoundNullFallback fallback)
    {
        var value = Rewrite(fallback.Value);
        var held = Synthetic("held", value.Type);
        var reading = new BoundLocalAccess(fallback.Value.Span, held);

        var present = new BoundBinary(fallback.Span, PrimitiveTypeSymbol.Bool,
            reading, BoundBinaryOp.NotEqual, new BoundNullLiteral(fallback.Span, value.Type));

        BoundExpression chosen = fallback.Type is OptionalTypeSymbol
            ? reading
            : new BoundConversion(fallback.Value.Span, fallback.Type, reading, ConversionKind.NarrowOptional);

        return new BoundLet(fallback.Span, held, value,
            new BoundConditional(fallback.Span, fallback.Type, present, chosen, Rewrite(fallback.Fallback)));
    }
}
