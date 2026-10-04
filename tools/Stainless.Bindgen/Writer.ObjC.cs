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

using System.Text;

namespace Stainless.Bindgen;

/// <summary>
/// The member names each Objective-C class and protocol has been given, over
/// every part of it in every framework, so that a category written later
/// neither declares a member again nor takes a name already taken.
/// </summary>
public sealed class ObjCNames
{
    public sealed record Member(string Name, string Selector, bool IsStatic, bool IsProperty, int Arity);

    private readonly Dictionary<string, List<Member>> _owners = new(StringComparer.Ordinal);

    private readonly Dictionary<string, HashSet<string>> _adopted = new(StringComparer.Ordinal);

    /// <summary>Whether <paramref name="owner"/> is listed as adopting a protocol for the first time.</summary>
    public bool Adopt(string owner, string protocol)
    {
        if (!_adopted.TryGetValue(owner, out var protocols)) _adopted[owner] = protocols = new(StringComparer.Ordinal);
        return protocols.Add(protocol);
    }

    /// <summary>
    /// The name a member is declared under, or null when its owner already
    /// answers the selector. A name taken by a member it cannot overload is
    /// changed by a fixed rule: a class member gains <c>Class</c> before it,
    /// a property <c>Property</c> after it, a method <c>Method</c>.
    /// </summary>
    public string? Claim(string owner, string name, IReadOnlyList<string> selectors, bool isStatic, bool isProperty, int arity)
    {
        if (!_owners.TryGetValue(owner, out var members)) _owners[owner] = members = [];
        if (members.Any(m => m.IsStatic == isStatic && selectors.Contains(m.Selector))) return null;

        string chosen = name;
        string renamed = isStatic ? "Class" + name : isProperty ? name + "Property" : name + "Method";
        for (int attempt = 1; members.Any(m => m.Name == chosen && Conflicts(m, isStatic, isProperty, arity)); attempt++)
            chosen = attempt == 1 ? renamed : renamed + attempt;

        foreach (string selector in selectors)
            members.Add(new Member(chosen, selector, isStatic, isProperty, arity));
        return chosen;
    }

    /// <summary>Two methods of one kind overload by their number of parameters; nothing else shares a name.</summary>
    private static bool Conflicts(Member existing, bool isStatic, bool isProperty, int arity) =>
        existing.IsProperty || isProperty || existing.IsStatic != isStatic || existing.Arity == arity;
}

public sealed partial class Writer
{
    /// <summary>
    /// Where a type is written decides what an object becomes. As a value --
    /// a parameter, a result, a property, a C variable -- it is a reference
    /// ARC counts; inside a struct or behind a pointer nothing would count it,
    /// so it is the pointer it is.
    /// </summary>
    private enum Placement { Raw, Field, Value }

    /// <summary>Where <c>AnyObject</c>, <c>Class</c> and <c>Selector</c> are.</summary>
    private const string ObjCModule = "Standard.ObjC";

    private readonly ObjCNames _names = names ?? new();

    /// <summary>The structs a Core Foundation type points at: bridged, or with a <c>GetTypeID</c>.</summary>
    private HashSet<string>? _cfStructs;

    private HashSet<string> CFStructs => _cfStructs ??= FindCFStructs();

    private HashSet<string> FindCFStructs()
    {
        var structs = new HashSet<string>(translation.BridgedRecords, StringComparer.Ordinal);
        foreach (var typedef in translation.Typedefs.Values)
            if (typedef.Type is CPointer { Pointee: CTag { Kind: CTagKind.Struct } tag } &&
                translation.TypeIDFunctions.Contains(TypeIDFunctionOf(typedef.Name)))
                structs.Add(tag.Name);
        return structs;
    }

    /// <summary><c>CFStringRef</c>'s is <c>CFStringGetTypeID</c>.</summary>
    private static string TypeIDFunctionOf(string typedef) =>
        (typedef.EndsWith("Ref", StringComparison.Ordinal) ? typedef[..^3] : typedef) + "GetTypeID";

