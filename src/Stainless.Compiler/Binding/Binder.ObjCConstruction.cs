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
/// Making an object of an Objective-C class defined here.
///
/// The runtime allocates it and runs its field initializers, through
/// <c>.cxx_construct</c>; a constructor is then an init, which starts by
/// sending an init message to the superclass or by running a defined base's
/// constructor. An init is allowed to answer with another object in
/// Objective-C, and is not here: the constructor's <c>this</c> is the object
/// <c>alloc</c> made, so a superclass init answering anything else stops the
/// program.
/// </summary>
public sealed partial class Binder
{
    /// <summary>
    /// The init message a constructor of a class defined here answers: its
    /// <c>[Selector]</c>, which MUST be in the init family, or <c>init</c> for
    /// one that takes nothing. One with parameters and no selector is reached
    /// by <c>new</c> alone.
    /// </summary>
    private void ReadInitSelector(
        FunctionSymbol constructor, NamedTypeSymbol type, IReadOnlyList<AttributeSyntax> attributes)
    {
        if (type is not ClassTypeSymbol { ObjC: ObjCClassKind.Defined }) return;

        foreach (var attribute in attributes.Where(a => a.Name.Last != "Selector"))
            diagnostics.Report(Codes.AttributeNotAllowedHere, attribute.Span,
                $"'[{attribute.Name.Last}]' means nothing on a constructor of '{type.Name}'; it " +
                "takes '[Selector]', the init message Objective-C makes one with",
                type);

        int parameters = constructor.Parameters.Count(p => !p.IsThis);
        string? selector = ReadSelector(attributes, type.Name, parameters, out var span);

        if (selector is not null && FamilyOf(selector) != "init")
        {
            diagnostics.Report(Codes.ObjCInitializerInvalid, span,
                $"a constructor of '{type.Name}' is answered as an init message, and " +
                $"'{selector}' is not one: its selector MUST begin with 'init', as " +
                "'initWithFrame:' does",
                type);
            return;
        }

        constructor.InitSelector = selector ?? (parameters == 0 ? "init" : null);
        if (constructor.InitSelector is not null) CheckObjCSignature(constructor, constructor.Span);
    }

    /// <summary>
    /// The method a class defined here runs its field initializers in. The
    /// runtime calls it from <c>.cxx_construct</c> as it allocates, so an
    /// object Cocoa makes through any init has them, as one <c>new</c> makes
    /// does.
    /// </summary>
    private static void SynthesizeObjCFieldInitializer(ClassTypeSymbol type)
    {
        if (type.Fields.FirstOrDefault(f => f.InitializerSyntax is not null) is not { } first) return;

        var where = first.InitializerSyntax!.Span;
        var symbol = new FunctionSymbol
        {
            Name = "$initialize",
            ModuleName = type.ModuleName,
            ReturnType = PrimitiveTypeSymbol.Void,
            Linkage = LinkageKind.Stainless,
            Kind = FunctionKind.Method,
            ContainingType = type,
            Body = new BlockSyntax(where, []),
            Span = where,
            Scope = first.InitializerScope,
            IsObjCFieldInitializer = true,
        };

        symbol.Parameters.Add(new ParameterSymbol("this", type, 0) { IsThis = true });
        type.ObjCFieldInitializer = symbol;
        first.InitializerScope!.Module.Functions.Add(symbol);
    }

    /// <summary>
    /// What <c>base(...)</c> may run for a class defined here: the
    /// constructors of the nearest defined class above it that has any, or
    /// else every init message the class it is built on declares, its
    /// superclasses' included.
    /// </summary>
    private static List<FunctionSymbol> ObjCBaseInitializers(ClassTypeSymbol classType, out ClassTypeSymbol? owner)
    {
        for (var current = classType.BaseClass; current is not null; current = current.BaseClass)
        {
            owner = current;
            if (current.ObjC == ObjCClassKind.Defined)
            {
                if (current.Constructors.Count > 0) return current.Constructors.ToList();
                continue;
            }

            var seen = new HashSet<string>(StringComparer.Ordinal);
            return current.SelfAndBases()
                .SelectMany(c => c.Methods)
                .Where(m => m is { IsMessage: true, ConsumesSelf: true, IsStatic: false } && seen.Add(m.Selector!))
                .ToList();
        }

        owner = null;
        return [];
    }

    /// <summary>The base initializer a class defined here runs when it names none: the one taking nothing.</summary>
    private static FunctionSymbol? ObjCImplicitBaseInitializer(ClassTypeSymbol classType, out ClassTypeSymbol? owner)
    {
        var parameterless = ObjCBaseInitializers(classType, out owner)
            .Where(f => !f.Parameters.Any(p => !p.IsThis))
            .ToList();
        return parameterless.FirstOrDefault(f => (f.Selector ?? f.InitSelector) == "init")
               ?? parameterless.FirstOrDefault();
    }

