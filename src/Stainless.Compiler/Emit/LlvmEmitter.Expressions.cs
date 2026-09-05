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
/// Expressions that read or write a location: locals, fields, bit-fields,
/// assignment and the type test.
/// </summary>
public sealed partial class LlvmEmitter
{
    // ============================================================ expressions

    private Val EmitExpression(BoundExpression expression)
    {
        switch (expression)
        {
            case BoundLiteral literal: return EmitLiteral(literal);
            case BoundStringLiteral text:
                return new Val(InternStringObject(text.Value), "ptr", text.Type);
            case BoundInterpolatedString interpolated:
                return EmitInterpolatedString(interpolated);
            case BoundNullLiteral nullLiteral: return new Val("null", "ptr", nullLiteral.Type);
            case BoundConstantAccess constant: return EmitConstant(constant);
            case BoundStaticAccess shared: return EmitStaticAccess(shared);
            case BoundSizeof sizeofExpression:
                return new Val(sizeofExpression.MeasuredType.Size.ToString(), "i64", sizeofExpression.Type);

            case BoundAlignof alignofExpression:
                return new Val(
                    alignofExpression.MeasuredType.Alignment.ToString(), "i64",
                    alignofExpression.Type);

            // A class field's stored offset is relative to the fields area, and
            // the header sits in front of it, so the number a caller can add to
            // the reference it holds is the sum.
            case BoundOffsetof offsetofExpression:
                return new Val(
                    (offsetofExpression.Field.Offset + (offsetofExpression.Owner is ClassTypeSymbol
                        ? ClassTypeSymbol.HeaderSize : 0)).ToString(),
                    "i64", offsetofExpression.Type);

            case BoundLocalAccess or BoundParameterAccess or BoundThis
                 or BoundFieldAccess or BoundDereference or BoundIndex:
                return LoadFrom(expression);

            case BoundAddressOf addressOf:
                return new Val(EmitAddress(addressOf.Operand), "ptr", addressOf.Type);

            case BoundConversion conversion: return EmitConversion(conversion);
            case BoundTypeTest test: return EmitTypeTest(test);
            case BoundUnary unary: return EmitUnary(unary);
            case BoundBinary binary: return EmitBinary(binary);
            case BoundConditional conditional: return EmitConditional(conditional);
            case BoundFunctionReference reference:
                return new Val(Symbol(reference.Function), "ptr", reference.Type);
            case BoundIndirectCall indirect: return EmitIndirectCall(indirect);
            case BoundAssignment assignment: return EmitAssignment(assignment);
            case BoundPropertyAssignment written: return EmitPropertyAssignment(written);
            case BoundCall call: return EmitCall(call);
            case BoundNew newExpression: return EmitNew(newExpression);
            case BoundClosure closure: return EmitClosure(closure);
            case BoundNewArray newArray: return EmitNewArray(newArray);
            case BoundArrayLiteral literalArray: return EmitArrayLiteral(literalArray);
            case BoundArrayLength length: return EmitArrayLength(length);
            case BoundSlice slice: return EmitSlice(slice);
            case BoundTypeof typeofExpression: return EmitTypeof(typeofExpression);

            // A constant in static storage, so this is its address and
            // nothing else: no load, no call, and two mentions of one
            // interface are the same pointer.
            case BoundIidof iidof:
                return new Val("@" + IidName(iidof.Named), "ptr", iidof.Type);
            case BoundVariantConstruction built: return EmitVariantConstruction(built);
            case BoundVariantTest test: return EmitVariantTest(test);
            case BoundVariantPayload payload: return EmitVariantPayload(payload);

            default:
                return new Val("0", "i32", PrimitiveTypeSymbol.Int);
        }
    }

