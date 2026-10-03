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

using Stainless.Source;
using Stainless.Syntax;

namespace Stainless.Binding;

/// <summary>
/// Objective-C: protocols, classes that exist already, and the selectors a
/// call through either sends.
///
/// Every member of an objc type names its selector with <c>[Selector]</c>;
/// nothing is derived from the Stainless name. What the selector says beyond
/// itself is its method family, which decides who owns a returned object.
/// </summary>
public sealed partial class Binder
{
    /// <summary>Every objc class in the program, imported or defined, kept out of <c>_classes</c>.</summary>
    private readonly List<ClassTypeSymbol> _objcClasses = [];

    /// <summary>Every protocol in the program.</summary>
    private readonly List<ObjCProtocolTypeSymbol> _objcProtocols = [];

    /// <summary>A protocol or an objc class, imported or defined.</summary>
    internal static bool IsObjCType(TypeSymbol? type) =>
        type is ObjCProtocolTypeSymbol or ClassTypeSymbol { IsObjC: true };

    /// <summary>An Objective-C reference, optional or not.</summary>
    internal static bool IsObjCReference(TypeSymbol? type) =>
        type is not null && IsObjCType(type.AsReference() ?? type);

    private bool _reportedNotDarwin;

    /// <summary>
    /// Objective-C exists on Apple's systems alone. Declarations bind
    /// anywhere, so a binding compiles on every host; a program that sends a
    /// message or asks an object what it is is refused, once, elsewhere.
    /// </summary>
    private void RequireDarwin(SourceSpan span)
    {
        if (TargetPlatform.Current.IsDarwin || _reportedNotDarwin) return;

        _reportedNotDarwin = true;
        diagnostics.Error("SL0915", span,
            $"this sends an Objective-C message, and the target is {TargetPlatform.Current.Name}; " +
            "Objective-C is Apple's runtime, so a program using it is built for 'arm64-macos' " +
            "or 'x64-macos'. Keep the code behind '#if MACOS' to build it elsewhere");
    }

    /// <summary>
    /// A type whose selector-bearing members are messages and nothing else: a
    /// protocol, or a class that already exists. Neither has storage or a body
    /// of its own to call.
    /// </summary>
    internal static bool IsDescribedOnly(TypeSymbol? type) =>
        type is ObjCProtocolTypeSymbol or ClassTypeSymbol { ObjC: ObjCClassKind.Imported };

    /// <summary>The attributes a member of an objc type may carry, which the compiler reads itself.</summary>
    private static bool IsObjCMemberAttribute(AttributeSyntax attribute) =>
        attribute.Name.Last is "Selector" or "Optional" or "ReturnsRetained" or "ReturnsNotRetained";

    /// <summary>
    /// Says which declarations <c>objc</c> and <c>extern</c> may be written on,
    /// before a symbol is made for one.
    /// </summary>
    private void CheckObjCModifiers(TypeDeclSyntax declaration)
    {
        bool objc = declaration.Modifiers.HasFlag(Modifiers.Objc);
        bool external = declaration.Modifiers.HasFlag(Modifiers.Extern);

        if (objc && declaration.Kind is not (TypeDeclKind.Class or TypeDeclKind.Interface))
            diagnostics.Error("SL0900", declaration.Span,
                $"'objc' goes before 'interface', 'class' or 'closure', and '{declaration.Name}' " +
                "is none of them; Objective-C has protocols, classes and blocks, and nothing else " +
                "it holds by reference");

        if (objc && declaration.Modifiers.HasFlag(Modifiers.Com))
            diagnostics.Error("SL0900", declaration.Span,
                $"'{declaration.Name}' cannot be both 'com' and 'objc'; the two are different " +
                "object models, counted by different calls");

        if (external && !(objc && declaration.Kind == TypeDeclKind.Class))
            diagnostics.Error("SL0901", declaration.Span,
                declaration.Kind == TypeDeclKind.Interface
                    ? $"'{declaration.Name}' is a protocol, which is only ever described, so " +
                      "'extern' says nothing; write 'objc interface'"
                    : $"'extern' before a type means an Objective-C class that already exists, " +
                      $"and '{declaration.Name}' is not one; write 'extern objc class'");

        if (objc && declaration.TypeParameters.Count > 0)
            diagnostics.Error("SL0900", declaration.Span,
                $"'{declaration.Name}' cannot be generic: an Objective-C class or protocol is " +
                "one runtime object, and Objective-C's generics are a fact about its headers");
    }

    // ------------------------------------------------------------- selectors

