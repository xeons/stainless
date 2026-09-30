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

namespace Stainless.Binding;

/// <summary>
/// Where a value has a bit pattern no value of its type uses: a reference
/// that is never null. A variant of two cases, the first carrying nothing,
/// spends that null on its first case and needs no tag (docs/abi.md 2.3).
/// </summary>
internal static class Niches
{
    /// <summary>
    /// The byte offset of the first never-null reference inside a laid-out
    /// type, or null when it has none. Structs and tuples are looked into;
    /// a variant, a union and a slice are not, since each can hold a null
    /// or garbage in any of its words.
    /// </summary>
    public static int? FindNiche(TypeSymbol type) => FindNiche(type, 0);

    private static int? FindNiche(TypeSymbol type, int at)
    {
        // An empty slot is a null in any of its words, so a slot has no niche.
        // In the order ZeroValues.FindNullInZero asks, so that a type has no
        // zero value exactly when it has a niche or holds a tagged variant
        // whose zero is what has none.
        switch (type)
        {
            case ErrorTypeSymbol:
            case OptionalTypeSymbol or WeakTypeSymbol or PointerTypeSymbol or DelegateTypeSymbol:
            case FixedArrayTypeSymbol:
                return null;

            case ClosureTypeSymbol { IsNullable: false } closure:
                return at + closure.Fields[0].Offset;

            case ClosureTypeSymbol or VariantTypeSymbol or UnionTypeSymbol or SliceTypeSymbol
                or SlotTypeSymbol:
                return null;

            case StructTypeSymbol structType:
                foreach (var field in structType.Fields)
                {
                    if (field.IsBitField)
                        continue;
                    if (FindNiche(field.Type, at + field.Offset) is { } found)
                        return found;
                }
                return null;

            case ComInterfaceTypeSymbol:
                return at;

            default:
                return type.IsReferenceType ? at : null;
        }
    }
}
