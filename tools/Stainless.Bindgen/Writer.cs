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

using System.Numerics;
using System.Text;
using System.Text.RegularExpressions;

namespace Stainless.Bindgen;

/// <summary>One declaration as Stainless, with what it needs from other modules.</summary>
public sealed record Emitted(string Key, string Owner, string Header, string Text, ISet<string> Imports)
{
    /// <summary>The types it names, by owner and key, so a later choice of where one lives can follow it.</summary>
    public IReadOnlySet<(string Owner, string Key)> Uses { get; init; } = new HashSet<(string, string)>();

    /// <summary>A struct declared with no body, which a body declared anywhere else supersedes.</summary>
    public bool IsOpaque { get; init; }

    /// <summary>What the layout probe compares it on, as C and as Stainless spell it.</summary>
    public IReadOnlyList<(string C, string Stainless)> Checks { get; init; } = [];

    /// <summary>The framework whose translation wrote it, whose headers its checks are compiled with.</summary>
    public string Source { get; init; } = "";

    /// <summary>The classes and messages it binds, which the runtime probe asks the Objective-C runtime for.</summary>
    public IReadOnlyList<RuntimeCheck> Runtime { get; init; } = [];
}

/// <summary>
/// A class, or a message a class answers, with the macOS it first appeared
/// in when that is later than the oldest the compiler builds for.
/// </summary>
public sealed record RuntimeCheck(string Class, string? Selector, bool IsInstance, string? Introduced);

/// <summary>A declaration that could not be bound, and why.</summary>
public sealed record Skipped(string Owner, string Header, string Name, string Reason);

/// <summary>
/// Turns the declarations one framework owns into Stainless, a declaration
/// at a time. The pieces that cannot be spelled are skipped with their
/// reason, never guessed at.
/// </summary>
public sealed partial class Writer(Translation translation, IReadOnlySet<string> generated, ObjCNames? names = null)
{
    /// <summary>The module everything outside a framework goes in: libc, Mach and MacTypes.h.</summary>
    public const string SystemOwner = "System";

    private static readonly HashSet<string> Keywords = new(StringComparer.Ordinal)
    {
        "module", "import", "as", "using", "virtual", "override", "abstract", "sealed", "protected", "public",
        "private", "internal", "class", "struct", "interface", "com", "objc", "attribute", "enum", "variant",
        "union", "delegate", "extern", "export", "if", "else", "while", "do", "for", "foreach", "in", "switch",
        "case", "default", "parallel", "spawn", "asm", "return", "break", "continue", "goto", "var", "const",
        "ref", "static", "threadsafe", "operator", "try", "readonly", "new", "null", "true", "false", "sizeof",
        "alignof", "offsetof", "nameof", "typeof", "iidof", "this", "base", "is", "weak", "void", "bool",
        "char", "char16", "char32", "sbyte", "short", "int", "long", "nint", "byte", "ushort", "uint", "ulong",
        "nuint", "float", "double", "out",
    };

    /// <summary>C's fixed-width and pointer-width typedefs, which are Stainless's own types.</summary>
    private static readonly Dictionary<string, string> Primitives = new(StringComparer.Ordinal)
    {
        ["int8_t"] = "sbyte", ["uint8_t"] = "byte", ["int16_t"] = "short", ["uint16_t"] = "ushort",
        ["int32_t"] = "int", ["uint32_t"] = "uint", ["int64_t"] = "long", ["uint64_t"] = "ulong",
        ["intptr_t"] = "nint", ["uintptr_t"] = "nuint", ["size_t"] = "nuint", ["ssize_t"] = "nint",
        ["ptrdiff_t"] = "nint", ["u_int8_t"] = "byte", ["u_int16_t"] = "ushort", ["u_int32_t"] = "uint",
        ["u_int64_t"] = "ulong", ["intmax_t"] = "long", ["uintmax_t"] = "ulong",
        ["__int128_t"] = "int128", ["__uint128_t"] = "uint128",
    };

    /// <summary>The declarations of <see cref="SystemOwner"/> something used, which that module is made of.</summary>
    public HashSet<CDecl> SystemNeeded { get; } = [];

    public List<Skipped> Skips { get; } = [];

    /// <summary>
    /// Who owns a header: the framework it is in -- the outermost, for an
    /// umbrella's subframework -- or <see cref="SystemOwner"/> for the rest of
    /// the SDK and clang's own headers, or null for clang's builtins.
    /// </summary>
    public static string? OwnerOf(string file)
    {
        if (file.Length == 0 || file.StartsWith('<')) return null;
        var framework = FrameworkPattern().Match(file);
        return framework.Success ? framework.Groups[1].Value : SystemOwner;
    }

    [GeneratedRegex(@"/System/Library/Frameworks/([^/]+)\.framework/")]
    private static partial Regex FrameworkPattern();

    /// <summary>
    /// The file a declaration goes in: its header's name, prefixed with its
    /// subframework's, or for a header outside every framework its path under
    /// <c>usr/include</c> with the slashes made underscores.
    /// </summary>
    public string HeaderOf(string file)
    {
        string name = Path.GetFileNameWithoutExtension(file);
        if (OwnerOf(file) == SystemOwner)
        {
            int include = file.LastIndexOf("/include/", StringComparison.Ordinal);
            string relative = include >= 0 ? file[(include + "/include/".Length)..] : Path.GetFileName(file);
            return Path.ChangeExtension(relative, null).Replace('/', '_');
        }

        var nested = Regex.Matches(file, @"/([^/]+)\.framework/");
        return nested.Count > 1 ? nested[^1].Groups[1].Value + "_" + name : name;
    }

    public static string ModuleOf(string owner) => "MacOS." + owner;

    // ------------------------------------------------------------ declarations

