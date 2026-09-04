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

namespace Stainless.Driver;

/// <summary>
/// Writes and reads the type names that appear in metadata.
///
/// A metadata file is read by a compilation that shares no symbols with the one
/// that wrote it, so a type has to survive as text. The spelling is the source
/// spelling with the module attached — <c>App.Math.Vector</c>, <c>int</c>,
/// <c>byte*</c>, <c>App.Shapes.Circle?</c> — which makes the file legible and
/// makes a mismatch say something a person can act on.
/// </summary>
public static class MetadataTypeNames
{
    public static string Write(TypeSymbol type) => type switch
    {
        PrimitiveTypeSymbol primitive => primitive.Name,
        PointerTypeSymbol pointer => Write(pointer.Element) + "*",
        ArrayTypeSymbol array => Write(array.Element) + "[]",
        FixedArrayTypeSymbol inline => $"{Write(inline.Element)}[{inline.Length}]",
        OptionalTypeSymbol optional => Write(optional.Element) + "?",
        WeakTypeSymbol weak => "weak " + Write(weak.Element) + "?",
        NamedTypeSymbol named => named.QualifiedName,
        _ => "void",
    };

    /// <summary>
    /// Resolves a written name against the types a compilation knows, or null
    /// when it names something that is not there.
    /// </summary>
    public static TypeSymbol? Read(string name, Func<string, NamedTypeSymbol?> lookup)
    {
        name = name.Trim();

        if (name.StartsWith("weak ", StringComparison.Ordinal))
        {
            // `weak C?` is the only spelling, so the trailing '?' is part of it.
            string inner = name["weak ".Length..].TrimEnd('?');
            return Read(inner, lookup) is { } referenced ? new WeakTypeSymbol(referenced) : null;
        }

        if (name.EndsWith('?'))
            return Read(name[..^1], lookup) is { } element ? new OptionalTypeSymbol(element) : null;

        if (name.EndsWith("[]", StringComparison.Ordinal))
            return Read(name[..^2], lookup) is { } element ? new ArrayTypeSymbol(element) : null;

        // `T[N]`: the length is part of the type, so it has to survive the trip.
        if (name.EndsWith(']') && name.LastIndexOf('[') is var open && open > 0 &&
            int.TryParse(name[(open + 1)..^1], out int length) && length > 0)
        {
            return Read(name[..open], lookup) is { } element
                ? new FixedArrayTypeSymbol(element, length)
                : null;
        }

        if (name.EndsWith('*'))
            return Read(name[..^1], lookup) is { } pointee ? new PointerTypeSymbol(pointee) : null;

        return Primitive(name) ?? (TypeSymbol?)lookup(name);
    }

    private static PrimitiveTypeSymbol? Primitive(string name) => name switch
    {
        "void" => PrimitiveTypeSymbol.Void,
        "bool" => PrimitiveTypeSymbol.Bool,
        "char" => PrimitiveTypeSymbol.Char,
        "sbyte" => PrimitiveTypeSymbol.SByte,
        "short" => PrimitiveTypeSymbol.Short,
        "int" => PrimitiveTypeSymbol.Int,
        "long" => PrimitiveTypeSymbol.Long,
        "nint" => PrimitiveTypeSymbol.NInt,
        "byte" => PrimitiveTypeSymbol.Byte,
        "ushort" => PrimitiveTypeSymbol.UShort,
        "uint" => PrimitiveTypeSymbol.UInt,
        "ulong" => PrimitiveTypeSymbol.ULong,
        "nuint" => PrimitiveTypeSymbol.NUInt,
        "float" => PrimitiveTypeSymbol.Float,
        "double" => PrimitiveTypeSymbol.Double,
        _ => null,
    };
}
