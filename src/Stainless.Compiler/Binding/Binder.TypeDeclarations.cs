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
                if (module.Types.TryGetValue(declaration.Name, out var already) &&
                    declaration.TypeParameters.Count == 0)
                {
                    DeclareAdditionalPart(declaration, already, scope);
                    continue;
                }

                if (!ClaimTypeName(module, declaration))
                    continue;

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
                        Documentation = declaration.Documentation,
                        RecordParameters = declaration.RecordParameters,
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
                        Documentation = declaration.Documentation,
                    },
                    TypeDeclKind.Interface => new InterfaceTypeSymbol
                    {
                        SimpleName = declaration.Name,
                        ModuleName = module.Name,
                        IsPublic = isPublic,
                        Span = declaration.Span,
                        Documentation = declaration.Documentation,
                    },
                    TypeDeclKind.Attribute => new AttributeTypeSymbol
                    {
                        SimpleName = declaration.Name,
                        ModuleName = module.Name,
                        IsPublic = isPublic,
                        Span = declaration.Span,
                        Documentation = declaration.Documentation,
                    },
                    TypeDeclKind.Variant => new VariantTypeSymbol
                    {
                        SimpleName = declaration.Name,
                        ModuleName = module.Name,
                        IsPublic = isPublic,
                        Span = declaration.Span,
                        Documentation = declaration.Documentation,
                    },
                    TypeDeclKind.Union => new UnionTypeSymbol
                    {
                        SimpleName = declaration.Name,
                        ModuleName = module.Name,
                        IsPublic = isPublic,
                        Span = declaration.Span,
                        Documentation = declaration.Documentation,
                    },
                    _ => new StructTypeSymbol
                    {
                        SimpleName = declaration.Name,
                        ModuleName = module.Name,
                        IsPublic = isPublic,
                        Span = declaration.Span,
                        Documentation = declaration.Documentation,
                    },
                };

                ReadInheritanceModifiers(type, declaration);

                if (declaration.IsOpaque) DeclareOpaque(type, declaration);

                module.Types[declaration.Name] = type;
                _typeSyntax[type] = (declaration, scope);
                _declaredTypes[declaration] = type;

                if (type is ClassTypeSymbol { IsIntrinsic: false } classType) _classes.Add(classType);
                if (type is InterfaceTypeSymbol interfaceType) _interfaces.Add(interfaceType);
                if (type is ComInterfaceTypeSymbol comInterface) _comInterfaces.Add(comInterface);
            }

            foreach (var declaration in unit.Declarations.OfType<AliasDeclSyntax>())
            {
                if (!ClaimTypeName(module, declaration))
                    continue;

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
                if (!ClaimTypeName(module, declaration))
                    continue;

                // A generic one stays a template until something names its type
                // arguments, exactly as a generic class does.
                if (declaration.TypeParameters.Count > 0)
                {
                    module.GenericDelegates[declaration.Name] =
                        new GenericDelegateTemplate(declaration.Name, scope, declaration);
                    continue;
                }

                // Declared before the loop body reads it, so the local below
                // keeps the name the rest of this block already uses.
                NamedTypeSymbol delegateType = declaration.CarriesReceiver
                    ? NewClosureType(declaration, module)
                    : new DelegateTypeSymbol
                    {
                        SimpleName = declaration.Name,
                        ModuleName = module.Name,
                        IsPublic = declaration.Modifiers.HasFlag(Modifiers.Public),
                        Span = declaration.Span,
                        Documentation = declaration.Documentation,
                    };

                ClaimThreadsafe(delegateType, declaration.Modifiers, declaration.Span);

                module.Types[declaration.Name] = delegateType;
                _delegateSyntax[delegateType] = (declaration, scope);
                _declaredTypes[declaration] = delegateType;
            }

            foreach (var declaration in unit.Declarations.OfType<EnumDeclSyntax>())
            {
                if (!ClaimTypeName(module, declaration))
                    continue;

                var enumType = new EnumTypeSymbol
                {
                    SimpleName = declaration.Name,
                    ModuleName = module.Name,
                    IsPublic = declaration.Modifiers.HasFlag(Modifiers.Public),
                    Span = declaration.Span,
                    Documentation = declaration.Documentation,
                };

                ClaimThreadsafe(enumType, declaration.Modifiers, declaration.Span);

                module.Types[declaration.Name] = enumType;
                _enumSyntax[enumType] = (declaration, scope);
                _declaredTypes[declaration] = enumType;
            }
        }
    }

    /// <summary>
    /// Whether a type name is still free in its module, reporting SL0201 when
    /// it is not.
    ///
    /// One question asked of all four tables, by every kind of declaration.
    /// Each loop above used to ask its own subset -- a type did not look at the
    /// aliases, an enum not at the generic closures -- which was harmless only
    /// while the declaration it skipped came later in the same file. Pass 2
    /// takes one file at a time, so a closure in one file and a class of the
    /// same name in the next were both accepted, and whichever the resolver
    /// happened to ask about first was the one every use meant.
    /// </summary>
    private bool ClaimTypeName(ModuleSymbol module, Declaration declaration)
    {
        string name = declaration switch
        {
            TypeDeclSyntax type => type.Name,
            DelegateDeclSyntax declared => declared.Name,
            EnumDeclSyntax declared => declared.Name,
            AliasDeclSyntax alias => alias.Name,
            _ => throw new ArgumentException("not a type declaration", nameof(declaration)),
        };

        if (!module.Types.ContainsKey(name) &&
            !module.GenericTypes.ContainsKey(name) &&
            !module.GenericDelegates.ContainsKey(name) &&
            !module.Aliases.ContainsKey(name))
            return true;

        diagnostics.Error("SL0201", declaration.Span,
            $"'{name}' is already declared in module '{module.Name}'");
        return false;
    }

    /// <summary>
    /// Records a <c>threadsafe</c> claim, or says why the type cannot make one.
    ///
    /// The word means that operations on the type synchronize themselves, so it
    /// belongs on something with operations. A variant and a union have none --
    /// they are a tag and some bytes -- and an enum is its integer, a delegate
    /// a pointer; all four already cross a thread boundary freely, so the word
    /// on one would be a promise about nothing.
    /// </summary>
    private void ClaimThreadsafe(NamedTypeSymbol type, Modifiers modifiers, SourceSpan span)
    {
        if (!modifiers.HasFlag(Modifiers.Threadsafe)) return;

        if (type is VariantTypeSymbol or UnionTypeSymbol or EnumTypeSymbol
                 or DelegateTypeSymbol or AttributeTypeSymbol)
        {
            diagnostics.Error("SL0582", span,
                $"'{type.Name}' cannot be 'threadsafe': the word says that operations on a " +
                "type synchronize themselves, and this has none. A class, a struct or an " +
                "interface may claim it");
            return;
        }

        type.IsThreadsafe = true;
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

        if (declaration.Modifiers.HasFlag(Modifiers.Threadsafe))
            ClaimThreadsafe(type, declaration.Modifiers, declaration.Span);

        if (declaration.Modifiers.HasFlag(Modifiers.Static)) type.IsStaticClass = true;

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

    /// <summary>
    /// A second declaration of a type inside its own module.
    ///
    /// A module already spans files, and this lets a type do the same. Every
    /// declaration must agree about what kind of type it is. A class may take
    /// fields from any of them and its base list from any one; every other
    /// kind takes both from the first, because its layout is C's or the
    /// runtime's.
    ///
    /// The members are declared by pass 4 without any help from here, because
    /// pass 4 walks declarations and looks each type up by name. All that is
    /// needed is to stop reporting the name as a duplicate, and to refuse what
    /// a later part may not carry.
    /// </summary>
    private void DeclareAdditionalPart(
        TypeDeclSyntax declaration, NamedTypeSymbol existing, FileScope scope)
    {
        // An enum, a delegate and a closure were not made by a type
        // declaration, so they have no kind of one to compare -- and asked for
        // one they read as a struct, which let a struct be accepted as more of
        // a delegate.
        if (existing is EnumTypeSymbol or DelegateTypeSymbol or ClosureTypeSymbol ||
            KindOf(existing) != declaration.Kind ||
            (existing is ComInterfaceTypeSymbol) != declaration.Modifiers.HasFlag(Modifiers.Com))
        {
            diagnostics.Error("SL0550", declaration.Span,
                $"'{declaration.Name}' is already declared in this module as a " +
                $"{Described(existing)}, so this declaration cannot add to it. A type may be " +
                "declared more than once inside its own module, but every declaration must " +
                "agree about what it is");
            return;
        }

        if (declaration.Implements.Count > 0)
        {
            if (!SpansDeclarations(existing))
                diagnostics.Error("SL0551", declaration.Span,
                    $"'{declaration.Name}' is already declared in this module, so this " +
                    "declaration may add members but not a base list; only a class takes its " +
                    "base list from a declaration other than the first");
            else if (_typeSyntax[existing].Declaration.Implements.Count > 0 ||
                     _baseListSyntax.ContainsKey(existing))
                diagnostics.Error("SL0551", declaration.Span,
                    $"'{declaration.Name}' already says what it derives from in another " +
                    "declaration; write the base list on exactly one of them");
            else
                _baseListSyntax[existing] = (declaration, scope);
        }

        if (declaration.IsOpaque)
            diagnostics.Error("SL0551", declaration.Span,
                $"'{declaration.Name}' is already declared in this module, so this declaration " +
                "has nothing to say by having no body");

        _additionalParts.Add(declaration);
        _declaredTypes[declaration] = existing;
    }

    /// <summary>
    /// Whether a later declaration may add fields and a base list. A class's
    /// layout is its own; a struct's is C's and an intrinsic's the runtime's.
    /// </summary>
    private static bool SpansDeclarations(NamedTypeSymbol type) =>
        type is ClassTypeSymbol { IsIntrinsic: false, IsCom: false };

    /// <summary>The kind of declaration a symbol came from, for comparing two.</summary>
    private static TypeDeclKind KindOf(NamedTypeSymbol type) => type switch
    {
        ComInterfaceTypeSymbol => TypeDeclKind.Interface,
        InterfaceTypeSymbol => TypeDeclKind.Interface,
        AttributeTypeSymbol => TypeDeclKind.Attribute,
        VariantTypeSymbol => TypeDeclKind.Variant,
        UnionTypeSymbol => TypeDeclKind.Union,
        ClassTypeSymbol => TypeDeclKind.Class,
        _ => TypeDeclKind.Struct,
    };

    private static string Described(NamedTypeSymbol type) => type switch
    {
        ComInterfaceTypeSymbol => "com interface",
        InterfaceTypeSymbol => "interface",
        AttributeTypeSymbol => "attribute",
        VariantTypeSymbol => "variant",
        UnionTypeSymbol => "union",
        ClassTypeSymbol => "class",
        DelegateTypeSymbol => "delegate",
        ClosureTypeSymbol => "closure",
        EnumTypeSymbol => "enum",
        _ => "struct",
    };
}
