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

using System.Numerics;
using Stainless.Source;
using Stainless.Syntax;

namespace Stainless.Binding;

/// <summary>
/// Constant expressions: what a <c>const</c>, an enum member's value and an
/// inline array's length may be.
///
/// A literal is read where the constant is declared. Anything else is bound as
/// an ordinary expression, so its types and conversions are the ones the same
/// expression has in a body, and the bound tree is evaluated here. A constant
/// is folded the first time anything names it, which is what lets one name
/// another declared later or in another file; whatever nothing named is folded
/// at the end of pass 4.
///
/// Arithmetic is exact, and a result outside its type is an error rather than
/// a wrapped value, as C# makes it. A shift and an explicit narrowing cast
/// wrap, because wrapping is what they are written for.
/// </summary>
public sealed partial class Binder
{
    /// <summary>A constant whose initializer is waiting to be folded.</summary>
    private sealed class PendingConstant(
        FileScope scope, GlobalConstDeclSyntax declaration, NamedTypeSymbol? owner)
    {
        public FileScope Scope { get; } = scope;
        public GlobalConstDeclSyntax Declaration { get; } = declaration;

        /// <summary>The type that declares it, whose constants it names bare.</summary>
        public NamedTypeSymbol? Owner { get; } = owner;

        public bool InProgress { get; set; }
    }

    /// <summary>An enum with a member whose value is an expression.</summary>
    private sealed class PendingEnum(
        FileScope scope, List<(EnumMemberSymbol Member, ExpressionSyntax? Value)> members)
    {
        public FileScope Scope { get; } = scope;
        public List<(EnumMemberSymbol Member, ExpressionSyntax? Value)> Members { get; } = members;
        public bool InProgress { get; set; }

        /// <summary>How many members have their value, in declaration order.</summary>
        public int Folded { get; set; }
    }

    /// <summary>
    /// A folded value and its type. An integer, a code unit and an enum member
    /// are a <see cref="BigInteger"/>; a floating-point value is a
    /// <c>double</c>, rounded to <c>float</c> where its type is one; then a
    /// <c>bool</c> and a <c>string</c>.
    /// </summary>
    private readonly record struct FoldedValue(TypeSymbol Type, object Value);

    private readonly Dictionary<ConstantSymbol, PendingConstant> _pendingConstants = [];
    private readonly Dictionary<EnumTypeSymbol, PendingEnum> _pendingEnums = [];

    /// <summary>Constants that could not be folded, which have said so once already.</summary>
    private readonly HashSet<ConstantSymbol> _unfoldedConstants = [];

    /// <summary>Folds every constant and enum nothing has named yet.</summary>
    private void FoldPendingConstants()
    {
        foreach (var type in _pendingEnums.Keys.ToList())
            EnsureEnumFolded(type);
        foreach (var constant in _pendingConstants.Keys.ToList())
            EnsureConstantFolded(constant);
    }

    /// <summary>
    /// Gives a constant its value if it is still waiting for one. A constant
    /// reached again while it is being folded depends on itself.
    /// </summary>
    private void EnsureConstantFolded(ConstantSymbol constant)
    {
        if (!_pendingConstants.TryGetValue(constant, out var pending)) return;
        var declaration = pending.Declaration;

        if (pending.InProgress)
        {
            diagnostics.Report(Codes.ConstantDependsOnItself, declaration.Value.Span,
                $"'{constant.Name}' is worked out from itself, through the constants its " +
                "value names; one of them has to be written another way");
            _pendingConstants.Remove(constant);
            _unfoldedConstants.Add(constant);
            return;
        }
        pending.InProgress = true;

        BoundExpression bound;
        using (Enter(_context.ForBody(null) with
               {
                   File = pending.Scope, ConstantOwner = pending.Owner, FoldingEnum = null,
               }))
        {
            PushScope();
            bound = BindExpression(declaration.Value);
            PopScope();
        }

        // A cycle found while binding has settled this one already.
        if (!_pendingConstants.Remove(constant)) return;

        if (FoldConstant(bound) is not { } folded)
        {
            _unfoldedConstants.Add(constant);
            return;
        }

        // A constant is held in a word.
        if (folded.Value is BigInteger wide && (wide < long.MinValue || wide > ulong.MaxValue))
        {
            diagnostics.Report(Codes.ConstantOutOfRange, declaration.Value.Span,
                $"{wide} needs more than 64 bits, and a constant holds at most that many");
            _unfoldedConstants.Add(constant);
            return;
        }

        if (declaration.Type is null)
        {
            constant.Type = folded.Type;
            constant.Value = RepresentFolded(folded);
            return;
        }

        // A C string or a String is the text, as a literal's is.
        if (folded.Value is string text && IsConstantStringType(constant.Type))
        {
            constant.Value = text;
            return;
        }

        var span = declaration.Value.Span;
        switch (BindConversion(BuildFoldedExpression(folded, span), constant.Type, span))
        {
            case BoundLiteral literal:
                constant.Value = literal.Value;
                break;
            case BoundStringLiteral written:
                constant.Value = written.Value;
                break;
            case BoundErrorExpression:
                _unfoldedConstants.Add(constant);
                break;
            default:
                diagnostics.Report(Codes.ConstValueTypeMismatch, span,
                    $"'{constant.Name}' is declared '{constant.Type.Name}', and this is a " +
                    $"'{folded.Type.Name}' that does not become one on its own; add a cast",
                    constant.Type);
                _unfoldedConstants.Add(constant);
                break;
        }
    }

