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
/// Slices, ranges and the bounds checks that stand behind both.
/// </summary>
public sealed partial class LlvmEmitter
{
    // ============================================================ slices

    /// <summary>The address of one of a slice's three fields.</summary>
    private string SliceField(string slice, SliceTypeSymbol type, int index) =>
        Emit("ptr", $"getelementptr inbounds {StructName(type)}, ptr {slice}, i32 0, i32 {index}");

    private string SliceLength(string slice, SliceTypeSymbol type) =>
        Emit("i64", $"load i64, ptr {SliceField(slice, type, 2)}");

    /// <summary>
    /// <c>a[from:to]</c>: the array this names, the offset into it, and how far
    /// it runs.
    ///
    /// Slicing a slice narrows rather than nests, so the array stored is the one
    /// underneath either way and the offsets add. That keeps a slice one
    /// indirection deep however many times it has been cut.
    /// </summary>
    private Val EmitSlice(BoundSlice expression)
    {
        var type = (SliceTypeSymbol)expression.Type;
        var source = EmitExpression(expression.Target);

        string array, baseOffset, sourceLength;

        if (expression.Target.Type is SliceTypeSymbol inner)
        {
            array = Emit("ptr", $"load ptr, ptr {SliceField(source.Ref, inner, 0)}");
            baseOffset = Emit("i64", $"load i64, ptr {SliceField(source.Ref, inner, 1)}");
            sourceLength = SliceLength(source.Ref, inner);
        }
        else
        {
            array = source.Ref;
            baseOffset = "0";
            string lengthSlot = Emit("ptr",
                $"getelementptr inbounds i8, ptr {array}, i64 {ArrayTypeSymbol.HeaderSize - 8}");
            sourceLength = Emit("i64", $"load i64, ptr {lengthSlot}");
        }

        string from = expression.Start is null
            ? "0"
            : WidenIndex(EmitExpression(expression.Start));

        string to = expression.End is null
            ? sourceLength
            : WidenIndex(EmitExpression(expression.End));

        // from <= to <= length, in one branch: an unsigned compare catches a
        // negative bound too, because it sign-extends to something enormous.
        string ordered = Emit("i1", $"icmp ule i64 {from}, {to}");
        string within = Emit("i1", $"icmp ule i64 {to}, {sourceLength}");
        string valid = Emit("i1", $"and i1 {ordered}, {within}");

        string okLabel = NextLabel("slice.ok");
        string failLabel = NextLabel("slice.fail");
        Terminator($"br i1 {valid}, label %{okLabel}, label %{failLabel}");

        Label(failLabel);
        Line($"call void @sl_slice_bounds_fail(i64 {from}, i64 {to}, i64 {sourceLength})");
        Terminator("unreachable");

        Label(okLabel);

        string slot = Alloca(StructName(type), "slice");
        Line($"store ptr {array}, ptr {SliceField(slot, type, 0)}");
        Line($"store i64 {Emit("i64", $"add i64 {baseOffset}, {from}")}, " +
             $"ptr {SliceField(slot, type, 1)}");
        Line($"store i64 {Emit("i64", $"sub i64 {to}, {from}")}, " +
             $"ptr {SliceField(slot, type, 2)}");

        // The array is retained into the slice's field, exactly as a struct
        // field retains what it holds; the slice is then a +1 temporary.
        Line($"call void @sl_retain(ptr {array})");
        TrackTemporary(slot, type);

        return new Val(slot, "ptr", type);
    }

