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

using System.Globalization;
using System.Text;
using Stainless.Binding;
using Stainless.Syntax;

namespace Stainless.Emit;

/// <summary>
/// The runtime type descriptions: a TypeInfo per type, the field
/// metadata reflection walks, and the attribute tables.
///
/// The <c>FieldKind</c> numbering here is an ABI shared with
/// <c>runtime/stainless.h</c> and <c>stdlib/Reflection.sl</c>. A new kind
/// is appended, never inserted.
/// </summary>
public sealed partial class LlvmEmitter
{
    private void TypeInfos(BoundProgram program)
    {
        _interfaceCount = program.Interfaces.Count;

        // A class from a referenced library keeps its table in that library.
        // Rebuilding one here would give an object a destructor compiled on this
        // side, which is not the one its fields were laid out for. Such a class
        // is not in program.Classes at all, for the same reason: nothing about it
        // is emitted except the name.
        foreach (string imported in program.Modules
                     .SelectMany(m => m.Types.Values)
                     .OfType<ClassTypeSymbol>()
                     .Select(c => c.ExternalTypeInfo)
                     .OfType<string>()
                     .Distinct(StringComparer.Ordinal)
                     .Order(StringComparer.Ordinal))
            // Windows needs dllimport on data. A function the linker can reach
            // through a generated thunk; a constant it cannot, because the
            // address has to come from the import address table.
            _module.AppendLine(OperatingSystem.IsWindows()
                ? $"@{imported} = external dllimport constant %SlTypeInfo"
                : $"@{imported} = external constant %SlTypeInfo");

        foreach (var classType in program.Classes)
        {
            string nameConstant = InternBytes(classType.QualifiedName);
            string tables = classType.Interfaces.Count > 0
                ? "@" + InterfaceTableName(classType)
                : "null";

            // A library's public classes are allocated through this table by
            // whoever consumes them, so it has to leave the binary.
            string visibility = forSharedLibrary && forStainlessConsumers && classType.IsPublic
                ? OperatingSystem.IsWindows() ? "dllexport constant" : "constant"
                : "internal constant";

            string baseInfo = classType.BaseClass is { } derivedFrom
                ? "@" + Mangler.TypeInfoSymbol(derivedFrom)
                : "null";

            string vtable = classType.VirtualTable.Count > 0
                ? "@" + VirtualTableName(classType)
                : "null";

            // A com class's tear-offs: which interface each one answers for and
            // where in the object it sits, which is what the generated
            // QueryInterface scans and what its AddRef subtracts.
            string comLayout = classType.IsCom && classType.ComInterfaces.Count > 0
                ? "@" + ComLayoutName(classType)
                : "null";

            _module.AppendLine(
                $"@{Mangler.TypeInfoSymbol(classType)} = {visibility} %SlTypeInfo " +
                $"{{ i64 {classType.InstanceSize}, ptr @{DestroyName(classType)}, " +
                $"ptr {nameConstant}, ptr {tables}, {Metadata(classType, ClassTypeSymbol.HeaderSize)}, " +
                $"ptr {baseInfo}, ptr {vtable}, ptr {comLayout} }}");
        }

        // One TypeInfo per array type. The element type is not recorded at run
        // time; instead each destroy hook already knows how to walk its elements,
        // which keeps the array header the same 32 bytes whatever it holds.
        foreach (var arrayType in program.Arrays)
        {
            string nameConstant = InternBytes(arrayType.Name);
            _module.AppendLine(
                $"@{ArrayTypeInfoName(arrayType)} = internal constant %SlTypeInfo " +
                $"{{ i64 {ArrayTypeSymbol.HeaderSize}, ptr @{ArrayDestroyName(arrayType)}, " +
                $"ptr {nameConstant}, ptr null, i64 0, ptr null, i64 0, ptr null, " +
                "ptr null, ptr null, ptr null }");
        }

        foreach (var structType in program.Modules
                     .SelectMany(m => m.Types.Values)
                     .OfType<StructTypeSymbol>()
                     .Where(t => t.IsReflected))
        {
            // A struct has no object header, so its metadata is reached only
            // through typeof rather than through an instance.
            string nameConstant = InternBytes(structType.QualifiedName);
            _module.AppendLine(
                $"@{StructTypeInfoName(structType)} = internal constant %SlTypeInfo " +
                $"{{ i64 {structType.Size}, ptr null, ptr {nameConstant}, ptr null, " +
                $"{Metadata(structType, 0)}, ptr null, ptr null, ptr null }}");
        }

        if (program.Classes.Count > 0 || program.Arrays.Count > 0) _module.AppendLine();
    }

