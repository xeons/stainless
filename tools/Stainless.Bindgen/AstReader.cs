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
using System.Numerics;
using System.Text.Json;

namespace Stainless.Bindgen;

/// <summary>
/// Reads clang's <c>-ast-dump=json</c> into declarations.
///
/// The dump writes a location's file and line only when they differ from
/// the last location it wrote, whichever node that belonged to, so the walk
/// goes through every location in the order they were written and carries
/// the last file and line along. A location's <c>includedFrom</c> is about
/// the include chain and is not a location.
/// </summary>
public sealed class AstReader
{
    private string _file = "";
    private int _line;
    private readonly Translation _translation = new();

    /// <summary>Records and enums with no tag, by node id, until a typedef gives one a name.</summary>
    private readonly Dictionary<string, CDecl> _anonymousById = new(StringComparer.Ordinal);

    public static Translation Read(JsonElement root)
    {
        var reader = new AstReader();
        foreach (var node in Inner(root))
            reader.ReadTopLevel(node);
        return reader._translation;
    }

    /// <summary>
    /// Reads a dump file one top-level declaration at a time, so that one
    /// larger than a JSON document can hold -- Accelerate's is -- is read all
    /// the same. clang writes each at four spaces' indent, opening on a line
    /// that is <c>{</c> alone and closing on one that is <c>}</c>, and a JSON
    /// string holds no raw line break, so those lines are where each begins
    /// and ends.
    /// </summary>
    public static Translation ReadFile(string path)
    {
        var reader = new AstReader();
        var options = new JsonDocumentOptions { MaxDepth = 100_000 };
        using var file = new StreamReader(path);
        System.Text.StringBuilder? element = null;

        while (file.ReadLine() is { } line)
        {
            if (element is null)
            {
                if (line == "    {") element = new System.Text.StringBuilder("{\n");
                continue;
            }

            if (line is "    }" or "    },")
            {
                element.Append('}');
                using var document = JsonDocument.Parse(element.ToString(), options);
                reader.ReadTopLevel(document.RootElement);
                element = null;
                continue;
            }

            element.Append(line).Append('\n');
        }

        return reader._translation;
    }

    private static IEnumerable<JsonElement> Inner(JsonElement node) =>
        node.TryGetProperty("inner", out var inner) ? inner.EnumerateArray() : [];

    private static string? Text(JsonElement node, string property) =>
        node.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;

    private static bool Flag(JsonElement node, string property) =>
        node.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.True;

    /// <summary>
    /// Walks every location under <paramref name="element"/> in the order the
    /// dump wrote them, keeping the last file and line.
    /// </summary>
    private void Track(JsonElement element)
    {
        if (element.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in element.EnumerateArray()) Track(item);
            return;
        }

        if (element.ValueKind != JsonValueKind.Object) return;

        if (element.TryGetProperty("offset", out _))
        {
            if (Text(element, "file") is { } file) _file = file;
            if (element.TryGetProperty("line", out var line)) _line = line.GetInt32();
        }

