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
/// Pass 2: every type in the program gets a symbol, and nothing more.
///
/// Nothing here looks at a base class, a member or a layout. That is the
/// whole point: a name must exist before anything can refer to it, and
/// Stainless has no headers to establish that order for it.
/// </summary>
public sealed partial class Binder
{
    // ============================================================ pass 2

    private void DeclareTypes()
    {
        foreach (var (scope, unit) in _units)
        {
            var module = scope.Module;
            foreach (var declaration in unit.Declarations.OfType<TypeDeclSyntax>())
            {
                if (module.Types.ContainsKey(declaration.Name) ||
                    module.GenericTypes.ContainsKey(declaration.Name))
                {
                    diagnostics.Error("SL0201", declaration.Span,
                        $"'{declaration.Name}' is already declared in module '{module.Name}'");
                    continue;
                }

                // A generic declaration is a template, not a type. Nothing about it
                // is checked until something instantiates it.
                if (declaration.TypeParameters.Count > 0)
                {
                    // Read here as well as below, because a generic declaration
                    // becomes a template and never reaches the code that does.
                    if (declaration.IsOpaque)
                        diagnostics.Error("SL0523", declaration.Span,
                            $"'{declaration.Name}' has no body, so it has nothing for a type " +
                            "parameter to appear in");
                    else if (module.GenericTypes.ContainsKey(declaration.Name))
                        diagnostics.Error("SL0201", declaration.Span,
                            $"'{declaration.Name}' is already declared in module '{module.Name}'");
                    else
                        module.GenericTypes[declaration.Name] =
                            new GenericTypeTemplate(declaration.Name, scope, declaration);
                    continue;
                }

                bool isPublic = declaration.Modifiers.HasFlag(Modifiers.Public);
                bool isCom = declaration.Modifiers.HasFlag(Modifiers.Com);

                NamedTypeSymbol type = declaration.Kind switch
                {
                    TypeDeclKind.Class => new ClassTypeSymbol
                    {
                        SimpleName = declaration.Name,
                        ModuleName = module.Name,
                        IsPublic = isPublic,
                        Span = declaration.Span,
                    },

                    // `com interface` is its own symbol rather than a flag on
                    // the ordinary one: the two are different things in memory,
                    // and sharing a symbol would mean every dispatch, every
                    // conversion and every retain asking which it was.
                    TypeDeclKind.Interface when isCom => new ComInterfaceTypeSymbol
                    {
                        SimpleName = declaration.Name,
                        ModuleName = module.Name,
                        IsPublic = isPublic,
                        Span = declaration.Span,
                    },
                    TypeDeclKind.Interface => new InterfaceTypeSymbol
                    {
                        SimpleName = declaration.Name,
                        ModuleName = module.Name,
                        IsPublic = isPublic,
                        Span = declaration.Span,
                    },
                    TypeDeclKind.Attribute => new AttributeTypeSymbol
                    {
                        SimpleName = declaration.Name,
                        ModuleName = module.Name,
                        IsPublic = isPublic,
                        Span = declaration.Span,
                    },
                    TypeDeclKind.Variant => new VariantTypeSymbol
                    {
                        SimpleName = declaration.Name,
                        ModuleName = module.Name,
                        IsPublic = isPublic,
                        Span = declaration.Span,
                    },
                    TypeDeclKind.Union => new UnionTypeSymbol
                    {
                        SimpleName = declaration.Name,
                        ModuleName = module.Name,
                        IsPublic = isPublic,
                        Span = declaration.Span,
                    },
                    _ => new StructTypeSymbol
                    {
                        SimpleName = declaration.Name,
                        ModuleName = module.Name,
                        IsPublic = isPublic,
                        Span = declaration.Span,
                    },
                };

                ReadInheritanceModifiers(type, declaration);

                if (declaration.IsOpaque) DeclareOpaque(type, declaration);

                module.Types[declaration.Name] = type;
                _typeSyntax[type] = (declaration, scope);

                if (type is ClassTypeSymbol { IsIntrinsic: false } classType) _classes.Add(classType);
                if (type is InterfaceTypeSymbol interfaceType) _interfaces.Add(interfaceType);
                if (type is ComInterfaceTypeSymbol comInterface) _comInterfaces.Add(comInterface);
            }

            foreach (var declaration in unit.Declarations.OfType<AliasDeclSyntax>())
            {
                if (module.Types.ContainsKey(declaration.Name) ||
                    module.GenericTypes.ContainsKey(declaration.Name) ||
                    module.Aliases.ContainsKey(declaration.Name))
                {
                    diagnostics.Error("SL0201", declaration.Span,
                        $"'{declaration.Name}' is already declared in module '{module.Name}'");
                    continue;
                }

                var alias = new AliasSymbol(declaration.Name, module.Name)
                {
                    IsPublic = declaration.Modifiers.HasFlag(Modifiers.Public),
                    Span = declaration.Span,
                };

                module.Aliases[declaration.Name] = alias;
                _aliasSyntax[alias] = (declaration, scope);
            }

            foreach (var declaration in unit.Declarations.OfType<DelegateDeclSyntax>())
            {
                if (module.Types.ContainsKey(declaration.Name) ||
                    module.GenericTypes.ContainsKey(declaration.Name))
                {
                    diagnostics.Error("SL0201", declaration.Span,
                        $"'{declaration.Name}' is already declared in module '{module.Name}'");
                    continue;
                }

                var delegateType = new DelegateTypeSymbol
                {
                    SimpleName = declaration.Name,
                    ModuleName = module.Name,
                    IsPublic = declaration.Modifiers.HasFlag(Modifiers.Public),
                    Span = declaration.Span,
                };

                module.Types[declaration.Name] = delegateType;
                _delegateSyntax[delegateType] = (declaration, scope);
            }

            foreach (var declaration in unit.Declarations.OfType<EnumDeclSyntax>())
            {
                if (module.Types.ContainsKey(declaration.Name) ||
                    module.GenericTypes.ContainsKey(declaration.Name))
                {
                    diagnostics.Error("SL0201", declaration.Span,
                        $"'{declaration.Name}' is already declared in module '{module.Name}'");
                    continue;
                }

                var enumType = new EnumTypeSymbol
                {
                    SimpleName = declaration.Name,
                    ModuleName = module.Name,
                    IsPublic = declaration.Modifiers.HasFlag(Modifiers.Public),
                    Span = declaration.Span,
                };

                module.Types[declaration.Name] = enumType;
                _enumSyntax[enumType] = (declaration, scope);
            }
        }
    }

