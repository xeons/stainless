// Stainless - an experimental systems language.
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
using System.Text;
using Stainless.Binding;
using Stainless.Syntax;

namespace Stainless.Emit;

/// <summary>
/// Conversions, arithmetic, comparison, the short-circuiting operators
/// and the conditional.
///
/// The division guards are here: a signed overflow and a division by
/// zero are undefined in LLVM, so both are checked rather than emitted
/// and hoped for.
/// </summary>
public sealed partial class LlvmEmitter
{
    private Val EmitConversion(BoundConversion conversion)
    {
        var operand = EmitExpression(conversion.Operand);
        string to = LlvmTypeOf(conversion.Type);
        string from = operand.LlvmType;

        switch (conversion.Kind)
        {
            case ConversionKind.Identity:
            case ConversionKind.PointerCast:
            case ConversionKind.NullToReference:
            case ConversionKind.ClassToInterface:

            // A checked optional is the same pointer; what a check bought is
            // the compiler's permission, and permission has no instructions.
            case ConversionKind.NarrowOptional:

            // A base subobject starts where the object does, so a reference to
            // the derived class already is a reference to the base one. This is
            // the whole benefit of single inheritance and the whole of its cost.
            case ConversionKind.Upcast:

            // Storing is what makes a reference weak: the slot's type sends the
            // store through sl_weak_retain instead of sl_retain. The value
            // itself is the same pointer either way.
            case ConversionKind.ReferenceToWeak:
                // An interface reference is the very same pointer; the vtable is
                // reached through the object's TypeInfo, not carried alongside it.
                return new Val(operand.Ref, to, conversion.Type);

            // Downwards the answer is not in the type, so it is asked of the
            // object. The pointer that comes back is the one that went in; what
            // the check buys is that it really points at one of those.
            case ConversionKind.Downcast:
            {
                var wanted = (ClassTypeSymbol)conversion.Type;

                string ok = Emit("i32",
                    $"call i32 @sl_is_instance(ptr {operand.Ref}, " +
                    $"ptr @{Mangler.TypeInfoSymbol(wanted)})");
                string held = Emit("i1", $"icmp ne i32 {ok}, 0");

                string good = NextLabel("cast.ok");
                string bad = NextLabel("cast.bad");

                Terminator($"br i1 {held}, label %{good}, label %{bad}");

                Label(bad);
                Line($"call void @sl_cast_failed(ptr {operand.Ref}, " +
                     $"ptr {InternBytes(wanted.QualifiedName)})");
                Terminator("unreachable");

                Label(good);
                return new Val(operand.Ref, to, conversion.Type);
            }

            // The pointer is unchanged; what changes is that ARC now owns
            // it. Tracked as a temporary, so the +1 COM handed over is dropped
            // at the end of the statement and what a variable keeps is the
            // reference its own store retained.
            case ConversionKind.ComAdopt:
                TrackTemporary(operand.Ref, conversion.Type);
                return new Val(operand.Ref, to, conversion.Type);

            // A COM vtable begins with its base's slots, so a derived
            // reference already answers the base's calls at the same address.
            // The class Upcast above is the same property seen from the object
            // side rather than the table side.
            case ConversionKind.ComUpcast:
                return new Val(operand.Ref, to, conversion.Type);

            // The address of the tear-off inside the object. One add, at an
            // offset the layout fixed -- the only COM conversion that is not
            // free, and it is not free because a COM pointer has to point at a
            // vtable pointer and a Stainless object starts with its header.
            case ConversionKind.ComTearOff:
            {
                var owner = (ClassTypeSymbol)conversion.Operand.Type;
                var presented = conversion.Type switch
                {
                    OptionalTypeSymbol optional => (ComInterfaceTypeSymbol)optional.Element,
                    var direct => (ComInterfaceTypeSymbol)direct,
                };

                // IUnknown is not in the list, and every com object answers to
                // it; the first tear-off is the canonical one, which is what
                // makes two IUnknown pointers to one object compare equal.
                int offset = owner.ComInterfaces.Contains(presented)
                    ? owner.TearOffOffset(presented)
                    : owner.TearOffsStart;

                return new Val(
                    Emit("ptr", $"getelementptr inbounds i8, ptr {operand.Ref}, i64 {offset}"),
                    to, conversion.Type);
            }

            // Downwards between com interfaces the answer is not the
            // compiler's: the object decides, in code that may not be ours. So
            // this is a QueryInterface, and what comes back is a reference the
            // caller owns rather than the pointer that went in.
            case ConversionKind.ComQuery:
            {
                var wanted = (ComInterfaceTypeSymbol)conversion.Type;

                string found = Emit("ptr",
                    $"call ptr @sl_com_query(ptr {operand.Ref}, ptr @{IidName(wanted)})");
                string held = Emit("i1", $"icmp ne ptr {found}, null");

                string good = NextLabel("qi.ok");
                string bad = NextLabel("qi.bad");

                Terminator($"br i1 {held}, label %{good}, label %{bad}");

                Label(bad);
                Line($"call void @sl_com_cast_failed(" +
                     $"ptr {InternBytes(conversion.Operand.Type.Name)}, " +
                     $"ptr {InternBytes(wanted.QualifiedName)})");
                Terminator("unreachable");

                Label(good);

                // QueryInterface answered at +1, so this is a temporary the
                // statement scope drops like any other.
                TrackTemporary(found, conversion.Type);
                return new Val(found, to, conversion.Type);
            }

            // The whole of an array, as a slice of it: offset zero, and the
            // length the array already knows. The array is retained into the
            // slice's field like anything a struct holds.
            case ConversionKind.ArrayToSlice:
            {
                var type = (SliceTypeSymbol)conversion.Type;
                string slot = Alloca(StructName(type), "whole");

                string lengthSlot = Emit("ptr",
                    $"getelementptr inbounds i8, ptr {operand.Ref}, " +
                    $"i64 {ArrayTypeSymbol.HeaderSize - 8}");
                string length = Emit("i64", $"load i64, ptr {lengthSlot}");

                Line($"store ptr {operand.Ref}, ptr {SliceField(slot, type, 0)}");
                Line($"store i64 0, ptr {SliceField(slot, type, 1)}");
                Line($"store i64 {length}, ptr {SliceField(slot, type, 2)}");
                Retain(operand.Ref, operand.Type);

                TrackTemporary(slot, type);
                return new Val(slot, "ptr", type);
            }

            case ConversionKind.StringLiteralToPointer:
                // Point at a plain byte array rather than into the object, so no
                // offset arithmetic is needed and the constant stays shareable.
                return new Val(
                    InternBytes(((BoundStringLiteral)conversion.Operand).Value), "ptr", conversion.Type);

            case ConversionKind.ReferenceToOptional:
                // A weak reference must be proven live before it can be used strongly.
                if (conversion.Operand.Type is WeakTypeSymbol)
                {
                    string loaded = Emit("ptr", $"call ptr @sl_weak_load(ptr {operand.Ref})");
                    TrackTemporary(loaded, conversion.Type);
                    return new Val(loaded, "ptr", conversion.Type);
                }
                return new Val(operand.Ref, to, conversion.Type);

            case ConversionKind.IntegerWiden:
                if (from == to) return new Val(operand.Ref, to, conversion.Type);
                return Converted(IsSigned(conversion.Operand.Type) ? "sext" : "zext");

            case ConversionKind.IntegerNarrow:
                if (from == to) return new Val(operand.Ref, to, conversion.Type);
                return Converted("trunc");

            case ConversionKind.IntToFloat:
                return Converted(IsSigned(conversion.Operand.Type) ? "sitofp" : "uitofp");

            case ConversionKind.FloatToInt:
                return Converted(IsSigned(conversion.Type) ? "fptosi" : "fptoui");

            case ConversionKind.FloatResize:
                if (from == to) return new Val(operand.Ref, to, conversion.Type);
                return Converted(to == "double" ? "fpext" : "fptrunc");

            case ConversionKind.PointerToInteger:
                return Converted("ptrtoint");

            case ConversionKind.IntegerToPointer:
                return Converted("inttoptr");

            case ConversionKind.BoolToInteger:
                return Converted("zext");

            default:
                return new Val(operand.Ref, to, conversion.Type);
        }

        Val Converted(string instruction) =>
            new(Emit(to, $"{instruction} {from} {operand.Ref} to {to}"), to, conversion.Type);
    }

