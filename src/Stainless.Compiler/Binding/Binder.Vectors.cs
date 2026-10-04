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
using Stainless.Syntax;

namespace Stainless.Binding;

// SIMD vectors: construction, lanes and swizzles, and the operators.
public sealed partial class Binder
{
    private const string LaneLetters = "xyzw";

    /// <summary>
    /// <c>new vfloat4(1, 2, 3, 4)</c>; <c>new vfloat4(0.5f)</c>, which fills
    /// every lane; <c>new vfloat4(v.xyz, 1)</c>, which joins; and
    /// <c>new vfloat4()</c>, which is zero.
    /// </summary>
    private BoundExpression BindVectorNew(NewSyntax syntax, VectorTypeSymbol vector, List<BoundExpression> arguments)
    {
        if (syntax.Arguments.Any(a => a is NamedArgumentSyntax or RefArgumentSyntax or OutArgumentSyntax))
        {
            diagnostics.Error("SL0929", syntax.Span,
                $"'{vector.Name}' is made from its lanes in order, so an argument is not named and not 'ref' or 'out'",
                vector);
            return new BoundErrorExpression(syntax.Span);
        }

        if (arguments.Count == 1 && arguments[0].Type is not VectorTypeSymbol)
            return new BoundVectorNew(syntax.Span, vector,
                [BindConversion(arguments[0], vector.Element, arguments[0].Span)]);

        var parts = new List<BoundExpression>();
        int filled = 0;
        foreach (var argument in arguments)
        {
            if (argument.Type is VectorTypeSymbol given)
            {
                if (given.Element != vector.Element)
                {
                    diagnostics.Error("SL0929", argument.Span,
                        $"'{given.Name}' holds '{given.Element.Name}' and '{vector.Name}' holds " +
                        $"'{vector.Element.Name}'; convert it with '({vector.WithLanes(given.Lanes)!.Name})' first",
                        given, vector);
                    return new BoundErrorExpression(syntax.Span);
                }

                filled += given.Lanes;
                parts.Add(argument);
                continue;
            }

            var lane = BindConversion(argument, vector.Element, argument.Span);
            if (lane.Type.IsError()) return new BoundErrorExpression(syntax.Span);
            filled++;
            parts.Add(lane);
        }

        if (filled != 0 && filled != vector.Lanes)
        {
            diagnostics.Error("SL0929", syntax.Span,
                $"'{vector.Name}' has {vector.Lanes} lanes, and these fill {filled}; give one value for " +
                "every lane, or one value to fill them all",
                vector);
            return new BoundErrorExpression(syntax.Span);
        }

        return new BoundVectorNew(syntax.Span, vector, parts);
    }

    /// <summary>
    /// <c>v.x</c>, which is a lane and so storage; <c>v.zyx</c>, a vector of
    /// the lanes named; and <c>v.lo</c>, <c>v.hi</c>, <c>v.even</c> and
    /// <c>v.odd</c>, the halves of a vector with an even number of lanes.
    /// </summary>
    private BoundExpression BindVectorMember(BoundExpression receiver, VectorTypeSymbol vector, MemberAccessSyntax syntax)
    {
        string member = syntax.Member;
        int[]? lanes = member switch
        {
            "lo" when vector.Lanes % 2 == 0 => [.. Enumerable.Range(0, vector.Lanes / 2)],
            "hi" when vector.Lanes % 2 == 0 => [.. Enumerable.Range(vector.Lanes / 2, vector.Lanes / 2)],
            "even" when vector.Lanes % 2 == 0 => [.. Enumerable.Range(0, vector.Lanes / 2).Select(i => i * 2)],
            "odd" when vector.Lanes % 2 == 0 => [.. Enumerable.Range(0, vector.Lanes / 2).Select(i => i * 2 + 1)],
            _ when member.Length <= 4 && member.All(c => LaneLetters.IndexOf(c) is >= 0) =>
                [.. member.Select(c => LaneLetters.IndexOf(c))],
            _ => null,
        };

        if (lanes is null || lanes.Any(lane => lane >= vector.Lanes))
        {
            string letters = LaneLetters[..Math.Min(4, vector.Lanes)];
            string named = string.Join(", ", letters.AsEnumerable());
            string reversed = new(letters.Reverse().ToArray());
            diagnostics.Error("SL0930", syntax.Span,
                $"'{vector.Name}' has no member named '{member}'; " +
                (vector.Lanes > 4 ? $"its first four lanes are {named}" : $"its lanes are {named}") +
                $", which combine as 'v.{reversed}', and every lane is 'v[i]'" +
                (vector.Lanes % 2 == 0 ? "; its halves are lo, hi, even and odd" : ""),
                vector);
            return new BoundErrorExpression(syntax.Span);
        }

        if (lanes.Length == 1)
            return new BoundIndex(syntax.Span, vector.Element, receiver,
                new BoundLiteral(syntax.Span, PrimitiveTypeSymbol.NUInt, (ulong)lanes[0]));

        return new BoundVectorShuffle(syntax.Span, vector.WithLanes(lanes.Length)!, receiver, lanes);
    }