    /// <summary>
    /// Reads what was written above a method, which only a member of an objc
    /// type may have: <c>[Selector]</c> and the few words about ownership and
    /// optionality that go with it.
    /// </summary>
    private void ReadMethodAttributes(
        FunctionSymbol symbol, NamedTypeSymbol? type, IReadOnlyList<AttributeSyntax> attributes,
        bool hasBody, SourceSpan span)
    {
        if (!IsObjCType(type))
        {
            if (attributes.Count > 0)
                diagnostics.Error("SL0728", attributes[0].Span,
                    $"'[{attributes[0].Name.Last}]' cannot be written on a method. An attribute " +
                    "goes on a type, an enum, a field, a property, an event or a static, which are " +
                    "the declarations something reads one back from; a method of an objc type " +
                    "takes '[Selector]'");
            return;
        }

        int parameters = symbol.Parameters.Count(p => !p.IsThis);
        string? selector = ReadSelector(attributes, symbol.Name, parameters, out var selectorSpan);

        ReadOwnershipWords(symbol, attributes, type!, selector);

        if (selector is null)
        {
            // A protocol and an imported class have nothing but messages: a
            // member with no selector there has nothing a call could do. One
            // that wrote a selector wrongly has already been told so.
            bool wroteOne = attributes.Any(a => a.Name.Last == "Selector");
            if (IsDescribedOnly(type) && !(type is ClassTypeSymbol && hasBody) && !wroteOne)
                diagnostics.Error("SL0902", span,
                    $"'{type!.Name}.{symbol.Name}' has no '[Selector(\"...\")]'. A call to a " +
                    $"member of {(type is ObjCProtocolTypeSymbol ? "a protocol" : "an Objective-C class")} " +
                    "sends a message, and the selector is the message; nothing is derived from " +
                    "the Stainless name",
                    type);
            return;
        }

        if (type is ObjCProtocolTypeSymbol && hasBody)
            diagnostics.Error("SL0903", span,
                $"'{type.Name}.{symbol.Name}' has a body, and a protocol member has none: " +
                "Objective-C has no default implementations, so an object answers the message " +
                "with its own method or not at all",
                type);

        if (type is ClassTypeSymbol { ObjC: ObjCClassKind.Imported } && hasBody)
            diagnostics.Error("SL0903", selectorSpan,
                $"'{type.Name}.{symbol.Name}' sends '{selector}' to a class that already exists, " +
                "so it has no body here; a member of an 'extern objc class' with a body is a " +
                "Stainless helper and takes no selector",
                type);

        symbol.Selector = selector;
        ApplyFamily(symbol, selector, attributes);
        CheckObjCSignature(symbol, span);
    }

    /// <summary>
    /// The selector one <c>[Selector("...")]</c> names, checked against the
    /// number of parameters it has to carry, or null when none was written.
    /// </summary>
    private string? ReadSelector(
        IReadOnlyList<AttributeSyntax> attributes, string member, int parameters, out SourceSpan span)
    {
        span = default;
        var written = attributes.Where(a => a.Name.Last == "Selector").ToList();
        if (written.Count == 0) return null;

        span = written[0].Span;
        if (written.Count > 1)
            diagnostics.Error("SL0904", written[1].Span,
                $"'{member}' has more than one '[Selector]'; a member sends one message");

        if (written[0].Arguments.Count != 1 ||
            ConstantValue(written[0].Arguments[0], _builtins.String) is not string text)
        {
            diagnostics.Error("SL0904", written[0].Span,
                "'[Selector]' on a method takes one string literal, as in " +
                "'[Selector(\"initWithFrame:\")]'");
            return null;
        }

        return CheckSelectorText(text, parameters, member, written[0].Arguments[0].Span) ? text : null;
    }

    /// <summary>
    /// Whether <paramref name="selector"/> is one Objective-C could send with
    /// <paramref name="parameters"/> arguments: one colon each, and none for
    /// none. The colons are what carry the arguments, so a mismatch is a
    /// message no object answers in the shape the call would make.
    /// </summary>
    private bool CheckSelectorText(string selector, int parameters, string member, SourceSpan span)
    {
        bool wellFormed = selector.Length > 0 &&
                          selector.All(c => char.IsAsciiLetterOrDigit(c) || c is '_' or ':') &&
                          !char.IsAsciiDigit(selector[0]) && selector[0] != ':';
        if (!wellFormed)
        {
            diagnostics.Error("SL0904", span,
                $"'{selector}' is not a selector; one is letters, digits and underscores, with a " +
                "colon after each piece that takes an argument");
            return false;
        }

        int colons = selector.Count(c => c == ':');
        if (colons == parameters) return true;

        diagnostics.Error("SL0905", span,
            $"'{selector}' takes {colons} argument{(colons == 1 ? "" : "s")} and '{member}' has " +
            $"{parameters}; a selector carries one argument after each colon, so the two MUST " +
            "agree");
        return false;
    }

