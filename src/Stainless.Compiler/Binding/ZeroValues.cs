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
/// Whether a type has a zero value: whether storage left as zero bytes is a
/// value of the type. It has none when those bytes would hold a null in a
/// reference whose type says it is never null: §2.16 of the specification.
/// </summary>
internal static class ZeroValues
{
    /// <summary>
    /// Where the zero of a type breaks a promise, or null when it keeps them
    /// all: the path to the slot, as <c>Holder.Data</c>, and the type that
    /// slot cannot be null in.
    /// </summary>
    public static (string Path, TypeSymbol Slot)? FindNullInZero(TypeSymbol type) =>
        FindNullInZero(type, [], type.Name);

    /// <summary>True when the zero of the type is a value of it.</summary>
    public static bool HasZeroValue(TypeSymbol type) => FindNullInZero(type) is null;

    /// <param name="walked">
    /// The structs this question is already inside. A struct cannot contain
    /// itself, and layout reports one that tries, so a second visit is the
    /// cycle and answers nothing further.
    /// </param>
    private static (string Path, TypeSymbol Slot)? FindNullInZero(
        TypeSymbol type, HashSet<TypeSymbol> walked, string path)
    {
        switch (type)
        {
            case ErrorTypeSymbol:
            case OptionalTypeSymbol or WeakTypeSymbol or PointerTypeSymbol or DelegateTypeSymbol:
                return null;

            // A union may not hold a counted reference, so its bytes hold
            // none to be null.
            case UnionTypeSymbol:
                return null;

            // Its function word is null, and nothing asks before calling it,
            // unless it is `Notify?`, whose null is asked about.
            case ClosureTypeSymbol { IsNullable: true }:
                return null;

            case ClosureTypeSymbol:
                return (path, type);

            case FixedArrayTypeSymbol inline:
                return FindNullInZero(inline.Element, walked, path + "[0]");

            // A zero tag is the first case, with its payload zeroed.
            case VariantTypeSymbol variant:
            {
                if (!walked.Add(type) ||
                    variant.Cases.FirstOrDefault(c => c.Tag == 0) is not { } first)
                    return null;

                foreach (var field in first.Fields)
                {
                    string inside = $"{path}.{first.Name}.{field.Name}";
                    if (FindNullInZero(field.Type, walked, inside) is { } found)
                        return found;
                }

                return null;
            }

            case StructTypeSymbol structType:
            {
                if (!walked.Add(type))
                    return null;

                foreach (var field in structType.Fields)
                {
                    if (FindNullInZero(field.Type, walked, $"{path}.{field.Name}") is { } found)
                        return found;
                }

                return null;
            }

            case ComInterfaceTypeSymbol:
                return (path, type);

            default:
                return type.IsReferenceType ? (path, type) : null;
        }
    }
}
