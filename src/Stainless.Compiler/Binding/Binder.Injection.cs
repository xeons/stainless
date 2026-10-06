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
/// The calls of <c>Standard.DependencyInjection.ActivatorUtilities</c>, each
/// replaced where it is bound with code for its type argument: the
/// constructor call .NET's container finds by reflection, written here because
/// a generic is compiled once per type argument and the constructor is known.
/// </summary>
public sealed partial class Binder
{
    /// <summary>How a constructor parameter is asked of a provider.</summary>
    private enum InjectionKind
    {
        /// <summary>A <c>T</c>: <c>GetRequiredService&lt;T&gt;()</c>.</summary>
        Required,

        /// <summary>A <c>T?</c>: <c>GetService&lt;T&gt;()</c>.</summary>
        Optional,

        /// <summary>A <c>T[]</c>: <c>GetServices&lt;T&gt;()</c>.</summary>
        Many,
    }

    private readonly record struct Injection(ParameterSymbol Parameter, TypeSymbol Service, InjectionKind Kind);

    /// <summary>
    /// The expansion of an <c>ActivatorUtilities</c> call, or null when
    /// <paramref name="function"/> is not one.
    /// </summary>
    private BoundExpression? ExpandActivatorCall(
        CallSyntax syntax, FunctionSymbol function, List<BoundExpression> arguments)
    {
        string? which = _builtins.ActivatorCallName(function);
        if (which is null)
            return null;

        var span = syntax.Span;
        var asked = function.TypeArguments[0];

        // The library's own placeholder body calls itself, and is bound for
        // each type argument too. Whatever is wrong with that argument was
        // said at the call that asked for it.
        using var quiet = function.Template is { } template && _context.Function?.Template == template
            ? diagnostics.Muted()
            : default(DiagnosticBag.Mute?);

        return which switch
        {
            "HasDefault" => new BoundLiteral(span, PrimitiveTypeSymbol.Bool, DefaultImplementationOf(asked, span) is not null),
            "CreateDefault" => ExpandCreateDefault(span, asked, arguments[0], function.ReturnType),
            "CreateInstance" => ExpandCreateInstance(span, asked, arguments[0]),
            _ => ExpandVisitDependencies(span, asked, arguments[0]),
        };
    }

    /// <summary><c>new T(provider.GetRequiredService&lt;P&gt;(), ...)</c>.</summary>
    private BoundExpression ExpandCreateInstance(SourceSpan span, TypeSymbol asked, BoundExpression provider)
    {
        if (!TryChooseInjectionConstructor(asked, span, out var classType, out var constructor, out var injections))
            return new BoundErrorExpression(span);

        return WithHeldValue(span, provider, "provider", held =>
        {
            var arguments = new List<BoundExpression>();
            foreach (var injection in injections)
            {
                string method = injection.Kind switch
                {
                    InjectionKind.Required => "GetRequiredService",
                    InjectionKind.Optional => "GetService",
                    _ => "GetServices",
                };
                var call = CallGenericMethod(held, method, injection.Service, [], span);
                if (call is null)
                    return new BoundErrorExpression(span);
                arguments.Add(call);
            }
            return new BoundNew(span, classType, constructor, arguments);
        });
    }

    /// <summary><c>visitor.Visit&lt;P&gt;(required)</c> for each parameter, then their count.</summary>
    private BoundExpression ExpandVisitDependencies(SourceSpan span, TypeSymbol asked, BoundExpression visitor)
    {
        if (!TryChooseInjectionConstructor(asked, span, out _, out _, out var injections))
            return new BoundErrorExpression(span);

        return WithHeldValue(span, visitor, "visitor", held =>
        {
            var calls = new List<BoundExpression>();
            foreach (var injection in injections)
            {
                var required = new BoundLiteral(span, PrimitiveTypeSymbol.Bool, injection.Kind == InjectionKind.Required);
                var call = CallGenericMethod(held, "Visit", injection.Service, [required], span);
                if (call is null)
                    return new BoundErrorExpression(span);
                calls.Add(call);
            }
            return new BoundSequence(span, calls, new BoundLiteral(span, PrimitiveTypeSymbol.Int, injections.Count));
        });
    }