    /// <summary>
    /// <c>[Optional]</c>, <c>[ReturnsRetained]</c> and <c>[ReturnsNotRetained]</c>,
    /// and anything else written on a member of an objc type, which is refused.
    /// </summary>
    private void ReadOwnershipWords(
        FunctionSymbol symbol, IReadOnlyList<AttributeSyntax> attributes,
        NamedTypeSymbol type, string? selector)
    {
        foreach (var attribute in attributes)
        {
            switch (attribute.Name.Last)
            {
                case "Selector":
                    break;

                case "Optional":
                    if (type is ObjCProtocolTypeSymbol) symbol.IsObjCOptional = true;
                    else
                        diagnostics.Error("SL0906", attribute.Span,
                            $"'[Optional]' says an object may not answer a protocol's member, and " +
                            $"'{type.Name}' is a class, whose members it answers by having them",
                            type);
                    break;

                case "ReturnsRetained":
                case "ReturnsNotRetained":
                    if (selector is null)
                        diagnostics.Error("SL0906", attribute.Span,
                            $"'[{attribute.Name.Last}]' is about what a message hands back, and " +
                            $"'{symbol.Name}' sends none",
                            type);
                    break;

                default:
                    diagnostics.Error("SL0906", attribute.Span,
                        $"'[{attribute.Name.Last}]' means nothing on a member of an objc type; it " +
                        "takes '[Selector]', '[Optional]', '[ReturnsRetained]' and " +
                        "'[ReturnsNotRetained]'",
                        type);
                    break;
            }
        }
    }

    /// <summary>
    /// Ownership from the selector's method family, as clang reads it, and
    /// then from <c>[ReturnsRetained]</c> or <c>[ReturnsNotRetained]</c>.
    /// </summary>
    private static void ApplyFamily(
        FunctionSymbol symbol, string selector, IReadOnlyList<AttributeSyntax>? attributes = null)
    {
        var family = FamilyOf(selector);

        // An init is a message to an object, about that object: on a class
        // method, or one that returns no object, the word is only a name.
        if (family == "init" &&
            (symbol.IsStatic || !IsObjCType(symbol.ReturnType.AsReference() ?? symbol.ReturnType)))
            family = null;

        symbol.ConsumesSelf = family == "init";
        symbol.ReturnsRetained = family is not null;

        foreach (var attribute in attributes ?? [])
        {
            if (attribute.Name.Last == "ReturnsRetained") symbol.ReturnsRetained = true;
            if (attribute.Name.Last == "ReturnsNotRetained") symbol.ReturnsRetained = false;
        }
    }

    /// <summary>
    /// The method family a selector is in, or null: <c>alloc</c>, <c>new</c>,
    /// <c>copy</c>, <c>mutableCopy</c> or <c>init</c>.
    ///
    /// It is clang's rule. Leading underscores are skipped; the selector MUST
    /// then begin with the family's word, and what follows the word MUST NOT be
    /// a lower-case letter -- so <c>initWithFrame:</c> is an init and
    /// <c>initialize</c> is not, and <c>newer</c> is not a new.
    /// </summary>
    public static string? FamilyOf(string selector)
    {
        string name = selector.TrimStart('_');
        foreach (string family in (string[])["alloc", "new", "copy", "mutableCopy", "init"])
        {
            if (!name.StartsWith(family, StringComparison.Ordinal)) continue;
            if (name.Length > family.Length && char.IsAsciiLetterLower(name[family.Length])) continue;
            return family;
        }

        return null;
    }

    /// <summary>
    /// Reads <c>[Selector("title")]</c> or <c>[Selector("title", "setTitle:")]</c>
    /// off a property of an objc type. An accessor cannot carry an attribute,
    /// so the property names both of its messages.
    /// </summary>
    private void ReadPropertySelectors(PropertySymbol property, NamedTypeSymbol type, PropertyDeclSyntax declaration)
    {
        if (!IsObjCType(type)) return;

        var written = declaration.Attributes.Where(a => a.Name.Last == "Selector").ToList();
        foreach (var attribute in declaration.Attributes)
            if (attribute.Name.Last is "Optional" && type is ObjCProtocolTypeSymbol)
            {
                if (property.Getter is { } optionalGetter) optionalGetter.IsObjCOptional = true;
                if (property.Setter is { } optionalSetter) optionalSetter.IsObjCOptional = true;
            }
            else if (attribute.Name.Last is "ReturnsRetained" or "ReturnsNotRetained" or "Optional")
                diagnostics.Error("SL0906", attribute.Span,
                    $"'[{attribute.Name.Last}]' is not written on a property of '{type.Name}'",
                    type);

        if (written.Count == 0)
        {
            if (IsDescribedOnly(type))
                diagnostics.Error("SL0902", declaration.Span,
                    $"'{type.Name}.{property.Name}' has no '[Selector(\"...\")]'. A property of " +
                    $"{(type is ObjCProtocolTypeSymbol ? "a protocol" : "an Objective-C class")} " +
                    "is a pair of messages, so it names them: '[Selector(\"title\", \"setTitle:\")]', " +
                    "or the getter's alone when there is no setter",
                    type);
            return;
        }

        if (written.Count > 1)
            diagnostics.Error("SL0904", written[1].Span,
                $"'{property.Name}' has more than one '[Selector]'; one names both messages");

        var arguments = written[0].Arguments;
        int wanted = property.Setter is null ? 1 : 2;
        var texts = arguments.Select(a => ConstantValue(a, _builtins.String) as string).ToList();
        if (arguments.Count != wanted || texts.Any(t => t is null))
        {
            diagnostics.Error("SL0904", written[0].Span,
                property.Setter is null
                    ? $"'{property.Name}' has no setter, so its '[Selector]' names the getter's " +
                      "message alone, as in '[Selector(\"title\")]'"
                    : $"'{property.Name}' has a getter and a setter, so its '[Selector]' names " +
                      "both messages, as in '[Selector(\"title\", \"setTitle:\")]'");
            return;
        }

        int indices = property.Getter?.Parameters.Count(p => !p.IsThis) ?? 0;
        if (property.Getter is { } getter &&
            CheckSelectorText(texts[0]!, indices, property.Name, arguments[0].Span))
        {
            getter.Selector = texts[0];
            ApplyFamily(getter, texts[0]!);
            CheckObjCSignature(getter, declaration.Span);
        }

        if (property.Setter is { } setter &&
            CheckSelectorText(texts[1]!, indices + 1, property.Name, arguments[1].Span))
        {
            setter.Selector = texts[1];
            CheckObjCSignature(setter, declaration.Span);
        }
    }

