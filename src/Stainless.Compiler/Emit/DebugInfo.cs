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
using Stainless.Binding;
using Stainless.Source;

namespace Stainless.Emit;

/// <summary>
/// The debug metadata graph: files, types, functions and source locations, in
/// the form LLVM writes them into DWARF or CodeView.
///
/// It is a graph of numbered nodes rather than a tree, and the numbers are the
/// whole of the linkage between it and the instruction stream: the emitter
/// appends <c>!dbg !42</c> to an instruction, and node 42 says which line that
/// was. So this class hands out ids and remembers what each one said, and the
/// emitter never has to know what a DISubprogram is.
///
/// A node may refer to one that does not exist yet, which is what makes a class
/// holding a reference to itself describable: the id is reserved before the
/// members are built, so the cycle closes on a number rather than on a value.
/// </summary>
public sealed class DebugInfo
{
    /// <summary>Node text by id; null until a reserved node is filled in.</summary>
    private readonly List<string?> _nodes = [];

    private readonly Dictionary<SourceText, int> _files = [];
    private readonly Dictionary<TypeSymbol, int> _types = [];
    private readonly Dictionary<FunctionSymbol, int> _subprograms = [];
    private readonly Dictionary<(int Line, int Column, int Scope), int> _locations = [];
    private readonly Dictionary<string, int> _basicTypes = new(StringComparer.Ordinal);

    private readonly int _compileUnit;
    private readonly bool _codeView;
    private readonly string _producer;

    /// <summary>
    /// <paramref name="mainFile"/> is the file the compile unit is named after.
    /// DWARF wants one even though a Stainless program has no single root file,
    /// so the first source given on the command line stands for the program.
    /// </summary>
    public DebugInfo(SourceText mainFile, string producer, bool codeView)
    {
        _producer = producer;
        _codeView = codeView;

        _compileUnit = Reserve();
        int file = File(mainFile);

        // splitDebugInlining and nameTableKind are what clang emits for a plain
        // -g build; leaving them off changes the size of the output and nothing
        // a debugger can see.
        Fill(_compileUnit,
            $"distinct !DICompileUnit(language: DW_LANG_C_plus_plus, file: !{file}, " +
            $"producer: {Quote(producer)}, isOptimized: false, runtimeVersion: 0, " +
            "emissionKind: FullDebug, splitDebugInlining: false, nameTableKind: None)");
    }

    // ============================================================ nodes

    private int Reserve()
    {
        _nodes.Add(null);
        return _nodes.Count - 1;
    }

    private void Fill(int id, string text) => _nodes[id] = text;

    private int Add(string text)
    {
        _nodes.Add(text);
        return _nodes.Count - 1;
    }

    /// <summary>A <c>!{...}</c> tuple, which is how DWARF spells a list.</summary>
    private int Tuple(IEnumerable<int> members) =>
        Add("!{" + string.Join(", ", members.Select(m => "!" + m)) + "}");

    // ============================================================ files

    public int File(SourceText source)
    {
        if (_files.TryGetValue(source, out int existing)) return existing;

        string full = source.Path;
        string directory, name;

        // A stdlib source has a synthetic path unless the driver wrote it out,
        // so splitting on the real path separator would produce nothing useful.
        try
        {
            full = Path.GetFullPath(source.Path);
            directory = Path.GetDirectoryName(full) ?? ".";
            name = Path.GetFileName(full);
        }
        catch (ArgumentException)
        {
            directory = ".";
            name = source.Path;
        }

        int id = Add($"!DIFile(filename: {Quote(name)}, directory: {Quote(directory)})");
        _files[source] = id;
        return id;
    }

    // ============================================================ locations

    /// <summary>
    /// The node for one point in the source, within one function.
    ///
    /// Locations repeat constantly — every instruction a statement expands to
    /// shares one — so they are pooled. It takes a large fraction off the size
    /// of the metadata for no work at all.
    /// </summary>
    public int Location(SourceSpan span, int scope)
    {
        var (line, column) = span.File.GetLineColumn(span.Start);
        var key = (line, column, scope);

        if (_locations.TryGetValue(key, out int existing)) return existing;

        int id = Add($"!DILocation(line: {line}, column: {column}, scope: !{scope})");
        _locations[key] = id;
        return id;
    }

