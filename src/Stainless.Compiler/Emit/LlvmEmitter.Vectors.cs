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

using System.Globalization;
using Stainless.Binding;

namespace Stainless.Emit;

// SIMD vectors: LLVM's own vector instructions, which every target lowers to
// what it has -- SSE, NEON, or one lane at a time.
public sealed partial class LlvmEmitter
{
    /// <summary>A constant vector with every lane <paramref name="lane"/>.</summary>
    private static string SplatConstant(VectorTypeSymbol vector, string lane)
    {
        string element = LlvmTypeOf(vector.Element);
        return "<" + string.Join(", ", Enumerable.Repeat($"{element} {lane}", vector.Lanes)) + ">";
    }

    /// <summary>A shuffle mask, spelled as LLVM wants one: <c>&lt;2 x i32&gt; &lt;i32 2, i32 0&gt;</c>.</summary>
    private static string Mask(IEnumerable<int> lanes)
    {
        var cells = lanes.Select(lane => lane < 0 ? "i32 poison" : $"i32 {lane}").ToList();
        return $"<{cells.Count} x i32> <{string.Join(", ", cells)}>";
    }

    private Val EmitVectorNew(BoundVectorNew made)
    {
        var vector = made.Vector;
        string type = LlvmTypeOf(vector);
        string element = LlvmTypeOf(vector.Element);

        if (made.Parts.Count == 0) return new Val("zeroinitializer", type, vector);

        if (made.Parts is [var only] && only.Type is not VectorTypeSymbol)
        {
            var lane = EmitExpression(only);
            string first = Emit(type, $"insertelement {type} poison, {element} {lane.Ref}, i32 0");
            return new Val(
                Emit(type, $"shufflevector {type} {first}, {type} poison, <{vector.Lanes} x i32> zeroinitializer"),
                type, vector);
        }

        string built = "poison";
        int at = 0;
        foreach (var part in made.Parts)
        {
            var value = EmitExpression(part);
            if (part.Type is VectorTypeSymbol given)
            {
                for (int i = 0; i < given.Lanes; i++)
                {
                    string lane = Emit(element, $"extractelement {value.LlvmType} {value.Ref}, i32 {i}");
                    built = Emit(type, $"insertelement {type} {built}, {element} {lane}, i32 {at++}");
                }
                continue;
            }

            built = Emit(type, $"insertelement {type} {built}, {element} {value.Ref}, i32 {at++}");
        }

        return new Val(built, type, vector);
    }

    private Val EmitVectorShuffle(BoundVectorShuffle shuffle)
    {
        var source = EmitExpression(shuffle.Vector);
        string type = LlvmTypeOf(shuffle.Type);
        return new Val(
            Emit(type, $"shufflevector {source.LlvmType} {source.Ref}, {source.LlvmType} poison, {Mask(shuffle.Lanes)}"),
            type, shuffle.Type);
    }

    /// <summary>
    /// <c>v.xy = p</c>: the vector is reached once, the value worked out, and
    /// then the vector read, merged and written, so a value that reads the
    /// vector sees it as it was.
    /// </summary>
    private Val EmitSwizzleAssignment(BoundSwizzleAssignment written)
    {
        var target = written.Target;
        var whole = (VectorTypeSymbol)target.Vector.Type;
        string wholeType = LlvmTypeOf(whole);

        string address = EmitAddress(target.Vector);
        var value = EmitExpression(written.Value);

        // The value widened to the whole vector's lanes, then each named lane
        // taken from it and every other from the vector as it was.
        int count = target.Lanes.Count;
        string widened = Emit(wholeType,
            $"shufflevector {value.LlvmType} {value.Ref}, {value.LlvmType} poison, " +
            Mask(Enumerable.Range(0, whole.Lanes).Select(i => i < count ? i : -1)));

        var merge = Enumerable.Range(0, whole.Lanes).ToArray();
        for (int k = 0; k < count; k++)
            merge[target.Lanes[k]] = whole.Lanes + k;

        string old = Emit(wholeType, $"load {wholeType}, ptr {address}{AlignedFor(whole)}");
        string merged = Emit(wholeType, $"shufflevector {wholeType} {old}, {wholeType} {widened}, {Mask(merge)}");
        Line($"store {wholeType} {merged}, ptr {address}{AlignedFor(whole)}");
        return value;
    }