    // ------------------------------------------------------------- conversions

    /// <summary>
    /// A conversion with an Objective-C reference on either side. Seeing an
    /// object as its superclass, a protocol it adopts or <c>AnyObject</c> is
    /// the same pointer; the other direction asks the object.
    /// </summary>
    /// <returns>
    /// True when the pairing is Objective-C's to decide, with
    /// <paramref name="kind"/> the answer or null for none. False leaves it to
    /// the rules for everything else -- <c>C?</c> to <c>C</c> above all.
    /// </returns>
    private bool ClassifiesObjC(TypeSymbol from, TypeSymbol to, bool explicitCast, out ConversionKind? kind)
    {
        kind = null;

        if (from is PointerTypeSymbol && IsObjCType(to))
        {
            kind = explicitCast ? ConversionKind.ObjCAdopt : null;
            return true;
        }

        if (IsObjCType(from) && to is PointerTypeSymbol)
        {
            kind = explicitCast ? ConversionKind.PointerCast : null;
            return true;
        }

        // Into a weak reference, which is a box made for the object.
        if (IsObjCReference(from) && to is WeakTypeSymbol { Element: var weakElement } &&
            IsObjCType(weakElement))
        {
            kind = IsObjCKindOf(from.AsReference() ?? from, weakElement) ? ConversionKind.ReferenceToWeak : null;
            return true;
        }

        if (IsObjCType(from) && to is OptionalTypeSymbol { Element: var optional })
        {
            kind = IsObjCType(optional) && IsObjCKindOf(from, optional)
                ? ConversionKind.ReferenceToOptional
                : null;
            return true;
        }

        if (from is OptionalTypeSymbol { Element: var fromElement } && IsObjCType(fromElement) &&
            to is OptionalTypeSymbol { Element: var toElement } && IsObjCType(toElement))
        {
            kind = IsObjCKindOf(fromElement, toElement) ? ConversionKind.ObjCUpcast : null;
            return true;
        }

        // One side Objective-C and the other not: nothing converts, except a
        // null or an optional reaching an objc type, which the general rules
        // know how to check.
        if (IsObjCType(from) != IsObjCType(to))
            return IsObjCType(from) || from is not (NullType or OptionalTypeSymbol);

        if (!IsObjCType(from)) return false;

        if (IsObjCKindOf(from, to))
        {
            kind = ConversionKind.ObjCUpcast;
            return true;
        }

        // Down to a class asks isKindOfClass:, and to a protocol asks
        // conformsToProtocol:. A class can always be asked, since a subclass
        // may adopt a protocol its superclass does not.
        bool couldBe = to is ObjCProtocolTypeSymbol ||
                       (to is ClassTypeSymbol toClass &&
                        (from is ObjCProtocolTypeSymbol ||
                         (from is ClassTypeSymbol fromClass && toClass.DerivesFrom(fromClass))));

        kind = explicitCast && couldBe && to != _builtins.AnyObject ? ConversionKind.ObjCDowncast : null;
        return true;
    }

    /// <summary>
    /// True when every <paramref name="from"/> is a <paramref name="to"/>:
    /// the same type, a superclass, an adopted protocol, or <c>AnyObject</c>.
    /// </summary>
    private bool IsObjCKindOf(TypeSymbol from, TypeSymbol to) => (from, to) switch
    {
        _ when from == to => true,
        (_, ObjCProtocolTypeSymbol any) when any == _builtins.AnyObject => true,
        (ClassTypeSymbol fromClass, ClassTypeSymbol toClass) => fromClass.DerivesFrom(toClass),
        (ClassTypeSymbol fromClass, ObjCProtocolTypeSymbol protocol) => fromClass.AdoptsObjC(protocol),
        (ObjCProtocolTypeSymbol fromProtocol, ObjCProtocolTypeSymbol protocol) => fromProtocol.Adopts(protocol),
        _ => false,
    };

    // ------------------------------------------------------------- sends