    // ============================================================ functions

    /// <summary>
    /// The node describing a function, or null for one this program does not
    /// define. A declaration has no body to step through and no line to sit on.
    /// </summary>
    public int? Subprogram(FunctionSymbol symbol, string linkageName)
    {
        if (_subprograms.TryGetValue(symbol, out int existing)) return existing;
        if (!symbol.HasBody || symbol.IsExternal) return null;

        int id = Reserve();
        _subprograms[symbol] = id;

        int file = File(symbol.Span.File);
        var (line, _) = symbol.Span.File.GetLineColumn(symbol.Span.Start);
        int type = SubroutineType(symbol);

        // The scope is the file rather than the containing type. Naming a method
        // 'Circle.Area' in the node says the same thing to a reader, and putting
        // a subprogram inside a composite type obliges the composite to list it
        // back — a second edge to maintain for a debugger frame that already
        // reads correctly.
        string name = symbol.ContainingType is null
            ? symbol.Name
            : symbol.ContainingType.Name + "." + symbol.Name;

        Fill(id,
            $"distinct !DISubprogram(name: {Quote(name)}, linkageName: {Quote(linkageName)}, " +
            $"scope: !{file}, file: !{file}, line: {line}, type: !{type}, scopeLine: {line}, " +
            $"flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !{_compileUnit})");

        return id;
    }

    private int SubroutineType(FunctionSymbol symbol)
    {
        // The first entry is the return type, and a null one means void — DWARF
        // has no node for "no type", so the absence is the encoding.
        var parts = new List<string>
        {
            symbol.ReturnType.IsVoid() ? "null" : "!" + Type(symbol.ReturnType),
        };

        parts.AddRange(symbol.Parameters.Select(p => "!" + Type(p.Type)));

        int types = Add("!{" + string.Join(", ", parts) + "}");
        return Add($"!DISubroutineType(types: !{types})");
    }

    // ============================================================ variables

    public int LocalVariable(string name, TypeSymbol type, SourceSpan span, int scope) =>
        Variable(name, type, span, scope, argument: 0);

    /// <summary>
    /// A parameter, which differs from a local only by carrying its position.
    /// The number is one-based, and is what lets a debugger print a frame's
    /// arguments in the order they were written rather than in slot order.
    /// </summary>
    public int Parameter(string name, TypeSymbol type, SourceSpan span, int scope, int index) =>
        Variable(name, type, span, scope, index + 1);

    private int Variable(string name, TypeSymbol type, SourceSpan span, int scope, int argument)
    {
        int file = File(span.File);
        var (line, _) = span.File.GetLineColumn(span.Start);
        string position = argument > 0 ? $"arg: {argument}, " : "";

        return Add($"!DILocalVariable(name: {Quote(name)}, {position}scope: !{scope}, " +
                   $"file: !{file}, line: {line}, type: !{Type(type)})");
    }

    // ============================================================ types