    /// <summary>
    /// The address of one lane. A vector's lanes lie end to end in memory as an
    /// array's elements do, so this is the inline array's bounds check and an
    /// element pointer.
    /// </summary>
    private string EmitVectorLaneAddress(BoundIndex index, VectorTypeSymbol vector)
    {
        string address = EmitAddress(index.Target);
        var offset = EmitExpression(index.Index);

        string lanes = vector.Lanes.ToString(CultureInfo.InvariantCulture);
        var position = PositionOf(offset, index.Origin, lanes);
        string widened = position.Index;
        string inRange = Emit("i1", $"icmp ult {Word} {widened}, {lanes}");

        string okLabel = NextLabel("bounds.ok");
        string failLabel = NextLabel("bounds.fail");
        Terminator($"br i1 {inRange}, label %{okLabel}, label %{failLabel}");

        Label(failLabel);
        FailPosition(position, lanes);
        Terminator("unreachable");

        Label(okLabel);
        return Emit("ptr",
            $"getelementptr inbounds {LlvmTypeOf(vector.Element)}, ptr {address}, {Word} {widened}");
    }

    /// <summary>A lane of a vector with no storage, named by a constant: no address to make.</summary>
    private Val? TryEmitLaneOfValue(BoundIndex index)
    {
        if (index.Target.Type is not VectorTypeSymbol || index.Target.IsLValue ||
            index.Index is not BoundLiteral { Value: ulong lane })
            return null;

        var source = EmitExpression(index.Target);
        string element = LlvmTypeOf(index.Type);
        return new Val(
            Emit(element, $"extractelement {source.LlvmType} {source.Ref}, i32 {lane}"), element, index.Type);
    }

    private Val EmitVectorUnary(BoundUnary unary, VectorTypeSymbol vector)
    {
        var operand = EmitExpression(unary.Operand);
        string type = operand.LlvmType;
        string instruction = unary.Operator switch
        {
            BoundUnaryOp.Negate when vector.Element.IsFloat => $"fneg {type} {operand.Ref}",
            BoundUnaryOp.Negate => $"sub {type} zeroinitializer, {operand.Ref}",
            _ => $"xor {type} {operand.Ref}, {SplatConstant(vector, "-1")}",
        };
        return new Val(Emit(type, instruction), type, unary.Type);
    }

    /// <summary>
    /// A vector operator. Arithmetic wraps lane by lane, as SIMD does. Equality
    /// answers for every lane: equal when each lane is, unequal when any is not.
    /// </summary>
    private Val EmitVectorBinary(BoundBinary binary, VectorTypeSymbol vector)
    {
        var left = EmitExpression(binary.Left);
        var right = EmitExpression(binary.Right);

        bool isFloat = vector.Element.IsFloat;
        bool signed = vector.Element.IsSigned;
        string type = left.LlvmType;
        string bits = $"<{vector.Lanes} x i1>";

        if (binary.Operator is BoundBinaryOp.Equal or BoundBinaryOp.NotEqual)
        {
            bool equal = binary.Operator == BoundBinaryOp.Equal;
            string compare = equal ? isFloat ? "fcmp oeq" : "icmp eq" : isFloat ? "fcmp une" : "icmp ne";
            string lanes = Emit(bits, $"{compare} {type} {left.Ref}, {right.Ref}");
            return new Val(ReduceLanes(equal ? "and" : "or", vector.Lanes, lanes), "i1", PrimitiveTypeSymbol.Bool);
        }

        string opcode = binary.Operator switch
        {
            BoundBinaryOp.Add => isFloat ? "fadd" : "add",
            BoundBinaryOp.Subtract => isFloat ? "fsub" : "sub",
            BoundBinaryOp.Multiply => isFloat ? "fmul" : "mul",
            BoundBinaryOp.Divide => isFloat ? "fdiv" : signed ? "sdiv" : "udiv",
            BoundBinaryOp.Remainder => isFloat ? "frem" : signed ? "srem" : "urem",
            BoundBinaryOp.BitAnd => "and",
            BoundBinaryOp.BitOr => "or",
            BoundBinaryOp.BitXor => "xor",
            BoundBinaryOp.ShiftLeft => "shl",
            BoundBinaryOp.UnsignedShiftRight => "lshr",
            _ => signed ? "ashr" : "lshr",
        };

        if (!isFloat && binary.Operator is BoundBinaryOp.Divide or BoundBinaryOp.Remainder)
            GuardVectorDivision(vector, left.Ref, right.Ref);

        string operand = right.Ref;
        if (binary.Operator is BoundBinaryOp.ShiftLeft or BoundBinaryOp.ShiftRight or BoundBinaryOp.UnsignedShiftRight)
            operand = Emit(type, $"and {type} {right.Ref}, {SplatConstant(vector, (vector.Element.Bits - 1).ToString(CultureInfo.InvariantCulture))}");

        return new Val(Emit(type, $"{opcode} {type} {left.Ref}, {operand}"), type, binary.Type);
    }

