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

public enum PassStyle
{
    /// <summary>Passed directly in a register as its natural LLVM type.</summary>
    Direct,
    /// <summary>
    /// A small struct travelling in registers, as the scalars in
    /// <see cref="ArgInfo.Pieces"/>.
    ///
    /// Win64 always produces exactly one, an integer of the struct's own size.
    /// SysV produces one or two, and either may be an integer or a float, which
    /// is why this is a list rather than a type.
    /// </summary>
    Coerce,
    /// <summary>A large struct passed as a pointer to a caller-allocated copy.</summary>
    Indirect,
}

/// <summary>
/// How one value crosses a call boundary.
///
/// <paramref name="LlvmType"/> is what a *return* is spelled as, and what a
/// single-register parameter is spelled as. A parameter travelling in two
/// registers is two declared parameters, which is what <see cref="Pieces"/>
/// says and <see cref="LlvmType"/> cannot.
/// </summary>
public sealed record ArgInfo(PassStyle Style, string LlvmType, TypeSymbol Type)
{
    /// <summary>
    /// The registers a coerced struct travels in, in order, each covering the
    /// eight bytes of the value at that offset. Empty for every other style.
    /// </summary>
    public IReadOnlyList<string> Pieces { get; init; } = [];

    /// <summary>
    /// How many bytes <see cref="Pieces"/> covers, when that is more than the
    /// value occupies. Zero -- meaning they cover it exactly -- for every
    /// convention but AAPCS64, where a twelve-byte struct travels in two
    /// eight-byte registers.
    ///
    /// It matters because a coerced value is read from and written to the
    /// object itself. Where the registers reach past it, a padded copy has to
    /// stand in: reading the object would read bytes that are not part of it,
    /// and writing it would overwrite bytes that belong to something else.
    /// </summary>
    public int PaddedSize { get; init; }

    /// <summary>
    /// True when an <see cref="PassStyle.Indirect"/> argument is a pointer to a
    /// copy the caller made, rather than the copy itself.
    ///
    /// System V and Win64 say <c>byval</c>, which hands LLVM the copying as
    /// well as the pointer. AAPCS64 cannot: LLVM lowers <c>byval</c> to the
    /// value on the outgoing stack on every target, and AAPCS64 wants a
    /// pointer in a general register -- a different place, read by a different
    /// instruction, with nothing to diagnose the difference.
    ///
    /// A return is unaffected: <c>sret</c> is a hidden pointer everywhere.
    /// </summary>
    public bool IndirectAsPointer { get; init; }
}

/// <summary>
/// Win64 (Microsoft x64) parameter and return classification.
///
/// LLVM IR does not apply a C ABI on its own — that is a front-end job — so if
/// Stainless is to be genuinely C-compatible, this is where it happens. The
/// rules are short: a struct whose size is exactly 1, 2, 4 or 8 bytes travels in
/// a register as an integer of that width; every other struct travels as a
/// pointer to a copy the caller owns. Returns follow the same split, with large
/// results written through a hidden first pointer argument.
/// </summary>
public static class Win64Abi
{
    public static bool IsRegisterSizedStruct(TypeSymbol type) =>
        type is StructTypeSymbol && type.Size is 1 or 2 or 4 or 8;

    public static ArgInfo ClassifyArgument(TypeSymbol type, Func<TypeSymbol, string> llvmTypeOf)
    {
        if (type is not StructTypeSymbol)
            return new ArgInfo(PassStyle.Direct, llvmTypeOf(type), type);

        if (!IsRegisterSizedStruct(type))
            return new ArgInfo(PassStyle.Indirect, "ptr", type);

        string coerced = $"i{type.Size * 8}";
        return new ArgInfo(PassStyle.Coerce, coerced, type) { Pieces = [coerced] };
    }

    public static ArgInfo ClassifyReturn(TypeSymbol type, Func<TypeSymbol, string> llvmTypeOf)
    {
        if (type.IsVoid()) return new ArgInfo(PassStyle.Direct, "void", type);
        return ClassifyArgument(type, llvmTypeOf);
    }
}