    /// <summary>
    /// <c>v.xy = p</c>, and <c>v.xy += p</c> where naming the vector twice
    /// names the same storage and does nothing else.
    /// </summary>
    private BoundExpression BindSwizzleAssignment(AssignmentSyntax syntax, BoundVectorShuffle target, BoundExpression value)
    {
        if (target.Lanes.Distinct().Count() != target.Lanes.Count)
        {
            diagnostics.Error("SL0931", syntax.Target.Span,
                "a lane named twice would be written twice, and which write lasts is no answer; " +
                "name each lane once",
                target.Type);
            return new BoundErrorExpression(syntax.Span);
        }

        if (!Writable(target.Vector, syntax.Target.Span, "=")) return new BoundErrorExpression(syntax.Span);
        NoteMemberWritten(target.Vector);

        if (syntax.Operator == TokenKind.Equals)
            return new BoundSwizzleAssignment(syntax.Span, target,
                BindConversion(value, target.Type, syntax.Value.Span));

        if (!IsRepeatable(target.Vector))
        {
            diagnostics.Error("SL0931", syntax.Target.Span,
                $"'{syntax.Operator.FixedText()}' on lanes reads the vector and writes it back, and this " +
                "vector is worked out by something that may not give the same answer twice; " +
                "put it in a local first",
                target.Type);
            return new BoundErrorExpression(syntax.Span);
        }

        var (op, token) = CompoundOperator(syntax.Operator);
        var combined = BindBinaryOperation(syntax.Span, target, op, value, token);
        if (combined.Type.IsError()) return new BoundErrorExpression(syntax.Span);
        return new BoundSwizzleAssignment(syntax.Span, target,
            BindConversion(combined, target.Type, syntax.Value.Span));
    }

