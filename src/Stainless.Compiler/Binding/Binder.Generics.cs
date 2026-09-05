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

using Stainless.Source;
using Stainless.Syntax;

namespace Stainless.Binding;

/// <summary>
/// Monomorphization, and pass 8 which drains what it queues.
///
/// An instantiation runs passes 4, 5 and 6 again with the type
/// arguments substituted in, so <c>Box&lt;int&gt;</c> is built exactly as a
/// hand-written type would have been. Bodies are queued rather than
/// bound, because binding one can instantiate another.
/// </summary>
public sealed partial class Binder
{
    // ============================================================ pass 8

    /// <summary>
    /// Binds the bodies produced by instantiation. Each one may instantiate more
    /// generics, so the queue is drained rather than iterated once.
    /// </summary>
    private void DrainPending()
    {
        var previous = _substitution;

        while (_pending.Count > 0)
        {
            var (function, substitution) = _pending.Dequeue();
            _substitution = substitution;
            BindFunctionBody(function);
        }

        _substitution = previous;
    }

    // ============================================================ generics

    private static string InstantiationKey(string name, IReadOnlyList<TypeSymbol> arguments) =>
        name + "<" + string.Join(",", arguments.Select(a => a.Name)) + ">";

    /// <summary>
    /// Produces the concrete type for <c>Box&lt;int&gt;</c>, building it the
    /// first time it is asked for.
    ///
    /// Stainless monomorphizes, so this is where a template stops being syntax:
    /// members are declared, interfaces resolved and the layout computed exactly
    /// as they would be for a hand-written type, with the type arguments
    /// substituted in. Bodies are queued rather than bound here, because an
    /// instantiation can be requested from inside another one.
    /// </summary>
    private NamedTypeSymbol Instantiate(
        GenericTypeTemplate template, IReadOnlyList<TypeSymbol> arguments, SourceSpan span)
    {
        if (arguments.Count != template.Parameters.Count)
        {
            diagnostics.Error("SL0323", span,
                $"'{template.Name}' takes {template.Parameters.Count} type " +
                $"argument{(template.Parameters.Count == 1 ? "" : "s")}, " +
                $"but {Given(arguments.Count)}");
            return new StructTypeSymbol { SimpleName = template.Name, ModuleName = template.Module.Name };
        }

        string key = InstantiationKey(template.Module.Name + "." + template.Name, arguments);
        if (_instantiatedTypes.TryGetValue(key, out var existing)) return existing;

        var declaration = template.Declaration;
        string displayName = template.Name + "<" + string.Join(", ", arguments.Select(a => a.Name)) + ">";
        bool isPublic = declaration.Modifiers.HasFlag(Modifiers.Public);

        NamedTypeSymbol type = declaration.Kind switch
        {
            TypeDeclKind.Class => new ClassTypeSymbol
            {
                SimpleName = displayName, ModuleName = template.Module.Name, IsPublic = isPublic,
                Template = template, TypeArguments = arguments, Span = declaration.Span,
            },
            TypeDeclKind.Interface => new InterfaceTypeSymbol
            {
                SimpleName = displayName, ModuleName = template.Module.Name, IsPublic = isPublic,
                Template = template, TypeArguments = arguments, Span = declaration.Span,
            },
            TypeDeclKind.Variant => new VariantTypeSymbol
            {
                SimpleName = displayName, ModuleName = template.Module.Name, IsPublic = isPublic,
                Template = template, TypeArguments = arguments, Span = declaration.Span,
            },
            TypeDeclKind.Union => new UnionTypeSymbol
            {
                SimpleName = displayName, ModuleName = template.Module.Name, IsPublic = isPublic,
                Template = template, TypeArguments = arguments, Span = declaration.Span,
            },
            _ => new StructTypeSymbol
            {
                SimpleName = displayName, ModuleName = template.Module.Name, IsPublic = isPublic,
                Template = template, TypeArguments = arguments, Span = declaration.Span,
            },
        };

        // Registered before its members are declared, so a self-referential
        // template such as `class Node<T> { Node<T>? next; }` terminates.
        ReadInheritanceModifiers(type, declaration);

        _instantiatedTypes[key] = type;
        if (type is ClassTypeSymbol instantiatedClass) _classes.Add(instantiatedClass);
        if (type is InterfaceTypeSymbol instantiatedInterface) _interfaces.Add(instantiatedInterface);
        if (type is StructTypeSymbol instantiatedStruct) _structs.Add(instantiatedStruct);

        var substitution = new Dictionary<string, TypeSymbol>(StringComparer.Ordinal);
        for (int i = 0; i < arguments.Count; i++) substitution[template.Parameters[i]] = arguments[i];

        var previousSubstitution = _substitution;
        var previousScope = _currentScope;
        _substitution = substitution;

        // A template is bound with the imports of the file that declared it, not
        // those of the file asking for this instantiation.
        _currentScope = template.Scope;

        VerifyConstraints(declaration.Constraints, template.Parameters, substitution,
            template.Scope, $"'{template.Name}'", span);

        // Attributes come from the template, because pass 6 only walks types it
        // found in source and an instantiation is made later than that. Without
        // this a [Shared] or [Reflect] on a generic would be silently dropped
        // from every instantiation of it.
        BindAttributes(declaration.Attributes, type.Attributes, template.Scope, type.Name);

        if (ReflectAttribute is { } reflect && type.Attributes.Any(a => a.Type == reflect) &&
            type is ClassTypeSymbol or StructTypeSymbol && type is not VariantTypeSymbol)
            type.IsReflected = true;

        DeclareTypeMembers(template.Scope, declaration, type);
        ResolveImplements(type, declaration, template.Scope);
        ComputeLayout(type, []);

        // Every body this instantiation owns is bound later, under this same
        // substitution.
        foreach (var method in type.Methods.Where(m => m.HasBody))
            _pending.Enqueue((method, substitution));

        if (type is ClassTypeSymbol withMembers)
        {
            foreach (var constructor in withMembers.Constructors)
                _pending.Enqueue((constructor, substitution));
            if (withMembers.Destructor is not null)
                _pending.Enqueue((withMembers.Destructor, substitution));
        }

        _substitution = previousSubstitution;
        _currentScope = previousScope;
        return type;
    }