    /// <summary>The declaration as Stainless, or null when it is skipped or says nothing new.</summary>
    public Emitted? Write(CDecl declaration)
    {
        string owner = OwnerOf(declaration.File) ?? SystemOwner;
        var context = new Context(owner, HeaderOf(declaration.File), declaration.Name);

        if (declaration.Availability.Unavailable)
            return null;

        // Named by a typedef, it is written under that name instead.
        if (declaration is CRecordDecl { AnonymousAt: not null })
            return null;

        if (declaration is CObjCContainer { IsDefinition: false })
            return null;

        try
        {
            string? text = declaration switch
            {
                CFunctionDecl function => WriteFunction(function, context),
                CRecordDecl record => WriteRecord(record, record.Name, context),
                CEnumDecl enumeration => WriteEnum(enumeration, enumeration.Name, context),
                CTypedefDecl typedef => WriteTypedef(typedef, context),
                CVariableDecl variable => WriteVariable(variable, context),
                CMacro macro => WriteMacro(macro, context),
                CObjCContainer container => WriteObjCContainer(container, context),
                _ => null,
            };

            if (text is null) return null;

            var all = new StringBuilder();
            foreach (string synthesized in context.Synthesized) all.Append(synthesized).Append('\n');
            all.Append(Documentation(declaration.Availability)).Append(text);

            return new Emitted(Key(declaration), owner, context.Header, all.ToString(), context.Imports)
            {
                Checks = Checks(declaration, text),
                Runtime = context.Runtime,
                Uses = context.Uses,
                IsOpaque = declaration is CRecordDecl { IsComplete: false } && context.Synthesized.Count == 0,
            };
        }
        catch (Unsupported unsupported)
        {
            Skips.Add(new Skipped(owner, context.Header, declaration.Name, unsupported.Message));
            return null;
        }
    }

    /// <summary>
    /// What the layout probe compares a declaration on, as C and as Stainless
    /// spell it: a struct's size, alignment and each field's offset, an
    /// enumerator's value, a macro's. Bit-fields have no offset, and the
    /// members of an anonymous struct or union inside another are left out.
    /// </summary>
    private List<(string C, string Stainless)> Checks(CDecl declaration, string text)
    {
        var checks = new List<(string, string)>();
        switch (declaration)
        {
            case CRecordDecl { IsComplete: true } record when record.Name.Length > 0 && !text.StartsWith("public struct " + record.Name + ";", StringComparison.Ordinal):
            {
                string c = record.IsTypedefName ? record.Name : $"{(record.Kind == CTagKind.Union ? "union" : "struct")} {record.Name}";
                string mine = Identifier(record.Name);
                checks.Add(($"sizeof({c})", $"sizeof({mine})"));
                checks.Add(($"_Alignof({c})", $"alignof({mine})"));
                foreach (var field in record.Fields.Where(f => f is { Name: not null, BitWidth: null, Inline: null } &&
                                                              f.Type is not CArray { Length: null or 0 }))
                    checks.Add(($"__builtin_offsetof({c}, {field.Name})", $"offsetof({mine}, {Identifier(field.Name!)})"));
                break;
            }

            case CEnumDecl enumeration when enumeration.Members.Count > 0:
            {
                if (enumeration.Name.Length == 0)
                {
                    foreach (var member in enumeration.Members)
                        checks.Add(($"{member.Name}", Identifier(member.Name)));
                    break;
                }

                var names = MemberNames(enumeration.Members.Select(m => m.Name).ToList());
                for (int i = 0; i < names.Count; i++)
                    checks.Add((enumeration.Members[i].Name, $"{Identifier(enumeration.Name)}.{Identifier(names[i])}"));
                break;
            }

            case CMacro { Value: not null } macro when !text.Contains(" float ", StringComparison.Ordinal) &&
                                                        !text.Contains(" double ", StringComparison.Ordinal) &&
                                                        !text.Contains(" ndouble ", StringComparison.Ordinal):
                checks.Add(($"({macro.Name})", Identifier(macro.Name)));
                break;
        }

        return checks;
    }

    public static string Key(CDecl declaration) => declaration switch
    {
        CMacro => "macro " + declaration.Name,
        CFunctionDecl => "function " + declaration.Name,
        CVariableDecl => "variable " + declaration.Name,
        CRecordDecl record => $"{record.Kind} {declaration.Name}",
        // An enum with no name is its constants, known by the first of them.
        CEnumDecl { Name.Length: 0, Members: [var first, ..] } => "constants " + first.Name,
        CEnumDecl => "enum " + declaration.Name,
        CObjCInterface => "class " + declaration.Name,
        CObjCProtocol => "protocol " + declaration.Name,
        CObjCCategory category => $"category {category.Class}({category.Name}) {category.File}",
        _ => "typedef " + declaration.Name,
    };

    private static string Documentation(Availability availability)
    {
        var lines = new StringBuilder();
        if (availability.Introduced is { } introduced && IsAfterDeploymentTarget(introduced))
            lines.Append($"/// macOS {introduced} and later.\n");
        if (availability.Deprecated is { } deprecated)
            lines.Append($"/// Deprecated in macOS {deprecated}.\n");
        return lines.ToString();
    }

    /// <summary>Whether a version is later than macOS 15.0, the oldest the compiler builds for.</summary>
    private static bool IsAfterDeploymentTarget(string version) =>
        Version.TryParse(version.Contains('.') ? version : version + ".0", out var parsed) && parsed > new Version(15, 0);