    private Val EmitUnary(BoundUnary unary)
    {
        var operand = EmitExpression(unary.Operand);
        string llvmType = operand.LlvmType;

        string instruction = unary.Operator switch
        {
            BoundUnaryOp.Negate when unary.Type is PrimitiveTypeSymbol { IsFloat: true } =>
                $"fneg {llvmType} {operand.Ref}",
            BoundUnaryOp.Negate => $"sub {llvmType} 0, {operand.Ref}",
            BoundUnaryOp.LogicalNot => $"xor i1 {operand.Ref}, true",
            _ => $"xor {llvmType} {operand.Ref}, -1",
        };

        return new Val(Emit(llvmType, instruction), llvmType, unary.Type);
    }

    private Val EmitBinary(BoundBinary binary)
    {
        if (binary.Operator is BoundBinaryOp.LogicalAnd or BoundBinaryOp.LogicalOr)
            return EmitShortCircuit(binary);

        // Pointer arithmetic is a GEP, not an add.
        if (binary.Left.Type is PointerTypeSymbol pointer &&
            binary.Operator is BoundBinaryOp.Add or BoundBinaryOp.Subtract)
        {
            var basePointer = EmitExpression(binary.Left);
            var offset = EmitExpression(binary.Right);
            string index = WidenIndex(offset);
            if (binary.Operator == BoundBinaryOp.Subtract)
                index = Emit("i64", $"sub i64 0, {index}");

            string element = LlvmTypeOf(pointer.Element);
            return new Val(
                Emit("ptr", $"getelementptr inbounds {element}, ptr {basePointer.Ref}, i64 {index}"),
                "ptr", binary.Type);
        }

        var left = EmitExpression(binary.Left);
        var right = EmitExpression(binary.Right);

        var operandType = binary.Left.Type;
        bool isFloat = operandType is PrimitiveTypeSymbol { IsFloat: true };
        bool signed = IsSigned(operandType);
        string type = left.LlvmType;

        string? comparison = binary.Operator switch
        {
            BoundBinaryOp.Equal => isFloat ? "fcmp oeq" : "icmp eq",

            // 'une', not 'one': IEEE says a NaN is unequal to everything
            // including itself, and an ordered compare would answer false to
            // exactly that. `x != x` is how NaN is detected.
            BoundBinaryOp.NotEqual => isFloat ? "fcmp une" : "icmp ne",
            BoundBinaryOp.Less => isFloat ? "fcmp olt" : signed ? "icmp slt" : "icmp ult",
            BoundBinaryOp.LessEqual => isFloat ? "fcmp ole" : signed ? "icmp sle" : "icmp ule",
            BoundBinaryOp.Greater => isFloat ? "fcmp ogt" : signed ? "icmp sgt" : "icmp ugt",
            BoundBinaryOp.GreaterEqual => isFloat ? "fcmp oge" : signed ? "icmp sge" : "icmp uge",
            _ => null,
        };

        if (comparison is not null)
            return new Val(
                Emit("i1", $"{comparison} {type} {left.Ref}, {right.Ref}"), "i1", PrimitiveTypeSymbol.Bool);

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
            _ => signed ? "ashr" : "lshr",
        };

