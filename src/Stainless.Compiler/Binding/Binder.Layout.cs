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

using Stainless.Source;
using Stainless.Syntax;

namespace Stainless.Binding;

/// <summary>
/// Pass 6: where each field sits, using the platform C rules.
///
/// A class reference is a pointer, so a class may contain itself; a
/// struct may not, and that cycle is caught here.
/// </summary>
public sealed partial class Binder
{
    // ============================================================ pass 6

    private void ComputeLayouts()
    {
        var inProgress = new HashSet<NamedTypeSymbol>();
        foreach (var type in _modules.Values.SelectMany(m => m.Types.Values))
            ComputeLayout(type, inProgress);
    }

    /// <summary>
    /// Lays out a type using the platform C rules. Class references are pointers,
    /// so a class may contain itself; a struct may not, and that cycle is reported here.
    /// </summary>
    private void ComputeLayout(NamedTypeSymbol type, HashSet<NamedTypeSymbol> inProgress)
    {
        if (type.LayoutComputed) return;

        if (!inProgress.Add(type))
        {
            diagnostics.Error("SL0216", type.Span ?? default,
                $"struct '{type.QualifiedName}' contains itself, so it has no finite size");
            type.SetLayout(0, 1);
            return;
        }

        // A variant's payload field has no size until every case has one, so
        // the filler is built here, immediately before the fields are walked.
        if (type is VariantTypeSymbol variant) SizePayloadStorage(variant, inProgress);

        // Every member of a union starts where the union does; its size is the
        // widest of them. That is the whole of the layout, and it is why a union
        // records nothing about which member is the live one.
        if (type is UnionTypeSymbol union)
        {
            int widest = 0, strictest = 1;

            foreach (var member in union.Fields)
            {
                if (member.Type is StructTypeSymbol nestedMember)
                    ComputeLayout(nestedMember, inProgress);

                member.Offset = 0;
                member.BitOffset = 0;
                widest = Math.Max(widest, member.Type.Size);
                strictest = Math.Max(strictest, Math.Max(1, member.Type.Alignment));
            }

            if (union.IsPacked) strictest = 1;
            if (union.RequestedAlignment is { } wanted) strictest = Math.Max(strictest, wanted);

            union.SetLayout(Math.Max(1, TypeExtensions.AlignTo(widest, strictest)), strictest);
            inProgress.Remove(type);
            return;
        }

        if (type.Fields.Any(f => f.IsBitField))
        {
            LayOutWithBitFields(type, inProgress);
            inProgress.Remove(type);
            return;
        }

        int offset = 0, alignment = 1;

        // A derived class's fields begin where its base's end, so the base
        // subobject is a prefix of the derived one and starts at the same
        // address. That is what makes an upcast free, and what makes every
        // inherited method's field offsets right without recomputing them.
        if (type is ClassTypeSymbol { BaseClass: { } inheritedFrom })
        {
            ComputeLayout(inheritedFrom, inProgress);
            offset = inheritedFrom.FieldsSize;
            alignment = Math.Max(alignment, inheritedFrom.FieldsAlignment);
        }

        foreach (var field in type.Fields)
        {
            // Only a struct field forces its type to be laid out first.
            if (field.Type is StructTypeSymbol nested)
                ComputeLayout(nested, inProgress);

            // Packed means no padding anywhere: a field lands where the one
            // before it ended, and the type asks nothing of its own address.
            int fieldAlignment = type.IsPacked ? 1 : Math.Max(1, field.Type.Alignment);
            offset = TypeExtensions.AlignTo(offset, fieldAlignment);
            field.Offset = offset;
            offset += field.Type.Size;
            alignment = Math.Max(alignment, fieldAlignment);
        }

        // [Align(N)] raises and never lowers, as alignas does -- including over
        // [Packed], so the two together mean "no padding inside, but put the
        // whole of it on an N-byte boundary".
        if (type.RequestedAlignment is { } requested)
            alignment = Math.Max(alignment, requested);

        // A struct with no fields still takes a byte, because the emitter gives
        // it one: LLVM has no zero-sized named struct, so a fieldless struct is
        // emitted as `type { i8 }`. If the binder disagreed, every copy of a
        // struct containing one would move the wrong number of bytes and read
        // its own padding. C++ and Rust settle it the same way.
        int size = type is StructTypeSymbol && type.Fields.Count == 0
            ? 1
            : TypeExtensions.AlignTo(offset, alignment);

        type.SetLayout(size, alignment);
        inProgress.Remove(type);
    }