    /// <summary>
    /// Gives an enum's members their values if one of them is an expression.
    /// A member's value may name the members before it, with or without the
    /// enum's name, and a member after it is a value that depends on itself.
    /// </summary>
    private void EnsureEnumFolded(EnumTypeSymbol type)
    {
        if (!_pendingEnums.TryGetValue(type, out var pending) || pending.InProgress) return;
        pending.InProgress = true;

        var underlying = type.UnderlyingType;
        ulong next = 0;

        for (int i = 0; i < pending.Members.Count; i++)
        {
            var (member, syntax) = pending.Members[i];
            ulong value = next;

            if (syntax is not null)
            {
                if (FoldEnumValue(syntax, underlying) is { } literal)
                    value = literal;
                else if (FoldEnumMember(type, i, pending.Scope, syntax) is { } folded)
                    value = folded;
            }

            member.Value = value;
            next = value + 1;
            pending.Folded = i + 1;
        }

        _pendingEnums.Remove(type);
    }

    /// <summary>One member's value from its expression, as the underlying type's bits.</summary>
    private ulong? FoldEnumMember(EnumTypeSymbol type, int index, FileScope scope, ExpressionSyntax syntax)
    {
        BoundExpression bound;
        using (Enter(_context.ForBody(null) with
               {
                   File = scope, ConstantOwner = null, FoldingEnum = type, FoldedEnumMembers = index,
               }))
        {
            PushScope();
            bound = BindExpression(syntax);
            PopScope();
        }

        if (FoldConstant(bound) is not { } folded) return null;

        var underlying = type.UnderlyingType;
        if (folded.Value is not BigInteger number)
        {
            diagnostics.Report(Codes.EnumValueNotConstant, syntax.Span,
                $"the value of '{type.Name}.{type.Members[index].Name}' must be an integer " +
                $"constant, and this is a '{folded.Type.Name}'",
                type);
            return null;
        }

        if (!FitsInteger(number, underlying.Bits, underlying.IsSigned))
        {
            diagnostics.Report(Codes.ConstantOutOfRange, syntax.Span,
                $"{number} does not fit in '{underlying.Name}', which '{type.Name}' is built on",
                type);
            return null;
        }

        return EnumBits(number, underlying);
    }

    /// <summary>
    /// An enum value as a member holds it: only the bits the underlying type
    /// has, so a negative one in a narrow type is not sign-extended.
    /// </summary>
    private static ulong EnumBits(BigInteger value, PrimitiveTypeSymbol underlying) =>
        (ulong)WrapInteger(value, Math.Min(underlying.Bits, 64), signed: false);

    /// <summary>
    /// Whether a member may be read now: always, unless its enum is being
    /// folded and has not reached it, which reports the cycle.
    /// </summary>
    private bool IsEnumMemberReady(EnumTypeSymbol type, EnumMemberSymbol member, SourceSpan span)
    {
        EnsureEnumFolded(type);
        if (!_pendingEnums.TryGetValue(type, out var pending)) return true;

        int index = pending.Members.FindIndex(m => ReferenceEquals(m.Member, member));
        if (index < 0 || index < pending.Folded) return true;

        diagnostics.Report(Codes.ConstantDependsOnItself, span,
            $"'{type.Name}.{member.Name}' is not worked out yet here: an enum member's value " +
            "may name the members before it, and this one comes at or after it",
            type);
        return false;
    }

