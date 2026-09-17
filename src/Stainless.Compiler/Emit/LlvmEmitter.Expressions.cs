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
            // All three answer a `nuint`, so all three are a word wide.
            case BoundSizeof sizeofExpression:
                return new Val(
                    sizeofExpression.MeasuredType.Size.ToString(), Word, sizeofExpression.Type);

            case BoundAlignof alignofExpression:
                return new Val(
                    alignofExpression.MeasuredType.Alignment.ToString(), Word,
                    alignofExpression.Type);

            // A class field's stored offset is relative to the fields area, and
            // the header sits in front of it, so the number a caller can add to
            // the reference it holds is the sum.
            case BoundOffsetof offsetofExpression:
                return new Val(
                    (offsetofExpression.Field.Offset + (offsetofExpression.Owner is ClassTypeSymbol
                        ? ClassTypeSymbol.HeaderSize : 0)).ToString(),
                    Word, offsetofExpression.Type);

            case BoundLocalAccess or BoundParameterAccess or BoundThis
                 or BoundFieldAccess or BoundDereference or BoundIndex:
                return LoadFrom(expression);

            case BoundAddressOf addressOf:
                // `out var x` declared a variable that no statement did, so
                // this is where it gets its slot -- before the call, which is
                // the only moment it could be.
                if (addressOf.DeclaresLocal is { } declared) DeclareOutLocal(declared);
                return new Val(EmitAddress(addressOf.Operand), "ptr", addressOf.Type);

            case BoundDefault zeroed:
            {
                string llvmType = LlvmTypeOf(zeroed.Type);

                // A struct travels as the address of its storage rather than as
                // a value in a register, so this needs somewhere to point at --
                // `zeroinitializer` is a constant, and handing it to the memcpy
                // that stores a struct copies from address zero.
                if (zeroed.Type is StructTypeSymbol structType)
                {
                    string slot = Alloca(llvmType, "zeroed");
                    Line($"store {llvmType} zeroinitializer, ptr {slot}");

                    // Nothing to release: every reference in it is already null.
                    // Nothing to retain either, which is why this is not tracked
                    // as a temporary.
                    return new Val(slot, "ptr", structType);
                }

                return new Val(ZeroOf(llvmType), llvmType, zeroed.Type);
            }

            case BoundTupleCreate tuple: return EmitTupleCreate(tuple);
            case BoundConversion conversion: return EmitConversion(conversion);

            // Everything but the last is evaluated for what it does; the last
            // one is the value. An object initializer is the whole reason
            // this exists.
            case BoundSequence sequence:
            {
                foreach (var side in sequence.Before) EmitExpression(side);
                return EmitExpression(sequence.Value);
            }
            case BoundTypeTest test: return EmitTypeTest(test);
            case BoundUnary unary: return EmitUnary(unary);
            case BoundBinary binary: return EmitBinary(binary);
            case BoundConditional conditional: return EmitConditional(conditional);

            case BoundLet held:
            {
                var value = EmitExpression(held.Value);

                // Borrowed, not owned: whatever produced the value is already
                // a temporary the statement will drop, so nothing is retained
                // here and nothing is released.
                //
                // A struct, a tuple, a variant and an inline array are all held
                // by address, so the name is that address and there is nothing
                // to copy. Everything else goes in a slot, because that is what
                // a read of a local reads through.
                if (held.Local.Type is StructTypeSymbol or FixedArrayTypeSymbol)
                {
                    _slots[held.Local] = value.Ref;
                }
                else
                {
                    string llvmType = LlvmTypeOf(held.Local.Type);
                    string slot = Alloca(llvmType, held.Local.Name);
                    _slots[held.Local] = slot;
                    Line($"store {llvmType} {value.Ref}, ptr {slot}");
                }

                return EmitExpression(held.Body);
            }
            case BoundFunctionReference reference:
                return new Val(Symbol(reference.Function), "ptr", reference.Type);
            case BoundIndirectCall indirect: return EmitIndirectCall(indirect);
            case BoundClosureCreate closure: return EmitClosureCreate(closure);
            case BoundClosureCall closureCall: return EmitClosureCall(closureCall);
            case BoundClosureEqual same: return EmitClosureEqual(same);
            case BoundAssignment assignment: return EmitAssignment(assignment);
            case BoundIncrement increment: return EmitIncrement(increment);
            case BoundPropertyIncrement stepped: return EmitPropertyIncrement(stepped);
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
            case BoundTry attempt: return EmitTry(attempt);

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
            double number => FormatFloating(number, literal.Type),
            float number => FormatFloating(number, literal.Type),
            ulong number => FormatInteger(number, literal.Type),
            _ => "0",
        };
        return new Val(text, llvmType, literal.Type);
    }

    /// <summary>
    /// A floating-point constant at the width of its type.
    ///
    /// LLVM spells a <c>float</c> constant as the double that holds it exactly,
    /// and rejects one that a float cannot hold: `float 0x3FB999999999999A`,
    /// the double 0.1, is an error rather than a rounding. So a value bound
    /// for a float is rounded to one first, which is what `const float Tenth =
    /// 0.1;` meant.
    /// </summary>
    private static string FormatFloating(double value, TypeSymbol type) =>
        FormatDouble(type is PrimitiveTypeSymbol { Kind: PrimitiveKind.Float } ? (float)value : value);

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
            double number => FormatFloating(number, constant.Type),
            float number => FormatFloating(number, constant.Type),
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
                    $"getelementptr inbounds {elementType}, ptr {target.Ref}, {Word} {widened}");
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
        string inRange = Emit("i1", $"icmp ult {Word} {widened}, {length}");

        string okLabel = NextLabel("bounds.ok");
        string failLabel = NextLabel("bounds.fail");
        Terminator($"br i1 {inRange}, label %{okLabel}, label %{failLabel}");

        Label(failLabel);
        Line($"call void @sl_array_bounds_fail({Word} {widened}, {Word} {length})");
        Terminator("unreachable");

        Label(okLabel);
        return Emit("ptr",
            $"getelementptr inbounds {LlvmTypeOf(inline)}, ptr {array}, i64 0, {Word} {widened}");
    }

    /// <summary>
    /// An index as the target's word, ready to compare against a length and to
    /// index with.
    ///
    /// On a 64-bit target every index is a word or narrower, so this is an
    /// extension and nothing else. On a 32-bit one an index may be *wider* --
    /// <c>array[someLong]</c> -- and truncating it would turn 0x1_0000_0000
    /// into 0: an index past the end of any possible array, passing a check it
    /// should fail. One that does not fit is saturated instead, to a value no
    /// length can be, and the ordinary comparison then refuses it.
    /// </summary>
    private string WidenIndex(Val index)
    {
        string word = Word;
        if (index.LlvmType == word) return index.Ref;

        int wordBits = TargetPlatform.Current.PointerWidth * 8;
        if (IntegerBits(index.LlvmType) < wordBits)
            return Emit(word,
                $"{(IsSigned(index.Type) ? "sext" : "zext")} {index.LlvmType} {index.Ref} to {word}");

        string truncated = Emit(word, $"trunc {index.LlvmType} {index.Ref} to {word}");
        string fits = Emit("i1",
            $"icmp ult {index.LlvmType} {index.Ref}, {1L << wordBits}");

        return Emit(word, $"select i1 {fits}, {word} {truncated}, {word} -1");
    }

    /// <summary>How many bits an LLVM integer type spells.</summary>
    private static int IntegerBits(string llvmType) =>
        llvmType.StartsWith('i') && int.TryParse(llvmType[1..], out int bits) ? bits : 0;

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
            $"getelementptr inbounds {StructName(owner)}, ptr {baseAddress}, " +
            $"i32 0, i32 {FieldSlot(owner, field)}");
    }

    /// <summary>
    /// Which member of the emitted struct a declared field is.
    ///
    /// The same number as the field's own index, unless the struct had its
    /// padding written out -- see <c>SpellingOf</c> -- in which case the pads
    /// are members too and everything after the first of them has moved.
    /// </summary>
    private int FieldSlot(StructTypeSymbol owner, FieldSymbol field) =>
        _fieldSlots.TryGetValue(StructName(owner), out var slots) && field.Index < slots.Length
            ? slots[field.Index]
            : field.Index;

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
        int bytes = AccessBytes(field);
        int bits = bytes * 8;
        string unit = $"i{bits}";

        string address = EmitFieldAddress(access);
        string loaded = Emit(unit, $"load {unit}, ptr {address}, align {AccessAlignment(field)}");

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

        // A bool is one bit to LLVM whatever it is to the layout, and a unit
        // narrower than the type widens the way the type's sign says.
        string declared = LlvmTypeOf(field.Type);
        int declaredBits = int.Parse(declared[1..], CultureInfo.InvariantCulture);
        if (declaredBits < bits)
            value = Emit(declared, $"trunc {unit} {value} to {declared}");
        else if (declaredBits > bits)
            value = Emit(declared,
                $"{(IsSigned(field.Type) ? "sext" : "zext")} {unit} {value} to {declared}");

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
        int bytes = AccessBytes(field);
        int bits = bytes * 8;
        string unit = $"i{bits}";

        string address = EmitFieldAddress(access);
        string loaded = Emit(unit, $"load {unit}, ptr {address}, align {AccessAlignment(field)}");

        int valueBits = int.Parse(value.LlvmType[1..], CultureInfo.InvariantCulture);
        string widened = valueBits == bits
            ? value.Ref
            : Emit(unit, $"{(valueBits < bits ? "zext" : "trunc")} {value.LlvmType} {value.Ref} to {unit}");

        string kept = Emit(unit, $"and {unit} {loaded}, {~(Mask(width) << field.BitOffset) & MaskAll(bits)}");
        string trimmed = Emit(unit, $"and {unit} {widened}, {Mask(width)}");
        string placed = field.BitOffset == 0
            ? trimmed
            : Emit(unit, $"shl {unit} {trimmed}, {field.BitOffset}");

        Line($"store {unit} {Emit(unit, $"or {unit} {kept}, {placed}")}, ptr {address}, " +
             $"align {AccessAlignment(field)}");
    }

    /// <summary>
    /// How many bytes are loaded and stored to reach a bit-field: the smallest
    /// power of two holding it from the start of its unit, and never more than
    /// the unit.
    ///
    /// Not simply the unit, because on i386 System V a unit can be wider than
    /// the struct it is in. `struct { char c; long long x : 3; }` is four bytes
    /// there, with an eight-byte `long long` unit starting at zero, so loading
    /// the whole unit read four bytes past the end of the value and storing it
    /// wrote them. Everywhere else a unit ends inside its struct, and the
    /// narrower access reads the same bits.
    /// </summary>
    private static int AccessBytes(FieldSymbol field)
    {
        int needed = (field.BitOffset + field.BitWidth!.Value + 7) / 8;
        int bytes = 1;
        while (bytes < needed) bytes *= 2;
        return Math.Min(bytes, Math.Max(1, field.Type.Size));
    }

    /// <summary>
    /// The alignment a unit's address is known to have: its type's, which on
    /// i386 System V is less than its size for a `long`.
    /// </summary>
    private static int AccessAlignment(FieldSymbol field) =>
        Math.Min(AccessBytes(field), Math.Max(1, field.Type.Alignment));

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

    /// <summary>
    /// Gives the variable an <c>out var x</c> introduced a slot, cleared.
    ///
    /// Cleared because the language has no definite-assignment analysis: a
    /// callee that returns without writing would otherwise leave the caller
    /// reading whatever the stack held. Zero is not the right answer either,
    /// but it is an answer rather than a hazard, and it matches what a new
    /// array and an owned local already promise.
    /// </summary>
    private void DeclareOutLocal(LocalSymbol local)
    {
        if (_slots.ContainsKey(local)) return;

        string llvmType = LlvmTypeOf(local.Type);
        string slot = Alloca(llvmType, local.Name);
        _slots[local] = slot;

        Line($"store {llvmType} {ZeroOf(llvmType)}, ptr {slot}");

        if (local.Type.IsManagedSlot() ||
            local.Type is StructTypeSymbol { } owning && owning.CarriesReferences())
        {
            ZeroOnEntry(slot, llvmType);
            TrackOwnedLocal(slot, local.Type);
        }
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
        // setter the object really has. A static one has no object, and so
        // nothing to dispatch on.
        string? receiverRef = null;
        string? virtualTarget = null;

        if (assignment.Receiver is not null)
        {
            receiverRef = EmitExpression(assignment.Receiver).Ref;

            // Not through the table for `base.P = x`: the override is what the
            // object's table holds, so dispatching would call the setter this
            // one is written inside.
            virtualTarget = assignment.IsNonVirtual ? null
                : setter.ContainingType is ComInterfaceTypeSymbol ? LoadComMethod(receiverRef, setter)
                : setter.ContainingType is InterfaceTypeSymbol
                    ? LoadInterfaceMethod(receiverRef, setter)
                : setter.IsDispatched ? LoadVirtualMethod(receiverRef, setter)
                : null;
        }

        // An indexer's indices come before `value`, in the order the setter
        // declares them and the call site wrote them.
        var indices = assignment.Indices.Select(EmitExpression).ToList();
        var value = EmitExpression(assignment.Value);

        var arguments = new List<string>();
        if (receiverRef is not null) arguments.Add($"ptr {receiverRef}");

        for (int i = 0; i < indices.Count; i++)
            AppendArgument(indices[i], assignment.Indices[i].Type, arguments);

        AppendArgument(value, assignment.Value.Type, arguments);

        Line($"call void {virtualTarget ?? Symbol(setter)}" +
             $"({string.Join(", ", arguments)})");

        return value;
    }

    /// <summary>
    /// <c>++x</c>, <c>x++</c>, <c>--x</c> and <c>x--</c> over a place.
    ///
    /// The address is worked out once and then read, changed and written, which
    /// is what an assignment to <c>x + 1</c> could not promise: that form
    /// evaluates the place twice, so <c>a[Next()]++</c> would call <c>Next</c>
    /// on both sides and step an element it never read.
    /// </summary>
    private Val EmitIncrement(BoundIncrement increment)
    {
        var target = increment.Target;

        // A bit-field is a slice of a storage unit rather than an address, and
        // the read and the write both know how to splice it.
        if (target is BoundFieldAccess { Field.IsBitField: true } bitField)
        {
            var wasBits = LoadBitField(bitField);
            var nowBits = StepOne(wasBits, increment.IsIncrement, increment.IsChecked, target.Type);
            StoreBitField(bitField, nowBits);
            return increment.IsPrefix ? nowBits : wasBits;
        }

        string address = EmitAddress(target);
        string llvmType = LlvmTypeOf(target.Type);

        var was = new Val(Emit(llvmType, $"load {llvmType}, ptr {address}"), llvmType, target.Type);
        var now = StepOne(was, increment.IsIncrement, increment.IsChecked, target.Type);

        Line($"store {llvmType} {now.Ref}, ptr {address}");
        return increment.IsPrefix ? now : was;
    }

    /// <summary>
    /// The same over a property, which is a getter and a setter rather than an
    /// address.
    ///
    /// The receiver is emitted once and used for both calls, so
    /// <c>Next().Count++</c> reads and writes one object.
    /// </summary>
    private Val EmitPropertyIncrement(BoundPropertyIncrement increment)
    {
        var property = increment.Property;
        var getter = property.Getter!;
        var setter = property.Setter!;

        string? receiverRef = null;
        string? virtualGet = null;
        string? virtualSet = null;

        if (increment.Receiver is not null)
        {
            receiverRef = EmitExpression(increment.Receiver).Ref;
            virtualGet = DispatchTarget(receiverRef, getter);
            virtualSet = DispatchTarget(receiverRef, setter);
        }

        string llvmType = LlvmTypeOf(property.Type);

        // An indexer's accessors take the indices as well as the receiver.
        // They are emitted once and reused by both calls, so `grid[Next()]++`
        // calls `Next` a single time and reads and writes the same element.
        var indices = new List<string>();
        for (int at = 0; at < increment.Arguments.Count; at++)
        {
            var argument = increment.Arguments[at];
            AppendArgument(EmitExpression(argument), argument.Type, indices);
        }

        var readArguments = new List<string>();
        if (receiverRef is not null) readArguments.Add($"ptr {receiverRef}");
        readArguments.AddRange(indices);

        var was = new Val(
            Emit(llvmType,
                $"call {llvmType} {virtualGet ?? Symbol(getter)}({string.Join(", ", readArguments)})"),
            llvmType, property.Type);

        var now = StepOne(was, increment.IsIncrement, increment.IsChecked, property.Type);

        var arguments = new List<string>();
        if (receiverRef is not null) arguments.Add($"ptr {receiverRef}");
        arguments.AddRange(indices);
        AppendArgument(now, property.Type, arguments);

        Line($"call void {virtualSet ?? Symbol(setter)}({string.Join(", ", arguments)})");
        return increment.IsPrefix ? now : was;
    }

    /// <summary>Where a call to this accessor goes, or null when it is not dispatched.</summary>
    private string? DispatchTarget(string receiverRef, FunctionSymbol accessor) =>
        accessor.ContainingType is ComInterfaceTypeSymbol ? LoadComMethod(receiverRef, accessor)
        : accessor.ContainingType is InterfaceTypeSymbol ? LoadInterfaceMethod(receiverRef, accessor)
        : accessor.IsDispatched ? LoadVirtualMethod(receiverRef, accessor)
        : null;

    /// <summary>
    /// One more, or one less.
    ///
    /// A pointer steps by an element, as C's does; a float adds 1.0; an integer
    /// adds 1, and inside <c>checked</c> notices if that did not fit.
    /// </summary>
    private Val StepOne(Val value, bool up, bool watched, TypeSymbol type)
    {
        if (type is PointerTypeSymbol pointer)
            return new Val(
                Emit("ptr", $"getelementptr inbounds {LlvmTypeOf(pointer.Element)}, " +
                            $"ptr {value.Ref}, i64 {(up ? 1 : -1)}"),
                "ptr", type);

        if (type is PrimitiveTypeSymbol { IsFloat: true })
            return new Val(
                Emit(value.LlvmType, $"{(up ? "fadd" : "fsub")} {value.LlvmType} {value.Ref}, 1.0"),
                value.LlvmType, type);

        if (watched)
            return new Val(
                CheckedArithmetic(
                    up ? BoundBinaryOp.Add : BoundBinaryOp.Subtract,
                    value.LlvmType, value.Ref, "1", IsSigned(type)),
                value.LlvmType, type);

        return new Val(
            Emit(value.LlvmType, $"{(up ? "add" : "sub")} {value.LlvmType} {value.Ref}, 1"),
            value.LlvmType, type);
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
                $"call i32 @sl_implements(ptr {value.Ref}, {Word} {interfaceType.Id})"),

            _ => Emit("i32",
                $"call i32 @sl_is_instance(ptr {value.Ref}, " +
                $"ptr @{Mangler.TypeInfoSymbol((ClassTypeSymbol)test.Tested)})"),
        };

        return new Val(Emit("i1", $"icmp ne i32 {answer}, 0"), "i1", test.Type);
    }
}