    /// <summary>A typedef naming a Core Foundation type: <c>CFTypeRef</c>, or a pointer to a CF struct.</summary>
    private bool IsCFTypedef(string name) =>
        name == "CFTypeRef" ||
        (translation.Typedefs.TryGetValue(name, out var typedef) &&
         typedef.Type is CPointer { Pointee: CTag { Kind: CTagKind.Struct } tag } &&
         CFStructs.Contains(tag.Name));

    /// <summary>The name a protocol is declared under: its own, unless a class has it too.</summary>
    private string ProtocolName(string name) =>
        translation.Interfaces.ContainsKey(name) ? name + "Protocol" : name;

    // ------------------------------------------------------------ types

    /// <summary>
    /// Whether <paramref name="type"/> is an object: an Objective-C object
    /// pointer, <c>id</c>, a block, or a Core Foundation type, through any
    /// typedef naming one.
    /// </summary>
    private bool IsManaged(CType type, Context context) => type switch
    {
        CTypedef { Name: "id" or "instancetype" } => true,
        CTypedef named when context.TypeParameters.Contains(named.Name) => true,
        CTypedef named when IsCFTypedef(named.Name) => true,
        CTypedef named when !Primitives.ContainsKey(named.Name) &&
                            translation.Typedefs.TryGetValue(named.Name, out var typedef) &&
                            typedef.Type != type => IsManaged(typedef.Type, context),
        CObjCQualified { Base: CTypedef idLike } when IsIdLike(idLike, context) => true,
        CPointer { Pointee: var pointee } => IsObjCClass(pointee),
        CBlock => true,
        _ => false,
    };

    /// <summary><c>id</c>, or a generic's type parameter, which is <c>id</c> erased.</summary>
    private static bool IsIdLike(CTypedef type, Context context) =>
        type.Name == "id" || context.TypeParameters.Contains(type.Name);

    /// <summary><c>NSString</c> or <c>NSArray&lt;T&gt;</c>, which only a pointer is ever to.</summary>
    private bool IsObjCClass(CType type) => type switch
    {
        CTypedef named => translation.Interfaces.ContainsKey(named.Name) || ClassAliased(named.Name) is not null,
        CObjCQualified { Base: CTypedef named } => translation.Interfaces.ContainsKey(named.Name),
        _ => false,
    };

    /// <summary>
    /// The class a typedef names, as <c>typedef NSArray&lt;MIDICIProfileState *&gt;
    /// MIDICIProfileStateList</c> does -- the class itself, which only a pointer
    /// is ever to -- or null.
    /// </summary>
    private CObjCInterface? ClassAliased(string typedef)
    {
        if (!translation.Typedefs.TryGetValue(typedef, out var declared)) return null;
        string? name = declared.Type switch
        {
            CTypedef named => named.Name,
            CObjCQualified { Base: CTypedef named } => named.Name,
            _ => null,
        };
        return name is not null && name != typedef && translation.Interfaces.TryGetValue(name, out var objcClass)
            ? objcClass
            : null;
    }