    /// <summary>
    /// An operator with a vector on either side, lane by lane. A lane value on
    /// one side fills every lane. Equality is a <c>bool</c> answering for every
    /// lane; ordering is per lane and so is a function, <c>vfloat4.LessThan</c>.
    /// </summary>
    private BoundExpression BindVectorBinary(
        SourceSpan span, BoundExpression left, BoundBinaryOp op, BoundExpression right, TokenKind token)
    {
        var vector = (left.Type as VectorTypeSymbol ?? right.Type as VectorTypeSymbol)!;

        if (left.Type is VectorTypeSymbol l && right.Type is VectorTypeSymbol r && l != r)
        {
            diagnostics.Error("SL0932", span,
                $"'{l.Name}' and '{r.Name}' are different vectors; convert one with a cast, as " +
                $"'({l.Name})value'",
                l, r);
            return new BoundErrorExpression(span);
        }

        bool shift = op is BoundBinaryOp.ShiftLeft or BoundBinaryOp.ShiftRight or BoundBinaryOp.UnsignedShiftRight;
        bool integer = vector.Element.IsInteger;
        string? refusal = op switch
        {
            BoundBinaryOp.Less or BoundBinaryOp.LessEqual or BoundBinaryOp.Greater or BoundBinaryOp.GreaterEqual =>
                $"a vector is not ordered as a whole; '{vector.Name}.LessThan(a, b)' and its kin answer " +
                "lane by lane, as a mask",
            BoundBinaryOp.BitAnd or BoundBinaryOp.BitOr or BoundBinaryOp.BitXor when !integer =>
                $"'{vector.Name}' holds floating-point lanes, which have no bits to combine",
            _ when shift && !integer => $"'{vector.Name}' holds floating-point lanes, which do not shift",
            _ when shift && left.Type is not VectorTypeSymbol =>
                "a shift moves the lanes of the vector on its left",
            _ => null,
        };
        if (refusal is not null)
        {
            diagnostics.Error("SL0932", span,
                $"operator '{token.FixedText()}' cannot be applied to '{left.Type.Name}' and " +
                $"'{right.Type.Name}': {refusal}",
                left.Type, right.Type);
            return new BoundErrorExpression(span);
        }

        var lanesLeft = VectorOperand(left, vector);
        var lanesRight = VectorOperand(right, vector);
        if (lanesLeft.Type.IsError() || lanesRight.Type.IsError()) return new BoundErrorExpression(span);

        bool equality = op is BoundBinaryOp.Equal or BoundBinaryOp.NotEqual;
        return new BoundBinary(span, equality ? PrimitiveTypeSymbol.Bool : vector, lanesLeft, op, lanesRight);
    }

    /// <summary>A side of a vector operator as the vector: itself, or a lane value filling every lane.</summary>
    private BoundExpression VectorOperand(BoundExpression operand, VectorTypeSymbol vector)
    {
        if (operand.Type is VectorTypeSymbol) return operand;
        var lane = BindConversion(operand, vector.Element, operand.Span);
        return lane.Type.IsError() ? lane : new BoundVectorNew(operand.Span, vector, [lane]);
    }

    /// <summary>
    /// A vector in an interpolation: <c>&lt;1, 2, 3, 4&gt;</c>, as .NET's
    /// vectors write themselves, each lane written as a lane alone would be.
    /// </summary>
    private BoundExpression VectorText(
        BoundExpression value, VectorTypeSymbol vector, SourceSpan span, Func<BoundExpression, BoundExpression> lane) =>
        WithHeldValue(span, value, "lanes", held =>
        {
            var parts = new List<BoundExpression> { new BoundStringLiteral(span, _builtins.String, "<") };
            for (int i = 0; i < vector.Lanes; i++)
            {
                if (i > 0) parts.Add(new BoundStringLiteral(span, _builtins.String, ", "));
                var written = lane(new BoundIndex(span, vector.Element, held,
                    new BoundLiteral(span, PrimitiveTypeSymbol.NUInt, (ulong)i)));
                if (written.Type.IsError()) return written;
                parts.Add(written);
            }

            parts.Add(new BoundStringLiteral(span, _builtins.String, ">"));
            return new BoundInterpolatedString(span, _builtins.String, parts);
        });

    /// <summary><c>-v</c>, <c>+v</c> and <c>~v</c>, lane by lane, with no widening of narrow lanes.</summary>
    private BoundExpression BindVectorUnary(UnarySyntax syntax, BoundExpression operand, VectorTypeSymbol vector)
    {
        switch (syntax.Operator)
        {
            case TokenKind.Plus:
                return operand;
            case TokenKind.Minus:
                return new BoundUnary(syntax.Span, vector, BoundUnaryOp.Negate, operand);
            case TokenKind.Tilde when vector.Element.IsInteger:
                return new BoundUnary(syntax.Span, vector, BoundUnaryOp.BitwiseNot, operand);
            default:
                diagnostics.Error("SL0232", syntax.Span,
                    $"operator '{syntax.Operator.FixedText()}' cannot be applied to '{vector.Name}'",
                    vector);
                return new BoundErrorExpression(syntax.Span);
        }
    }
}