    private Val EmitLiteral(BoundLiteral literal)
    {
        string llvmType = LlvmTypeOf(literal.Type);
        string text = literal.Value switch
        {
            bool flag => flag ? "true" : "false",
            int scalar => scalar.ToString(CultureInfo.InvariantCulture),
            double number => FormatDouble(number),
            ulong number => FormatInteger(number, literal.Type),
            _ => "0",
        };
        return new Val(text, llvmType, literal.Type);
    }

    private static string FormatInteger(ulong value, TypeSymbol type)
    {
        // An enum is its underlying integer, and is spelled as one.
        if (type is EnumTypeSymbol enumType) type = enumType.UnderlyingType;

        // LLVM wants the signed two's-complement spelling for signed types.
        if (type is PrimitiveTypeSymbol { IsSigned: true, Size: var size })
        {
            long signed = size switch
            {
                1 => (sbyte)value,
                2 => (short)value,
                4 => (int)value,
                _ => (long)value,
            };
            return signed.ToString(CultureInfo.InvariantCulture);
        }
        return value.ToString(CultureInfo.InvariantCulture);
    }

    /// <summary>LLVM accepts a double as a 16-digit hex bit pattern, which never loses precision.</summary>
    private static string FormatDouble(double value) =>
        "0x" + BitConverter.DoubleToUInt64Bits(value).ToString("X16", CultureInfo.InvariantCulture);

    private Val EmitConstant(BoundConstantAccess access)
    {
        var constant = access.Constant;
        string llvmType = LlvmTypeOf(constant.Type);
        string text = constant.Value switch
        {
            bool flag => flag ? "true" : "false",
            int scalar => scalar.ToString(CultureInfo.InvariantCulture),
            double number => FormatDouble(number),
            ulong number => FormatInteger(number, constant.Type),
            string s => InternBytes(s),
            _ => "0",
        };
        return new Val(text, llvmType, constant.Type);
    }

    /// <summary>Computes the address of an lvalue expression.</summary>
    private string EmitAddress(BoundExpression expression)
    {
        switch (expression)
        {
            case BoundStaticAccess shared:
                return "@" + StaticName(shared.Static);

            case BoundLocalAccess local:
                return _slots[local.Local];

            case BoundParameterAccess parameter:
                return _parameterSlots[parameter.Parameter];

            case BoundThis thisExpression:
                return _parameterSlots[thisExpression.Parameter];

            case BoundFieldAccess field:
                return EmitFieldAddress(field);

            case BoundDereference dereference:
            {
                var pointer = EmitExpression(dereference.Operand);
                return pointer.Ref;
            }

            case BoundIndex index:
            {
                if (index.Target.Type is ArrayTypeSymbol) return EmitArrayElementAddress(index);
                if (index.Target.Type is SliceTypeSymbol) return EmitSliceElementAddress(index);
                if (index.Target.Type is FixedArrayTypeSymbol inline)
                    return EmitInlineElementAddress(index, inline);

                var target = EmitExpression(index.Target);
                var offset = EmitExpression(index.Index);
                string elementType = LlvmTypeOf(index.Type);
                string widened = WidenIndex(offset);
                return Emit("ptr",
                    $"getelementptr inbounds {elementType}, ptr {target.Ref}, i64 {widened}");
            }

            default:
            {
                // A temporary that needs an address: materialise it.
                var value = EmitExpression(expression);
                if (value.IsStructAddress) return value.Ref;
                string slot = Alloca(value.LlvmType, "temp");
                Line($"store {value.LlvmType} {value.Ref}, ptr {slot}");
                return slot;
            }
        }
    }