    /// <summary>
    /// An object type as a value: the class, protocol, closure, Core
    /// Foundation type or typedef ARC counts, without the <c>?</c>.
    /// </summary>
    private string SpellManaged(CType type, Context context, string hint)
    {
        context.Imports.Add(ObjCModule);
        switch (type)
        {
            case CTypedef { Name: "id" }:
                return "AnyObject";

            case CTypedef { Name: "instancetype" }:
                return "Self";

            case CTypedef named when context.TypeParameters.Contains(named.Name):
                return "AnyObject";

            case CTypedef named when IsCFTypedef(named.Name) || translation.Typedefs.ContainsKey(named.Name):
            {
                if (!translation.Typedefs.TryGetValue(named.Name, out var typedef))
                    throw new Unsupported($"'{named.Name}', which no header declares");
                if (OwnerOf(typedef.File) is not { } owner)
                    throw new Unsupported($"'{named.Name}', which only the compiler declares");
                Use(owner, typedef, context);
                return Identifier(named.Name);
            }

            case CObjCQualified { Base: CTypedef idLike, Arguments: var protocols } when IsIdLike(idLike, context):
                // `id<A, B>` is seen as the first: what it answers, A's
                // messages, is still answered.
                return protocols is [CTypedef first, ..] && translation.Protocols.TryGetValue(first.Name, out var protocol)
                    ? SpellObjCDecl(protocol, ProtocolName(protocol.Name), context)
                    : "AnyObject";

            case CPointer { Pointee: CTypedef named } when translation.Interfaces.TryGetValue(named.Name, out var objcClass):
                return SpellObjCDecl(objcClass, objcClass.Name, context);

            case CPointer { Pointee: CTypedef aliased } when ClassAliased(aliased.Name) is not null:
            {
                var typedef = translation.Typedefs[aliased.Name];
                Use(OwnerOf(typedef.File) ?? SystemOwner, typedef, context);
                return Identifier(aliased.Name);
            }

            case CPointer { Pointee: CObjCQualified { Base: CTypedef named } } when translation.Interfaces.TryGetValue(named.Name, out var generic):
                return SpellObjCDecl(generic, generic.Name, context);

            case CBlock block:
                return Synthesize(context, Suffixed(hint, "Block"), n => WriteBlock(n, block.Function, context));

            default:
                throw new Unsupported($"the object type {type}");
        }
    }

    /// <summary>A class or protocol named where it is used, which MUST be one that binds.</summary>
    private string SpellObjCDecl(CObjCContainer declared, string name, Context context)
    {
        if (!declared.IsDefinition)
            throw new Unsupported($"'{declared.Name}', which no header defines");
        if (OwnerOf(declared.File) is not { } owner)
            throw new Unsupported($"'{declared.Name}', which only the compiler declares");
        Use(owner, declared, context);
        return Identifier(name);
    }

    /// <summary>An object type inside a struct or behind a pointer: the pointer, which owns nothing.</summary>
    private string SpellUnmanaged(CType type, Context context, string hint)
    {
        // A Core Foundation typedef is its struct's pointer; CFTypeRef is `const void *`.
        if (type is CTypedef named && named.Name != "CFTypeRef" && IsCFTypedef(named.Name))
            return Spell(translation.Typedefs[named.Name].Type, context, hint);
        return "void*";
    }

    // ------------------------------------------------------------ Core Foundation

    /// <summary>
    /// A Core Foundation type: an object ARC counts, asked what it is by its
    /// CFTypeID. A mutable type derives from the immutable one pointing at
    /// the same struct, and shares its id.
    /// </summary>
    private string WriteCFType(CTypedefDecl typedef, Context context)
    {
        context.Imports.Add(ObjCModule);
        if (typedef.Name == "CFTypeRef")
            return "/// Any Core Foundation object.\n[CFType]\npublic extern objc class CFTypeRef { }\n";

        var tag = (CTag)((CPointer)typedef.Type).Pointee;
        var immutable = typedef.PointsToConst
            ? null
            : translation.Typedefs.Values.FirstOrDefault(t =>
                t.Name != typedef.Name && t.PointsToConst &&
                t.Type is CPointer { Pointee: CTag other } && other == tag);

        string baseName = immutable is not null
            ? SpellManaged(new CTypedef(immutable.Name), context, typedef.Name)
            : SpellManaged(new CTypedef("CFTypeRef"), context, typedef.Name);

        string function = TypeIDFunctionOf(typedef.Name);
        string attribute = immutable is null && translation.TypeIDFunctions.Contains(function)
            ? $"[CFType(\"{function}\")]"
            : "[CFType]";
        return $"{attribute}\npublic extern objc class {Identifier(typedef.Name)} : {baseName} {{ }}\n";
    }