    /// <summary>
    /// A call that sends a message. A class message goes to the class the
    /// call named, and a <c>Self</c> result has the receiver's type.
    /// </summary>
    private BoundExpression SendMessage(
        SourceSpan span, FunctionSymbol function, BoundExpression? receiver,
        IReadOnlyList<BoundExpression> arguments, IReadOnlyList<int>? order,
        bool nonVirtual, NamedTypeSymbol? named)
    {
        RequireDarwin(span);

        var classReceiver = function.IsStatic
            ? named as ClassTypeSymbol ?? function.ContainingType as ClassTypeSymbol
            : null;

        var call = new BoundCall(span, function, receiver, arguments)
        {
            IsNonVirtual = nonVirtual,
            EvaluationOrder = order,
            ClassReceiver = classReceiver,
        };

        if (!function.ReturnsSelf) return call;

        TypeSymbol? actual = function.IsStatic ? classReceiver : receiver?.Type;
        if (actual is null || actual == function.ReturnType) return call;

        return new BoundConversion(span, actual, call, ConversionKind.ObjCSelf);
    }

    /// <summary>
    /// A method held in a closure or a delegate without being called. A
    /// message has no function to point at, and a closure counts its object
    /// with <c>sl_retain</c>, which an Objective-C object cannot take; a lambda
    /// that sends the message is what to write instead.
    /// </summary>
    private bool RefuseObjCReference(FunctionSymbol chosen, BoundExpression? receiver, SourceSpan span)
    {
        if (!chosen.IsMessage && !IsObjCReference(receiver?.Type)) return false;

        diagnostics.Error("SL0913", span,
            $"'{chosen.Name}' is a member of an Objective-C type, so it cannot be held without " +
            "being called: a message has no function to point at, and the object it goes to " +
            "is not counted the way a closure counts its own. Write a lambda that sends it, " +
            $"such as '() => x.{chosen.Name}()'");
        return true;
    }

    // ------------------------------------------------------------- signatures

    /// <summary>
    /// Refuses a parameter or result Objective-C cannot carry: a Stainless
    /// object, a <c>String</c>, an array, a closure, or a struct holding any
    /// of them. What crosses is what C can spell, plus objc references.
    /// </summary>
    private void CheckObjCSignature(FunctionSymbol symbol, SourceSpan span)
    {
        foreach (var parameter in symbol.Parameters.Where(p => !p.IsThis))
            if (ObjCSignatureProblem(parameter.Type) is { } why)
                diagnostics.Error("SL0907", span,
                    $"'{parameter.Name}' of '{symbol.Name}' is {why}, which an Objective-C " +
                    "message cannot carry; it takes what C can spell and Objective-C objects",
                    parameter.Type);

        if (ObjCSignatureProblem(symbol.ReturnType) is { } result)
            diagnostics.Error("SL0907", span,
                $"'{symbol.Name}' returns {result}, which an Objective-C message cannot carry; " +
                "it takes what C can spell and Objective-C objects",
                symbol.ReturnType);
    }

    /// <summary>Why <paramref name="type"/> cannot cross an objc message, or null when it can.</summary>
    private static string? ObjCSignatureProblem(TypeSymbol type)
    {
        if (type.IsError() || type.IsVoid()) return null;

        var element = type.AsReference() ?? type;
        if (IsObjCType(element)) return null;

        return type switch
        {
            PointerTypeSymbol { Element: var pointee } when IsObjCReference(pointee) =>
                "a pointer to an Objective-C reference, which nothing would count (write 'out' " +
                "or 'ref', which the call writes back)",
            WeakTypeSymbol => "a weak reference",
            ClassTypeSymbol { SimpleName: "String" } => "a 'String' (an 'NSString' is the one it takes)",
            OptionalTypeSymbol { Element: ClassTypeSymbol { SimpleName: "String" } } =>
                "a 'String' (an 'NSString' is the one it takes)",
            _ when type.IsReferenceType || type is OptionalTypeSymbol => $"'{type.Name}', a Stainless reference",
            StructTypeSymbol when type.CarriesReferences() => $"'{type.Name}', a struct holding references",
            _ => null,
        };
    }

    // ------------------------------------------------------------- types

    /// <summary>
    /// Reads <c>[ObjCName]</c> and <c>[ObjCRoot]</c> off a type and returns
    /// what is left for the ordinary attribute machinery.
    /// </summary>
    private IReadOnlyList<AttributeSyntax> BindObjCTypeAttributes(
        NamedTypeSymbol type, TypeDeclSyntax declaration, IReadOnlyList<AttributeSyntax> written)
    {
        var mine = written.Where(a => a.Name.Last is "ObjCName" or "ObjCRoot").ToList();
        if (mine.Count == 0) return written;

        foreach (var attribute in mine)
        {
            if (!IsObjCType(type))
            {
                diagnostics.Error("SL0908", attribute.Span,
                    $"'[{attribute.Name.Last}]' is about an Objective-C class or protocol, and " +
                    $"'{type.Name}' is neither",
                    type);
                continue;
            }

            if (attribute.Name.Last == "ObjCRoot")
            {
                if (type is ClassTypeSymbol { ObjC: ObjCClassKind.Imported } root && attribute.Arguments.Count == 0)
                    root.IsObjCRoot = true;
                else
                    diagnostics.Error("SL0908", attribute.Span,
                        type is ClassTypeSymbol { ObjC: ObjCClassKind.Defined }
                            ? $"'{type.Name}' is defined here, and a root class is one the " +
                              "runtime's own classes are built on; derive from 'NSObject' instead"
                            : $"'[ObjCRoot]' takes nothing and goes on an 'extern objc class'",
                        type);
                continue;
            }

            if (attribute.Arguments.Count != 1 ||
                ConstantValue(attribute.Arguments[0], _builtins.String) is not string name ||
                name.Length == 0 || !name.All(c => char.IsAsciiLetterOrDigit(c) || c is '_' or '.'))
            {
                diagnostics.Error("SL0908", attribute.Span,
                    "'[ObjCName]' takes one string literal, the name the Objective-C runtime " +
                    "knows: '[ObjCName(\"NSObject\")]'",
                    type);
                continue;
            }

            if (type is ObjCProtocolTypeSymbol protocol) protocol.RuntimeName = name;
            else ((ClassTypeSymbol)type).ObjCRuntimeName = name;
        }

        return written.Except(mine).ToList();
    }