    private static string StructTypeInfoName(StructTypeSymbol type) =>
        "_SLti_struct_" + Mangler.SymbolSafe(type.QualifiedName);

    /// <summary>The TypeInfo constant holding a reflected type's metadata.</summary>
    public static string TypeInfoOf(NamedTypeSymbol type) => type switch
    {
        ClassTypeSymbol classType => "@" + Mangler.TypeInfoSymbol(classType),
        StructTypeSymbol structType => "@" + StructTypeInfoName(structType),
        _ => "null",
    };

    /// <summary>
    /// The trailing half of a TypeInfo: field and attribute tables, or four
    /// zeroes when the type was not marked [Reflect]. The tables are constants,
    /// so they cost binary size and nothing else.
    /// </summary>
    private string Metadata(NamedTypeSymbol type, int fieldBase)
    {
        if (!type.IsReflected) return "i64 0, ptr null, i64 0, ptr null";

        // What an instance holds, not what its class declared: a derived class
        // reflects everything it inherited too, because that is what is in the
        // object a deserializer is about to fill in. The offsets are already
        // absolute, so the base's fields need no adjusting.
        var reflected = type is ClassTypeSymbol withBase
            ? withBase.AllFields().ToList()
            : type.Fields.ToList();

        string fields = "null";
        if (reflected.Count > 0)
        {
            // Materialised before the name is taken and before anything is
            // appended: building a row emits its own attribute tables, and
            // StringBuilder's interpolation handler appends as it goes, so a
            // lazy sequence here would nest one constant inside another.
            var rows = reflected.Select(field =>
            {
                string attributes = AttributeTable(field.Attributes);

                return $"%SlFieldInfo {{ ptr {InternBytes(field.Name)}, " +
                       $"i64 {fieldBase + field.Offset}, i32 {(int)KindOf(field.Type)}, " +
                       $"ptr {NestedTypeInfo(field.Type)}, {attributes} }}";
            }).ToList();

            string body = string.Join(", ", rows);
            fields = "@" + NextMetadataName("fields");
            _metadata.AppendLine(
                $"{fields} = internal constant [{reflected.Count} x %SlFieldInfo] [{body}]");
        }

        string typeAttributes = AttributeTable(type.Attributes);

        return $"i64 {reflected.Count}, ptr {fields}, {typeAttributes}";
    }

    /// <summary>Emits an attribute table and returns its count-and-pointer pair.</summary>
    private string AttributeTable(IReadOnlyList<AppliedAttribute> attributes)
    {
        if (attributes.Count == 0) return "i64 0, ptr null";

        var rows = new List<string>();
        foreach (var attribute in attributes)
        {
            string values = "null";
            if (attribute.Values.Count > 0)
            {
                var cells = attribute.Values.Select(value => value switch
                {
                    string text =>
                        $"%SlAttributeValue {{ i32 {(int)FieldKind.String}, i64 0, " +
                        $"ptr {InternBytes(text)} }}",
                    bool flag =>
                        $"%SlAttributeValue {{ i32 {(int)FieldKind.Bool}, " +
                        $"i64 {(flag ? 1 : 0)}, ptr null }}",
                    double number =>
                        $"%SlAttributeValue {{ i32 {(int)FieldKind.Double}, " +
                        $"i64 {BitConverter.DoubleToInt64Bits(number)}, ptr null }}",
                    ulong number =>
                        $"%SlAttributeValue {{ i32 {(int)FieldKind.Long}, " +
                        $"i64 {unchecked((long)number)}, ptr null }}",
                    _ => $"%SlAttributeValue {{ i32 0, i64 0, ptr null }}",
                });

                string cellBody = string.Join(", ", cells.ToList());
                values = "@" + NextMetadataName("values");
                _metadata.AppendLine(
                    $"{values} = internal constant " +
                    $"[{attribute.Values.Count} x %SlAttributeValue] [{cellBody}]");
            }

            rows.Add($"%SlAttribute {{ ptr {InternBytes(attribute.Type.SimpleName)}, " +
                     $"i64 {attribute.Values.Count}, ptr {values} }}");
        }

        string rowBody = string.Join(", ", rows);
        string table = "@" + NextMetadataName("attributes");
        _metadata.AppendLine(
            $"{table} = internal constant [{attributes.Count} x %SlAttribute] [{rowBody}]");

        return $"i64 {attributes.Count}, ptr {table}";
    }