        foreach (var property in element.EnumerateObject())
        {
            if (property.Name is "includedFrom" or "offset" or "file" or "line") continue;
            if (property.Value.ValueKind is JsonValueKind.Object or JsonValueKind.Array)
                Track(property.Value);
        }
    }

    /// <summary>
    /// The file and position a node's own location names, read from its
    /// <c>loc</c>; for a macro expansion, where it was expanded.
    /// </summary>
    private (string File, string Where) Locate(JsonElement node)
    {
        if (!node.TryGetProperty("loc", out var loc)) return (_file, "");

        Track(loc);
        var bare = loc.TryGetProperty("expansionLoc", out var expansion) ? expansion : loc;
        int column = bare.TryGetProperty("col", out var col) ? col.GetInt32() : 0;
        return (_file, $"{_file}:{_line}:{column}");
    }

    /// <summary>Everything after a node's location: its range and children, for the tracking alone.</summary>
    private void TrackRest(JsonElement node)
    {
        foreach (var property in node.EnumerateObject())
            if (property.Name != "loc" && property.Value.ValueKind is JsonValueKind.Object or JsonValueKind.Array)
                Track(property.Value);
    }

    private void ReadTopLevel(JsonElement node)
    {
        string kind = Text(node, "kind") ?? "";
        var (file, where) = Locate(node);

        CDecl? declared = kind switch
        {
            "FunctionDecl" => ReadFunction(node, file),
            "RecordDecl" => ReadRecord(node, file, where),
            "EnumDecl" => ReadEnum(node, file, where),
            "TypedefDecl" => ReadTypedef(node, file),
            "VarDecl" => ReadVariable(node, file),
            _ => null,
        };

        // A record is read with its children, which moves the tracking
        // along itself; everything else is tracked here.
        if (kind != "RecordDecl") TrackRest(node);

        if (declared is null) return;
        declared = declared with { Availability = ReadAvailability(node) };

        if (declared is CTypedefDecl typedef && NameAnonymous(node, typedef) is { } named)
        {
            Register(named);
            declared = typedef with
            {
                Type = new CTag(named is CRecordDecl record ? record.Kind : CTagKind.Enum, typedef.Name),
            };
        }

        Remember(node, declared);
        Register(declared);
    }

    /// <summary>Keeps a record or enum with no tag by its node id, for a typedef to name.</summary>
    private void Remember(JsonElement node, CDecl declared)
    {
        if (declared is CRecordDecl { AnonymousAt: not null } or CEnumDecl { AnonymousAt: not null } &&
            Text(node, "id") is { } id)
            _anonymousById[id] = declared;
    }

    /// <summary>
    /// <c>typedef struct { ... } CFRange;</c>: the record with no tag, which
    /// clang prints as <c>struct CFRange</c>, under the typedef's name.
    /// </summary>
    private CDecl? NameAnonymous(JsonElement node, CTypedefDecl typedef)
    {
        if (DeclId(node) is not { } id || !_anonymousById.Remove(id, out var anonymous)) return null;

        int at = _translation.Declarations.FindIndex(d => ReferenceEquals(d, anonymous));
        if (at >= 0) _translation.Declarations.RemoveAt(at);
        if (anonymous is CRecordDecl { AnonymousAt: { } place }) _translation.Anonymous.Remove(place);
        if (anonymous is CEnumDecl { AnonymousAt: { } enumPlace }) _translation.Anonymous.Remove(enumPlace);

        return anonymous switch
        {
            CRecordDecl record => record with { Name = typedef.Name, AnonymousAt = null, File = typedef.File, IsTypedefName = true },
            CEnumDecl enumeration => enumeration with { Name = typedef.Name, AnonymousAt = null, File = typedef.File },
            _ => null,
        };
    }

    /// <summary>The id of the first declaration a typedef's type tree points at.</summary>
    private static string? DeclId(JsonElement node)
    {
        foreach (var child in Inner(node))
        {
            if (child.TryGetProperty("decl", out var decl) && Text(decl, "id") is { } id) return id;
            if (Text(child, "kind") is "PointerType" or "BlockPointerType" or "FunctionProtoType") return null;
            if (DeclId(child) is { } nested) return nested;
        }

        return null;
    }

    private void Register(CDecl declared)
    {
        _translation.Declarations.Add(declared);
        switch (declared)
        {
            case CTypedefDecl typedef:
                _translation.Typedefs.TryAdd(typedef.Name, typedef);
                break;

            case CRecordDecl record when record.AnonymousAt is { } at:
                _translation.Anonymous[at] = record;
                break;

            case CRecordDecl record:
                var key = (record.Kind, record.Name);
                if (!_translation.Records.TryGetValue(key, out var existing) || (!existing.IsComplete && record.IsComplete))
                    _translation.Records[key] = record;
                break;

            case CEnumDecl { AnonymousAt: { } at } anonymous:
                _translation.Anonymous[at] = anonymous;
                break;

            case CEnumDecl named:
                if (!_translation.Enums.TryGetValue(named.Name, out var known) || known.Members.Count == 0)
                    _translation.Enums[named.Name] = named;
                break;
        }
    }

    private static Availability ReadAvailability(JsonElement node)
    {
        string? introduced = null, deprecated = null;
        bool unavailable = false;

        foreach (var child in Inner(node))
        {
            switch (Text(child, "kind"))
            {
                case "AvailabilityAttr" when Text(child, "platform") is "macos" or "macosx":
                    introduced = Text(child, "introduced") ?? introduced;
                    deprecated = Text(child, "deprecated") ?? Text(child, "obsoleted") ?? deprecated;
                    unavailable |= Flag(child, "unavailable") || Text(child, "obsoleted") is not null;
                    break;

                case "UnavailableAttr":
                    unavailable = true;
                    break;
            }
        }

        return new Availability(introduced, deprecated, unavailable);
    }

    /// <summary>
    /// A node's type as written; through <c>typeof</c>, which says only what
    /// it was computed from, the type it comes to.
    /// </summary>
    private static CType TypeOf(JsonElement node)
    {
        if (!node.TryGetProperty("type", out var type) || Text(type, "qualType") is not { } spelling)
            return new CUnsupported("no type");

        if (spelling.Contains("typeof", StringComparison.Ordinal) && Text(type, "desugaredQualType") is { } desugared)
            spelling = desugared;

        return ParseOrUnsupported(spelling);
    }

    private static CType ParseOrUnsupported(string spelling)
    {
        try
        {
            return CTypeParser.Parse(spelling);
        }
        catch (FormatException error)
        {
            return new CUnsupported($"'{spelling}' could not be read: {error.Message}");
        }
    }

    private static CFunctionDecl? ReadFunction(JsonElement node, string file)
    {
        if (Text(node, "name") is not { } name) return null;

        var type = TypeOf(node);
        var parameters = Inner(node)
            .Where(c => Text(c, "kind") == "ParmVarDecl")
            .Select(c => new CParameter(Text(c, "name"), TypeOf(c)))
            .ToList();

        var result = type is CFunction function ? function.Result : type;

        return new CFunctionDecl(name, file, result, parameters, Flag(node, "variadic"))
        {
            IsInline = Text(node, "storageClass") == "static" || Flag(node, "inline"),
            AsmLabel = Inner(node).Where(c => Text(c, "kind") == "AsmLabelAttr")
                .Select(c => Text(c, "label") ?? "?").FirstOrDefault(),
        };
    }

    private CRecordDecl? ReadRecord(JsonElement node, string file, string where)
    {
        string? name = Text(node, "name");
        var kind = Text(node, "tagUsed") == "union" ? CTagKind.Union : CTagKind.Struct;

        var record = new CRecordDecl(name ?? "", file, kind)
        {
            IsComplete = Flag(node, "completeDefinition"),
            AnonymousAt = name is null ? where : null,
        };

        // The record's range is written before its children.
        if (node.TryGetProperty("range", out var range)) Track(range);

        bool packed = false, pragmaPack = false;
        int? alignment = null;
        CRecordDecl? pendingAnonymous = null;

        foreach (var child in Inner(node))
        {
            string childKind = Text(child, "kind") ?? "";
            switch (childKind)
            {
                case "PackedAttr":
                    packed = true;
                    Track(child);
                    break;

                case "MaxFieldAlignmentAttr":
                    pragmaPack = true;
                    Track(child);
                    break;

                case "AlignedAttr":
                    alignment = AlignmentOf(child);
                    Track(child);
                    break;

                case "RecordDecl":
                {
                    var (childFile, childWhere) = Locate(child);
                    var nested = ReadRecord(child, childFile, childWhere);

                    // A nested record with no name and no field naming it is
                    // a member the enclosing record takes as its own.
                    if (nested is { AnonymousAt: not null })
                        pendingAnonymous = nested;
                    else if (nested is not null)
                        Register(nested);
                    break;
                }

                case "FieldDecl":
                {
                    Locate(child);
                    TrackRest(child);
                    var type = TypeOf(child);
                    string? fieldName = Text(child, "name");
                    int? width = Flag(child, "isBitfield") && FirstValue(child) is { } bits ? (int)bits : null;

                    var field = new CField(fieldName, type, width)
                    {
                        Alignment = Inner(child).Where(a => Text(a, "kind") == "AlignedAttr")
                            .Select(a => (int?)AlignmentOf(a)).Max(),
                    };
                    // A member with no name is the record declared just before
                    // it, whatever its type is spelled as; a named one of an
                    // unnamed type is matched on where that type was declared.
                    if (pendingAnonymous is { AnonymousAt: { } at } &&
                        (fieldName is null ||
                         (Innermost(type) is CAnonymous anonymous &&
                          anonymous.Where.Contains(at[..at.LastIndexOf(':')], StringComparison.Ordinal))))
                    {
                        _translation.Anonymous[at] = pendingAnonymous;
                        if (fieldName is null) field = field with { Inline = pendingAnonymous };
                        pendingAnonymous = null;
                    }

                    record.Fields.Add(field);
                    break;
                }

                default:
                    Track(child);
                    break;
            }
        }

        return record with { IsPacked = packed, Alignment = alignment, HasPragmaPack = pragmaPack };
    }

    private CEnumDecl ReadEnum(JsonElement node, string file, string where)
    {
        string? name = Text(node, "name");
        CType? underlying = node.TryGetProperty("fixedUnderlyingType", out var fixedType) &&
                            Text(fixedType, "qualType") is { } spelling
            ? ParseOrUnsupported(spelling)
            : null;

        var declared = new CEnumDecl(name ?? "", file)
        {
            Underlying = underlying,
            IsFlags = Inner(node).Any(c => Text(c, "kind") == "FlagEnumAttr"),
            AnonymousAt = name is null ? where : null,
        };

        BigInteger next = 0;
        foreach (var member in Inner(node).Where(c => Text(c, "kind") == "EnumConstantDecl"))
        {
            var written = FirstValue(member);
            var value = written ?? next;
            next = value + 1;

            // An enumerator marked unavailable on macOS does not exist here.
            if (ReadAvailability(member).Unavailable) continue;
            declared.Members.Add(new CEnumMember(Text(member, "name") ?? "", value, written is not null));
        }

        return declared;
    }

    private static CTypedefDecl? ReadTypedef(JsonElement node, string file) =>
        Text(node, "name") is { } name ? new CTypedefDecl(name, file, TypeOf(node)) : null;

    private static CVariableDecl? ReadVariable(JsonElement node, string file) =>
        Text(node, "name") is { } name &&
        (Text(node, "storageClass") == "extern" || name.StartsWith(Macros.TypePrefix, StringComparison.Ordinal))
            ? new CVariableDecl(name, file, TypeOf(node))
            : null;

    /// <summary>
    /// What an <c>aligned</c> attribute asks for: its argument, or with none
    /// the most any type is aligned to, which is sixteen on both targets.
    /// </summary>
    private static int AlignmentOf(JsonElement attribute) =>
        FirstValue(attribute) is { } value ? (int)value : 16;

    /// <summary>The type an array or pointer is of, all the way in.</summary>
    private static CType Innermost(CType type) => type switch
    {
        CArray array => Innermost(array.Element),
        CPointer pointer => Innermost(pointer.Pointee),
        _ => type,
    };

    /// <summary>The first constant clang folded under <paramref name="node"/>: an enumerator's value, a width.</summary>
    private static BigInteger? FirstValue(JsonElement node)
    {
        foreach (var child in Inner(node))
        {
            if (Text(child, "kind") == "ConstantExpr" && Text(child, "value") is { } text &&
                BigInteger.TryParse(text, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var value))
                return value;

            if (FirstValue(child) is { } nested) return nested;
        }

        return null;
    }
}
