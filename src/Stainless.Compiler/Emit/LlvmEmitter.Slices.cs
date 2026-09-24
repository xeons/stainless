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
/// Slices, ranges and the bounds checks that stand behind both.
/// </summary>
public sealed partial class LlvmEmitter
{
    // ============================================================ slices

    /// <summary>The address of one of a slice's three fields.</summary>
    private string SliceField(string slice, SliceTypeSymbol type, int index) =>
        Emit("ptr", $"getelementptr inbounds {StructName(type)}, ptr {slice}, i32 0, i32 {index}");

    // A slice's offset and length are `nuint` fields, so both narrow with the
    // target. Loading one as i64 on a 32-bit build would read the field after it.
    private string SliceLength(string slice, SliceTypeSymbol type) =>
        Emit(Word, $"load {Word}, ptr {SliceField(slice, type, 2)}");

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
            baseOffset = Emit(Word, $"load {Word}, ptr {SliceField(source.Ref, inner, 1)}");
            sourceLength = SliceLength(source.Ref, inner);
        }
        else
        {
            array = source.Ref;
            baseOffset = "0";
            string lengthSlot = Emit("ptr",
                $"getelementptr inbounds i8, ptr {array}, i64 {RuntimeLayout.ArrayLength}");
            sourceLength = Emit(Word, $"load {Word}, ptr {lengthSlot}");
        }

        string from = expression.Start is null
            ? "0"
            : WidenIndex(EmitExpression(expression.Start));

        string to = expression.End is null
            ? sourceLength
            : WidenIndex(EmitExpression(expression.End));

        // from <= to <= length, in one branch: an unsigned compare catches a
        // negative bound too, because it sign-extends to something enormous.
        string ordered = Emit("i1", $"icmp ule {Word} {from}, {to}");
        string within = Emit("i1", $"icmp ule {Word} {to}, {sourceLength}");
        string valid = Emit("i1", $"and i1 {ordered}, {within}");

        string okLabel = NextLabel("slice.ok");
        string failLabel = NextLabel("slice.fail");
        Terminator($"br i1 {valid}, label %{okLabel}, label %{failLabel}");

        Label(failLabel);
        Line($"call void @sl_slice_bounds_fail({Word} {from}, {Word} {to}, {Word} {sourceLength})");
        Terminator("unreachable");

        Label(okLabel);

        string slot = Alloca(StructName(type), "slice");
        Line($"store ptr {array}, ptr {SliceField(slot, type, 0)}");
        Line($"store {Word} {Emit(Word, $"add {Word} {baseOffset}, {from}")}, " +
             $"ptr {SliceField(slot, type, 1)}");
        Line($"store {Word} {Emit(Word, $"sub {Word} {to}, {from}")}, " +
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
        string inRange = Emit("i1", $"icmp ult {Word} {widened}, {length}");

        string okLabel = NextLabel("bounds.ok");
        string failLabel = NextLabel("bounds.fail");
        Terminator($"br i1 {inRange}, label %{okLabel}, label %{failLabel}");

        Label(failLabel);
        Line($"call void @sl_array_bounds_fail({Word} {widened}, {Word} {length})");
        Terminator("unreachable");

        Label(okLabel);
        string array = Emit("ptr", $"load ptr, ptr {SliceField(slice.Ref, type, 0)}");
        string start = Emit(Word, $"load {Word}, ptr {SliceField(slice.Ref, type, 1)}");
        string data = Emit("ptr",
            $"getelementptr inbounds i8, ptr {array}, i64 {ArrayTypeSymbol.HeaderSize}");

        return Emit("ptr",
            $"getelementptr inbounds {LlvmTypeOf(type.Element)}, ptr {data}, " +
            $"{Word} {Emit(Word, $"add {Word} {start}, {widened}")}");
    }

    private string EmitArrayElementAddress(BoundIndex index)
    {
        var arrayType = (ArrayTypeSymbol)index.Target.Type;
        var array = EmitExpression(index.Target);
        var offset = EmitExpression(index.Index);

        string widened = WidenIndex(offset);
        string lengthSlot = Emit("ptr",
            $"getelementptr inbounds i8, ptr {array.Ref}, i64 {RuntimeLayout.ArrayLength}");
        string length = Emit(Word, $"load {Word}, ptr {lengthSlot}");
        string inRange = Emit("i1", $"icmp ult {Word} {widened}, {length}");

        string okLabel = NextLabel("bounds.ok");
        string failLabel = NextLabel("bounds.fail");
        Terminator($"br i1 {inRange}, label %{okLabel}, label %{failLabel}");

        Label(failLabel);
        Line($"call void @sl_array_bounds_fail({Word} {widened}, {Word} {length})");
        Terminator("unreachable");

        Label(okLabel);
        string data = Emit("ptr",
            $"getelementptr inbounds i8, ptr {array.Ref}, i64 {ArrayTypeSymbol.HeaderSize}");
        return Emit("ptr",
            $"getelementptr inbounds {LlvmTypeOf(arrayType.Element)}, ptr {data}, {Word} {widened}");
    }

    /// <summary>
    /// A call through a delegate. The only difference from a direct call is that
    /// the target is a loaded pointer rather than a symbol, so the signature has
    /// to be written out for LLVM to know how to call it.
    /// </summary>
    /// <summary>
    /// Building a closure: two stores, and a retain on the object.
    ///
    /// The function word is the method's own address. Nothing is wrapped and
    /// nothing is shuffled, because a method already takes its receiver as
    /// argument zero -- which is the whole reason this representation is two
    /// words rather than a generated class.
    /// </summary>
    private Val EmitClosureCreate(BoundClosureCreate closure)
    {
        var type = closure.ClosureType;
        string slot = Alloca(StructName(type), "closure");

        string functionSlot = StructFieldAddress(slot, type, type.Function!);
        Line($"store ptr {Symbol(closure.Function)}, ptr {functionSlot}, align {TargetPlatform.Current.PointerWidth}");

        string receiverSlot = StructFieldAddress(slot, type, type.Receiver!);

        // A plain function's thunk has no object, and ignores the null it is
        // handed in place of one.
        if (closure.Receiver is null)
        {
            Line($"store ptr null, ptr {receiverSlot}, align 8");
            TrackTemporary(slot, type);
            return new Val(slot, "ptr", type);
        }

        var receiver = EmitExpression(closure.Receiver);

        // +1, and tracked, exactly as a struct-returning call's result is: what
        // comes out of here owns its object until the statement ends or
        // something stores it.
        Retain(receiver.Ref, type.Receiver!.Type);
        Line($"store ptr {receiver.Ref}, ptr {receiverSlot}, align {TargetPlatform.Current.PointerWidth}");

        TrackTemporary(slot, type);
        return new Val(slot, "ptr", type);
    }

    /// <summary>
    /// Comparing two: both words, and each side loaded once.
    /// </summary>
    private Val EmitClosureEqual(BoundClosureEqual comparison)
    {
        var type = comparison.ClosureType;

        var left = EmitExpression(comparison.Left);
        var right = EmitExpression(comparison.Right);

        string leftFunction = Emit("ptr",
            $"load ptr, ptr {StructFieldAddress(left.Ref, type, type.Function!)}, align {TargetPlatform.Current.PointerWidth}");
        string rightFunction = Emit("ptr",
            $"load ptr, ptr {StructFieldAddress(right.Ref, type, type.Function!)}, align {TargetPlatform.Current.PointerWidth}");

        string leftReceiver = Emit("ptr",
            $"load ptr, ptr {StructFieldAddress(left.Ref, type, type.Receiver!)}, align {TargetPlatform.Current.PointerWidth}");
        string rightReceiver = Emit("ptr",
            $"load ptr, ptr {StructFieldAddress(right.Ref, type, type.Receiver!)}, align {TargetPlatform.Current.PointerWidth}");

        string predicate = comparison.Negated ? "ne" : "eq";
        string sameFunction = Emit("i1", $"icmp {predicate} ptr {leftFunction}, {rightFunction}");
        string sameReceiver = Emit("i1", $"icmp {predicate} ptr {leftReceiver}, {rightReceiver}");

        // Equal wants both, different wants either.
        string combine = comparison.Negated ? "or" : "and";
        string answer = Emit("i1", $"{combine} i1 {sameFunction}, {sameReceiver}");

        return new Val(answer, "i1", PrimitiveTypeSymbol.Bool);
    }

    /// <summary>
    /// Calling one: load both words, and put the object in front of the
    /// arguments the caller wrote.
    /// </summary>
    private Val EmitClosureCall(BoundClosureCall call)
    {
        var type = call.ClosureType;
        var returnInfo = ClassifyResult(type.ReturnType);

        // Resolved before the arguments, for the reason a delegate's target is.
        var held = EmitExpression(call.Target);

        string functionSlot = StructFieldAddress(held.Ref, type, type.Function!);
        string function = Emit("ptr", $"load ptr, ptr {functionSlot}, align {TargetPlatform.Current.PointerWidth}");

        string receiverSlot = StructFieldAddress(held.Ref, type, type.Receiver!);
        string receiver = Emit("ptr", $"load ptr, ptr {receiverSlot}, align {TargetPlatform.Current.PointerWidth}");

        var arguments = new List<string>();
        string? sretSlot = null;

        if (returnInfo.Style == PassStyle.Indirect)
        {
            var structType = (StructTypeSymbol)type.ReturnType;
            sretSlot = Alloca(StructName(structType), "call.sret");
            arguments.Add($"ptr sret({StructName(structType)}) {sretSlot}");
        }

        arguments.Add($"ptr {receiver}");
        AppendArguments(call.Arguments, arguments);

        string signature = returnInfo.Style == PassStyle.Indirect ? "void" : returnInfo.LlvmType;
        string invocation = $"call {signature} {function}({string.Join(", ", arguments)})";

        if (returnInfo.Style == PassStyle.Indirect)
        {
            Line(invocation);
            return new Val(sretSlot!, "ptr", type.ReturnType);
        }

        if (type.ReturnType.IsVoid())
        {
            Line(invocation);
            return Val.Void;
        }

        return Landed(Emit(returnInfo.LlvmType, invocation), returnInfo, type.ReturnType);
    }

    /// <summary>
    /// What a call answered with, as the rest of the emitter expects to find
    /// it.
    ///
    /// A struct small enough to travel in registers comes back as a value and
    /// not as an address, and everything downstream of a struct expects an
    /// address -- so it is put in a slot here. Missing this is not a
    /// diagnostic: the value is simply used as a pointer, and the load reads
    /// whatever the first eight bytes of the struct happened to be.
    ///
    /// The direct call path has always done this. The two indirect ones did
    /// not, and nothing noticed until `Optional&lt;T&gt;.FlatMap` started
    /// taking a closure rather than an interface -- an interface call is a
    /// direct call through a vtable slot, so it went the other way.
    /// </summary>
    private Val Landed(string result, ArgInfo returnInfo, TypeSymbol returnType)
    {
        if (returnInfo.Style == PassStyle.Coerce)
        {
            var structType = (StructTypeSymbol)returnType;
            string slot = Alloca(StructName(structType), "call.result");
            StoreCoerced(slot, result, returnInfo);
            if (structType.CarriesReferences()) TrackTemporary(slot, structType);
            return new Val(slot, "ptr", returnType);
        }

        // A returned reference arrives at +1 and is dropped when the statement ends.
        if (returnType.NeedsArc()) TrackTemporary(result, returnType);

        return new Val(result, returnInfo.LlvmType, returnType);
    }

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

        // **The convention is the delegate's, and there is nothing else to ask.**
        // A direct call reads it off the function it names; a call through a
        // pointer has no symbol behind it, so the type is the only thing that
        // knows -- which is why `delegate __stdcall` exists at all. Empty on
        // every target but x86, where it is the difference between a call that
        // works and a stack that does not come back.
        string convention = ConventionPrefix(call.DelegateType.Convention);
        string invocation = $"call {convention}{signature} {target.Ref}({string.Join(", ", arguments)})";

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

        return Landed(Emit(signature, invocation), returnInfo, delegateType.ReturnType);
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

        int declaredFirst = arguments.Count;
        AppendArguments(call.Arguments, arguments);
        MarkRegisters(function, arguments, declaredFirst);

        string signature = function.IsVariadic
            ? $"{(returnInfo.Style == PassStyle.Indirect ? "void" : returnInfo.LlvmType)} " +
              $"({VariadicSignature(function)})"
            : returnInfo.Style == PassStyle.Indirect ? "void" : returnInfo.LlvmType;

        // An interface method is reached through the object; everything else is
        // a direct call to a known symbol.
        string target = virtualTarget ?? Symbol(function);

        // The convention goes on the call as well as on the callee: LLVM does
        // not look it up, and a call that disagrees is undefined rather than
        // refused. A virtual target is reached through a pointer and carries the
        // declared convention of the method it came from.
        string invocation =
            $"call {Convention(function)}{signature} {target}({string.Join(", ", arguments)})";

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
    /// <summary>
    /// <c>(a, b)</c>: a slot, zeroed, with each element stored into its field.
    ///
    /// Zeroed first so that every field goes in through the ordinary owning
    /// store -- the slot starts null, so its release is a no-op -- which is the
    /// same reason a variant is built this way.
    /// </summary>
    private Val EmitTupleCreate(BoundTupleCreate expression)
    {
        var tuple = expression.Tuple;
        string slot = Alloca(StructName(tuple), "tuple");
        Line($"store {StructName(tuple)} zeroinitializer, ptr {slot}");

        for (int i = 0; i < expression.Elements.Count; i++)
        {
            var field = tuple.Fields[i];
            string target = Emit("ptr",
                $"getelementptr inbounds {StructName(tuple)}, ptr {slot}, " +
                $"i32 0, i32 {FieldSlot(tuple, field)}");

            StoreInto(target, EmitExpression(expression.Elements[i]), field.Type);
        }

        if (tuple.CarriesReferences()) TrackTemporary(slot, tuple);
        return new Val(slot, "ptr", tuple);
    }

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
                    $"i32 0, i32 {FieldSlot(payload, field)}");

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
    /// <summary>
    /// <c>try e</c>: evaluate once, branch, and either carry on or return.
    ///
    /// The failure arm emits an ordinary <c>return</c> statement, which is the
    /// point of the binder having built one -- reference counts, scope
    /// releases and an sret struct return are all handled by the code that
    /// already handles them, rather than by a second copy here that would
    /// drift.
    /// </summary>
    private Val EmitTry(BoundTry expression)
    {
        string failLabel = NextLabel("try.fail");
        string okLabel = NextLabel("try.ok");

        // One slot, so both arms read the same value and the operand runs once.
        var held = expression.Slot.Type;
        string slot = Alloca(LlvmTypeOf(held), "try");
        _slots[expression.Slot] = slot;

        // Blanked first, for the reason a declared local is: an alloca holds
        // whatever was on the stack, and the store below releases what it is
        // replacing. Without this it released a Result made of rubbish, which
        // is exactly as bad as it sounds -- it corrupted the heap and the
        // program went back round a loop it had already left.
        if (held.IsManagedSlot()) Line($"store ptr null, ptr {slot}");
        else if (held is StructTypeSymbol owning && owning.CarriesReferences())
            Line($"store {StructName(owning)} zeroinitializer, ptr {slot}");

        var value = EmitExpression(expression.Operand);
        StoreInto(slot, value, held);

        // The store took a reference, so something has to give it back. Both
        // arms read the payload out and whatever consumes it takes a reference
        // of its own, and a return retains before it flushes -- so the end of
        // the statement is where this slot stops owning what it holds.
        if (held.CarriesReferences()) TrackTemporary(slot, held);

        var test = EmitExpression(expression.Test);
        Terminator($"br i1 {test.Ref}, label %{okLabel}, label %{failLabel}");

        // The failure arm returns, and a return releases every temporary this
        // statement has made and then forgets them. They are still live on the
        // arm below, which has not returned, so the list is put back -- one
        // branch's cleanup MUST NOT stand for the other's.
        var pending = new List<(string Ref, TypeSymbol Type)>(_pendingReleases);

        Label(failLabel);
        EmitStatement(expression.OnFailure);
        if (!_blockTerminated) Terminator($"br label %{okLabel}");

        _pendingReleases.Clear();
        _pendingReleases.AddRange(pending);

        Label(okLabel);
        return EmitExpression(expression.OnSuccess);
    }

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
            $"i32 0, i32 {FieldSlot(payload, field)}");

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
                // Win64 passes a pointer to a copy the caller owns, and so does
                // AAPCS64 -- the difference is only whether LLVM is told to
                // make the copy itself.
                string copy = Alloca(StructName(structType), "arg.copy");
                MemCopy(copy, value.Ref, structType.Size);
                arguments.Add(info.IndirectAsPointer
                    ? $"ptr {copy}"
                    : $"ptr byval({StructName(structType)}) {copy}");
            }
            else
            {
                // One argument per register, each read from the eight bytes it
                // stands for -- out of a padded copy where the registers reach
                // past the value.
                string source = value.Ref;
                if (NeedsPadding(info))
                {
                    source = PaddedCopy(info);
                    MemCopy(source, value.Ref, structType.Size);
                }

                for (int piece = 0; piece < info.Pieces.Count; piece++)
                {
                    string spelling = info.Pieces[piece];
                    string address = PieceAddress(source, piece);
                    arguments.Add(
                        $"{spelling} {Emit(spelling, $"load {spelling}, ptr {address}")}");
                }
            }
            return;
        }

        arguments.Add($"{value.LlvmType} {value.Ref}");
    }
}
