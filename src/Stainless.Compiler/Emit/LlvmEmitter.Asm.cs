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

using System.Text;
using Stainless.Binding;
using Stainless.Syntax;

namespace Stainless.Emit;

/// <summary>
/// <c>asm</c> statements, which are LLVM's inline assembly calls with the
/// operands spelled as register constraints.
/// </summary>
public sealed partial class LlvmEmitter
{
    private readonly List<BoundAsm> _asmBlocks = [];

    /// <summary>
    /// Every block this emitter wrote, in the order written. The driver reads it
    /// when the assembler rejects one, to put the complaint back on the line of
    /// source it was about.
    /// </summary>
    public IReadOnlyList<BoundAsm> AsmBlocks => _asmBlocks;

    /// <summary>
    /// One <c>call ... asm</c>.
    ///
    /// <para>
    /// Every operand is evaluated once, in the order written, before the block:
    /// an input's value, and an output's address. The stores happen after it,
    /// in the same order. Taking an output's address first is what makes
    /// <c>inout rax = counts[Next()]</c> call <c>Next</c> once rather than once
    /// for the read and again for the write.
    /// </para>
    ///
    /// <para>
    /// A value narrower than its register is extended to the register's width
    /// by its own signedness, so an <c>int</c> of -1 in <c>rcx</c> is -1 in all
    /// sixty-four bits. LLVM happens to do the same for an <c>i32</c> handed to
    /// <c>{rcx}</c> today, but nothing promises it, and a block reading the whole
    /// register would otherwise see whatever the upper half last held. An output
    /// narrower than its register is the low bits, and a <c>bool</c> is whether
    /// the register is anything but zero.
    /// </para>
    /// </summary>
    private void EmitAsm(BoundAsm statement)
    {
        _asmBlocks.Add(statement);

        var target = TargetPlatform.Current;
        var arguments = new List<string>();
        var outputs = new List<(BoundAsmOperand Operand, string Address)>();

        foreach (var operand in statement.Operands)
        {
            string llvmType = RegisterType(operand);

            if (operand.Direction == AsmDirection.In)
            {
                var value = EmitExpression(operand.Value);
                arguments.Add($"{llvmType} {IntoRegister(value, llvmType)}");
                continue;
            }

            string address = EmitAddress(operand.Value);
            outputs.Add((operand, address));

            if (operand.Direction == AsmDirection.InOut)
            {
                string valueType = LlvmTypeOf(operand.Value.Type);
                var held = new Val(
                    Emit(valueType, $"load {valueType}, ptr {address}"), valueType, operand.Value.Type);
                arguments.Add($"{llvmType} {IntoRegister(held, llvmType)}");
            }
        }

        var constraints = new List<string>();
        constraints.AddRange(statement.Operands.Where(o => o.IsOutput).Select(o => $"={{{o.Constraint}}}"));
        constraints.AddRange(statement.Operands.Where(o => o.IsInput).Select(o => $"{{{o.Constraint}}}"));
        constraints.AddRange(statement.Clobbers.Select(c => $"~{{{c}}}"));

        string resultType = outputs.Count switch
        {
            0 => "void",
            1 => RegisterType(outputs[0].Operand),
            _ => "{ " + string.Join(", ", outputs.Select(o => RegisterType(o.Operand))) + " }",
        };

        // Intel syntax on x86, because it is the one its documentation and
        // most of what is written about it use; ARM has one syntax.
        string dialect = target.Architecture == TargetArch.Arm64 ? "" : "inteldialect ";
        string call = $"call {resultType} asm {dialect}\"{AsmString(statement.Text)}\", " +
                      $"\"{string.Join(",", constraints)}\"({string.Join(", ", arguments)})";

        if (outputs.Count == 0)
        {
            Line(call);
            FlushTemporaries();
            return;
        }

        string result = Emit(resultType, call);

        for (int i = 0; i < outputs.Count; i++)
        {
            var (operand, address) = outputs[i];
            string registerType = RegisterType(operand);
            string raw = outputs.Count == 1
                ? result
                : Emit(registerType, $"extractvalue {resultType} {result}, {i}");

            StoreInto(address, OutOfRegister(raw, registerType, operand.Value.Type), operand.Value.Type);
        }

        FlushTemporaries();
    }

    /// <summary>
    /// The LLVM type the register is handed or read as: the register's own
    /// width for an integer, a pointer where the value is one — the register is
    /// then exactly a pointer wide, since nothing wider or narrower binds — and
    /// the value's own type in a vector register.
    /// </summary>
    private static string RegisterType(BoundAsmOperand operand)
    {
        var type = operand.Value.Type;

        if (operand.Register.Kind == AsmRegisterKind.Vector) return LlvmTypeOf(type);
        if (type is PointerTypeSymbol or DelegateTypeSymbol) return "ptr";
        return $"i{operand.Register.Bits}";
    }

    /// <summary>A value widened to its register's type, by its own signedness.</summary>
    private string IntoRegister(Val value, string registerType)
    {
        if (value.LlvmType == registerType) return value.Ref;

        var type = value.Type is EnumTypeSymbol named ? named.UnderlyingType : value.Type;
        string extend = type is PrimitiveTypeSymbol { IsSigned: true } ? "sext" : "zext";

        return Emit(registerType, $"{extend} {value.LlvmType} {value.Ref} to {registerType}");
    }

    /// <summary>What a register read back means as a value of the place's type.</summary>
    private Val OutOfRegister(string raw, string registerType, TypeSymbol type)
    {
        string llvmType = LlvmTypeOf(type);
        if (llvmType == registerType) return new Val(raw, llvmType, type);

        if (type is PrimitiveTypeSymbol { Kind: PrimitiveKind.Bool })
            return new Val(Emit("i1", $"icmp ne {registerType} {raw}, 0"), "i1", type);

        return new Val(Emit(llvmType, $"trunc {registerType} {raw} to {llvmType}"), llvmType, type);
    }

    /// <summary>
    /// The block's text as an LLVM string: printable ASCII as itself, and a
    /// quote, a backslash and every other byte of the UTF-8 as <c>\XX</c>.
    ///
    /// Only a carriage return is taken out. A file saved with Windows line
    /// endings would otherwise emit different IR from the same file saved on
    /// Linux, and nothing about the instructions differs. Everything else is
    /// kept exactly, line for line, because the assembler numbers the lines of
    /// what it was given and those numbers are how a complaint finds its way
    /// back to the source.
    /// </summary>
    public static string AsmString(string text)
    {
        var escaped = new StringBuilder();
        foreach (byte b in Encoding.UTF8.GetBytes(text.Replace("\r", "")))
        {
            if (b is >= 0x20 and < 0x7F && b != '"' && b != '\\')
                escaped.Append((char)b);
            else
                escaped.Append('\\').Append(b.ToString("X2"));
        }

        return escaped.ToString();
    }
}