    /// <summary>Produces the concrete function for a generic call such as <c>Max(1, 2)</c>.</summary>
    private FunctionSymbol? InstantiateFunction(
        GenericFunctionTemplate template, IReadOnlyList<TypeSymbol> arguments, SourceSpan span)
    {
        if (arguments.Count != template.Parameters.Count)
        {
            diagnostics.Error("SL0324", span,
                $"'{template.Name}' takes {template.Parameters.Count} type " +
                $"argument{(template.Parameters.Count == 1 ? "" : "s")}, " +
                $"but {arguments.Count} were inferred");
            return null;
        }

        string owner = template.ContainingType is null
            ? template.Module.Name
            : template.ContainingType.QualifiedName;

        // The declaration's position is in the key because functions overload and
        // templates do too: `Sort<T>(T[:])` and `Sort<T>(IList<T>)` are two
        // templates of one name, and instantiating both at `int` must give two
        // functions rather than whichever was asked for first.
        string key = InstantiationKey(
            owner + "." + template.Name + "@" + template.Declaration.Span.Start, arguments);
        if (_instantiatedFunctions.TryGetValue(key, out var existing)) return existing;

        // The enclosing type's arguments first, then the method's own on top.
        var substitution = new Dictionary<string, TypeSymbol>(
            template.OuterSubstitution, StringComparer.Ordinal);
        for (int i = 0; i < arguments.Count; i++) substitution[template.Parameters[i]] = arguments[i];

        var previousSubstitution = _substitution;
        var previousScope = _currentScope;
        _substitution = substitution;
        _currentScope = template.Scope;

        var declaration = template.Declaration;

        VerifyConstraints(declaration.Constraints, template.Parameters, substitution,
            template.Scope, $"'{template.Name}'", span);

        var symbol = new FunctionSymbol
        {
            Name = template.Name,
            ModuleName = template.Module.Name,
            ReturnType = ResolveType(declaration.ReturnType, template.Scope),
            Linkage = LinkageKind.Stainless,
            Kind = template.ContainingType is null ? FunctionKind.Function : FunctionKind.Method,
            ContainingType = template.ContainingType,
            IsPublic = template.IsPublic,
            Body = declaration.Body,
            Span = declaration.Span,
            TypeArguments = arguments.ToList(),
            Scope = template.Scope,
        };

        if (template.ContainingType is { } containing)
        {
            // A method receives its instance: classes by reference, structs by pointer.
            TypeSymbol thisType = containing is ClassTypeSymbol reference
                ? reference
                : new PointerTypeSymbol(containing);
            symbol.Parameters.Add(new ParameterSymbol("this", thisType, 0) { IsThis = true });
        }

        AddParameters(symbol, declaration.Parameters, template.Scope);

        _instantiatedFunctions[key] = symbol;
        _pending.Enqueue((symbol, substitution));

        _substitution = previousSubstitution;
        _currentScope = previousScope;
        return symbol;
    }