    /// <summary>An earlier member of the enum being folded, named without the enum.</summary>
    private EnumMemberSymbol? FindEarlierEnumMember(EnumTypeSymbol type, string name)
    {
        for (int i = 0; i < _context.FoldedEnumMembers && i < type.Members.Count; i++)
            if (type.Members[i].Name == name)
                return type.Members[i];
        return null;
    }

    /// <summary>
    /// An inline array's length written as an expression, or null. Answers
    /// <paramref name="reported"/> when it has said why itself.
    /// </summary>
    private long? FoldConstantLength(ExpressionSyntax syntax, FileScope scope, out bool reported)
    {
        reported = false;
        BoundExpression bound;
        using (Enter(_context.ForBody(null) with { File = scope, ConstantOwner = null, FoldingEnum = null }))
        {
            PushScope();
            bound = BindExpression(syntax);
            PopScope();
        }

        var folded = EvaluateConstant(bound, out var stop);
        if (folded is null)
        {
            reported = stop is null;
            return null;
        }
        return folded.Value.Value is BigInteger number && number >= long.MinValue && number <= long.MaxValue
            ? (long)number
            : null;
    }

    /// <summary>
    /// A case label's bits: what <see cref="FoldSwitchLabel"/> reads, or a
    /// constant expression folded to the same shape.
    /// </summary>
    private ulong? FoldCaseLabel(BoundExpression bound)
    {
        if (FoldSwitchLabel(bound) is { } bits) return bits;
        if (EvaluateConstant(bound, out _) is not { Value: BigInteger number } folded) return null;
        return folded.Type is EnumTypeSymbol enumType
            ? EnumBits(number, enumType.UnderlyingType)
            : (ulong)WrapInteger(number, 64, signed: false);
    }

    // ------------------------------------------------------------- evaluating

    /// <summary>
    /// The value of a bound expression made only of constants, or null after
    /// saying why not.
    /// </summary>
    private FoldedValue? FoldConstant(BoundExpression expression)
    {
        var folded = EvaluateConstant(expression, out var stop);
        if (folded is null && stop is not null)
            diagnostics.Report(Codes.InvalidConstantInitializer, stop.Span,
                "a constant is worked out before the program runs, and this is worked out " +
                "while it runs; a constant expression is made of literals, constants, enum " +
                "members, and the operators and casts between them");
        return folded;
    }

    /// <summary>
    /// Evaluates an expression. Null with <paramref name="stop"/> set names the
    /// part that is not constant; null with it unset means a diagnostic has
    /// been reported already.
    /// </summary>
    private FoldedValue? EvaluateConstant(BoundExpression expression, out BoundExpression? stop)
    {
        stop = null;
        switch (expression)
        {
            case BoundErrorExpression:
                return null;

            case BoundStringLiteral text:
                return new FoldedValue(text.Type, text.Value);

            case BoundLiteral or BoundConstantAccess:
                return ReadConstantLeaf(expression, out stop);

            case BoundDefault zero:
                return ZeroOf(zero.Type) is { } nothing ? new FoldedValue(zero.Type, nothing) : Stop(zero, out stop);

            case BoundConditional choice:
            {
                if (EvaluateConstant(choice.Condition, out stop) is not { Value: bool condition })
                    return null;
                return EvaluateConstant(condition ? choice.WhenTrue : choice.WhenFalse, out stop);
            }

            case BoundUnary unary:
                return EvaluateUnary(unary, out stop);

            case BoundBinary binary:
                return EvaluateBinary(binary, out stop);

            case BoundConversion conversion:
                return EvaluateConversion(conversion, out stop);

            case BoundCall call when ReferenceEquals(call.Function, _builtins.StringConcat) &&
                                     call.Arguments.Count == 2:
            {
                if (EvaluateConstant(call.Arguments[0], out stop) is not { Value: string left }) return null;
                if (EvaluateConstant(call.Arguments[1], out stop) is not { Value: string right }) return null;
                return new FoldedValue(call.Type, left + right);
            }

            default:
                return Stop(expression, out stop);
        }
    }

    private static FoldedValue? Stop(BoundExpression at, out BoundExpression? stop)
    {
        stop = at;
        return null;
    }