    /// <summary>
    /// A name in an objc type's base list, or an objc type in anyone's.
    /// Objective-C's two kinds take part only with each other: a protocol
    /// adopts protocols, and a class has one superclass and adopts protocols.
    /// </summary>
    private void BindObjCBase(NamedTypeSymbol type, TypeSymbol resolved, SourceSpan span, bool isFirst)
    {
        switch (type, resolved)
        {
            case (ObjCProtocolTypeSymbol protocol, ObjCProtocolTypeSymbol adopted):
                if (adopted == protocol || adopted.Adopts(protocol))
                    diagnostics.Error("SL0910", span,
                        $"'{protocol.Name}' and '{adopted.Name}' adopt each other",
                        protocol, adopted);
                else if (protocol.Bases.Contains(adopted))
                    diagnostics.Warning("SL0304", span,
                        $"'{protocol.Name}' already lists '{adopted.Name}'", protocol, adopted);
                else
                    protocol.Bases.Add(adopted);
                return;

            case (ClassTypeSymbol { IsObjC: true } classType, ClassTypeSymbol { IsObjC: true } superclass):
                // The superclass's own list first: a cycle is found there, and
                // a chain is walked whole only once each link is settled.
                if (_typeSyntax.TryGetValue(superclass, out var entry))
                    ResolveImplements(superclass, entry.Declaration, entry.Scope);

                if (!isFirst)
                    diagnostics.Error("SL0910", span,
                        $"'{superclass.Name}' is a class, so it is '{classType.Name}''s superclass " +
                        "and goes first in the list, before the protocols",
                        classType, superclass);
                else if (superclass == classType || superclass.DerivesFrom(classType))
                    diagnostics.Error("SL0910", span,
                        $"'{classType.Name}' and '{superclass.Name}' derive from each other",
                        classType, superclass);
                else
                    classType.BaseClass = superclass;
                return;

            case (ClassTypeSymbol { IsObjC: true } classType, ObjCProtocolTypeSymbol adopted):
                if (classType.ObjCProtocols.Contains(adopted))
                    diagnostics.Warning("SL0304", span,
                        $"'{classType.Name}' already lists '{adopted.Name}'", classType, adopted);
                else
                    classType.ObjCProtocols.Add(adopted);
                return;
        }

        string why = (type, resolved) switch
        {
            (ObjCProtocolTypeSymbol, _) =>
                $"'{type.Name}' is a protocol, and a protocol adopts protocols; " +
                $"'{resolved.Name}' is not one",
            (ClassTypeSymbol { IsObjC: true }, ClassTypeSymbol) =>
                $"'{type.Name}' is an Objective-C class, and '{resolved.Name}' is a Stainless " +
                "one; an Objective-C object is laid out by the Objective-C runtime and has no " +
                "Stainless header for a Stainless class to begin with",
            (ClassTypeSymbol { IsObjC: true }, _) =>
                $"'{type.Name}' is an Objective-C class, and '{resolved.Name}' is not a protocol; " +
                "a Stainless interface is dispatched through a Stainless header, which an " +
                "Objective-C object has not got",
            (_, ObjCProtocolTypeSymbol) =>
                $"'{type.Name}' is not an Objective-C class, so it cannot adopt the protocol " +
                $"'{resolved.Name}'; write 'objc class {type.Name}'",
            _ =>
                $"'{type.Name}' is not an Objective-C class, so it cannot derive from " +
                $"'{resolved.Name}'; write 'objc class {type.Name}'",
        };

        diagnostics.Error("SL0910", span, why, type, resolved);
        if (type is ClassTypeSymbol refused) _objcBaseRefused.Add(refused);
    }

    /// <summary>Objc classes whose superclass was refused, which a missing root says nothing more about.</summary>
    private readonly HashSet<ClassTypeSymbol> _objcBaseRefused = [];