    /// <summary>
    /// Core Foundation's Create rule, as clang reads it: a function whose
    /// name holds <c>Create</c> or <c>Copy</c> as a word hands over what it
    /// returns.
    /// </summary>
    public static bool FollowsCreateRule(string name)
    {
        for (int at = 0; at < name.Length; at++)
        {
            char c = name[at];
            if (c is not ('C' or 'c')) continue;
            if (c == 'c' && at > 0 && char.IsAsciiLetter(name[at - 1])) continue;

            string rest = name[(at + 1)..];
            int length = rest.StartsWith("reate", StringComparison.Ordinal) ? 5
                : rest.StartsWith("opy", StringComparison.Ordinal) ? 3
                : 0;
            if (length == 0) continue;

            int after = at + 1 + length;
            if (after == name.Length || !char.IsAsciiLetterLower(name[after])) return true;
        }

        return false;
    }

    /// <summary><c>CFRelease</c>, <c>CGColorRetain</c> and the like, which ARC's counting already does.</summary>
    private bool IsManualCounting(CFunctionDecl function, Context context) =>
        function.Name is "CFRetain" or "CFRelease" or "CFAutorelease" or "CFMakeCollectable" ||
        ((function.Name.EndsWith("Retain", StringComparison.Ordinal) || function.Name.EndsWith("Release", StringComparison.Ordinal)) &&
         function.Parameters is [{ Type: CTypedef named }] && IsCFTypedef(named.Name));

    // ------------------------------------------------------------ declarations

    /// <summary>
    /// The selector's method family, by clang's rule: <c>alloc</c>,
    /// <c>new</c>, <c>copy</c>, <c>mutableCopy</c>, or <c>init</c> on an
    /// instance method returning an object. One of these hands over what it
    /// returns without being told.
    /// </summary>
    private static bool ReturnsRetainedByFamily(string selector, bool isInstance, bool returnsObject)
    {
        string name = selector.TrimStart('_');
        foreach (string family in (string[])["alloc", "new", "copy", "mutableCopy", "init"])
        {
            if (!name.StartsWith(family, StringComparison.Ordinal)) continue;
            if (name.Length > family.Length && char.IsAsciiLetterLower(name[family.Length])) continue;
            return family != "init" || (isInstance && returnsObject);
        }

        return false;
    }

    /// <summary>What a type synthesized for a member is named after: its class, or its protocol as declared.</summary>
    private string HintOwner(string owner) =>
        owner.StartsWith("protocol ", StringComparison.Ordinal) ? ProtocolName(owner["protocol ".Length..]) : owner;

    /// <summary>The version a declaration appeared in, when that is later than the oldest built for.</summary>
    private static string? Later(Availability availability) =>
        availability.Introduced is { } introduced && IsAfterDeploymentTarget(introduced) ? introduced : null;

    private static bool IsAllocFamily(string selector) =>
        selector.TrimStart('_') is var name && name.StartsWith("alloc", StringComparison.Ordinal) &&
        (name.Length == 5 || !char.IsAsciiLetterLower(name[5]));

    /// <summary><c>initWithFrame:display:</c> is <c>InitWithFrameDisplay</c>.</summary>
    public static string MemberName(string selector)
    {
        var name = new StringBuilder();
        foreach (string piece in selector.Split(':', StringSplitOptions.RemoveEmptyEntries))
        {
            int letter = 0;
            while (letter < piece.Length && piece[letter] == '_') letter++;
            name.Append(piece[..letter]);
            if (letter < piece.Length) name.Append(char.ToUpperInvariant(piece[letter])).Append(piece[(letter + 1)..]);
        }

        return name.ToString();
    }