    private string? WriteFunction(CFunctionDecl function, Context context)
    {
        if (function.IsInline)
            throw new Unsupported("inline in the header, so nothing exports it");
        if (function.AsmLabel is not null)
            throw new Unsupported($"linked as '{function.AsmLabel}', and an extern cannot be renamed");
        if (IsManualCounting(function, context))
            throw new Unsupported("manual reference counting, which ARC does");
        if (function.Parameters.FirstOrDefault(p => p.IsConsumed) is { } consumed)
            throw new Unsupported($"it takes ownership of '{consumed.Name}', which a binding cannot hand over");

        string result = Canonical(function.Result) is CBuiltin { Name: "void" }
            ? "void"
            : Spell(function.Result, context, function.Name + "Result", Placement.Value, function.ResultNullability);
        var parameters = new List<string>();
        var parameterNames = ParameterNames(function.Parameters);
        for (int i = 0; i < function.Parameters.Count; i++)
        {
            var parameter = function.Parameters[i];
            string name = parameterNames[i];
            string type = SpellParameter(parameter.Type, context, function.Name + Capitalized(name), parameter.Nullability);
            parameters.Add($"{type} {name}");
        }

        if (function.Variadic) parameters.Add("...");

        // ARC's rule for a C function is +0; a CF function follows the
        // Create rule unless an attribute says otherwise.
        bool returnsObject = IsManaged(function.Result, context);
        bool retained = returnsObject &&
                        (function.ReturnsRetained ??
                         (IsCFValue(function.Result) && FollowsCreateRule(function.Name)));
        string ownership = retained ? "[ReturnsRetained] " : "";
        return $"{ownership}public extern \"C\" {result} {Identifier(function.Name)}({string.Join(", ", parameters)});\n";
    }

    /// <summary>A Core Foundation type, through any typedef naming one.</summary>
    private bool IsCFValue(CType type) => type switch
    {
        CTypedef named when IsCFTypedef(named.Name) => true,
        CTypedef named when translation.Typedefs.TryGetValue(named.Name, out var typedef) && typedef.Type != type =>
            IsCFValue(typedef.Type),
        _ => false,
    };

    private string? WriteVariable(CVariableDecl variable, Context context)
    {
        // An array's symbol is the array, so one of unknown length is declared
        // as its first element: its address is the array's.
        if (variable.Type is CArray { Length: null } unknown)
            return "/// An array of unknown length; its address is the array's.\n" +
                   $"public extern \"C\" {Spell(unknown.Element, context, variable.Name + "Element")} {Identifier(variable.Name)};\n";
        if (variable.Type is CFunction)
            throw new Unsupported("a function declared as a variable");

        string type = Spell(variable.Type, context, variable.Name + "Type", Placement.Value, variable.Nullability);
        return $"public extern \"C\" {type} {Identifier(variable.Name)};\n";
    }

    private string? WriteTypedef(CTypedefDecl typedef, Context context)
    {
        if (IsPrivateName(typedef.Name) || Primitives.ContainsKey(typedef.Name)) return null;
        if (Canonical(typedef.Type) is CBuiltin { Name: "void" }) return null;

        if (IsCFTypedef(typedef.Name))
            return WriteCFType(typedef, context);
        if (ClassAliased(typedef.Name) is { } aliasedClass)
            return $"public using {Identifier(typedef.Name)} = {SpellObjCDecl(aliasedClass, aliasedClass.Name, context)};\n";
        if (typedef.Type is not CBlock && IsManaged(typedef.Type, context))
        {
            // `typedef id<NSFileProviderItem> NSFileProviderItem` names what is named already.
            string aliased = SpellManaged(typedef.Type, context, typedef.Name + "Type");
            return aliased == Identifier(typedef.Name) ? null : $"public using {Identifier(typedef.Name)} = {aliased};\n";
        }

        switch (typedef.Type)
        {
            // `typedef struct CGRect CGRect`: the tag already has the name;
            // and a struct with no body is named by its tag wherever it is used.
            case CTag tag when tag.Name == typedef.Name || IsIncomplete(tag):
                return null;

            // `typedef struct { ... } CGPoint`: the record takes the name.
            case CAnonymous anonymous:
                return FindAnonymous(anonymous) switch
                {
                    CRecordDecl record => WriteRecord(record, typedef.Name, context),
                    CEnumDecl enumeration => WriteEnum(enumeration, typedef.Name, context),
                    _ => throw new Unsupported($"the type it names was never declared ({anonymous.Where})"),
                };

            case CPointer { Pointee: CFunction function }:
                return WriteDelegate(typedef.Name, function, context);

            case CFunction function:
                return WriteDelegate(typedef.Name, function, context);

            case CBlock block:
                return WriteBlock(typedef.Name, block.Function, context);

            // `typedef unsigned char Str255[256]`: the array itself, which a
            // field holds whole and a parameter receives as a pointer.
            case CArray { Length: not null } array:
                return $"public using {Identifier(typedef.Name)} = {Spell(array, context, typedef.Name + "Type", Placement.Field)};\n";

            // `typedef __darwin_uuid_t uuid_t`: an array through a typedef is
            // an array too.
            case var _ when Canonical(typedef.Type) is CArray { Length: not null }:
                return $"public using {Identifier(typedef.Name)} = {Spell(typedef.Type, context, typedef.Name + "Type", Placement.Field)};\n";

            default:
                return $"public using {Identifier(typedef.Name)} = {Spell(typedef.Type, context, typedef.Name + "Type")};\n";
        }
    }

    private string WriteDelegate(string name, CFunction function, Context context)
    {
        if (function.Variadic) throw new Unsupported("a variadic function pointer, which a delegate cannot be");

        // C calls it and says nothing of who owns an object it passes, so
        // what a delegate takes is the pointer.
        var parameters = function.Parameters
            .Select((p, i) => $"{SpellParameter(p, context, name + "Arg" + i, use: Placement.Raw)} arg{i}");
        return $"public delegate {Spell(function.Result, context, name + "Result")} {Identifier(name)}({string.Join(", ", parameters)});\n";
    }