    /// <summary>
    /// A vector's built-in function. Each is an LLVM intrinsic or a few vector
    /// instructions, which every target lowers to what it has.
    /// </summary>
    private Val EmitVectorFunction(BoundVectorFunction called)
    {
        var vector = called.Vector;
        string type = LlvmTypeOf(vector);
        string lane = LlvmTypeOf(vector.Element);
        bool isFloat = vector.Element.IsFloat;
        bool signed = vector.Element.IsSigned;
        string suffix = OverloadSuffix(type);
        var arguments = called.Arguments.Select(a => EmitExpression(a).Ref).ToList();

        string Unary(string name, string value) => CallIntrinsic($"llvm.{name}.{suffix}", type, (type, value));
        string Binary(string name, string left, string right) =>
            CallIntrinsic($"llvm.{name}.{suffix}", type, (type, left), (type, right));
        string Lowest(string left, string right) =>
            Binary(isFloat ? "minnum" : signed ? "smin" : "umin", left, right);
        string Highest(string left, string right) =>
            Binary(isFloat ? "maxnum" : signed ? "smax" : "umax", left, right);
        string Arithmetic(string floating, string integer, string left, string right) =>
            Emit(type, $"{(isFloat ? floating : integer)} {type} {left}, {right}");

        // Added in lane order, from negative zero for floats, which is the
        // sum a loop over the lanes would give.
        string Total(string value) => isFloat
            ? CallIntrinsic($"llvm.vector.reduce.fadd.{suffix}", lane, (lane, "0x8000000000000000"), (type, value))
            : CallIntrinsic($"llvm.vector.reduce.add.{suffix}", lane, (type, value));
        string DotOf(string left, string right) => Total(Arithmetic("fmul", "mul", left, right));
        string LengthOf(string value) =>
            CallIntrinsic($"llvm.sqrt.{OverloadSuffix(lane)}", lane, (lane, DotOf(value, value)));

        string Compared(string floating, string integer)
        {
            string bits = Emit($"<{vector.Lanes} x i1>",
                $"{(isFloat ? "fcmp " + floating : "icmp " + integer)} {type} {arguments[0]}, {arguments[1]}");
            return Emit(LlvmTypeOf(vector.MaskType), $"sext <{vector.Lanes} x i1> {bits} to {LlvmTypeOf(vector.MaskType)}");
        }

        string Ordered(string floating, string signedCompare, string unsignedCompare) =>
            Compared(floating, signed ? signedCompare : unsignedCompare);

        string result = called.Function switch
        {
            VectorFunction.Dot => DotOf(arguments[0], arguments[1]),
            VectorFunction.Sum => Total(arguments[0]),
            VectorFunction.LengthSquared => DotOf(arguments[0], arguments[0]),
            VectorFunction.Length => LengthOf(arguments[0]),
            VectorFunction.Distance => LengthOf(Arithmetic("fsub", "sub", arguments[0], arguments[1])),
            VectorFunction.Normalize => Emit(type,
                $"fdiv {type} {arguments[0]}, {Splat(vector, LengthOf(arguments[0]))}"),
            VectorFunction.Cross => Cross(type, arguments[0], arguments[1]),
            VectorFunction.Min => Lowest(arguments[0], arguments[1]),
            VectorFunction.Max => Highest(arguments[0], arguments[1]),
            VectorFunction.Clamp => Lowest(Highest(arguments[0], arguments[1]), arguments[2]),
            VectorFunction.Abs => isFloat
                ? Unary("fabs", arguments[0])
                : CallIntrinsic($"llvm.abs.{suffix}", type, (type, arguments[0]), ("i1", "false")),
            VectorFunction.Sqrt => Unary("sqrt", arguments[0]),
            VectorFunction.Floor => Unary("floor", arguments[0]),
            VectorFunction.Ceiling => Unary("ceil", arguments[0]),
            VectorFunction.Round => Unary("roundeven", arguments[0]),
            VectorFunction.Truncate => Unary("trunc", arguments[0]),
            VectorFunction.FusedMultiplyAdd => CallIntrinsic($"llvm.fma.{suffix}", type,
                (type, arguments[0]), (type, arguments[1]), (type, arguments[2])),
            VectorFunction.Lerp => Emit(type, $"fadd {type} {arguments[0]}, " +
                Emit(type, $"fmul {type} {Emit(type, $"fsub {type} {arguments[1]}, {arguments[0]}")}, {arguments[2]}")),
            VectorFunction.Equal => Compared("oeq", "eq"),
            VectorFunction.NotEqual => Compared("une", "ne"),
            VectorFunction.LessThan => Ordered("olt", "slt", "ult"),
            VectorFunction.LessThanOrEqual => Ordered("ole", "sle", "ule"),
            VectorFunction.GreaterThan => Ordered("ogt", "sgt", "ugt"),
            VectorFunction.GreaterThanOrEqual => Ordered("oge", "sge", "uge"),
            VectorFunction.Select => Selected(vector, arguments[0], arguments[1], arguments[2]),
            VectorFunction.All => ReduceLanes("and", vector.Lanes,
                Emit($"<{vector.Lanes} x i1>", $"icmp ne {type} {arguments[0]}, zeroinitializer")),
            _ => ReduceLanes("or", vector.Lanes,
                Emit($"<{vector.Lanes} x i1>", $"icmp ne {type} {arguments[0]}, zeroinitializer")),
        };

        string resultType = LlvmTypeOf(called.Type);
        return new Val(result, resultType, called.Type);
    }