    private string? WriteObjCContainer(CObjCContainer container, Context context)
    {
        if (!container.IsDefinition) return null;
        context.Imports.Add(ObjCModule);

        foreach (string parameter in container.TypeParameters) context.TypeParameters.Add(parameter);
        context.InObjC = true;

        string owner;
        var header = new StringBuilder();
        var bases = new List<string>();

        switch (container)
        {
            case CObjCInterface objcClass:
                owner = objcClass.Name;
                if (objcClass.Super is { } super)
                {
                    if (!translation.Interfaces.TryGetValue(super, out var superclass))
                        throw new Unsupported($"its superclass '{super}', which no header declares");
                    bases.Add(SpellObjCDecl(superclass, superclass.Name, context));
                }
                else header.Append("[ObjCRoot]\n");
                header.Append($"public extern objc class {Identifier(objcClass.Name)}");
                break;

            case CObjCCategory category:
                if (!translation.Interfaces.TryGetValue(category.Class, out var extended))
                    throw new Unsupported($"it adds to '{category.Class}', which no header declares");
                owner = extended.Name;
                SpellObjCDecl(extended, extended.Name, context);
                if (category.Name.Length > 0) header.Append($"/// {category.Name}, a category of {extended.Name}.\n");
                header.Append($"public extern objc class {Identifier(extended.Name)}");
                foreach (string parameter in extended.TypeParameters) context.TypeParameters.Add(parameter);
                break;

            default:
                owner = "protocol " + container.Name;
                string name = ProtocolName(container.Name);
                if (name != container.Name) header.Append($"[ObjCName(\"{container.Name}\")]\n");
                header.Append($"public objc interface {Identifier(name)}");
                break;
        }

        // A protocol that does not bind is left off the list: the object
        // still answers its messages, and nothing else is lost.
        foreach (string adopted in container.Protocols)
        {
            if (!translation.Protocols.TryGetValue(adopted, out var protocol) || protocol.Availability.Unavailable) continue;
            if (!_names.Adopt(owner, adopted)) continue;
            try
            {
                bases.Add(SpellObjCDecl(protocol, ProtocolName(protocol.Name), context));
            }
            catch (Unsupported)
            {
            }
        }

        if (bases.Count > 0) header.Append(" : ").Append(string.Join(", ", bases.Distinct()));

        var body = new StringBuilder();
        bool isProtocol = container is CObjCProtocol;
        context.Introduced = Later(container.Availability);
        if (container is CObjCInterface)
            context.Runtime.Add(new RuntimeCheck(owner, null, false, context.Introduced));
        foreach (var property in container.Properties)
            WriteMember(owner, container, () => WriteProperty(owner, property, isProtocol, context), property.Name, body);
        foreach (var method in container.Methods)
            WriteMember(owner, container, () => WriteMethod(owner, container, method, isProtocol, context), method.Selector, body);

        return body.Length == 0
            ? header.Append(" { }\n").ToString()
            : header.Append("\n{\n").Append(body).Append("}\n").ToString();
    }

    /// <summary>One member, or its reason for being left out, which is kept with the rest.</summary>
    private void WriteMember(string owner, CObjCContainer container, Func<string?> write, string name, StringBuilder body)
    {
        try
        {
            if (write() is { } text) body.Append(text);
        }
        catch (Unsupported unsupported)
        {
            Skips.Add(new Skipped(OwnerOf(container.File) ?? SystemOwner, HeaderOf(container.File),
                $"{owner.Replace("protocol ", "")}.{name}", unsupported.Message));
        }
    }

    private string? WriteProperty(string owner, CObjCProperty property, bool isProtocol, Context context)
    {
        if (property.Availability.Unavailable) return null;

        string type = SpellValue(property.Type, property.Nullability, context, HintOwner(owner) + MemberName(property.Name));
        var selectors = property.IsReadOnly
            ? (IReadOnlyList<string>)[property.GetterSelector]
            : [property.GetterSelector, property.SetterSelector];

        string? name = _names.Claim(owner, Capitalize(property.Name), selectors, property.IsClass, isProperty: true, 0);
        if (name is null) return null;

        if (!isProtocol)
            foreach (string asked in selectors)
                context.Runtime.Add(new RuntimeCheck(owner, asked, !property.IsClass, Later(property.Availability) ?? context.Introduced));

        string selector = string.Join(", ", selectors.Select(s => $"\"{s}\""));
        string accessors = property.IsReadOnly ? "{ get; }" : "{ get; set; }";
        string optional = property.IsOptional ? "[Optional] " : "";
        string visibility = isProtocol ? "" : "public ";
        // A protocol's class member is one each adopting class answers.
        string isStatic = !property.IsClass ? "" : isProtocol ? "static abstract " : "static ";
        return Indented(Documentation(property.Availability)) +
               $"    {optional}[Selector({selector})] {visibility}{isStatic}{type} {Identifier(name)} {accessors}\n";
    }