    /// <summary>
    /// A block type: what it takes and returns crosses as a message's does,
    /// so an object is counted and a <c>BOOL</c> is <c>bool</c>.
    /// </summary>
    private string WriteBlock(string name, CFunction function, Context context)
    {
        if (function.Variadic) throw new Unsupported("a variadic block");

        bool outer = context.InObjC;
        context.InObjC = true;
        try
        {
            var parameters = function.Parameters.Select((p, i) =>
                $"{SpellValue(p, function.ParameterNullability.ElementAtOrDefault(i), context, name + "Arg" + i)} arg{i}");
            string result = Canonical(function.Result) is CBuiltin { Name: "void" }
                ? "void"
                : SpellValue(function.Result, function.ResultNullability, context, name + "Result");
            return $"public objc closure {result} {Identifier(name)}({string.Join(", ", parameters)});\n";
        }
        finally
        {
            context.InObjC = outer;
        }
    }

    private string? WriteRecord(CRecordDecl record, string name, Context context)
    {
        if (name.Length == 0) return null;

        // An incomplete record whose definition is elsewhere in the program
        // is declared by that definition.
        if (!record.IsComplete)
        {
            if (translation.Records.TryGetValue((record.Kind, record.Name), out var complete) && complete.IsComplete)
                return null;
            if (record.Kind == CTagKind.Union)
                throw new Unsupported("an incomplete union, which only a struct can be");
            return $"public struct {Identifier(name)};\n";
        }

        // A field's own alignment raises the record's, which is all it does to
        // a union and to a struct's first field; any later one moves offsets
        // that only the field could say.
        int? alignment = record.Alignment;
        for (int i = 0; i < record.Fields.Count; i++)
        {
            if (record.Fields[i].Alignment is not { } wanted) continue;
            if (record.Kind == CTagKind.Struct && i > 0)
                throw new Unsupported(
                    $"its field '{record.Fields[i].Name}' is aligned to {wanted}, which Stainless has no way to say of a field");
            alignment = Math.Max(alignment ?? 1, wanted);
        }

        if (alignment is > 4096)
            throw new Unsupported($"aligned to {alignment} bytes, more than [Align] allows");
        // Under `#pragma pack`, the most any field is aligned to; a record with
        // no tag nested in one was declared under the same pragma.
        int? pack = record.HasPragmaPack ? record.Pack ?? _enclosingPack : null;

        if ((record.IsPacked || pack is not null) && HasBitFields(record))
            throw new Unsupported("packed with bit-fields, which Stainless does not lay out together");
        if (record.HasPragmaPack && pack is null)
            throw new Unsupported("declared under a #pragma pack whose value clang did not say");

        var text = new StringBuilder();
        if (record.IsPacked) text.Append("[Packed]\n");
        else if (pack is { } most) text.Append($"[Pack({most})]\n");
        if (alignment is { } raised) text.Append($"[Align({raised})]\n");
        text.Append($"public {(record.Kind == CTagKind.Union ? "union" : "struct")} {Identifier(name)}\n{{\n");

        int? outer = _enclosingPack;
        _enclosingPack = pack;
        try
        {
            WriteFields(record, name, context, text, "    ");
        }
        finally
        {
            _enclosingPack = outer;
        }

        text.Append("}\n");
        return text.ToString();
    }

    /// <summary>The pack of the record whose fields are being written, for a nested one with no tag.</summary>
    private int? _enclosingPack;

    private static bool HasBitFields(CRecordDecl record) =>
        record.Fields.Any(f => f.BitWidth is not null || (f.Inline is { } inline && HasBitFields(inline)));

    private void WriteFields(CRecordDecl record, string owner, Context context, StringBuilder text, string indent)
    {
        for (int i = 0; i < record.Fields.Count; i++)
        {
            var field = record.Fields[i];

            if (field.Inline is { } inline)
            {
                text.Append($"{indent}public {(inline.Kind == CTagKind.Union ? "union" : "struct")}\n{indent}{{\n");
                WriteFields(inline, owner, context, text, indent + "    ");
                text.Append($"{indent}}}\n");
                continue;
            }

            if (field.Name is null)
                throw new Unsupported("an unnamed field, which Stainless has no way to write");

            if (field.BitWidth == 0)
                throw new Unsupported("a zero-width bit-field");

            // A flexible array member, or a run of zero-length arrays ending
            // the struct, adds nothing to its size; C's sizeof leaves them out
            // as this does.
            if (record.Fields.Skip(i).All(f => f.Type is CArray { Length: null or 0 }))
            {
                text.Append($"{indent}// {field.Name}[] follows: a flexible array member.\n");
                continue;
            }

            string type = Spell(field.Type, context, owner + Capitalized(field.Name), Placement.Field);
            string width = field.BitWidth is { } bits ? $" : {bits}" : "";
            string packed = field.IsPacked ? "[Packed] " : "";
            text.Append($"{indent}{packed}public {type} {Identifier(field.Name)}{width};\n");
        }
    }

    /// <summary>
    /// A <c>#define</c> constant: an integer with the value clang folded it
    /// to, a floating-point literal as written, or a string literal -- a C
    /// string, a <c>CFSTR("...")</c> or an <c>@"..."</c>.
    /// </summary>
    private string? WriteMacro(CMacro macro, Context context)
    {
        if (macro.Type is null) return null;
        if (WriteStringMacro(macro, context) is { } stringConstant) return stringConstant;

        string? type = MacroType(macro.Type);
        string name = Identifier(macro.Name);

        if (type is "float" or "double" or "ndouble")
        {
            var literal = FloatLiteral().Match(macro.Body);
            if (!literal.Success) throw new Unsupported($"a {type} macro that is not a literal ({macro.Body})");
            string text = literal.Groups[1].Value;

            // A literal is a double's: LDBL_MAX's 1.19e4932 is not one.
            if (!double.TryParse(text, System.Globalization.NumberStyles.Float,
                    System.Globalization.CultureInfo.InvariantCulture, out double parsed) ||
                double.IsInfinity(parsed))
                throw new Unsupported($"a {type} beyond a double, which a literal holds ({macro.Body})");
            if (!text.Contains('.') && !text.Contains('e') && !text.Contains('E')) text += ".0";
            return $"public const {type} {name} = {text}{(type == "float" ? "f" : "")};\n";
        }

        if (type == "bool" && macro.Value is { } truth)
            return $"public const bool {name} = {(truth.IsZero ? "false" : "true")};\n";

        if (type is not null && macro.Value is { } value)
            return $"public const {type} {name} = {Literal(value, type)};\n";

        // An integer with no value folded was never a constant: an attribute
        // or a keyword spelled as a macro, which clang's recovery typed.
        if (type is not null) return null;

        throw new Unsupported($"a macro of type '{macro.Type}', which a const cannot hold");
    }

