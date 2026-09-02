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

        if (function.ContainingType is not null)
            AppendIdentifier(sb, function.ContainingType.SimpleName);

        AppendIdentifier(sb, function.Kind switch
        {
            FunctionKind.Constructor => "ctor",
            FunctionKind.Destructor => "dtor",
            _ => function.Name,
        });

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

            case StructTypeSymbol structType:
                sb.Append('S');
                AppendIdentifier(sb, Sanitize(structType.QualifiedName));
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

    private static string Sanitize(string qualifiedName) => qualifiedName.Replace('.', '_');
}