    private readonly Dictionary<AliasSymbol, (AliasDeclSyntax Declaration, FileScope Scope)>
        _aliasSyntax = [];

    /// <summary>Aliases being resolved right now; a second visit is a ring.</summary>
    private readonly HashSet<AliasSymbol> _aliasesInProgress = [];

    /// <summary>
    /// The type an alias names, resolved the first time something asks.
    ///
    /// Deferred rather than done in a pass of its own because an alias may name
    /// a type declared later in the file, or another alias declared later --
    /// declaration order never matters here, and this is the cheapest way to
    /// keep that true.
    /// </summary>
    private TypeSymbol ResolveAlias(AliasSymbol alias)
    {
        if (alias.Target is { } already) return already;

        if (!_aliasesInProgress.Add(alias))
        {
            diagnostics.Error("SL0522", alias.Span,
                $"'{alias.Name}' is defined in terms of itself, so it names no type");
            return alias.Target = ErrorTypeSymbol.Instance;
        }

        var (declaration, scope) = _aliasSyntax[alias];
        var target = ResolveType(declaration.Target, scope);

        _aliasesInProgress.Remove(alias);
        return alias.Target = target;
    }

    /// <summary>
    /// Resolves every alias nothing happened to use.
    ///
    /// An alias is resolved where it is named, so one nothing names would never
    /// be looked at -- and a ring of them, or one naming a type that is not
    /// there, would be accepted in silence. Left until the end because
    /// resolving one can instantiate a generic, and that wants the binder whole.
    /// </summary>
    private void ResolveRemainingAliases()
    {
        foreach (var alias in _aliasSyntax.Keys.Where(a => a.Target is null).ToList())
            ResolveAlias(alias);
    }

    /// <summary>
    /// Marks a type declared with no body, and refuses the shapes that cannot
    /// mean anything without one.
    /// </summary>
    private void DeclareOpaque(NamedTypeSymbol type, TypeDeclSyntax declaration)
    {
        if (type is not StructTypeSymbol structType || type is UnionTypeSymbol or VariantTypeSymbol)
        {
            diagnostics.Error("SL0523", declaration.Span,
                $"'{type.Name}' has no body, and only a 'struct' may be written that way. " +
                "An incomplete type exists to be pointed at, and " +
                (type is ClassTypeSymbol
                    ? "a class is already reached through a pointer this compiler has to lay out"
                    : "this kind of type is nothing but its contents"));
            return;
        }

        if (declaration.TypeParameters.Count > 0)
        {
            diagnostics.Error("SL0523", declaration.Span,
                $"'{type.Name}' has no body, so it has nothing for a type parameter to appear in");
            return;
        }

        // An implements list needs no word here: a struct cannot implement an
        // interface at all (SL0302), body or no body, and that message says why.
        structType.IsOpaque = true;

        // Nothing will ever lay it out, and everything downstream asks whether a
        // layout has been computed rather than whether it could be.
        structType.SetLayout(0, 1);
    }

    /// <summary>
    /// Reads <c>abstract</c> and <c>sealed</c> onto a type. Both are about
    /// deriving, so neither means anything on something nothing can derive from.
    /// </summary>
    private void ReadInheritanceModifiers(NamedTypeSymbol type, TypeDeclSyntax declaration)
    {
        bool isAbstract = declaration.Modifiers.HasFlag(Modifiers.Abstract);
        bool isSealed = declaration.Modifiers.HasFlag(Modifiers.Sealed);

        if (declaration.Modifiers.HasFlag(Modifiers.Com))
        {
            if (type is ClassTypeSymbol comClass) comClass.IsCom = true;
            else if (type is not ComInterfaceTypeSymbol)
                diagnostics.Error("SL0528", declaration.Span,
                    $"'com' goes before 'interface' or 'class', and '{type.Name}' is neither; " +
                    "a COM reference points at a vtable pointer, and only those two have one");
        }

        if (type is not ClassTypeSymbol classType)
        {
            if (isAbstract || isSealed)
                diagnostics.Error("SL0495", declaration.Span,
                    $"'{type.Name}' is not a class, so it cannot be " +
                    $"'{(isAbstract ? "abstract" : "sealed")}'; only a class is derived from");
            return;
        }

        if (isAbstract && isSealed)
        {
            diagnostics.Error("SL0496", declaration.Span,
                $"'{type.Name}' cannot be both 'abstract' and 'sealed': the first says it must " +
                "be derived from and the second says it cannot be");
            return;
        }

        classType.IsAbstract = isAbstract;
        classType.IsSealed = isSealed;
    }
}