    /// <summary>
    /// A macro whose body is a string literal, as the constant it makes: a
    /// <c>byte*</c> for a <c>char</c> array, and the string object for
    /// <c>CFSTR</c> and <c>@</c>. Null when the macro is not one; a body that
    /// computes a string, from other macros say, is not a literal and is refused.
    /// </summary>
    private string? WriteStringMacro(CMacro macro, Context context)
    {
        string? type;
        string body;
        switch (Canonical(macro.Type!))
        {
            case CArray { Element: CBuiltin { Name: "char" } }:
                type = "byte*";
                body = macro.Body;
                break;

            case CPointer { Pointee: CTag { Kind: CTagKind.Struct, Name: "__CFString" } }:
                var made = CFStringMacro().Match(macro.Body);
                if (!made.Success) throw new Unsupported($"a CFStringRef macro that is not CFSTR(\"...\") ({macro.Body})");
                type = Spell(new CTypedef("CFStringRef"), context, macro.Name, Placement.Value, Nullability.NonNull);
                body = made.Groups[1].Value;
                break;

            case CPointer when MacroAlias().IsMatch(macro.Body) && macro.Body.Trim() is not ("NULL" or "nil" or "Nil"):
                throw new Unsupported($"a macro naming '{macro.Body.Trim()}', and an extern cannot take a second name");

            case CPointer when macro.Body.StartsWith('@'):
                type = Spell(macro.Type!, context, macro.Name, Placement.Value, Nullability.NonNull);
                if (type != "NSString") throw new Unsupported($"an object macro of type '{type}', which is no NSString");
                body = macro.Body[1..];
                break;

            default:
                return null;
        }

        var bytes = CStringLiterals.Decode(body)
            ?? throw new Unsupported($"a string macro whose body is not a literal ({macro.Body})");
        string text;
        try
        {
            text = new UTF8Encoding(false, true).GetString(bytes);
        }
        catch (DecoderFallbackException)
        {
            throw new Unsupported($"a string macro that is not UTF-8 ({macro.Body})");
        }

        return $"public const {type} {Identifier(macro.Name)} = {CStringLiterals.Spell(text)};\n";
    }

    [GeneratedRegex(@"^\(?\s*CFSTR\s*\((.*)\)\s*\)?$")]
    private static partial Regex CFStringMacro();

    [GeneratedRegex(@"^\s*[A-Za-z_][A-Za-z0-9_]*\s*$")]
    private static partial Regex MacroAlias();

    /// <summary>The primitive a macro's type comes to, through typedefs and enums, or null.</summary>
    private string? MacroType(CType type)
    {
        switch (Canonical(type))
        {
            case CBuiltin builtin when builtin.Name != "void":
                try { return Builtin(builtin.Name); }
                catch (Unsupported) { return null; }

            case CTag { Kind: CTagKind.Enum } tag when translation.Enums.TryGetValue(tag.Name, out var enumeration):
                return EnumUnderlying(enumeration);

            case CAnonymous anonymous when FindAnonymous(anonymous) is CEnumDecl enumeration:
                return EnumUnderlying(enumeration);

            default:
                return null;
        }
    }

    [GeneratedRegex(@"^\(?\s*([-+]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?)[fFlL]?\s*\)?$")]
    private static partial Regex FloatLiteral();

    private string? WriteEnum(CEnumDecl enumeration, string name, Context context)
    {
        // A forward declaration; the definition writes the enum.
        if (name.Length > 0 && enumeration.Members.Count == 0 &&
            translation.Enums.TryGetValue(name, out var defined) && defined.Members.Count > 0)
            return null;

        string underlying = EnumUnderlying(enumeration);

        if (name.Length == 0 || enumeration.Members.Count == 0)
        {
            // `enum { kCFNotFound = -1 };`: constants under their own names.
            var constants = new StringBuilder();
            foreach (var member in enumeration.Members)
                constants.Append($"public const {underlying} {Identifier(member.Name)} = {Literal(member.Value, underlying)};\n");
            return constants.Length > 0 ? constants.ToString() : null;
        }

        var names = MemberNames(enumeration.Members.Select(m => m.Name).ToList());
        var text = new StringBuilder();
        if (enumeration.IsFlags) text.Append("[Flags]\n");
        text.Append($"public enum {Identifier(name)} : {underlying}\n{{\n");
        for (int i = 0; i < enumeration.Members.Count; i++)
            text.Append($"    {Identifier(names[i])} = {Literal(enumeration.Members[i].Value, underlying)},\n");
        text.Append("}\n");
        return text.ToString();
    }

    /// <summary>
    /// The integer type under an enum: the one written after the colon, or
    /// for one with none, the narrowest of <c>int</c>, <c>uint</c> and
    /// <c>long</c> that holds every value, as C chooses.
    /// </summary>
    private string EnumUnderlying(CEnumDecl enumeration)
    {
        if (enumeration.Underlying is { } written && Canonical(written) is CBuiltin builtin)
            return Builtin(builtin.Name);

        var values = enumeration.Members.Select(m => m.Value).ToList();
        if (values.All(v => v >= int.MinValue && v <= int.MaxValue)) return "int";
        if (values.All(v => v >= 0 && v <= uint.MaxValue)) return "uint";
        return values.All(v => v >= 0) ? "ulong" : "long";
    }