    /// <summary>
    /// The address of one element of a slice: the array's data, then past the
    /// slice's own offset. The bound checked is the slice's length, not the
    /// array's, which is the whole point of having one.
    /// </summary>
    private string EmitSliceElementAddress(BoundIndex index)
    {
        var type = (SliceTypeSymbol)index.Target.Type;
        var slice = EmitExpression(index.Target);
        var offset = EmitExpression(index.Index);

        string widened = WidenIndex(offset);
        string length = SliceLength(slice.Ref, type);
        string inRange = Emit("i1", $"icmp ult i64 {widened}, {length}");

        string okLabel = NextLabel("bounds.ok");
        string failLabel = NextLabel("bounds.fail");
        Terminator($"br i1 {inRange}, label %{okLabel}, label %{failLabel}");

        Label(failLabel);
        Line($"call void @sl_array_bounds_fail(i64 {widened}, i64 {length})");
        Terminator("unreachable");

        Label(okLabel);
        string array = Emit("ptr", $"load ptr, ptr {SliceField(slice.Ref, type, 0)}");
        string start = Emit("i64", $"load i64, ptr {SliceField(slice.Ref, type, 1)}");
        string data = Emit("ptr",
            $"getelementptr inbounds i8, ptr {array}, i64 {ArrayTypeSymbol.HeaderSize}");

        return Emit("ptr",
            $"getelementptr inbounds {LlvmTypeOf(type.Element)}, ptr {data}, " +
            $"i64 {Emit("i64", $"add i64 {start}, {widened}")}");
    }

    private string EmitArrayElementAddress(BoundIndex index)
    {
        var arrayType = (ArrayTypeSymbol)index.Target.Type;
        var array = EmitExpression(index.Target);
        var offset = EmitExpression(index.Index);

        string widened = WidenIndex(offset);
        string lengthSlot = Emit("ptr", $"getelementptr inbounds i8, ptr {array.Ref}, i64 24");
        string length = Emit("i64", $"load i64, ptr {lengthSlot}");
        string inRange = Emit("i1", $"icmp ult i64 {widened}, {length}");

        string okLabel = NextLabel("bounds.ok");
        string failLabel = NextLabel("bounds.fail");
        Terminator($"br i1 {inRange}, label %{okLabel}, label %{failLabel}");

        Label(failLabel);
        Line($"call void @sl_array_bounds_fail(i64 {widened}, i64 {length})");
        Terminator("unreachable");

        Label(okLabel);
        string data = Emit("ptr",
            $"getelementptr inbounds i8, ptr {array.Ref}, i64 {ArrayTypeSymbol.HeaderSize}");
        return Emit("ptr",
            $"getelementptr inbounds {LlvmTypeOf(arrayType.Element)}, ptr {data}, i64 {widened}");
    }

    /// <summary>
    /// A call through a delegate. The only difference from a direct call is that
    /// the target is a loaded pointer rather than a symbol, so the signature has
    /// to be written out for LLVM to know how to call it.
    /// </summary>
    private Val EmitIndirectCall(BoundIndirectCall call)
    {
        var delegateType = call.DelegateType;
        var returnInfo = ClassifyResult(delegateType.ReturnType);

        // Resolved before the arguments, so an argument that is itself a call
        // cannot disturb the target this one loaded.
        var target = EmitExpression(call.Target);

        var arguments = new List<string>();
        string? sretSlot = null;

        if (returnInfo.Style == PassStyle.Indirect)
        {
            var structType = (StructTypeSymbol)delegateType.ReturnType;
            sretSlot = Alloca(StructName(structType), "call.sret");
            arguments.Add($"ptr sret({StructName(structType)}) {sretSlot}");
        }

        AppendArguments(call.Arguments, arguments);

        string signature = returnInfo.Style == PassStyle.Indirect ? "void" : returnInfo.LlvmType;
        string invocation = $"call {signature} {target.Ref}({string.Join(", ", arguments)})";

        if (returnInfo.Style == PassStyle.Indirect)
        {
            Line(invocation);
            return new Val(sretSlot!, "ptr", delegateType.ReturnType);
        }

        if (delegateType.ReturnType.IsVoid())
        {
            Line(invocation);
            return Val.Void;
        }

        var result = new Val(Emit(signature, invocation), signature, delegateType.ReturnType);
        if (delegateType.ReturnType.NeedsArc()) TrackTemporary(result.Ref, delegateType.ReturnType);
        return result;
    }