    /// <summary>
    /// Runs once the attributes are read: names every objc type for the
    /// runtime, and checks that each imported chain ends at a root class.
    /// </summary>
    private void CheckObjCClasses()
    {
        NameObjCTypes();

        foreach (var classType in _objcClasses)
        {
            var span = classType.Span ?? default;

            if (classType.IsObjCRoot)
            {
                if (classType.BaseClass is not null)
                    diagnostics.Error("SL0911", span,
                        $"'{classType.Name}' is '[ObjCRoot]', so it has no superclass; it derives " +
                        $"from '{classType.BaseClass.Name}'",
                        classType, classType.BaseClass);
                continue;
            }

            // A metaclass's isa is its root's metaclass, so a chain that stops
            // short of the root would name the wrong one.
            if (!classType.SelfAndBases().Any(c => c.IsObjCRoot || _objcBaseRefused.Contains(c)))
                diagnostics.Error("SL0911", span,
                    classType.ObjC == ObjCClassKind.Defined && classType.BaseClass is null
                        ? $"'{classType.Name}' has no superclass, and a class defined here is built " +
                          "on one the runtime already has; derive it from 'NSObject'"
                        : $"'{classType.Name}' does not reach a root class: follow its superclasses " +
                          "and one of them MUST be an 'extern objc class' marked '[ObjCRoot]', as " +
                          "'NSObject' is. Name the superclass it really has",
                    classType);
        }

        // A base's selectors are settled before a class deriving from it
        // inherits them.
        foreach (var defined in _objcClasses
                     .Where(c => c.ObjC == ObjCClassKind.Defined)
                     .OrderBy(c => c.SelfAndBases().Count()))
        {
            RequireDarwin(defined.Span ?? default);
            if (_typeSyntax.TryGetValue(defined, out var entry))
                CheckDefinedClassShape(defined, entry.Declaration);
            ResolveObjCMembers(defined);
            CheckProtocolsAnswered(defined);
            CheckObjCFields(defined);
        }
    }

    /// <summary>
    /// What a class defined here cannot be. The runtime makes one object of
    /// it per <c>alloc</c> and asks it for messages by name, so each of these
    /// would need something the runtime has no way to give.
    /// </summary>
    private void CheckDefinedClassShape(ClassTypeSymbol defined, TypeDeclSyntax declaration)
    {
        string? why =
            declaration.Modifiers.HasFlag(Modifiers.Static) ? "static: the runtime registers a class to make instances of it"
            : declaration.PrimaryParameters.Count > 0 ? "given a primary constructor: Objective-C makes an object with 'alloc' and an init message, and a constructor is written as one"
            : null;

        if (why is not null)
            diagnostics.Error("SL0923", declaration.Span,
                $"'{defined.Name}' is an Objective-C class, which cannot be {why}",
                defined);

        foreach (var function in declaration.Members.OfType<FunctionDeclSyntax>())
            if (function.TypeParameters.Count > 0 &&
                (function.Attributes.Any(a => a.Name.Last == "Selector") || function.Modifiers.HasFlag(Modifiers.Override)))
                diagnostics.Error("SL0923", function.Span,
                    $"'{defined.Name}.{function.Name}' is generic, and a message is one method the " +
                    "runtime finds by its selector, with no type arguments to choose between; a " +
                    "generic helper without a selector is called directly and may be",
                    defined);
    }

    /// <summary>How a member is named in a diagnostic: a property by its own name, not its accessor's.</summary>
    private static string MemberName(FunctionSymbol method) => method.Accessor?.Name ?? method.Name;

    /// <summary>
    /// Gives each member of a class defined here the selector it answers: its
    /// own, the one it overrides, or the one a protocol it adopts names for a
    /// member of the same name and parameters.
    /// </summary>
    private void ResolveObjCMembers(ClassTypeSymbol defined)
    {
        foreach (var method in defined.Methods)
        {
            if (method.IsVirtual && !method.IsOverride)
            {
                diagnostics.Error("SL0921", method.Span,
                    $"'{defined.Name}.{MemberName(method)}' is '{(method.IsAbstract ? "abstract" : "virtual")}', " +
                    "which an Objective-C class does not need: every message it answers can be " +
                    "overridden already. Drop the word",
                    defined);
                continue;
            }

            if (method.IsOverride)
            {
                ResolveObjCOverride(defined, method);
                continue;
            }

            if (method.Selector is null &&
                FindObjCMessage(defined.ObjCProtocols.SelectMany(p => p.SelfAndBases()), method) is { } required)
                TakeSelector(method, required);

            if (method.Selector is null) continue;

            if (defined.BaseClass is { } baseClass &&
                SelfAndProtocols(baseClass).SelectMany(t => t.Methods)
                    .Any(m => m.Selector == method.Selector && m.IsStatic == method.IsStatic))
                diagnostics.Error("SL0921", method.Span,
                    $"'{defined.Name}.{MemberName(method)}' answers '{method.Selector}', which " +
                    $"'{baseClass.Name}' already answers; write 'override' to replace it",
                    defined, baseClass);
        }
    }

