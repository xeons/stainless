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

namespace Stainless.Emit;

/// <summary>
/// Objective-C blocks, as clang lays them out.
///
/// A block made here is a literal on the stack -- <c>_NSConcreteStackBlock</c>,
/// flags, an invoke function, a descriptor, and the two words of the
/// Stainless closure it holds -- copied to the heap with <c>_Block_copy</c>
/// at once, so that a block is never held on the stack. The copy and
/// dispose helpers retain and release the closure's object, which is the
/// only thing a block captures. The invoke function, one per block type,
/// calls the closure under the C convention Objective-C calls a block with.
/// </summary>
public sealed partial class LlvmEmitter
{
    /// <summary>Block types something made a block of or called one through, each with its invoke function written once.</summary>
    private readonly List<ObjCBlockTypeSymbol> _blockTypes = [];

    /// <summary>The block literal: isa, flags, reserved, invoke, descriptor, then the closure's function and object.</summary>
    private const string BlockLiteralType = "{ ptr, i32, i32, ptr, ptr, ptr, ptr }";

    /// <summary>
    /// The size of <see cref="BlockLiteralType"/>, which its descriptor states
    /// and <c>_Block_copy</c> copies: three pointers and two 32-bit words, then
    /// the closure's two pointers.
    /// </summary>
    private static int BlockLiteralSize => 5 * TargetPlatform.Current.PointerWidth + 8;

    /// <summary>
    /// BLOCK_HAS_COPY_DISPOSE and BLOCK_HAS_SIGNATURE, and BLOCK_USE_STRET when
    /// the invoke function returns through a hidden pointer on Intel.
    /// </summary>
    private int BlockFlags(ObjCBlockTypeSymbol block) =>
        (1 << 25) | (1 << 30) |
        (BoolIsByte && ClassifyResult(block.ReturnType).Style == PassStyle.Indirect ? 1 << 29 : 0);

    /// <summary>A block, optional or not.</summary>
    private static bool IsBlock(TypeSymbol type) => (type.AsReference() ?? type) is ObjCBlockTypeSymbol;

    private string BlockInvokeSymbol(ObjCBlockTypeSymbol block)
    {
        if (!_blockTypes.Contains(block)) _blockTypes.Add(block);
        return $"@\"sl.block.invoke.{Mangler.SymbolSafe(block.QualifiedName)}\"";
    }

    private static string BlockDescriptorSymbol(ObjCBlockTypeSymbol block) =>
        $"@\"sl.block.descriptor.{Mangler.SymbolSafe(block.QualifiedName)}\"";

    /// <summary>
    /// A closure made a block: the literal written on the stack around the
    /// closure's two words, and copied to the heap, where the copy helper
    /// retains the closure's object. What comes back is owned.
    /// </summary>
    private Val EmitBlockFromClosure(Val closure, ClosureTypeSymbol closureType, ObjCBlockTypeSymbol block)
    {
        string function = Emit("ptr", $"load ptr, ptr {StructFieldAddress(closure.Ref, closureType, closureType.Function!)}");
        string receiver = Emit("ptr", $"load ptr, ptr {StructFieldAddress(closure.Ref, closureType, closureType.Receiver!)}");

        string literal = Alloca(BlockLiteralType, "block");
        string Field(int index) =>
            Emit("ptr", $"getelementptr inbounds {BlockLiteralType}, ptr {literal}, i32 0, i32 {index}");

        Line($"store ptr @_NSConcreteStackBlock, ptr {Field(0)}");
        Line($"store i32 {BlockFlags(block)}, ptr {Field(1)}");
        Line($"store i32 0, ptr {Field(2)}");
        Line($"store ptr {BlockInvokeSymbol(block)}, ptr {Field(3)}");
        Line($"store ptr {BlockDescriptorSymbol(block)}, ptr {Field(4)}");
        Line($"store ptr {function}, ptr {Field(5)}");
        Line($"store ptr {receiver}, ptr {Field(6)}");

        string heap = Emit("ptr", $"call ptr @_Block_copy(ptr {literal})");
        return Fresh(new Val(heap, "ptr", block));
    }