    /// <summary>
    /// The address of one element of an inline array.
    ///
    /// The array has no header and no indirection -- it is laid out where it was
    /// written -- so this is the array's own address plus the index, and the
    /// bounds check compares against a number that was in the type.
    /// </summary>
    private string EmitInlineElementAddress(BoundIndex index, FixedArrayTypeSymbol inline)
    {
        string array = EmitAddress(index.Target);
        var offset = EmitExpression(index.Index);
        string widened = WidenIndex(offset);

        // One unsigned compare covers both ends, as it does for an array: a
        // negative index sign-extends to a very large unsigned value. The length
        // is a constant here rather than a load, because it was in the type.
        string length = inline.Length.ToString();
        string inRange = Emit("i1", $"icmp ult i64 {widened}, {length}");

        string okLabel = NextLabel("bounds.ok");
        string failLabel = NextLabel("bounds.fail");
        Terminator($"br i1 {inRange}, label %{okLabel}, label %{failLabel}");

        Label(failLabel);
        Line($"call void @sl_array_bounds_fail(i64 {widened}, i64 {length})");
        Terminator("unreachable");

        Label(okLabel);
        return Emit("ptr",
            $"getelementptr inbounds {LlvmTypeOf(inline)}, ptr {array}, i64 0, i64 {widened}");
    }

    private string WidenIndex(Val index)
    {
        if (index.LlvmType == "i64") return index.Ref;
        return Emit("i64", $"{(IsSigned(index.Type) ? "sext" : "zext")} {index.LlvmType} {index.Ref} to i64");
    }

    private string EmitFieldAddress(BoundFieldAccess access)
    {
        var field = access.Field;

        if (field.ContainingType is ClassTypeSymbol)
        {
            // The receiver is already a reference; fields live past the header.
            var receiver = EmitExpression(access.Receiver!);
            return ClassFieldAddress(receiver.Ref, field);
        }

        // Struct receiver: address of the value, then a structural GEP.
        string baseAddress = access.Receiver is null
            ? throw new InvalidOperationException("struct field access needs a receiver")
            : EmitAddress(access.Receiver);

        return StructFieldAddress(baseAddress, (StructTypeSymbol)field.ContainingType, field);
    }

    /// <summary>True for a struct whose LLVM type is bytes rather than fields.</summary>
    private static bool HasBitFields(StructTypeSymbol type) => type.Fields.Any(f => f.IsBitField);

    /// <summary>
    /// Where a field of a value type lives.
    ///
    /// A union's member is at the union's own address, because all of them are.
    /// A struct with bit-fields has no LLVM fields to index, so its members are
    /// reached by the byte offset the layout gave them. Everything else is the
    /// structural index, which is what lets LLVM see through the access.
    /// </summary>
    private string StructFieldAddress(string baseAddress, StructTypeSymbol owner, FieldSymbol field)
    {
        if (owner is UnionTypeSymbol) return baseAddress;

        if (HasBitFields(owner))
            return field.Offset == 0
                ? baseAddress
                : Emit("ptr", $"getelementptr inbounds i8, ptr {baseAddress}, i64 {field.Offset}");

        return Emit("ptr",
            $"getelementptr inbounds {StructName(owner)}, ptr {baseAddress}, i32 0, i32 {field.Index}");
    }

    // ============================================================ bit-fields

    /// <summary>
    /// Reads a bit-field: load the storage unit it sits in, move its bits down,
    /// and widen them back to the declared type.
    ///
    /// A signed one is shifted left and then arithmetic-shifted right, which
    /// sign-extends from the field's own width rather than the unit's -- a
    /// three-bit signed field holding 7 is -1.
    /// </summary>
    private Val LoadBitField(BoundFieldAccess access)
    {
        var field = access.Field;
        int width = field.BitWidth!.Value;
        int bits = field.Type.Size * 8;
        string unit = $"i{bits}";

        string address = EmitFieldAddress(access);
        string loaded = Emit(unit, $"load {unit}, ptr {address}, align {field.Type.Size}");

        string value;
        if (IsSigned(field.Type))
        {
            string high = Emit(unit, $"shl {unit} {loaded}, {bits - field.BitOffset - width}");
            value = Emit(unit, $"ashr {unit} {high}, {bits - width}");
        }
        else
        {
            string low = field.BitOffset == 0
                ? loaded
                : Emit(unit, $"lshr {unit} {loaded}, {field.BitOffset}");
            value = Emit(unit, $"and {unit} {low}, {Mask(width)}");
        }

        // A bool is one bit to LLVM whatever it is to the layout.
        string declared = LlvmTypeOf(field.Type);
        if (declared != unit) value = Emit(declared, $"trunc {unit} {value} to {declared}");

        return new Val(value, declared, field.Type);
    }