    /// <summary>A value as a literal of <paramref name="type"/>, wrapped to its width as C converts it.</summary>
    private static string Literal(BigInteger value, string type)
    {
        (int bits, bool signed) = type switch
        {
            "sbyte" => (8, true), "byte" => (8, false), "short" => (16, true), "ushort" => (16, false),
            "int" => (32, true), "uint" => (32, false), "long" or "nint" => (64, true),
            "int128" => (128, true), "uint128" => (128, false),
            _ => (64, false),
        };

        var modulus = BigInteger.One << bits;
        var wrapped = ((value % modulus) + modulus) % modulus;
        if (signed && wrapped >= modulus >> 1) wrapped -= modulus;
        return wrapped.ToString(System.Globalization.CultureInfo.InvariantCulture) + (signed ? "" : wrapped > int.MaxValue ? "u" : "");
    }

    /// <summary>
    /// Enumerators with the prefix they share taken off at a word boundary:
    /// <c>kCFCompareLessThan</c> and <c>kCFCompareEqualTo</c> are
    /// <c>LessThan</c> and <c>EqualTo</c>. What is left MUST begin with a
    /// letter, and a single enumerator keeps its whole name.
    /// </summary>
    public static List<string> MemberNames(List<string> names)
    {
        if (names.Count < 2) return names;

        int prefix = names.Skip(1).Aggregate(names[0].Length, (length, n) =>
        {
            int common = 0;
            while (common < length && common < n.Length && n[common] == names[0][common]) common++;
            return common;
        });

        // Back to the start of a word.
        while (prefix > 0 && !IsWordStart(names[0], prefix)) prefix--;

        if (prefix == 0 || names.Any(n => n.Length <= prefix || !char.IsAsciiLetter(n[prefix])))
            return names;

        return names.Select(n => n[prefix..]).ToList();
    }

    /// <summary>
    /// True when a word begins at <paramref name="at"/>: after an underscore,
    /// or at a capital that follows a small letter or a digit, or that a
    /// small letter follows, as the <c>S</c> of <c>CFURLSession</c> does.
    /// </summary>
    private static bool IsWordStart(string name, int at) =>
        at > 0 && at < name.Length &&
        (name[at - 1] == '_' ||
         (char.IsAsciiLetterUpper(name[at]) &&
          (!char.IsAsciiLetterUpper(name[at - 1]) ||
           (at + 1 < name.Length && char.IsAsciiLetterLower(name[at + 1])))));

    // ------------------------------------------------------------ types

    /// <summary>A parameter's type: an array decays to a pointer to its element, as C passes it.</summary>
    private string SpellParameter(CType type, Context context, string hint,
                                  Nullability nullability = Nullability.Unspecified, Placement use = Placement.Value) =>
        Canonical(type) is CArray array
            ? Spell(new CPointer(array.Element), context, hint)
            : Spell(type, context, hint, use, nullability);

    /// <summary>
    /// A type as Stainless writes it, noting the modules and synthesized
    /// types it needs. An object is counted where it is a value, and is a
    /// plain pointer anywhere else; a value is optional unless C promised it
    /// is never nil.
    /// </summary>
    private string Spell(CType type, Context context, string hint, Placement use = Placement.Raw,
                         Nullability nullability = Nullability.Unspecified)
    {
        if (IsManaged(type, context))
        {
            if (use != Placement.Value) return SpellUnmanaged(type, context, hint);
            string managed = SpellManaged(type, context, hint);
            return nullability == Nullability.NonNull ? managed : managed + "?";
        }

        bool isField = use is Placement.Field or Placement.Value;
        switch (type)
        {
            case CTypedef { Name: "Class" } or CObjCQualified { Base: CTypedef { Name: "Class" } }:
                context.Imports.Add(ObjCModule);
                return "Class";

            case CTypedef { Name: "SEL" }:
                context.Imports.Add(ObjCModule);
                return "Selector";

            case CTypedef { Name: "BOOL" } when context.InObjC:
                return "bool";

            case CBuiltin builtin:
                return Builtin(builtin.Name);

            case CVector vector:
                return SpellVector(vector);

            case CUnsupported unsupported:
                throw new Unsupported(unsupported.Why);

            case CTypedef typedef:
                return SpellTypedef(typedef.Name, context, hint, use);

            case CTag tag:
                return SpellTag(tag, context);

            case CAnonymous anonymous:
                return FindAnonymous(anonymous) is { } found && NameOfAnonymous(found) is { } name
                    ? SpellNamed(found, name, context)
                    : SynthesizeAnonymous(anonymous, context, hint);

            case CPointer { Pointee: CFunction function }:
                return Synthesize(context, Suffixed(hint, "Function"), n => WriteDelegate(n, function, context));

            case CBlock block:
                return Synthesize(context, Suffixed(hint, "Block"), n => WriteBlock(n, block.Function, context));

            // System V's va_list is an array of this, so a parameter of it has
            // decayed to a pointer by the time clang prints it.
            case CPointer { Pointee: CTag { Kind: CTagKind.Struct, Name: "__va_list_tag" } }:
                return "VaList";

            case CPointer pointer:
                return Spell(pointer.Pointee, context, hint) + "*";

            case CArray array when isField:
            {
                if (array.Length is not { } length) throw new Unsupported("an array of no length inside a struct");
                var element = array.Element;
                long total = length;
                while (element is CArray { Length: { } inner } nested)
                {
                    total *= inner;
                    element = nested.Element;
                }
                return $"{Spell(element, context, hint)}[{total}]";
            }

            case CArray array:
                return Spell(array.Element, context, hint) + "*";

            case CFunction function:
                throw new Unsupported($"a function type where a value is wanted ({function})");

            default:
                throw new Unsupported($"the type {type}");
        }
    }

