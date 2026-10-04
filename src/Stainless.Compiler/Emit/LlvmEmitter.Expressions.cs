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
using Stainless.Source;
using Stainless.Syntax;

namespace Stainless.Emit;

/// <summary>
/// Expressions that read or write a location: locals, fields, bit-fields,
/// assignment and the type test.
/// </summary>
public sealed partial class LlvmEmitter
{
    // ============================================================ expressions

    /// <summary>The dispatch behind <see cref="EmitOwnable"/>.</summary>
    private Val EmitValue(BoundExpression expression)
    {
        switch (expression)
        {
            case BoundLiteral literal: return EmitLiteral(literal);

            // Immortal, so there is nothing to count: a retain or a release of
            // one returns at once.
            case BoundStringLiteral text:
                return Uncounted(new Val(InternStringObject(text.Value), "ptr", text.Type));
            case BoundUtf8Literal bytes:
                return Uncounted(new Val(InternUtf8Array(bytes.Value), "ptr", bytes.Type));
            case BoundInterpolatedString interpolated:
                return EmitInterpolatedString(interpolated);
            case BoundNullLiteral nullLiteral:
                return Uncounted(new Val("null", "ptr", nullLiteral.Type));
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
                if (addressOf.DeclaresLocal is { } declared)
                    DeclareExpressionLocal(declared);
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

                    // Every reference in it is null, so it owes nothing.
                    return Uncounted(new Val(slot, "ptr", structType));
                }

                return Uncounted(new Val(ZeroOf(llvmType), llvmType, zeroed.Type));
            }

            case BoundTupleCreate tuple: return EmitTupleCreate(tuple);
            case BoundConversion conversion: return EmitConversion(conversion);

            // Everything but the last is evaluated for what it does; the last
            // one is the value. An object initializer is the whole reason
            // this exists.
            case BoundSequence sequence:
            {
                foreach (var side in sequence.Before) EmitDiscarded(side);
                return EmitOwnable(sequence.Value);
            }
            case BoundTypeTest test: return EmitTypeTest(test);
            case BoundUnmatchedSwitch unmatched: return EmitUnmatchedSwitch(unmatched);
            case BoundUnary unary: return EmitUnary(unary);
            case BoundBinary binary: return EmitBinary(binary);
            case BoundConditional conditional: return EmitConditional(conditional, movesTrueArm: false);
            case BoundLet held: return EmitLet(held);
            case BoundFunctionReference reference:
                ReachedModules.Add(reference.Function.ModuleName);
                return new Val(Symbol(reference.Function), "ptr", reference.Type);
            case BoundIndirectCall indirect: return EmitIndirectCall(indirect);
            case BoundClosureCreate closure: return EmitClosureCreate(closure);
            case BoundClosureCall closureCall: return EmitClosureCall(closureCall);
            case BoundClosureEqual same: return EmitClosureEqual(same);
            case BoundAssignment assignment: return EmitAssignment(assignment);
            case BoundIncrement increment: return EmitIncrement(increment);
            case BoundCall call: return EmitCall(call);
            case BoundNew newExpression: return EmitNew(newExpression);
            case BoundStructNew filled: return EmitStructNew(filled);
            case BoundClosure closure: return EmitClosure(closure);
            case BoundNewArray newArray: return EmitNewArray(newArray);
            case BoundArrayFill fill: return EmitArrayFill(fill);
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
            case BoundSlotValue read: return EmitSlotValue(read);
            case BoundSlotFill fill: return EmitSlotFill(fill);
            case BoundTry attempt: return EmitTry(attempt);