    /// <summary>
    /// Writes a bit-field: read the unit, clear the field's bits, put the new
    /// ones in, write it back. Bits outside the field are untouched, which is
    /// what makes two fields sharing a unit independent.
    /// </summary>
    private void StoreBitField(BoundFieldAccess access, Val value)
    {
        var field = access.Field;
        int width = field.BitWidth!.Value;
        int bits = field.Type.Size * 8;
        string unit = $"i{bits}";

        string address = EmitFieldAddress(access);
        string loaded = Emit(unit, $"load {unit}, ptr {address}, align {field.Type.Size}");

        string widened = value.LlvmType == unit
            ? value.Ref
            : Emit(unit, $"zext {value.LlvmType} {value.Ref} to {unit}");

        string kept = Emit(unit, $"and {unit} {loaded}, {~(Mask(width) << field.BitOffset) & MaskAll(bits)}");
        string trimmed = Emit(unit, $"and {unit} {widened}, {Mask(width)}");
        string placed = field.BitOffset == 0
            ? trimmed
            : Emit(unit, $"shl {unit} {trimmed}, {field.BitOffset}");

        Line($"store {unit} {Emit(unit, $"or {unit} {kept}, {placed}")}, ptr {address}, " +
             $"align {field.Type.Size}");
    }

    /// <summary>The low <paramref name="width"/> bits set, as LLVM writes a constant.</summary>
    private static long Mask(int width) => width >= 64 ? -1L : (1L << width) - 1;

    private static long MaskAll(int bits) => bits >= 64 ? -1L : (1L << bits) - 1;

    private string ClassFieldAddress(string objectRef, FieldSymbol field) =>
        Emit("ptr",
            $"getelementptr inbounds i8, ptr {objectRef}, i64 {ClassTypeSymbol.HeaderSize + field.Offset}");

    private Val LoadFrom(BoundExpression expression)
    {
        // A bit-field is not at an address of its own; it is some of the bits of
        // one, so reading it is more than a load.
        if (expression is BoundFieldAccess { Field.IsBitField: true } bitField)
            return LoadBitField(bitField);

        // A struct is represented by its address, so there is nothing to load.
        if (expression.Type is StructTypeSymbol)
            return new Val(EmitAddress(expression), "ptr", expression.Type);

        string address = EmitAddress(expression);
        string llvmType = LlvmTypeOf(expression.Type);
        return new Val(Emit(llvmType, $"load {llvmType}, ptr {address}"), llvmType, expression.Type);
    }

    private void StoreInto(string slot, Val value, TypeSymbol targetType)
    {
        if (targetType is StructTypeSymbol structType)
        {
            // Retain before release, for the reason StoreManaged does it: a
            // struct assigned to itself must not destroy what it is copying.
            if (structType.CarriesReferences())
            {
                RetainFieldsAt(value.Ref, structType);
                ReleaseFieldsAt(slot, structType);
            }

            MemCopy(slot, value.Ref, structType.Size);
            return;
        }

        if (targetType.IsManagedSlot())
        {
            StoreManaged(slot, value.Ref, targetType);
            return;
        }

        // An inline array is held by address, like a struct, because it is its
        // elements rather than a reference to them. So the whole of it moves,
        // and each element that owns something is retained on the way.
        if (targetType is FixedArrayTypeSymbol inline)
        {
            if (inline.Element.CarriesReferences())
                for (int i = 0; i < inline.Length; i++)
                {
                    string source = Emit("ptr",
                        $"getelementptr inbounds {LlvmTypeOf(inline.Element)}, " +
                        $"ptr {value.Ref}, i64 {i}");
                    string target = Emit("ptr",
                        $"getelementptr inbounds {LlvmTypeOf(inline.Element)}, " +
                        $"ptr {slot}, i64 {i}");
                    StoreInto(target, new Val(source, "ptr", inline.Element), inline.Element);
                }
            else
                MemCopy(slot, value.Ref, inline.Size);
            return;
        }

        Line($"store {LlvmTypeOf(targetType)} {value.Ref}, ptr {slot}");
    }