    /// <summary>
    /// An <c>override</c> in a class defined here: it finds the superclass's
    /// message of the same name and parameters, and answers that selector with
    /// the ownership the superclass declared.
    /// </summary>
    private void ResolveObjCOverride(ClassTypeSymbol defined, FunctionSymbol method)
    {
        var inherited = defined.BaseClass is { } baseClass
            ? FindObjCMessage(SelfAndProtocols(baseClass), method)
            : null;

        if (inherited is null)
        {
            diagnostics.Error("SL0921", method.Span,
                $"'{defined.Name}.{MemberName(method)}' is an 'override', and no superclass of " +
                $"'{defined.Name}' has a message named '{MemberName(method)}' taking these parameters " +
                $"to replace{(method.Selector is null ? "" : $"; to answer '{method.Selector}' afresh, drop 'override'")}",
                defined);
            return;
        }

        if (method.Selector is not null && method.Selector != inherited.Selector)
        {
            diagnostics.Error("SL0921", method.Span,
                $"'{defined.Name}.{MemberName(method)}' overrides '{inherited.Selector}', so it answers " +
                $"that selector and not '{method.Selector}'; an override inherits its selector, " +
                "so leave '[Selector]' off",
                defined);
            return;
        }

        bool returnFits = method.ReturnType == inherited.ReturnType ||
                          (IsObjCReference(method.ReturnType) && IsObjCReference(inherited.ReturnType) &&
                           IsObjCKindOf(method.ReturnType.AsReference() ?? method.ReturnType,
                                        inherited.ReturnType.AsReference() ?? inherited.ReturnType) &&
                           (method.ReturnType is not OptionalTypeSymbol ||
                            inherited.ReturnType is OptionalTypeSymbol));
        if (!returnFits)
            diagnostics.Error("SL0921", method.Span,
                $"'{defined.Name}.{MemberName(method)}' returns '{method.ReturnType.Name}', and the " +
                $"'{inherited.Selector}' it overrides returns '{inherited.ReturnType.Name}'; an " +
                "override returns the same, or a class derived from it",
                defined);

        method.Overridden = inherited;
        method.Selector = inherited.Selector;
        method.ConsumesSelf = inherited.ConsumesSelf;
        method.ReturnsRetained = inherited.ReturnsRetained;
        CheckObjCSignature(method, method.Span);
    }

    /// <summary>A member's selector taken from the protocol member it implements.</summary>
    private void TakeSelector(FunctionSymbol method, FunctionSymbol from)
    {
        method.Selector = from.Selector;
        method.ConsumesSelf = from.ConsumesSelf;
        method.ReturnsRetained = from.ReturnsRetained;
        CheckObjCSignature(method, method.Span);
    }

    /// <summary>A class and its superclasses, each followed by the protocols it adopts.</summary>
    private static IEnumerable<NamedTypeSymbol> SelfAndProtocols(ClassTypeSymbol start) =>
        start.SelfAndBases().SelectMany(c =>
            ((IEnumerable<NamedTypeSymbol>)[c]).Concat(c.ObjCProtocols.SelectMany(p => p.SelfAndBases())));

    /// <summary>
    /// The message among <paramref name="owners"/>' members with the name,
    /// parameters and kind of <paramref name="method"/>, nearest first.
    /// </summary>
    private static FunctionSymbol? FindObjCMessage(IEnumerable<NamedTypeSymbol> owners, FunctionSymbol method) =>
        owners.SelectMany(t => t.Methods).FirstOrDefault(m =>
            m.IsMessage && m.Name == method.Name && m.IsStatic == method.IsStatic &&
            m.ParameterTypes.SequenceEqual(method.ParameterTypes));

    /// <summary>
    /// Every required member of every protocol a class defined here adopts
    /// MUST be answered: by the class, by a class it derives from, or by a
    /// superclass that already exists and says it adopts the protocol.
    /// </summary>
    private void CheckProtocolsAnswered(ClassTypeSymbol defined)
    {
        foreach (var protocol in defined.ObjCProtocols.SelectMany(p => p.SelfAndBases()).Distinct())
        {
            if (defined.SelfAndBases().Any(c => c.ObjC == ObjCClassKind.Imported && c.AdoptsObjC(protocol)))
                continue;

            foreach (var required in protocol.Methods.Where(m => m.IsMessage && !m.IsObjCOptional))
            {
                bool answered = defined.SelfAndBases().Any(c => c.Methods.Any(m =>
                    m.Selector == required.Selector && m.IsStatic == required.IsStatic));
                if (answered) continue;

                diagnostics.Error("SL0922", defined.Span ?? default,
                    $"'{defined.Name}' adopts '{protocol.Name}' and does not answer " +
                    $"'{required.Selector}', which it requires: declare " +
                    $"'{MemberName(required)}' " +
                    "with the same parameters, or mark the protocol's member '[Optional]'",
                    defined, protocol);
            }
        }
    }

    /// <summary>
    /// The runtime names nothing set: an imported class or a protocol is
    /// called what it was declared as, which is what the headers call it.
    /// </summary>
    private void NameObjCTypes()
    {
        foreach (var protocol in _objcProtocols)
            protocol.RuntimeName ??= protocol.SimpleName;

        foreach (var classType in _objcClasses)
            classType.ObjCRuntimeName ??= classType.ObjC == ObjCClassKind.Defined
                ? classType.ModuleName + "." + classType.SimpleName
                : classType.SimpleName;
    }
}