    /// <summary>A literal, a named constant or an enum member, read as a value.</summary>
    private FoldedValue? ReadConstantLeaf(BoundExpression leaf, out BoundExpression? stop)
    {
        stop = null;
        (object? value, TypeSymbol type) = leaf switch
        {
            BoundLiteral literal => (literal.Value, literal.Type),
            BoundConstantAccess named => (named.Constant.Value, named.Constant.Type),
            _ => ((object?)null, leaf.Type),
        };

        if (leaf is BoundConstantAccess { Constant: var constant })
        {
            EnsureConstantFolded(constant);
            if (_unfoldedConstants.Contains(constant)) return null;
            value = constant.Value;
            type = constant.Type;
        }

        switch (value)
        {
            case bool truth:
                return new FoldedValue(type, truth);
            case double number:
                return new FoldedValue(type, number);
            case float number:
                return new FoldedValue(type, (double)number);
            case string text:
                return new FoldedValue(type, text);
            case int scalar when IntegerShape(type) is not null:
                return new FoldedValue(type, new BigInteger(scalar));
            case ulong bits when type is EnumTypeSymbol enumType:
                return new FoldedValue(type,
                    WrapInteger(bits, enumType.UnderlyingType.Bits, enumType.UnderlyingType.IsSigned));
            case ulong when IntegerLiteral(leaf) is { } written:
                return new FoldedValue(type,
                    written.Negative ? -new BigInteger(written.Magnitude) : new BigInteger(written.Magnitude));
            default:
                return Stop(leaf, out stop);
        }
    }

    private FoldedValue? EvaluateUnary(BoundUnary unary, out BoundExpression? stop)
    {
        if (EvaluateConstant(unary.Operand, out stop) is not { } operand) return null;

        switch (unary.Operator)
        {
            case BoundUnaryOp.LogicalNot when operand.Value is bool truth:
                return new FoldedValue(unary.Type, !truth);

            case BoundUnaryOp.Negate when operand.Value is double number:
                return FloatResult(unary.Type, -number);

            case BoundUnaryOp.Negate when operand.Value is BigInteger number:
                return CheckedInteger(unary, unary.Type, -number);

            case BoundUnaryOp.BitwiseNot when operand.Value is BigInteger number &&
                                              IntegerShape(unary.Type) is { } shape:
                return new FoldedValue(unary.Type, WrapInteger(~number, shape.Bits, shape.Signed));

            default:
                return Stop(unary, out stop);
        }
    }