    private Val EmitCall(BoundCall call)
    {
        var function = call.Function;
        var returnInfo = ClassifyResult(function.ReturnType);

        var arguments = new List<string>();
        string? sretSlot = null;

        if (returnInfo.Style == PassStyle.Indirect)
        {
            var structType = (StructTypeSymbol)function.ReturnType;
            sretSlot = Alloca(StructName(structType), "call.sret");
            arguments.Add($"ptr sret({StructName(structType)}) {sretSlot}");
        }

        // Held locally, not in a field: an argument may itself be an interface
        // call, and a field would let the inner call overwrite this one's target.
        string? virtualTarget = null;

        if (call.Receiver is not null)
        {
            var receiver = EmitExpression(call.Receiver);
            arguments.Add($"ptr {receiver.Ref}");

            // Resolved before the arguments so the load reads the receiver as it
            // was, whatever the arguments go on to do.
            if (function.ContainingType is ComInterfaceTypeSymbol)
                virtualTarget = LoadComMethod(receiver.Ref, function);
            else if (function.ContainingType is InterfaceTypeSymbol)
                virtualTarget = LoadInterfaceMethod(receiver.Ref, function);
            else if (function.IsDispatched && !call.IsNonVirtual)
                virtualTarget = LoadVirtualMethod(receiver.Ref, function);
        }

        AppendArguments(call.Arguments, arguments);

        string signature = function.IsVariadic
            ? $"{(returnInfo.Style == PassStyle.Indirect ? "void" : returnInfo.LlvmType)} " +
              $"({VariadicSignature(function)})"
            : returnInfo.Style == PassStyle.Indirect ? "void" : returnInfo.LlvmType;

        // An interface method is reached through the object; everything else is
        // a direct call to a known symbol.
        string target = virtualTarget ?? Symbol(function);

        string invocation =
            $"call {signature} {target}({string.Join(", ", arguments)})";

        if (returnInfo.Style == PassStyle.Indirect)
        {
            Line(invocation);
            if (function.ReturnType.CarriesReferences())
                TrackTemporary(sretSlot!, function.ReturnType);
            return new Val(sretSlot!, "ptr", function.ReturnType);
        }

        if (function.ReturnType.IsVoid())
        {
            Line(invocation);
            return Val.Void;
        }

        string result = Emit(returnInfo.LlvmType, invocation);

        if (returnInfo.Style == PassStyle.Coerce)
        {
            // Land the register-sized struct back in memory so it has an address.
            var structType = (StructTypeSymbol)function.ReturnType;
            string slot = Alloca(StructName(structType), "call.result");
            StoreCoerced(slot, result, returnInfo);
            if (structType.CarriesReferences()) TrackTemporary(slot, structType);
            return new Val(slot, "ptr", function.ReturnType);
        }

        // A returned reference arrives at +1 and is dropped when the statement ends.
        if (function.ReturnType.NeedsArc())
            TrackTemporary(result, function.ReturnType);

        return new Val(result, returnInfo.LlvmType, function.ReturnType);
    }

    /// <summary>
    /// Builds a variant value: zeroed, its tag set, and each argument stored
    /// into the field of the case's payload it belongs to.
    ///
    /// Zeroing first is what lets each field go in through the ordinary owning
    /// store: the slot being written starts null, so its release is a no-op. It
    /// also settles the bytes of the payload that this case does not use, which
    /// matters because a variant is copied whole and compared as bytes by
    /// nobody, but read by a debugger and written to a file by somebody.
    ///
    /// The finished value is a +1 temporary, exactly like one returned by a call.
    /// </summary>
    private Val EmitVariantConstruction(BoundVariantConstruction expression)
    {
        var variant = (VariantTypeSymbol)expression.Type;
        string slot = Alloca(StructName(variant), expression.Case.Name);
        Line($"store {StructName(variant)} zeroinitializer, ptr {slot}");

        Line($"store i8 {expression.Case.Tag}, ptr {TagAddress(slot, variant)}");

        if (expression.Case.Payload is { } payload)
        {
            string address = PayloadAddress(slot, variant);

            for (int i = 0; i < expression.Arguments.Count; i++)
            {
                var field = payload.Fields[i];
                string target = Emit("ptr",
                    $"getelementptr inbounds {StructName(payload)}, ptr {address}, " +
                    $"i32 0, i32 {field.Index}");

                StoreInto(target, EmitExpression(expression.Arguments[i]), field.Type);
            }
        }

        if (variant.CarriesReferences()) TrackTemporary(slot, variant);
        return new Val(slot, "ptr", variant);
    }