    /// <summary>
    /// The class <c>[DefaultImplementation]</c> names for an instantiation of
    /// a generic interface, made as <see cref="ExpandCreateInstance"/> makes
    /// one; a null of <paramref name="result"/> for anything else.
    /// </summary>
    private BoundExpression ExpandCreateDefault(
        SourceSpan span, TypeSymbol asked, BoundExpression provider, TypeSymbol result)
    {
        if (DefaultImplementationOf(asked, span) is not { } implementation)
            return new BoundNullLiteral(span, result);

        var made = ExpandCreateInstance(span, implementation, provider);
        if (made.Type.IsError())
            return made;
        return BindConversion(made, result, span);
    }

    /// <summary>
    /// For an instantiation of a generic interface marked
    /// <c>[DefaultImplementation("Module.Class")]</c>, that class instantiated
    /// with the same type arguments; null for anything else.
    /// </summary>
    private ClassTypeSymbol? DefaultImplementationOf(TypeSymbol asked, SourceSpan span)
    {
        if (asked is not InterfaceTypeSymbol { Template: { } template } contract)
            return null;

        var marked = template.Declaration.Attributes
            .FirstOrDefault(a => a.Name.Text is "DefaultImplementation" or "Standard.DependencyInjection.DefaultImplementation");
        if (marked is null)
            return null;

        string? named = marked.Arguments.FirstOrDefault() is LiteralSyntax { Value: string text } ? text : null;
        int dot = named?.LastIndexOf('.') ?? -1;
        GenericTypeTemplate? found = named is not null && dot > 0 &&
                                     _modules.TryGetValue(named[..dot], out var module)
            ? module.FindGenericType(named[(dot + 1)..], contract.TypeArguments.Count)
            : null;

        if (found is null || found.Declaration.Kind != TypeDeclKind.Class)
        {
            diagnostics.Report(Codes.DefaultImplementationInvalid, OutsideTheLibrary(span),
                $"'{template.Name}' says '{named ?? "(nothing)"}' is its default implementation, which " +
                $"is not a generic class taking {contract.TypeArguments.Count} type " +
                $"argument{(contract.TypeArguments.Count == 1 ? "" : "s")}; name it with its module, " +
                "as 'App.Logger'",
                contract);
            return null;
        }

        return Instantiate(found, contract.TypeArguments, span) as ClassTypeSymbol;
    }

    /// <summary>
    /// The public constructor a container uses for <paramref name="asked"/>,
    /// and how each of its parameters is asked for. Reports, at the program's
    /// own call, why there is none.
    /// </summary>
    private bool TryChooseInjectionConstructor(
        TypeSymbol asked, SourceSpan span, out ClassTypeSymbol classType,
        out FunctionSymbol? constructor, out List<Injection> injections)
    {
        classType = null!;
        constructor = null;
        injections = [];
        var at = OutsideTheLibrary(span);

        if (asked is not ClassTypeSymbol { IsAbstract: false, IsStaticClass: false, RuntimeFactory: null } made ||
            made.ObjC != ObjCClassKind.None)
        {
            diagnostics.Report(Codes.InjectedTypeNotConstructible, at,
                $"'{FullTypeName(asked)}' cannot be made by a container: it MUST be a class that is " +
                "neither abstract nor static. Register the class that implements it, or a factory",
                asked);
            return false;
        }
        classType = made;

        if (made.Constructors.Count == 0)
        {
            TryImplicitBaseConstructor(made, out constructor);
            CheckRequiredMembers(made, constructor, null, at);
            return true;
        }

        var reachable = made.Constructors.Where(c => c.IsPublic).ToList();
        if (reachable.Count == 0)
        {
            diagnostics.Report(Codes.InjectedTypeNotConstructible, at,
                $"'{FullTypeName(asked)}' has no public constructor, so a container cannot make " +
                "one. Make a constructor public, or register a factory",
                asked);
            return false;
        }

        int most = reachable.Max(c => c.ParameterTypes.Count());
        var widest = reachable.Where(c => c.ParameterTypes.Count() == most).ToList();
        if (widest.Count > 1)
        {
            diagnostics.Report(Codes.InjectedConstructorAmbiguous, at,
                $"'{FullTypeName(asked)}' has {widest.Count} public constructors taking {most} " +
                $"parameter{(most == 1 ? "" : "s")}, and a container uses the one with most; it " +
                "cannot choose between these. Remove one, or register a factory",
                asked);
            return false;
        }
        constructor = widest[0];

        foreach (var parameter in constructor.Parameters.Where(p => !p.IsThis))
        {
            var (service, kind) = parameter.Type switch
            {
                OptionalTypeSymbol { Element: var element } => (element, InjectionKind.Optional),
                ArrayTypeSymbol { Element: var element } => (element, InjectionKind.Many),
                var plain => (plain, InjectionKind.Required),
            };

            bool askable = service is ClassTypeSymbol or InterfaceTypeSymbol &&
                           !ReferenceEquals(service, _builtins.String) &&
                           !parameter.IsParams && !parameter.IsByReference && !parameter.IsOptional;
            if (!askable)
            {
                diagnostics.Report(Codes.InjectedParameterUnresolvable, at,
                    $"parameter '{parameter.Name}' of '{FullTypeName(asked)}' is " +
                    $"'{FullTypeName(parameter.Type)}', which a container cannot be asked for: a " +
                    "parameter MUST be a class or an interface, optional or an array of one, and " +
                    "neither 'ref', 'params' nor given a default. Register a factory instead",
                    asked);
                return false;
            }
            injections.Add(new Injection(parameter, service, kind));
        }

        CheckRequiredMembers(made, constructor, null, at);
        return true;
    }