    private FoldedValue? EvaluateBinary(BoundBinary binary, out BoundExpression? stop)
    {
        if (EvaluateConstant(binary.Left, out stop) is not { } left) return null;
        if (EvaluateConstant(binary.Right, out stop) is not { } right) return null;
        var op = binary.Operator;

        if (left.Value is bool a && right.Value is bool b)
        {
            bool? answer = op switch
            {
                BoundBinaryOp.LogicalAnd or BoundBinaryOp.BitAnd => a && b,
                BoundBinaryOp.LogicalOr or BoundBinaryOp.BitOr => a || b,
                BoundBinaryOp.BitXor or BoundBinaryOp.NotEqual => a != b,
                BoundBinaryOp.Equal => a == b,
                _ => null,
            };
            return answer is { } truth ? new FoldedValue(binary.Type, truth) : Stop(binary, out stop);
        }

        if (left.Value is string first && right.Value is string second &&
            op is BoundBinaryOp.Equal or BoundBinaryOp.NotEqual)
            return new FoldedValue(binary.Type, (first == second) == (op == BoundBinaryOp.Equal));

        if (left.Value is double x && right.Value is double y)
        {
            return op switch
            {
                BoundBinaryOp.Add => FloatResult(binary.Type, x + y),
                BoundBinaryOp.Subtract => FloatResult(binary.Type, x - y),
                BoundBinaryOp.Multiply => FloatResult(binary.Type, x * y),
                BoundBinaryOp.Divide => FloatResult(binary.Type, x / y),
                BoundBinaryOp.Remainder => FloatResult(binary.Type, x % y),
                BoundBinaryOp.Equal => new FoldedValue(binary.Type, x == y),
                BoundBinaryOp.NotEqual => new FoldedValue(binary.Type, x != y),
                BoundBinaryOp.Less => new FoldedValue(binary.Type, x < y),
                BoundBinaryOp.LessEqual => new FoldedValue(binary.Type, x <= y),
                BoundBinaryOp.Greater => new FoldedValue(binary.Type, x > y),
                BoundBinaryOp.GreaterEqual => new FoldedValue(binary.Type, x >= y),
                _ => Stop(binary, out stop),
            };
        }

        if (left.Value is not BigInteger m || right.Value is not BigInteger n)
            return Stop(binary, out stop);

        switch (op)
        {
            case BoundBinaryOp.Equal: return new FoldedValue(binary.Type, m == n);
            case BoundBinaryOp.NotEqual: return new FoldedValue(binary.Type, m != n);
            case BoundBinaryOp.Less: return new FoldedValue(binary.Type, m < n);
            case BoundBinaryOp.LessEqual: return new FoldedValue(binary.Type, m <= n);
            case BoundBinaryOp.Greater: return new FoldedValue(binary.Type, m > n);
            case BoundBinaryOp.GreaterEqual: return new FoldedValue(binary.Type, m >= n);
        }

        if (IntegerShape(binary.Type) is not { } shape) return Stop(binary, out stop);

        switch (op)
        {
            case BoundBinaryOp.Add: return CheckedInteger(binary, binary.Type, m + n);
            case BoundBinaryOp.Subtract: return CheckedInteger(binary, binary.Type, m - n);
            case BoundBinaryOp.Multiply: return CheckedInteger(binary, binary.Type, m * n);

            case BoundBinaryOp.Divide:
            case BoundBinaryOp.Remainder:
                if (n.IsZero)
                {
                    diagnostics.Report(Codes.ConstantDivisionByZero, binary.Span,
                        op == BoundBinaryOp.Divide ? "division by zero" : "the remainder of a division by zero");
                    return null;
                }
                // Truncated toward zero, and the remainder takes the dividend's
                // sign, as the processor's instruction does.
                return CheckedInteger(binary, binary.Type,
                    op == BoundBinaryOp.Divide ? BigInteger.Divide(m, n) : BigInteger.Remainder(m, n));

            case BoundBinaryOp.BitAnd: return new FoldedValue(binary.Type, WrapInteger(m & n, shape.Bits, shape.Signed));
            case BoundBinaryOp.BitOr: return new FoldedValue(binary.Type, WrapInteger(m | n, shape.Bits, shape.Signed));
            case BoundBinaryOp.BitXor: return new FoldedValue(binary.Type, WrapInteger(m ^ n, shape.Bits, shape.Signed));

            // The count is reduced modulo the width, as the emitted shift is.
            case BoundBinaryOp.ShiftLeft:
            case BoundBinaryOp.ShiftRight:
            case BoundBinaryOp.UnsignedShiftRight:
            {
                int count = (int)(WrapInteger(n, 64, signed: false) % shape.Bits);
                BigInteger shifted = op switch
                {
                    BoundBinaryOp.ShiftLeft => m << count,
                    BoundBinaryOp.ShiftRight => m >> count,
                    _ => WrapInteger(m, shape.Bits, signed: false) >> count,
                };
                return new FoldedValue(binary.Type, WrapInteger(shifted, shape.Bits, shape.Signed));
            }

            default:
                return Stop(binary, out stop);
        }
    }

    private FoldedValue? EvaluateConversion(BoundConversion conversion, out BoundExpression? stop)
    {
        if (EvaluateConstant(conversion.Operand, out stop) is not { } operand) return null;
        var target = conversion.Type;

        switch (conversion.Kind)
        {
            case ConversionKind.Identity:
            case ConversionKind.IntegerWiden:
            case ConversionKind.IntegerNarrow:
                if (operand.Value is BigInteger integral && IntegerShape(target) is { } width)
                    return new FoldedValue(target, WrapInteger(integral, width.Bits, width.Signed));
                return conversion.Kind == ConversionKind.Identity
                    ? operand with { Type = target }
                    : Stop(conversion, out stop);

            case ConversionKind.BoolToInteger when operand.Value is bool truth:
                return new FoldedValue(target, truth ? BigInteger.One : BigInteger.Zero);

            case ConversionKind.IntToFloat when operand.Value is BigInteger whole:
                return FloatResult(target, (double)whole);

            case ConversionKind.FloatResize when operand.Value is double number:
                return FloatResult(target, number);

            case ConversionKind.FloatToInt when operand.Value is double number &&
                                                IntegerShape(target) is { } shape:
            {
                if (double.IsNaN(number) || double.IsInfinity(number) ||
                    !FitsInteger(new BigInteger(Math.Truncate(number)), shape.Bits, shape.Signed))
                {
                    diagnostics.Report(Codes.ConstantOutOfRange, conversion.Span,
                        $"{number} does not fit in '{target.Name}', so it cannot become one",
                        target);
                    return null;
                }
                return new FoldedValue(target, new BigInteger(Math.Truncate(number)));
            }

            default:
                return Stop(conversion, out stop);
        }
    }

