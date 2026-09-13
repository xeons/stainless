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

using Stainless.Binding;

namespace Stainless.Emit;

/// <summary>
/// 32-bit x86 parameter and return classification, for both systems.
///
/// <para>
/// <b>Parameters are the easy half: every struct goes on the stack.</b> None of
/// the conventions a C declaration can name on x86 passes an aggregate in a
/// register, so there is nothing to classify -- a struct is a copy the caller
/// pushes, which is what <see cref="PassStyle.Indirect"/> lowers to.
/// </para>
///
/// <para>
/// clang spells some of them differently: a struct whose fields are all scalars
/// and whose size is a multiple of four is <i>expanded</i> into one argument per
/// field, so a <c>{int, int, int}</c> arrives as three <c>i32</c>. That is the
/// same twelve bytes in the same order, so a caller that pushes the struct and a
/// callee that expands it agree. The shorter spelling is kept here.
/// </para>
///
/// <para>
/// <b>Returns are where the two systems part company, and it is not a detail.</b>
/// Windows returns a struct of exactly 1, 2, 4 or 8 bytes in <c>EAX</c>, or in
/// <c>EDX:EAX</c> for the last -- the same split Win64 makes. i386 SysV returns
/// <i>every</i> struct through a hidden pointer, whatever its size: clang
/// answers <c>sret</c> for a struct of one byte. Classifying a Linux x86 return
/// by Win64's rule would put the value in a register the caller never reads.
/// </para>
///
/// <para>
/// Every rule here was read off clang rather than off a specification, by
/// compiling the same C for <c>i686-pc-windows-msvc</c> and
/// <c>i686-pc-linux-gnu</c> and looking at what came out. tests/cases/x86-abi is
/// the same question asked of a running program.
/// </para>
/// </summary>
public static class X86Abi
{
    /// <summary>
    /// A struct returned in registers rather than through a hidden pointer.
    /// Windows only, and only at the four sizes a register pair covers.
    /// </summary>
    public static bool ReturnsInRegisters(TypeSymbol type, bool windows) =>
        windows && type is StructTypeSymbol && type.Size is 1 or 2 or 4 or 8;

    public static ArgInfo ClassifyArgument(TypeSymbol type, Func<TypeSymbol, string> llvmTypeOf) =>
        type is StructTypeSymbol
            ? new ArgInfo(PassStyle.Indirect, "ptr", type)
            : new ArgInfo(PassStyle.Direct, llvmTypeOf(type), type);

    public static ArgInfo ClassifyReturn(
        TypeSymbol type, Func<TypeSymbol, string> llvmTypeOf, bool windows)
    {
        if (type.IsVoid()) return new ArgInfo(PassStyle.Direct, "void", type);

        if (type is not StructTypeSymbol)
            return new ArgInfo(PassStyle.Direct, llvmTypeOf(type), type);

        if (!ReturnsInRegisters(type, windows))
            return new ArgInfo(PassStyle.Indirect, "ptr", type);

        string coerced = $"i{type.Size * 8}";
        return new ArgInfo(PassStyle.Coerce, coerced, type) { Pieces = [coerced] };
    }
}
