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
    /// <summary>
    /// Writes the base pointer of every class derived from a referenced one,
    /// before anything can ask what an object is.
    ///
    /// Only Windows needs it, and only for this one field. An imported datum's
    /// address lives in the import address table and is not known until the
    /// loader has filled that in, so it cannot be written into a constant --
    /// which is what a TypeInfo otherwise is. A store at startup costs one
    /// instruction per derived class, once.
    ///
    /// It runs from <c>llvm.global_ctors</c>, so it is done before <c>main</c>
    /// in a program and on load in a library -- and so before any static
    /// initializer, which is the earliest anything could hold one of these
    /// objects and ask <c>sl_is_instance</c> to walk its chain.
    /// </summary>
    private void PatchBasesAtStartup(List<ClassTypeSymbol> patched)
    {
        if (patched.Count == 0) return;

        const string name = "_SLbind_bases";

        _module.AppendLine();
        _module.AppendLine($"define internal void @{name}() {{");
        _module.AppendLine("entry:");

        int slot = 0;
        foreach (var classType in patched)
        {
            _module.AppendLine(
                $"  %{slot} = getelementptr inbounds i8, ptr @{Mangler.TypeInfoSymbol(classType)}, " +
                $"i64 {RuntimeLayout.TypeInfoBase}");

            _module.AppendLine(
                $"  store ptr @{Mangler.TypeInfoSymbol(classType.BaseClass!)}, ptr %{slot}, align {TargetPlatform.Current.PointerWidth}");

            slot++;
        }

        _module.AppendLine("  ret void");
        _module.AppendLine("}");
        _module.AppendLine();

        // Priority 0, beside the literal binding: neither reads what the other
        // writes, and both have to be done before anything the program wrote.
        _startup.Add((0, name));
    }

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

        // The destroy hook of every referenced class something here derives
        // from. A derived hook ends by calling its base's, which is where an
        // object being taken apart from the outside in crosses back into the
        // library that laid the inside out.
        //
        // Only the ones actually derived from: declaring every referenced
        // class's would name symbols in libraries this program links and
        // otherwise never touches.
        foreach (string destroy in program.Classes
                     .Select(c => c.BaseClass)
                     .OfType<ClassTypeSymbol>()
                     .Select(b => b.ExternalDestroy)
                     .OfType<string>()
                     .Distinct(StringComparer.Ordinal)
                     .Order(StringComparer.Ordinal))
            _module.AppendLine(OperatingSystem.IsWindows()
                ? $"declare dllimport void @{destroy}(ptr)"
                : $"declare void @{destroy}(ptr)");

        var patched = new List<ClassTypeSymbol>();

        foreach (var classType in program.Classes)
        {
            string nameConstant = InternBytes(classType.QualifiedName);
            string tables = classType.Interfaces.Count > 0
                ? "@" + InterfaceTableName(classType)
                : "null";

            // Deriving from a referenced class means naming that library's
            // TypeInfo here. On Windows an imported *datum* has no address until
            // the loader has filled in the import table, so it cannot appear in
            // a constant initializer -- it is written at startup instead, and
            // the table has to be writable to be written to. ELF needs none of
            // this: a relocation into another shared object is ordinary there.
            bool patchBase = OperatingSystem.IsWindows() &&
                             classType.BaseClass is { IsReferenced: true };

            if (patchBase) patched.Add(classType);

            // A library's public classes are allocated through this table by
            // whoever consumes them, so it has to leave the binary.
            string kind = patchBase ? "global" : "constant";
            string visibility = forSharedLibrary && forStainlessConsumers && classType.IsPublic
                ? OperatingSystem.IsWindows() ? $"dllexport {kind}" : kind
                : $"internal {kind}";

            string baseInfo = classType.BaseClass is { } derivedFrom && !patchBase
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
                $"{{ {Word} {classType.InstanceSize}, ptr @{DestroyName(classType)}, " +
                $"ptr {nameConstant}, ptr {tables}, {Metadata(classType, ClassTypeSymbol.HeaderSize)}, " +
                $"ptr {baseInfo}, ptr {vtable}, ptr {comLayout}, " +
                $"{PropertyTable(classType)}, ptr null, {EventTable(classType)} }}");
        }

        PatchBasesAtStartup(patched);

        // One TypeInfo per array type. The element type is not recorded at run
        // time; instead each destroy hook already knows how to walk its elements,
        // which keeps the array header the same 32 bytes whatever it holds.
        foreach (var arrayType in program.Arrays)
        {
            string nameConstant = InternBytes(arrayType.Name);
            _module.AppendLine(
                $"@{ArrayTypeInfoName(arrayType)} = internal constant %SlTypeInfo " +
                $"{{ {Word} {ArrayTypeSymbol.HeaderSize}, ptr @{ArrayDestroyName(arrayType)}, " +
                $"ptr {nameConstant}, ptr null, {Word} 0, ptr null, {Word} 0, ptr null, " +
                $"ptr null, ptr null, ptr null, {Word} 0, ptr null, ptr null, {Word} 0, ptr null }}");
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
                $"{{ {Word} {structType.Size}, ptr null, ptr {nameConstant}, ptr null, " +
                $"{Metadata(structType, 0)}, ptr null, ptr null, ptr null, " +
                $"{PropertyTable(structType)}, ptr null, {Word} 0, ptr null }}");
        }

        if (program.Classes.Count > 0 || program.Arrays.Count > 0) _module.AppendLine();
    }

    /// <summary>
    /// This binary's reflected types, sorted by name, and the startup call
    /// that links them into the runtime's chain.
    ///
    /// Nothing in a compiled binary looks a type up by name -- <c>typeof</c>
    /// resolves to a constant -- so a document that says "App.Button" has
    /// nowhere to go without this. The table is emitted per module and
    /// registered on load, which is what makes it work for a shared library
    /// as well as a program: each contributes its own block and the runtime
    /// walks the chain.
    ///
    /// **Only [Reflect] types are in it.** A program that could name any type
    /// at run time would be a program whose linker could drop nothing.
    /// </summary>
    private void TypeRegistry(BoundProgram program)
    {
        var reflected = new List<(string Name, string Symbol)>();

        foreach (var classType in program.Classes.Where(c => c.IsReflected))
            reflected.Add((classType.QualifiedName, "@" + Mangler.TypeInfoSymbol(classType)));

        foreach (var structType in program.Modules
                     .SelectMany(m => m.Types.Values)
                     .OfType<StructTypeSymbol>()
                     .Where(t => t.IsReflected))
            reflected.Add((structType.QualifiedName, "@" + StructTypeInfoName(structType)));

        if (reflected.Count == 0) return;

        // Sorted by UTF-8 bytes, because the search is `strcmp` and that is
        // what it compares. Ordinal string order would agree for every ASCII
        // name and disagree above the BMP, which is exactly the kind of
        // difference that would be found years later by one person.
        reflected.Sort((left, right) => Utf8Order(left.Name, right.Name));

        string table = "@" + NextMetadataName("typetable");
        _metadata.AppendLine(
            $"{table} = internal constant [{reflected.Count} x ptr] " +
            $"[{string.Join(", ", reflected.Select(t => "ptr " + t.Symbol))}]");

        // `global` rather than `constant`: the runtime writes `next` into it,
        // which is the only mutable word in the whole reflection ABI.
        string block = "@" + NextMetadataName("typeblock");
        _metadata.AppendLine(
            $"{block} = internal global %SlTypeBlock " +
            $"{{ {Word} {reflected.Count}, ptr {table}, ptr null }}");

        const string name = "_SLregister_types";

        _module.AppendLine();
        _module.AppendLine($"define internal void @{name}() {{");
        _module.AppendLine("entry:");
        _module.AppendLine($"  call void @sl_types_register(ptr {block})");
        _module.AppendLine("  ret void");
        _module.AppendLine("}");

        // Priority 1: after the string literals are bound, before anything a
        // program adds later.
        _startup.Add((1, name));
    }

    /// <summary>
    /// Compares two names as their UTF-8 bytes, which is what <c>strcmp</c>
    /// will do to them.
    /// </summary>
    private static int Utf8Order(string left, string right)
    {
        var a = System.Text.Encoding.UTF8.GetBytes(left);
        var b = System.Text.Encoding.UTF8.GetBytes(right);

        int shared = Math.Min(a.Length, b.Length);
        for (int i = 0; i < shared; i++)
            if (a[i] != b[i]) return a[i] < b[i] ? -1 : 1;

        return a.Length.CompareTo(b.Length);
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
        if (!type.IsReflected) return $"{Word} 0, ptr null, {Word} 0, ptr null";

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

                // SL_FIELD_PROPERTY. An automatic property's storage is a
                // field named after the property, so this is the only thing
                // telling a walk over the table that writing it would go
                // straight past the setter.
                int flags = field.IsBackingField ? 1 : 0;

                return $"%SlFieldInfo {{ ptr {InternBytes(field.Name)}, " +
                       $"{Word} {fieldBase + field.Offset}, i32 {(int)KindOf(field.Type)}, " +
                       $"ptr {NestedTypeInfo(field.Type)}, {attributes}, " +
                       $"{ElementColumns(field.Type)}, i32 {flags} }}";
            }).ToList();

            string body = string.Join(", ", rows);
            fields = "@" + NextMetadataName("fields");
            _metadata.AppendLine(
                $"{fields} = internal constant [{reflected.Count} x %SlFieldInfo] [{body}]");
        }

        string typeAttributes = AttributeTable(type.Attributes);

        return $"{Word} {reflected.Count}, ptr {fields}, {typeAttributes}";
    }

    /// <summary>
    /// The property table's count-and-pointer pair, or a zero pair.
    ///
    /// Properties are described separately from fields because setting one is
    /// not writing the other. A serializer filling plain data is right to write
    /// an automatic property's storage directly; a form loader setting a
    /// control's <c>Left</c> is not, because the setter is what re-runs the
    /// layout. So both tables are emitted and the caller chooses.
    ///
    /// **The accessors recorded are this type's own.** A virtual property
    /// overridden further down answers correctly, because each class has its
    /// own table and the most-derived declaration is the one that lands in it;
    /// what does not happen is dispatch. Reaching an object through
    /// <c>typeof(Base)</c> and setting a property the derived class overrode
    /// calls the base's setter, where the language's own <c>.Left = x</c>
    /// would not.
    /// </summary>
    private string PropertyTable(NamedTypeSymbol type)
    {
        if (!type.IsReflected) return $"{Word} 0, ptr null";

        // Base first, so that a derived class's override replaces the
        // declaration it overrides and keeps the position the base gave it.
        var candidates = type is ClassTypeSymbol withBase
            ? withBase.SelfAndBases().Reverse().SelectMany(c => c.Properties)
            : type.Properties;

        var order = new List<string>();
        var newest = new Dictionary<string, PropertySymbol>(StringComparer.Ordinal);

        foreach (var property in candidates)
        {
            // An indexer's accessors take arguments nothing here could supply,
            // and a static property has no instance to pass one.
            if (property.IsIndexer) continue;
            if (property.Getter?.IsStatic == true || property.Setter?.IsStatic == true) continue;
            if (property.Getter is null && property.Setter is null) continue;

            if (!newest.ContainsKey(property.Name)) order.Add(property.Name);
            newest[property.Name] = property;
        }

        if (order.Count == 0) return $"{Word} 0, ptr null";

        // Materialised before anything is appended, for the reason the field
        // rows are: building a row emits its own attribute table.
        var rows = order.Select(name =>
        {
            var property = newest[name];
            string attributes = AttributeTable(property.Attributes);

            // Symbol() supplies the '@' and quotes the name when a mangling
            // needs it, which a C++-linkage accessor does.
            string getter = property.Getter is { } read ? Symbol(read) : "null";
            string setter = property.Setter is { } write ? Symbol(write) : "null";

            // SL_PROPERTY_PUBLIC, so a tool listing what a caller can set --
            // a form designer's grid -- can leave out what a caller cannot.
            int flags = property.IsPublic ? 1 : 0;

            return $"%SlPropertyInfo {{ ptr {InternBytes(property.Name)}, " +
                   $"i32 {(int)KindOf(property.Type)}, ptr {NestedTypeInfo(property.Type)}, " +
                   $"ptr {getter}, ptr {setter}, {attributes}, i32 {flags} }}";
        }).ToList();

        string table = "@" + NextMetadataName("properties");
        _metadata.AppendLine(
            $"{table} = internal constant [{order.Count} x %SlPropertyInfo] " +
            $"[{string.Join(", ", rows)}]");

        return $"{Word} {order.Count}, ptr {table}";
    }

    /// <summary>
    /// What an array field's elements are: their kind, their type when they
    /// have one, and their stride.
    ///
    /// Zeroed for everything else. The stride is what makes a walk over an
    /// array possible without knowing the element type at compile time -- the
    /// address of the data plus this, times the index -- and it is the reason
    /// this is three columns rather than the two a field already had.
    ///
    /// A slice is deliberately not included. It is three words rather than a
    /// reference, so an element of one is not reached the way this describes,
    /// and answering as though it were would be worse than answering nothing.
    /// </summary>
    private string ElementColumns(TypeSymbol type)
    {
        if (type is not ArrayTypeSymbol array) return $"i32 0, ptr null, {Word} 0";

        return $"i32 {(int)KindOf(array.Element)}, " +
               $"ptr {NestedTypeInfo(array.Element)}, " +
               $"{Word} {array.Element.Size}";
    }

    /// <summary>Emits an attribute table and returns its count-and-pointer pair.</summary>
    private string AttributeTable(IReadOnlyList<AppliedAttribute> attributes)
    {
        if (attributes.Count == 0) return $"{Word} 0, ptr null";

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
                    float number =>
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
                     $"{Word} {attribute.Values.Count}, ptr {values} }}");
        }

        string rowBody = string.Join(", ", rows);
        string table = "@" + NextMetadataName("attributes");
        _metadata.AppendLine(
            $"{table} = internal constant [{attributes.Count} x %SlAttribute] [{rowBody}]");

        return $"{Word} {attributes.Count}, ptr {table}";
    }

    /// <summary>
    /// A reflected class's public events, its bases' included, each once: a
    /// name and the delegate it takes. What a form designer lists.
    /// </summary>
    private string EventTable(ClassTypeSymbol type)
    {
        if (!type.IsReflected) return $"{Word} 0, ptr null";

        var seen = new HashSet<string>(StringComparer.Ordinal);
        var rows = new List<string>();
        foreach (var declared in type.SelfAndBases().Reverse().SelectMany(c => c.Events))
        {
            if (!declared.IsPublic || declared.IsStatic || !seen.Add(declared.Name)) continue;
            rows.Add($"%SlEventInfo {{ ptr {InternBytes(declared.Name)}, " +
                     $"ptr {InternBytes(declared.Type.QualifiedName)} }}");
        }
        if (rows.Count == 0) return $"{Word} 0, ptr null";

        string table = "@" + NextMetadataName("events");
        _metadata.AppendLine(
            $"{table} = internal constant [{rows.Count} x %SlEventInfo] [{string.Join(", ", rows)}]");
        return $"{Word} {rows.Count}, ptr {table}";
    }

    private readonly Dictionary<EnumTypeSymbol, string> _enumTypeInfos = [];

    /// <summary>
    /// An enum's TypeInfo, made the first time a reflected property or field
    /// names it: its members' names and values, its attributes -- which is
    /// where `[Flags]` is read from -- and the kind of integer it is.
    /// </summary>
    private string EnumTypeInfo(EnumTypeSymbol type)
    {
        if (_enumTypeInfos.TryGetValue(type, out var known)) return known;
        string info = "@" + NextMetadataName("enum");
        _enumTypeInfos[type] = info;

        int count = type.Members.Count;
        string names = "null";
        string values = "null";
        if (count > 0)
        {
            var nameCells = type.Members.Select(m => $"ptr {InternBytes(m.Name)}").ToList();
            var valueCells = type.Members.Select(m => $"i64 {unchecked((long)m.Value)}").ToList();
            names = "@" + NextMetadataName("enumnames");
            values = "@" + NextMetadataName("enumvalues");
            _metadata.AppendLine(
                $"{names} = internal constant [{count} x ptr] [{string.Join(", ", nameCells)}]");
            _metadata.AppendLine(
                $"{values} = internal constant [{count} x i64] [{string.Join(", ", valueCells)}]");
        }

        string members = "@" + NextMetadataName("enummembers");
        _metadata.AppendLine(
            $"{members} = internal constant %SlEnumInfo {{ {Word} {count}, ptr {names}, " +
            $"ptr {values}, i32 {(int)KindOf(type.UnderlyingType)} }}");

        string attributes = AttributeTable(type.Attributes);
        string name = InternBytes(type.QualifiedName);
        _metadata.AppendLine(
            $"{info} = internal constant %SlTypeInfo {{ {Word} {type.Size}, ptr null, " +
            $"ptr {name}, ptr null, {Word} 0, ptr null, {attributes}, ptr null, ptr null, " +
            $"ptr null, {Word} 0, ptr null, ptr {members}, {Word} 0, ptr null }}");
        return info;
    }

    private readonly StringBuilder _metadata = new();
    private int _nextMetadata;

    private string NextMetadataName(string hint) => $".meta.{hint}.{_nextMetadata++}";

    /// <summary>
    /// The TypeInfo a field's own type points at, when it has one.
    ///
    /// An optional is unwrapped, because <see cref="KindOf"/> unwraps one too:
    /// a `C?` field reports kind Class, and reporting no type beside that
    /// said the field held a class of no type -- which is what stopped a
    /// serializer walking into one.
    /// </summary>
    private string NestedTypeInfo(TypeSymbol type) => type switch
    {
        OptionalTypeSymbol optional => NestedTypeInfo(optional.Element),
        EnumTypeSymbol enumeration => EnumTypeInfo(enumeration),
        StructTypeSymbol { IsReflected: true } structType => TypeInfoOf(structType),
        ClassTypeSymbol { IsIntrinsic: false } classType => TypeInfoOf(classType),

        // An array's own record, which every array type already has -- it is
        // what carries the destroy hook that walks the elements. It was left
        // null here for as long as reflection could only read an array that
        // already existed; `sl_field_new_array` is what needs it, because
        // making one takes the record of the array rather than of its
        // elements. `IsAggregate` still answers false for an array, so nothing
        // that walks fields starts walking into one.
        ArrayTypeSymbol array => "@" + ArrayTypeInfoName(array),

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
        // An enum is its integer: the accessors pass one, and what it means is
        // in the TypeInfo `NestedTypeInfo` points at.
        EnumTypeSymbol enumeration => KindOf(enumeration.UnderlyingType),
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

    /// <summary>
    /// The symbol suffix for an array type, built from the element's
    /// <em>qualified</em> name.
    ///
    /// <c>type.Name</c> is the simple one, so two <c>Point</c> structs in
    /// different modules -- <c>Forms.Drawing.Point</c> and
    /// <c>Win32.User32.Point</c>, say -- gave their arrays one symbol between
    /// them, and the second definition was rejected by LLVM rather than by
    /// anything that could name the source. Qualifying matches what the struct
    /// and destructor names next door already do.
    ///
    /// Both symbols this feeds are <c>internal</c>, so the spelling is private
    /// to one module and no ABI depends on it.
    /// </summary>
    private static string ArraySuffix(ArrayTypeSymbol type) =>
        Mangler.SymbolSafe(QualifiedElementName(type.Element) + "[]");

    private static string QualifiedElementName(TypeSymbol element) => element switch
    {
        NamedTypeSymbol named => named.QualifiedName,
        ArrayTypeSymbol nested => QualifiedElementName(nested.Element) + "[]",
        FixedArrayTypeSymbol inline => QualifiedElementName(inline.Element) + "[N]",
        PointerTypeSymbol pointer => QualifiedElementName(pointer.Element) + "*",
        _ => element.Name,
    };

    private static string ArrayTypeInfoName(ArrayTypeSymbol type) => "_SLti_array_" + ArraySuffix(type);
    private static string ArrayDestroyName(ArrayTypeSymbol type) => "_SLdestroy_array_" + ArraySuffix(type);

    /// <summary>Total interfaces in the program; the width of every dispatch table.</summary>
}