    /// <summary>
    /// A call through a block: its invoke function, given the block and then
    /// the arguments as C passes them, a <c>BOOL</c> being the target's own.
    /// An object it hands back is +0, as an Objective-C call's is, and is
    /// claimed; one declared non-optional is checked for nil.
    /// </summary>
    private Val EmitBlockCall(BoundClosureCall call, ObjCBlockTypeSymbol block)
    {
        var returnInfo = ClassifyResult(block.ReturnType);
        var held = EmitExpression(call.Target);

        string invokeSlot = Emit("ptr", $"getelementptr inbounds {BlockLiteralType}, ptr {held.Ref}, i32 0, i32 3");
        string invoke = Emit("ptr", $"load ptr, ptr {invokeSlot}");

        var arguments = new List<string>();
        string? sretSlot = null;
        if (returnInfo.Style == PassStyle.Indirect)
        {
            var structType = (StructTypeSymbol)block.ReturnType;
            sretSlot = Alloca(StructName(structType), "block.sret");
            arguments.Add($"ptr sret({StructName(structType)}) {sretSlot}");
        }

        arguments.Add($"ptr {held.Ref}");

        var lowered = new List<string>[call.Arguments.Count];
        foreach (int i in call.EvaluationOrder ?? Enumerable.Range(0, call.Arguments.Count))
        {
            var expression = call.Arguments[i];
            var value = EmitExpression(expression);
            lowered[i] = [];
            if (BoolIsByte && IsBool(expression.Type))
                lowered[i].Add($"i8 signext {Emit("i8", $"zext i1 {value.Ref} to i8")}");
            else
                AppendArgument(value, expression.Type, lowered[i], variadic: false);
        }

        foreach (var pieces in lowered) arguments.AddRange(pieces);

        bool boolResult = BoolIsByte && IsBool(block.ReturnType);
        string spelling = boolResult ? "signext i8" : ResultSpelling(returnInfo);
        string invocation = $"call {spelling} {invoke}({string.Join(", ", arguments)})";

        if (returnInfo.Style == PassStyle.Indirect)
        {
            Line(invocation);
            return Fresh(new Val(sretSlot!, "ptr", block.ReturnType));
        }

        if (returnInfo.Style == PassStyle.Ignore)
        {
            Line(invocation);
            return EmptyResult(block.ReturnType);
        }

        if (block.ReturnType.IsVoid())
        {
            Line(invocation);
            return Val.Void;
        }

        string result = Emit(boolResult ? "i8" : returnInfo.LlvmType, invocation);
        if (boolResult)
            return new Val(Emit("i1", $"icmp ne i8 {result}, 0"), "i1", block.ReturnType);

        if (IsObjCReference(block.ReturnType))
        {
            result = ClaimReturned(result);
            if (IsNeverNullReference(block.ReturnType))
            {
                string present = Emit("i1", $"icmp ne ptr {result}, null");
                string good = NextLabel("block.ok");
                string bad = NextLabel("block.nil");
                Terminator($"br i1 {present}, label %{good}, label %{bad}");
                Label(bad);
                string type = block.ReturnType is NamedTypeSymbol named ? named.QualifiedName : block.ReturnType.Name;
                Line($"call void @sl_objc_nil(ptr {InternBytes($"a {block.Name} block")}, ptr {InternBytes(type)})");
                Terminator("unreachable");
                Label(good);
            }
        }

        return Landed(result, returnInfo, block.ReturnType);
    }

    /// <summary>
    /// The invoke function of every block type used, their descriptors, and
    /// the copy and dispose helpers they share. Written after the last
    /// function, since a block type is found by the code that uses it.
    /// </summary>
    private void BlockTables()
    {
        if (_blockTypes.Count == 0) return;

        _module.AppendLine();
        _module.AppendLine(
            "define internal void @sl.block.copy(ptr %destination, ptr %source)" + FrameAttributes + " {");
        _module.AppendLine("entry:");
        _module.AppendLine($"  %slot = getelementptr inbounds {BlockLiteralType}, ptr %source, i32 0, i32 6");
        _module.AppendLine("  %receiver = load ptr, ptr %slot");
        _module.AppendLine("  call void @sl_retain(ptr %receiver)");
        _module.AppendLine("  ret void");
        _module.AppendLine("}");
        _module.AppendLine();
        _module.AppendLine("define internal void @sl.block.dispose(ptr %block)" + FrameAttributes + " {");
        _module.AppendLine("entry:");
        _module.AppendLine($"  %slot = getelementptr inbounds {BlockLiteralType}, ptr %block, i32 0, i32 6");
        _module.AppendLine("  %receiver = load ptr, ptr %slot");
        _module.AppendLine("  call void @sl_release(ptr %receiver)");
        _module.AppendLine("  ret void");
        _module.AppendLine("}");
        _module.AppendLine();

        // The list grows while it is walked only if an invoke function names
        // another block type, which a block parameter does.
        for (int i = 0; i < _blockTypes.Count; i++)
        {
            var block = _blockTypes[i];
            EmitBlockInvoke(block);

            string signature = ObjCString(MethodTypeSection, BlockTypeEncoding(block));
            _module.AppendLine(
                $"{BlockDescriptorSymbol(block)} = internal constant {{ i64, i64, ptr, ptr, ptr }} " +
                $"{{ i64 0, i64 {BlockLiteralSize}, ptr @sl.block.copy, ptr @sl.block.dispose, ptr {signature} }}");
        }

        _module.Append(_objcStringData);
        _objcStringData.Clear();
        _module.AppendLine();
    }