    /// <summary>
    /// A C vector as the Stainless one: <c>vfloat4</c>. C's <c>char</c> is
    /// signed on every Apple target, so a vector of it is of <c>sbyte</c>.
    /// </summary>
    private string SpellVector(CVector vector)
    {
        if (Canonical(vector.Element) is not CBuiltin { Name: var c })
            throw new Unsupported($"a vector of {vector.Element}");

        var (element, size) = c switch
        {
            "char" or "signed char" => ("sbyte", 1),
            "unsigned char" => ("byte", 1),
            "short" => ("short", 2),
            "unsigned short" => ("ushort", 2),
            "int" => ("int", 4),
            "unsigned int" => ("uint", 4),
            "float" => ("float", 4),
            "long" or "long long" => ("long", 8),
            "unsigned long" or "unsigned long long" => ("ulong", 8),
            "double" => ("double", 8),
            _ => throw new Unsupported($"a vector of {c}"),
        };

        int lanes = vector.CountIsBytes ? vector.Count / size : vector.Count;
        int[] counts = size switch
        {
            1 => [2, 3, 4, 8, 16, 32, 64],
            2 => [2, 3, 4, 8, 16, 32],
            4 => [2, 3, 4, 8, 16],
            _ => [2, 3, 4, 8],
        };
        if (!counts.Contains(lanes)) throw new Unsupported($"a vector of {lanes} {c}");
        return $"v{element}{lanes}";
    }

    private static string Builtin(string name) => name switch
    {
        "void" => "void",
        "bool" => "bool",
        "char" or "unsigned char" => "byte",
        "signed char" => "sbyte",
        "short" => "short",
        "unsigned short" => "ushort",
        "int" or "wchar_t" => "int",
        "unsigned int" => "uint",
        "long" or "long long" => "long",
        "unsigned long" or "unsigned long long" => "ulong",
        "float" => "float",
        "double" => "double",
        "long double" => "ndouble",
        "char16_t" => "char16",
        "char32_t" => "char32",
        "__int128" => "int128",
        "unsigned __int128" => "uint128",
        _ => throw new Unsupported($"the builtin type '{name}'"),
    };

    private string SpellTypedef(string name, Context context, string hint, Placement use)
    {
        if (context.TypeParameters.Contains(name)) return "void*";
        if (Primitives.TryGetValue(name, out string? primitive)) return primitive;
        if (name is "va_list" or "__builtin_va_list" or "__darwin_va_list" or "__gnuc_va_list")
            return "VaList";

        if (!translation.Typedefs.TryGetValue(name, out var typedef))
            throw new Unsupported($"the type '{name}', which no header declares");

        string? owner = OwnerOf(typedef.File);

        // `__darwin_size_t` and the like are the implementation's: what they
        // stand for is written instead.
        // Spelled where it is written, so a private typedef of an array is
        // the array inside a struct, as `uuid_t`'s `__darwin_uuid_t` is.
        if (owner is null || IsPrivateName(name))
            return Spell(typedef.Type, context, hint, use);

        // A typedef of a tag of its own name, or of a struct with no body,
        // is spelled as the tag: a value of an incomplete type is no type.
        if (typedef.Type is CTag tag && (tag.Name == name || IsIncomplete(tag)))
            return SpellTag(tag, context);

        // `typedef void GLvoid`: an alias of no type, which only a pointer can
        // be of, so it is spelled as what it is.
        if (Canonical(typedef.Type) is CBuiltin { Name: "void" })
            return "void";

        Use(owner, typedef, context);
        return Identifier(name);
    }

    private string SpellTag(CTag tag, Context context)
    {
        CDecl? declared = tag.Kind == CTagKind.Enum
            ? translation.Enums.GetValueOrDefault(tag.Name)
            : translation.Records.GetValueOrDefault((tag.Kind, tag.Name));

        if (declared is null) throw new Unsupported($"{tag.Kind.ToString().ToLowerInvariant()} {tag.Name}, which no header declares");
        return SpellNamed(declared, tag.Name, context);
    }

    private string SpellNamed(CDecl declared, string name, Context context)
    {
        string? owner = OwnerOf(declared.File);
        if (owner is null) throw new Unsupported($"'{name}', which only the compiler declares");
        Use(owner, declared, context);
        return Identifier(name);
    }

    /// <summary>
    /// Notes that <paramref name="context"/> names a declaration of
    /// <paramref name="owner"/>, which MUST itself be one that binds: a
    /// declaration naming a type that is skipped is skipped with it.
    /// </summary>
    private void Use(string owner, CDecl declared, Context context)
    {
        if (owner != SystemOwner && !generated.Contains(owner))
            throw new Unsupported($"it uses '{declared.Name}' from {owner}, which is not generated");
        if (declared.Availability.Unavailable)
            throw new Unsupported($"it uses '{declared.Name}', which is unavailable on macOS");
        if (WhyNotWritable(declared) is { } why)
            throw new Unsupported($"it uses '{declared.Name}', which is skipped: {why}");

        if (owner == SystemOwner) SystemNeeded.Add(declared);
        if (owner != context.Owner) context.Imports.Add(ModuleOf(owner));
        context.Uses.Add((owner, Key(declared)));
    }

    private readonly Dictionary<CDecl, string?> _writable = new(ReferenceEqualityComparer.Instance);
    private readonly HashSet<CDecl> _checking = new(ReferenceEqualityComparer.Instance);