        // Floating point division by zero is defined and produces an infinity;
        // integer division by zero is not, and neither is the one signed case
        // that overflows.
        if (!isFloat && binary.Operator is BoundBinaryOp.Divide or BoundBinaryOp.Remainder &&
            !IsSafeDivisor(binary.Right))
            GuardDivision(type, left.Ref, right.Ref, signed);

        string operand = binary.Operator is BoundBinaryOp.ShiftLeft or BoundBinaryOp.ShiftRight
            ? MaskShiftCount(type, right.Ref)
            : right.Ref;

        return new Val(
            Emit(type, $"{opcode} {type} {left.Ref}, {operand}"), type, binary.Type);
    }

    /// <summary>
    /// True for a divisor that cannot be zero and cannot make a division
    /// overflow, so the guard would be branches the optimiser only deletes again.
    ///
    /// A constant divisor is the overwhelmingly common case — <c>n / 2</c>,
    /// <c>i % 16</c> — and skipping it keeps the emitted IR the size it was.
    /// </summary>
    private static bool IsSafeDivisor(BoundExpression divisor) =>
        divisor is BoundLiteral { Value: ulong value } && value != 0
        && value != unchecked((ulong)-1);

    /// <summary>
    /// Traps on the integer divisions LLVM leaves undefined.
    ///
    /// Undefined is not "whatever the hardware does": the optimiser may fold an
    /// expression containing one to any value it likes, which is how <c>10 /
    /// Zero()</c> came to print a number and exit successfully. A language that
    /// bounds-checks every index should not quietly return nonsense here, so
    /// this is the same shape as the bounds check — compare, branch, abort.
    /// </summary>
    private void GuardDivision(string type, string dividend, string divisor, bool signed)
    {
        string zeroLabel = NextLabel("div.zero");
        string liveLabel = NextLabel("div.live");

        string byZero = Emit("i1", $"icmp eq {type} {divisor}, 0");
        Terminator($"br i1 {byZero}, label %{zeroLabel}, label %{liveLabel}");

        Label(zeroLabel);
        Line("call void @sl_divide_by_zero()");
        Terminator("unreachable");

        Label(liveLabel);
        if (!signed) return;

        // The one remaining undefined case: the most negative value divided by
        // -1 has no representable result.
        string overflowLabel = NextLabel("div.overflow");
        string okLabel = NextLabel("div.ok");

        string atMinimum = Emit("i1", $"icmp eq {type} {dividend}, {SmallestOf(type)}");
        string byNegativeOne = Emit("i1", $"icmp eq {type} {divisor}, -1");
        string overflows = Emit("i1", $"and i1 {atMinimum}, {byNegativeOne}");
        Terminator($"br i1 {overflows}, label %{overflowLabel}, label %{okLabel}");

        Label(overflowLabel);
        Line("call void @sl_divide_overflow()");
        Terminator("unreachable");

        Label(okLabel);
    }

    /// <summary>
    /// Reduces a shift count modulo the operand's width, which is what C# does.
    ///
    /// LLVM leaves a count at or past the width undefined, so <c>1 &lt;&lt; 40</c>
    /// on an <c>int</c> produced garbage rather than the 256 a C# reader
    /// expects. One <c>and</c> makes it defined, and costs nothing the hardware
    /// was not doing anyway.
    /// </summary>
    private string MaskShiftCount(string type, string count) =>
        Emit(type, $"and {type} {count}, {WidthOf(type) - 1}");

    private static int WidthOf(string llvmType) => llvmType switch
    {
        "i8" => 8,
        "i16" => 16,
        "i64" => 64,
        _ => 32,
    };

    /// <summary>The most negative value of a signed integer type, as LLVM spells it.</summary>
    private static string SmallestOf(string llvmType) => llvmType switch
    {
        "i8" => "-128",
        "i16" => "-32768",
        "i64" => "-9223372036854775808",
        _ => "-2147483648",
    };

    /// <summary>
    /// <c>&amp;&amp;</c> and <c>||</c> must not evaluate the right operand unless
    /// they have to, so they become branches with a phi rather than bitwise ops.
    /// </summary>
    private Val EmitShortCircuit(BoundBinary binary)
    {
        bool isAnd = binary.Operator == BoundBinaryOp.LogicalAnd;
        string rightLabel = NextLabel(isAnd ? "and.rhs" : "or.rhs");
        string endLabel = NextLabel(isAnd ? "and.end" : "or.end");

        var left = EmitExpression(binary.Left);
        string leftBlock = CurrentBlockLabel();

        Terminator(isAnd
            ? $"br i1 {left.Ref}, label %{rightLabel}, label %{endLabel}"
            : $"br i1 {left.Ref}, label %{endLabel}, label %{rightLabel}");

        Label(rightLabel);

        // Anything the right operand allocates is released here, at the end of
        // its own block. Deferring it to the merge would emit a release the
        // defining instruction does not dominate, since the merge is also
        // reached when the right operand never ran.
        int mark = _pendingReleases.Count;
        var right = EmitExpression(binary.Right);
        FlushTemporaries(mark);

        string rightBlock = CurrentBlockLabel();
        Terminator($"br label %{endLabel}");

        Label(endLabel);
        string result = Emit("i1",
            $"phi i1 [ {(isAnd ? "false" : "true")}, %{leftBlock} ], [ {right.Ref}, %{rightBlock} ]");

        return new Val(result, "i1", PrimitiveTypeSymbol.Bool);
    }

    /// <summary>
    /// <c>a ? b : c</c>. Like the short-circuit operators this is branches and a
    /// phi, because only the chosen arm may run.
    /// </summary>
    private Val EmitConditional(BoundConditional expression)
    {
        string trueLabel = NextLabel("cond.true");
        string falseLabel = NextLabel("cond.false");
        string endLabel = NextLabel("cond.end");

        var condition = EmitExpression(expression.Condition);
        Terminator($"br i1 {condition.Ref}, label %{trueLabel}, label %{falseLabel}");

        Label(trueLabel);
        var whenTrue = EmitArm(expression.WhenTrue);
        string trueBlock = CurrentBlockLabel();
        Terminator($"br label %{endLabel}");

        Label(falseLabel);
        var whenFalse = EmitArm(expression.WhenFalse);
        string falseBlock = CurrentBlockLabel();
        Terminator($"br label %{endLabel}");

        Label(endLabel);
        string llvmType = whenTrue.LlvmType;
        string result = Emit(llvmType,
            $"phi {llvmType} [ {whenTrue.Ref}, %{trueBlock} ], [ {whenFalse.Ref}, %{falseBlock} ]");

        // The arms each left a +1 reference; the merged one is now the temporary.
        if (expression.Type.NeedsArc() || expression.Type.CarriesReferences())
            TrackTemporary(result, expression.Type);

        return new Val(result, llvmType, expression.Type);
    }

    /// <summary>
    /// Emits one arm of a conditional so that it leaves exactly one owned
    /// reference behind and no temporaries of its own.
    ///
    /// Anything the arm allocated has to be released inside the arm's own block,
    /// since the merge is also reached when the arm never ran and a release
    /// there would not be dominated by its definition. Retaining first means the
    /// surviving value is independent of whatever the flush destroys.
    /// </summary>
    private Val EmitArm(BoundExpression arm)
    {
        int mark = _pendingReleases.Count;
        var value = EmitExpression(arm);

        if (arm.Type.NeedsArc()) Retain(value.Ref, arm.Type);
        else if (arm.Type is StructTypeSymbol structArm && structArm.CarriesReferences())
            RetainFieldsAt(value.Ref, structArm);

        FlushTemporaries(mark);

        return value;
    }

    private string CurrentBlockLabel() => _currentBlock;
}