    /// <summary>Calls an LLVM intrinsic, declaring it once.</summary>
    private string CallIntrinsic(string name, string result, params (string Type, string Value)[] arguments)
    {
        _overflowIntrinsics.Add(
            $"declare {result} @{name}({string.Join(", ", arguments.Select(a => a.Type))}) " +
            "nounwind willreturn memory(none) speculatable");
        return Emit(result, $"call {result} @{name}({string.Join(", ", arguments.Select(a => $"{a.Type} {a.Value}"))})");
    }

    /// <summary>A vector with every lane <paramref name="lane"/>, worked out at run time.</summary>
    private string Splat(VectorTypeSymbol vector, string lane)
    {
        string type = LlvmTypeOf(vector);
        string first = Emit(type, $"insertelement {type} poison, {LlvmTypeOf(vector.Element)} {lane}, i32 0");
        return Emit(type, $"shufflevector {type} {first}, {type} poison, <{vector.Lanes} x i32> zeroinitializer");
    }

    /// <summary><c>a.yzx * b.zxy - a.zxy * b.yzx</c>.</summary>
    private string Cross(string type, string left, string right)
    {
        string Turned(string value, int a, int b, int c) =>
            Emit(type, $"shufflevector {type} {value}, {type} poison, {Mask([a, b, c])}");

        string first = Emit(type, $"fmul {type} {Turned(left, 1, 2, 0)}, {Turned(right, 2, 0, 1)}");
        string second = Emit(type, $"fmul {type} {Turned(left, 2, 0, 1)}, {Turned(right, 1, 2, 0)}");
        return Emit(type, $"fsub {type} {first}, {second}");
    }

    /// <summary>Each lane from <paramref name="whenSet"/> where the mask's is not zero, else from <paramref name="otherwise"/>.</summary>
    private string Selected(VectorTypeSymbol vector, string mask, string whenSet, string otherwise)
    {
        string type = LlvmTypeOf(vector);
        string maskType = LlvmTypeOf(vector.MaskType);
        string bits = Emit($"<{vector.Lanes} x i1>", $"icmp ne {maskType} {mask}, zeroinitializer");
        return Emit(type, $"select <{vector.Lanes} x i1> {bits}, {type} {whenSet}, {type} {otherwise}");
    }

    /// <summary>Whether all (<c>and</c>) or any (<c>or</c>) of a vector of bits is set.</summary>
    private string ReduceLanes(string how, int lanes, string bits)
    {
        string intrinsic = $"llvm.vector.reduce.{how}.v{lanes}i1";
        _overflowIntrinsics.Add($"declare i1 @{intrinsic}(<{lanes} x i1>) nounwind willreturn memory(none)");
        return Emit("i1", $"call i1 @{intrinsic}(<{lanes} x i1> {bits})");
    }

    /// <summary>
    /// The integer divisions LLVM leaves undefined, refused in any lane: a zero
    /// divisor, and the most negative value divided by -1.
    /// </summary>
    private void GuardVectorDivision(VectorTypeSymbol vector, string dividend, string divisor)
    {
        string type = LlvmTypeOf(vector);
        string bits = $"<{vector.Lanes} x i1>";

        string zeroLabel = NextLabel("div.zero");
        string liveLabel = NextLabel("div.live");
        string zeros = Emit(bits, $"icmp eq {type} {divisor}, zeroinitializer");
        Terminator($"br i1 {ReduceLanes("or", vector.Lanes, zeros)}, label %{zeroLabel}, label %{liveLabel}");

        Label(zeroLabel);
        Line("call void @sl_divide_by_zero()");
        Terminator("unreachable");

        Label(liveLabel);
        if (!vector.Element.IsSigned) return;

        string overflowLabel = NextLabel("div.overflow");
        string okLabel = NextLabel("div.ok");
        string element = LlvmTypeOf(vector.Element);
        string atMinimum = Emit(bits, $"icmp eq {type} {dividend}, {SplatConstant(vector, SmallestOf(element))}");
        string byNegativeOne = Emit(bits, $"icmp eq {type} {divisor}, {SplatConstant(vector, "-1")}");
        string overflows = Emit(bits, $"and {bits} {atMinimum}, {byNegativeOne}");
        Terminator($"br i1 {ReduceLanes("or", vector.Lanes, overflows)}, label %{overflowLabel}, label %{okLabel}");

        Label(overflowLabel);
        Line("call void @sl_divide_overflow()");
        Terminator("unreachable");

        Label(okLabel);
    }
}