    /// <summary>
    /// The node describing a type, built once and reused.
    ///
    /// The id is reserved before the members are built, so a type that reaches
    /// itself — a class holding a reference to its own kind — terminates on the
    /// second visit instead of recurring forever.
    /// </summary>
    public int Type(TypeSymbol type)
    {
        if (_types.TryGetValue(type, out int existing)) return existing;

        switch (type)
        {
            case PrimitiveTypeSymbol primitive:
                return _types[type] = BasicType(primitive);

            case PointerTypeSymbol pointer:
            {
                int id = Reserve();
                _types[type] = id;
                Fill(id, pointer.Element.IsVoid()
                    // DWARF spells void* as a pointer with no base type.
                    ? "!DIDerivedType(tag: DW_TAG_pointer_type, size: 64)"
                    : $"!DIDerivedType(tag: DW_TAG_pointer_type, baseType: !{Type(pointer.Element)}, " +
                      "size: 64)");
                return id;
            }

            // An optional and a weak reference are the same machine value as the
            // reference they wrap; the difference is in what the compiler will
            // let you do with them, which DWARF has no way to say.
            case OptionalTypeSymbol optional:
                return _types[type] = Type(optional.Element);

            case WeakTypeSymbol weak:
                return _types[type] = Type(weak.Element);

            case ArrayTypeSymbol array:
            {
                int id = Reserve();
                _types[type] = id;
                Fill(id, $"!DIDerivedType(tag: DW_TAG_pointer_type, baseType: !{ArrayBody(array)}, " +
                         "size: 64)");
                return id;
            }

            case EnumTypeSymbol enumType:
                return _types[type] = EnumerationType(enumType);

            case VariantTypeSymbol variant:
                return _types[type] = VariantType(variant);

            case StructTypeSymbol structType:
                return _types[type] = Composite(structType, structType.Size, headerBytes: 0);

            case DelegateTypeSymbol delegateType:
                return _types[type] = DelegateType(delegateType);

            // A class or interface reference is a pointer to the object; the
            // object itself is what carries the fields.
            case ClassTypeSymbol classType:
            {
                int id = Reserve();
                _types[type] = id;
                int body = Composite(classType, classType.InstanceSize, ClassTypeSymbol.HeaderSize);
                Fill(id, $"!DIDerivedType(tag: DW_TAG_pointer_type, baseType: !{body}, size: 64)");
                return id;
            }

            case InterfaceTypeSymbol interfaceType:
            {
                int id = Reserve();
                _types[type] = id;
                int body = Add(
                    $"!DICompositeType(tag: DW_TAG_structure_type, name: " +
                    $"{Quote(interfaceType.QualifiedName)}, size: 0, flags: DIFlagFwdDecl)");
                Fill(id, $"!DIDerivedType(tag: DW_TAG_pointer_type, baseType: !{body}, size: 64)");
                return id;
            }

            default:
                // An error type, or something added later that has no description
                // yet. A pointer-shaped unknown is wrong in less visible ways
                // than a missing node, which would not verify at all.
                return _types[type] = Add("!DIDerivedType(tag: DW_TAG_pointer_type, size: 64)");
        }
    }

    private int BasicType(PrimitiveTypeSymbol primitive)
    {
        if (primitive.IsVoid())
            return Add("!DIDerivedType(tag: DW_TAG_pointer_type, size: 64)");

        if (_basicTypes.TryGetValue(primitive.Name, out int existing)) return existing;

        string encoding = primitive.Kind switch
        {
            PrimitiveKind.Bool => "DW_ATE_boolean",

            // Stainless spells the one-byte integer 'byte' and the character
            // 'char', so char is the one that gets the character encoding.
            PrimitiveKind.Char => "DW_ATE_unsigned_char",

            _ when primitive.IsFloat => "DW_ATE_float",
            _ when primitive.IsSigned => "DW_ATE_signed",
            _ => "DW_ATE_unsigned",
        };

        int id = Add($"!DIBasicType(name: {Quote(primitive.Name)}, size: {primitive.Size * 8}, " +
                     $"encoding: {encoding})");
        _basicTypes[primitive.Name] = id;
        return id;
    }

    private int EnumerationType(EnumTypeSymbol enumType)
    {
        int id = Reserve();
        _types[enumType] = id;

        var members = enumType.Members
            .Select(m => Add($"!DIEnumerator(name: {Quote(m.Name)}, value: {EnumValue(enumType, m)})"))
            .ToList();

        Fill(id,
            $"!DICompositeType(tag: DW_TAG_enumeration_type, name: {Quote(enumType.QualifiedName)}, " +
            $"{Position(enumType.Span)}baseType: !{Type(enumType.UnderlyingType)}, " +
            $"size: {enumType.Size * 8}, align: {enumType.Alignment * 8}, " +
            $"elements: !{Tuple(members)})");

        return id;
    }

    /// <summary>The member's constant, re-signed so a negative one prints as one.</summary>
    private static string EnumValue(EnumTypeSymbol enumType, EnumMemberSymbol member) =>
        enumType.UnderlyingType.IsSigned
            ? SignExtend(member.Value, enumType.UnderlyingType.Bits)
                .ToString(System.Globalization.CultureInfo.InvariantCulture)
            : member.Value.ToString(System.Globalization.CultureInfo.InvariantCulture);

