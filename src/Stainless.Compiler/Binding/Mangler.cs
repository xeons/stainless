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

using System.Text;
using Stainless.Syntax;

namespace Stainless.Binding;

/// <summary>
/// Produces linker symbol names. The scheme is documented in docs/abi.md and is
/// deliberately length-prefixed so it needs no separators and never collides
/// with a C identifier (which cannot contain the leading "_SL" plus digits shape
/// this produces for any realistic name).
/// </summary>
public static class Mangler
{
    public static string Mangle(FunctionSymbol function)
    {
        // C linkage means "use exactly this name" in both directions.
        if (function.Linkage is LinkageKind.ExternC or LinkageKind.ExportC)
            return function.Name;

        var sb = new StringBuilder("_SL");

        foreach (string segment in function.ModuleName.Split('.', StringSplitOptions.RemoveEmptyEntries))
            AppendIdentifier(sb, segment);

        // An instantiated generic's simple name is `Box<int>`, which a linker
        // symbol may not contain.
        if (function.ContainingType is not null)
            AppendIdentifier(sb, SymbolSafe(function.ContainingType.SimpleName));

        AppendIdentifier(sb, function.Kind switch
        {
            FunctionKind.Constructor => "ctor",
            FunctionKind.Destructor => "dtor",
            _ => function.Name,
        });

        // An instantiated generic carries its type arguments, so two
        // instantiations never collide even when their parameters match.
        if (function.TypeArguments.Count > 0)
        {
            sb.Append('G').Append(function.TypeArguments.Count);
            foreach (var argument in function.TypeArguments) AppendType(sb, argument);
        }

        var valueParameters = function.Parameters.Where(p => !p.IsThis).ToList();
        if (valueParameters.Count == 0) sb.Append('v');
        else foreach (var parameter in valueParameters) AppendType(sb, parameter.Type);

        if (function.IsVariadic) sb.Append('z');

        sb.Append('E');
        AppendType(sb, function.ReturnType);
        return sb.ToString();
    }

    /// <summary>The symbol holding a class's static <c>TypeInfo</c> record.</summary>
    public static string TypeInfoSymbol(ClassTypeSymbol type) =>
        "_SLti" + Sanitize(type.QualifiedName);

    private static void AppendIdentifier(StringBuilder sb, string identifier)
    {
        sb.Append(identifier.Length);
        sb.Append(identifier);
    }

    private static void AppendType(StringBuilder sb, TypeSymbol type)
    {
        switch (type)
        {
            case PrimitiveTypeSymbol primitive:
                sb.Append(PrimitiveCode(primitive.Kind));
                break;

            case PointerTypeSymbol pointer:
                sb.Append('P');
                AppendType(sb, pointer.Element);
                break;

            case ArrayTypeSymbol array:
                sb.Append('A');
                AppendType(sb, array.Element);
                break;

            case OptionalTypeSymbol optional:
                sb.Append('O');
                AppendType(sb, optional.Element);
                break;

            case WeakTypeSymbol weak:
                sb.Append('W');
                AppendType(sb, weak.Element);
                break;

            case ClassTypeSymbol classType:
                sb.Append('C');
                AppendIdentifier(sb, Sanitize(classType.QualifiedName));
                break;

            case InterfaceTypeSymbol interfaceType:
                sb.Append('I');
                AppendIdentifier(sb, Sanitize(interfaceType.QualifiedName));
                break;

            case StructTypeSymbol structType:
                sb.Append('S');
                AppendIdentifier(sb, Sanitize(structType.QualifiedName));
                break;

            case EnumTypeSymbol enumType:
                sb.Append('E');
                AppendIdentifier(sb, Sanitize(enumType.QualifiedName));
                break;

            case DelegateTypeSymbol delegateType:
                sb.Append('D');
                AppendIdentifier(sb, Sanitize(delegateType.QualifiedName));
                break;

            default:
                sb.Append('v');
                break;
        }
    }

    private static char PrimitiveCode(PrimitiveKind kind) => kind switch
    {
        PrimitiveKind.SByte => 'a',
        PrimitiveKind.Short => 's',
        PrimitiveKind.Int => 'i',
        PrimitiveKind.Long => 'l',
        PrimitiveKind.NInt => 'n',
        PrimitiveKind.Byte => 'h',
        PrimitiveKind.UShort => 't',
        PrimitiveKind.UInt => 'j',
        PrimitiveKind.ULong => 'm',
        PrimitiveKind.NUInt => 'y',
        PrimitiveKind.Float => 'f',
        PrimitiveKind.Double => 'd',
        PrimitiveKind.Bool => 'b',
        PrimitiveKind.Char => 'c',
        _ => 'v',
    };

    /// <summary>
    /// Reduces a name to what a linker symbol may contain. Instantiated generics
    /// arrive here as <c>App.Box&lt;int&gt;</c>, arrays as <c>int[]</c>, and both
    /// the mangler and the emitter must agree on the result.
    /// </summary>
    public static string SymbolSafe(string name) =>
        new(name.Select(c => char.IsLetterOrDigit(c) ? c : '_').ToArray());

    private static string Sanitize(string qualifiedName) => SymbolSafe(qualifiedName);
}