            default:
                throw Unhandled(expression, expression.Span);
        }
    }

    /// <summary>
    /// <c>let x = value in body</c>.
    ///
    /// Borrowed unless asked otherwise: whatever produced the value is a
    /// temporary the statement will drop. An owned one takes a +1 of its own,
    /// released with the statement's temporaries, and holds a copy of a struct
    /// taken now, because the storage it came from may be written before the
    /// name is read.
    ///
    /// A struct, a tuple, a variant and an inline array are all held by
    /// address, so the name is that address. Everything else goes in a slot,
    /// because that is what a read of a local reads through.
    /// </summary>
    private Val EmitLet(BoundLet held)
    {
        var local = held.Local;
        bool byAddress = IsHeldByAddress(local);

        if (held.IsOwned)
        {
            NameLet(held);
            var result = EmitOwnable(held.Body);
            _soleStores.Remove(local);
            return result;
        }

        var value = EmitOwnable(held.Value);
        bool handedOn = value.Hold == Hold.Owned && HandsOnLocal(held);
        bool fallsBack = value.Hold == Hold.Owned && FallsBackFrom(held);

        value = Borrow(value);
        Name(local, value, byAddress);

        if (fallsBack)
        {
            var merged = EmitConditional((BoundConditional)held.Body, movesTrueArm: true);
            Reclaim(value);
            return merged;
        }

        var body = EmitOwnable(held.Body);
        if (!handedOn) return body;

        // The body is the object the value made, so its +1 is the body's.
        Reclaim(value);
        return Fresh(body);
    }

    /// <summary>Gives the name a <c>let</c> binds its value, keeping nothing past the statement.</summary>
    private void NameLet(BoundLet held)
    {
        var local = held.Local;
        var type = local.Type;
        bool byAddress = IsHeldByAddress(local);

        if (!held.IsOwned)
        {
            Name(local, EmitExpression(held.Value), byAddress);
            return;
        }

        var kept = EmitOwned(held.Value);

        if (byAddress && kept.Hold != Hold.Owned)
        {
            string copy = Alloca(LlvmTypeOf(type), local.Name);
            MemCopy(copy, kept.Ref, type.Size);
            kept = kept with { Ref = copy };
        }

        if (kept.Hold == Hold.Owned)
        {
            TrackTemporary(kept.Ref, type);
            if (IsSoleStore(held)) _soleStores[local] = kept;
        }

        Name(local, kept, byAddress);
    }

    /// <summary>
    /// True when the one use of what an owned <c>let</c> holds is the whole
    /// value of a store that every path through the body makes: a
    /// deconstruction's <c>(a, b) = (b, a)</c>. The store is then handed the
    /// let's own +1.
    /// </summary>
    private static bool IsSoleStore(BoundLet held) =>
        LocalUseCounter.Uses(held.Body, held.Local) == 1 && StoresOnEveryPath(held.Body, held.Local);

    private static bool StoresOnEveryPath(BoundExpression expression, LocalSymbol local) => expression switch
    {
        BoundAssignment assignment => ReadsOnly(assignment.Value, local),
        BoundLet inner => StoresOnEveryPath(inner.Body, local),
        BoundSequence sequence =>
            sequence.Before.Any(side => StoresOnEveryPath(side, local))
            || StoresOnEveryPath(sequence.Value, local),
        _ => false,
    };

    /// <summary>True for a read of the local, through conversions that pass ownership.</summary>
    private static bool ReadsOnly(BoundExpression expression, LocalSymbol local) => expression switch
    {
        BoundLocalAccess read => ReferenceEquals(read.Local, local),
        BoundConversion conversion => PassesOwnership(conversion) && ReadsOnly(conversion.Operand, local),
        _ => false,
    };

    /// <summary>The owned <c>let</c> a store's value reads for the last time, or null.</summary>
    private LocalSymbol? SoleStoreOf(BoundExpression value)
    {
        while (value is BoundConversion conversion && PassesOwnership(conversion))
            value = conversion.Operand;

        return value is BoundLocalAccess { Local: var local } && _soleStores.ContainsKey(local)
            ? local
            : null;
    }

    private static bool IsHeldByAddress(LocalSymbol local) =>
        local.Type is StructTypeSymbol or FixedArrayTypeSymbol;

    /// <summary>Where a name a <c>let</c> binds is read from.</summary>
    private void Name(LocalSymbol local, Val value, bool byAddress)
    {
        if (byAddress)
        {
            _slots[local] = value.Ref;
            return;
        }

        string llvmType = LlvmTypeOf(local.Type);
        string slot = Alloca(llvmType, local.Name);
        _slots[local] = slot;
        Line($"store {llvmType} {value.Ref}, ptr {slot}");
    }

    /// <summary>
    /// Emits an expression for what it does, and keeps nothing it yields.
    ///
    /// An assignment is the reason: its value goes into the slot and nowhere
    /// else, so an owned one is moved there rather than retained there and
    /// released at the end of the statement.
    /// </summary>
    private void EmitDiscarded(BoundExpression expression)
    {
        switch (expression)
        {
            case BoundAssignment assignment
                when assignment.Target is not BoundFieldAccess { Field.IsBitField: true }:
            {
                if (assignment.DeclaresLocal is { } declared)
                    DeclareExpressionLocal(declared);

                string address = EmitAddress(assignment.Target);

                // The slot holds nothing yet, so there is nothing to let go of.
                if (assignment.IsInitialization)
                {
                    InitializeWith(address, EmitOwned(assignment.Value), assignment.Target.Type);
                    return;
                }

                if (SoleStoreOf(assignment.Value) is { } last)
                {
                    var moved = EmitOwnable(assignment.Value);
                    Reclaim(_soleStores[last]);
                    _soleStores.Remove(last);
                    MoveInto(address, moved, assignment.Target.Type);
                    return;
                }

                var value = EmitOwned(assignment.Value);
                MoveInto(address, value, assignment.Target.Type);
                return;
            }

            case BoundSequence sequence:
                foreach (var side in sequence.Before) EmitDiscarded(side);
                EmitDiscarded(sequence.Value);
                return;

            // What an assignment holds while its value is evaluated.
            case BoundLet held:
                NameLet(held);
                EmitDiscarded(held.Body);
                _soleStores.Remove(held.Local);
                return;

            default:
                EmitExpression(expression);
                return;
        }
    }

    /// <summary>A node no case of the emitter handles, which only a compiler bug can put there.</summary>
    private static InternalCompilerError Unhandled(object node, SourceSpan span) =>
        new($"the emitter has no case for {node.GetType().Name}", span);

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
            _ => throw new InternalCompilerError(
                $"a literal holding {literal.Value?.GetType().Name ?? "null"}", literal.Span),
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
    private static string FormatFloating(double value, TypeSymbol type) => type switch
    {
        PrimitiveTypeSymbol { Kind: PrimitiveKind.Float } => FormatDouble((float)value),
        PrimitiveTypeSymbol { Kind: PrimitiveKind.NDouble } =>
            FormatFloatAs(value, Binding.TargetPlatform.Current.LongDoubleType),
        _ => FormatDouble(value),
    };

    /// <summary>
    /// A double's value as a constant of <paramref name="llvmType"/>, which
    /// holds every double exactly: x87's <c>0xK</c> spelling, sign and exponent
    /// then the 64-bit significand with its integer bit, or IEEE quad's
    /// <c>0xL</c>, its low 64 bits first.
    /// </summary>
    public static string FormatFloatAs(double value, string llvmType)
    {
        if (llvmType is "float" or "double") return FormatDouble(value);

        ulong bits = BitConverter.DoubleToUInt64Bits(value);
        ulong sign = bits >> 63;
        int exponent = (int)((bits >> 52) & 0x7FF);
        ulong fraction = bits & 0xFFFFFFFFFFFFFUL;

        // The exponent and significand in the wider format's own terms.
        int wide;
        ulong significand;
        if (exponent == 0x7FF)
        {
            wide = 0x7FFF;
            significand = fraction;
        }
        else if (exponent == 0 && fraction == 0)
        {
            wide = 0;
            significand = 0;
        }
        else
        {
            // A subnormal double is normal in either wider format.
            int shift = 0;
            if (exponent == 0)
            {
                while ((fraction & (1UL << 52)) == 0)
                {
                    fraction <<= 1;
                    shift++;
                }
                fraction &= 0xFFFFFFFFFFFFFUL;
                exponent = 1;
            }

            wide = exponent - 1023 - shift + 16383;
            significand = fraction;
        }

        if (llvmType == "x86_fp80")
        {
            // The integer bit is explicit, and set for every number but zero.
            ulong integer = wide is 0 ? 0 : 1UL << 63;
            ulong mantissa = integer | (significand << 11);
            return $"0xK{(sign << 15) | (ulong)wide:X4}{mantissa:X16}";
        }

        // fp128: 1 sign bit, 15 exponent bits, 112 fraction bits.
        ulong high = (sign << 63) | ((ulong)wide << 48) | (significand >> 4);
        ulong low = significand << 60;
        return $"0xL{low:X16}{high:X16}";
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
            double number => FormatFloating(number, constant.Type),
            float number => FormatFloating(number, constant.Type),
            ulong number => FormatInteger(number, constant.Type),
            string s when IsObjCReference(constant.Type) => ConstantStringObject(s),
            string s => InternBytes(s),
            _ => throw new InternalCompilerError(
                $"a constant holding {constant.Value?.GetType().Name ?? "null"}", access.Span),
        };
        return new Val(text, llvmType, constant.Type);
    }

    /// <summary>Computes the address of an lvalue expression.</summary>
    private string EmitAddress(BoundExpression expression)
    {
        switch (expression)
        {
            case BoundStaticAccess shared:
                ReachedModules.Add(shared.Static.ModuleName);
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

        // One unsigned compare covers both ends, as it does for an array: a
        // negative index sign-extends to a very large unsigned value. The length
        // is a constant here rather than a load, because it was in the type.
        string length = inline.Length.ToString();
        var position = PositionOf(offset, index.Origin, length);
        string widened = position.Index;
        string inRange = Emit("i1", $"icmp ult {Word} {widened}, {length}");

        string okLabel = NextLabel("bounds.ok");
        string failLabel = NextLabel("bounds.fail");
        Terminator($"br i1 {inRange}, label %{okLabel}, label %{failLabel}");

        Label(failLabel);
        FailPosition(position, length);
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
    private void StoreBitField(BoundFieldAccess access, Val value) =>
        StoreBitField(EmitFieldAddress(access), access.Field, value);

    /// <summary>The same, into a storage unit whose address is already known.</summary>
    private void StoreBitField(string address, FieldSymbol field, Val value)
    {
        int width = field.BitWidth!.Value;
        int bytes = AccessBytes(field);
        int bits = bytes * 8;
        string unit = $"i{bits}";

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
        field.ContainingType is ClassTypeSymbol { ObjC: ObjCClassKind.Defined } objc
            ? ObjCFieldAddress(objectRef, objc, field)
            : Emit("ptr",
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

    /// <summary>
    /// The arm a switch expression over an enum has for a value that is none
    /// of its members. The call does not come back; the zero after it is only
    /// so the conditional it is an arm of has something to merge.
    /// </summary>
    private Val EmitUnmatchedSwitch(BoundUnmatchedSwitch unmatched)
    {
        Line($"call void @sl_switch_unmatched(ptr {InternBytes(unmatched.Subject.Name)})");
        return EmitExpression(new BoundDefault(unmatched.Span, unmatched.Type));
    }

    /// <summary>
    /// Gives a variable no statement declared a slot, cleared: the one an
    /// <c>out var x</c> introduced, or a name a pattern binds.
    ///
    /// Cleared because the language has no definite-assignment analysis: a
    /// callee that returns without writing would otherwise leave the caller
    /// reading whatever the stack held. Zero is not the right answer either,
    /// but it is an answer rather than a hazard, and it matches what a new
    /// array and an owned local already promise.
    ///
    /// An owned slot is cleared on entry and as it is released, never here.
    /// A declaration inside a loop's condition runs on every pass, and a
    /// store here would drop what the last pass left without releasing it.
    /// </summary>
    private void DeclareExpressionLocal(LocalSymbol local)
    {
        if (_slots.ContainsKey(local)) return;

        string llvmType = LlvmTypeOf(local.Type);
        string slot = Alloca(llvmType, local.Name);
        _slots[local] = slot;

        if (local.Type.IsManagedSlot() ||
            local.Type is StructTypeSymbol { } owning && owning.CarriesReferences())
        {
            ZeroOnEntry(slot, llvmType);
            TrackOwnedLocal(slot, local.Type);
            _clearedOnRelease.Add(slot);
        }
        else
        {
            Line($"store {llvmType} {ZeroOf(llvmType)}, ptr {slot}");
        }
    }

    /// <summary>
    /// Works out the place, then the value, then stores: C#'s order, so
    /// <c>a[i++] = i</c> stores the new <c>i</c> into the old element.
    /// </summary>
    private Val EmitAssignment(BoundAssignment assignment)
    {
        // A bit-field shares its storage unit with its neighbours, so writing it
        // is a read, a splice and a write rather than a store.
        if (assignment.Target is BoundFieldAccess { Field.IsBitField: true } bitField)
        {
            string unit = EmitFieldAddress(bitField);
            var bits = EmitExpression(assignment.Value);
            StoreBitField(unit, bitField.Field, bits);
            return bits;
        }

        if (assignment.DeclaresLocal is { } declared)
            DeclareExpressionLocal(declared);

        string address = EmitAddress(assignment.Target);
        var value = EmitExpression(assignment.Value);
        StoreInto(address, value, assignment.Target.Type);
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

        if (Binder.IsObjCType(test.Tested))
            return new Val(EmitObjCTest(value.Ref, test.Tested), "i1", test.Type);

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
