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
/// The small vocabulary everything else is written in: how a type is
/// spelled in IR, and how an instruction is emitted into the current
/// block.
/// </summary>
public sealed partial class LlvmEmitter
{
    // ============================================================ types

    /// <summary>
    /// How a type is spelled in IR.
    ///
    /// Public because both ABI classifiers take it as an argument, which makes
    /// it part of their contract rather than an internal detail: anything
    /// asking one of them what a shape does has to hand it the same speller
    /// the emitter uses, or it is asking about a different program.
    /// </summary>
    public static string LlvmTypeOf(TypeSymbol type) => type switch
    {
        PrimitiveTypeSymbol primitive => primitive.Kind switch
        {
            PrimitiveKind.Void => "void",
            PrimitiveKind.Bool => "i1",
            PrimitiveKind.Char or PrimitiveKind.SByte or PrimitiveKind.Byte => "i8",
            PrimitiveKind.Short or PrimitiveKind.UShort
                or PrimitiveKind.Char16 => "i16",
            PrimitiveKind.Int or PrimitiveKind.UInt
                or PrimitiveKind.Char32 => "i32",
            PrimitiveKind.Float => "float",
            PrimitiveKind.Double => "double",
            _ => "i64",
        },
        StructTypeSymbol structType => StructName(structType),

        // An inline array is its elements, so LLVM is told exactly that. This
        // is what makes a struct holding one the width the C struct is.
        FixedArrayTypeSymbol inline => $"[{inline.Length} x {LlvmTypeOf(inline.Element)}]",

        // A delegate is a bare function pointer, which is what makes it the
        // same value a C function pointer is.
        DelegateTypeSymbol => "ptr",

        // An enum is its underlying integer, which is what makes it the same
        // bytes as the C enum it lines up with.
        EnumTypeSymbol enumType => LlvmTypeOf(enumType.UnderlyingType),

        _ => "ptr",     // pointers, class references, optionals and weak references
    };

    private static string StructName(StructTypeSymbol type) =>
        (type is UnionTypeSymbol ? "%union." : "%struct.") +
        Mangler.SymbolSafe(type.QualifiedName);

    private static string DestroyName(ClassTypeSymbol type) =>
        "_SLdestroy_" + Mangler.SymbolSafe(type.QualifiedName);

    private static bool IsSigned(TypeSymbol type) => type switch
    {
        // An enum orders and shifts as the integer it is represented by.
        EnumTypeSymbol enumType => enumType.UnderlyingType.IsSigned,
        _ => type is PrimitiveTypeSymbol { IsSigned: true },
    };

    // ============================================================ instruction helpers

    private string NextTemp() => "%" + _nextTemp++;
    private string NextLabel(string hint) => $"{hint}.{_nextLabel++}";

    /// <summary>
    /// The <c>!dbg</c> suffix every instruction in a described function carries.
    ///
    /// Attaching it here rather than at each call site is what keeps debug info
    /// from spreading through the emitter: this is the one place an instruction
    /// is written. It also satisfies LLVM's rule that a call inside a function
    /// with debug info must have a location, without having to know which of the
    /// lines below happens to be a call.
    /// </summary>
    private string Dbg => _debugLocation is { } id ? $", !dbg !{id}" : "";

    private void Line(string text)
    {
        if (_blockTerminated) return;       // unreachable code after a terminator
        _body.Append("  ").Append(text).AppendLine(Dbg);
    }

    private void Terminator(string text)
    {
        if (_blockTerminated) return;
        _body.Append("  ").Append(text).AppendLine(Dbg);
        _blockTerminated = true;
    }

    private void Label(string name)
    {
        // A block must be entered somehow; fall through if the previous one is open.
        if (!_blockTerminated) _body.AppendLine($"  br label %{name}");
        _body.AppendLine($"{name}:");
        _blockTerminated = false;
        _currentBlock = name;
    }

    private string Emit(string llvmType, string instruction)
    {
        string temp = NextTemp();
        Line($"{temp} = {instruction}");
        return llvmType == "void" ? "" : temp;
    }

    /// <summary>
    /// Every alloca is hoisted into the entry block and given a name rather than a
    /// number. Hoisting keeps a declaration inside a loop from growing the stack on
    /// each iteration; naming keeps it out of LLVM's sequential numbering, which
    /// would otherwise be violated by emitting it ahead of earlier instructions.
    /// </summary>
    private string Alloca(string llvmType, string hint)
    {
        string name = $"%{SanitizeIdentifier(hint)}.s{_nextSlot++}";
        _entryAllocas.AppendLine($"  {name} = alloca {llvmType}, align {AlignOf(llvmType)}");
        return name;
    }

    private int AlignOf(string llvmType) => llvmType switch
    {
        "i1" or "i8" => 1,
        "i16" => 2,
        "i32" or "float" => 4,
        _ when llvmType.StartsWith('%') =>
            _structAlignment.TryGetValue(llvmType, out int declared) ? declared : 1,
        _ => 8,
    };

    /// <summary>
    /// Ties a stack slot to the name and type the source gave it, so a debugger
    /// can print the variable rather than the address.
    /// </summary>
    private void DeclareVariable(string slot, int variable)
    {
        if (debug is null || _debugScope is null) return;

        Line($"call void @llvm.dbg.declare(metadata ptr {slot}, metadata !{variable}, " +
             "metadata !DIExpression())");
    }

    private void MemCopy(string destination, string source, int size)
    {
        Line($"call void @llvm.memcpy.p0.p0.i64(ptr {destination}, ptr {source}, i64 {size}, i1 false)");
    }
}