    private Val EmitAssignment(BoundAssignment assignment)
    {
        var value = EmitExpression(assignment.Value);

        // A bit-field shares its storage unit with its neighbours, so writing it
        // is a read, a splice and a write rather than a store.
        if (assignment.Target is BoundFieldAccess { Field.IsBitField: true } bitField)
        {
            StoreBitField(bitField, value);
            return value;
        }

        string address = EmitAddress(assignment.Target);
        StoreInto(address, value, assignment.Target.Type);
        return value;
    }

    /// <summary>
    /// Calls a setter, then hands back the value it was given.
    ///
    /// A setter returns nothing, but an assignment is an expression whose value
    /// is what was stored — so the value is emitted here rather than inside a
    /// call that would swallow it. Dispatch is resolved before the value for the
    /// reason <see cref="EmitCall"/> resolves it before the arguments: the
    /// value's own code must not be able to change which object is written.
    /// </summary>
    private Val EmitPropertyAssignment(BoundPropertyAssignment assignment)
    {
        var setter = assignment.Property.Setter!;

        // A setter dispatches for the same reasons a getter does: it is an
        // ordinary method, and `Node.Label = x` on a `Leaf` has to reach the
        // setter the object really has.
        var receiver = EmitExpression(assignment.Receiver);
        string? virtualTarget =
            setter.ContainingType is ComInterfaceTypeSymbol ? LoadComMethod(receiver.Ref, setter)
            : setter.ContainingType is InterfaceTypeSymbol ? LoadInterfaceMethod(receiver.Ref, setter)
            : setter.IsDispatched ? LoadVirtualMethod(receiver.Ref, setter)
            : null;

        var value = EmitExpression(assignment.Value);

        var arguments = new List<string> { $"ptr {receiver.Ref}" };
        AppendArgument(value, assignment.Value.Type, arguments);

        Line($"call void {virtualTarget ?? Symbol(setter)}" +
             $"({string.Join(", ", arguments)})");

        return value;
    }

    /// <summary>
    /// <c>value is Type</c>: one call, and no branch of its own.
    ///
    /// A class is a walk up the object's base chain; an interface is a look in
    /// its dispatch table. Both answer 0 for a null reference, which is what
    /// makes the test over an optional a single question rather than two.
    /// </summary>
    private Val EmitTypeTest(BoundTypeTest test)
    {
        var value = EmitExpression(test.Value);

        string answer = test.Tested switch
        {
            // The object is asked, and it answers at +1 -- which sl_com_is
            // drops again, because the question was a bool.
            ComInterfaceTypeSymbol comInterface => Emit("i32",
                $"call i32 @sl_com_is(ptr {value.Ref}, ptr @{IidName(comInterface)})"),

            InterfaceTypeSymbol interfaceType => Emit("i32",
                $"call i32 @sl_implements(ptr {value.Ref}, i64 {interfaceType.Id})"),

            _ => Emit("i32",
                $"call i32 @sl_is_instance(ptr {value.Ref}, " +
                $"ptr @{Mangler.TypeInfoSymbol((ClassTypeSymbol)test.Tested)})"),
        };

        return new Val(Emit("i1", $"icmp ne i32 {answer}, 0"), "i1", test.Type);
    }
}
