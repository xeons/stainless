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
    /// <summary>
    /// How a compilation reading this name builds the structural types, which
    /// it has to intern rather than construct: a slice and a tuple are named
    /// types, so two of them made separately would not compare equal, and a
    /// library's <c>int[:]</c> has to be the same symbol as the consumer's.
    /// Null factories mean the reader only wants to know whether the name is
    /// one it could resolve, which is what the metadata writer asks.
    /// </summary>
    public delegate TypeSymbol? SliceFactory(TypeSymbol element);

    public delegate TypeSymbol? TupleFactory(IReadOnlyList<TypeSymbol> elements);

    public static string Write(TypeSymbol type) => type switch
    {
        PrimitiveTypeSymbol primitive => primitive.Name,
        PointerTypeSymbol pointer => Write(pointer.Element) + "*",
        ArrayTypeSymbol array => Write(array.Element) + "[]",
        FixedArrayTypeSymbol inline => $"{Write(inline.Element)}[{inline.Length}]",
        OptionalTypeSymbol optional => Write(optional.Element) + "?",
        WeakTypeSymbol weak => "weak " + Write(weak.Element) + "?",

        // Before the named cases, which both of these are: a slice and a tuple
        // are structural, so what identifies one is what it is made of and not
        // the module it was first written in. Spelled as a name -- both are
        // interned under `Standard` -- they would come out `Standard.int[:]`,
        // which is a type in no source file and which nothing can read back.
        SliceTypeSymbol slice => Write(slice.Element) + "[:]",
        TupleTypeSymbol tuple => "(" + string.Join(", ", tuple.Elements.Select(Write)) + ")",

        NamedTypeSymbol named => named.QualifiedName,
        _ => "void",
    };

    /// <summary>
    /// Resolves a written name against the types a compilation knows, or null
    /// when it names something that is not there.
    /// </summary>
    public static TypeSymbol? Read(
        string name,
        Func<string, NamedTypeSymbol?> lookup,
        SliceFactory? sliceOf = null,
        TupleFactory? tupleOf = null)
    {
        name = name.Trim();

        if (name.StartsWith("weak ", StringComparison.Ordinal))
        {
            // `weak C?` is the only spelling, so the trailing '?' is part of it.
            string inner = name["weak ".Length..].TrimEnd('?');
            return Read(inner, lookup, sliceOf, tupleOf) is { } referenced
                ? new WeakTypeSymbol(referenced)
                : null;
        }

        if (name.EndsWith('?'))
            return Read(name[..^1], lookup, sliceOf, tupleOf) is { } element
                ? new OptionalTypeSymbol(element)
                : null;

        if (name.EndsWith("[]", StringComparison.Ordinal))
            return Read(name[..^2], lookup, sliceOf, tupleOf) is { } element
                ? new ArrayTypeSymbol(element)
                : null;

        // `T[:]`, before `T[N]`, which it would otherwise look like.
        if (name.EndsWith("[:]", StringComparison.Ordinal))
            return Read(name[..^3], lookup, sliceOf, tupleOf) is { } element
                ? sliceOf?.Invoke(element) ?? element
                : null;

        // `T[N]`: the length is part of the type, so it has to survive the trip.
        if (name.EndsWith(']') && name.LastIndexOf('[') is var open && open > 0 &&
            int.TryParse(name[(open + 1)..^1], out int length) && length > 0)
        {
            return Read(name[..open], lookup, sliceOf, tupleOf) is { } element
                ? new FixedArrayTypeSymbol(element, length)
                : null;
        }

        if (name.EndsWith('*'))
            return Read(name[..^1], lookup, sliceOf, tupleOf) is { } pointee
                ? new PointerTypeSymbol(pointee)
                : null;

        if (name.StartsWith('(') && name.EndsWith(')'))
        {
            var elements = new List<TypeSymbol>();

            foreach (string part in SplitElements(name[1..^1]))
            {
                if (Read(part, lookup, sliceOf, tupleOf) is not { } element) return null;
                elements.Add(element);
            }

            if (elements.Count < 2) return null;
            return tupleOf?.Invoke(elements) ?? elements[0];
        }

        return Primitive(name) ?? (TypeSymbol?)lookup(name);
    }

    /// <summary>
    /// The named types a written name is built out of, with every wrapper
    /// peeled off and the primitives left out: what <c>(int, App.Point[:])</c>
    /// mentions is <c>App.Point</c>.
    ///
    /// The metadata writer asks this to find a public surface naming something
    /// the metadata does not carry. It goes through <see cref="Read"/> rather
    /// than trimming characters at the call site, so that the spelling this
    /// recognises and the spelling a consumer accepts cannot drift apart --
    /// which is exactly how <c>char16</c> came to be written by a library and
    /// unreadable by anything that referenced it.
    /// </summary>
    public static IEnumerable<string> LeafNames(string written)
    {
        var mentioned = new List<string>();

        Read(
            written,
            name =>
            {
                mentioned.Add(name);
                return Placeholder_;
            },
            element => element,
            elements => elements[0]);

        return mentioned;
    }

    /// <summary>Stands in for a named type while <see cref="LeafNames"/> walks one.</summary>
    private static readonly NamedTypeSymbol Placeholder_ =
        new StructTypeSymbol { SimpleName = "?", ModuleName = "?" };

    /// <summary>
    /// A tuple's elements, split at the commas that are its own. An element may
    /// be a tuple or a fixed array, so the depth has to be counted rather than
    /// the string split.
    /// </summary>
    private static List<string> SplitElements(string inside)
    {
        var parts = new List<string>();
        int depth = 0, start = 0;

        for (int i = 0; i < inside.Length; i++)
        {
            switch (inside[i])
            {
                case '(' or '[': depth++; break;
                case ')' or ']': depth--; break;
                case ',' when depth == 0:
                    parts.Add(inside[start..i]);
                    start = i + 1;
                    break;
            }
        }

        parts.Add(inside[start..]);
        return parts;
    }

    /// <summary>
    /// The primitives by the name they are written under, taken from the list
    /// the type system itself keeps.
    ///
    /// A second copy of that list is what this was, and it was two names short
    /// -- <c>char16</c> and <c>char32</c> -- so a public struct with one in it
    /// was described by the library and unreadable by its consumer. Derived
    /// from <see cref="PrimitiveTypeSymbol.All"/>, it cannot fall behind again.
    /// </summary>
    private static readonly Dictionary<string, PrimitiveTypeSymbol> Primitives_ =
        PrimitiveTypeSymbol.All.ToDictionary(p => p.Name, StringComparer.Ordinal);

    private static PrimitiveTypeSymbol? Primitive(string name) =>
        Primitives_.TryGetValue(name, out var found) ? found : null;
}