    /// <summary>Why a declaration cannot be written, or null when it can; asked once each.</summary>
    private string? WhyNotWritable(CDecl declared)
    {
        if (_writable.TryGetValue(declared, out string? known)) return known;

        // A type that refers to itself through a pointer is writable as far
        // as that reference is concerned.
        if (!_checking.Add(declared)) return null;

        string? why = null;
        var scratch = new Context(OwnerOf(declared.File) ?? SystemOwner, HeaderOf(declared.File), declared.Name);
        try
        {
            _ = declared switch
            {
                CRecordDecl record => WriteRecord(record, record.Name.Length > 0 ? record.Name : "Anonymous", scratch),
                CEnumDecl enumeration => WriteEnum(enumeration, enumeration.Name, scratch),
                CTypedefDecl typedef => WriteTypedef(typedef, scratch),
                _ => null,
            };
        }
        catch (Unsupported unsupported)
        {
            why = unsupported.Message;
        }

        _checking.Remove(declared);
        _writable[declared] = why;
        return why;
    }

    /// <summary>The typedef that names a record or enum with no tag, if one does.</summary>
    private string? NameOfAnonymous(CDecl found) =>
        translation.Typedefs.Values.FirstOrDefault(t => t.Type is CAnonymous a && FindAnonymous(a) == found)?.Name;

    /// <summary>
    /// The record or enum clang named <c>(unnamed struct at file:line:column)</c>,
    /// matched on the place, or on the file and line when the column differs.
    /// </summary>
    public CDecl? FindAnonymous(CAnonymous anonymous)
    {
        var where = AnonymousPlace().Match(anonymous.Where);
        if (!where.Success) return null;
        string place = where.Groups[1].Value;

        if (translation.Anonymous.TryGetValue(place, out var exact)) return exact;
        string line = place[..place.LastIndexOf(':')];
        return translation.Anonymous.FirstOrDefault(p => p.Key.StartsWith(line + ":", StringComparison.Ordinal)).Value;
    }

    [GeneratedRegex(@"\((?:unnamed|anonymous)(?: (?:struct|union|enum))? at (.+)\)$")]
    private static partial Regex AnonymousPlace();

    /// <summary>An unnamed record somewhere a type is wanted, given the name of where it is.</summary>
    private string SynthesizeAnonymous(CAnonymous anonymous, Context context, string hint) =>
        FindAnonymous(anonymous) switch
        {
            CRecordDecl record => Synthesize(context, hint, n => WriteRecord(record, n, context)!),
            CEnumDecl enumeration => Synthesize(context, hint, n => WriteEnum(enumeration, n, context)!),
            _ => throw new Unsupported($"an unnamed type that was never declared ({anonymous.Where})"),
        };

    /// <summary>A name with a word on the end, unless it ends with that word already.</summary>
    private static string Suffixed(string name, string word) =>
        name.EndsWith(word, StringComparison.Ordinal) ? name : name + word;

    /// <summary>A type the declaration being written needs and C never named, written before it.</summary>
    private static string Synthesize(Context context, string name, Func<string, string> write)
    {
        string identifier = Identifier(name);
        if (context.SynthesizedNames.Add(identifier))
            context.Synthesized.Add(write(identifier));
        return identifier;
    }

    /// <summary>A type with its typedefs resolved, to find the integer under an enum.</summary>
    private CType Canonical(CType type) =>
        type is CTypedef typedef
            ? Primitives.TryGetValue(typedef.Name, out string? primitive)
                ? new CBuiltin(primitive switch
                {
                    "sbyte" => "signed char", "byte" => "unsigned char", "short" => "short",
                    "ushort" => "unsigned short", "int" => "int", "uint" => "unsigned int",
                    "long" or "nint" => "long", "int128" => "__int128",
                    "uint128" => "unsigned __int128", _ => "unsigned long",
                })
                // clang's own `typedef id id` names itself.
                : translation.Typedefs.TryGetValue(typedef.Name, out var declared) && declared.Type != type
                    ? Canonical(declared.Type)
                    : type
            : type;

    private bool IsIncomplete(CTag tag) =>
        tag.Kind != CTagKind.Enum &&
        translation.Records.TryGetValue((tag.Kind, tag.Name), out var record) && !record.IsComplete;

    private static bool IsPrivateName(string name) => name.StartsWith("__", StringComparison.Ordinal);

    /// <summary>Each parameter's name, made unique where a header gives two the same one.</summary>
    private static List<string> ParameterNames(IReadOnlyList<CParameter> parameters)
    {
        var names = parameters.Select((p, i) => ParameterName(p.Name, i)).ToList();
        for (int i = 0; i < names.Count; i++)
            if (names.IndexOf(names[i]) != i)
                names[i] += i;
        return names;
    }

    private static string ParameterName(string? name, int index) =>
        Identifier(string.IsNullOrEmpty(name) ? $"arg{index}" : name);

    private static string Capitalized(string name)
    {
        string bare = name.TrimStart('@', '_');
        return bare.Length == 0 ? "Value" : char.ToUpperInvariant(bare[0]) + bare[1..];
    }

    /// <summary>A C name as a Stainless identifier: a keyword is escaped, and links as itself.</summary>
    public static string Identifier(string name) => Keywords.Contains(name) ? "@" + name : name;

    /// <summary>What one declaration being written has gathered.</summary>
    private sealed class Context(string owner, string header, string name)
    {
        /// <summary>An Objective-C class's type parameters, which are <c>id</c>.</summary>
        public HashSet<string> TypeParameters { get; } = new(StringComparer.Ordinal);

        /// <summary>Inside a message or a block, where a <c>BOOL</c> is <c>bool</c>.</summary>
        public bool InObjC { get; set; }

        public List<RuntimeCheck> Runtime { get; } = [];

        /// <summary>When the class, category or protocol being written appeared, if later than the oldest built for.</summary>
        public string? Introduced { get; set; }

        public string Owner { get; } = owner;
        public string Header { get; } = header;
        public string Name { get; } = name;
        public HashSet<string> Imports { get; } = new(StringComparer.Ordinal);
        public HashSet<(string Owner, string Key)> Uses { get; } = [];
        public List<string> Synthesized { get; } = [];
        public HashSet<string> SynthesizedNames { get; } = new(StringComparer.Ordinal);
    }

    private sealed class Unsupported(string why) : Exception(why);
}