    /// <summary>An integer result, refused when its type cannot hold it.</summary>
    private FoldedValue? CheckedInteger(BoundExpression at, TypeSymbol type, BigInteger value)
    {
        if (IntegerShape(type) is not { } shape) return null;
        if (FitsInteger(value, shape.Bits, shape.Signed)) return new FoldedValue(type, value);

        diagnostics.Report(Codes.ConstantExpressionOverflow, at.Span,
            $"this is {value}, which does not fit in '{type.Name}'; a constant is checked where " +
            "a value worked out at run time would wrap, so the overflow is an error. Make the " +
            "operands a wider type, or cast the result",
            type);
        return null;
    }

    private static FoldedValue FloatResult(TypeSymbol type, double value) =>
        new(type, type is PrimitiveTypeSymbol { Kind: PrimitiveKind.Float } ? (double)(float)value : value);

    /// <summary>The width and signedness of an integer, a code unit or an enum's underlying type.</summary>
    private static (int Bits, bool Signed)? IntegerShape(TypeSymbol type) => type switch
    {
        PrimitiveTypeSymbol { IsInteger: true } integer => (integer.Bits, integer.IsSigned),
        EnumTypeSymbol enumType => (enumType.UnderlyingType.Bits, enumType.UnderlyingType.IsSigned),
        _ => null,
    };

    private static bool FitsInteger(BigInteger value, int bits, bool signed) =>
        signed
            ? value >= -(BigInteger.One << (bits - 1)) && value < BigInteger.One << (bits - 1)
            : value >= 0 && value < BigInteger.One << bits;

    /// <summary>A value cut to <paramref name="bits"/> bits, as the type holding them reads them.</summary>
    private static BigInteger WrapInteger(BigInteger value, int bits, bool signed)
    {
        var size = BigInteger.One << bits;
        var kept = value & (size - 1);
        return signed && kept >= size >> 1 ? kept - size : kept;
    }

    private object? ZeroOf(TypeSymbol type) => type switch
    {
        PrimitiveTypeSymbol { Kind: PrimitiveKind.Bool } => false,
        PrimitiveTypeSymbol { IsFloat: true } => 0.0,
        _ when IntegerShape(type) is not null => BigInteger.Zero,
        _ => null,
    };

    /// <summary>
    /// A folded value as a constant symbol holds it: an integer as its two's
    /// complement in a <c>ulong</c>, a code unit as its scalar, a float as a
    /// <c>float</c>.
    /// </summary>
    private static object RepresentFolded(FoldedValue folded) => folded.Value switch
    {
        BigInteger number when folded.Type is EnumTypeSymbol enumType => EnumBits(number, enumType.UnderlyingType),
        BigInteger scalar when folded.Type is PrimitiveTypeSymbol { IsCodeUnit: true } => (int)scalar,
        BigInteger number => (ulong)WrapInteger(number, 64, signed: false),
        double number when folded.Type is PrimitiveTypeSymbol { Kind: PrimitiveKind.Float } => (float)number,
        var other => other,
    };

    /// <summary>
    /// A folded value as the expression a person would have written for it, so
    /// the ordinary conversion to the declared type checks its range: a
    /// negative integer is a minus over its magnitude, as the parser makes one.
    /// </summary>
    private BoundExpression BuildFoldedExpression(FoldedValue folded, SourceSpan span)
    {
        var type = folded.Type;
        switch (folded.Value)
        {
            case BigInteger number when type is EnumTypeSymbol enumType:
                return new BoundLiteral(span, type, EnumBits(number, enumType.UnderlyingType));
            case BigInteger scalar when type is PrimitiveTypeSymbol { IsCodeUnit: true }:
                return new BoundLiteral(span, type, (int)scalar);
            case BigInteger number when number.Sign < 0:
                return new BoundUnary(span, type, BoundUnaryOp.Negate,
                    new BoundLiteral(span, type, (ulong)(-number)));
            case BigInteger number:
                return new BoundLiteral(span, type, (ulong)number);
            case double number when type is PrimitiveTypeSymbol { Kind: PrimitiveKind.Float }:
                return new BoundLiteral(span, type, (float)number);
            case string text:
                return new BoundStringLiteral(span, type, text);
            default:
                return new BoundLiteral(span, type, folded.Value);
        }
    }
}