    private string? WriteMethod(string owner, CObjCContainer container, CObjCMethod method, bool isProtocol, Context context)
    {
        if (method.Availability.Unavailable) return null;
        if (method.Parameters.FirstOrDefault(p => p.IsConsumed) is { } consumed)
            throw new Unsupported($"it takes ownership of '{consumed.Name}', which a binding cannot hand over");

        string memberName = MemberName(method.Selector);
        string hint = HintOwner(owner) + memberName;

        // `alloc` fails by stopping the program, never by answering nil; what
        // the unaudited objc/NSObject.h leaves unsaid is that.
        var resultNullability = method.ResultNullability == Nullability.Unspecified && IsAllocFamily(method.Selector)
            ? Nullability.NonNull
            : method.ResultNullability;
        string result = Canonical(method.Result) is CBuiltin { Name: "void" }
            ? "void"
            : SpellValue(method.Result, resultNullability, context, hint + "Result");

        var parameters = new List<string>();
        var parameterNames = ParameterNames(method.Parameters);
        for (int i = 0; i < method.Parameters.Count; i++)
        {
            var parameter = method.Parameters[i];
            string name = parameterNames[i];

            // `NSError **error`: an object the callee stores for the caller,
            // which the call writes back.
            if (parameter is { IsAutoreleasing: true, Type: CPointer { Pointee: var stored } } && IsManaged(stored, context))
            {
                parameters.Add($"out {SpellManaged(stored, context, hint + Capitalize(name))}? {name}");
                continue;
            }

            string type = SpellValue(parameter.Type, parameter.Nullability, context, hint + Capitalize(name));
            parameters.Add($"{type} {name}");
        }

        string? claimed = _names.Claim(owner, memberName, [method.Selector], !method.IsInstance, isProperty: false, parameters.Count);
        if (method.IsVariadic) parameters.Add("...");
        if (claimed is null) return null;

        bool returnsObject = IsManaged(method.Result, context);
        bool byFamily = ReturnsRetainedByFamily(method.Selector, method.IsInstance, returnsObject);
        string ownership = (method.ReturnsRetained, returnsObject) switch
        {
            (true, true) when !byFamily => "[ReturnsRetained] ",
            (false, true) when byFamily => "[ReturnsNotRetained] ",
            _ => "",
        };

        if (!isProtocol)
            context.Runtime.Add(new RuntimeCheck(owner, method.Selector, method.IsInstance, Later(method.Availability) ?? context.Introduced));

        string optional = method.IsOptional ? "[Optional] " : "";
        string visibility = isProtocol ? "" : "public ";
        string isStatic = method.IsInstance ? "" : isProtocol ? "static abstract " : "static ";
        return Indented(Documentation(method.Availability)) +
               $"    {optional}{ownership}[Selector(\"{method.Selector}\")] {visibility}{isStatic}{result} " +
               $"{Identifier(claimed)}({string.Join(", ", parameters)});\n";
    }

    /// <summary>A type where a value is: an object with its <c>?</c>, anything else as it is.</summary>
    private string SpellValue(CType type, Nullability nullability, Context context, string hint)
    {
        if (context.InObjC && type is CTypedef { Name: "BOOL" }) return "bool";
        return Spell(type, context, hint, Placement.Value, nullability);
    }

    private static string Capitalize(string name)
    {
        string bare = name.TrimStart('@');
        return bare.Length == 0 ? bare : char.ToUpperInvariant(bare[0]) + bare[1..];
    }

    private static string Indented(string lines) =>
        lines.Length == 0 ? "" : string.Concat(lines.Split('\n', StringSplitOptions.RemoveEmptyEntries).Select(l => "    " + l + "\n"));
}