    private static long SignExtend(ulong value, int bits) =>
        bits >= 64 ? (long)value : (long)(value << (64 - bits)) >> (64 - bits);

    /// <summary>
    /// A struct or class body: the fields, at the offsets the layout gave them.
    ///
    /// <paramref name="headerBytes"/> is what sits in front of the fields — zero
    /// for a struct, the object header for a class — because a field's recorded
    /// offset is measured from the start of the fields area rather than from the
    /// start of the allocation, and DWARF wants the latter.
    /// </summary>
    private int Composite(NamedTypeSymbol type, int size, int headerBytes)
    {
        int id = Reserve();
        _types[type] = id;

        string where = Position(type.Span);
        var members = new List<int>();

        if (headerBytes > 0)
        {
            // The header is not a field and has no name in the source, but a
            // debugger that does not know it is there computes every offset
            // wrong. Naming it keeps the picture honest.
            members.Add(Add(
                $"!DIDerivedType(tag: DW_TAG_member, name: \"__header\", {where}" +
                $"baseType: !{Type(PrimitiveTypeSymbol.Byte)}, " +
                $"size: {headerBytes * 8}, offset: 0)"));
        }

        // A property's backing field carries the property's own name, which is
        // the name that reads it, so it needs no special treatment here.
        foreach (var field in type.Fields)
        {
            members.Add(Add(
                $"!DIDerivedType(tag: DW_TAG_member, name: {Quote(field.Name)}, {where}" +
                $"baseType: !{Type(field.Type)}, size: {field.Type.Size * 8}, " +
                $"offset: {(headerBytes + field.Offset) * 8})"));
        }

        Fill(id,
            $"!DICompositeType(tag: DW_TAG_structure_type, name: {Quote(type.QualifiedName)}, " +
            $"{where}size: {size * 8}, align: {type.Alignment * 8}, " +
            $"elements: !{Tuple(members)})");

        return id;
    }

    /// <summary>
    /// A variant: the tag, then every case's payload described at the one offset
    /// they share.
    ///
    /// DWARF 5 has a variant part for exactly this, and LLVM will emit one, but
    /// what reads it is thin on the ground and there is none at all in CodeView.
    /// Overlapping members are understood everywhere: a debugger shows all the
    /// cases, the tag says which of them is real, and nothing has to be taught
    /// a new shape to get that far.
    /// </summary>
    private int VariantType(VariantTypeSymbol variant)
    {
        int id = Reserve();
        _types[variant] = id;

        string where = Position(variant.Span);
        var members = new List<int>
        {
            Add($"!DIDerivedType(tag: DW_TAG_member, name: \"tag\", {where}" +
                $"baseType: !{Type(PrimitiveTypeSymbol.Byte)}, size: 8, offset: 0)"),
        };

        if (variant.PayloadField is { } payload)
        {
            int offset = payload.Offset * 8;

            foreach (var variantCase in variant.Cases)
            {
                if (variantCase.Payload is not { } body) continue;

                members.Add(Add(
                    $"!DIDerivedType(tag: DW_TAG_member, name: {Quote(variantCase.Name)}, " +
                    $"{Position(variantCase.Span)}baseType: !{Type(body)}, " +
                    $"size: {body.Size * 8}, offset: {offset})"));
            }
        }

        Fill(id,
            $"!DICompositeType(tag: DW_TAG_structure_type, name: {Quote(variant.QualifiedName)}, " +
            $"{where}size: {variant.Size * 8}, align: {variant.Alignment * 8}, " +
            $"elements: !{Tuple(members)})");

        return id;
    }