    /// <summary>
    /// <c>v.Circle</c> — one load and one comparison. The binder has already
    /// decided this is a question about the tag rather than a field read.
    /// </summary>
    private Val EmitVariantTest(BoundVariantTest expression)
    {
        var variant = expression.Case.DeclaringVariant;
        var value = EmitExpression(expression.Value);

        string tag = Emit("i8", $"load i8, ptr {TagAddress(value.Ref, variant)}");
        return new Val(
            Emit("i1", $"icmp eq i8 {tag}, {expression.Case.Tag}"),
            "i1", PrimitiveTypeSymbol.Bool);
    }

    /// <summary>
    /// A payload, or one field of it. No tag is checked: the binder only makes
    /// this node where it has already established which case is present, and
    /// checking again would be asking a question whose answer is known.
    /// </summary>
    private Val EmitVariantPayload(BoundVariantPayload expression)
    {
        var variant = expression.Case.DeclaringVariant;
        var payload = expression.Case.Payload!;
        var value = EmitExpression(expression.Receiver);

        string address = PayloadAddress(value.Ref, variant);

        if (expression.Field is not { } field)
            return new Val(address, "ptr", payload);

        string slot = Emit("ptr",
            $"getelementptr inbounds {StructName(payload)}, ptr {address}, " +
            $"i32 0, i32 {field.Index}");

        return field.Type is StructTypeSymbol
            ? new Val(slot, "ptr", field.Type)
            : new Val(Emit(LlvmTypeOf(field.Type),
                $"load {LlvmTypeOf(field.Type)}, ptr {slot}"), LlvmTypeOf(field.Type), field.Type);
    }

    /// <summary>Where the tag sits: the first field, and so the value's own address.</summary>
    private string TagAddress(string value, VariantTypeSymbol variant) =>
        Emit("ptr", $"getelementptr inbounds {StructName(variant)}, ptr {value}, i32 0, i32 0");

    /// <summary>
    /// Where a variant's payload starts. The tag is the first field and the
    /// payload the second, so this is a constant offset the C layout already
    /// decided; every case's fields are then read from it through that case's
    /// own struct, which is what overlapping them means.
    /// </summary>
    private string PayloadAddress(string value, VariantTypeSymbol variant) =>
        Emit("ptr", $"getelementptr inbounds {StructName(variant)}, ptr {value}, i32 0, i32 1");

    private string VariadicSignature(FunctionSymbol function)
    {
        var parts = function.Parameters
            .SelectMany(p => Declared(ClassifyParameter(p)))
            .ToList();
        parts.Add("...");
        return string.Join(", ", parts);
    }

    /// <summary>
    /// Lowers each argument to its ABI form. The callee is not needed: every
    /// argument was already converted to the parameter's type during binding, so
    /// the expression's own type is the one the ABI classifies.
    /// </summary>
    private void AppendArguments(
        IReadOnlyList<BoundExpression> expressions, List<string> arguments)
    {
        for (int i = 0; i < expressions.Count; i++)
            AppendArgument(EmitExpression(expressions[i]), expressions[i].Type, arguments);
    }

    /// <summary>Lowers one already-emitted value to its ABI form.</summary>
    private void AppendArgument(Val value, TypeSymbol type, List<string> arguments)
    {
        if (type is StructTypeSymbol structType)
        {
            var info = ClassifyValue(structType);
            if (info.Style == PassStyle.Indirect)
            {
                // Win64 passes a pointer to a copy the caller owns.
                string copy = Alloca(StructName(structType), "arg.copy");
                MemCopy(copy, value.Ref, structType.Size);
                arguments.Add($"ptr byval({StructName(structType)}) {copy}");
            }
            else
            {
                // One argument per register, each read from the eight bytes it
                // stands for.
                for (int piece = 0; piece < info.Pieces.Count; piece++)
                {
                    string spelling = info.Pieces[piece];
                    string address = PieceAddress(value.Ref, piece);
                    arguments.Add(
                        $"{spelling} {Emit(spelling, $"load {spelling}, ptr {address}")}");
                }
            }
            return;
        }

        arguments.Add($"{value.LlvmType} {value.Ref}");
    }
}
