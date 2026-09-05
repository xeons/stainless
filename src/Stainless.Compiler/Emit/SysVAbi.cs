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
/// System V AMD64 parameter and return classification: Linux, macOS, the BSDs,
/// and everything that is not Windows.
///
/// Longer than <see cref="Win64Abi"/> because the rule is not about size. A
/// value of sixteen bytes or less is cut into eightbytes, each eightbyte is
/// classified by what lies in it, and that decides which bank of registers it
/// travels in. So <c>{ double; int; }</c> goes in one integer register and one
/// SSE register while <c>{ float; int; }</c> goes in one integer register, and
/// nothing about either follows from their sizes.
///
/// Every shape here is checked against clang built for
/// <c>x86_64-pc-linux-gnu</c> rather than read off the specification, which is
/// what tests/cases/sysv-abi holds: the two have to agree signature for
/// signature, because disagreeing by one register is a program that links and
/// then reads an argument that was never passed.
/// </summary>
public static class SysVAbi
{
    /// <summary>Which bank of registers an eightbyte travels in.</summary>
    private enum Class
    {
        /// <summary>Nothing lies in this eightbyte at all.</summary>
        None,

        /// <summary>An integer register: rdi, rsi, rdx, rcx, r8, r9.</summary>
        Integer,

        /// <summary>An SSE register: xmm0 to xmm7.</summary>
        Sse,

        /// <summary>Not in registers at all — the whole value goes on the stack.</summary>
        Memory,
    }

    /// <summary>
    /// What is known about one eightbyte of a value.
    ///
    /// <see cref="Used"/> is the last byte any field actually reaches, which is
    /// not the same as how much of the eightbyte exists: <c>{ long; char; }</c>
    /// is sixteen bytes and its second eightbyte holds one. clang sizes the
    /// register by what is used, so a load of it never reaches past the object.
    /// </summary>
    private sealed class EightByte
    {
        public Class Class;
        public int Used;
        public bool HasDouble;

        /// <summary>
        /// The width of the field that begins exactly here, or zero.
        ///
        /// When nothing else in this eightbyte reaches past it, this is the
        /// register's width -- which is how <c>{ long; char; }</c> passes its
        /// second register as an i8 rather than as an i64 covering seven bytes
        /// of padding.
        /// </summary>
        public int FirstWidth;

        /// <summary>Exactly one pointer covers this and nothing else does.</summary>
        public int Pointers;
        public int Others;
    }

    /// <summary>Anything larger travels in memory whatever it holds.</summary>
    private const int MaxRegisterSize = 16;

    private const int Width = 8;

    public static ArgInfo ClassifyArgument(TypeSymbol type, Func<TypeSymbol, string> llvmTypeOf)
    {
        if (type is not StructTypeSymbol structType)
            return new ArgInfo(PassStyle.Direct, llvmTypeOf(type), type);

        if (Pieces(structType, llvmTypeOf) is not { } pieces)
            return new ArgInfo(PassStyle.Indirect, "ptr", type);

        // A one-register value is spelled as that register. A two-register one
        // is two parameters, and only a *return* gathers them into a struct.
        return new ArgInfo(PassStyle.Coerce, pieces[0], type) { Pieces = pieces };
    }

    public static ArgInfo ClassifyReturn(TypeSymbol type, Func<TypeSymbol, string> llvmTypeOf)
    {
        if (type.IsVoid()) return new ArgInfo(PassStyle.Direct, "void", type);

        var info = ClassifyArgument(type, llvmTypeOf);
        if (info.Style != PassStyle.Coerce || info.Pieces.Count < 2) return info;

        // Two registers coming back are one LLVM value, because a function has
        // one return. Going the other way they are two parameters, because it
        // may have as many of those as it likes.
        return info with { LlvmType = "{ " + string.Join(", ", info.Pieces) + " }" };
    }

    /// <summary>
    /// The registers a struct travels in, or null when it travels in memory.
    /// </summary>
    private static IReadOnlyList<string>? Pieces(
        StructTypeSymbol structType, Func<TypeSymbol, string> llvmTypeOf)
    {
        if (structType.Size == 0 || structType.Size > MaxRegisterSize) return null;

        int count = (structType.Size + Width - 1) / Width;
        var parts = new EightByte[count];
        for (int i = 0; i < count; i++) parts[i] = new EightByte();

        if (!Classify(structType, 0, parts, llvmTypeOf)) return null;
        if (parts.Any(p => p.Class is Class.Memory or Class.None)) return null;

        var pieces = new List<string>(count);
        int index = 0;

        foreach (var part in parts)
        {
            pieces.Add(part switch
            {
                { Class: Class.Sse, HasDouble: true } => "double",
                { Class: Class.Sse } => part.Used > 4 ? "<2 x float>" : "float",

                // A lone pointer keeps its own spelling rather than becoming an
                // integer of the same width. Both travel in the same register,
                // and LLVM reasons better about the one that says what it is.
                { Pointers: 1, Others: 0 } => "ptr",

                _ => "i" + IntegerWidth(part, structType.Size, index) * 8,
            });

            index++;
        }

        return pieces;
    }