    /// <summary>
    /// Lays out a struct that has bit-fields in it.
    ///
    /// The two C ABIs genuinely disagree here, and not in a corner: for
    /// <c>struct { int a : 1; char b : 1; }</c> gcc gives four bytes and MSVC
    /// gives eight. So there are two algorithms, chosen the way the C++ mangler
    /// chooses a scheme, and both are checked against what the target's own
    /// compiler makes of the same declaration.
    ///
    /// **Itanium** packs to the bit and starts a new storage unit only when a
    /// field would cross a boundary of its own declared type. A three-bit
    /// <c>int</c> followed by a four-bit <c>short</c> share one word.
    ///
    /// **Microsoft** keeps a current storage unit of one declared type's size,
    /// and opens a new one whenever the next field will not fit *or* is declared
    /// with a type of a different size. The same two fields land in a four-byte
    /// unit and a two-byte one.
    /// </summary>
    private void LayOutWithBitFields(NamedTypeSymbol type, HashSet<NamedTypeSymbol> inProgress)
    {
        // Checked here rather than where the width was read, because [Packed] is
        // not known until attributes have been folded and that is a pass later.
        if (type.IsPacked)
            diagnostics.Error("SL0470", type.Span ?? default,
                $"'{type.Name}' is '[Packed]' and has bit-fields, and the two together mean " +
                "different things to different C compilers -- gcc packs the bits and MSVC keeps " +
                "the storage unit. Until one of them is chosen and checked against it, this is " +
                "refused rather than guessed");

        foreach (var nested in type.Fields.Select(f => f.Type).OfType<StructTypeSymbol>())
            ComputeLayout(nested, inProgress);

        int alignment = 1;
        foreach (var field in type.Fields)
            alignment = Math.Max(alignment, Math.Max(1, field.Type.Alignment));

        if (type.RequestedAlignment is { } wanted) alignment = Math.Max(alignment, wanted);

        int size = _cppAbi == CppAbi.Microsoft
            ? LayOutMicrosoftBitFields(type)
            : LayOutItaniumBitFields(type);

        type.SetLayout(Math.Max(1, TypeExtensions.AlignTo(size, alignment)), alignment);
    }

    /// <summary>
    /// gcc and clang: allocate at the next free bit, and move to the next
    /// boundary of the declared type only when the field would straddle one.
    /// </summary>
    private static int LayOutItaniumBitFields(NamedTypeSymbol type)
    {
        long bit = 0;

        foreach (var field in type.Fields)
        {
            if (field.BitWidth is not { } width)
            {
                // An ordinary field closes whatever was being filled and takes
                // its own alignment from the byte it lands on.
                int at = TypeExtensions.AlignTo(
                    (int)((bit + 7) / 8), Math.Max(1, field.Type.Alignment));
                field.Offset = at;
                field.BitOffset = 0;
                bit = (long)(at + field.Type.Size) * 8;
                continue;
            }

            long unit = (long)field.Type.Size * 8;

            // A bit-field must sit inside one storage unit of its own type. If
            // it would cross the boundary, it starts at the next one.
            if (bit / unit != (bit + width - 1) / unit)
                bit = (bit + unit - 1) / unit * unit;

            long start = bit / unit * unit;
            field.Offset = (int)(start / 8);
            field.BitOffset = (int)(bit - start);
            bit += width;
        }

        return (int)((bit + 7) / 8);
    }

    /// <summary>
    /// MSVC: keep a storage unit of one declared type's size, and open a new one
    /// when the next field does not fit or is declared with a different size.
    /// </summary>
    private static int LayOutMicrosoftBitFields(NamedTypeSymbol type)
    {
        int offset = 0;             // where the next thing goes
        int unitAt = -1;            // byte offset of the open storage unit
        int unitSize = 0;           // its size, from the type that opened it
        int unitUsed = 0;           // bits of it spoken for

        foreach (var field in type.Fields)
        {
            if (field.BitWidth is not { } width)
            {
                // An ordinary field closes the unit outright.
                unitAt = -1;
                offset = TypeExtensions.AlignTo(offset, Math.Max(1, field.Type.Alignment));
                field.Offset = offset;
                field.BitOffset = 0;
                offset += field.Type.Size;
                continue;
            }

            int size = field.Type.Size;

            bool fits = unitAt >= 0 && size == unitSize && unitUsed + width <= size * 8;

            if (!fits)
            {
                offset = TypeExtensions.AlignTo(offset, Math.Max(1, field.Type.Alignment));
                unitAt = offset;
                unitSize = size;
                unitUsed = 0;
                offset += size;
            }

            field.Offset = unitAt;
            field.BitOffset = unitUsed;
            unitUsed += width;
        }

        return offset;
    }

    /// <summary>
    /// Gives a variant's payload field exactly the size and alignment the widest
    /// case needs.
    ///
    /// There is no way to say "N bytes, aligned to A" in the type system, so the
    /// filler says it in fields: as many integers of A bytes as it takes to
    /// cover the widest payload. LLVM lays that out to the same size and the
    /// same alignment the C rules give it here, which is what lets a case's
    /// fields be read straight out of the payload's address.
    /// </summary>
    private void SizePayloadStorage(VariantTypeSymbol variant, HashSet<NamedTypeSymbol> inProgress)
    {
        if (variant.PayloadStorage is not { } storage || storage.LayoutComputed) return;

        int size = 0, alignment = 1;

        foreach (var payload in variant.Cases.Select(c => c.Payload).OfType<StructTypeSymbol>())
        {
            ComputeLayout(payload, inProgress);
            size = Math.Max(size, payload.Size);
            alignment = Math.Max(alignment, payload.Alignment);
        }

        var element = alignment switch
        {
            >= 8 => PrimitiveTypeSymbol.ULong,
            >= 4 => PrimitiveTypeSymbol.UInt,
            >= 2 => PrimitiveTypeSymbol.UShort,
            _ => PrimitiveTypeSymbol.Byte,
        };

        int count = Math.Max(1, (size + element.Size - 1) / element.Size);
        for (int i = 0; i < count; i++)
            storage.Fields.Add(new FieldSymbol("e" + i, element, storage, i));

        ComputeLayout(storage, inProgress);
    }
}