    /// <summary>
    /// Checks each <c>where</c> clause against the type arguments actually
    /// supplied.
    ///
    /// Because Stainless monomorphizes, a template's body is checked per
    /// instantiation rather than once against its constraints. A constraint is
    /// therefore a promise verified here, at the use site, where it can name the
    /// offending type -- rather than a Rust-style contract the body is checked
    /// against. See docs/language-spec.md for what that means in practice.
    /// </summary>
    private void VerifyConstraints(
        IReadOnlyList<WhereClauseSyntax> clauses,
        IReadOnlyList<string> parameters,
        Dictionary<string, TypeSymbol> substitution,
        FileScope scope,
        string owner,
        SourceSpan span)
    {
        foreach (var clause in clauses)
        {
            if (!substitution.TryGetValue(clause.TypeParameter, out var argument))
            {
                diagnostics.Error("SL0330", clause.Span,
                    $"'{clause.TypeParameter}' is not a type parameter of {owner}; " +
                    $"it declares {string.Join(", ", parameters.Select(p => "'" + p + "'"))}");
                continue;
            }

            foreach (var constraintSyntax in clause.Constraints)
            {
                // Resolved under the substitution, so `where T : Comparer<U>` works.
                var constraint = ResolveType(constraintSyntax, scope);
                if (constraint.IsError()) continue;

                if (constraint is not InterfaceTypeSymbol required)
                {
                    diagnostics.Error("SL0329", constraintSyntax.Span,
                        $"'{constraint.Name}' is not an interface, so it cannot constrain " +
                        $"'{clause.TypeParameter}'; Stainless constrains type parameters by " +
                        "interface only");
                    continue;
                }

                if (Satisfies(argument, required)) continue;

                diagnostics.Error("SL0328", span,
                    $"'{argument.Name}' cannot be used as '{clause.TypeParameter}' in {owner} " +
                    $"because it does not implement '{required.Name}'" +
                    (argument is ClassTypeSymbol implementer && implementer.Interfaces.Count > 0
                        ? $"; it implements " +
                          string.Join(", ", implementer.Interfaces.Select(i => "'" + i.Name + "'"))
                        : ""));
            }
        }
    }

    /// <summary>
    /// True when <paramref name="argument"/> meets an interface constraint: a
    /// class that implements it, or the interface itself.
    /// </summary>
    private bool Satisfies(TypeSymbol argument, InterfaceTypeSymbol required) => argument switch
    {
        ClassTypeSymbol implementer =>
            implementer.AllInterfaces().Contains(required) ||
            SatisfiesIntrinsically(argument, required),
        InterfaceTypeSymbol self => self.Equals(required) || self.AllInterfaces().Contains(required),
        _ => SatisfiesIntrinsically(argument, required),
    };