    /// <summary>
    /// <paramref name="value"/> held in a local for <paramref name="body"/> to
    /// read as often as it needs, and evaluated once.
    /// </summary>
    private static BoundExpression WithHeldValue(
        SourceSpan span, BoundExpression value, string name, Func<BoundExpression, BoundExpression> body)
    {
        var local = new LocalSymbol(name, value.Type, isConst: false);
        var inner = body(new BoundLocalAccess(span, local));
        if (inner.Type.IsError())
            return inner;
        bool made = value is BoundCall or BoundNew or BoundIndirectCall or BoundClosureCall;
        return new BoundLet(span, local, value, inner) { IsOwned = value.Type.NeedsArc() && !made };
    }

    /// <summary>
    /// <c>receiver.Name&lt;typeArgument&gt;(arguments)</c>, for a generic method
    /// of the receiver's class, or null when it has none of that shape.
    /// </summary>
    private BoundExpression? CallGenericMethod(
        BoundExpression receiver, string name, TypeSymbol typeArgument,
        List<BoundExpression> arguments, SourceSpan span)
    {
        if (receiver.Type is not NamedTypeSymbol owner)
            return null;

        var template = GenericMethodsNamed(owner, name)
            .FirstOrDefault(t => t.Parameters.Count == 1 &&
                                 t.Declaration.Parameters.Count == arguments.Count);
        if (template is null)
            throw new InternalCompilerError(
                $"'{owner.Name}' has no generic method '{name}' taking {arguments.Count} arguments");

        var function = InstantiateFunction(template, [typeArgument], span);
        return function is null ? null : new BoundCall(span, function, receiver, arguments);
    }

    /// <summary>
    /// Where a diagnostic about a type argument belongs: <paramref name="span"/>,
    /// unless it is inside the standard library, in which case the call that
    /// instantiated the library's generic, followed out until it is the
    /// program's own.
    /// </summary>
    private SourceSpan OutsideTheLibrary(SourceSpan span)
    {
        // A lambda is bound as a function of its own, which nothing
        // instantiated; the one it was written in is the one to follow.
        var function = _context.Closures.Count > 0 ? _context.Closures[0].OuterFunction : _context.Function;
        var at = span;
        for (int depth = 0; function is not null && IsStandardModule(function.ModuleName) && depth < 64; depth++)
        {
            if (function.InstantiatedAt is not { } instantiated)
                break;
            at = instantiated;
            function = function.InstantiatedBy;
        }
        return at;
    }

    private static bool IsStandardModule(string module) =>
        module == Builtins.StandardModuleName ||
        module.StartsWith(Builtins.StandardModuleName + ".", StringComparison.Ordinal);
}