    /// <summary>
    /// The function Objective-C calls a block of one type through: the
    /// block, then the arguments, and the closure the block holds called
    /// with its object and them. As an IMP does, it converts a <c>BOOL</c>
    /// on Intel, copies a block it is handed before passing it on, checks an
    /// object parameter declared non-optional, hands an object back at +0,
    /// and stops the program at an exception.
    /// </summary>
    private void EmitBlockInvoke(ObjCBlockTypeSymbol block)
    {
        BeginImp();
        string description = $"a {block.Name} block";
        var returnInfo = ClassifyResult(block.ReturnType);
        bool boolResult = BoolIsByte && IsBool(block.ReturnType);

        var declared = new List<string>();
        var forwarded = new List<string>();
        if (returnInfo.Style == PassStyle.Indirect)
        {
            string sret = $"ptr sret({StructName((StructTypeSymbol)block.ReturnType)})";
            declared.Add($"{sret} %sret");
            forwarded.Add($"{sret} %sret");
        }

        declared.Add("ptr %block");

        string functionSlot = Emit("ptr", $"getelementptr inbounds {BlockLiteralType}, ptr %block, i32 0, i32 5");
        string function = Emit("ptr", $"load ptr, ptr {functionSlot}");
        string receiverSlot = Emit("ptr", $"getelementptr inbounds {BlockLiteralType}, ptr %block, i32 0, i32 6");
        string receiver = Emit("ptr", $"load ptr, ptr {receiverSlot}");
        forwarded.Add($"ptr {receiver}");

        var copied = new List<string>();
        foreach (var parameter in block.Signature)
        {
            var info = ClassifyValue(parameter.Type);
            string name = ArgumentName(parameter);

            if (BoolIsByte && IsBool(parameter.Type))
            {
                declared.Add($"i8 signext {name}");
                forwarded.Add($"{info.LlvmType}{Widening(info)} {Emit("i1", $"icmp ne i8 {name}, 0")}");
                continue;
            }

            var spellings = Declared(info).ToList();
            for (int piece = 0; piece < spellings.Count; piece++)
                declared.Add($"{spellings[piece]} {(spellings.Count == 1 ? name : $"{name}.{piece}")}");

            if (IsObjCReference(parameter.Type) && IsNeverNullReference(parameter.Type))
                RequireArgument(name, parameter, description);

            if (IsBlock(parameter.Type))
            {
                string copy = Emit("ptr", $"call ptr @objc_retainBlock(ptr {name})");
                copied.Add(copy);
                forwarded.Add($"ptr {copy}");
                continue;
            }

            for (int piece = 0; piece < spellings.Count; piece++)
                forwarded.Add($"{spellings[piece]} {(spellings.Count == 1 ? name : $"{name}.{piece}")}");
        }

        string landing = NextLabel("imp.unwind");
        string ok = NextLabel("imp.ok");
        string bodyResult = ResultSpelling(returnInfo);
        bool hasResult = !(returnInfo.Style is PassStyle.Indirect or PassStyle.Ignore || block.ReturnType.IsVoid());
        string invocation = $"invoke {bodyResult} {function}({string.Join(", ", forwarded)}) to label %{ok} unwind label %{landing}";
        string? result = hasResult ? Emit(returnInfo.LlvmType, invocation) : null;
        if (!hasResult) Line(invocation);
        _blockTerminated = true;

        Label(ok);
        foreach (string copy in copied)
            Line($"call void @objc_release(ptr {copy})");

        string returnSpelling = bodyResult;
        if (boolResult)
        {
            Terminator($"ret i8 {Emit("i8", $"zext i1 {result} to i8")}");
            returnSpelling = "signext i8";
        }
        else if (result is not null && IsObjCReference(block.ReturnType))
        {
            Terminator($"ret ptr {Emit("ptr", $"tail call ptr @objc_autoreleaseReturnValue(ptr {result})")}");
        }
        else
        {
            Terminator(result is null ? "ret void" : $"ret {returnInfo.LlvmType} {result}");
        }

        EndImp(landing, description,
            $"{returnSpelling} {BlockInvokeSymbol(block)}({string.Join(", ", declared)})");
    }

    /// <summary>
    /// A block's signature as its descriptor carries it: the result, the size
    /// of the arguments, the block itself as <c>@?0</c>, then each argument
    /// with its offset. <c>v20@?0@8B16</c> takes an object and a BOOL.
    /// </summary>
    private static string BlockTypeEncoding(ObjCBlockTypeSymbol block)
    {
        int pointer = TargetPlatform.Current.PointerWidth;
        int offset = pointer;
        var arguments = new System.Text.StringBuilder("@?0");

        foreach (var parameter in block.Signature)
        {
            arguments.Append(TypeEncoding(parameter.Type, topLevel: true)).Append(offset);
            offset += Math.Max(EncodedSize(parameter.Type), 4);
        }

        return TypeEncoding(block.ReturnType, topLevel: true) + offset + arguments;
    }
}