    /// <summary>
    /// <c>base(args)</c> in a constructor of a class defined here: a
    /// constructor of a defined base, called directly, or an init message
    /// sent to the superclass, which MUST answer with this same object.
    /// </summary>
    private BoundExpression BindObjCBaseConstruction(
        CallSyntax syntax, ClassTypeSymbol classType, List<BoundExpression> arguments)
    {
        var candidates = ObjCBaseInitializers(classType, out var owner);
        if (candidates.Count == 0)
        {
            diagnostics.Report(Codes.ObjCInitializerInvalid, syntax.Span,
                $"nothing '{classType.Name}' is built on declares an init message to run; " +
                $"declare '[Selector(\"init\")] public Self Init();' on " +
                $"'{owner?.Name ?? classType.Name}'",
                classType);
            return new BoundErrorExpression(syntax.Span);
        }

        var chosen = ResolveOverload(candidates, arguments, syntax.Span, $"base {owner!.Name}");
        if (chosen is null) return new BoundErrorExpression(syntax.Span);

        var self = new BoundThis(syntax.Span, classType, _context.Function!.Parameters[0]);
        var receiver = new BoundConversion(syntax.Span, classType.BaseClass!, self, ConversionKind.ObjCUpcast);

        _boundExplicitChain = true;
        return BuildCall(syntax, chosen, receiver, arguments, nonVirtual: true);
    }

    /// <summary>
    /// The base chain a constructor of a class defined here starts with when
    /// it wrote none: the base initializer that takes nothing.
    /// </summary>
    private BoundBlock WithObjCBaseConstruction(FunctionSymbol constructor, ClassTypeSymbol classType, BoundBlock body)
    {
        if (ObjCImplicitBaseInitializer(classType, out var owner) is not { } chained)
        {
            diagnostics.Report(Codes.ObjCInitializerInvalid, constructor.Span,
                $"'{owner?.Name ?? classType.Name}' has no initializer that takes no arguments, " +
                $"so '{classType.Name}' has to say which one to run: write 'base(...)' as the " +
                "first statement of its constructor",
                classType);
            return body;
        }

        var self = new BoundThis(constructor.Span, classType, constructor.Parameters[0]);
        var receiver = new BoundConversion(constructor.Span, classType.BaseClass!, self, ConversionKind.ObjCUpcast);
        var call = new BoundCall(constructor.Span, chained, receiver, []) { IsNonVirtual = true };

        return new BoundBlock(body.Span,
            [new BoundExpressionStatement(constructor.Span, call), .. body.Statements]);
    }

    /// <summary>
    /// What <c>new C()</c> runs for a class defined here that declares no
    /// constructor: the <c>init</c> message, sent to the object, so that
    /// whichever class answers it does.
    /// </summary>
    private FunctionSymbol? ObjCInitMessage(ClassTypeSymbol classType, SourceSpan span)
    {
        var init = classType.SelfAndBases()
            .SelectMany(c => c.Methods)
            .FirstOrDefault(m => m is { Selector: "init", IsStatic: false });
        if (init is not null) return init;

        diagnostics.Report(Codes.ObjCInitializerInvalid, span,
            $"'new {classType.Name}()' sends 'init', and nothing '{classType.Name}' is built on " +
            "declares it; declare '[Selector(\"init\")] public Self Init();' on its root class",
            classType);
        return null;
    }

    /// <summary>
    /// The fields of a class defined here: Objective-C may make one through
    /// an init that runs none of its constructors, so a field without a zero
    /// value MUST have an initializer, which runs whichever init it was; an
    /// event's list is made in <c>.cxx_construct</c> as well. A
    /// bit-field has no place in the one ivar the fields share. And a class
    /// answers each message with one method.
    /// </summary>
    private void CheckObjCFields(ClassTypeSymbol defined)
    {
        foreach (var field in defined.Fields)
        {
            if (field.IsBitField)
                diagnostics.Report(Codes.ObjCClassShapeUnsupported, defined.Span ?? default,
                    $"'{defined.Name}.{field.Name}' is a bit-field, which an Objective-C class " +
                    "cannot hold; use a whole integer",
                    defined);
            else if (field.InitializerSyntax is null && !field.Type.IsError() &&
                     !ZeroValues.HasZeroValue(field.Type) &&
                     !defined.Events.Any(e => e.BackingField == field))
                diagnostics.Report(Codes.FieldMayBeUnassigned, defined.Span ?? default,
                    $"'{defined.Name}.{field.Name}' is a '{field.Type.Name}', which has no zero " +
                    "value, and Objective-C may make the object through an init that runs none " +
                    "of its constructors; give the field an initializer, or make it optional",
                    defined, field.Type);
        }

        var answered = new Dictionary<string, FunctionSymbol>(StringComparer.Ordinal);
        foreach (var member in defined.Methods.Where(m => m.IsMessage && !m.IsStatic)
                     .Concat(defined.Constructors.Where(c => c.InitSelector is not null)))
        {
            string selector = member.Selector ?? member.InitSelector!;
            if (answered.TryAdd(selector, member)) continue;

            diagnostics.Report(Codes.ObjCOverrideInvalid, member.Span,
                $"'{defined.Name}' answers '{selector}' twice; a class answers each message " +
                "with one method",
                defined);
        }
    }
}