    /// <summary>
    /// What a <c>T[]</c> points at: the object header, then the length.
    ///
    /// The elements themselves live inline after it and are deliberately not
    /// described. DWARF can only express an array whose bound it knows, and this
    /// one's is the field beside it — so a debugger is told where the length is
    /// and left to read the elements from the address.
    /// </summary>
    private int ArrayBody(ArrayTypeSymbol array)
    {
        int length = Add(
            "!DIDerivedType(tag: DW_TAG_member, name: \"length\", " +
            $"baseType: !{Type(PrimitiveTypeSymbol.NUInt)}, size: 64, offset: 192)");

        int header = Add(
            "!DIDerivedType(tag: DW_TAG_member, name: \"__header\", " +
            $"baseType: !{Type(PrimitiveTypeSymbol.Byte)}, size: 192, offset: 0)");

        return Add(
            $"!DICompositeType(tag: DW_TAG_structure_type, name: {Quote(array.Name)}, " +
            $"size: {ArrayTypeSymbol.HeaderSize * 8}, align: 64, " +
            $"elements: !{Tuple([header, length])})");
    }

    private int DelegateType(DelegateTypeSymbol delegateType)
    {
        int id = Reserve();
        _types[delegateType] = id;

        var parts = new List<string>
        {
            delegateType.ReturnType.IsVoid() ? "null" : "!" + Type(delegateType.ReturnType),
        };
        parts.AddRange(delegateType.Signature.Select(p => "!" + Type(p.Type)));

        int types = Add("!{" + string.Join(", ", parts) + "}");
        int signature = Add($"!DISubroutineType(types: !{types})");

        Fill(id, $"!DIDerivedType(tag: DW_TAG_pointer_type, baseType: !{signature}, size: 64)");
        return id;
    }

    // ============================================================ rendering

    /// <summary>
    /// The whole graph, plus the named metadata that anchors it. Emitted last,
    /// because a node is created the first time something refers to it.
    /// </summary>
    public string Render()
    {
        var text = new StringBuilder();

        var flags = new List<int>
        {
            Add("!{i32 2, !\"Debug Info Version\", i32 3}"),
        };

        // Windows debuggers read CodeView, and clang emits it only when the
        // module asks; everywhere else the format is DWARF.
        flags.Add(_codeView
            ? Add("!{i32 2, !\"CodeView\", i32 1}")
            : Add("!{i32 7, !\"Dwarf Version\", i32 5}"));

        int ident = Add($"!{{{MdString(_producer)}}}");

        text.AppendLine($"!llvm.dbg.cu = !{{!{_compileUnit}}}");
        text.AppendLine($"!llvm.module.flags = !{{{string.Join(", ", flags.Select(f => "!" + f))}}}");
        text.AppendLine($"!llvm.ident = !{{!{ident}}}");
        text.AppendLine();

        for (int i = 0; i < _nodes.Count; i++)
            text.AppendLine($"!{i} = {_nodes[i] ?? "!{}"}");

        return text.ToString();
    }

    /// <summary>
    /// The <c>file:</c> and <c>line:</c> a node carries, or nothing at all.
    ///
    /// A built-in such as <c>String</c> and a type read back from a referenced
    /// library both have no source here to point at. Both fields are optional in
    /// DWARF, so the honest answer is to leave them out rather than to invent a
    /// file the debugger would then fail to open.
    /// </summary>
    private string Position(SourceSpan? span)
    {
        if (span is not { } at) return "";

        var (line, _) = at.File.GetLineColumn(at.Start);
        return $"file: !{File(at.File)}, line: {line}, ";
    }

    /// <summary>
    /// A string as LLVM's metadata syntax wants it.
    ///
    /// Only <c>\\</c> and hex escapes are defined there, and a Windows path is
    /// full of backslashes, so anything outside plain printable ASCII goes out
    /// as the hex of its UTF-8 bytes rather than as itself.
    /// </summary>
    private static string Quote(string value)
    {
        var text = new StringBuilder("\"");

        foreach (byte b in Encoding.UTF8.GetBytes(value))
        {
            if (b is >= 0x20 and < 0x7F && b != (byte)'"' && b != (byte)'\\')
                text.Append((char)b);
            else
                text.Append('\\').Append(b.ToString("X2"));
        }

        return text.Append('"').ToString();
    }

    /// <summary>The same string as a metadata node, which is spelled with a bang.</summary>
    private static string MdString(string value) => "!" + Quote(value);
}