    /// <summary>
    /// How many bytes an integer register covers.
    ///
    /// The field at the front of the eightbyte, when nothing else there reaches
    /// past it. Otherwise what is left of the value from here, capped at eight
    /// -- which is where an <c>i24</c> comes from, and why a three-byte struct
    /// is not read as four.
    /// </summary>
    private static int IntegerWidth(EightByte part, int totalSize, int index)
    {
        if (part.FirstWidth > 0 && part.Used == part.FirstWidth) return part.FirstWidth;
        return Math.Min(totalSize - index * Width, Width);
    }

    /// <summary>
    /// Marks every eightbyte a value's fields lie in, recursing into whatever
    /// is nested. False means the whole thing goes to memory.
    /// </summary>
    private static bool Classify(
        TypeSymbol type, int at, EightByte[] parts, Func<TypeSymbol, string> llvmTypeOf)
    {
        switch (type)
        {
            // A union's members all begin at offset zero, so they are merged
            // against each other -- and an eightbyte holding both a double and
            // an int is an integer one, because that is what merging says.
            case UnionTypeSymbol union:
                foreach (var member in union.Fields)
                    if (!Classify(member.Type, at, parts, llvmTypeOf))
                        return false;
                return true;

            case StructTypeSymbol nested:
                foreach (var field in nested.Fields)
                {
                    int offset = at + field.Offset;

                    // An unaligned field puts the whole value in memory, which
                    // is what [Packed] usually produces and why a packed struct
                    // is rarely passed in registers.
                    if (!field.IsBitField && field.Type.Alignment > 0 &&
                        offset % field.Type.Alignment != 0)
                        return false;

                    // A bit-field is classified by its storage unit, which is
                    // the whole of its declared type and not one byte of it.
                    // Marking one byte made `{ uint:4; uint:4; uint:24; }` --
                    // four bytes, and a single storage unit -- travel as an i8,
                    // so a caller sent the first eight bits of it and the rest
                    // arrived as zero. The unit is what the emitter loads and
                    // stores, so it is what has to cross.
                    if (field.IsBitField)
                    {
                        Mark(Class.Integer, offset, Math.Max(1, field.Type.Size), parts,
                             isDouble: false, isPointer: false);
                        continue;
                    }

                    if (!Classify(field.Type, offset, parts, llvmTypeOf)) return false;
                }
                return true;

            case FixedArrayTypeSymbol inline:
                for (int i = 0; i < inline.Length; i++)
                    if (!Classify(inline.Element, at + i * inline.Element.Size,
                                  parts, llvmTypeOf))
                        return false;
                return true;

            case PrimitiveTypeSymbol { Kind: PrimitiveKind.Float or PrimitiveKind.Double } real:
                Mark(Class.Sse, at, real.Size, parts,
                     isDouble: real.Kind == PrimitiveKind.Double, isPointer: false);
                return true;

            // Everything else is a scalar in an integer register: an integer, a
            // bool, a code unit, an enum, a pointer, a function pointer, and
            // every kind of reference.
            default:
                Mark(Class.Integer, at, Math.Max(1, type.Size), parts,
                     isDouble: false, isPointer: llvmTypeOf(type) == "ptr");
                return true;
        }
    }

    /// <summary>
    /// Merges a class into every eightbyte the field touches, and records how
    /// far into each one it reaches.
    ///
    /// Integer wins over SSE, which is the whole of the merge rule once x87 is
    /// out of the picture -- and it is, because Stainless has no long double.
    /// </summary>
    private static void Mark(
        Class what, int at, int size, EightByte[] parts, bool isDouble, bool isPointer)
    {
        int first = at / Width;
        int last = (at + size - 1) / Width;

        for (int i = first; i <= last && i < parts.Length; i++)
        {
            var part = parts[i];

            part.Class = part.Class switch
            {
                Class.None => what,
                Class.Integer => Class.Integer,
                _ => what == Class.Integer ? Class.Integer : Class.Sse,
            };

            // How far into this eightbyte the field reaches, which is what the
            // register is sized by.
            int endInPart = Math.Min(Width, at + size - i * Width);
            part.Used = Math.Max(part.Used, endInPart);

            // A double fills its eightbyte, so an SSE eightbyte holding one is
            // passed as a double rather than as a pair of floats.
            if (isDouble) part.HasDouble = true;

            if (isPointer && at % Width == 0 && size == Width) part.Pointers++;
            else part.Others++;

            // The first field to begin exactly at this eightbyte. A union has
            // several, and any of them answers the same, because what decides
            // the width is whether anything reaches past it.
            if (at == i * Width && part.FirstWidth == 0) part.FirstWidth = size;
        }
    }
}
