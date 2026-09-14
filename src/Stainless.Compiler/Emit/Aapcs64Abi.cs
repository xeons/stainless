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
/// AAPCS64 parameter and return classification: 64-bit ARM, on Windows and on
/// everything else alike.
///
/// <para>
/// <b>One class for both systems, which is not true of x86 or of x86-64.</b>
/// Microsoft's ARM64 ABI and the ARM one agree about every shape below --
/// checked by compiling the same C for <c>aarch64-pc-windows-msvc</c> and
/// <c>aarch64-unknown-linux-gnu</c> and diffing the declarations. What differs
/// between those two is how wide a C <c>long</c> is, and Stainless has no type
/// whose width depends on the system.
/// </para>
///
/// <para>
/// <b>The rule is neither Win64's size nor System V's eightbytes.</b> A struct
/// whose members are all the same floating-point type, four or fewer of them
/// and no padding, is a <i>homogeneous floating-point aggregate</i> and travels
/// in one SIMD register per member -- however big it is, so four doubles cross
/// in registers at thirty-two bytes. Everything else of sixteen bytes or less
/// travels in one or two general registers, and everything larger is a pointer
/// to a copy the caller made.
/// </para>
///
/// <para>
/// <b>Two things here have no counterpart in the other three classifiers.</b>
/// The first is that the registers may cover more than the value does: a
/// twelve-byte struct crosses as <c>[2 x i64]</c>, so the load is sixteen bytes
/// wide and has to be made from a padded copy rather than from the value.
/// <see cref="ArgInfo.PaddedSize"/> is what says so. The second is that a large
/// struct is <i>not</i> <c>byval</c>: AAPCS64 puts a pointer to the caller's
/// copy in a register, and LLVM lowers <c>byval</c> to twenty-four bytes on the
/// stack on every target -- a different place and a different register. That is
/// <see cref="ArgInfo.IndirectAsPointer"/>.
/// </para>
///
/// <para>
/// Every answer below was read off clang rather than off the specification, the
/// same way the other three were. What is not here is a machine to run it on:
/// nothing in this project has executed an ARM64 binary, so these are checked
/// against clang's declarations and by the unit tests, and not by a program.
/// </para>
/// </summary>
public static class Aapcs64Abi
{
    /// <summary>
    /// Anything larger than this and not homogeneous travels behind a pointer.
    /// </summary>
    private const int MaxRegisterSize = 16;

    /// <summary>
    /// How many members a homogeneous aggregate may have: there are eight SIMD
    /// argument registers and a value may not take more than half of them.
    /// </summary>
    private const int MaxHomogeneousMembers = 4;

    public static ArgInfo ClassifyArgument(TypeSymbol type, Func<TypeSymbol, string> llvmTypeOf)
    {
        if (type is not StructTypeSymbol structType)
            return new ArgInfo(PassStyle.Direct, llvmTypeOf(type), type);

        // A register per member, spelled as an array of them. Size does not
        // come into it: four doubles is thirty-two bytes and travels in v0-v3.
        if (Homogeneous(structType) is { } homogeneous)
        {
            string spelling = $"[{homogeneous.Count} x {llvmTypeOf(homogeneous.Element)}]";
            return new ArgInfo(PassStyle.Coerce, spelling, type) { Pieces = [spelling] };
        }

        if (structType.Size is <= 0 or > MaxRegisterSize)
            return new ArgInfo(PassStyle.Indirect, "ptr", type) { IndirectAsPointer = true };

        // A struct holding nothing but pointers keeps them as pointers, exactly
        // as System V does for a lone one: the registers are the same and LLVM
        // reasons better about the spelling that says what it is.
        int unit = Unit(structType);
        string register = unit == MaxRegisterSize ? "i128"
            : AllPointers(structType, llvmTypeOf) ? "ptr"
            : "i64";

        return Covered(structType, unit, register, type);
    }

    public static ArgInfo ClassifyReturn(TypeSymbol type, Func<TypeSymbol, string> llvmTypeOf)
    {
        if (type.IsVoid()) return new ArgInfo(PassStyle.Direct, "void", type);

        if (type is not StructTypeSymbol structType)
            return new ArgInfo(PassStyle.Direct, llvmTypeOf(type), type);

        // A homogeneous aggregate comes back in the same registers it goes out
        // in, and is spelled as itself rather than as an array of its members.
        // That is clang's spelling, and the two are the same registers.
        if (Homogeneous(structType) is not null)
        {
            string spelling = llvmTypeOf(type);
            return new ArgInfo(PassStyle.Coerce, spelling, type) { Pieces = [spelling] };
        }

        if (structType.Size is <= 0 or > MaxRegisterSize)
            return new ArgInfo(PassStyle.Indirect, "ptr", type);

        // Eight bytes or less comes back in one register sized to the value,
        // which is where an `i24` comes from and why nothing has to be padded
        // to read it. Going the other way the same struct is an `i64`, because
        // an argument register is sized by the slot and a result by the value.
        if (structType.Size <= 8)
        {
            string exact = $"i{structType.Size * 8}";
            return new ArgInfo(PassStyle.Coerce, exact, type) { Pieces = [exact] };
        }

        int unit = Unit(structType);
        return Covered(structType, unit, unit == MaxRegisterSize ? "i128" : "i64", type);
    }