    private readonly StringBuilder _metadata = new();
    private int _nextMetadata;

    private string NextMetadataName(string hint) => $".meta.{hint}.{_nextMetadata++}";

    /// <summary>The TypeInfo a field's own type points at, when it has one.</summary>
    private static string NestedTypeInfo(TypeSymbol type) => type switch
    {
        StructTypeSymbol { IsReflected: true } structType => TypeInfoOf(structType),
        ClassTypeSymbol { IsIntrinsic: false } classType => TypeInfoOf(classType),
        _ => "null",
    };

    /// <summary>Kept in step with enum SlKind in the runtime.</summary>
    private enum FieldKind
    {
        None = 0,
        Bool, Char, SByte, Short, Int, Long, NInt,
        Byte, UShort, UInt, ULong, NUInt,
        Float, Double,
        Pointer, String, Class, Interface, Struct, Array,

        // Appended, not slotted in beside Char: the number is what the
        // runtime and Reflection.sl agree on, so the ones already given
        // out cannot move.
        Char16, Char32,
    }

    private static FieldKind KindOf(TypeSymbol type) => type switch
    {
        PrimitiveTypeSymbol primitive => primitive.Kind switch
        {
            PrimitiveKind.Bool => FieldKind.Bool,
            PrimitiveKind.Char => FieldKind.Char,
            PrimitiveKind.Char16 => FieldKind.Char16,
            PrimitiveKind.Char32 => FieldKind.Char32,
            PrimitiveKind.SByte => FieldKind.SByte,
            PrimitiveKind.Short => FieldKind.Short,
            PrimitiveKind.Int => FieldKind.Int,
            PrimitiveKind.Long => FieldKind.Long,
            PrimitiveKind.NInt => FieldKind.NInt,
            PrimitiveKind.Byte => FieldKind.Byte,
            PrimitiveKind.UShort => FieldKind.UShort,
            PrimitiveKind.UInt => FieldKind.UInt,
            PrimitiveKind.ULong => FieldKind.ULong,
            PrimitiveKind.NUInt => FieldKind.NUInt,
            PrimitiveKind.Float => FieldKind.Float,
            PrimitiveKind.Double => FieldKind.Double,
            _ => FieldKind.None,
        },
        ClassTypeSymbol { SimpleName: "String", IsIntrinsic: true } => FieldKind.String,
        ClassTypeSymbol => FieldKind.Class,
        InterfaceTypeSymbol => FieldKind.Interface,
        StructTypeSymbol => FieldKind.Struct,
        ArrayTypeSymbol => FieldKind.Array,
        PointerTypeSymbol => FieldKind.Pointer,
        OptionalTypeSymbol optional => KindOf(optional.Element),
        _ => FieldKind.None,
    };

    private static string ArraySuffix(ArrayTypeSymbol type) => Mangler.SymbolSafe(type.Name);

    private static string ArrayTypeInfoName(ArrayTypeSymbol type) => "_SLti_array_" + ArraySuffix(type);
    private static string ArrayDestroyName(ArrayTypeSymbol type) => "_SLdestroy_array_" + ArraySuffix(type);

    /// <summary>Total interfaces in the program; the width of every dispatch table.</summary>
}