    /// <summary>
    /// The three interfaces a primitive, an enum or a String implements without
    /// saying so.
    ///
    /// None of them can carry a declaration: a primitive is not a class, an
    /// enum is its integer, and String belongs to the runtime. But they are
    /// exactly the types people use as keys and sort by, so a rule that
    /// excluded them would exclude the point of having constraints. The binder
    /// recognises the members instead — see
    /// <see cref="TryBindIntrinsicMember"/> — and this is the matching answer
    /// at the constraint.
    /// </summary>
    private bool SatisfiesIntrinsically(TypeSymbol argument, InterfaceTypeSymbol required)
    {
        if (!HasIntrinsicMembers(argument)) return false;
        if (required.ModuleName != "Standard.Collections") return false;

        // IHashable takes no type argument; the other two are about this type.
        if (required.Template is null)
            return required.SimpleName == "IHashable";

        return required.Template.Name is "IEquatable" or "IComparable"
               && required.TypeArguments.Count == 1
               && required.TypeArguments[0].Equals(argument);
    }

    /// <summary>
    /// True for the types whose ordering, equality and hashing the compiler
    /// supplies. Deliberately not pointers: two pointers being equal is a
    /// question about addresses rather than about values, and a program that
    /// means it can say so with a cast.
    /// </summary>
    private bool HasIntrinsicMembers(TypeSymbol type) =>
        type is PrimitiveTypeSymbol { Kind: not PrimitiveKind.Void } or EnumTypeSymbol
        || _builtins.IsString(type);

    /// <summary>
    /// Matches a declared parameter type against an argument's actual type to
    /// discover what each type parameter must be. Structural and deliberately
    /// simple: it looks through arrays and pointers, and stops at anything else.
    /// </summary>
    private void Infer(
        TypeSyntax pattern,
        TypeSymbol actual,
        IReadOnlySet<string> parameters,
        Dictionary<string, TypeSymbol> inferred,
        FileScope scope)
    {
        switch (pattern)
        {
            case NamedTypeSyntax { Name.Parts.Count: 1, TypeArguments.Count: 0 } name
                when parameters.Contains(name.Name.Parts[0]):
                inferred.TryAdd(name.Name.Parts[0], actual);
                break;

            case ArrayTypeSyntax array when actual is ArrayTypeSymbol actualArray:
                Infer(array.Element, actualArray.Element, parameters, inferred, scope);
                break;

            // `T[:]` matches a slice, and an array too: an array converts to a
            // slice of the whole of itself, so `Sort(numbers)` should infer T
            // from the array rather than refuse to look at it.
            case SliceTypeSyntax slice when actual is SliceTypeSymbol actualSlice:
                Infer(slice.Element, actualSlice.Element, parameters, inferred, scope);
                break;

            case SliceTypeSyntax slice when actual is ArrayTypeSymbol whole:
                Infer(slice.Element, whole.Element, parameters, inferred, scope);
                break;

            case PointerTypeSyntax pointer when actual is PointerTypeSymbol actualPointer:
                Infer(pointer.Element, actualPointer.Element, parameters, inferred, scope);
                break;

            case NullableTypeSyntax nullable when actual is OptionalTypeSymbol actualOptional:
                Infer(nullable.Element, actualOptional.Element, parameters, inferred, scope);
                break;

            // `IReadOnlyList<T>` against a `List<Money>`: find the instantiation
            // of the same template on the argument or among its interfaces, then
            // line the arguments up.
            case NamedTypeSyntax { TypeArguments.Count: > 0 } constructed:
            {
                var template = FindGenericType(constructed.Name, scope);
                if (template is null) break;

                foreach (var candidate in InferenceCandidates(actual))
                {
                    if (!ReferenceEquals(candidate.Template, template)) continue;
                    if (candidate.TypeArguments.Count != constructed.TypeArguments.Count) continue;

                    for (int i = 0; i < candidate.TypeArguments.Count; i++)
                        Infer(constructed.TypeArguments[i], candidate.TypeArguments[i],
                            parameters, inferred, scope);
                    return;
                }
                break;
            }
        }
    }

    /// <summary>An argument's own type, then every interface it carries.</summary>
    private static IEnumerable<NamedTypeSymbol> InferenceCandidates(TypeSymbol actual)
    {
        if (actual is not NamedTypeSymbol named) yield break;

        yield return named;
        foreach (var interfaceType in named.AllInterfaces()) yield return interfaceType;
    }
}