    /// <summary>
    /// How wide one register is for this value: sixteen bytes for a value that
    /// asks to be aligned that way, and eight for everything else.
    /// </summary>
    private static int Unit(StructTypeSymbol structType) =>
        structType.Alignment >= MaxRegisterSize ? MaxRegisterSize : 8;

    /// <summary>
    /// One or more registers of <paramref name="register"/>, enough to cover
    /// the value, with how many bytes that comes to when it is more than the
    /// value itself.
    /// </summary>
    private static ArgInfo Covered(
        StructTypeSymbol structType, int unit, string register, TypeSymbol type)
    {
        int covered = (structType.Size + unit - 1) / unit * unit;
        string spelling = covered == unit ? register : $"[{covered / unit} x {register}]";

        return new ArgInfo(PassStyle.Coerce, spelling, type)
        {
            Pieces = [spelling],
            PaddedSize = covered > structType.Size ? covered : 0,
        };
    }

    /// <summary>
    /// The floating-point type every member is and how many there are, or null
    /// when the value is not a homogeneous aggregate.
    ///
    /// The size check at the end is what rejects padding: <c>{ float; float; }</c>
    /// is eight bytes and two members, and a struct that is eight bytes with
    /// one float in it is neither -- so it is not this, whatever its members
    /// look like one at a time.
    /// </summary>
    private static (PrimitiveTypeSymbol Element, int Count)? Homogeneous(
        StructTypeSymbol structType)
    {
        PrimitiveTypeSymbol? element = null;
        int members = 0;

        if (!Gather(structType, ref element, ref members)) return null;
        if (element is null || members == 0 || members > MaxHomogeneousMembers) return null;
        if (element.Size * members != structType.Size) return null;

        return (element, members);
    }

    /// <summary>
    /// Counts the members of a would-be homogeneous aggregate, recursing into
    /// whatever is nested. False the moment anything that is not the one
    /// floating-point type turns up.
    /// </summary>
    private static bool Gather(TypeSymbol type, ref PrimitiveTypeSymbol? element, ref int members)
    {
        switch (type)
        {
            // A union's members overlap, so it contributes the most any one of
            // them does rather than the sum -- and they still have to agree
            // with each other and with everything outside about the type.
            case UnionTypeSymbol union:
            {
                int most = 0;
                foreach (var field in union.Fields)
                {
                    if (field.IsBitField) return false;

                    int branch = 0;
                    if (!Gather(field.Type, ref element, ref branch)) return false;
                    most = Math.Max(most, branch);
                }
                members += most;
                return true;
            }

            case StructTypeSymbol nested:
                foreach (var field in nested.Fields)
                {
                    if (field.IsBitField) return false;
                    if (!Gather(field.Type, ref element, ref members)) return false;
                }
                return true;

            case FixedArrayTypeSymbol inline:
            {
                int one = 0;
                if (!Gather(inline.Element, ref element, ref one)) return false;
                members += one * inline.Length;
                return true;
            }

            case PrimitiveTypeSymbol { Kind: PrimitiveKind.Float or PrimitiveKind.Double } real:
                if (element is not null && element.Kind != real.Kind) return false;
                element = real;
                members++;
                return true;

            default:
                return false;
        }
    }

    /// <summary>
    /// Whether every last thing in the value is a pointer. An empty aggregate
    /// is not, because there is nothing in it to be one.
    /// </summary>
    private static bool AllPointers(TypeSymbol type, Func<TypeSymbol, string> llvmTypeOf)
    {
        switch (type)
        {
            case StructTypeSymbol aggregate:
                if (aggregate.Fields.Count == 0) return false;
                foreach (var field in aggregate.Fields)
                    if (field.IsBitField || !AllPointers(field.Type, llvmTypeOf))
                        return false;
                return true;

            case FixedArrayTypeSymbol inline:
                return AllPointers(inline.Element, llvmTypeOf);

            default:
                return llvmTypeOf(type) == "ptr";
        }
    }
}
