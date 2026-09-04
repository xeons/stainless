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

/// <summary>The fully resolved program handed to the emitter.</summary>
public sealed class BoundProgram
{
    public required IReadOnlyList<ModuleSymbol> Modules { get; init; }
    public required IReadOnlyList<BoundFunction> Functions { get; init; }
    public required IReadOnlyList<ClassTypeSymbol> Classes { get; init; }
    public required IReadOnlyList<InterfaceTypeSymbol> Interfaces { get; init; }

    /// <summary>
    /// Every struct type the program uses: those declared in a module, and the
    /// instantiations of a generic one. An instantiation belongs to no module's
    /// type table, so without this the IR would name a type nothing defined.
    /// </summary>
    public required IReadOnlyList<StructTypeSymbol> Structs { get; init; }

    /// <summary>Every distinct array type used, each needing its own TypeInfo.</summary>
    public required IReadOnlyList<ArrayTypeSymbol> Arrays { get; init; }

    /// <summary>Runtime constructors for intrinsic classes, needing a declaration in the IR.</summary>
    public required IReadOnlyList<string> RuntimeFactories { get; init; }
    public required IReadOnlyList<FunctionSymbol> ExternalFunctions { get; init; }
    public FunctionSymbol? EntryPoint { get; init; }

    /// <summary>Module-level storage, in the order its initializers must run.</summary>
    public required IReadOnlyList<StaticSymbol> Statics { get; init; }
}

/// <summary>
/// Turns parsed files into a typed program.
///
/// The passes exist in this order for one reason: Stainless has no headers, so
/// nothing may depend on declaration order. Every name in the program is known
/// before any body is checked, which is exactly the guarantee a header file
/// exists to fake in C and C++.
/// </summary>
/// <param name="requireEntryPoint">
/// False when building a library, which has no <c>Main</c> and must not be
/// warned about one.
/// </param>
public sealed class Binder(
    DiagnosticBag diagnostics,
    bool requireEntryPoint = true,
    CppAbi? cppAbi = null,
    IReadOnlyList<Driver.ModuleMetadata>? references = null)
{
    private readonly Builtins _builtins = new();

    /// <summary>The C++ ABI names are mangled for, defaulting to the host's.</summary>
    private readonly CppAbi _cppAbi = cppAbi ?? CppMangler.HostAbi;
    private readonly Dictionary<string, ModuleSymbol> _modules = new(StringComparer.Ordinal);
    private readonly List<(FileScope Scope, CompilationUnitSyntax Unit)> _units = [];
    private readonly List<BoundFunction> _functions = [];
    private readonly List<ClassTypeSymbol> _classes = [];
    private readonly List<InterfaceTypeSymbol> _interfaces = [];
    private readonly List<StructTypeSymbol> _structs = [];

    /// <summary>
    /// Which case each variant in scope is known to be holding. A fact is put
    /// here by a condition that tested one, and taken away by anything that
    /// could have changed it.
    /// </summary>
    private Dictionary<object, VariantCaseSymbol> _variantFacts = [];
    private readonly Dictionary<TypeSymbol, ArrayTypeSymbol> _arrays = [];
    private readonly Dictionary<TypeSymbol, SliceTypeSymbol> _slices = [];

    /// <summary>Instantiated generics, keyed by template and type arguments.</summary>
    private readonly Dictionary<string, NamedTypeSymbol> _instantiatedTypes = new(StringComparer.Ordinal);
    private readonly Dictionary<string, FunctionSymbol> _instantiatedFunctions = new(StringComparer.Ordinal);

    /// <summary>
    /// Bodies already bound. An instantiated method is reachable both through its
    /// module's function list and through the pending queue, so without this it
    /// would be bound twice and emitted twice.
    /// </summary>
    private readonly HashSet<FunctionSymbol> _boundFunctions = [];

    /// <summary>Bodies awaiting binding, with the substitution they belong to.</summary>
    private readonly Queue<(FunctionSymbol Function, Dictionary<string, TypeSymbol> Substitution)> _pending = new();

    /// <summary>The type arguments in force while binding inside an instantiation.</summary>
    private Dictionary<string, TypeSymbol> _substitution = new(StringComparer.Ordinal);
    private readonly Dictionary<NamedTypeSymbol, (TypeDeclSyntax Declaration, FileScope Scope)> _typeSyntax = [];
    private readonly Dictionary<EnumTypeSymbol, (EnumDeclSyntax Declaration, FileScope Scope)> _enumSyntax = [];
    private readonly Dictionary<DelegateTypeSymbol, (DelegateDeclSyntax Declaration, FileScope Scope)> _delegateSyntax = [];
    private readonly Dictionary<StaticSymbol, (StaticDeclSyntax Declaration, FileScope Scope)> _staticSyntax = [];
    private List<StaticSymbol> _staticOrder = [];

    /// <summary>
    /// Numbers the hidden locals a lowering introduces. A '$' cannot appear in a
    /// source identifier, and the counter keeps nested lowerings of the same
    /// construct from colliding with one another.
    /// </summary>
    private int _synthetic;

    /// <summary>How many 'parallel' scopes enclose what is being bound.</summary>
    private int _parallelDepth;

    private string SyntheticName(string hint) => $"${hint}.{_synthetic++}";

    // Per-function binding state.
    private FunctionSymbol? _currentFunction;

    /// <summary>The file being bound. Imports are per-file, so this is the unit of lookup.</summary>
    private FileScope? _currentScope;
    private ModuleSymbol? _currentModule => _currentScope?.Module;
    private readonly List<Dictionary<string, LocalSymbol>> _scopes = [];
    private int _loopDepth;

    /// <summary>
    /// How many <c>switch</c> statements enclose what is being bound. Separate
    /// from the loop depth because a switch is a target for <c>break</c> but not
    /// for <c>continue</c>, which passes straight through it to the loop.
    /// </summary>
    private int _switchDepth;

    public BoundProgram Bind(IReadOnlyList<CompilationUnitSyntax> units)
    {
        _builtins.RegisterInto(_modules);

        // A referenced library's declarations come first, so a source file can
        // name them exactly as it names anything else. This runs before pass 1
        // rather than as one of them: it declares rather than resolves, and a
        // program with no references skips it entirely.
        if (references is { Count: > 0 })
        {
            var loader = new MetadataLoader(diagnostics);
            loader.RegisterIntrinsics(_modules.Values);
            loader.Load(references, _modules);
        }

        DeclareModules(units);      // pass 1: every module exists
        DeclareTypes();             // pass 2: every type name exists
        ResolveImports();           // pass 3: every module can see its imports
        DeclareMembers();           // pass 4: every signature and field type is resolved
        ResolveInterfaces();        // pass 5: every class satisfies what it claims
        ResolveAttributes();        // pass 6: attributes fold to constants
        ComputeLayouts();           // pass 7: every value type has a size
        CheckUnions();              //         and a union counts nothing
        ValidateLinkageSignatures();// pass 8: no counted reference crosses a language boundary
        BindBodies();               // pass 9: only now is any code checked
        BindStatics();              // pass 10: static initializers, then their order
        DrainPending();             // pass 11: bodies of everything instantiated along the way
        CheckConstructorDelegation();
        ResolveRemainingAliases();

        // Interface ids are assigned last, because instantiating a generic can
        // introduce a new interface at any point up to here.
        for (int id = 0; id < _interfaces.Count; id++) _interfaces[id].Id = id;

        var external = _modules.Values
            .SelectMany(m => m.Functions)
            .Where(f => f.Linkage.IsImport() || f.IsExternal)
            .GroupBy(f => f.MangledName)
            .Select(g => g.First())
            .ToList();

        return new BoundProgram
        {
            Modules = _modules.Values.ToList(),
            Functions = _functions,
            Classes = _classes,
            Interfaces = _interfaces,
            Structs = _modules.Values
                .SelectMany(m => m.Types.Values)
                .OfType<StructTypeSymbol>()
                .Concat(_structs)
                .ToList(),
            Arrays = _arrays.Values.ToList(),
            RuntimeFactories = _modules.Values
                .SelectMany(m => m.Types.Values)
                .OfType<ClassTypeSymbol>()
                .Select(c => c.RuntimeFactory)
                .OfType<string>()
                .Distinct(StringComparer.Ordinal)
                .Order(StringComparer.Ordinal)
                .ToList(),
            ExternalFunctions = external,
            EntryPoint = requireEntryPoint ? FindEntryPoint() : null,
            Statics = _staticOrder,
        };
    }

    // ============================================================ pass 1

    private void DeclareModules(IReadOnlyList<CompilationUnitSyntax> units)
    {
        foreach (var unit in units)
        {
            if (unit.ModuleName is null)
            {
                diagnostics.Error("SL0332", new SourceSpan(unit.File, 0, 0),
                    "this file does not say which module it belongs to; " +
                    "start it with a declaration such as 'module App.Thing;'");
                continue;
            }

            string name = unit.ModuleName.Text;

            // Several files may declare the same module and merge into it, as C#
            // namespaces do. Each still gets its own scope, because imports are
            // written per file.
            if (!_modules.TryGetValue(name, out var module))
            {
                module = new ModuleSymbol(name);
                _modules[name] = module;
            }

            var scope = new FileScope(module);
            _builtins.AutoImportInto(scope);
            _units.Add((scope, unit));
        }
    }

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
                        diagnostics.Error("SL0321", declaration.Span,
                            $"'{declaration.Name}' is already declared in module '{module.Name}'");
                    else
                        module.GenericTypes[declaration.Name] =
                            new GenericTypeTemplate(declaration.Name, scope, declaration);
                    continue;
                }

                bool isPublic = declaration.Modifiers.HasFlag(Modifiers.Public);
                NamedTypeSymbol type = declaration.Kind switch
                {
                    TypeDeclKind.Class => new ClassTypeSymbol
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

    // ============================================================ pass 3

    private void ResolveImports()
    {
        foreach (var (scope, unit) in _units)
        {
            foreach (var import in unit.Imports)
            {
                if (!_modules.TryGetValue(import.Name.Text, out var target))
                {
                    diagnostics.Error("SL0202", import.Span,
                        $"module '{import.Name.Text}' was not found among the compiled sources");
                    continue;
                }

                if (target == scope.Module)
                {
                    diagnostics.Warning("SL0203", import.Span,
                        "a file does not need to import its own module");
                    continue;
                }

                string key = import.Alias ?? import.Name.Last;
                scope.Imports[key] = target;

                // The full dotted name always works too, so `import A.B;` lets you
                // write both `B.Thing` and `A.B.Thing`.
                scope.Imports[import.Name.Text] = target;
            }
        }
    }

    // ============================================================ pass 4

    private void DeclareMembers()
    {
        foreach (var (scope, unit) in _units)
        {
            _currentScope = scope;
            var module = scope.Module;

            foreach (var declaration in unit.Declarations)
            {
                switch (declaration)
                {
                    case FunctionDeclSyntax function:
                        if (function.TypeParameters.Count > 0)
                            module.GenericFunctions.Add(
                                new GenericFunctionTemplate(function.Name, scope, function));
                        else
                            DeclareFunction(scope, containingType: null, function);
                        break;

                    case TypeDeclSyntax typeDecl:
                        // Templates wait; their members depend on type arguments.
                        if (typeDecl.TypeParameters.Count == 0)
                            DeclareTypeMembers(scope, typeDecl, module.Types[typeDecl.Name]);
                        break;

                    case StaticDeclSyntax staticDecl:
                        DeclareStatic(scope, staticDecl);
                        break;

                    case DelegateDeclSyntax delegateDecl:
                        DeclareDelegateSignature(
                            (DelegateTypeSymbol)module.Types[delegateDecl.Name], delegateDecl, scope);
                        break;

                    case EnumDeclSyntax enumDecl:
                        DeclareEnumMembers(
                            (EnumTypeSymbol)module.Types[enumDecl.Name], enumDecl, scope);
                        break;

                    case GlobalConstDeclSyntax constant:
                        DeclareGlobalConstant(scope, constant);
                        break;

                    case FieldDeclSyntax field:
                        diagnostics.Error("SL0204", field.Span,
                            $"'{field.Name}' is a module-level variable; only 'const' values are " +
                            "allowed at module scope");
                        break;

                    case PropertyDeclSyntax property:
                        diagnostics.Error("SL0400", property.Span,
                            $"'{property.Name}' is a property, and a property belongs to a type; " +
                            "a module has no instance for its accessors to read");
                        break;
                }
            }
        }

        _currentScope = null;
    }

    /// <summary>
    /// Resolves a delegate's return and parameter types. The names are kept for
    /// diagnostics and for the generated C header; nothing else reads them.
    /// </summary>
    private void DeclareDelegateSignature(
        DelegateTypeSymbol type, DelegateDeclSyntax declaration, FileScope scope)
    {
        type.ReturnType = ResolveType(declaration.ReturnType, scope);

        for (int i = 0; i < declaration.Parameters.Count; i++)
        {
            var parameter = declaration.Parameters[i];
            var parameterType = ResolveType(parameter.Type, scope);

            if (parameterType.IsVoid())
            {
                diagnostics.Error("SL0359", parameter.Span,
                    $"parameter '{parameter.Name}' of delegate '{type.Name}' cannot be 'void'");
                parameterType = ErrorTypeSymbol.Instance;
            }

            type.Signature.Add(new ParameterSymbol(parameter.Name, parameterType, i)
            {
                Mode = parameter.Mode,
            });
        }
    }

    /// <summary>
    /// Resolves an enum's underlying type and folds its members to constants.
    ///
    /// A member without a value continues from the previous one, starting at
    /// zero, as in C and C#. The values are checked against the underlying type
    /// here so that a too-large constant is reported at the enum, not at a use.
    /// </summary>
    private void DeclareEnumMembers(EnumTypeSymbol type, EnumDeclSyntax declaration, FileScope scope)
    {
        if (declaration.UnderlyingType is not null)
        {
            var underlying = ResolveType(declaration.UnderlyingType, scope);
            if (underlying is PrimitiveTypeSymbol { IsInteger: true } integer)
            {
                type.UnderlyingType = integer;
            }
            else if (!underlying.IsError())
            {
                diagnostics.Error("SL0350", declaration.UnderlyingType.Span,
                    $"an enum must be built on an integer type, but '{underlying.Name}' is not one");
            }
        }

        ulong next = 0;

        foreach (var member in declaration.Members)
        {
            if (type.FindMember(member.Name) is not null)
            {
                diagnostics.Error("SL0351", member.Span,
                    $"'{type.Name}' already has a member named '{member.Name}'");
                continue;
            }

            ulong value = next;

            if (member.Value is not null)
            {
                if (FoldEnumValue(member.Value, type.UnderlyingType) is { } folded)
                    value = folded;
                else
                    diagnostics.Error("SL0352", member.Value.Span,
                        $"the value of '{type.Name}.{member.Name}' must be an integer constant");
            }

            type.Members.Add(new EnumMemberSymbol(member.Name, type, value));
            next = value + 1;
        }
    }

    /// <summary>An enum member's constant: an integer literal, optionally negated.</summary>
    private ulong? FoldEnumValue(ExpressionSyntax syntax, PrimitiveTypeSymbol underlying)
    {
        bool negate = false;

        while (syntax is UnarySyntax { Operator: TokenKind.Minus or TokenKind.Plus } unary)
        {
            if (unary.Operator == TokenKind.Minus) negate = !negate;
            syntax = unary.Operand;
        }

        if (syntax is not LiteralSyntax { Kind: TokenKind.IntLiteral, Value: ulong raw }) return null;

        ulong value = negate ? unchecked((ulong)-(long)raw) : raw;

        // Keep only the bits the underlying type actually has.
        return underlying.Size >= 8 ? value : value & ((1UL << underlying.Bits) - 1);
    }

    /// <summary>
    /// Turns a variant's cases into symbols, and gives the variant the two
    /// fields that represent it.
    ///
    /// Each case's parameters become a struct of their own. That struct is an
    /// ordinary one — laid out, copied, retained and described by the machinery
    /// that already exists — and the case is a name for it plus a tag. The
    /// variant itself then has two fields: the tag, and a filler wide enough for
    /// the largest payload, whose size is not known until every case has been
    /// laid out and so is settled in pass 7.
    /// </summary>
    private void DeclareVariantCases(
        FileScope scope, TypeDeclSyntax declaration, VariantTypeSymbol variant)
    {
        if (declaration.Cases.Count > 255)
            diagnostics.Error("SL0432", declaration.Span,
                $"variant '{variant.Name}' has {declaration.Cases.Count} cases; the tag is a " +
                "byte, so 255 is the limit");

        foreach (var declared in declaration.Cases)
        {
            if (variant.FindCase(declared.Name) is not null)
            {
                diagnostics.Error("SL0433", declared.Span,
                    $"variant '{variant.Name}' already has a case named '{declared.Name}'");
                continue;
            }

            var caseSymbol = new VariantCaseSymbol
            {
                Name = declared.Name,
                DeclaringVariant = variant,
                Tag = variant.Cases.Count,
                Span = declared.Span,
            };

            if (declared.Parameters.Count > 0)
            {
                var payload = new StructTypeSymbol
                {
                    // '$' is in no identifier, so this names a type the source
                    // cannot reach. It is reached through the case instead.
                    SimpleName = variant.SimpleName + "$" + declared.Name,
                    ModuleName = variant.ModuleName,
                    IsPublic = variant.IsPublic,
                    Span = declared.Span,
                };

                foreach (var parameter in declared.Parameters)
                {
                    if (payload.FindStorage(parameter.Name) is not null)
                    {
                        diagnostics.Error("SL0434", parameter.Span,
                            $"case '{declared.Name}' already carries a field named " +
                            $"'{parameter.Name}'");
                        continue;
                    }

                    payload.Fields.Add(new FieldSymbol(
                        parameter.Name, ResolveType(parameter.Type, scope),
                        payload, payload.Fields.Count) { IsPublic = true });
                }

                _structs.Add(payload);
                caseSymbol.Payload = payload;
            }

            variant.Cases.Add(caseSymbol);
        }

        // The tag first, so a variant with no payload at all is one byte and
        // reads like an enum. Both fields are hidden storage: the case is the
        // name for what is in there, and reaching past it would be reading a
        // payload without the proof that makes it mean anything.
        variant.Fields.Add(new FieldSymbol(
            VariantTypeSymbol.TagFieldName, PrimitiveTypeSymbol.Byte, variant, 0)
        {
            IsBackingField = true,
        });

        if (!variant.Cases.Any(c => c.Payload is not null)) return;

        var storage = new StructTypeSymbol
        {
            SimpleName = variant.SimpleName + "$payload",
            ModuleName = variant.ModuleName,
            IsPublic = variant.IsPublic,
            Span = declaration.Span,
        };

        _structs.Add(storage);
        variant.PayloadStorage = storage;

        variant.Fields.Add(new FieldSymbol(
            VariantTypeSymbol.PayloadFieldName, storage, variant, 1)
        {
            IsBackingField = true,
        });
    }

    /// <summary>
    /// The width of a bit-field, checked against what may be one.
    ///
    /// A bit-field is storage measured in bits rather than bytes, so what may
    /// have one is what the target's C compiler will give one: an integer or a
    /// bool. The width has to be a constant, because the layout of everything
    /// after it depends on the number.
    /// </summary>
    private int? BindBitWidth(
        FieldDeclSyntax field, TypeSymbol fieldType, NamedTypeSymbol owner, FileScope scope)
    {
        if (owner is not StructTypeSymbol || owner is VariantTypeSymbol)
        {
            diagnostics.Error("SL0469", field.Span,
                $"'{owner.Name}.{field.Name}' is a bit-field, and only a struct or a union has " +
                "those; a class lays its fields out behind a header the compiler owns");
            return null;
        }

        bool usable = fieldType is PrimitiveTypeSymbol { IsInteger: true } or
                                   PrimitiveTypeSymbol { Kind: PrimitiveKind.Bool };

        if (!usable)
        {
            diagnostics.Error("SL0471", field.Span,
                $"'{fieldType.Name}' cannot be a bit-field; a bit-field is some of the bits of " +
                "an integer or a bool");
            return null;
        }

        if (ConstantValue(field.BitWidth!, PrimitiveTypeSymbol.Int) is not { } value)
        {
            diagnostics.Error("SL0472", field.BitWidth!.Span,
                "a bit-field's width must be a constant; the layout of everything after it " +
                "depends on the number");
            return null;
        }

        long width = Convert.ToInt64(value, System.Globalization.CultureInfo.InvariantCulture);
        int capacity = fieldType.Size * 8;

        if (width <= 0)
        {
            diagnostics.Error("SL0473", field.BitWidth!.Span,
                $"a bit-field is at least one bit wide, and '{field.Name}' asks for {width}. " +
                "C's zero-width field, which closes a storage unit, is not written yet");
            return null;
        }

        if (width > capacity)
        {
            diagnostics.Error("SL0474", field.BitWidth!.Span,
                $"'{field.Name}' asks for {width} bits, and '{fieldType.Name}' has {capacity}");
            return null;
        }

        return (int)width;
    }

    private void DeclareTypeMembers(
        FileScope scope, TypeDeclSyntax declaration, NamedTypeSymbol type)
    {
        var module = scope.Module;
        var classType = type as ClassTypeSymbol;

        if (type is VariantTypeSymbol variant) DeclareVariantCases(scope, declaration, variant);

        foreach (var member in declaration.Members)
        {
            if (type is AttributeTypeSymbol && member is not FieldDeclSyntax)
            {
                diagnostics.Error("SL0340", member.Span,
                    $"attribute '{type.Name}' may only declare fields; " +
                    "it is compile-time data, not a type with behaviour");
                continue;
            }

            if (type is InterfaceTypeSymbol && member is not (FunctionDeclSyntax or PropertyDeclSyntax))
            {
                diagnostics.Error("SL0300", member.Span,
                    $"interface '{type.Name}' may only declare methods and properties; " +
                    "it has no state, no constructor and no destructor");
                continue;
            }

            switch (member)
            {
                case FieldDeclSyntax field:
                {
                    if (type.FindStorage(field.Name) is not null ||
                        type.FindProperty(field.Name) is not null)
                    {
                        diagnostics.Error("SL0205", field.Span,
                            $"'{type.Name}' already declares a member named '{field.Name}'");
                        break;
                    }
                    if (field.Initializer is not null)
                        diagnostics.Error("SL0206", field.Span,
                            "field initializers are not supported yet; assign the field in a constructor");

                    var fieldType = ResolveType(field.Type, scope);

                    // A struct holding a reference is allowed, and copying one
                    // then retains what it holds. What it costs is the C
                    // guarantee: such a struct is no longer bytes a C function
                    // could be handed, which ValidateLinkageSignature enforces.

                    if (Dispatchable(field.Modifiers) is { } wrongOnAField)
                        diagnostics.Error("SL0497", field.Span,
                            $"'{type.Name}.{field.Name}' is a field, so it cannot be " +
                            $"'{wrongOnAField}'; only a method or a property is dispatched");

                    if (field.Modifiers.HasFlag(Modifiers.Protected) &&
                        type is not ClassTypeSymbol)
                        diagnostics.Error("SL0519", field.Span,
                            $"'{type.Name}.{field.Name}' cannot be 'protected'; the word means " +
                            "'and anything deriving from this', and only a class is derived from");

                    var declared = new FieldSymbol(field.Name, fieldType, type, type.Fields.Count)
                    {
                        IsPublic = field.Modifiers.HasFlag(Modifiers.Public),
                        IsProtected = field.Modifiers.HasFlag(Modifiers.Protected),
                        IsAnonymous = field.IsAnonymous,
                    };

                    if (field.BitWidth is not null)
                        declared.BitWidth = BindBitWidth(field, fieldType, type, scope);

                    type.Fields.Add(declared);
                    break;
                }

                case FunctionDeclSyntax method:
                    if (method.TypeParameters.Count > 0)
                    {
                        if (type is InterfaceTypeSymbol)
                        {
                            // A vtable has one slot per method, and a generic
                            // method has as many bodies as it has instantiations.
                            diagnostics.Error("SL0322", method.Span,
                                $"'{method.Name}' is generic, and an interface method cannot be; " +
                                "dispatch needs one entry per method, and a generic one has " +
                                "a body per instantiation");
                            break;
                        }

                        // The substitution in force is the enclosing type's, if it
                        // is itself an instantiation; the method's own parameters
                        // are merged onto it at each call.
                        type.GenericMethods.Add(new GenericFunctionTemplate(method.Name, scope, method)
                        {
                            ContainingType = type,
                            OuterSubstitution = new Dictionary<string, TypeSymbol>(
                                _substitution, StringComparer.Ordinal),
                        });
                        break;
                    }
                    DeclareFunction(scope, type, method);
                    break;

                case PropertyDeclSyntax property:
                    DeclareProperty(scope, type, property);
                    break;

                // Only pass 2 declares aliases, and it looks at the top level.
                // Taking one here and dropping it is the shape of bug this
                // language keeps finding in itself, so it is refused instead.
                case AliasDeclSyntax alias:
                    diagnostics.Error("SL0525", alias.Span,
                        $"'{alias.Name}' is a type alias inside '{type.Name}'; an alias belongs " +
                        "to a module, which is what this language has instead of a namespace. " +
                        "Move it out of the type");
                    break;

                case ConstructorDeclSyntax constructor:
                {
                    if (classType is null)
                    {
                        diagnostics.Error("SL0207", constructor.Span,
                            $"'{type.Name}' is a struct; structs are plain C values and have no constructors");
                        break;
                    }
                    var symbol = new FunctionSymbol
                    {
                        Name = "ctor",
                        ModuleName = module.Name,
                        ReturnType = PrimitiveTypeSymbol.Void,
                        Linkage = LinkageKind.Stainless,
                        Kind = FunctionKind.Constructor,
                        ContainingType = type,
                        Body = constructor.Body,
                        Span = constructor.Span,
                        Scope = scope,
                        IsPublic = constructor.Modifiers.HasFlag(Modifiers.Public),
                    };
                    symbol.Parameters.Add(new ParameterSymbol("this", classType, 0) { IsThis = true });
                    AddParameters(symbol, constructor.Parameters, scope);
                    classType.Constructors.Add(symbol);
                    break;
                }

                case DestructorDeclSyntax destructor:
                {
                    if (classType is null)
                    {
                        diagnostics.Error("SL0208", destructor.Span,
                            $"'{type.Name}' is a struct; only classes are reference counted and can have a destructor");
                        break;
                    }
                    if (classType.Destructor is not null)
                    {
                        diagnostics.Error("SL0209", destructor.Span,
                            $"'{type.Name}' already declares a destructor");
                        break;
                    }
                    var symbol = new FunctionSymbol
                    {
                        Name = "dtor",
                        ModuleName = module.Name,
                        ReturnType = PrimitiveTypeSymbol.Void,
                        Linkage = LinkageKind.Stainless,
                        Kind = FunctionKind.Destructor,
                        ContainingType = type,
                        Body = destructor.Body,
                        Span = destructor.Span,
                        Scope = scope,
                    };
                    symbol.Parameters.Add(new ParameterSymbol("this", classType, 0) { IsThis = true });
                    classType.Destructor = symbol;
                    break;
                }
            }
        }
    }

    /// <summary>
    /// Declares a property: the pair of methods it really is, and the hidden
    /// field it keeps its value in when it asked for one.
    ///
    /// Everything downstream sees methods and a field. That is what makes a
    /// property free: it dispatches through an interface, crosses a generic
    /// instantiation and lands in a vtable without any of those knowing it is
    /// not an ordinary method.
    /// </summary>
    private void DeclareProperty(
        FileScope scope, NamedTypeSymbol type, PropertyDeclSyntax declaration)
    {
        if (type.FindStorage(declaration.Name) is not null ||
            type.FindProperty(declaration.Name) is not null)
        {
            diagnostics.Error("SL0386", declaration.Span,
                $"'{type.Name}' already declares a member named '{declaration.Name}'");
            return;
        }

        var propertyType = ResolveType(declaration.Type, scope);
        if (propertyType.IsVoid())
        {
            diagnostics.Error("SL0387", declaration.Span,
                $"property '{type.Name}.{declaration.Name}' cannot have type 'void'; " +
                "a property is a value, and 'void' is the absence of one");
            propertyType = ErrorTypeSymbol.Instance;
        }

        var getter = declaration.Accessors.FirstOrDefault(a => a.IsGetter);
        var setter = declaration.Accessors.FirstOrDefault(a => !a.IsGetter);

        if (declaration.Accessors.Count > 2 || declaration.Accessors.Count(a => a.IsGetter) > 1)
        {
            diagnostics.Error("SL0388", declaration.Span,
                $"property '{type.Name}.{declaration.Name}' declares the same accessor twice");
            return;
        }

        if (getter is null)
        {
            // A value that can only be written is a method, and reads better as
            // one. Allowing the shape would only disguise that.
            diagnostics.Error("SL0389", declaration.Span,
                setter is null
                    ? $"property '{type.Name}.{declaration.Name}' declares no accessor; write 'get;'"
                    : $"property '{type.Name}.{declaration.Name}' has a setter but no getter; " +
                      "something that can only be written is a method, not a property");
            return;
        }

        bool isInterface = type is InterfaceTypeSymbol;
        bool isAbstract = declaration.Modifiers.HasFlag(Modifiers.Abstract);
        bool wantsStorage = false;

        if (isInterface || isAbstract)
        {
            foreach (var accessor in declaration.Accessors.Where(a => a.Body is not null))
                diagnostics.Error("SL0392", accessor.Span,
                    isInterface
                        ? $"'{type.Name}.{declaration.Name}' is an interface property, so its " +
                          $"{(accessor.IsGetter ? "getter" : "setter")} cannot have a body; " +
                          "interfaces declare signatures only"
                        : $"'{type.Name}.{declaration.Name}' is abstract, so its " +
                          $"{(accessor.IsGetter ? "getter" : "setter")} cannot have a body; " +
                          "a derived class supplies one");
        }
        else
        {
            bool getterIsAuto = getter.Body is null;

            // Half a hidden field is not a thing: an automatic accessor and a
            // written one would have to agree about storage nothing can name.
            if (setter is not null && (setter.Body is null) != getterIsAuto)
            {
                diagnostics.Error("SL0391", declaration.Span,
                    $"property '{type.Name}.{declaration.Name}' mixes an automatic accessor " +
                    "with a written one; either both are automatic, or both have bodies and " +
                    "name storage the type already declares");
                return;
            }

            wantsStorage = getterIsAuto;

            // A struct has no constructor, so a get-only automatic property on
            // one has no moment at which it could ever be given a value.
            if (wantsStorage && setter is null && type is StructTypeSymbol)
                diagnostics.Error("SL0401", declaration.Span,
                    $"'{type.Name}.{declaration.Name}' could never be assigned: it is automatic " +
                    "and has no setter, and a struct has no constructor to fill it in; add " +
                    "'set;', or give it a body that computes the value");
        }

        FieldSymbol? backing = null;
        if (wantsStorage)
        {
            // Named after the property, because that is what the storage is. It
            // is hidden from lookup, so nothing can reach past the accessors.
            backing = new FieldSymbol(declaration.Name, propertyType, type, type.Fields.Count)
            {
                IsBackingField = true,
            };
            type.Fields.Add(backing);
        }

        var property = new PropertySymbol
        {
            Name = declaration.Name,
            Type = propertyType,
            ContainingType = type,
            Span = declaration.Span,
            IsPublic = declaration.Modifiers.HasFlag(Modifiers.Public) || isInterface,
            IsProtected = declaration.Modifiers.HasFlag(Modifiers.Protected),
            BackingField = backing,
        };

        // A property's dispatch is its accessors' -- they are the methods, and a
        // vtable has no notion of a property at all.
        var accessorModifiers = declaration.Modifiers;

        property.Getter = DeclareAccessor(scope, type, property, getter, false, accessorModifiers);
        if (setter is not null)
            property.Setter = DeclareAccessor(scope, type, property, setter, true, accessorModifiers);

        type.Properties.Add(property);
    }

    /// <summary>
    /// Declares one accessor as the method it is: <c>get_Name</c> returning the
    /// property type, or <c>set_Name</c> taking one parameter called
    /// <c>value</c> — which is why <c>value</c> resolves inside a setter with no
    /// special case anywhere in name lookup.
    /// </summary>
    private FunctionSymbol? DeclareAccessor(
        FileScope scope, NamedTypeSymbol type, PropertySymbol property,
        AccessorSyntax accessor, bool isSetter, Modifiers modifiers)
    {
        string role = isSetter ? "setter" : "getter";
        string name = (isSetter ? "set_" : "get_") + property.Name;

        if (type.FindMethod(name) is not null)
        {
            diagnostics.Error("SL0393", accessor.Span,
                $"'{type.Name}' already declares a method named '{name}', which is the name " +
                $"the {role} of property '{property.Name}' has to use");
            return null;
        }

        // A setter may be narrowed; a getter may not. The getter is what the
        // property's visibility means, so letting it differ would only make the
        // word 'public' on the property itself a lie.
        bool isPublic = property.IsPublic;
        if (accessor.Modifiers.HasFlag(Modifiers.Private))
        {
            if (isSetter) isPublic = false;
            else
                diagnostics.Error("SL0394", accessor.Span,
                    $"the getter of '{type.Name}.{property.Name}' is what makes the property " +
                    "public or not, so it cannot be narrowed on its own; write the property " +
                    "itself without 'public', or narrow the setter instead");
        }

        var symbol = new FunctionSymbol
        {
            Name = name,
            ModuleName = scope.Module.Name,
            ReturnType = isSetter ? PrimitiveTypeSymbol.Void : property.Type,
            Linkage = LinkageKind.Stainless,
            Kind = FunctionKind.Method,
            ContainingType = type,
            IsPublic = isPublic,
            IsProtected = property.IsProtected,
            IsVirtual = modifiers.HasFlag(Modifiers.Virtual)
                        || modifiers.HasFlag(Modifiers.Override)
                        || modifiers.HasFlag(Modifiers.Abstract),
            IsOverride = modifiers.HasFlag(Modifiers.Override),
            IsAbstract = modifiers.HasFlag(Modifiers.Abstract),
            IsSealed = modifiers.HasFlag(Modifiers.Sealed),
            Body = accessor.Body,
            Span = accessor.Span,
            Scope = scope,
            Accessor = property,
            IsAutoAccessor = accessor.Body is null
                             && type is not InterfaceTypeSymbol
                             && !modifiers.HasFlag(Modifiers.Abstract),
        };

        TypeSymbol thisType = type is ClassTypeSymbol reference
            ? reference
            : new PointerTypeSymbol(type);
        symbol.Parameters.Add(new ParameterSymbol("this", thisType, 0) { IsThis = true });

        if (isSetter)
            symbol.Parameters.Add(new ParameterSymbol("value", property.Type, 1));

        type.Methods.Add(symbol);
        scope.Module.Functions.Add(symbol);
        return symbol;
    }

    private void DeclareFunction(FileScope scope, NamedTypeSymbol? containingType, FunctionDeclSyntax declaration)
    {
        var module = scope.Module;
        var returnType = ResolveType(declaration.ReturnType, scope);

        var symbol = new FunctionSymbol
        {
            Name = declaration.Name,
            ModuleName = module.Name,
            ReturnType = returnType,
            Linkage = declaration.Linkage,
            Kind = containingType is null ? FunctionKind.Function : FunctionKind.Method,
            ContainingType = containingType,
            // Every interface member is part of the contract, so it is public
            // whether or not the programmer wrote the word.
            IsPublic = declaration.Modifiers.HasFlag(Modifiers.Public)
                       || containingType is InterfaceTypeSymbol,
            IsProtected = declaration.Modifiers.HasFlag(Modifiers.Protected),
            IsVirtual = declaration.Modifiers.HasFlag(Modifiers.Virtual)
                        || declaration.Modifiers.HasFlag(Modifiers.Override)
                        || declaration.Modifiers.HasFlag(Modifiers.Abstract),
            IsOverride = declaration.Modifiers.HasFlag(Modifiers.Override),
            IsAbstract = declaration.Modifiers.HasFlag(Modifiers.Abstract),
            IsSealed = declaration.Modifiers.HasFlag(Modifiers.Sealed),
            IsVariadic = declaration.IsVariadic,
            Body = declaration.Body,
            Span = declaration.Span,
            Scope = scope,
        };

        if (containingType is not null)
        {
            // A method receives its instance: classes by reference, structs by pointer.
            TypeSymbol thisType = containingType is ClassTypeSymbol c
                ? c
                : new PointerTypeSymbol(containingType);
            symbol.Parameters.Add(new ParameterSymbol("this", thisType, 0) { IsThis = true });
        }

        AddParameters(symbol, declaration.Parameters, scope);

        if (declaration.Linkage.IsCpp())
        {
            // A C++ name encodes its parameters, so it can only be built once
            // they are known. `export "C++"` with no namespace written takes the
            // module's, because a module is what Stainless calls a namespace.
            symbol.CppNamespace = declaration.Namespace.Count > 0
                ? declaration.Namespace
                : declaration.Linkage == LinkageKind.ExportCpp
                    ? module.Name.Split('.', StringSplitOptions.RemoveEmptyEntries)
                    : [];

            // A `ref T` is a `T*`, so it mangles as one. C++ has a reference
            // type of its own that mangles differently, and this is not it: what
            // crosses is an address, which is what a C++ `T*` is too.
            symbol.ForeignName = CppMangler.Mangle(
                _cppAbi, symbol.CppNamespace, symbol.Name, symbol.ReturnType,
                symbol.Parameters
                    .Where(p => !p.IsThis)
                    .Select(p => p.IsByReference
                        ? new PointerTypeSymbol(p.Type)
                        : p.Type)
                    .ToList());
        }

        if (Dispatchable(declaration.Modifiers) is { } dispatch &&
            containingType is not ClassTypeSymbol)
            diagnostics.Error("SL0519", declaration.Span,
                containingType is InterfaceTypeSymbol
                    ? $"'{declaration.Name}' is an interface method, so '{dispatch}' says nothing " +
                      "new: every interface method is dispatched already"
                    : containingType is null
                        ? $"'{declaration.Name}' is a module-level function, so it cannot be " +
                          $"'{dispatch}'; there is no receiver to dispatch on"
                        : $"'{containingType.Name}' is not a class, so '{declaration.Name}' " +
                          $"cannot be '{dispatch}'; only a class is derived from");

        if (declaration.Modifiers.HasFlag(Modifiers.Protected) &&
            containingType is not ClassTypeSymbol)
            diagnostics.Error("SL0519", declaration.Span,
                $"'{declaration.Name}' cannot be 'protected'; the word means 'and anything " +
                "deriving from this', and only a class is derived from");

        // 'override' already says it is dispatched, because what it replaces was.
        if (declaration.Modifiers.HasFlag(Modifiers.Override) &&
            declaration.Modifiers.HasFlag(Modifiers.Virtual))
            diagnostics.Error("SL0507", declaration.Span,
                $"'{declaration.Name}' is both 'virtual' and 'override'; an override is " +
                "dispatched because what it replaces was");

        if (containingType is InterfaceTypeSymbol)
        {
            if (declaration.Body is not null)
                diagnostics.Error("SL0301", declaration.Span,
                    $"'{declaration.Name}' is an interface method and cannot have a body; " +
                    "interfaces declare signatures only");
        }
        else if (symbol.IsAbstract)
        {
            if (declaration.Body is not null)
                diagnostics.Error("SL0498", declaration.Span,
                    $"'{declaration.Name}' is abstract, so it cannot have a body; " +
                    "a derived class supplies one");
        }
        else if (!declaration.Linkage.IsImport() && declaration.Body is null)
        {
            diagnostics.Error("SL0210", declaration.Span,
                $"'{declaration.Name}' has no body; Stainless has no forward declarations, " +
                "because declaration order never matters");
        }

        if (containingType is null && CaseNamed(scope, declaration.Name) is { } shadowed)
            diagnostics.Error("SL0414", declaration.Span,
                $"a module-level function cannot be named '{declaration.Name}': it is a case of " +
                $"variant '{shadowed.DeclaringVariant.QualifiedName}', and a bare " +
                $"'{declaration.Name}(...)' builds one of those. A method of a type may still " +
                "be called this, because a method is reached through its receiver");

        if (containingType is not null)
        {
            var signature = symbol.ParameterTypes.ToList();

            if (containingType.Methods.Any(m => m.Name == declaration.Name && m.Accepts(signature)))
                diagnostics.Error("SL0211", declaration.Span,
                    $"'{containingType.Name}' already declares a method '{declaration.Name}' " +
                    "taking these parameter types; overloads must differ in their parameters, " +
                    "and a return type alone does not distinguish two methods");

            // An interface gives each of its methods a dispatch slot by
            // position, so two of the same name in one interface would be a
            // call the receiver could not resolve.
            else if (containingType is InterfaceTypeSymbol &&
                     containingType.Methods.Any(m => m.Name == declaration.Name))
                diagnostics.Error("SL0416", declaration.Span,
                    $"'{containingType.Name}' already declares '{declaration.Name}'; an interface " +
                    "method may not be overloaded, because dispatch gives each one a single slot. " +
                    "A class may still implement two interfaces whose methods share a name");

            containingType.Methods.Add(symbol);
        }

        module.Functions.Add(symbol);
    }

    /// <summary>
    /// Refuses a C signature that would hand a counted reference across the
    /// boundary inside a struct.
    ///
    /// A struct of plain data is still a C struct, byte for byte, and crosses
    /// freely in both directions. One that holds a reference is not: copying it
    /// retains what it holds, and C has no way to perform that copy — it would
    /// memcpy the bytes and leave the count behind. The same reasoning already
    /// keeps a bare <c>String</c> out of a C signature; this closes the gap a
    /// struct could otherwise smuggle one through.
    /// </summary>
    /// <summary>
    /// The dispatch word written on a declaration that cannot be dispatched, or
    /// null when none was. Reported where the declaration is, so that a
    /// <c>virtual</c> on a field says so rather than going quiet.
    /// </summary>
    private static string? Dispatchable(Modifiers modifiers) =>
        modifiers.HasFlag(Modifiers.Virtual) ? "virtual"
        : modifiers.HasFlag(Modifiers.Override) ? "override"
        : modifiers.HasFlag(Modifiers.Abstract) ? "abstract"
        : null;

    private void ValidateLinkageSignatures()
    {
        foreach (var symbol in _modules.Values.SelectMany(m => m.Functions))
        {
            if (!symbol.Linkage.IsForeign()) continue;

            string how = symbol.Linkage switch
            {
                LinkageKind.ExternC => "extern \"C\"",
                LinkageKind.ExportC => "export \"C\"",
                LinkageKind.ExternCpp => "extern \"C++\"",
                _ => "export \"C++\"",
            };

            if (symbol.ReturnType is StructTypeSymbol { } returned && returned.CarriesReferences())
                diagnostics.Error("SL0284", symbol.Span,
                    $"'{returned.Name}' holds a reference, so it cannot be returned across " +
                    $"{how}; C would copy its bytes and leave the count behind. Return a " +
                    "struct of plain data, or a raw pointer");

            foreach (var parameter in symbol.Parameters)
            {
                if (parameter.Type is not StructTypeSymbol { } passed ||
                    !passed.CarriesReferences())
                    continue;

                diagnostics.Error("SL0284", symbol.Span,
                    $"'{passed.Name}' holds a reference, so parameter '{parameter.Name}' " +
                    $"cannot cross {how}; C would copy its bytes and leave the count behind. " +
                    "Pass a struct of plain data, or a raw pointer");
            }
        }
    }

    private void AddParameters(FunctionSymbol symbol, IReadOnlyList<ParameterSyntax> parameters, FileScope scope)
    {
        foreach (var parameter in parameters)
        {
            if (symbol.Parameters.Any(p => p.Name == parameter.Name))
            {
                diagnostics.Error("SL0212", parameter.Span,
                    $"duplicate parameter name '{parameter.Name}'");
                continue;
            }

            var type = ResolveType(parameter.Type, scope);
            if (type.IsVoid())
                diagnostics.Error("SL0213", parameter.Span,
                    $"parameter '{parameter.Name}' cannot have type 'void'");

            // C decays an array parameter to a pointer and Stainless has no
            // decay, so passing one by value would be a silent copy of every
            // element *and* a different ABI from the C it is meant to match.
            // `ref` is the one that lines up: it is `T (*)[N]` on both sides.
            if (type is FixedArrayTypeSymbol && parameter.Mode == ParameterMode.Value)
                diagnostics.Error("SL0491", parameter.Span,
                    $"parameter '{parameter.Name}' cannot be '{type.Name}' by value; C " +
                    "passes an array as a pointer and copying every element here would " +
                    $"be neither. Write 'ref {type.Name}' or 'in {type.Name}'");

            symbol.Parameters.Add(
                new ParameterSymbol(parameter.Name, type, symbol.Parameters.Count)
                {
                    Mode = parameter.Mode,
                });
        }
    }

    private void DeclareGlobalConstant(FileScope scope, GlobalConstDeclSyntax declaration)
    {
        var module = scope.Module;
        if (module.Constants.ContainsKey(declaration.Name))
        {
            diagnostics.Error("SL0214", declaration.Span,
                $"'{declaration.Name}' is already declared in module '{module.Name}'");
            return;
        }

        // Module constants must fold at compile time, so only literals are allowed
        // for now -- and a negated one, which the parser sees as a unary minus
        // over a literal rather than as a literal. A C header is full of them.
        object? value = null;
        TypeSymbol type = declaration.Type is null
            ? PrimitiveTypeSymbol.Int
            : ResolveType(declaration.Type, scope);

        if (ConstantLiteral(declaration.Value) is { } literal)
        {
            bool negated = Negated(declaration.Value);
            value = negated ? Negate(literal.Value) : literal.Value;

            if (negated && value is null)
                diagnostics.Error("SL0215", declaration.Value.Span,
                    "only a number can be negated");

            if (declaration.Type is null)
                type = literal.Kind switch
                {
                    TokenKind.FloatLiteral => PrimitiveTypeSymbol.Double,
                    TokenKind.TrueKeyword or TokenKind.FalseKeyword => PrimitiveTypeSymbol.Bool,
                    TokenKind.CharLiteral => PrimitiveTypeSymbol.Char,
                    _ => PrimitiveTypeSymbol.Int,
                };
            else if (!Suits(literal.Kind, type))
                diagnostics.Error("SL0479", declaration.Value.Span,
                    $"'{declaration.Name}' is declared '{type.Name}', and " +
                    $"{literal.Kind.Describe()} is not one");
        }
        else
        {
            diagnostics.Error("SL0215", declaration.Value.Span,
                "a module-level 'const' must be initialized with a literal");
        }

        // A constant is a value inlined at every use, so it has to be something
        // that fits in one. A String is a counted object, and inlining a pointer
        // to its bytes would produce something that looks like a String, passes
        // every check, and is not one -- which is worse than not compiling.
        if (type is not (PrimitiveTypeSymbol or EnumTypeSymbol) && !type.IsError())
        {
            diagnostics.Error("SL0478", declaration.Span,
                $"a 'const' holds a number, a bool, a char or an enum, and " +
                $"'{type.Name}' is none of those. Write " +
                $"'static readonly {type.Name} {declaration.Name} = ...' instead, " +
                "which has storage rather than being inlined");

            // Registered anyway, so that every use of it does not then report
            // an undefined name on top of the one real error.
        }

        module.Constants[declaration.Name] = new ConstantSymbol(declaration.Name, type, value)
        {
            IsPublic = declaration.Modifiers.HasFlag(Modifiers.Public),
        };
    }

    /// <summary>
    /// Whether a literal of this kind can be the value of a constant of this type.
    ///
    /// Without this a mistyped constant is not an error but a zero, which is
    /// the worst of the three possible outcomes: it compiles, it runs, and the
    /// number it stands for is wrong everywhere it was used.
    /// </summary>
    private static bool Suits(TokenKind kind, TypeSymbol type)
    {
        if (type.IsError()) return true;
        var underlying = type is EnumTypeSymbol enumType ? enumType.UnderlyingType : type;

        return kind switch
        {
            // A character is a byte-wide integer, so it suits both -- which is
            // the same latitude C# gives `const int Newline = '\n';`.
            TokenKind.IntLiteral or TokenKind.CharLiteral =>
                underlying is PrimitiveTypeSymbol { IsInteger: true }
                    or PrimitiveTypeSymbol { Kind: PrimitiveKind.Char },
            TokenKind.FloatLiteral => underlying is PrimitiveTypeSymbol { IsFloat: true },
            TokenKind.TrueKeyword or TokenKind.FalseKeyword =>
                underlying is PrimitiveTypeSymbol { Kind: PrimitiveKind.Bool },
            _ => false,
        };
    }

    /// <summary>The literal a constant initializer is, looking through one minus.</summary>
    private static LiteralSyntax? ConstantLiteral(ExpressionSyntax value) => value switch
    {
        LiteralSyntax literal => literal,
        UnarySyntax { Operator: TokenKind.Minus, Operand: LiteralSyntax literal } => literal,
        _ => null,
    };

    private static bool Negated(ExpressionSyntax value) =>
        value is UnarySyntax { Operator: TokenKind.Minus };

    /// <summary>
    /// Negates a literal's value, or null when it is not a number.
    ///
    /// An integer literal is held as a <c>ulong</c> whatever it will end up
    /// being, so the negation is two's complement and stays a <c>ulong</c>. That
    /// is the same shape the emitter already narrows to the constant's declared
    /// width, so -21 as an <c>int</c> comes out as -21 and not as 2^64 - 21.
    /// </summary>
    private static object? Negate(object? value) => value switch
    {
        ulong number => unchecked(0UL - number),
        double number => -number,
        _ => null,
    };

    // ============================================================ pass 5

    /// <summary>
    /// Resolves what each type derives from -- a base class, interfaces, or both
    /// -- checks that it really supplies what it claims, and lays out its
    /// dispatch table.
    ///
    /// Interfaces go first so that an interface's own <c>extends</c> list is
    /// settled before any class is measured against it. Classes then resolve
    /// base-first, by recursion rather than by sorting: a derived class cannot
    /// inherit a vtable that does not exist yet.
    ///
    /// Interface ids are assigned across the whole program, which is what lets a
    /// class's dispatch table be indexed directly instead of searched.
    /// </summary>
    private void ResolveInterfaces()
    {
        foreach (var (type, entry) in _typeSyntax.Where(e => e.Key is InterfaceTypeSymbol))
            ResolveImplements(type, entry.Declaration, entry.Scope);

        foreach (var (type, entry) in _typeSyntax.Where(e => e.Key is not InterfaceTypeSymbol))
            ResolveImplements(type, entry.Declaration, entry.Scope);
    }

    /// <summary>Types whose bases and interfaces are settled.</summary>
    private readonly HashSet<NamedTypeSymbol> _inheritanceDone = [];

    /// <summary>Types being settled right now; a second visit is a cycle.</summary>
    private readonly HashSet<NamedTypeSymbol> _inheritanceInProgress = [];

    private void ResolveImplements(
        NamedTypeSymbol type, TypeDeclSyntax declaration, FileScope scope)
    {
        if (_inheritanceDone.Contains(type)) return;
        if (!_inheritanceInProgress.Add(type)) return;      // a cycle; the caller reports it

        var classType = type as ClassTypeSymbol;

        if (type is StructTypeSymbol && declaration.Implements.Count > 0)
        {
            string kind = type switch
            {
                VariantTypeSymbol => "variant",
                UnionTypeSymbol => "union",
                _ => "struct",
            };
            diagnostics.Error("SL0302", declaration.Span,
                $"{kind} '{type.Name}' cannot implement an interface; an interface " +
                "reference is a counted pointer, and a " + kind + " is a plain C value");
        }
        else
        {
            for (int i = 0; i < declaration.Implements.Count; i++)
            {
                var written = declaration.Implements[i];
                var resolved = ResolveType(written, scope);
                if (resolved.IsError()) continue;

                // A class in the list is the base class, and only the first name
                // may be one -- which is what makes `: Base, IShape` read the way
                // it does in C# without any lookahead at all.
                if (resolved is ClassTypeSymbol baseClass)
                {
                    BindBaseClass(type, classType, baseClass, written.Span, isFirst: i == 0);
                    continue;
                }

                if (resolved is not InterfaceTypeSymbol interfaceType)
                {
                    diagnostics.Error("SL0303", written.Span,
                        $"'{resolved.Name}' is not an interface, so '{type.Name}' cannot " +
                        (type is InterfaceTypeSymbol ? "extend" : "implement") + " it");
                    continue;
                }

                if (type.Interfaces.Contains(interfaceType))
                {
                    diagnostics.Warning("SL0304", written.Span,
                        $"'{type.Name}' already lists '{interfaceType.Name}'");
                    continue;
                }

                if (interfaceType == type || interfaceType.AllInterfaces().Contains(type))
                {
                    diagnostics.Error("SL0333", written.Span,
                        $"'{type.Name}' and '{interfaceType.Name}' extend each other");
                    continue;
                }

                type.Interfaces.Add(interfaceType);

                // Only a class has to supply implementations. An interface
                // extending another merely widens its own contract.
                if (classType is not null)
                    VerifyImplements(classType, interfaceType, written.Span);
            }
        }

        // Every class gets a table, base or no base: a class may declare the
        // first `virtual` in its own family.
        if (classType is not null) ResolveVirtuals(classType, declaration);

        _inheritanceInProgress.Remove(type);
        _inheritanceDone.Add(type);
    }

    /// <summary>
    /// Adopts <paramref name="baseClass"/> as the base of <paramref name="classType"/>,
    /// having first settled the base's own inheritance -- a derived class cannot
    /// inherit a dispatch table that has not been built.
    /// </summary>
    private void BindBaseClass(
        NamedTypeSymbol type, ClassTypeSymbol? classType,
        ClassTypeSymbol baseClass, SourceSpan span, bool isFirst)
    {
        if (classType is null)
        {
            diagnostics.Error("SL0512", span,
                $"'{type.Name}' is an interface and '{baseClass.Name}' is a class; an interface " +
                "extends interfaces only, because it has no state to inherit");
            return;
        }

        if (classType.BaseClass is not null)
        {
            diagnostics.Error("SL0510", span,
                $"'{classType.Name}' already derives from '{classType.BaseClass.Name}', so it " +
                $"cannot also derive from '{baseClass.Name}'. With two bases a reference to one " +
                "of them is a different address from the object itself, and reference identity, " +
                "free upcasts and 'sl_retain' all rest on those being the same. Interfaces give " +
                "several types without several states");
            return;
        }

        if (!isFirst)
        {
            diagnostics.Error("SL0508", span,
                $"the base class must be written first: '{classType.Name} : {baseClass.Name}, ...'. " +
                "A class has one base and any number of interfaces, and putting the base at the " +
                "front is what tells them apart without a keyword");
            return;
        }

        if (_inheritanceInProgress.Contains(baseClass))
        {
            diagnostics.Error("SL0511", span,
                baseClass == classType
                    ? $"'{classType.Name}' cannot derive from itself"
                    : $"'{classType.Name}' and '{baseClass.Name}' derive from each other, so " +
                      "neither has a size");
            return;
        }

        if (baseClass.IsSealed)
        {
            diagnostics.Error("SL0509", span,
                $"'{baseClass.Name}' is sealed, so nothing may derive from it");
            return;
        }

        if (baseClass.IsIntrinsic || baseClass.RuntimeFactory is not null)
        {
            diagnostics.Error("SL0513", span,
                $"'{baseClass.Name}' is provided by the runtime rather than compiled here, so " +
                "its layout and its destructor are not this compilation's to extend");
            return;
        }

        if (baseClass.ExternalTypeInfo is not null)
        {
            diagnostics.Error("SL0513", span,
                $"'{baseClass.Name}' comes from a referenced library, and deriving across a " +
                "library boundary is not supported: the derived object would carry a dispatch " +
                "table built here for a layout compiled there");
            return;
        }

        // Settle the base before taking anything from it. This is what puts the
        // whole hierarchy in order without a separate sorting pass.
        if (_typeSyntax.TryGetValue(baseClass, out var entry))
            ResolveImplements(baseClass, entry.Declaration, entry.Scope);

        classType.BaseClass = baseClass;

        // Implementing an interface is inherited along with everything else, and
        // the object needs its dispatch table either way.
        foreach (var inherited in baseClass.Interfaces)
            if (!classType.Interfaces.Contains(inherited))
                classType.Interfaces.Add(inherited);
    }

    /// <summary>
    /// Builds a class's dispatch table and checks every word written about
    /// overriding.
    ///
    /// The table starts as a copy of the base's, so an inherited method keeps its
    /// slot and a call through a base reference reaches whatever the object
    /// really is. An <c>override</c> replaces the entry in place; a new
    /// <c>virtual</c> is appended after everything inherited.
    /// </summary>
    private void ResolveVirtuals(ClassTypeSymbol classType, TypeDeclSyntax declaration)
    {
        if (classType.BaseClass is { } inheritedFrom)
            classType.VirtualTable.AddRange(inheritedFrom.VirtualTable);

        foreach (var method in classType.Methods)
        {
            if (method.IsVirtual && !method.IsPublic && !method.IsProtected)
                diagnostics.Error("SL0506", method.Span,
                    $"'{classType.Name}.{Describe(method)}' is dispatched, so it must be " +
                    "'public' or 'protected': a derived class has to be able to name what it " +
                    "is replacing");

            if (method.IsSealed && !method.IsOverride)
                diagnostics.Error("SL0507", method.Span,
                    $"'{classType.Name}.{Describe(method)}' is 'sealed' and overrides nothing; " +
                    "the word closes an inherited chain, so it goes with 'override'");

            if (method.IsAbstract && !classType.IsAbstract)
                diagnostics.Error("SL0505", method.Span,
                    $"'{classType.Name}.{Describe(method)}' is abstract, so '{classType.Name}' " +
                    "must be abstract too; a class with a method that has no body cannot be made");

            var signature = method.ParameterTypes.ToList();
            var inherited = classType.BaseClass?
                .FindMethods(method.Name)
                .FirstOrDefault(m => m.Accepts(signature));

            if (method.IsOverride)
            {
                if (inherited is null)
                {
                    diagnostics.Error("SL0499", method.Span,
                        classType.BaseClass is null
                            ? $"'{classType.Name}.{Describe(method)}' is marked 'override' and " +
                              $"'{classType.Name}' derives from nothing"
                            : $"'{classType.Name}.{Describe(method)}' is marked 'override' and " +
                              $"'{classType.BaseClass.Name}' declares nothing of that name and " +
                              "those parameters");
                    continue;
                }

                if (!inherited.IsVirtual)
                {
                    diagnostics.Error("SL0500", method.Span,
                        $"'{inherited.ContainingType!.Name}.{Describe(inherited)}' is not " +
                        "virtual, so it cannot be overridden; mark it 'virtual' or 'abstract'");
                    continue;
                }

                if (inherited.IsSealed)
                {
                    diagnostics.Error("SL0501", method.Span,
                        $"'{inherited.ContainingType!.Name}.{Describe(inherited)}' is a sealed " +
                        "override, so nothing may override it further");
                    continue;
                }

                if (!SignaturesAgree(method, inherited))
                {
                    diagnostics.Error("SL0502", method.Span,
                        $"'{classType.Name}.{Describe(method)}' does not match what it overrides; " +
                        $"expected '{inherited.ReturnType.Name} {inherited.Name}(" +
                        string.Join(", ", inherited.Parameters.Where(p => !p.IsThis).Select(Spelled)) +
                        ")'");
                    continue;
                }

                method.Overridden = inherited;
                method.VirtualSlot = inherited.VirtualSlot;
                classType.VirtualTable[method.VirtualSlot] = method;
                continue;
            }

            if (inherited is not null)
            {
                // Silent hiding is the one shape C# allows here and this does
                // not: `new` exists to say "I know", and a language with no way
                // to reach the hidden member has nothing to say it about.
                diagnostics.Error("SL0503", method.Span,
                    $"'{classType.Name}.{Describe(method)}' has the same name and parameters as " +
                    $"'{inherited.ContainingType!.Name}.{Describe(inherited)}'" +
                    (inherited.IsVirtual
                        ? "; write 'override' to replace it"
                        : ", which is not virtual; rename one of them, or mark the inherited " +
                          "one 'virtual' and this one 'override'"));
                continue;
            }

            if (method.IsVirtual)
            {
                method.VirtualSlot = classType.VirtualTable.Count;
                classType.VirtualTable.Add(method);
            }
        }

        if (classType.IsAbstract) return;

        // A class that declares no constructor is built by its base's, and one
        // with no base constructor it could call is a class nothing can make.
        // Said here rather than at each `new`, because the declaration is where
        // the missing constructor goes.
        if (classType.Constructors.Count == 0 &&
            !TryImplicitBaseConstructor(classType, out _))
            diagnostics.Error("SL0517", classType.Span ?? declaration.Span,
                $"'{classType.Name}' declares no constructor and every constructor of " +
                $"'{NearestConstructing(classType)!.Name}' takes arguments, so nothing could " +
                $"ever build one; give '{classType.Name}' a constructor whose first statement " +
                "is 'base(...)'");

        // A concrete class is one every abstract method of which has a body
        // somewhere in the chain -- which is exactly the table having no
        // abstract entry left in it.
        // One its own declaration left abstract has already been reported
        // against that declaration, which is where the mistake is.
        foreach (var missing in classType.VirtualTable
                     .Where(m => m.IsAbstract && m.ContainingType != classType))
            diagnostics.Error("SL0504", classType.Span ?? declaration.Span,
                $"'{classType.Name}' does not implement abstract " +
                $"'{missing.ContainingType!.Name}.{Describe(missing)}'; add 'public override " +
                $"{missing.ReturnType.Name} {missing.Name}(" +
                string.Join(", ", missing.Parameters.Where(p => !p.IsThis)
                    .Select(p => p.Type.Name + " " + p.Name)) + ")'");
    }

    /// <summary>
    /// True when two methods agree on everything a caller can observe: the
    /// return type, and each parameter's type and mode. The mode is part of it
    /// because a <c>ref int</c> and an <c>int</c> are passed differently, and the
    /// slot would then hold a function the caller is about to hand a pointer to.
    /// </summary>
    private static bool SignaturesAgree(FunctionSymbol method, FunctionSymbol other)
    {
        var mine = method.Parameters.Where(p => !p.IsThis).ToList();
        var theirs = other.Parameters.Where(p => !p.IsThis).ToList();

        return method.ReturnType.Equals(other.ReturnType) &&
               mine.Count == theirs.Count &&
               mine.Zip(theirs).All(pair =>
                   pair.First.Type.Equals(pair.Second.Type) &&
                   pair.First.Mode == pair.Second.Mode);
    }

    /// <summary>
    /// A method as a diagnostic should name it. An accessor is named by its
    /// property, because that is the thing the source wrote.
    /// </summary>
    private static string Describe(FunctionSymbol method) =>
        method.Accessor is { } property ? property.Name : method.Name;

    /// <summary>The <c>[Reflect]</c> marker, found in Standard.Reflection.</summary>
    private AttributeTypeSymbol? ReflectAttribute =>
        _modules.TryGetValue("Standard.Reflection", out var module) &&
        module.Types.TryGetValue("Reflect", out var found)
            ? found as AttributeTypeSymbol
            : null;

    /// <summary>The struct <c>typeof</c> produces, also from Standard.Reflection.</summary>
    private StructTypeSymbol? TypeHandle =>
        _modules.TryGetValue("Standard.Reflection", out var module) &&
        module.Types.TryGetValue("Type", out var found)
            ? found as StructTypeSymbol
            : null;

    /// <summary>
    /// Binds every applied attribute once all types are known. Arguments must be
    /// constants, since the values are written into the binary rather than
    /// evaluated.
    /// </summary>
    private void ResolveAttributes()
    {
        var reflect = ReflectAttribute;

        // Enums live in their own table, and until [Flags] there was nothing an
        // attribute on one could mean -- so they were silently dropped.
        foreach (var (type, entry) in _enumSyntax)
            BindAttributes(entry.Declaration.Attributes, type.Attributes, entry.Scope, type.Name);

        foreach (var (type, entry) in _typeSyntax)
            if (entry.Declaration.Attributes.Count > 0 &&
                entry.Declaration.Attributes.Any(a => a.Name.Last == "Flags"))
                diagnostics.Error("SL0411", entry.Declaration.Span,
                    $"'[Flags]' says an enum's members combine as bits; '{type.Name}' is not an enum");

        foreach (var (type, entry) in _typeSyntax)
        {
            BindAttributes(entry.Declaration.Attributes, type.Attributes, entry.Scope, type.Name);

            if (reflect is not null && type.Attributes.Any(a => a.Type == reflect))
            {
                // A variant is a struct, so it would pass the test below and emit
                // its two hidden fields as if they were the programmer's. They
                // are not, and a variant's shape is its cases, which the field
                // tables have no way to say.
                if (type is VariantTypeSymbol)
                    diagnostics.Error("SL0442", entry.Declaration.Span,
                        $"'[Reflect]' emits a type's fields, and the fields of variant " +
                        $"'{type.Name}' are a tag and a payload the source cannot name. What " +
                        "a reader would want is its cases, and those are not described yet");
                else if (type.Fields.Any(f => f.IsBitField))
                    diagnostics.Error("SL0475", entry.Declaration.Span,
                        $"'[Reflect]' describes a field by its byte offset, and '{type.Name}' " +
                        "has bit-fields, which have not got one. Reflecting them means saying " +
                        "where in a byte they start, and the tables do not");
                else if (type is ClassTypeSymbol or StructTypeSymbol) type.IsReflected = true;
                else
                    diagnostics.Error("SL0341", entry.Declaration.Span,
                        $"'[Reflect]' applies to a class or a struct; '{type.Name}' is neither");
            }

            ReadLayoutAttributes(type, entry.Declaration.Span);

            foreach (var member in entry.Declaration.Members.OfType<FieldDeclSyntax>())
            {
                if (member.Attributes.Count == 0) continue;
                if (type.FindField(member.Name) is not { } field) continue;

                BindAttributes(member.Attributes, field.Attributes, entry.Scope,
                    type.Name + "." + field.Name);
            }

            // An attribute on an automatic property lands on its backing field
            // too, so a reflected type reports the storage the way it was
            // annotated rather than losing the annotation to the lowering.
            foreach (var member in entry.Declaration.Members.OfType<PropertyDeclSyntax>())
            {
                if (member.Attributes.Count == 0) continue;
                if (type.FindProperty(member.Name) is not { } property) continue;

                BindAttributes(member.Attributes, property.Attributes, entry.Scope,
                    type.Name + "." + property.Name);
                property.BackingField?.Attributes.AddRange(property.Attributes);
            }
        }
    }

    private void BindAttributes(
        IReadOnlyList<AttributeSyntax> syntax,
        List<AppliedAttribute> applied,
        FileScope scope,
        string owner)
    {
        foreach (var attribute in syntax)
        {
            var resolved = ResolveNamedType(
                new NamedTypeSyntax(attribute.Span, attribute.Name), scope);
            if (resolved.IsError()) continue;

            if (resolved is not AttributeTypeSymbol attributeType)
            {
                diagnostics.Error("SL0342", attribute.Span,
                    $"'{resolved.Name}' is not an attribute, so it cannot be written on {owner}");
                continue;
            }

            if (attribute.Arguments.Count != attributeType.Fields.Count)
            {
                diagnostics.Error("SL0343", attribute.Span,
                    $"'{attributeType.Name}' takes {attributeType.Fields.Count} " +
                    $"argument{(attributeType.Fields.Count == 1 ? "" : "s")}, " +
                    $"but {Given(attribute.Arguments.Count)}");
                continue;
            }

            var values = new List<object?>();
            bool ok = true;

            for (int i = 0; i < attribute.Arguments.Count; i++)
            {
                var expected = attributeType.Fields[i].Type;
                var value = ConstantValue(attribute.Arguments[i], expected);

                if (value is null)
                {
                    diagnostics.Error("SL0344", attribute.Arguments[i].Span,
                        $"argument {i + 1} of '{attributeType.Name}' must be a constant " +
                        $"'{expected.Name}'; attribute values are written into the binary");
                    ok = false;
                    break;
                }

                values.Add(value);
            }

            if (ok) applied.Add(new AppliedAttribute(attributeType, values));
        }
    }

    /// <summary>Folds a literal to the value an attribute field will hold, or null.</summary>
    private object? ConstantValue(ExpressionSyntax syntax, TypeSymbol expected)
    {
        if (syntax is not LiteralSyntax literal) return null;

        if (literal.Kind == TokenKind.StringLiteral)
            return _builtins.IsString(expected) ? literal.Value : null;

        return (literal.Kind, expected) switch
        {
            (TokenKind.IntLiteral, PrimitiveTypeSymbol { IsInteger: true }) => literal.Value,
            (TokenKind.FloatLiteral, PrimitiveTypeSymbol { IsFloat: true }) => literal.Value,
            (TokenKind.TrueKeyword or TokenKind.FalseKeyword,
                PrimitiveTypeSymbol { Kind: PrimitiveKind.Bool }) => literal.Value,
            _ => null,
        };
    }

    private void VerifyImplements(
        ClassTypeSymbol classType, InterfaceTypeSymbol interfaceType, SourceSpan span)
    {
        // Implementing IList also means implementing IReadOnlyList, and the
        // object needs a dispatch table for each.
        foreach (var inherited in interfaceType.AllInterfaces())
        {
            if (classType.Interfaces.Contains(inherited)) continue;
            classType.Interfaces.Add(inherited);
            VerifyImplements(classType, inherited, span);
        }

        foreach (var required in interfaceType.Methods)
        {
            var found = classType.FindImplementation(required);

            // A missing property is one mistake, not two: the getter reports it
            // and the setter stays quiet.
            if (found is null && required.Accessor is { Getter: not null } missing &&
                required != missing.Getter && classType.FindProperty(missing.Name) is null)
                continue;

            if (found is null)
            {
                // A missing accessor is a missing property as far as the source
                // is concerned, so say so in the shape it was written in.
                diagnostics.Error("SL0305", span,
                    required.Accessor is { } declared
                        ? $"'{classType.Name}' does not implement property " +
                          $"'{interfaceType.Name}.{declared.Name}'; add 'public {declared.Type.Name} " +
                          $"{declared.Name} {{ get;{(declared.Setter is null ? "" : " set;")} }}'"
                        : $"'{classType.Name}' does not implement '{interfaceType.Name}.{required.Name}'; " +
                          $"add 'public {required.ReturnType.Name} {required.Name}(" +
                          string.Join(", ", required.Parameters.Where(p => !p.IsThis)
                              .Select(p => p.Type.Name + " " + p.Name)) + ")'");
                continue;
            }

            if (!found.IsPublic)
            {
                diagnostics.Error("SL0306", found.Span,
                    $"'{classType.Name}.{found.Name}' implements " +
                    $"'{interfaceType.Name}.{required.Name}' and must therefore be public");
            }

            var wanted = required.Parameters.Where(p => !p.IsThis).ToList();
            var actual = found.Parameters.Where(p => !p.IsThis).ToList();

            // The mode is part of the match, not decoration on it. A method
            // taking an int cannot stand in for one taking a ref int: the two
            // are passed differently, and the vtable slot would hold a function
            // the caller is about to hand a pointer to.
            if (!found.ReturnType.Equals(required.ReturnType) ||
                wanted.Count != actual.Count ||
                !wanted.Zip(actual).All(pair =>
                    pair.First.Type.Equals(pair.Second.Type) &&
                    pair.First.Mode == pair.Second.Mode))
            {
                diagnostics.Error("SL0307", found.Span,
                    $"'{classType.Name}.{found.Name}' does not match " +
                    $"'{interfaceType.Name}.{required.Name}'; expected " +
                    $"'{required.ReturnType.Name} {required.Name}(" +
                    string.Join(", ", wanted.Select(Spelled)) + ")'");
            }
        }
    }

    /// <summary>A parameter as the source writes it, mode included.</summary>
    private static string Spelled(ParameterSymbol parameter) =>
        (parameter.Mode == ParameterMode.Ref ? "ref " :
         parameter.Mode == ParameterMode.In ? "in " : "") + parameter.Type.Name;

    /// <summary>
    /// Reads <c>[Packed]</c> and <c>[Align(N)]</c> onto a type, before pass 7
    /// lays it out.
    ///
    /// The cap is what the allocator can promise. <c>malloc</c> guarantees
    /// <c>max_align_t</c>, which is 16 on every target here, and a class holding
    /// an over-aligned field would be handed memory that does not honour it. A
    /// local could be aligned further, and a heap object could too once the
    /// runtime allocates by a type's alignment rather than by its size -- but
    /// half a rule is worse than a stated limit.
    /// </summary>
    private void ReadLayoutAttributes(NamedTypeSymbol type, SourceSpan span)
    {
        const int MaxAlignment = 16;

        if (type.Attributes.Any(a => a.Type == _builtins.Packed))
        {
            if (type is StructTypeSymbol and not VariantTypeSymbol) type.IsPacked = true;
            else
                diagnostics.Error("SL0463", span,
                    $"'[Packed]' lays out a struct with no padding, and '{type.Name}' is " +
                    (type is VariantTypeSymbol
                        ? "a variant, whose payload area is not a field the source arranged"
                        : "not a struct"));
        }

        if (type.Attributes.FirstOrDefault(a => a.Type == _builtins.Align) is not { } align) return;

        if (type is not StructTypeSymbol || type is VariantTypeSymbol)
        {
            diagnostics.Error("SL0464", span,
                $"'[Align]' applies to a struct; '{type.Name}' is not one");
            return;
        }

        int requested = align.Values.Count > 0 && align.Values[0] is { } value
            ? Convert.ToInt32(value, System.Globalization.CultureInfo.InvariantCulture)
            : 0;

        if (requested <= 0 || (requested & (requested - 1)) != 0)
        {
            diagnostics.Error("SL0465", span,
                $"'[Align({requested})]' is not an alignment; it must be a power of two");
            return;
        }

        if (requested > MaxAlignment)
        {
            diagnostics.Error("SL0466", span,
                $"'[Align({requested})]' is more than the {MaxAlignment} bytes the allocator " +
                "guarantees, so an object holding one of these would not honour it. " +
                $"{MaxAlignment} is the most that can be promised until the runtime allocates " +
                "by alignment as well as by size");
            return;
        }

        type.RequestedAlignment = requested;
    }

    /// <summary>
    /// Checks that nothing in a union is counted.
    ///
    /// A union does not record which member is live, so a copy would not know
    /// what to retain and a drop would not know what to release. Every other
    /// value type in the language answers both questions from its type alone;
    /// this is the one that cannot, which is why the reference is refused rather
    /// than the counting made conditional.
    /// </summary>
    private void CheckUnions()
    {
        foreach (var union in _modules.Values.SelectMany(m => m.Types.Values).OfType<UnionTypeSymbol>())
        {
            if (union.Fields.Count == 0)
                diagnostics.Error("SL0467", union.Span ?? default,
                    $"union '{union.Name}' has no members; a union is the choice between its " +
                    "members, so one with none has no values at all");

            foreach (var member in union.Fields.Where(f => f.Type.CarriesReferences()))
                diagnostics.Error("SL0468", union.Span ?? default,
                    $"'{union.Name}.{member.Name}' is '{member.Type.Name}', which holds a " +
                    "counted reference, and a union does not record which member is the live " +
                    "one -- so a copy could not know what to retain. Hold the reference beside " +
                    "the union, or use a 'variant', which does record it");
        }
    }

    // ============================================================ pass 6

    private void ComputeLayouts()
    {
        var inProgress = new HashSet<NamedTypeSymbol>();
        foreach (var type in _modules.Values.SelectMany(m => m.Types.Values))
            ComputeLayout(type, inProgress);
    }

    /// <summary>
    /// Lays out a type using the platform C rules. Class references are pointers,
    /// so a class may contain itself; a struct may not, and that cycle is reported here.
    /// </summary>
    private void ComputeLayout(NamedTypeSymbol type, HashSet<NamedTypeSymbol> inProgress)
    {
        if (type.LayoutComputed) return;

        if (!inProgress.Add(type))
        {
            diagnostics.Error("SL0216", default,
                $"struct '{type.QualifiedName}' contains itself, so it has no finite size");
            type.SetLayout(0, 1);
            return;
        }

        // A variant's payload field has no size until every case has one, so
        // the filler is built here, immediately before the fields are walked.
        if (type is VariantTypeSymbol variant) SizePayloadStorage(variant, inProgress);

        // Every member of a union starts where the union does; its size is the
        // widest of them. That is the whole of the layout, and it is why a union
        // records nothing about which member is the live one.
        if (type is UnionTypeSymbol union)
        {
            int widest = 0, strictest = 1;

            foreach (var member in union.Fields)
            {
                if (member.Type is StructTypeSymbol nestedMember)
                    ComputeLayout(nestedMember, inProgress);

                member.Offset = 0;
                member.BitOffset = 0;
                widest = Math.Max(widest, member.Type.Size);
                strictest = Math.Max(strictest, Math.Max(1, member.Type.Alignment));
            }

            if (union.IsPacked) strictest = 1;
            if (union.RequestedAlignment is { } wanted) strictest = Math.Max(strictest, wanted);

            union.SetLayout(Math.Max(1, TypeExtensions.AlignTo(widest, strictest)), strictest);
            inProgress.Remove(type);
            return;
        }

        if (type.Fields.Any(f => f.IsBitField))
        {
            LayOutWithBitFields(type, inProgress);
            inProgress.Remove(type);
            return;
        }

        int offset = 0, alignment = 1;

        // A derived class's fields begin where its base's end, so the base
        // subobject is a prefix of the derived one and starts at the same
        // address. That is what makes an upcast free, and what makes every
        // inherited method's field offsets right without recomputing them.
        if (type is ClassTypeSymbol { BaseClass: { } inheritedFrom })
        {
            ComputeLayout(inheritedFrom, inProgress);
            offset = inheritedFrom.FieldsSize;
            alignment = Math.Max(alignment, inheritedFrom.FieldsAlignment);
        }

        foreach (var field in type.Fields)
        {
            // Only a struct field forces its type to be laid out first.
            if (field.Type is StructTypeSymbol nested)
                ComputeLayout(nested, inProgress);

            // Packed means no padding anywhere: a field lands where the one
            // before it ended, and the type asks nothing of its own address.
            int fieldAlignment = type.IsPacked ? 1 : Math.Max(1, field.Type.Alignment);
            offset = TypeExtensions.AlignTo(offset, fieldAlignment);
            field.Offset = offset;
            offset += field.Type.Size;
            alignment = Math.Max(alignment, fieldAlignment);
        }

        // [Align(N)] raises and never lowers, as alignas does -- including over
        // [Packed], so the two together mean "no padding inside, but put the
        // whole of it on an N-byte boundary".
        if (type.RequestedAlignment is { } requested)
            alignment = Math.Max(alignment, requested);

        // A struct with no fields still takes a byte, because the emitter gives
        // it one: LLVM has no zero-sized named struct, so a fieldless struct is
        // emitted as `type { i8 }`. If the binder disagreed, every copy of a
        // struct containing one would move the wrong number of bytes and read
        // its own padding. C++ and Rust settle it the same way.
        int size = type is StructTypeSymbol && type.Fields.Count == 0
            ? 1
            : TypeExtensions.AlignTo(offset, alignment);

        type.SetLayout(size, alignment);
        inProgress.Remove(type);
    }

    /// <summary>
    /// Lays out a struct that has bit-fields in it.
    ///
    /// The two C ABIs genuinely disagree here, and not in a corner: for
    /// <c>struct { int a : 1; char b : 1; }</c> gcc gives four bytes and MSVC
    /// gives eight. So there are two algorithms, chosen the way the C++ mangler
    /// chooses a scheme, and both are checked against what the target's own
    /// compiler makes of the same declaration.
    ///
    /// **Itanium** packs to the bit and starts a new storage unit only when a
    /// field would cross a boundary of its own declared type. A three-bit
    /// <c>int</c> followed by a four-bit <c>short</c> share one word.
    ///
    /// **Microsoft** keeps a current storage unit of one declared type's size,
    /// and opens a new one whenever the next field will not fit *or* is declared
    /// with a type of a different size. The same two fields land in a four-byte
    /// unit and a two-byte one.
    /// </summary>
    private void LayOutWithBitFields(NamedTypeSymbol type, HashSet<NamedTypeSymbol> inProgress)
    {
        // Checked here rather than where the width was read, because [Packed] is
        // not known until attributes have been folded and that is a pass later.
        if (type.IsPacked)
            diagnostics.Error("SL0470", type.Span ?? default,
                $"'{type.Name}' is '[Packed]' and has bit-fields, and the two together mean " +
                "different things to different C compilers -- gcc packs the bits and MSVC keeps " +
                "the storage unit. Until one of them is chosen and checked against it, this is " +
                "refused rather than guessed");

        foreach (var nested in type.Fields.Select(f => f.Type).OfType<StructTypeSymbol>())
            ComputeLayout(nested, inProgress);

        int alignment = 1;
        foreach (var field in type.Fields)
            alignment = Math.Max(alignment, Math.Max(1, field.Type.Alignment));

        if (type.RequestedAlignment is { } wanted) alignment = Math.Max(alignment, wanted);

        int size = _cppAbi == CppAbi.Microsoft
            ? LayOutMicrosoftBitFields(type)
            : LayOutItaniumBitFields(type);

        type.SetLayout(Math.Max(1, TypeExtensions.AlignTo(size, alignment)), alignment);
    }

    /// <summary>
    /// gcc and clang: allocate at the next free bit, and move to the next
    /// boundary of the declared type only when the field would straddle one.
    /// </summary>
    private static int LayOutItaniumBitFields(NamedTypeSymbol type)
    {
        long bit = 0;

        foreach (var field in type.Fields)
        {
            if (field.BitWidth is not { } width)
            {
                // An ordinary field closes whatever was being filled and takes
                // its own alignment from the byte it lands on.
                int at = TypeExtensions.AlignTo(
                    (int)((bit + 7) / 8), Math.Max(1, field.Type.Alignment));
                field.Offset = at;
                field.BitOffset = 0;
                bit = (long)(at + field.Type.Size) * 8;
                continue;
            }

            long unit = (long)field.Type.Size * 8;

            // A bit-field must sit inside one storage unit of its own type. If
            // it would cross the boundary, it starts at the next one.
            if (bit / unit != (bit + width - 1) / unit)
                bit = (bit + unit - 1) / unit * unit;

            long start = bit / unit * unit;
            field.Offset = (int)(start / 8);
            field.BitOffset = (int)(bit - start);
            bit += width;
        }

        return (int)((bit + 7) / 8);
    }

    /// <summary>
    /// MSVC: keep a storage unit of one declared type's size, and open a new one
    /// when the next field does not fit or is declared with a different size.
    /// </summary>
    private static int LayOutMicrosoftBitFields(NamedTypeSymbol type)
    {
        int offset = 0;             // where the next thing goes
        int unitAt = -1;            // byte offset of the open storage unit
        int unitSize = 0;           // its size, from the type that opened it
        int unitUsed = 0;           // bits of it spoken for

        foreach (var field in type.Fields)
        {
            if (field.BitWidth is not { } width)
            {
                // An ordinary field closes the unit outright.
                unitAt = -1;
                offset = TypeExtensions.AlignTo(offset, Math.Max(1, field.Type.Alignment));
                field.Offset = offset;
                field.BitOffset = 0;
                offset += field.Type.Size;
                continue;
            }

            int size = field.Type.Size;

            bool fits = unitAt >= 0 && size == unitSize && unitUsed + width <= size * 8;

            if (!fits)
            {
                offset = TypeExtensions.AlignTo(offset, Math.Max(1, field.Type.Alignment));
                unitAt = offset;
                unitSize = size;
                unitUsed = 0;
                offset += size;
            }

            field.Offset = unitAt;
            field.BitOffset = unitUsed;
            unitUsed += width;
        }

        return offset;
    }

    /// <summary>
    /// Gives a variant's payload field exactly the size and alignment the widest
    /// case needs.
    ///
    /// There is no way to say "N bytes, aligned to A" in the type system, so the
    /// filler says it in fields: as many integers of A bytes as it takes to
    /// cover the widest payload. LLVM lays that out to the same size and the
    /// same alignment the C rules give it here, which is what lets a case's
    /// fields be read straight out of the payload's address.
    /// </summary>
    private void SizePayloadStorage(VariantTypeSymbol variant, HashSet<NamedTypeSymbol> inProgress)
    {
        if (variant.PayloadStorage is not { } storage || storage.LayoutComputed) return;

        int size = 0, alignment = 1;

        foreach (var payload in variant.Cases.Select(c => c.Payload).OfType<StructTypeSymbol>())
        {
            ComputeLayout(payload, inProgress);
            size = Math.Max(size, payload.Size);
            alignment = Math.Max(alignment, payload.Alignment);
        }

        var element = alignment switch
        {
            >= 8 => PrimitiveTypeSymbol.ULong,
            >= 4 => PrimitiveTypeSymbol.UInt,
            >= 2 => PrimitiveTypeSymbol.UShort,
            _ => PrimitiveTypeSymbol.Byte,
        };

        int count = Math.Max(1, (size + element.Size - 1) / element.Size);
        for (int i = 0; i < count; i++)
            storage.Fields.Add(new FieldSymbol("e" + i, element, storage, i));

        ComputeLayout(storage, inProgress);
    }

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

    // ============================================================ pass 7

    private void BindBodies()
    {
        // Walked by module rather than by file, because a module may span files
        // and each function already remembers which one it came from.
        foreach (var module in _modules.Values.ToList())
        {
            // Snapshotted: binding a body can instantiate a generic, which adds
            // to exactly these collections while we are walking them.
            //
            // A method of an instantiated generic is skipped: it is queued with
            // the substitution that gives its type parameters meaning, and
            // binding it here would be binding it without one. That only shows
            // up when the instantiation happened before this pass -- from a
            // field's type, or a static's -- because anything instantiated
            // during it lands outside the snapshot.
            foreach (var function in module.Functions
                         .Where(f => f.HasBody && f.ContainingType?.Template is null)
                         .ToList())
                BindFunctionBody(function);

            foreach (var type in module.Types.Values.OfType<ClassTypeSymbol>().ToList())
            {
                foreach (var constructor in type.Constructors.ToList()) BindFunctionBody(constructor);
                if (type.Destructor is not null) BindFunctionBody(type.Destructor);
            }
        }

        _currentScope = null;
    }

    private void BindFunctionBody(FunctionSymbol function)
    {
        if (function.IsAutoAccessor) { BindAutoAccessor(function); return; }
        if (function.Body is null) return;
        if (!_boundFunctions.Add(function)) return;

        // Bound against the imports of the file it was written in.
        if (function.Scope is not null) _currentScope = function.Scope;

        _currentFunction = function;
        _scopes.Clear();
        _loopDepth = 0;
        _switchDepth = 0;
        _variantFacts = [];

        // `base(...)` is only a statement at the very head of a constructor, so
        // the one place it may appear is found before anything is bound and
        // every other appearance is refused where it stands.
        _constructorChain = function.Kind == FunctionKind.Constructor
            ? function.Body.Statements.FirstOrDefault() is
                ExpressionStatementSyntax
                {
                    Expression: CallSyntax { Callee: BaseSyntax or ThisSyntax } head
                }
                ? head
                : null
            : null;

        PushScope();
        var body = BindBlock(function.Body);
        PopScope();

        _constructorChain = null;

        if (function.Kind == FunctionKind.Constructor)
            body = WithBaseConstruction(function, body);

        if (!function.ReturnType.IsVoid() && !function.ReturnType.IsError() && !AlwaysReturns(body))
            diagnostics.Error("SL0217", function.Span,
                $"not all paths through '{function.Name}' return a value of type '{function.ReturnType.Name}'");

        _functions.Add(new BoundFunction(function, body));
        _currentFunction = null;
    }

    /// <summary>
    /// The one <c>base(...)</c> a constructor may contain, or null. Compared by
    /// reference, so a second one anywhere else is not it.
    /// </summary>
    private CallSyntax? _constructorChain;

    /// <summary>
    /// Puts the base construction at the head of a constructor when the source
    /// did not write one.
    ///
    /// A base class is constructed before the derived class's body runs, always:
    /// the derived body may read what the base set up, and nothing else would
    /// make that safe. Written explicitly, the call is already the first
    /// statement; left out, it is the base's parameterless constructor, and
    /// there being none is an error rather than a class that skips it.
    /// </summary>
    private BoundBlock WithBaseConstruction(FunctionSymbol constructor, BoundBlock body)
    {
        if (constructor.ContainingType is not ClassTypeSymbol classType) return body;
        if (classType.BaseClass is null) return body;

        // Written out; BindBaseConstruction already put it first.
        if (_boundExplicitChain) { _boundExplicitChain = false; return body; }

        if (!TryImplicitBaseConstructor(classType, out var chained))
        {
            diagnostics.Error("SL0517", constructor.Span,
                $"'{NearestConstructing(classType)!.Name}' has no constructor that takes no " +
                $"arguments, so '{classType.Name}' has to say which one to run: write " +
                "'base(...)' as the first statement of its constructor");
            return body;
        }

        if (chained is null) return body;

        var self = new BoundThis(constructor.Span, classType, constructor.Parameters[0]);
        var call = new BoundCall(constructor.Span, chained,
            new BoundConversion(constructor.Span, chained.ContainingType!, self, ConversionKind.Upcast),
            []) { IsNonVirtual = true };

        return new BoundBlock(body.Span,
            [new BoundExpressionStatement(constructor.Span, call), .. body.Statements]);
    }

    /// <summary>Set while binding a constructor whose source wrote its own chain.</summary>
    private bool _boundExplicitChain;

    /// <summary>
    /// <c>base(args)</c> at the head of a constructor: run the base's
    /// constructor over this same object, before this one's body.
    /// </summary>
    private BoundExpression BindBaseConstruction(CallSyntax syntax, List<BoundExpression> arguments)
    {
        if (!ReferenceEquals(syntax, _constructorChain))
        {
            diagnostics.Error("SL0516", syntax.Span,
                _currentFunction?.Kind == FunctionKind.Constructor
                    ? "'base(...)' has to be the first statement of the constructor: the base " +
                      "class is built before this class's body runs, and a body that had already " +
                      "run would be reading fields nothing had set"
                    : "'base(...)' constructs the base class, so it belongs at the head of a " +
                      "constructor and nowhere else");
            return new BoundErrorExpression(syntax.Span);
        }

        var classType = (ClassTypeSymbol)_currentFunction!.ContainingType!;

        if (classType.BaseClass is not { } baseClass)
        {
            diagnostics.Error("SL0515", syntax.Span,
                $"'{classType.Name}' derives from nothing, so it has no base to construct");
            return new BoundErrorExpression(syntax.Span);
        }

        // Past any class that declares no constructor: there is nothing there
        // to run, and what is above it still has to be built.
        if (NearestConstructing(classType) is not { } ancestor)
        {
            diagnostics.Error("SL0517", syntax.Span,
                $"nothing '{classType.Name}' derives from declares a constructor, so there is " +
                "none to call; remove the 'base(...)'");
            return new BoundErrorExpression(syntax.Span);
        }

        var chosen = ResolveOverload(
            ancestor.Constructors, arguments, syntax.Span, $"base {ancestor.Name}");
        if (chosen is null) return new BoundErrorExpression(syntax.Span);

        var self = new BoundThis(syntax.Span, classType, _currentFunction.Parameters[0]);
        var receiver = new BoundConversion(syntax.Span, ancestor, self, ConversionKind.Upcast);

        _boundExplicitChain = true;
        return BuildCall(syntax, chosen, receiver, arguments, nonVirtual: true);
    }

    /// <summary>
    /// <c>this(args)</c> at the head of a constructor: run another of this
    /// class's own constructors over the same object first.
    ///
    /// The one it delegates to builds the base, so no base chain is inserted
    /// here -- inserting one would construct the base twice, and the second
    /// pass would overwrite whatever the first had set.
    /// </summary>
    private BoundExpression BindThisConstruction(CallSyntax syntax, List<BoundExpression> arguments)
    {
        if (!ReferenceEquals(syntax, _constructorChain))
        {
            diagnostics.Error("SL0516", syntax.Span,
                _currentFunction?.Kind == FunctionKind.Constructor
                    ? "'this(...)' has to be the first statement of the constructor: it is what " +
                      "builds the object, and a body that had already run would be overwritten " +
                      "by it"
                    : "'this(...)' runs another constructor of this class, so it belongs at the " +
                      "head of a constructor and nowhere else");
            return new BoundErrorExpression(syntax.Span);
        }

        var classType = (ClassTypeSymbol)_currentFunction!.ContainingType!;

        var chosen = ResolveOverload(
            classType.Constructors, arguments, syntax.Span, $"this {classType.Name}");
        if (chosen is null) return new BoundErrorExpression(syntax.Span);

        if (chosen == _currentFunction)
        {
            diagnostics.Error("SL0521", syntax.Span,
                $"this constructor of '{classType.Name}' delegates to itself");
            return new BoundErrorExpression(syntax.Span);
        }

        _delegated[_currentFunction] = chosen;

        var self = new BoundThis(syntax.Span, classType, _currentFunction.Parameters[0]);

        _boundExplicitChain = true;
        return BuildCall(syntax, chosen, self, arguments, nonVirtual: true);
    }

    /// <summary>Which constructor each delegating one runs, for the cycle check.</summary>
    private readonly Dictionary<FunctionSymbol, FunctionSymbol> _delegated = [];

    /// <summary>
    /// Refuses a ring of constructors that delegate to each other.
    ///
    /// Each one is legal on its own and the ring never builds anything, so this
    /// cannot be seen from a single body -- it is checked once every body has
    /// said where it delegates.
    /// </summary>
    private void CheckConstructorDelegation()
    {
        foreach (var start in _delegated.Keys)
        {
            var seen = new HashSet<FunctionSymbol> { start };

            for (var current = _delegated[start];
                 _delegated.TryGetValue(current, out var next);
                 current = next)
            {
                if (seen.Add(current)) continue;

                diagnostics.Error("SL0521", start.Span,
                    $"the constructors of '{start.ContainingType!.Name}' delegate to each other " +
                    "in a ring, so none of them ever builds anything");
                break;
            }
        }
    }

    /// <summary>
    /// Supplies the body of an automatic accessor, which has no syntax to bind.
    ///
    /// The getter returns the hidden field and the setter stores into it, and
    /// that is the entire meaning of <c>{ get; set; }</c>. Building the bound
    /// nodes directly rather than synthesising source keeps the backing field
    /// unnameable: there is no point at which a name has to resolve to it.
    /// </summary>
    private void BindAutoAccessor(FunctionSymbol accessor)
    {
        if (!_boundFunctions.Add(accessor)) return;
        if (accessor.Accessor?.BackingField is not { } field) return;

        var span = accessor.Span;
        var receiver = Receiver(span, accessor.Parameters[0]);
        var storage = new BoundFieldAccess(span, receiver, field);

        BoundStatement statement = accessor.ReturnType.IsVoid()
            ? new BoundExpressionStatement(span, new BoundAssignment(
                span, storage, new BoundParameterAccess(span, accessor.Parameters[1])))
            : new BoundReturn(span, storage);

        _functions.Add(new BoundFunction(accessor, new BoundBlock(span, [statement])));
    }

    // ============================================================ variants

    /// <summary>
    /// The declaration a narrowed fact can be attached to.
    ///
    /// Only a plain local or parameter qualifies. A field or a call result is
    /// refused for the reason a compound assignment refuses a computed receiver:
    /// the compiler would be proving something about one evaluation and letting
    /// it be read from another. Putting the Result in a local first is the fix,
    /// and it is what the code wants to say anyway.
    /// </summary>
    private static object? NarrowableSubject(BoundExpression expression) => expression switch
    {
        BoundLocalAccess local => local.Local,
        BoundParameterAccess parameter => parameter.Parameter,
        _ => null,
    };

    /// <summary>Forgets what was known about a Result, because something may have changed it.</summary>
    private void InvalidateVariantFact(BoundExpression target)
    {
        // Writing a field of a Result changes it just as assigning the whole
        // thing does, so the subject is looked for through field accesses too.
        for (BoundExpression? current = target; current is not null;
             current = (current as BoundFieldAccess)?.Receiver)
        {
            if (NarrowableSubject(current) is not { } subject) continue;

            _variantFacts.Remove(subject);
            return;
        }
    }

    /// <summary>
    /// What a condition proves when it is true, and what it proves when it is
    /// false.
    ///
    /// Only the shapes a variant is actually tested with are read: <c>v.Case</c>,
    /// its negation, and the two short-circuit operators. Anything else proves
    /// nothing, which costs a diagnostic rather than soundness.
    ///
    /// A true test proves the case outright. A false one proves a case only when
    /// there are exactly two, because then ruling one out leaves no choice --
    /// which is what keeps <c>if (!r.Ok) { ... r.Error ... }</c> working now that
    /// Result is an ordinary variant.
    /// </summary>
    private (Dictionary<object, VariantCaseSymbol> WhenTrue, Dictionary<object, VariantCaseSymbol> WhenFalse)
        ConditionFacts(BoundExpression condition)
    {
        switch (condition)
        {
            case BoundVariantTest test
                when NarrowableSubject(test.Value) is { } subject:
            {
                var variant = test.Case.DeclaringVariant;
                var whenTrue = new Dictionary<object, VariantCaseSymbol> { [subject] = test.Case };

                var others = variant.Cases.Where(c => c != test.Case).ToList();
                var whenFalse = others.Count == 1
                    ? new Dictionary<object, VariantCaseSymbol> { [subject] = others[0] }
                    : [];

                return (whenTrue, whenFalse);
            }

            case BoundUnary { Operator: BoundUnaryOp.LogicalNot } negation:
            {
                var (whenTrue, whenFalse) = ConditionFacts(negation.Operand);
                return (whenFalse, whenTrue);
            }

            // `a && b` proves both only when it is true; either could be the
            // false one, so falsehood proves nothing. `a || b` is the mirror.
            case BoundBinary { Operator: BoundBinaryOp.LogicalAnd } and:
            {
                var left = ConditionFacts(and.Left);
                var right = ConditionFacts(and.Right);
                return (Merge(left.WhenTrue, right.WhenTrue), []);
            }

            case BoundBinary { Operator: BoundBinaryOp.LogicalOr } or:
            {
                var left = ConditionFacts(or.Left);
                var right = ConditionFacts(or.Right);
                return ([], Merge(left.WhenFalse, right.WhenFalse));
            }

            default:
                return ([], []);
        }
    }

    private static Dictionary<object, VariantCaseSymbol> Merge(
        Dictionary<object, VariantCaseSymbol> first, Dictionary<object, VariantCaseSymbol> second)
    {
        var merged = new Dictionary<object, VariantCaseSymbol>(first);
        foreach (var (key, value) in second) merged[key] = value;
        return merged;
    }

    private Dictionary<object, VariantCaseSymbol> SnapshotFacts() => new(_variantFacts);

    private void ApplyFacts(Dictionary<object, VariantCaseSymbol> facts)
    {
        foreach (var (key, value) in facts) _variantFacts[key] = value;
    }

    /// <summary>
    /// Drops every fact about a name the given statement assigns to.
    ///
    /// A loop body runs more than once, so a fact proved by its condition on the
    /// way in says nothing about the second time round if the body reassigned
    /// the Result. Matching on the name rather than the symbol makes this
    /// over-eager under shadowing, which loses a narrowing and never invents one.
    /// </summary>
    private void InvalidateAssignedIn(Syntax.StatementSyntax body)
    {
        var assigned = new HashSet<string>(StringComparer.Ordinal);
        CollectAssignedNames(body, assigned);
        if (assigned.Count == 0) return;

        foreach (var subject in _variantFacts.Keys.ToList())
        {
            string name = subject switch
            {
                LocalSymbol local => local.Name,
                ParameterSymbol parameter => parameter.Name,
                _ => "",
            };

            if (assigned.Contains(name)) _variantFacts.Remove(subject);
        }
    }

    private static void CollectAssignedNames(Syntax.SyntaxNode? node, HashSet<string> names)
    {
        if (node is null) return;

        if (node is Syntax.AssignmentSyntax assignment && RootName(assignment.Target) is { } assigned)
            names.Add(assigned);

        foreach (var child in ChildNodes(node)) CollectAssignedNames(child, names);
    }

    private static readonly Dictionary<Type, System.Reflection.PropertyInfo[]> ChildProperties = [];

    /// <summary>
    /// The syntax nodes one node holds, found by reflection.
    ///
    /// The AST is a set of records with no common child accessor, and writing a
    /// visitor over all of them to answer one question about loops would be more
    /// code than the question is worth. This walks the record's own properties
    /// instead, so a new node kind is covered the day it is added.
    /// </summary>
    private static IEnumerable<Syntax.SyntaxNode> ChildNodes(Syntax.SyntaxNode node)
    {
        var type = node.GetType();
        if (!ChildProperties.TryGetValue(type, out var properties))
        {
            properties = type.GetProperties()
                .Where(p => p.GetIndexParameters().Length == 0 &&
                            (typeof(Syntax.SyntaxNode).IsAssignableFrom(p.PropertyType) ||
                             typeof(System.Collections.IEnumerable).IsAssignableFrom(p.PropertyType)))
                .ToArray();
            ChildProperties[type] = properties;
        }

        foreach (var property in properties)
        {
            object? value = property.GetValue(node);

            if (value is Syntax.SyntaxNode child)
            {
                yield return child;
            }
            else if (value is System.Collections.IEnumerable sequence and not string)
            {
                foreach (object? item in sequence)
                    if (item is Syntax.SyntaxNode listed) yield return listed;
            }
        }
    }

    /// <summary>The identifier an assignment target is rooted at, if it is rooted at one.</summary>
    private static string? RootName(Syntax.ExpressionSyntax expression) => expression switch
    {
        Syntax.NameSyntax name when name.Name.Parts.Count == 1 => name.Name.Parts[0],
        Syntax.MemberAccessSyntax member => RootName(member.Target),
        Syntax.IndexSyntax index => RootName(index.Target),
        _ => null,
    };

    /// <summary>Conservative reachability check: does this statement always return?</summary>
    private static bool AlwaysReturns(BoundStatement statement) => statement switch
    {
        BoundReturn => true,
        BoundBlock block => block.Statements.Any(AlwaysReturns),
        BoundIf { Else: not null } ifStatement =>
            AlwaysReturns(ifStatement.Then) && AlwaysReturns(ifStatement.Else),
        // `while (true)` without a break never falls through.
        BoundWhile { Condition: BoundLiteral { Value: true } } loop => !ContainsBreak(loop.Body),
        BoundFor { Condition: null } loop => !ContainsBreak(loop.Body),

        // Every arm returns and no value escapes them, so nothing reaches the
        // statement after the switch.
        BoundSwitch chosen =>
            (chosen.IsExhaustive || chosen.Sections.Any(s => s.IsDefault)) &&
            chosen.Sections.All(s => AlwaysReturns(s.Body)),

        _ => false,
    };

    private static bool ContainsBreak(BoundStatement statement) => statement switch
    {
        BoundBreak => true,

        // A break inside a nested switch belongs to that switch, not to us.
        BoundSwitch => false,
        BoundBlock block => block.Statements.Any(ContainsBreak),
        BoundIf ifStatement => ContainsBreak(ifStatement.Then) ||
                               (ifStatement.Else is not null && ContainsBreak(ifStatement.Else)),
        _ => false,     // a break inside a nested loop belongs to that loop
    };

    // ------------------------------------------------------------ scopes

    private void PushScope() => _scopes.Add(new Dictionary<string, LocalSymbol>(StringComparer.Ordinal));
    private void PopScope() => _scopes.RemoveAt(_scopes.Count - 1);

    private LocalSymbol? LookupLocal(string name)
    {
        for (int i = _scopes.Count - 1; i >= 0; i--)
            if (_scopes[i].TryGetValue(name, out var local)) return local;
        return null;
    }

    private LocalSymbol DeclareLocal(string name, TypeSymbol type, bool isConst, SourceSpan span)
    {
        var local = new LocalSymbol(name, type, isConst);
        if (LookupLocal(name) is not null)
            diagnostics.Error("SL0218", span, $"'{name}' is already declared in this scope");
        else if (_currentFunction?.Parameters.Any(p => p.Name == name) == true)
            diagnostics.Error("SL0219", span, $"'{name}' is already the name of a parameter");
        _scopes[^1][name] = local;
        return local;
    }

    // ------------------------------------------------------------ statements

    private BoundBlock BindBlock(BlockSyntax syntax)
    {
        PushScope();
        var statements = new List<BoundStatement>();
        var block = new BoundBlock(syntax.Span, statements);

        foreach (var statement in syntax.Statements)
        {
            var bound = BindStatement(statement);
            if (bound is BoundLocalDeclaration declaration) block.Locals.Add(declaration.Local);
            statements.Add(bound);
        }

        PopScope();
        return block;
    }

    private BoundStatement BindStatement(StatementSyntax syntax) => syntax switch
    {
        BlockSyntax block => BindBlock(block),
        LocalDeclSyntax local => BindLocalDeclaration(local),
        ExpressionStatementSyntax expression => BindExpressionStatement(expression),
        IfSyntax ifStatement => BindIf(ifStatement),
        WhileSyntax whileStatement => BindWhile(whileStatement),
        ForSyntax forStatement => BindFor(forStatement),
        ForEachSyntax forEach => BindForEach(forEach),
        ParallelSyntax parallel => BindParallel(parallel),
        ParallelForSyntax parallelFor => BindParallelFor(parallelFor),
        SpawnSyntax spawn => BindSpawn(spawn),
        ReturnSyntax returnStatement => BindReturn(returnStatement),
        SwitchSyntax switchStatement => BindSwitch(switchStatement),
        BreakSyntax breakStatement => BindBreak(breakStatement),
        ContinueSyntax continueStatement => BindContinue(continueStatement),
        _ => new BoundBlock(syntax.Span, []),
    };

    private BoundStatement BindLocalDeclaration(LocalDeclSyntax syntax)
    {
        BoundExpression? initializer = null;
        TypeSymbol type;

        if (syntax.Type is null)
        {
            // `var` requires an initializer to infer from.
            if (syntax.Initializer is null)
            {
                diagnostics.Error("SL0220", syntax.Span,
                    $"'var {syntax.Name}' needs an initializer for its type to be inferred");
                type = ErrorTypeSymbol.Instance;
            }
            else
            {
                initializer = BindExpression(syntax.Initializer);
                type = initializer.Type;
                if (type.IsVoid())
                {
                    diagnostics.Error("SL0221", syntax.Initializer.Span,
                        "cannot infer a type from an expression of type 'void'");
                    type = ErrorTypeSymbol.Instance;
                }
                else if (type is VariantDraftType)
                {
                    string built = (initializer as BoundVariantDraft)?.Case ?? "a case";
                    diagnostics.Error("SL0287", syntax.Initializer.Span,
                        $"'{syntax.Name}' cannot be a 'var': '{built}' names a case without " +
                        "naming its variant, and one value does not say what a variant's type " +
                        "arguments are. Write the type out, name the variant as in " +
                        $"'Shape.{built}(...)', or return this directly from a function that " +
                        "declares it");
                    type = ErrorTypeSymbol.Instance;
                }
            }
        }
        else
        {
            type = ResolveType(syntax.Type, _currentScope!);
            if (syntax.Initializer is not null)
                initializer = BindConversion(BindExpression(syntax.Initializer), type, syntax.Initializer.Span);
        }

        var local = DeclareLocal(syntax.Name, type, syntax.IsConst, syntax.Span);
        return new BoundLocalDeclaration(syntax.Span, local, initializer);
    }

    private BoundStatement BindExpressionStatement(ExpressionStatementSyntax syntax)
    {
        var expression = BindExpression(syntax.Expression);

        bool hasEffect = expression is BoundAssignment or BoundPropertyAssignment or BoundCall
                                    or BoundIndirectCall or BoundNew or BoundErrorExpression;
        if (!hasEffect)
            diagnostics.Warning("SL0222", syntax.Span,
                "this expression has no effect; its result is discarded");

        return new BoundExpressionStatement(syntax.Span, expression);
    }

    private BoundStatement BindIf(IfSyntax syntax)
    {
        var condition = BindCondition(syntax.Condition);
        var (whenTrue, whenFalse) = ConditionFacts(condition);

        var entry = SnapshotFacts();

        ApplyFacts(whenTrue);
        var then = BindStatement(syntax.Then);

        _variantFacts = new Dictionary<object, VariantCaseSymbol>(entry);
        ApplyFacts(whenFalse);
        var otherwise = syntax.Else is null ? null : BindStatement(syntax.Else);

        _variantFacts = entry;

        // A branch that always leaves proves its opposite for everything after
        // the `if`. This is what makes the early return read the way it should:
        // `if (!read.Ok) { return Fail(read.Error); }` and the rest of the
        // function is holding a value.
        bool thenExits = AlwaysExits(then);
        bool elseExits = otherwise is not null && AlwaysExits(otherwise);

        if (thenExits && !elseExits) ApplyFacts(whenFalse);
        else if (elseExits && !thenExits) ApplyFacts(whenTrue);

        return new BoundIf(syntax.Span, condition, then, otherwise);
    }

    private BoundStatement BindWhile(WhileSyntax syntax)
    {
        var condition = BindCondition(syntax.Condition);

        // A loop body runs again, so anything it assigns to is unknown inside it
        // however the loop was entered.
        if (_variantFacts.Count > 0) InvalidateAssignedIn(syntax.Body);

        var entry = SnapshotFacts();
        ApplyFacts(ConditionFacts(condition).WhenTrue);

        _loopDepth++;
        var body = BindStatement(syntax.Body);
        _loopDepth--;

        // Nothing the condition proved survives the loop: it is also left by
        // failing that same condition.
        _variantFacts = entry;
        return new BoundWhile(syntax.Span, condition, body);
    }

    private BoundStatement BindFor(ForSyntax syntax)
    {
        PushScope();

        BoundStatement? initializer = syntax.Initializer is null ? null : BindStatement(syntax.Initializer);
        var condition = syntax.Condition is null ? null : BindCondition(syntax.Condition);
        var step = syntax.Step is null ? null : BindExpression(syntax.Step);

        // The same rule a `while` obeys: what the body assigns to is unknown
        // inside it, and the condition proves nothing after it.
        if (_variantFacts.Count > 0) InvalidateAssignedIn(syntax.Body);
        var entry = SnapshotFacts();
        if (condition is not null) ApplyFacts(ConditionFacts(condition).WhenTrue);

        _loopDepth++;
        var body = BindStatement(syntax.Body);
        _loopDepth--;
        _variantFacts = entry;

        var result = new BoundFor(syntax.Span, initializer, condition, step, body);
        if (initializer is BoundLocalDeclaration declaration) result.Locals.Add(declaration.Local);

        PopScope();
        return result;
    }

    /// <summary>
    /// <c>foreach</c>, lowered here rather than in the emitter.
    ///
    /// An array iterates by index, which costs no allocation and no dispatch.
    /// Anything else is asked for a <c>GetEnumerator()</c>, found by name rather
    /// than by interface, so a type can be iterable without Standard.Collections
    /// appearing anywhere in the program.
    ///
    /// The collection is evaluated once into a hidden local, which fixes the
    /// semantics and keeps the object alive for the whole loop. Its name starts
    /// with '$' so no source identifier can collide with it, and is numbered so
    /// that nested loops do not collide with each other.
    /// </summary>
    private BoundStatement BindForEach(ForEachSyntax syntax)
    {
        PushScope();

        var collection = BindExpression(syntax.Collection);
        var statements = new List<BoundStatement>();
        var outer = new BoundBlock(syntax.Span, statements);

        if (collection.Type.IsError())
        {
            PopScope();
            return outer;
        }

        var sequence = DeclareLocal(
            SyntheticName("sequence"), collection.Type, isConst: false, syntax.Collection.Span);
        statements.Add(new BoundLocalDeclaration(syntax.Collection.Span, sequence, collection));
        outer.Locals.Add(sequence);

        if (collection.Type is ArrayTypeSymbol array)
            statements.Add(BuildArrayLoop(syntax, sequence, array.Element));
        else if (collection.Type is SliceTypeSymbol slice)
            statements.Add(BuildArrayLoop(syntax, sequence, slice.Element));
        else if (BuildEnumeratorLoop(syntax, sequence, outer, statements) is { } loop)
            statements.Add(loop);

        PopScope();
        return outer;
    }

    /// <summary>The array fast path: an ordinary indexed <c>for</c>.</summary>
    private BoundStatement BuildArrayLoop(
        ForEachSyntax syntax, LocalSymbol sequence, TypeSymbol element)
    {
        PushScope();

        var index = DeclareLocal(
            SyntheticName("index"), PrimitiveTypeSymbol.NUInt, isConst: false, syntax.Span);
        var initializer = new BoundLocalDeclaration(syntax.Span, index,
            new BoundLiteral(syntax.Span, PrimitiveTypeSymbol.NUInt, 0UL));

        var condition = new BoundBinary(syntax.Span, PrimitiveTypeSymbol.Bool,
            new BoundLocalAccess(syntax.Span, index),
            BoundBinaryOp.Less,
            new BoundArrayLength(syntax.Span, PrimitiveTypeSymbol.NUInt,
                new BoundLocalAccess(syntax.Span, sequence)));

        var step = new BoundAssignment(syntax.Span,
            new BoundLocalAccess(syntax.Span, index),
            new BoundBinary(syntax.Span, PrimitiveTypeSymbol.NUInt,
                new BoundLocalAccess(syntax.Span, index),
                BoundBinaryOp.Add,
                new BoundLiteral(syntax.Span, PrimitiveTypeSymbol.NUInt, 1UL)));

        var item = new BoundIndex(syntax.Span, element,
            new BoundLocalAccess(syntax.Span, sequence),
            new BoundLocalAccess(syntax.Span, index));

        var body = BindForEachBody(syntax, item);

        var loop = new BoundFor(syntax.Span, initializer, condition, step, body);
        loop.Locals.Add(index);

        PopScope();
        return loop;
    }

    /// <summary>
    /// The general path: <c>while ($e.MoveNext()) { var x = $e.Current(); ... }</c>.
    /// Putting MoveNext in the condition is what makes <c>continue</c> advance the
    /// enumerator rather than spin on the same element.
    /// </summary>
    private BoundStatement? BuildEnumeratorLoop(
        ForEachSyntax syntax, LocalSymbol sequence, BoundBlock outer, List<BoundStatement> statements)
    {
        if (sequence.Type is not NamedTypeSymbol source ||
            source.FindMethod("GetEnumerator") is not { } getEnumerator ||
            getEnumerator.Parameters.Count(p => !p.IsThis) != 0)
        {
            diagnostics.Error("SL0356", syntax.Collection.Span,
                $"'{sequence.Type.Name}' cannot be iterated; it is not an array and has no " +
                "'GetEnumerator()' method taking no arguments");
            return null;
        }

        if (getEnumerator.ReturnType is not NamedTypeSymbol enumerator ||
            enumerator.FindMethod("MoveNext") is not { } moveNext ||
            !moveNext.ReturnType.IsBool() ||
            moveNext.Parameters.Count(p => !p.IsThis) != 0 ||
            enumerator.FindMethod("Current") is not { } current ||
            current.Parameters.Count(p => !p.IsThis) != 0 ||
            current.ReturnType.IsVoid())
        {
            diagnostics.Error("SL0357", syntax.Collection.Span,
                $"'{sequence.Type.Name}.GetEnumerator()' returns '{getEnumerator.ReturnType.Name}', " +
                "which is not an enumerator; that needs a 'bool MoveNext()' and a 'Current()' " +
                "returning the element");
            return null;
        }

        var handle = DeclareLocal(
            SyntheticName("enumerator"), getEnumerator.ReturnType, isConst: false, syntax.Span);
        statements.Add(new BoundLocalDeclaration(syntax.Span, handle,
            new BoundCall(syntax.Span, getEnumerator,
                new BoundLocalAccess(syntax.Span, sequence), [])));
        outer.Locals.Add(handle);

        var condition = new BoundCall(syntax.Span, moveNext,
            new BoundLocalAccess(syntax.Span, handle), []);

        var element = new BoundCall(syntax.Span, current,
            new BoundLocalAccess(syntax.Span, handle), []);

        return new BoundWhile(syntax.Span, condition, BindForEachBody(syntax, element));
    }

    /// <summary>
    /// Declares the loop variable from the element expression, then binds the body
    /// around it. The variable lives inside the loop, so a managed element is
    /// released at the end of each iteration rather than at the end of the loop.
    /// </summary>
    private BoundStatement BindForEachBody(ForEachSyntax syntax, BoundExpression element)
    {
        PushScope();
        if (_variantFacts.Count > 0) InvalidateAssignedIn(syntax.Body);

        var type = syntax.Type is null
            ? element.Type
            : ResolveType(syntax.Type, _currentScope!);

        var value = syntax.Type is null
            ? element
            : BindConversion(element, type, syntax.Collection.Span);

        var variable = DeclareLocal(syntax.Name, type, isConst: false, syntax.Span);

        var statements = new List<BoundStatement>
        {
            new BoundLocalDeclaration(syntax.Span, variable, value),
        };

        var block = new BoundBlock(syntax.Span, statements);
        block.Locals.Add(variable);

        _loopDepth++;
        statements.Add(BindStatement(syntax.Body));
        _loopDepth--;

        PopScope();
        return block;
    }

    /// <summary>
    /// <c>parallel { ... }</c>. The scope is opened before the body and joined
    /// after it, so a job cannot outlive the block -- which is what makes it
    /// safe for a job to borrow the enclosing function's locals.
    ///
    /// Jumping out of the block would skip the join and leave jobs running with
    /// references to a dead frame, so `return`, `break` and `continue` may not
    /// cross the boundary.
    /// </summary>
    private BoundStatement BindParallel(ParallelSyntax syntax)
    {
        int enclosingLoops = _loopDepth;
        int enclosingSwitches = _switchDepth;
        _loopDepth = 0;
        _switchDepth = 0;
        _parallelDepth++;

        var body = BindBlock(syntax.Body);

        _parallelDepth--;
        _loopDepth = enclosingLoops;
        _switchDepth = enclosingSwitches;

        return new BoundParallel(syntax.Span, body);
    }

    private BoundStatement BindSpawn(SpawnSyntax syntax)
    {
        if (_parallelDepth == 0)
        {
            diagnostics.Error("SL0364", syntax.Span,
                "'spawn' needs an enclosing 'parallel' block; it is that block's " +
                "closing brace that waits for the work");
            return new BoundBlock(syntax.Span, []);
        }

        var call = BindExpression(syntax.Call);
        if (call.Type.IsError()) return new BoundBlock(syntax.Span, []);

        // Only a direct call, so the arguments are known values the parent can
        // copy. A delegate would be callable too, but its target is a value that
        // has to be marshalled as well, and that can wait.
        if (call is not BoundCall spawned)
        {
            diagnostics.Error("SL0365", syntax.Call.Span,
                "'spawn' takes a function or method call; there is nothing else " +
                "for a worker thread to run");
            return new BoundBlock(syntax.Span, []);
        }

        if (!CheckSpawnArguments(spawned)) return new BoundBlock(syntax.Span, []);

        if (syntax.Target is null)
            return new BoundSpawn(syntax.Span, null, spawned);

        var target = BindExpression(syntax.Target);
        if (target.Type.IsError()) return new BoundBlock(syntax.Span, []);

        if (!target.IsLValue)
        {
            diagnostics.Error("SL0366", syntax.Target.Span,
                "a spawned result must be stored in a variable, field or element; " +
                "the worker writes it there while the parent waits");
            return new BoundBlock(syntax.Span, []);
        }

        if (spawned.Type.IsVoid())
        {
            diagnostics.Error("SL0367", syntax.Span,
                $"'{spawned.Function.Name}' returns nothing, so there is no result to store");
            return new BoundBlock(syntax.Span, []);
        }

        // The conversion has to be settled here: the worker stores into the
        // parent's slot, so the value must already have that slot's type.
        var converted = BindConversion(spawned, target.Type, syntax.Span);
        if (converted is not BoundCall matched)
        {
            diagnostics.Error("SL0368", syntax.Span,
                $"'{spawned.Function.Name}' returns '{spawned.Type.Name}', which needs a " +
                $"conversion to '{target.Type.Name}'; assign it after the 'parallel' block instead");
            return new BoundBlock(syntax.Span, []);
        }

        return new BoundSpawn(syntax.Span, target, matched);
    }

    /// <summary>
    /// <c>parallel for</c>. The iteration space is computed once and split into
    /// chunks, so the loop has to be a counted one: <c>i = start</c>,
    /// <c>i &lt; limit</c>, <c>i = i + stride</c>. A general C-style <c>for</c>
    /// has no trip count to divide.
    /// </summary>
    private BoundStatement BindParallelFor(ParallelForSyntax syntax)
    {
        PushScope();

        int enclosingLoops = _loopDepth;
        int enclosingSwitches = _switchDepth;
        _loopDepth = 0;
        _switchDepth = 0;
        _parallelDepth++;

        var result = BindParallelForCore(syntax);

        _parallelDepth--;
        _loopDepth = enclosingLoops;
        _switchDepth = enclosingSwitches;

        PopScope();
        return result;
    }

    private BoundStatement BindParallelForCore(ParallelForSyntax syntax)
    {
        var initializer = BindStatement(syntax.Initializer);

        if (initializer is not BoundLocalDeclaration { Initializer: { } start } declaration ||
            declaration.Local.Type is not PrimitiveTypeSymbol { IsInteger: true })
        {
            diagnostics.Error("SL0369", syntax.Initializer.Span,
                "a 'parallel for' must start by declaring an integer loop variable, " +
                "as in 'parallel for (int i = 0; ...)'");
            return new BoundBlock(syntax.Span, []);
        }

        var variable = declaration.Local;

        var condition = BindExpression(syntax.Condition);
        if (condition is not BoundBinary
            {
                Operator: BoundBinaryOp.Less or BoundBinaryOp.LessEqual,
            } test ||
            Underlying(test.Left) is not BoundLocalAccess counted || counted.Local != variable)
        {
            diagnostics.Error("SL0370", syntax.Condition.Span,
                $"a 'parallel for' condition must be '{variable.Name} < limit' or " +
                $"'{variable.Name} <= limit'; the loop is split before it runs, so its " +
                "trip count has to be known up front");
            return new BoundBlock(syntax.Span, []);
        }

        var step = BindExpression(syntax.Step);
        if (step is not BoundAssignment
            {
                Target: BoundLocalAccess stepped,
                Value: BoundBinary { Operator: BoundBinaryOp.Add } increment,
            } ||
            stepped.Local != variable ||
            Underlying(increment.Left) is not BoundLocalAccess { } from || from.Local != variable)
        {
            diagnostics.Error("SL0371", syntax.Step.Span,
                $"a 'parallel for' step must be '{variable.Name} = {variable.Name} + stride' " +
                $"or '{variable.Name} += stride'");
            return new BoundBlock(syntax.Span, []);
        }

        // A non-constant stride could be zero or negative, and either makes the
        // trip count meaningless. A literal can simply be checked.
        if (Underlying(increment.Right) is not BoundLiteral { Value: ulong raw } || raw == 0)
        {
            diagnostics.Error("SL0372", syntax.Step.Span,
                "the stride of a 'parallel for' must be a positive integer literal, " +
                "because the iteration space is divided before the loop runs");
            return new BoundBlock(syntax.Span, []);
        }

        var body = BindStatement(syntax.Body);

        var walker = new CaptureWalker(variable);
        walker.Visit(body);

        foreach (var capture in walker.Captures)
        {
            var (captureType, captureName) = capture switch
            {
                LocalSymbol local => (local.Type, local.Name),
                ParameterSymbol parameter => (parameter.Type, parameter.Name),
                _ => (ErrorTypeSymbol.Instance as TypeSymbol, "?"),
            };

            if (!IsSendable(captureType))
                ReportNotSendable(captureType, syntax.Span,
                    $"'{captureName}', which every chunk of this loop reads,");
        }

        foreach (var (symbol, span, name) in walker.Assignments)
        {
            diagnostics.Error("SL0373", span,
                $"'{name}' is declared outside this 'parallel for', so assigning to it " +
                "races between chunks; accumulate into an AtomicLong, or into a " +
                "distinct element per iteration");
        }

        return new BoundParallelFor(
            syntax.Span, variable, start, test.Right, increment.Right,
            test.Operator == BoundBinaryOp.LessEqual, body, walker.Captures);
    }

    /// <summary>
    /// A spawned call's arguments are borrowed, exactly as any call's are: the
    /// parent keeps them alive, and no reference count crosses a thread.
    ///
    /// That only works if the parent still holds them when the job runs. A value
    /// created in the argument list is owned by nothing once the statement ends,
    /// and the job would find it destroyed, so it has to be named first.
    /// </summary>
    private bool CheckSpawnArguments(BoundCall call)
    {
        bool ok = true;

        // A `ref` hands a job the address of the parent's variable, and two jobs
        // given the same one race on it with nothing to say they may. The
        // parallel block does keep the frame alive, so this is a rule about
        // sharing rather than about lifetime -- and it is the same rule
        // everything else crossing a thread already obeys.
        foreach (var parameter in call.Function.Parameters.Where(p => p.IsByReference))
        {
            diagnostics.Error("SL0449", call.Span,
                $"'{call.Function.Name}' takes '{Spelled(parameter)} {parameter.Name}', and a " +
                "spawned call would hand a job the address of the caller's storage; two jobs " +
                "given the same one would race on it. Pass a copy, or guard it with 'Mutex<T>'");
            ok = false;
        }

        if (call.Receiver is { } receiver)
        {
            if (receiver.Type.NeedsArc() && !IsHeldElsewhere(receiver))
            {
                diagnostics.Error("SL0375", receiver.Span,
                    "the receiver of a spawned call must be held in a variable or field; " +
                    "a job borrows what it is given, and a temporary is gone before it runs");
                ok = false;
            }
            else if (!IsSendable(receiver.Type))
            {
                ReportNotSendable(receiver.Type, receiver.Span, "the receiver of this spawned call");
                ok = false;
            }
        }

        foreach (var argument in call.Arguments)
        {
            if (argument.Type.NeedsArc() && !IsHeldElsewhere(argument))
            {
                diagnostics.Error("SL0375", argument.Span,
                    $"a spawned call borrows its arguments, so this '{argument.Type.Name}' must be " +
                    "held in a variable or field first; a temporary is destroyed at the end of " +
                    "this statement, before the job runs");
                ok = false;
                continue;
            }

            // The parent keeps hold of what it lends, so both threads can reach it.
            if (!IsSendable(argument.Type))
            {
                ReportNotSendable(argument.Type, argument.Span, "this argument to a spawned call");
                ok = false;
            }
        }

        return ok;
    }

    /// <summary>
    /// True when something other than this expression owns the value: a variable,
    /// a field, an element, or a literal, which is immortal.
    /// </summary>
    private static bool IsHeldElsewhere(BoundExpression expression) => expression switch
    {
        BoundConversion conversion => IsHeldElsewhere(conversion.Operand),
        BoundStringLiteral or BoundNullLiteral => true,
        BoundLocalAccess or BoundParameterAccess or BoundThis => true,
        BoundFieldAccess or BoundIndex or BoundDereference => true,
        _ => false,
    };

    /// <summary>
    /// The storage an lvalue ultimately names, looking through field access and
    /// indexing. A write to <c>Config.Limits[0]</c> is a write to <c>Config</c>.
    /// </summary>
    /// <summary>
    /// The parameter an assignment writes into, when the write lands in the
    /// parameter's own storage rather than through a reference it holds.
    ///
    /// <c>p = x</c> and, for a struct parameter, <c>p.field = x</c> both change
    /// the callee's private copy, and that copy must therefore own what it
    /// holds. <c>p[i] = x</c> and a write through a class field are a different
    /// thing entirely: they reach the caller's object, which is the whole point
    /// of passing it, and the parameter is still borrowed.
    /// </summary>
    private static ParameterSymbol? WrittenParameter(BoundExpression target) => target switch
    {
        BoundParameterAccess parameter => parameter.Parameter,

        BoundFieldAccess { Receiver: { } receiver } when receiver.Type is StructTypeSymbol =>
            WrittenParameter(receiver),

        // A struct's setter is called through the receiver's address, and any
        // address of a struct is a way to write into it.
        BoundAddressOf { Operand: { } operand } when operand.Type is StructTypeSymbol =>
            WrittenParameter(operand),

        _ => null,
    };

    private static BoundExpression BaseOf(BoundExpression expression) => expression switch
    {
        BoundFieldAccess { Receiver: { } receiver } => BaseOf(receiver),
        BoundIndex index => BaseOf(index.Target),
        BoundConversion conversion => BaseOf(conversion.Operand),

        // A struct receiver is passed by address, so the address of a thing is
        // still that thing as far as ownership goes.
        BoundAddressOf address => BaseOf(address.Operand),
        _ => expression,
    };

    /// <summary>Strips conversions, so a widened loop variable still matches.</summary>
    private static BoundExpression Underlying(BoundExpression expression) =>
        expression is BoundConversion conversion ? Underlying(conversion.Operand) : expression;


    // ============================================================ sendability

    /// <summary>
    /// Whether a value of this type may be reached by more than one thread.
    ///
    /// Reference counts are atomic, so sharing an object no longer corrupts its
    /// count. What is left is the harder half: nothing synchronizes the object's
    /// *contents*, and two threads writing the same field is a race no count
    /// could have saved. Three cases are safe:
    ///
    ///   plain data       there is no shared mutable state; a value is copied
    ///   String           immutable, and its bytes live inside the object
    ///   [Shared]         the author has said the type synchronizes internally
    ///
    /// An array of plain data is included as a fourth, and it is the one that is
    /// pragmatic rather than proven: a job borrows the array without retaining
    /// it, which is sound as far as it goes, but nothing yet stops the job from
    /// storing it somewhere and retaining it then. It earns its place because
    /// data parallelism is the point of `parallel for`, and rejecting it would
    /// leave the feature with nothing to iterate.
    /// </summary>
    private bool IsSendable(TypeSymbol type) => type switch
    {
        PrimitiveTypeSymbol or PointerTypeSymbol or EnumTypeSymbol or DelegateTypeSymbol => true,

        // A variant's own fields are a tag and a blob of bytes, both of them
        // plain data, so asking them would say yes to a variant holding a List.
        // What it really holds is whatever its cases hold.
        VariantTypeSymbol variant =>
            variant.Cases.SelectMany(c => c.Fields).All(f => IsSendable(f.Type)),

        // A struct is as safe as the things inside it. Copying one retains what
        // it holds, and that is sound now that counts are atomic, so a struct of
        // primitives and Strings crosses as freely as its parts would.
        StructTypeSymbol structType => structType.Fields.All(f => IsSendable(f.Type)),

        ArrayTypeSymbol array => IsPlainData(array.Element),

        _ when _builtins.IsString(type) => true,

        NamedTypeSymbol named => IsShared(named),

        OptionalTypeSymbol optional => IsSendable(optional.Element),

        _ => false,
    };

    private bool IsPlainData(TypeSymbol type) =>
        type is PrimitiveTypeSymbol or PointerTypeSymbol or EnumTypeSymbol or DelegateTypeSymbol
        || (type is StructTypeSymbol structType && !structType.CarriesReferences());

    /// <summary>True when the type carries <c>[Shared]</c>.</summary>
    private static bool IsShared(NamedTypeSymbol type) =>
        type.Attributes.Any(a => a.Type.SimpleName == "Shared");

    /// <summary>
    /// True for an enum marked <c>[Flags]</c>: a set of bits rather than a
    /// choice among alternatives, and so something <c>|</c> can combine.
    /// </summary>
    private bool IsFlags(TypeSymbol type) =>
        type is EnumTypeSymbol enumType &&
        enumType.Attributes.Any(a => a.Type == _builtins.Flags);

    /// <summary>
    /// Reports a value that would be reachable from two threads at once.
    /// The message names the three ways out, because the fix is never obvious
    /// from the rule alone.
    /// </summary>
    private void ReportNotSendable(TypeSymbol type, SourceSpan span, string what)
    {
        diagnostics.Error("SL0377", span,
            $"{what} is '{type.Name}', which more than one thread would reach, and " +
            "nothing about it says how two of them may. Counts are atomic, so the " +
            "reference itself is safe; what is not is the contents. Pass plain data or " +
            $"a String, guard it with 'Mutex<T>', or mark '{type.Name}' with [Shared] " +
            "if it already synchronizes itself");
    }


    // ============================================================ statics

    private void DeclareStatic(FileScope scope, StaticDeclSyntax declaration)
    {
        var module = scope.Module;

        if (module.Statics.ContainsKey(declaration.Name) ||
            module.Constants.ContainsKey(declaration.Name))
        {
            diagnostics.Error("SL0214", declaration.Span,
                $"'{declaration.Name}' is already declared in module '{module.Name}'");
            return;
        }

        var type = ResolveType(declaration.Type, scope);

        module.Statics[declaration.Name] = new StaticSymbol(declaration.Name, type, module.Name)
        {
            IsPublic = declaration.Modifiers.HasFlag(Modifiers.Public),
            Span = declaration.Span,
        };

        _staticSyntax[module.Statics[declaration.Name]] = (declaration, scope);
    }

    /// <summary>
    /// Binds every static's initializer, then decides what order they run in.
    ///
    /// C++ cannot do this and calls the result a fiasco; Swift avoids it by
    /// making every static lazy and paying a guard check on every access, which
    /// has to become atomic the moment threads exist. Stainless compiles the
    /// whole program at once, so it can simply look at the dependency graph and
    /// sort it -- no guard, no per-access cost, and a compile error rather than
    /// a runtime mystery when the graph has a cycle.
    /// </summary>
    private void BindStatics()
    {
        foreach (var (symbol, (declaration, scope)) in _staticSyntax)
        {
            _currentScope = scope;
            _currentFunction = null;

            var value = BindConversion(
                BindExpression(declaration.Value), symbol.Type, declaration.Value.Span);
            symbol.Initializer = value;

            // A static outlives every thread, so whatever it holds is reachable
            // from all of them at once.
            if (!IsSendable(symbol.Type))
                ReportNotSendable(symbol.Type, declaration.Span, $"static '{symbol.Name}'");
        }

        _currentScope = null;

        foreach (var (symbol, _) in _staticSyntax)
            CollectStaticDependencies(symbol, symbol.Initializer);

        _staticOrder = SortStatics();
    }

    private static void CollectStaticDependencies(StaticSymbol owner, BoundExpression? expression)
    {
        var walker = new StaticReferenceWalker();
        walker.Visit(expression);

        foreach (var referenced in walker.Found)
            if (referenced != owner && !owner.DependsOn.Contains(referenced))
                owner.DependsOn.Add(referenced);
    }

    /// <summary>
    /// Orders the statics so that nothing runs before what it reads. A cycle is
    /// reported here rather than left to produce a zero at run time.
    /// </summary>
    private List<StaticSymbol> SortStatics()
    {
        var ordered = new List<StaticSymbol>();
        var done = new HashSet<StaticSymbol>();
        var onStack = new HashSet<StaticSymbol>();

        void Visit(StaticSymbol symbol)
        {
            if (done.Contains(symbol)) return;

            if (!onStack.Add(symbol))
            {
                diagnostics.Error("SL0378", symbol.Span,
                    $"the initializer of '{symbol.QualifiedName}' depends on itself, " +
                    "directly or through another static; there is no order that would " +
                    "give it a value before it is read");
                return;
            }

            foreach (var dependency in symbol.DependsOn) Visit(dependency);

            onStack.Remove(symbol);
            if (done.Add(symbol)) ordered.Add(symbol);
        }

        foreach (var symbol in _staticSyntax.Keys) Visit(symbol);
        return ordered;
    }


    // ============================================================ closures

    /// <summary>
    /// What a lambda body can see of the scope it was written in, and where the
    /// values it reaches for end up.
    /// </summary>
    private sealed class ClosureContext
    {
        /// <summary>The generated class, or null for a lambda becoming a delegate.</summary>
        public ClassTypeSymbol? Type { get; init; }
        public ParameterSymbol? This { get; init; }

        /// <summary>The scope chain in force where the lambda was written.</summary>
        public required List<Dictionary<string, LocalSymbol>> OuterScopes { get; init; }
        public required FunctionSymbol? OuterFunction { get; init; }

        public Dictionary<string, FieldSymbol> Captured { get; } = new(StringComparer.Ordinal);
        public List<(FieldSymbol Field, BoundExpression Value)> Captures { get; } = [];
    }

    private readonly List<ClosureContext> _closures = [];
    private int _closureCount;

    /// <summary>
    /// Resolves a name a lambda body used but did not declare, by capturing it.
    ///
    /// The value is read in the scope the lambda was written in and copied into
    /// a field, so the closure owns what it captured rather than pointing at a
    /// frame that may be gone. Nested lambdas capture through one another: the
    /// inner one captures from the outer one's field, which the outer one
    /// captured in turn.
    /// </summary>
    private BoundExpression? TryCapture(string name, SourceSpan span) =>
        _closures.Count == 0 ? null : CaptureFrom(_closures.Count - 1, name, span);

    private BoundExpression? CaptureFrom(int index, string name, SourceSpan span)
    {
        var closure = _closures[index];

        if (closure.Captured.TryGetValue(name, out var already))
            return new BoundFieldAccess(
                span, new BoundThis(span, closure.Type!, closure.This!), already);

        var outer = ResolveOutside(index, name, span);
        if (outer is null) return null;

        if (closure.Type is null)
        {
            diagnostics.Error("SL0381", span,
                $"this lambda reads '{name}' from around it, so it cannot become a delegate; " +
                "a delegate is a bare function pointer with nowhere to keep what was " +
                "captured. Convert it to a single-method interface instead");
            return new BoundErrorExpression(span);
        }

        if (outer.Type.IsVoid() || outer.Type.IsError()) return new BoundErrorExpression(span);

        var field = new FieldSymbol(name, outer.Type, closure.Type, closure.Type.Fields.Count);
        closure.Type.Fields.Add(field);
        closure.Captured[name] = field;
        closure.Captures.Add((field, outer));

        return new BoundFieldAccess(span, new BoundThis(span, closure.Type, closure.This!), field);
    }

    /// <summary>Reads a name in the context the closure at <paramref name="index"/> was written in.</summary>
    private BoundExpression? ResolveOutside(int index, string name, SourceSpan span)
    {
        var closure = _closures[index];

        for (int i = closure.OuterScopes.Count - 1; i >= 0; i--)
            if (closure.OuterScopes[i].TryGetValue(name, out var local))
                return new BoundLocalAccess(span, local);

        if (closure.OuterFunction?.Parameters.FirstOrDefault(p => p.Name == name && !p.IsThis)
            is { } parameter)
            return new BoundParameterAccess(span, parameter);

        // The lambda that encloses this one may be able to reach it.
        if (index > 0) return CaptureFrom(index - 1, name, span);

        // Otherwise it may be a member of the object the lambda was written
        // inside. Reading it here rather than in the lambda body is what makes
        // it a capture: the value is copied into a field, so the closure holds
        // the member's value and not a route back to the object.
        return MemberOfEnclosingThis(closure, name, span);
    }

    /// <summary>
    /// <c>this.name</c> in the context the outermost lambda was written in, or
    /// null if there is no <c>this</c> there or it has no such member.
    /// </summary>
    private BoundExpression? MemberOfEnclosingThis(
        ClosureContext closure, string name, SourceSpan span)
    {
        if (EnclosingThis(closure, span) is not { } receiver) return null;
        if (receiver.Type is not NamedTypeSymbol owner) return null;

        if (owner.FindProperty(name) is { } property)
            return BindPropertyRead(span, receiver, property);

        return owner.FindField(name) is { } field
            ? new BoundFieldAccess(span, receiver, field)
            : null;
    }

    /// <summary>
    /// A method of the type the outermost lambda was written inside, which a
    /// bare call in a lambda body may mean.
    /// </summary>
    private List<FunctionSymbol> MethodsOfEnclosingThis(string name) =>
        _closures.Count == 0
            ? []
            : _closures[0].OuterFunction?.ContainingType?.FindMethods(name).ToList() ?? [];

    /// <summary>The receiver of the method a lambda was written inside, if it had one.</summary>
    private static BoundExpression? EnclosingThis(ClosureContext closure, SourceSpan span) =>
        closure.OuterFunction?.Parameters.FirstOrDefault(p => p.IsThis) is { } self
            ? Receiver(span, self)
            : null;

    /// <summary>
    /// <c>this</c> written inside a lambda, which means the object the lambda
    /// appears in rather than the closure the compiler generated for it.
    ///
    /// It is captured by value under a name no field can collide with, since
    /// <c>this</c> is a keyword. Capturing it rather than pointing at the
    /// enclosing frame is the same rule every other capture obeys.
    /// </summary>
    private BoundExpression CaptureThis(int index, SourceSpan span)
    {
        var closure = _closures[index];

        if (closure.Captured.TryGetValue(ThisCaptureName, out var already))
            return new BoundFieldAccess(
                span, new BoundThis(span, closure.Type!, closure.This!), already);

        var outer = index > 0 ? CaptureThis(index - 1, span) : EnclosingThis(closure, span);

        if (outer is null)
        {
            diagnostics.Error("SL0228", span,
                "'this' is only valid inside a method, constructor or destructor");
            return new BoundErrorExpression(span);
        }

        if (outer.Type.IsError()) return new BoundErrorExpression(span);

        if (closure.Type is null)
        {
            diagnostics.Error("SL0381", span,
                "this lambda reads 'this' from around it, so it cannot become a delegate; " +
                "a delegate is a bare function pointer with nowhere to keep what was " +
                "captured. Convert it to a single-method interface instead");
            return new BoundErrorExpression(span);
        }

        var field = new FieldSymbol(
            ThisCaptureName, outer.Type, closure.Type, closure.Type.Fields.Count);
        closure.Type.Fields.Add(field);
        closure.Captured[ThisCaptureName] = field;
        closure.Captures.Add((field, outer));

        return new BoundFieldAccess(span, new BoundThis(span, closure.Type, closure.This!), field);
    }

    /// <summary>
    /// The closure field a captured <c>this</c> lands in. It is spelled as the
    /// keyword deliberately: no source identifier can be this, so nothing the
    /// programmer writes can collide with it.
    /// </summary>
    private const string ThisCaptureName = "this";

    /// <summary>
    /// Turns a lambda into whatever it is being assigned to: an instance of a
    /// generated class for a single-method interface, or a plain function for a
    /// delegate. A delegate cannot capture, because it is one pointer.
    /// </summary>
    private BoundExpression BindLambda(BoundLambda lambda, TypeSymbol target, SourceSpan span)
    {
        var syntax = lambda.Syntax;

        if (target is DelegateTypeSymbol asDelegate)
            return BindLambdaAsFunction(syntax, asDelegate, span);

        if (target is InterfaceTypeSymbol asInterface && SingleMethodOf(asInterface) is { } method)
            return BindLambdaAsClosure(syntax, asInterface, method, span);

        diagnostics.Error("SL0382", span,
            $"a lambda becomes a delegate or an interface with exactly one method, " +
            $"and '{target.Name}' is neither");
        return new BoundErrorExpression(span);
    }

    /// <summary>The lone method of a functional interface, or null if it is not one.</summary>
    private static FunctionSymbol? SingleMethodOf(InterfaceTypeSymbol type) =>
        type.Methods.Count == 1 && type.Interfaces.Count == 0 ? type.Methods[0] : null;

    private BoundExpression BindLambdaAsClosure(
        LambdaSyntax syntax, InterfaceTypeSymbol target, FunctionSymbol method, SourceSpan span)
    {
        var wanted = method.Parameters.Where(p => !p.IsThis).ToList();
        if (!CheckLambdaArity(syntax, wanted.Count, target.Name, span)) return new BoundErrorExpression(span);

        var closureType = new ClassTypeSymbol
        {
            SimpleName = $"Closure.{_closureCount++}",
            ModuleName = _currentModule!.Name,
            Span = span,
        };
        closureType.Interfaces.Add(target);

        var symbol = new FunctionSymbol
        {
            Name = method.Name,
            ModuleName = closureType.ModuleName,
            ReturnType = method.ReturnType,
            Linkage = LinkageKind.Stainless,
            Kind = FunctionKind.Method,
            ContainingType = closureType,
            IsPublic = true,
            Span = syntax.Span,
            Scope = _currentScope,
        };

        var self = new ParameterSymbol("this", closureType, 0) { IsThis = true };
        symbol.Parameters.Add(self);
        AddLambdaParameters(symbol, syntax, wanted);

        closureType.Methods.Add(symbol);

        var context = new ClosureContext
        {
            Type = closureType,
            This = self,
            OuterScopes = [.. _scopes],
            OuterFunction = _currentFunction,
        };

        var body = BindLambdaBody(syntax, symbol, context);

        // The fields are known only now, so the layout waits for the body.
        ComputeLayout(closureType, []);
        _classes.Add(closureType);
        _functions.Add(new BoundFunction(symbol, body));

        return new BoundClosure(span, target, closureType, context.Captures);
    }

    private BoundExpression BindLambdaAsFunction(
        LambdaSyntax syntax, DelegateTypeSymbol target, SourceSpan span)
    {
        if (!CheckLambdaArity(syntax, target.Signature.Count, target.Name, span))
            return new BoundErrorExpression(span);

        var symbol = new FunctionSymbol
        {
            Name = $"Lambda.{_closureCount++}",
            ModuleName = _currentModule!.Name,
            ReturnType = target.ReturnType,
            Linkage = LinkageKind.Stainless,
            IsPublic = false,
            Span = syntax.Span,
            Scope = _currentScope,
        };

        AddLambdaParameters(symbol, syntax, target.Signature);

        var context = new ClosureContext
        {
            OuterScopes = [.. _scopes],
            OuterFunction = _currentFunction,
        };

        var body = BindLambdaBody(syntax, symbol, context);
        _functions.Add(new BoundFunction(symbol, body));

        return new BoundFunctionReference(span, target, symbol);
    }

    private bool CheckLambdaArity(LambdaSyntax syntax, int wanted, string target, SourceSpan span)
    {
        if (syntax.Parameters.Count == wanted) return true;

        diagnostics.Error("SL0383", span,
            $"'{target}' takes {wanted} argument{(wanted == 1 ? "" : "s")}, " +
            $"but this lambda declares {syntax.Parameters.Count}");
        return false;
    }

    /// <summary>
    /// Gives the generated function its parameters. A lambda may write their
    /// types or leave them out; left out, they come from the target, which is
    /// the only thing that knows them.
    /// </summary>
    private void AddLambdaParameters(
        FunctionSymbol symbol, LambdaSyntax syntax, IReadOnlyList<ParameterSymbol> wanted)
    {
        for (int i = 0; i < syntax.Parameters.Count && i < wanted.Count; i++)
        {
            var declared = syntax.Parameters[i];
            var type = wanted[i].Type;

            if (declared.Type is not null)
            {
                var written = ResolveType(declared.Type, _currentScope!);
                if (!written.IsError() && !written.Equals(type))
                    diagnostics.Error("SL0384", declared.Span,
                        $"parameter '{declared.Name}' is '{written.Name}', but the target " +
                        $"expects '{type.Name}'");
            }

            symbol.Parameters.Add(new ParameterSymbol(declared.Name, type, symbol.Parameters.Count));
        }
    }

    /// <summary>
    /// Binds the body against the generated function rather than the enclosing
    /// one. The scope chain is put aside rather than extended, so a name from
    /// outside is reached by capturing it and not by accident.
    /// </summary>
    private BoundBlock BindLambdaBody(
        LambdaSyntax syntax, FunctionSymbol symbol, ClosureContext context)
    {
        var savedScopes = new List<Dictionary<string, LocalSymbol>>(_scopes);
        var savedFunction = _currentFunction;
        int savedLoops = _loopDepth;
        int savedSwitches = _switchDepth;
        int savedParallel = _parallelDepth;

        _scopes.Clear();
        _currentFunction = symbol;
        _loopDepth = 0;
        _switchDepth = 0;
        _parallelDepth = 0;
        _closures.Add(context);

        PushScope();

        BoundBlock body;
        if (syntax.Block is not null)
        {
            body = BindBlock(syntax.Block);
        }
        else
        {
            // An expression body returns, unless the target returns nothing.
            var value = BindExpression(syntax.Expression!);
            BoundStatement statement = symbol.ReturnType.IsVoid()
                ? new BoundExpressionStatement(syntax.Expression!.Span, value)
                : new BoundReturn(syntax.Expression!.Span,
                    BindConversion(value, symbol.ReturnType, syntax.Expression!.Span));

            body = new BoundBlock(syntax.Span, [statement]);
        }

        PopScope();

        if (!symbol.ReturnType.IsVoid() && !AlwaysReturns(body))
            diagnostics.Error("SL0217", syntax.Span,
                $"not all paths through this lambda return a value of type '{symbol.ReturnType.Name}'");

        _closures.RemoveAt(_closures.Count - 1);
        _scopes.Clear();
        _scopes.AddRange(savedScopes);
        _currentFunction = savedFunction;
        _loopDepth = savedLoops;
        _switchDepth = savedSwitches;
        _parallelDepth = savedParallel;

        return body;
    }

    /// <summary>
    /// Binds a switch: one governing value, and sections whose labels are
    /// constants of its type.
    ///
    /// A reference-typed governor is spilled into a hidden local first. The
    /// comparisons span several basic blocks, and a local is owned storage the
    /// ordinary scope machinery releases on every path out — including a
    /// <c>return</c> from the middle of a section.
    /// </summary>
    private BoundStatement BindSwitch(SwitchSyntax syntax)
    {
        var value = BindExpression(syntax.Value);
        if (value.Type.IsError()) return new BoundBlock(syntax.Span, []);

        if (value.Type is VariantTypeSymbol variant)
            return BindVariantSwitch(syntax, value, variant);

        foreach (var binding in syntax.Sections.SelectMany(section => section.Bindings))
            diagnostics.Error("SL0438", binding.Span,
                $"'case {binding.Case} {binding.Name}' matches a variant's case and binds what " +
                $"it carries, and '{value.Type.Name}' is not a variant");

        bool onText = _builtins.IsString(value.Type);
        bool onOrdinal = value.Type is PrimitiveTypeSymbol { IsInteger: true } or EnumTypeSymbol
                         || value.Type.IsBool();

        if (!onText && !onOrdinal)
        {
            diagnostics.Error("SL0403", syntax.Value.Span,
                $"'{value.Type.Name}' cannot be switched on; a switch needs a value with " +
                "constant labels, so it takes an integer, 'char', 'bool', an enum or a String");
            return new BoundBlock(syntax.Span, []);
        }

        // The value is compared in one block and used in several, so a String
        // has to outlive the comparison chain. A local does that for free.
        BoundLocalDeclaration? spill = null;
        if (value.Type.NeedsArc())
        {
            var held = DeclareLocal(
                SyntheticName("switch"), value.Type, isConst: true, syntax.Value.Span);
            spill = new BoundLocalDeclaration(syntax.Value.Span, held, value);
            value = new BoundLocalAccess(syntax.Value.Span, held);
        }

        var sections = new List<BoundSwitchSection>();
        var seenOrdinals = new Dictionary<ulong, SourceSpan>();
        var seenText = new Dictionary<string, SourceSpan>(StringComparer.Ordinal);
        bool sawDefault = false;

        _switchDepth++;

        foreach (var section in syntax.Sections)
        {
            var labels = new List<BoundExpression>();

            foreach (var label in section.Labels)
            {
                var bound = BindConversion(BindExpression(label), value.Type, label.Span);
                if (bound.Type.IsError()) continue;

                if (onText)
                {
                    if (Underlying(bound) is not BoundStringLiteral text)
                    {
                        diagnostics.Error("SL0404", label.Span,
                            "a 'case' label must be a constant, and this is not a string literal");
                        continue;
                    }

                    if (!seenText.TryAdd(text.Value, label.Span))
                        diagnostics.Error("SL0405", label.Span,
                            $"this switch already has a case for \"{text.Value}\"");
                    else
                        labels.Add(text);

                    continue;
                }

                if (FoldSwitchLabel(bound) is not { } bits)
                {
                    diagnostics.Error("SL0404", label.Span,
                        $"a 'case' label must be a constant of type '{value.Type.Name}', " +
                        "and this is not one");
                    continue;
                }

                if (!seenOrdinals.TryAdd(bits, label.Span))
                    diagnostics.Error("SL0405", label.Span,
                        "this switch already has a case for that value");
                else
                    // The folded value, not the expression it was written as:
                    // `case -1:` is a negation, and an LLVM switch arm has to
                    // be a constant rather than an instruction.
                    labels.Add(new BoundLiteral(label.Span, value.Type, bits));
            }

            if (section.HasDefault)
            {
                if (sawDefault)
                    diagnostics.Error("SL0406", section.Span,
                        "this switch already has a 'default' section");
                sawDefault = true;
            }

            PushScope();
            var body = new BoundBlock(section.Span,
                section.Statements.Select(BindStatement).ToList());
            PopScope();

            // No fall-through, as in C#. A section that runs off its end is
            // almost always a forgotten 'break', and the reader of one that
            // meant it has no way to tell.
            if (!AlwaysExits(body))
                diagnostics.Error("SL0407", section.Span,
                    "a switch section must not run off its end; finish it with 'break', " +
                    "'return' or 'continue'. Stack the labels instead, as in " +
                    "'case 1: case 2:', when two values share a body");

            sections.Add(new BoundSwitchSection(
                section.Span, labels, section.HasDefault, body));
        }

        _switchDepth--;

        BoundStatement result = new BoundSwitch(syntax.Span, value, sections);
        return spill is null
            ? result
            : new BoundBlock(syntax.Span, [spill, result]);
    }

    /// <summary>
    /// A switch over a variant: one arm per case, and no default needed once
    /// they are all there.
    ///
    /// This is the other half of the proof that guards a payload. Inside an arm
    /// the switched value is known to be that case, so its fields are readable
    /// under their own names; and <c>case Circle c:</c> additionally copies the
    /// payload into a name of its own, for when the thing switched on was not a
    /// local to begin with and there is nothing for a narrowing to be about.
    /// </summary>
    private BoundStatement BindVariantSwitch(
        SwitchSyntax syntax, BoundExpression value, VariantTypeSymbol variant)
    {
        // Narrowing is about a name, so one is made when there is not one
        // already. It also gives the value somewhere to live for the length of
        // the switch, which a variant holding a reference needs anyway.
        BoundLocalDeclaration? spill = null;
        if (NarrowableSubject(value) is null)
        {
            var held = DeclareLocal(
                SyntheticName("switch"), variant, isConst: true, syntax.Value.Span);
            spill = new BoundLocalDeclaration(syntax.Value.Span, held, value);
            value = new BoundLocalAccess(syntax.Value.Span, held);
        }

        var subject = NarrowableSubject(value);
        var sections = new List<BoundSwitchSection>();
        var covered = new Dictionary<VariantCaseSymbol, SourceSpan>();
        bool sawDefault = false;

        _switchDepth++;

        foreach (var section in syntax.Sections)
        {
            var cases = new List<VariantCaseSymbol>();
            VariantCaseSymbol? bound = null;
            string boundName = "";
            var boundSpan = section.Span;

            // `case Circle:` parses as an expression, because at that point
            // nothing knows whether Circle is a case or a constant. Here it is
            // known, so a bare name that names a case is one.
            foreach (var label in section.Labels)
            {
                if (label is NameSyntax { Name.Parts: [var only] } &&
                    variant.FindCase(only) is { } named)
                {
                    if (!covered.TryAdd(named, label.Span))
                        diagnostics.Error("SL0405", label.Span,
                            $"this switch already has a case for '{named.Name}'");
                    else
                        cases.Add(named);

                    continue;
                }

                diagnostics.Error("SL0404", label.Span,
                    $"a 'case' label in a switch over '{variant.Name}' names one of its cases; " +
                    "they are " + Listed(variant.Cases.Select(c => c.Name)));
            }

            foreach (var declared in section.Bindings)
            {
                if (variant.FindCase(declared.Case) is not { } matched)
                {
                    diagnostics.Error("SL0435", declared.Span,
                        $"variant '{variant.Name}' has no case named '{declared.Case}'; it has " +
                        Listed(variant.Cases.Select(c => c.Name)));
                    continue;
                }

                if (!covered.TryAdd(matched, declared.Span))
                {
                    diagnostics.Error("SL0405", declared.Span,
                        $"this switch already has a case for '{matched.Name}'");
                    continue;
                }

                cases.Add(matched);

                if (matched.Payload is null)
                {
                    diagnostics.Error("SL0439", declared.Span,
                        $"case '{matched.Name}' carries nothing, so there is nothing for " +
                        $"'{declared.Name}' to be; write 'case {matched.Name}:'");
                    continue;
                }

                if (bound is not null || cases.Count > 1)
                {
                    diagnostics.Error("SL0440", declared.Span,
                        "only one case may be bound in a section, because each carries " +
                        "something different; give this case a section of its own");
                    continue;
                }

                bound = matched;
                boundName = declared.Name;
                boundSpan = declared.Span;
            }

            if (section.HasDefault)
            {
                if (sawDefault)
                    diagnostics.Error("SL0406", section.Span,
                        "this switch already has a 'default' section");
                sawDefault = true;
            }

            // Inside the arm, the value is that case. One case only: a section
            // reached by two of them has proved nothing about which.
            var saved = SnapshotFacts();
            if (subject is not null && cases.Count == 1) _variantFacts[subject] = cases[0];
            else if (subject is not null) _variantFacts.Remove(subject);

            PushScope();

            var statements = new List<BoundStatement>();
            LocalSymbol? binding = null;

            if (bound is not null)
            {
                binding = DeclareLocal(boundName, bound.Payload!, isConst: true, boundSpan);
                statements.Add(new BoundLocalDeclaration(boundSpan, binding,
                    new BoundVariantPayload(boundSpan, value, bound, null)));
            }

            statements.AddRange(section.Statements.Select(BindStatement));
            var body = new BoundBlock(section.Span, statements);

            PopScope();
            _variantFacts = saved;

            if (!AlwaysExits(body))
                diagnostics.Error("SL0407", section.Span,
                    "a switch section must not run off its end; finish it with 'break', " +
                    "'return' or 'continue'. Stack the labels instead, as in " +
                    "'case Circle: case Rect:', when two cases share a body");

            sections.Add(new BoundSwitchSection(section.Span, [], section.HasDefault, body)
            {
                Cases = cases,
                Binding = binding,
            });
        }

        _switchDepth--;

        var missing = variant.Uncovered(covered.Keys).ToList();

        if (missing.Count > 0 && !sawDefault)
            diagnostics.Error("SL0436", syntax.Span,
                $"this switch over '{variant.Name}' does not cover " +
                Listed(missing.Select(c => "'" + c.Name + "'")) +
                "; a variant is the choice between its cases, so a switch that leaves one out " +
                "has no answer for it. Add the case, or a 'default'");

        BoundStatement result = new BoundSwitch(syntax.Span, value, sections)
        {
            IsExhaustive = missing.Count == 0,
        };

        return spill is null ? result : new BoundBlock(syntax.Span, [spill, result]);
    }

    /// <summary>
    /// The raw bits of a constant switch label, or null when it is not one.
    /// Negative literals arrive as a negation of a positive one, which is why
    /// this looks through a unary minus rather than only at literals.
    /// </summary>
    private static ulong? FoldSwitchLabel(BoundExpression expression) => Underlying(expression) switch
    {
        BoundLiteral { Value: ulong bits } => bits,
        BoundLiteral { Value: bool flag } => flag ? 1UL : 0UL,
        BoundLiteral { Value: char character } => character,
        BoundUnary { Operator: BoundUnaryOp.Negate, Operand: var operand }
            when FoldSwitchLabel(operand) is { } magnitude => unchecked((ulong)-(long)magnitude),
        BoundConstantAccess { Constant.Value: ulong bits } => bits,
        BoundConstantAccess { Constant.Value: bool flag } => flag ? 1UL : 0UL,
        BoundConstantAccess { Constant.Value: char character } => character,
        _ => null,
    };

    /// <summary>
    /// Whether a statement always leaves the section it is in. Wider than
    /// <see cref="AlwaysReturns"/> by exactly <c>break</c> and <c>continue</c>,
    /// and it stops at a loop, whose own <c>break</c> lands after the loop
    /// rather than out of the section.
    /// </summary>
    private static bool AlwaysExits(BoundStatement statement) => statement switch
    {
        BoundBreak or BoundContinue => true,
        BoundBlock block => block.Statements.Any(AlwaysExits),
        BoundIf { Else: not null } branch => AlwaysExits(branch.Then) && AlwaysExits(branch.Else),
        _ => AlwaysReturns(statement),
    };

    private BoundStatement BindReturn(ReturnSyntax syntax)
    {
        if (_parallelDepth > 0)
        {
            diagnostics.Error("SL0374", syntax.Span,
                "'return' cannot leave a 'parallel' block; the join at its closing brace " +
                "would be skipped and the jobs left running against a dead frame");
            return new BoundReturn(syntax.Span, null);
        }

        var expected = _currentFunction?.ReturnType ?? PrimitiveTypeSymbol.Void;

        if (syntax.Value is null)
        {
            if (!expected.IsVoid())
                diagnostics.Error("SL0223", syntax.Span,
                    $"this function must return a value of type '{expected.Name}'");
            return new BoundReturn(syntax.Span, null);
        }

        var value = BindExpression(syntax.Value);
        if (expected.IsVoid())
        {
            diagnostics.Error("SL0224", syntax.Span,
                "this function returns 'void', so 'return' cannot take a value");
            return new BoundReturn(syntax.Span, null);
        }

        return new BoundReturn(syntax.Span, BindConversion(value, expected, syntax.Value.Span));
    }

    private BoundStatement BindBreak(BreakSyntax syntax)
    {
        if (_loopDepth == 0 && _switchDepth == 0)
            diagnostics.Error("SL0225", syntax.Span,
                "'break' is only valid inside a loop or a switch");
        return new BoundBreak(syntax.Span);
    }

    private BoundStatement BindContinue(ContinueSyntax syntax)
    {
        if (_loopDepth == 0)
            diagnostics.Error("SL0226", syntax.Span, "'continue' is only valid inside a loop");
        return new BoundContinue(syntax.Span);
    }

    private BoundExpression BindCondition(ExpressionSyntax syntax)
    {
        var condition = BindExpression(syntax);
        if (!condition.Type.IsBool() && !condition.Type.IsError())
            diagnostics.Error("SL0227", syntax.Span,
                $"a condition must be 'bool', but this is '{condition.Type.Name}'; " +
                "Stainless has no implicit conversion to 'bool'");
        return condition;
    }

    // ------------------------------------------------------------ expressions

    private BoundExpression BindExpression(ExpressionSyntax syntax) => syntax switch
    {
        LiteralSyntax literal => BindLiteral(literal),
        NameSyntax name => BindName(name),
        ThisSyntax thisExpression => BindThis(thisExpression),
        BaseSyntax baseExpression => BindBaseValue(baseExpression),
        TypeTestSyntax typeTest => BindTypeTest(typeTest),
        UnarySyntax unary => BindUnary(unary),
        BinarySyntax binary => BindBinary(binary),
        AssignmentSyntax assignment => BindAssignment(assignment),
        CallSyntax call => BindCall(call),
        MemberAccessSyntax member => BindMemberAccess(member),
        SliceSyntax slice => BindSlice(slice),
        IndexSyntax index => BindIndex(index),
        NewSyntax newExpression => BindNew(newExpression),
        NewArraySyntax newArray => BindNewArray(newArray),
        ConditionalSyntax conditional => BindConditional(conditional),
        LambdaSyntax lambda => new BoundLambda(lambda.Span, LambdaType.Instance, lambda),
        CastSyntax cast => BindCast(cast),
        SizeofSyntax sizeofExpression => BindSizeof(sizeofExpression),
        AlignofSyntax alignofExpression => BindAlignof(alignofExpression),
        OffsetofSyntax offsetofExpression => BindOffsetof(offsetofExpression),
        TypeofSyntax typeofExpression => BindTypeof(typeofExpression),
        _ => new BoundErrorExpression(syntax.Span),
    };

    private BoundExpression BindLiteral(LiteralSyntax syntax) => syntax.Kind switch
    {
        TokenKind.IntLiteral => new BoundLiteral(syntax.Span, PrimitiveTypeSymbol.Int, syntax.Value),
        TokenKind.FloatLiteral => new BoundLiteral(syntax.Span, PrimitiveTypeSymbol.Double, syntax.Value),
        TokenKind.CharLiteral => new BoundLiteral(syntax.Span, PrimitiveTypeSymbol.Char, syntax.Value),
        TokenKind.TrueKeyword or TokenKind.FalseKeyword =>
            new BoundLiteral(syntax.Span, PrimitiveTypeSymbol.Bool, syntax.Value),
        TokenKind.StringLiteral => new BoundStringLiteral(
            syntax.Span, _builtins.String, (string)syntax.Value!),
        TokenKind.NullKeyword => new BoundNullLiteral(syntax.Span, NullType.Instance),
        _ => new BoundErrorExpression(syntax.Span),
    };

    private BoundExpression BindThis(ThisSyntax syntax)
    {
        // Inside a lambda, `this` is the object the lambda was written in. The
        // generated closure also has a `this`, and letting the keyword mean
        // that one silently rebound the programmer's word to a type they never
        // wrote.
        if (_closures.Count > 0) return CaptureThis(_closures.Count - 1, syntax.Span);

        var parameter = _currentFunction?.Parameters.FirstOrDefault(p => p.IsThis);
        if (parameter is null)
        {
            diagnostics.Error("SL0228", syntax.Span,
                "'this' is only valid inside a method, constructor or destructor");
            return new BoundErrorExpression(syntax.Span);
        }
        return Receiver(syntax.Span, parameter);
    }

    /// <summary>
    /// The receiver expression for a method's implicit instance. A class method
    /// holds the reference directly; a struct method holds a pointer to the value,
    /// so it is dereferenced back into an lvalue here.
    /// </summary>
    private static BoundExpression Receiver(SourceSpan span, ParameterSymbol parameter)
    {
        var self = new BoundThis(span, parameter.Type, parameter);
        return parameter.Type is PointerTypeSymbol { Element: NamedTypeSymbol } pointer
            ? new BoundDereference(span, pointer.Element, self)
            : self;
    }

    /// <summary>
    /// <c>base</c> written where a value belongs. It never is one: it is this
    /// object seen as its base class, which only means anything when a member is
    /// being looked up on it.
    /// </summary>
    private BoundExpression BindBaseValue(BaseSyntax syntax)
    {
        diagnostics.Error("SL0515", syntax.Span,
            "'base' is not a value; it says where to look a member up, so it is only useful " +
            "as 'base.Member' or, at the head of a constructor, as 'base(...)'");
        return new BoundErrorExpression(syntax.Span);
    }

    /// <summary>
    /// <c>base</c> as the receiver of a member access: this object, typed as the
    /// class it derives from.
    ///
    /// The conversion emits nothing -- the base subobject starts where the
    /// object does -- so what it changes is only where the name is looked up,
    /// and that the call it feeds is not dispatched. Both are the point: an
    /// override reaching its base through the vtable would find itself.
    /// </summary>
    private BoundExpression? BindBaseReceiver(SourceSpan span)
    {
        if (_currentFunction?.ContainingType is not ClassTypeSymbol here)
        {
            diagnostics.Error("SL0515", span,
                "'base' is only valid inside a class method, constructor or destructor");
            return null;
        }

        if (here.BaseClass is not { } baseClass)
        {
            diagnostics.Error("SL0515", span,
                $"'{here.Name}' derives from nothing, so it has no 'base'");
            return null;
        }

        if (BindImplicitThis(span) is not { } self) return null;
        return new BoundConversion(span, baseClass, self, ConversionKind.Upcast);
    }

    /// <summary>
    /// <c>value is Type</c>: whether the object really is one of those.
    ///
    /// A test that could never be true is a mistake rather than a constant
    /// false, and one that must be true is a redundancy worth saying so about.
    /// </summary>
    private BoundExpression BindTypeTest(TypeTestSyntax syntax)
    {
        var value = BindExpression(syntax.Value);
        var tested = ResolveType(syntax.Tested, _currentScope!);
        if (value.Type.IsError() || tested.IsError()) return new BoundErrorExpression(syntax.Span);

        if (tested is not NamedTypeSymbol { IsReferenceType: true } wanted)
        {
            diagnostics.Error("SL0518", syntax.Span,
                $"'{tested.Name}' is not a class or an interface, so 'is' has nothing to ask: " +
                "every other type is known exactly where it is written");
            return new BoundErrorExpression(syntax.Span);
        }

        if (value.Type is WeakTypeSymbol)
        {
            diagnostics.Error("SL0518", syntax.Span,
                $"'{value.Type.Name}' may already have died, so what it is cannot be asked " +
                "directly; read it into a '" + wanted.Name + "?' first, which is the check " +
                "that makes it safe to look at");
            return new BoundErrorExpression(syntax.Span);
        }

        if (value.Type.AsReference() is not NamedTypeSymbol subject)
        {
            diagnostics.Error("SL0518", syntax.Span,
                $"'is' asks what an object really is, and '{value.Type.Name}' is not a reference " +
                "to one");
            return new BoundErrorExpression(syntax.Span);
        }

        // Two classes in different families: no object is ever both.
        if (subject is ClassTypeSymbol subjectClass && wanted is ClassTypeSymbol wantedClass)
        {
            if (!subjectClass.DerivesFrom(wantedClass) && !wantedClass.DerivesFrom(subjectClass))
            {
                diagnostics.Error("SL0518", syntax.Span,
                    $"no object is both a '{subjectClass.Name}' and a '{wantedClass.Name}': " +
                    "neither derives from the other");
                return new BoundErrorExpression(syntax.Span);
            }

            // Upwards, the answer is settled by the type -- except through an
            // optional, where it still says 'and not null'.
            if (subjectClass.DerivesFrom(wantedClass) && value.Type is not OptionalTypeSymbol)
                diagnostics.Warning("SL0520", syntax.Span,
                    $"every '{subjectClass.Name}' is a '{wantedClass.Name}', so this is always true");
        }

        return new BoundTypeTest(syntax.Span, PrimitiveTypeSymbol.Bool, value, wanted);
    }

    private BoundExpression BindName(NameSyntax syntax)
    {
        var parts = syntax.Name.Parts;

        if (parts.Count == 1)
        {
            string name = parts[0];

            if (LookupLocal(name) is { } local)
                return new BoundLocalAccess(syntax.Span, local);

            if (_currentFunction?.Parameters.FirstOrDefault(p => p.Name == name && !p.IsThis) is { } parameter)
                return new BoundParameterAccess(syntax.Span, parameter);

            // An unqualified member name inside a method means `this.member`.
            if (_currentFunction?.ContainingType?.FindProperty(name) is { } ownProperty)
            {
                var receiver = BindImplicitThis(syntax.Span);
                if (receiver is not null)
                    return BindPropertyRead(syntax.Span, receiver, ownProperty);
            }

            if (_currentFunction?.ContainingType?.FindField(name) is { } field)
            {
                if (!CanReach(field.IsPublic, field.IsProtected, field.ContainingType))
                {
                    diagnostics.Error("SL0249", syntax.Span,
                        NotVisible(field.ContainingType, name, field.IsProtected));
                    return new BoundErrorExpression(syntax.Span);
                }

                var receiver = BindImplicitThis(syntax.Span);
                if (receiver is not null) return new BoundFieldAccess(syntax.Span, receiver, field);
            }

            if (_currentModule!.Constants.TryGetValue(name, out var constant))
                return new BoundConstantAccess(syntax.Span, constant);

            if (_currentModule.Statics.TryGetValue(name, out var moduleStatic))
                return new BoundStaticAccess(syntax.Span, moduleStatic);

            foreach (var import in _currentScope!.Imports.Values.Distinct())
            {
                if (import.Constants.TryGetValue(name, out var imported) && imported.IsPublic)
                    return new BoundConstantAccess(syntax.Span, imported);

                if (import.Statics.TryGetValue(name, out var importedStatic) && importedStatic.IsPublic)
                    return new BoundStaticAccess(syntax.Span, importedStatic);
            }
        }

        // Not declared here, so a lambda body reaches outward and captures it.
        if (parts.Count == 1 && TryCapture(parts[0], syntax.Span) is { } captured)
            return captured;

        // A bare function name is a value only once it is known which delegate
        // it is becoming, so it stays a group until a conversion resolves it.
        var functions = ResolveFunctionCandidates(syntax.Name);
        if (functions.Count > 0)
            return new BoundFunctionGroup(
                syntax.Span, FunctionGroupType.Instance, syntax.Name.Text, functions);

        // A case that carries nothing is written without parentheses, so it
        // reaches here rather than through a call. Last, like every other bare
        // case name: a local, a parameter, a field and a function all win first.
        if (parts.Count == 1 && CouldBeVariantCase(parts[0]))
            return new BoundVariantDraft(syntax.Span, parts[0], []);

        diagnostics.Error("SL0229", syntax.Span, $"'{syntax.Name.Text}' is not defined");
        return new BoundErrorExpression(syntax.Span);
    }

    private BoundExpression? BindImplicitThis(SourceSpan span)
    {
        var parameter = _currentFunction?.Parameters.FirstOrDefault(p => p.IsThis);
        return parameter is null ? null : Receiver(span, parameter);
    }

    private BoundExpression BindUnary(UnarySyntax syntax)
    {
        // `&x` and `*p` are addressing, not arithmetic, so handle them first.
        if (syntax.Operator == TokenKind.Amp)
        {
            var target = BindExpression(syntax.Operand);
            if (!target.IsLValue && !target.Type.IsError())
            {
                diagnostics.Error("SL0230", syntax.Span, "cannot take the address of a temporary value");
                return new BoundErrorExpression(syntax.Span);
            }
            return new BoundAddressOf(syntax.Span, new PointerTypeSymbol(target.Type), target);
        }

        if (syntax.Operator == TokenKind.Star)
        {
            var target = BindExpression(syntax.Operand);
            if (target.Type is not PointerTypeSymbol pointer)
            {
                if (!target.Type.IsError())
                    diagnostics.Error("SL0231", syntax.Span,
                        $"cannot dereference '{target.Type.Name}'; only pointers can be dereferenced");
                return new BoundErrorExpression(syntax.Span);
            }
            return new BoundDereference(syntax.Span, pointer.Element, target);
        }

        var operand = BindExpression(syntax.Operand);
        if (operand.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        if (syntax.Operator == TokenKind.Plus)
            return operand;

        var (op, valid) = syntax.Operator switch
        {
            TokenKind.Minus => (BoundUnaryOp.Negate,
                operand.Type is PrimitiveTypeSymbol { IsNumeric: true }),
            TokenKind.Bang => (BoundUnaryOp.LogicalNot, operand.Type.IsBool()),
            TokenKind.Tilde => (BoundUnaryOp.BitwiseNot,
                operand.Type is PrimitiveTypeSymbol { IsInteger: true } || IsFlags(operand.Type)),
            _ => (BoundUnaryOp.Negate, false),
        };

        if (!valid)
        {
            diagnostics.Error("SL0232", syntax.Span,
                $"operator '{syntax.Operator.FixedText()}' cannot be applied to '{operand.Type.Name}'");
            return new BoundErrorExpression(syntax.Span);
        }

        // Small integers promote to int before arithmetic, as in C#.
        if (op is BoundUnaryOp.Negate or BoundUnaryOp.BitwiseNot)
            operand = PromoteToInt(operand);

        return new BoundUnary(syntax.Span, operand.Type, op, operand);
    }

    private BoundExpression BindBinary(BinarySyntax syntax)
    {
        var left = BindExpression(syntax.Left);
        var right = BindExpression(syntax.Right);
        if (left.Type.IsError() || right.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        var op = syntax.Operator switch
        {
            TokenKind.Plus => BoundBinaryOp.Add,
            TokenKind.Minus => BoundBinaryOp.Subtract,
            TokenKind.Star => BoundBinaryOp.Multiply,
            TokenKind.Slash => BoundBinaryOp.Divide,
            TokenKind.Percent => BoundBinaryOp.Remainder,
            TokenKind.Amp => BoundBinaryOp.BitAnd,
            TokenKind.Pipe => BoundBinaryOp.BitOr,
            TokenKind.Caret => BoundBinaryOp.BitXor,
            TokenKind.LessLess => BoundBinaryOp.ShiftLeft,
            TokenKind.GreaterGreater => BoundBinaryOp.ShiftRight,
            TokenKind.EqualsEquals => BoundBinaryOp.Equal,
            TokenKind.BangEquals => BoundBinaryOp.NotEqual,
            TokenKind.Less => BoundBinaryOp.Less,
            TokenKind.LessEquals => BoundBinaryOp.LessEqual,
            TokenKind.Greater => BoundBinaryOp.Greater,
            TokenKind.GreaterEquals => BoundBinaryOp.GreaterEqual,
            TokenKind.AmpAmp => BoundBinaryOp.LogicalAnd,
            _ => BoundBinaryOp.LogicalOr,
        };

        return BindBinaryOperation(syntax.Span, left, op, right, syntax.Operator);
    }

    private BoundExpression BindBinaryOperation(
        SourceSpan span, BoundExpression left, BoundBinaryOp op, BoundExpression right, TokenKind token)
    {
        // Logical operators: bool only, and they short-circuit.
        if (op is BoundBinaryOp.LogicalAnd or BoundBinaryOp.LogicalOr)
        {
            if (!left.Type.IsBool() || !right.Type.IsBool())
            {
                diagnostics.Error("SL0233", span,
                    $"operator '{token.FixedText()}' requires 'bool' operands, but got " +
                    $"'{left.Type.Name}' and '{right.Type.Name}'");
                return new BoundErrorExpression(span);
            }
            return new BoundBinary(span, PrimitiveTypeSymbol.Bool, left, op, right);
        }

        // Pointer arithmetic: p + i, p - i.
        if (left.Type is PointerTypeSymbol && op is BoundBinaryOp.Add or BoundBinaryOp.Subtract &&
            right.Type is PrimitiveTypeSymbol { IsInteger: true })
        {
            return new BoundBinary(span, left.Type, left, op, PromoteToInt(right));
        }

        // Strings compare by value and concatenate with '+'. Both lower to a
        // runtime call, so neither is a special case anywhere downstream.
        if (_builtins.IsString(left.Type) && _builtins.IsString(right.Type))
        {
            if (op == BoundBinaryOp.Add)
                return new BoundCall(span, _builtins.StringConcat, receiver: null, [left, right]);

            if (op is BoundBinaryOp.Equal or BoundBinaryOp.NotEqual)
            {
                var comparison = new BoundCall(
                    span, _builtins.StringEquals, receiver: null, [left, right]);

                return op == BoundBinaryOp.Equal
                    ? comparison
                    : new BoundUnary(span, PrimitiveTypeSymbol.Bool, BoundUnaryOp.LogicalNot, comparison);
            }

            diagnostics.Error("SL0291", span,
                $"operator '{token.FixedText()}' cannot be applied to strings");
            return new BoundErrorExpression(span);
        }

        if (_builtins.IsString(left.Type) != _builtins.IsString(right.Type))
        {
            var other = _builtins.IsString(left.Type) ? right.Type : left.Type;
            diagnostics.Error("SL0292", span,
                $"cannot apply '{token.FixedText()}' to 'String' and '{other.Name}'; " +
                "convert it first, for example with Standard.Text.FromInteger");
            return new BoundErrorExpression(span);
        }

        // Enums compare with each other and with nothing else. Comparison is
        // allowed as well as equality, because an ordered enum -- a severity, a
        // log level -- is the common case and `level >= Level.Warning` is what
        // people write. Arithmetic is not: adding two colours means nothing.
        if (left.Type is EnumTypeSymbol || right.Type is EnumTypeSymbol)
        {
            bool comparison = op is BoundBinaryOp.Equal or BoundBinaryOp.NotEqual
                or BoundBinaryOp.Less or BoundBinaryOp.LessEqual
                or BoundBinaryOp.Greater or BoundBinaryOp.GreaterEqual;

            bool bitwise = op is BoundBinaryOp.BitAnd or BoundBinaryOp.BitOr or BoundBinaryOp.BitXor;

            if (!left.Type.Equals(right.Type))
            {
                diagnostics.Error("SL0353", span,
                    $"'{left.Type.Name}' and '{right.Type.Name}' are different types and do not " +
                    "compare; an enum converts only through an explicit cast");
                return new BoundErrorExpression(span);
            }

            // A set of bits combines; a choice among alternatives does not. The
            // attribute is what says which one this enum is.
            if (bitwise && IsFlags(left.Type))
                return new BoundBinary(span, left.Type, left, op, right);

            if (!comparison)
            {
                diagnostics.Error("SL0354", span,
                    $"operator '{token.FixedText()}' cannot be applied to '{left.Type.Name}'; " +
                    (bitwise
                        ? $"'{left.Type.Name}' is a choice among alternatives, not a set of bits. " +
                          "Mark it '[Flags]' if its members are meant to combine"
                        : "an enum supports comparison, not arithmetic"));
                return new BoundErrorExpression(span);
            }

            return new BoundBinary(span, PrimitiveTypeSymbol.Bool, left, op, right);
        }

        // Reference and pointer equality.
        if (op is BoundBinaryOp.Equal or BoundBinaryOp.NotEqual &&
            IsReferenceLike(left.Type) && IsReferenceLike(right.Type))
        {
            var (comparableLeft, comparableRight) = UnifyReferences(left, right, span);
            return new BoundBinary(span, PrimitiveTypeSymbol.Bool, comparableLeft, op, comparableRight);
        }

        if (left.Type is not PrimitiveTypeSymbol leftPrimitive ||
            right.Type is not PrimitiveTypeSymbol rightPrimitive)
        {
            diagnostics.Error("SL0234", span,
                $"operator '{token.FixedText()}' cannot be applied to '{left.Type.Name}' and '{right.Type.Name}'");
            return new BoundErrorExpression(span);
        }

        // A divisor that is zero at compile time is always a mistake, and there
        // is no reason to make the program run before saying so. A divisor that
        // is only zero sometimes is guarded in the emitted code instead.
        if (op is BoundBinaryOp.Divide or BoundBinaryOp.Remainder &&
            leftPrimitive.IsInteger && rightPrimitive.IsInteger &&
            FoldSwitchLabel(right) is 0)
        {
            diagnostics.Error("SL0415", span,
                op == BoundBinaryOp.Divide
                    ? "division by zero"
                    : "the remainder of a division by zero");

            // Carry on with a value of the type this would have had, so the
            // expression around it reports nothing further: one mistake should
            // produce one message. It is wrapped rather than left a bare
            // literal, because a literal would take part in overload resolution
            // as a literal does and could be ambiguous where the division was not.
            var recovered = PromoteToInt(left).Type;
            return new BoundConversion(span, recovered,
                new BoundLiteral(span, recovered, 0UL), ConversionKind.Identity);
        }

        // Shifts keep the left type; only the left operand promotes.
        if (op is BoundBinaryOp.ShiftLeft or BoundBinaryOp.ShiftRight)
        {
            if (!leftPrimitive.IsInteger || !rightPrimitive.IsInteger)
            {
                diagnostics.Error("SL0235", span, "shift operators require integer operands");
                return new BoundErrorExpression(span);
            }
            // The result is the left operand's type, and the count is brought to
            // that same type. LLVM requires both operands of a shift to match,
            // so a count of a different width produced invalid IR; narrowing it
            // loses nothing, because the emitter reduces it modulo the width.
            var shifted = PromoteToInt(left);
            var count = PromoteToInt(right);

            if (!count.Type.Equals(shifted.Type))
                count = new BoundConversion(span, shifted.Type, count,
                    count.Type.Size < shifted.Type.Size
                        ? ConversionKind.IntegerWiden
                        : ConversionKind.IntegerNarrow);

            return new BoundBinary(span, shifted.Type, shifted, op, count);
        }

        bool isComparison = op is BoundBinaryOp.Equal or BoundBinaryOp.NotEqual
            or BoundBinaryOp.Less or BoundBinaryOp.LessEqual
            or BoundBinaryOp.Greater or BoundBinaryOp.GreaterEqual;

        if (leftPrimitive.Kind == PrimitiveKind.Bool && rightPrimitive.Kind == PrimitiveKind.Bool)
        {
            if (op is BoundBinaryOp.Equal or BoundBinaryOp.NotEqual
                or BoundBinaryOp.BitAnd or BoundBinaryOp.BitOr or BoundBinaryOp.BitXor)
                return new BoundBinary(span, isComparison ? PrimitiveTypeSymbol.Bool : PrimitiveTypeSymbol.Bool,
                    left, op, right);

            diagnostics.Error("SL0236", span,
                $"operator '{token.FixedText()}' cannot be applied to 'bool' operands");
            return new BoundErrorExpression(span);
        }

        if (!leftPrimitive.IsNumeric || !rightPrimitive.IsNumeric)
        {
            diagnostics.Error("SL0237", span,
                $"operator '{token.FixedText()}' cannot be applied to '{left.Type.Name}' and '{right.Type.Name}'");
            return new BoundErrorExpression(span);
        }

        if (!TryFindCommonType(leftPrimitive, rightPrimitive, out var common))
        {
            diagnostics.Error("SL0238", span,
                $"'{left.Type.Name}' and '{right.Type.Name}' have no common type; " +
                "add an explicit cast to choose one");
            return new BoundErrorExpression(span);
        }

        // Bitwise operators need integers, not floats.
        if (op is BoundBinaryOp.BitAnd or BoundBinaryOp.BitOr or BoundBinaryOp.BitXor or BoundBinaryOp.Remainder
            && common.IsFloat && op != BoundBinaryOp.Remainder)
        {
            diagnostics.Error("SL0239", span,
                $"operator '{token.FixedText()}' requires integer operands");
            return new BoundErrorExpression(span);
        }

        left = BindConversion(left, common, span);
        right = BindConversion(right, common, span);
        return new BoundBinary(span, isComparison ? PrimitiveTypeSymbol.Bool : common, left, op, right);
    }

    private static bool IsReferenceLike(TypeSymbol type) =>
        type is PointerTypeSymbol or ClassTypeSymbol or InterfaceTypeSymbol
            or OptionalTypeSymbol or WeakTypeSymbol or NullType or DelegateTypeSymbol;

    private (BoundExpression, BoundExpression) UnifyReferences(
        BoundExpression left, BoundExpression right, SourceSpan span)
    {
        if (left.Type is NullType) left = new BoundNullLiteral(span, right.Type);
        if (right.Type is NullType) right = new BoundNullLiteral(span, left.Type);
        return (left, right);
    }

    /// <summary>Integer promotion: anything narrower than <c>int</c> widens to <c>int</c>.</summary>
    private BoundExpression PromoteToInt(BoundExpression expression)
    {
        if (expression.Type is PrimitiveTypeSymbol { IsInteger: true, Size: < 4 })
            return new BoundConversion(
                expression.Span, PrimitiveTypeSymbol.Int, expression, ConversionKind.IntegerWiden);
        return expression;
    }

    private static bool TryFindCommonType(
        PrimitiveTypeSymbol left, PrimitiveTypeSymbol right, out PrimitiveTypeSymbol common)
    {
        common = PrimitiveTypeSymbol.Int;

        if (left.IsFloat || right.IsFloat)
        {
            common = left.Kind == PrimitiveKind.Double || right.Kind == PrimitiveKind.Double
                ? PrimitiveTypeSymbol.Double
                : PrimitiveTypeSymbol.Float;
            return true;
        }

        // Promote to at least int, then to whichever side is wider.
        var wider = left.Size >= right.Size ? left : right;
        if (wider.Size < 4) { common = PrimitiveTypeSymbol.Int; return true; }

        if (left.Size == right.Size && left.IsSigned != right.IsSigned)
        {
            // Same width, different signedness: only widening to a bigger signed type is safe.
            if (left.Size >= 8) return false;
            common = PrimitiveTypeSymbol.Long;
            return true;
        }

        common = wider;
        return true;
    }

    /// <summary>
    /// <c>a ? b : c</c>. The arms must meet at one type: the same type, a common
    /// numeric type, or one that the other converts to implicitly.
    /// </summary>
    private BoundExpression BindConditional(ConditionalSyntax syntax)
    {
        var condition = BindCondition(syntax.Condition);

        // Each arm runs only when the condition chose it, so each is bound
        // knowing what that choice proved. `r.Ok ? r.Value : Describe(r.Error)`
        // is the shape this exists for.
        var (proves, disproves) = ConditionFacts(condition);
        var entry = SnapshotFacts();

        ApplyFacts(proves);
        var whenTrue = BindExpression(syntax.WhenTrue);

        _variantFacts = new Dictionary<object, VariantCaseSymbol>(entry);
        ApplyFacts(disproves);
        var whenFalse = BindExpression(syntax.WhenFalse);

        _variantFacts = entry;

        if (whenTrue.Type.IsError() || whenFalse.Type.IsError())
            return new BoundErrorExpression(syntax.Span);

        if (whenTrue.Type.IsVoid() || whenFalse.Type.IsVoid())
        {
            diagnostics.Error("SL0348", syntax.Span,
                "a conditional expression must produce a value, but an arm is 'void'");
            return new BoundErrorExpression(syntax.Span);
        }

        var type = CommonArmType(whenTrue, whenFalse);
        if (type is null)
        {
            diagnostics.Error("SL0349", syntax.Span,
                $"the arms of a conditional have no common type: one is " +
                $"'{whenTrue.Type.Name}', the other '{whenFalse.Type.Name}'");
            return new BoundErrorExpression(syntax.Span);
        }

        return new BoundConditional(
            syntax.Span, type,
            condition,
            BindConversion(whenTrue, type, syntax.WhenTrue.Span),
            BindConversion(whenFalse, type, syntax.WhenFalse.Span));
    }

    /// <summary>The type both arms of a conditional reach, or null if they do not.</summary>
    private TypeSymbol? CommonArmType(BoundExpression left, BoundExpression right)
    {
        if (left.Type.Equals(right.Type)) return left.Type;

        // `flag ? obj : null` is an optional, which is what the null was reaching for.
        if (left is BoundNullLiteral && right.Type.IsReferenceType) return new OptionalTypeSymbol(right.Type);
        if (right is BoundNullLiteral && left.Type.IsReferenceType) return new OptionalTypeSymbol(left.Type);

        if (left.Type is PrimitiveTypeSymbol { IsNumeric: true } leftNumber &&
            right.Type is PrimitiveTypeSymbol { IsNumeric: true } rightNumber &&
            TryFindCommonType(leftNumber, rightNumber, out var common))
            return common;

        // Otherwise one arm must already be assignable to the other, which is
        // what covers C -> C?, C -> I and an integer literal adopting a width.
        if (IsImplicitlyConvertible(right, left.Type)) return left.Type;
        if (IsImplicitlyConvertible(left, right.Type)) return right.Type;

        return null;
    }

    private BoundExpression BindAssignment(AssignmentSyntax syntax)
    {
        var target = BindExpression(syntax.Target);

        // The target was bound as a read, which is what proves it is a property
        // and, usefully, has already bound the receiver exactly once.
        if (target is BoundCall { Function.Accessor: { } property } read)
            return BindPropertyAssignment(syntax, read, property);

        var value = BindExpression(syntax.Value);

        if (target.Type.IsError() || value.Type.IsError())
            return new BoundErrorExpression(syntax.Span);

        if (BaseOf(target) is BoundStaticAccess owner)
        {
            diagnostics.Error("SL0379", syntax.Target.Span,
                $"'{owner.Static.Name}' is a static, and every static is readonly; " +
                "the value it holds is shared by every thread, so nothing may write it " +
                "after it is initialized");
            return new BoundErrorExpression(syntax.Span);
        }

        // An `in` parameter is the caller's storage, and the promise not to
        // write it is the only thing separating it from a `ref`. Reaching a
        // field of one is the same write one level down, so the base is what is
        // asked rather than the target itself.
        if (BaseOf(target) is BoundParameterAccess { Parameter.Mode: ParameterMode.In } borrowed)
        {
            diagnostics.Error("SL0448", syntax.Target.Span,
                $"'{borrowed.Parameter.Name}' is an 'in' parameter, which is the caller's " +
                "storage and promises not to be written; take it as 'ref' if it should be, or " +
                "copy it into a local first");
            return new BoundErrorExpression(syntax.Span);
        }

        if (!target.IsLValue)
        {
            diagnostics.Error("SL0240", syntax.Target.Span,
                target is BoundLocalAccess { Local.IsConst: true } constant
                    ? $"'{constant.Local.Name}' is declared 'const' and cannot be assigned"
                    : "the left-hand side of an assignment must be a variable, field or dereference");
            return new BoundErrorExpression(syntax.Span);
        }

        // Compound assignment desugars to `target = target op value`.
        if (syntax.Operator != TokenKind.Equals)
        {
            var (op, token) = CompoundOperator(syntax.Operator);
            value = BindBinaryOperation(syntax.Span, target, op, value, token);
            if (value.Type.IsError()) return new BoundErrorExpression(syntax.Span);
        }

        // Whatever was proved about this Result was proved about the value it
        // held a moment ago.
        InvalidateVariantFact(target);

        // Writing into a parameter's own storage makes it owned; see
        // ParameterSymbol.IsAssigned.
        if (WrittenParameter(target) is { } written) written.IsAssigned = true;

        return new BoundAssignment(syntax.Span, target, BindConversion(value, target.Type, syntax.Value.Span));
    }

    /// <summary>The operation behind a compound assignment, and the token to blame.</summary>
    private static (BoundBinaryOp Op, TokenKind Token) CompoundOperator(TokenKind kind) => kind switch
    {
        TokenKind.PlusEquals => (BoundBinaryOp.Add, TokenKind.Plus),
        TokenKind.MinusEquals => (BoundBinaryOp.Subtract, TokenKind.Minus),
        TokenKind.StarEquals => (BoundBinaryOp.Multiply, TokenKind.Star),
        TokenKind.SlashEquals => (BoundBinaryOp.Divide, TokenKind.Slash),
        TokenKind.PercentEquals => (BoundBinaryOp.Remainder, TokenKind.Percent),
        TokenKind.AmpEquals => (BoundBinaryOp.BitAnd, TokenKind.Amp),
        TokenKind.PipeEquals => (BoundBinaryOp.BitOr, TokenKind.Pipe),
        TokenKind.CaretEquals => (BoundBinaryOp.BitXor, TokenKind.Caret),
        TokenKind.LessLessEquals => (BoundBinaryOp.ShiftLeft, TokenKind.LessLess),
        _ => (BoundBinaryOp.ShiftRight, TokenKind.GreaterGreater),
    };

    /// <summary>
    /// Reads a property: a call to its getter, and nothing more. Everything
    /// downstream — ARC, interface dispatch, the calling convention — then sees
    /// an ordinary call and needs to know nothing about properties.
    /// </summary>
    private BoundExpression BindPropertyRead(
        SourceSpan span, BoundExpression receiver, PropertySymbol property)
    {
        if (property.Getter is not { } getter) return new BoundErrorExpression(span);

        if (!CanReach(getter.IsPublic, getter.IsProtected, property.ContainingType))
        {
            diagnostics.Error("SL0249", span,
                NotVisible(property.ContainingType, property.Name, getter.IsProtected));
            return new BoundErrorExpression(span);
        }

        // A struct accessor takes its receiver by pointer, exactly as a struct
        // method does.
        if (property.ContainingType is StructTypeSymbol structType)
            receiver = new BoundAddressOf(span, new PointerTypeSymbol(structType), receiver);

        return new BoundCall(span, getter, receiver, []);
    }

    /// <summary>
    /// Writes a property. The setter is an ordinary method, so this is a call;
    /// the node exists only so the assignment can still yield the value it
    /// stored, which a setter's own <c>void</c> return cannot.
    /// </summary>
    private BoundExpression BindPropertyAssignment(
        AssignmentSyntax syntax, BoundCall read, PropertySymbol property)
    {
        var receiver = read.Receiver!;

        // A struct's setter writes into the receiver's own storage, so this is
        // a write to the parameter exactly as `p.field = x` is.
        if (WrittenParameter(receiver) is { } mutated) mutated.IsAssigned = true;

        InvalidateVariantFact(receiver);

        var value = BindExpression(syntax.Value);
        if (value.Type.IsError() || property.Type.IsError())
            return new BoundErrorExpression(syntax.Span);

        if (property.Setter is not { } setter)
        {
            // A get-only automatic property is still storage, and the type's own
            // constructor is where storage gets filled in.
            if (property.BackingField is { } backing && syntax.Operator == TokenKind.Equals &&
                _currentFunction is { Kind: FunctionKind.Constructor } ctor &&
                ctor.ContainingType == property.ContainingType)
            {
                var storage = new BoundFieldAccess(syntax.Target.Span, receiver, backing);
                return new BoundAssignment(syntax.Span, storage,
                    BindConversion(value, property.Type, syntax.Value.Span));
            }

            diagnostics.Error("SL0395", syntax.Target.Span,
                $"'{property.ContainingType.Name}.{property.Name}' has no setter" +
                (property.ContainingType is InterfaceTypeSymbol
                    ? ", so the contract does not offer one; declare it 'get; set;'"
                    : property.BackingField is null
                        ? "; it is computed, so there is nothing to write"
                        : "; add 'set;', or assign it in a constructor of " +
                          $"'{property.ContainingType.Name}'"));
            return new BoundErrorExpression(syntax.Span);
        }

        if (!CanReach(setter.IsPublic, setter.IsProtected, property.ContainingType))
        {
            diagnostics.Error("SL0396", syntax.Target.Span,
                setter.IsProtected
                    ? $"'{property.ContainingType.Name}.{property.Name}' can be read from " +
                      $"anywhere but written only by '{property.ContainingType.Name}' and " +
                      "classes deriving from it"
                    : $"'{property.ContainingType.Name}.{property.Name}' can be read from " +
                      "anywhere but only written inside its own module");
            return new BoundErrorExpression(syntax.Span);
        }

        // A struct's setter writes the receiver's own storage, so a static one is
        // the very case SL0379 exists for. A class's setter writes the object
        // rather than the static, which the sendability rules already govern.
        if (property.ContainingType is StructTypeSymbol &&
            BaseOf(receiver) is BoundStaticAccess owner)
        {
            diagnostics.Error("SL0379", syntax.Target.Span,
                $"'{owner.Static.Name}' is a static, and every static is readonly; " +
                "the value it holds is shared by every thread, so nothing may write it " +
                "after it is initialized");
            return new BoundErrorExpression(syntax.Span);
        }

        // A struct's setter writes through a pointer, so a temporary receiver
        // would be written and then thrown away.
        if (property.ContainingType is StructTypeSymbol &&
            receiver is BoundAddressOf { Operand: var target } && !IsRepeatable(target))
        {
            diagnostics.Error("SL0399", syntax.Target.Span,
                $"'{property.ContainingType.Name}.{property.Name}' is being set on a temporary " +
                "struct, so the write would be discarded; assign to a variable first");
            return new BoundErrorExpression(syntax.Span);
        }

        if (syntax.Operator != TokenKind.Equals)
        {
            // `p.X += 1` reads through the getter and writes through the setter,
            // so the receiver is evaluated twice. Requiring it to be a plain load
            // is what makes that harmless.
            if (!IsRepeatable(receiver))
            {
                diagnostics.Error("SL0397", syntax.Target.Span,
                    $"'{property.ContainingType.Name}.{property.Name}' is a property, so this " +
                    "would call the getter and the setter on separately evaluated receivers; " +
                    "put the receiver in a variable first");
                return new BoundErrorExpression(syntax.Span);
            }

            var (op, token) = CompoundOperator(syntax.Operator);
            value = BindBinaryOperation(syntax.Span, read, op, value, token);
            if (value.Type.IsError()) return new BoundErrorExpression(syntax.Span);
        }

        return new BoundPropertyAssignment(syntax.Span, receiver, property,
            BindConversion(value, property.Type, syntax.Value.Span));
    }

    /// <summary>
    /// True when evaluating this expression again has no consequences: it reads
    /// storage or computes from constants, rather than doing anything.
    ///
    /// A call is deliberately absent, which is what makes this useful: it is
    /// exactly the question a lowering has to ask before naming its operand
    /// twice.
    /// </summary>
    private static bool IsRepeatable(BoundExpression expression) => expression switch
    {
        BoundLiteral or BoundStringLiteral or BoundNullLiteral or BoundConstantAccess => true,
        BoundLocalAccess or BoundParameterAccess or BoundThis or BoundStaticAccess => true,
        BoundFieldAccess field => field.Receiver is null || IsRepeatable(field.Receiver),
        BoundDereference dereference => IsRepeatable(dereference.Operand),
        BoundAddressOf address => IsRepeatable(address.Operand),
        BoundConversion conversion => IsRepeatable(conversion.Operand),
        BoundUnary unary => IsRepeatable(unary.Operand),
        BoundBinary binary => IsRepeatable(binary.Left) && IsRepeatable(binary.Right),
        _ => false,
    };

    private BoundExpression BindIndex(IndexSyntax syntax)
    {
        var target = BindExpression(syntax.Target);
        var index = BindExpression(syntax.Index);

        if (target.Type.IsError() || index.Type.IsError())
            return new BoundErrorExpression(syntax.Span);

        if (target.Type is not (PointerTypeSymbol or ArrayTypeSymbol or SliceTypeSymbol
                                or FixedArrayTypeSymbol))
        {
            diagnostics.Error("SL0241", syntax.Span,
                $"cannot index '{target.Type.Name}'; only arrays, slices and pointers support " +
                "indexing");
            return new BoundErrorExpression(syntax.Span);
        }

        if (index.Type is not PrimitiveTypeSymbol { IsInteger: true })
        {
            diagnostics.Error("SL0242", syntax.Index.Span,
                $"an index must be an integer, but this is '{index.Type.Name}'");
            return new BoundErrorExpression(syntax.Span);
        }

        // Any integer indexes an array, as in C#. A negative one sign-extends to
        // a very large unsigned value, so the single unsigned bounds compare in
        // the emitter catches it without a second check.
        // An inline array's length is part of its type, so a constant index can
        // be answered now rather than at run time. That is strictly better than
        // what `T[]` can do, and it is the whole reason the length is in the
        // type: the check is free and the failure is a compile error.
        if (target.Type is FixedArrayTypeSymbol inline)
        {
            if (FoldSwitchLabel(index) is { } constant &&
                constant <= long.MaxValue && (long)constant >= inline.Length)
            {
                diagnostics.Error("SL0490", syntax.Index.Span,
                    $"index {constant} is past the end of '{inline.Name}', which has " +
                    $"{Counted(inline.Length, "element")}");
                return new BoundErrorExpression(syntax.Span);
            }

            return new BoundIndex(syntax.Span, inline.Element, target, PromoteToInt(index));
        }

        if (target.Type is ArrayTypeSymbol array)
            return new BoundIndex(syntax.Span, array.Element, target, PromoteToInt(index));

        if (target.Type is SliceTypeSymbol slice)
            return new BoundIndex(syntax.Span, slice.Element, target, PromoteToInt(index));

        var pointer = (PointerTypeSymbol)target.Type;
        return new BoundIndex(syntax.Span, pointer.Element, target, PromoteToInt(index));
    }

    /// <summary>
    /// <c>a[from:to]</c> over an array or another slice.
    ///
    /// Slicing a slice narrows it rather than nesting: the result names the same
    /// array, further in. So there is one indirection however many times a slice
    /// has been cut, and the array underneath is kept alive by whichever slices
    /// still name it.
    /// </summary>
    private BoundExpression BindSlice(SliceSyntax syntax)
    {
        var target = BindExpression(syntax.Target);
        if (target.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        var element = target.Type switch
        {
            ArrayTypeSymbol array => array.Element,
            SliceTypeSymbol slice => slice.Element,
            _ => null,
        };

        if (element is null)
        {
            diagnostics.Error("SL0452", syntax.Span,
                $"cannot slice '{target.Type.Name}'; slicing takes part of an array or of " +
                "another slice");
            return new BoundErrorExpression(syntax.Span);
        }

        var start = BindBound(syntax.Start);
        var end = BindBound(syntax.End);

        if (start?.Type.IsError() == true || end?.Type.IsError() == true)
            return new BoundErrorExpression(syntax.Span);

        return new BoundSlice(syntax.Span, SliceOf(element), target, start, end);
    }

    /// <summary>One end of a slice, or null where the source left it out.</summary>
    private BoundExpression? BindBound(ExpressionSyntax? syntax)
    {
        if (syntax is null) return null;

        var bound = BindExpression(syntax);
        if (bound.Type.IsError()) return bound;

        if (bound.Type is not PrimitiveTypeSymbol { IsInteger: true })
        {
            diagnostics.Error("SL0242", syntax.Span,
                $"a slice bound must be an integer, but this is '{bound.Type.Name}'");
            return new BoundErrorExpression(syntax.Span);
        }

        return BindConversion(bound, PrimitiveTypeSymbol.NUInt, syntax.Span);
    }

    /// <summary>
    /// <c>T[N]</c>. The length has to be known now, because it is part of the
    /// type and the type decides a layout -- so it is a literal or a constant
    /// and nothing else.
    /// </summary>
    private TypeSymbol ResolveFixedArray(FixedArrayTypeSyntax syntax, FileScope scope)
    {
        var element = ResolveType(syntax.Element, scope);
        if (element.IsError()) return element;

        if (element.IsVoid())
        {
            diagnostics.Error("SL0485", syntax.Span, "there is no array of 'void'");
            return ErrorTypeSymbol.Instance;
        }

        // A counted reference in an inline array would have to be retained
        // element by element on every copy of whatever holds it. That is the
        // same question a union cannot answer, and the answer here is the same
        // one for now: plain data.
        if (element.CarriesReferences())
        {
            diagnostics.Error("SL0486", syntax.Span,
                $"an inline array cannot hold '{element.Name}', because it holds a " +
                "counted reference and every copy of the array would have to retain " +
                $"each element. Use '{element.Name}[]', which is one counted object " +
                "rather than N of them");
            return ErrorTypeSymbol.Instance;
        }

        if (ConstantLength(syntax.Length, scope) is not { } length)
        {
            diagnostics.Error("SL0487", syntax.Length.Span,
                "the length of an inline array must be a constant, because it is " +
                "part of the type: an integer literal, or a 'const' holding one");
            return ErrorTypeSymbol.Instance;
        }

        if (length <= 0)
        {
            diagnostics.Error("SL0488", syntax.Length.Span,
                $"an inline array needs at least one element, and this asks for {length}");
            return ErrorTypeSymbol.Instance;
        }

        // The product has to stay addressable. This is far past any real struct
        // and exists so that a typo produces a diagnostic rather than a
        // nonsensical size.
        long bytes = (long)element.Size * length;
        if (bytes > int.MaxValue)
        {
            diagnostics.Error("SL0489", syntax.Length.Span,
                $"'{element.Name}[{length}]' would be {bytes} bytes, which is more " +
                "than a value can be");
            return ErrorTypeSymbol.Instance;
        }

        return new FixedArrayTypeSymbol(element, (int)length);
    }

    /// <summary>
    /// The value of an inline array's length: an integer literal, or a name that
    /// reaches a constant holding one.
    /// </summary>
    private long? ConstantLength(ExpressionSyntax syntax, FileScope scope)
    {
        switch (syntax)
        {
            case LiteralSyntax { Kind: TokenKind.IntLiteral, Value: ulong number }:
                return number > long.MaxValue ? null : (long)number;

            case NameSyntax name when name.Name.Parts.Count == 1:
                return LookUpConstant(scope.Module, name.Name.Parts[0], scope);

            case MemberAccessSyntax { Target: NameSyntax target } member
                when target.Name.Parts.Count == 1 &&
                     scope.Imports.TryGetValue(target.Name.Parts[0], out var imported):
                return LookUpConstant(imported, member.Member, scope, requirePublic: true);

            default:
                return null;
        }
    }

    private long? LookUpConstant(
        ModuleSymbol module, string name, FileScope scope, bool requirePublic = false)
    {
        if (!module.Constants.TryGetValue(name, out var constant))
        {
            foreach (var imported in scope.Imports.Values)
                if (imported.Constants.TryGetValue(name, out var candidate) && candidate.IsPublic)
                {
                    constant = candidate;
                    break;
                }

            if (constant is null) return null;
        }
        else if (requirePublic && !constant.IsPublic)
        {
            return null;
        }

        return constant.Value is ulong number && number <= long.MaxValue ? (long)number : null;
    }

    private BoundExpression BindSizeof(SizeofSyntax syntax)
    {
        var measured = ResolveType(syntax.Type, _currentScope!);
        return new BoundSizeof(syntax.Span, PrimitiveTypeSymbol.NUInt, measured);
    }

    private BoundExpression BindAlignof(AlignofSyntax syntax)
    {
        var measured = ResolveType(syntax.Type, _currentScope!);
        return new BoundAlignof(syntax.Span, PrimitiveTypeSymbol.NUInt, measured);
    }

    /// <summary>
    /// <c>offsetof(T, Field)</c>, which is C's, and answers the same number for
    /// a struct. For a class it counts from the start of the allocation, so the
    /// result is what to add to the reference you hold -- a class reference
    /// points at the object header, and the fields follow it.
    /// </summary>
    private BoundExpression BindOffsetof(OffsetofSyntax syntax)
    {
        var owner = ResolveType(syntax.Type, _currentScope!);
        if (owner.IsError()) return new BoundErrorExpression(syntax.Span);

        if (owner is not NamedTypeSymbol named || owner is InterfaceTypeSymbol)
        {
            diagnostics.Error("SL0480", syntax.Type.Span,
                $"'offsetof' needs a struct, union, variant or class, and " +
                $"'{owner.Name}' is none of those");
            return new BoundErrorExpression(syntax.Span);
        }

        var field = named.Fields.FirstOrDefault(f => f.Name == syntax.Field);
        if (field is null)
        {
            diagnostics.Error("SL0481", syntax.FieldSpan,
                $"'{named.Name}' has no field named '{syntax.Field}'");
            return new BoundErrorExpression(syntax.Span);
        }

        if (field.IsBitField)
        {
            diagnostics.Error("SL0482", syntax.FieldSpan,
                $"'{named.Name}.{field.Name}' is a bit-field, which has no byte " +
                "offset of its own; C refuses this too");
            return new BoundErrorExpression(syntax.Span);
        }

        return new BoundOffsetof(syntax.Span, PrimitiveTypeSymbol.NUInt, named, field);
    }

    /// <summary>
    /// <c>typeof(T)</c>. The result is a handle to metadata the compiler laid
    /// down for T, so T must have been marked [Reflect].
    /// </summary>
    private BoundExpression BindTypeof(TypeofSyntax syntax)
    {
        var measured = ResolveType(syntax.Type, _currentScope!);
        if (measured.IsError()) return new BoundErrorExpression(syntax.Span);

        if (TypeHandle is not { } handle)
        {
            diagnostics.Error("SL0347", syntax.Span,
                "'typeof' needs Standard.Reflection, which is not part of this compilation");
            return new BoundErrorExpression(syntax.Span);
        }

        if (measured is not NamedTypeSymbol { IsReflected: true } reflected)
        {
            diagnostics.Error("SL0346", syntax.Span,
                $"'{measured.Name}' carries no metadata, so 'typeof' cannot name it; " +
                "mark its declaration '[Reflect]'");
            return new BoundErrorExpression(syntax.Span);
        }

        return new BoundTypeof(syntax.Span, handle, reflected);
    }

    private BoundExpression BindCast(CastSyntax syntax)
    {
        var targetType = ResolveType(syntax.Type, _currentScope!);
        var operand = BindExpression(syntax.Operand);
        if (operand.Type.IsError() || targetType.IsError())
            return new BoundErrorExpression(syntax.Span);

        var kind = ClassifyConversion(operand.Type, targetType, explicitCast: true);
        if (kind is null)
        {
            diagnostics.Error("SL0243", syntax.Span,
                $"cannot convert '{operand.Type.Name}' to '{targetType.Name}'");
            return new BoundErrorExpression(syntax.Span);
        }

        return kind == ConversionKind.Identity && operand.Type.Equals(targetType)
            ? operand
            : new BoundConversion(syntax.Span, targetType, operand, kind.Value);
    }

    private BoundExpression BindNew(NewSyntax syntax)
    {
        var type = ResolveType(syntax.Type, _currentScope!);
        if (type.IsError()) return new BoundErrorExpression(syntax.Span);

        if (type is not ClassTypeSymbol classType)
        {
            diagnostics.Error("SL0244", syntax.Span,
                $"'{type.Name}' is not a class; only classes are heap allocated. " +
                type switch
                {
                    StructTypeSymbol => "Declare a struct as a plain value instead.",
                    InterfaceTypeSymbol => "An interface has no implementation to construct; " +
                                           "create a class that implements it.",
                    _ => "Use a pointer and an allocator for raw memory.",
                });
            return new BoundErrorExpression(syntax.Span);
        }

        if (classType.IsAbstract)
        {
            diagnostics.Error("SL0514", syntax.Span,
                $"'{classType.Name}' is abstract, so there is no such object to make; " +
                "it exists to be derived from. Make one of its derived classes instead");
            return new BoundErrorExpression(syntax.Span);
        }

        // A runtime-provided class is built by its factory, not by sl_alloc.
        if (classType.RuntimeFactory is not null)
        {
            if (syntax.Arguments.Count > 0)
                diagnostics.Error("SL0308", syntax.Span,
                    $"'new {classType.Name}()' takes no arguments");
            return new BoundNew(syntax.Span, classType, constructor: null, []);
        }

        var arguments = syntax.Arguments.Select(BindExpression).ToList();

        if (classType.Constructors.Count == 0)
        {
            if (arguments.Count > 0)
                diagnostics.Error("SL0245", syntax.Span,
                    $"'{classType.Name}' has no constructor, so 'new {classType.Name}()' takes no arguments");

            // Constructors are not inherited, but a class that declares none is
            // one whose only construction is its base's -- so that is what runs.
            // A class with no way to run one reported that where it was
            // declared, so nothing is said again here.
            TryImplicitBaseConstructor(classType, out var inherited);
            return new BoundNew(syntax.Span, classType, inherited, []);
        }

        var constructor = ResolveOverload(classType.Constructors, arguments, syntax.Span, $"new {classType.Name}");
        if (constructor is null) return new BoundErrorExpression(syntax.Span);

        var converted = ConvertArguments(constructor, arguments, syntax.Arguments);
        return new BoundNew(syntax.Span, classType, constructor, converted);
    }

    /// <summary>
    /// The base constructor a class chains to when it does not say which.
    ///
    /// It is the nearest one up the chain, skipping any class that declares no
    /// constructor at all -- such a class has nothing to run, and its own base
    /// still does. A class that declares only constructors taking arguments has
    /// to be named explicitly, because there is no obvious one to pick.
    /// </summary>
    private bool TryImplicitBaseConstructor(
        ClassTypeSymbol classType, out FunctionSymbol? chained)
    {
        chained = null;

        // Nothing up the chain declares one, so there is nothing to run and
        // nothing to complain about.
        if (NearestConstructing(classType) is not { } ancestor) return true;

        chained = ancestor.Constructors.FirstOrDefault(c => !c.Parameters.Any(p => !p.IsThis));
        return chained is not null;
    }

    /// <summary>
    /// The nearest class up the chain that declares a constructor, or null.
    ///
    /// A class that declares none has nothing of its own to run, and its base
    /// still does, so <c>base(...)</c> reaches past it -- which is also what
    /// C# means by the implicit constructor such a class is given.
    /// </summary>
    private static ClassTypeSymbol? NearestConstructing(ClassTypeSymbol classType)
    {
        for (var current = classType.BaseClass; current is not null; current = current.BaseClass)
            if (current.Constructors.Count > 0) return current;

        return null;
    }

    /// <summary>
    /// True when the code being bound may reach a <c>protected</c> member of
    /// <paramref name="owner"/>: it is inside a class that derives from it.
    /// </summary>
    private bool CanReachProtected(NamedTypeSymbol owner) =>
        owner is ClassTypeSymbol ownerClass &&
        _currentFunction?.ContainingType is ClassTypeSymbol here &&
        here.DerivesFrom(ownerClass);

    /// <summary>
    /// Whether a member of <paramref name="owner"/> with this visibility can be
    /// named from where binding is.
    ///
    /// Public is everywhere. Anything else is its module's, which is what
    /// privacy has always meant here -- a module is the unit of it. Protected
    /// adds the one exception: a class deriving from the owner may reach it
    /// wherever that class lives, because a base class handing something to its
    /// derived classes and to nobody else is the whole of what the word is for.
    /// </summary>
    private bool CanReach(bool isPublic, bool isProtected, NamedTypeSymbol owner) =>
        isPublic
        || owner.ModuleName == _currentModule!.Name
        || (isProtected && CanReachProtected(owner));

    /// <summary>How a diagnostic should describe a member that could not be reached.</summary>
    private static string NotVisible(NamedTypeSymbol owner, string member, bool isProtected) =>
        isProtected
            ? $"'{owner.Name}.{member}' is protected, so only '{owner.Name}' and classes " +
              "deriving from it may name it"
            : $"'{owner.Name}.{member}' is not public";

    /// <summary>
    /// Flattens a chain of member accesses back into a dotted name, so that
    /// <c>A.B.Thing</c> can be recognised as a module path. Returns null as soon
    /// as anything other than a plain name appears in the chain.
    /// </summary>
    private static IReadOnlyList<string>? FlattenName(ExpressionSyntax expression) => expression switch
    {
        NameSyntax name => name.Name.Parts,
        MemberAccessSyntax member when FlattenName(member.Target) is { } prefix =>
            [.. prefix, member.Member],
        _ => null,
    };

    /// <summary>
    /// Resolves a member-access target to a module, or null when it names a value.
    /// A local, parameter or field always wins over a module of the same name.
    /// </summary>
    private ModuleSymbol? ResolveModulePrefix(ExpressionSyntax target)
    {
        if (FlattenName(target) is not { } parts) return null;

        if (LookupLocal(parts[0]) is not null) return null;
        if (_currentFunction?.Parameters.Any(p => p.Name == parts[0] && !p.IsThis) == true) return null;
        if (_currentFunction?.ContainingType?.FindField(parts[0]) is not null) return null;
        if (_currentFunction?.ContainingType?.FindProperty(parts[0]) is not null) return null;

        string name = string.Join('.', parts);
        if (_currentScope!.Imports.TryGetValue(name, out var module)) return module;
        return _modules.TryGetValue(name, out module) ? module : null;
    }

    /// <summary>
    /// Resolves a member-access target to an enum type, or null when it names a
    /// value. Like <see cref="ResolveModulePrefix"/> a local of the same name
    /// wins, so an enum called <c>Level</c> never shadows a variable.
    /// </summary>
    /// <summary>
    /// The variant a <c>Shape.Circle</c> is qualified by, or null.
    ///
    /// Only a variant already named as a type, so a generic one is not reachable
    /// this way: type arguments cannot be written at a call, which is the same
    /// reason <c>Ok(x)</c> takes its type from where it is going.
    /// </summary>
    private VariantTypeSymbol? ResolveVariantPrefix(ExpressionSyntax target)
    {
        if (FlattenName(target) is not { } parts) return null;

        // A value of that name is nearer than a type of it, exactly as for an
        // enum: `shape.Circle` tests a variant, `Shape.Circle` builds one.
        if (LookupLocal(parts[0]) is not null) return null;
        if (_currentFunction?.Parameters.Any(p => p.Name == parts[0] && !p.IsThis) == true) return null;
        if (_currentFunction?.ContainingType?.FindField(parts[0]) is not null) return null;
        if (_currentFunction?.ContainingType?.FindProperty(parts[0]) is not null) return null;

        if (parts.Count == 1)
        {
            if (_currentScope!.Module.Types.TryGetValue(parts[0], out var local))
                return local as VariantTypeSymbol;

            foreach (var imported in _currentScope.Imports.Values)
                if (imported.Types.TryGetValue(parts[0], out var found) &&
                    found is VariantTypeSymbol { IsPublic: true } visible)
                    return visible;

            return null;
        }

        string moduleName = string.Join(".", parts.Take(parts.Count - 1));
        return _modules.TryGetValue(moduleName, out var module) &&
               module.Types.TryGetValue(parts[^1], out var qualified) &&
               qualified is VariantTypeSymbol { IsPublic: true } reachable
            ? reachable
            : null;
    }

    private EnumTypeSymbol? ResolveEnumPrefix(ExpressionSyntax target)
    {
        if (FlattenName(target) is not { } parts) return null;

        if (LookupLocal(parts[0]) is not null) return null;
        if (_currentFunction?.Parameters.Any(p => p.Name == parts[0] && !p.IsThis) == true) return null;
        if (_currentFunction?.ContainingType?.FindField(parts[0]) is not null) return null;
        if (_currentFunction?.ContainingType?.FindProperty(parts[0]) is not null) return null;

        // Either a bare name in this module, or one qualified by its module.
        if (parts.Count == 1)
        {
            if (_currentScope!.Module.Types.TryGetValue(parts[0], out var local))
                return local as EnumTypeSymbol;

            var visible = _currentScope.Imports.Values.Distinct()
                .Select(m => m.Types.TryGetValue(parts[0], out var t) && t.IsPublic ? t : null)
                .OfType<EnumTypeSymbol>()
                .Distinct()
                .ToList();

            return visible.Count == 1 ? visible[0] : null;
        }

        string moduleName = string.Join('.', parts.Take(parts.Count - 1));
        ModuleSymbol? module =
            _currentScope!.Imports.TryGetValue(moduleName, out var imported) ? imported
            : _modules.TryGetValue(moduleName, out var known) ? known
            : null;

        if (module is null) return null;
        return module.Types.TryGetValue(parts[^1], out var candidate) && candidate.IsPublic
            ? candidate as EnumTypeSymbol
            : null;
    }

    private BoundExpression BindNewArray(NewArraySyntax syntax)
    {
        var element = ResolveType(syntax.ElementType, _currentScope!);
        var length = BindExpression(syntax.Length);

        if (element.IsError() || length.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        if (element.IsVoid())
        {
            diagnostics.Error("SL0311", syntax.Span, "there is no array of 'void'");
            return new BoundErrorExpression(syntax.Span);
        }

        if (length.Type is not PrimitiveTypeSymbol { IsInteger: true })
        {
            diagnostics.Error("SL0312", syntax.Length.Span,
                $"an array length must be an integer, but this is '{length.Type.Name}'");
            return new BoundErrorExpression(syntax.Span);
        }

        return new BoundNewArray(syntax.Span, ArrayOf(element),
            BindConversion(length, PrimitiveTypeSymbol.NUInt, syntax.Length.Span));
    }

    private BoundExpression BindMemberAccess(MemberAccessSyntax syntax)
    {
        // `Module.Member` is a qualified name, not a value access. A module,
        // a variant and an enum are all names, so `->` reaches none of them:
        // there is nothing there to be pointed at.
        if (!syntax.ThroughPointer && ResolveModulePrefix(syntax.Target) is { } importedModule)
        {
            if (importedModule.Constants.TryGetValue(syntax.Member, out var constant) && constant.IsPublic)
                return new BoundConstantAccess(syntax.Span, constant);

            if (importedModule.Statics.TryGetValue(syntax.Member, out var shared) && shared.IsPublic)
                return new BoundStaticAccess(syntax.Span, shared);

            diagnostics.Error("SL0246", syntax.Span,
                $"module '{importedModule.Name}' has no public member named '{syntax.Member}'");
            return new BoundErrorExpression(syntax.Span);
        }

        // `Shape.Empty` builds a variant whose case carries nothing. One that
        // does carry something is a call, and BindCall handles it.
        if (!syntax.ThroughPointer && ResolveVariantPrefix(syntax.Target) is { } variantType)
        {
            if (variantType.FindCase(syntax.Member) is not { } named)
            {
                diagnostics.Error("SL0435", syntax.Span,
                    $"variant '{variantType.Name}' has no case named '{syntax.Member}'; it has " +
                    Listed(variantType.Cases.Select(c => c.Name)));
                return new BoundErrorExpression(syntax.Span);
            }

            return BindVariantConstruction(variantType, named, [], syntax.Span);
        }

        // `Color.Red` names a constant of an enum type, not a member of a value.
        if (!syntax.ThroughPointer && ResolveEnumPrefix(syntax.Target) is { } enumType)
        {
            if (enumType.FindMember(syntax.Member) is { } member)
                return new BoundLiteral(syntax.Span, enumType, member.Value);

            diagnostics.Error("SL0355", syntax.Span,
                $"enum '{enumType.Name}' has no member named '{syntax.Member}'");
            return new BoundErrorExpression(syntax.Span);
        }

        var receiver = syntax.Target is BaseSyntax
            ? BindBaseReceiver(syntax.Target.Span)
            : BindExpression(syntax.Target);

        if (receiver is null || receiver.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        // An inline array's length was written in its type, so it is a constant
        // rather than a load -- and, unlike the other two, it never had to be
        // stored anywhere.
        if (receiver.Type is FixedArrayTypeSymbol inline)
        {
            if (syntax.Member == "Length")
                return new BoundLiteral(
                    syntax.Span, PrimitiveTypeSymbol.NUInt, (ulong)inline.Length);

            diagnostics.Error("SL0313", syntax.Span,
                $"'{inline.Name}' has no member named '{syntax.Member}'; " +
                "an inline array has only 'Length', and is indexed");
            return new BoundErrorExpression(syntax.Span);
        }

        // An array's only member is its length, which lives in the header; a
        // slice's is the one it carries, and it answers to the same name.
        if (receiver.Type is ArrayTypeSymbol or SliceTypeSymbol)
        {
            if (syntax.Member == "Length")
                return new BoundArrayLength(syntax.Span, PrimitiveTypeSymbol.NUInt, receiver);

            diagnostics.Error("SL0313", syntax.Span,
                $"'{receiver.Type.Name}' has no member named '{syntax.Member}'; " +
                (receiver.Type is SliceTypeSymbol
                    ? "a slice has only 'Length', and is indexed and sliced further"
                    : "an array has only 'Length'"));
            return new BoundErrorExpression(syntax.Span);
        }

        if (ReachThroughPointer(syntax, receiver) is not { } reachedThrough)
            return new BoundErrorExpression(syntax.Span);
        receiver = reachedThrough;

        if (receiver.Type is not NamedTypeSymbol && receiver.Type.AsClass() is null)
        {
            diagnostics.Error("SL0247", syntax.Span,
                $"'{receiver.Type.Name}' has no member named '{syntax.Member}'");
            return new BoundErrorExpression(syntax.Span);
        }

        var namedType = receiver.Type as NamedTypeSymbol ?? receiver.Type.AsClass()!;

        if (receiver.Type is OptionalTypeSymbol or WeakTypeSymbol)
        {
            diagnostics.Error("SL0248", syntax.Span,
                $"'{receiver.Type.Name}' may be null; check it against null before accessing '{syntax.Member}'");
            return new BoundErrorExpression(syntax.Span);
        }

        // A variant's members are its cases and their payloads, neither of
        // which is a field the source may reach directly.
        if (receiver.Type is VariantTypeSymbol variantReceiver)
            return BindVariantRead(syntax, receiver, variantReceiver);

        // Properties come first: an automatic one has a field of the same name,
        // and reaching that field directly would skip the accessor and, through
        // an interface, skip dispatch with it.
        if (namedType.FindProperty(syntax.Member) is { } property)
            return BindPropertyRead(syntax.Span, receiver, property);

        if (namedType.FindField(syntax.Member) is { } field)
        {
            if (!CanReach(field.IsPublic, field.IsProtected, field.ContainingType))
            {
                diagnostics.Error("SL0249", syntax.Span,
                    NotVisible(field.ContainingType, syntax.Member, field.IsProtected));
                return new BoundErrorExpression(syntax.Span);
            }
            return new BoundFieldAccess(syntax.Span, receiver, field);
        }

        // A member of a nameless struct or union reads as the parent's own, so
        // what is built is the chain of field accesses that reaches it. The
        // layout already put it where C would; this is only the name.
        if (ReachThroughAnonymous(syntax.Span, receiver, namedType, syntax.Member) is { } reached)
            return reached;

        if (namedType.FindMethod(syntax.Member) is not null)
        {
            // Methods are only reachable through a call, which BindCall handles.
            diagnostics.Error("SL0250", syntax.Span,
                $"'{namedType.Name}.{syntax.Member}' is a method; call it with '()'");
            return new BoundErrorExpression(syntax.Span);
        }

        diagnostics.Error("SL0251", syntax.Span,
            $"'{namedType.Name}' has no member named '{syntax.Member}'");
        return new BoundErrorExpression(syntax.Span);
    }

    /// <summary>
    /// Applies <c>.</c> and <c>-&gt;</c> to a receiver that may be a pointer.
    ///
    /// Both spellings dereference, which is why <c>p.field</c> has always meant
    /// <c>(*p).field</c>. They differ only in what they refuse: an arrow says
    /// the programmer expected a pointer, so finding a value there is a mistake
    /// worth reporting rather than a spelling to accept.
    ///
    /// Returns null when it has reported one.
    /// </summary>
    private BoundExpression? ReachThroughPointer(
        MemberAccessSyntax syntax, BoundExpression receiver)
    {
        if (receiver.Type is PointerTypeSymbol { Element: NamedTypeSymbol } pointer)
            return new BoundDereference(syntax.Span, pointer.Element, receiver);

        if (!syntax.ThroughPointer) return receiver;

        diagnostics.Error("SL0494", syntax.Span,
            receiver.Type is PointerTypeSymbol pointed
                ? $"'{pointed.Name}' points at '{pointed.Element.Name}', which has no members, " +
                  $"so '->{syntax.Member}' reaches nothing"
                : $"'{receiver.Type.Name}' is not a pointer, so '->' does not apply to it; " +
                  $"write '.{syntax.Member}'");

        return null;
    }

    /// <summary>
    /// Finds <paramref name="member"/> inside this type's nameless members, and
    /// returns the access that reaches it -- one field access per level.
    ///
    /// The search is breadth-first so that the shallowest match wins, which is
    /// the rule C uses and the only one that keeps an outer name from being
    /// shadowed by a deeper one.
    /// </summary>
    private BoundExpression? ReachThroughAnonymous(
        SourceSpan span, BoundExpression receiver, NamedTypeSymbol type, string member)
    {
        var level = new List<(BoundExpression Access, NamedTypeSymbol Type)> { (receiver, type) };

        while (level.Count > 0)
        {
            var next = new List<(BoundExpression Access, NamedTypeSymbol Type)>();

            var found = new List<(BoundExpression Access, NamedTypeSymbol Owner)>();

            foreach (var (access, current) in level)
            {
                foreach (var anonymous in current.Fields.Where(f => f.IsAnonymous))
                {
                    if (anonymous.Type is not NamedTypeSymbol inner) continue;

                    var reached = new BoundFieldAccess(span, access, anonymous);
                    if (inner.FindField(member) is { } field)
                        found.Add((new BoundFieldAccess(span, reached, field), inner));

                    next.Add((reached, inner));
                }
            }

            // Two nameless members at the same depth both offering the name is
            // a question with no answer, so it is asked rather than guessed.
            if (found.Count > 1)
            {
                // The generated names are deliberately unwritable, so naming
                // them here would point at something the reader cannot use.
                diagnostics.Error("SL0492", span,
                    $"'{member}' is ambiguous: {Counted(found.Count, "nameless member")} " +
                    $"of '{type.Name}' declare{(found.Count == 1 ? "s" : "")} it. Give one of " +
                    "them a name, so that the one you mean can be said");
                return new BoundErrorExpression(span);
            }

            if (found.Count == 1) return found[0].Access;

            level = next;
        }

        return null;
    }

    /// <summary>
    /// <c>r.Ok</c>, <c>r.Value</c> and <c>r.Error</c>.
    ///
    /// The storage is module-private and this reads it directly, so the three
    /// names cost a field load and no call. What <c>Value</c> and <c>Error</c>
    /// additionally cost is a proof: it is readable only where the compiler has
    /// already established the case it belongs to, which is what makes a variant
    /// different from a struct whose fields happen to sit together.
    /// </summary>
    /// <summary>
    /// <c>Ok(x)</c> - a case named without its variant, held as a draft until
    /// something says which variant was meant.
    ///
    /// This is how <c>Ok</c> and <c>Fail</c> have always worked, generalized:
    /// one value cannot say what a variant's type arguments are, so the case is
    /// resolved from the type it is being returned or assigned into, the same
    /// rule a lambda obeys. Functions win a name outright - a bare call is only
    /// a draft when nothing else answers to it - so a case name costs a program
    /// nothing it was already using.
    /// </summary>
    private BoundExpression BindVariantDraft(
        CallSyntax syntax, string name, List<BoundExpression> arguments) =>
        new BoundVariantDraft(syntax.Span, name, arguments);

    /// <summary>
    /// The case a name would build if it were written bare in this file, or
    /// null. It is what SL0414 refuses to let a module-level function shadow.
    /// </summary>
    private VariantCaseSymbol? CaseNamed(FileScope scope, string name)
    {
        var previous = _currentScope;
        _currentScope = scope;

        try
        {
            var found = VariantsWithCase(name).FirstOrDefault()?.FindCase(name);
            if (found is not null) return found;

            // A generic variant has no symbol until it is instantiated, so its
            // template's cases are read from the syntax -- which is also how
            // Result's Ok and Fail are found before any Result exists.
            foreach (var template in VisibleModules().SelectMany(m => m.GenericTypes.Values))
            {
                if (template.Declaration.Kind != TypeDeclKind.Variant) continue;
                if (template.Declaration.Cases.All(c => c.Name != name)) continue;

                return new VariantCaseSymbol
                {
                    Name = name,
                    Tag = 0,
                    Span = template.Declaration.Span,
                    DeclaringVariant = new VariantTypeSymbol
                    {
                        SimpleName = template.Name,
                        ModuleName = template.Module.Name,
                    },
                };
            }

            return null;
        }
        finally
        {
            _currentScope = previous;
        }
    }

    /// <summary>Every variant this file can see with a case of that name.</summary>
    private List<VariantTypeSymbol> VariantsWithCase(string name)
    {
        return VisibleModules()
            .Distinct()
            .SelectMany(m => m.Types.Values)
            .OfType<VariantTypeSymbol>()
            .Where(v => v.FindCase(name) is not null)
            .Distinct()
            .ToList();
    }

    /// <summary>
    /// True when a bare <c>Name(...)</c> could be building a variant, which is
    /// what makes it worth holding as a draft rather than reporting as an
    /// unknown function.
    ///
    /// A generic variant is not in any module's type table until it has been
    /// instantiated, so its template's cases are read from the syntax. That is
    /// what keeps <c>Ok(x)</c> working in a program that has not yet named a
    /// <c>Result&lt;T, E&gt;</c> anywhere.
    /// </summary>
    private bool CouldBeVariantCase(string name)
    {
        if (VariantsWithCase(name).Count > 0) return true;

        return VisibleModules()
            .SelectMany(m => m.GenericTypes.Values)
            .Any(t => t.Declaration.Kind == TypeDeclKind.Variant &&
                      t.Declaration.Cases.Any(c => c.Name == name));
    }

    /// <summary>
    /// Settles a draft against the variant it is becoming, converting each
    /// argument to the field it is stored in.
    /// </summary>
    private BoundExpression BindVariantSettle(
        BoundVariantDraft draft, TypeSymbol target, SourceSpan span)
    {
        if (target is not VariantTypeSymbol variant)
        {
            diagnostics.Error("SL0413", span,
                $"'{draft.Case}' names a variant's case, but '{target.Name}' is expected here");
            return new BoundErrorExpression(span);
        }

        if (variant.FindCase(draft.Case) is not { } variantCase)
        {
            diagnostics.Error("SL0435", span,
                $"'{variant.Name}' has no case named '{draft.Case}'; it has " +
                Listed(variant.Cases.Select(c => c.Name)));
            return new BoundErrorExpression(span);
        }

        return BindVariantConstruction(variant, variantCase, draft.Arguments, span);
    }

    /// <summary>Checks the arguments against a case's fields and builds the value.</summary>
    private BoundExpression BindVariantConstruction(
        VariantTypeSymbol variant,
        VariantCaseSymbol variantCase,
        IReadOnlyList<BoundExpression> arguments,
        SourceSpan span)
    {
        var fields = variantCase.Fields;

        if (arguments.Count != fields.Count)
        {
            diagnostics.Error("SL0289", span,
                $"'{variant.Name}.{variantCase.Name}' carries {Counted(fields.Count, "field")}, " +
                $"but {Given(arguments.Count)}; " +
                $"it is written '{variantCase.Signature}'");
            return new BoundErrorExpression(span);
        }

        var converted = arguments
            .Select((argument, i) => BindConversion(argument, fields[i].Type, argument.Span))
            .ToList();

        return new BoundVariantConstruction(span, variant, variantCase, converted);
    }

    /// <summary>
    /// <c>v.Case</c>, which asks the tag, and <c>v.field</c>, which reads a
    /// payload once something has said which case is there.
    ///
    /// The proof is the whole point. A payload field is storage that only means
    /// anything when its case is the one present, so reading it without having
    /// established that is refused rather than answered.
    /// </summary>
    private BoundExpression BindVariantRead(
        MemberAccessSyntax syntax, BoundExpression receiver, VariantTypeSymbol variant)
    {
        if (variant.FindCase(syntax.Member) is { } tested)
            return new BoundVariantTest(
                syntax.Span, PrimitiveTypeSymbol.Bool, receiver, tested);

        // A variant may carry ordinary members too, and Result's ValueOr is one.
        if (variant.FindProperty(syntax.Member) is { } property)
            return BindPropertyRead(syntax.Span, receiver, property);

        var carrying = variant.Cases.Where(c => c.FindField(syntax.Member) is not null).ToList();

        if (carrying.Count == 0)
        {
            if (variant.FindMethod(syntax.Member) is not null)
            {
                diagnostics.Error("SL0250", syntax.Span,
                    $"'{variant.Name}.{syntax.Member}' is a method; call it with '()'");
                return new BoundErrorExpression(syntax.Span);
            }

            diagnostics.Error("SL0251", syntax.Span,
                $"'{variant.Name}' has no case or field named '{syntax.Member}'; its cases are " +
                Listed(variant.Cases.Select(c => c.Signature)));
            return new BoundErrorExpression(syntax.Span);
        }

        var subject = NarrowableSubject(receiver);

        if (subject is null)
        {
            diagnostics.Error("SL0285", syntax.Span,
                $"'{syntax.Member}' can only be read from a variant held in a local or a " +
                "parameter, because that is the only thing a check can be about; assign " +
                "this to one first, then test which case it is");
            return new BoundErrorExpression(syntax.Span);
        }

        var known = _variantFacts.TryGetValue(subject, out var fact) ? fact : null;
        string name = SubjectName(subject);

        if (known is null)
        {
            var suggestion = carrying[0];
            diagnostics.Error("SL0286", syntax.Span,
                $"'{name}.{syntax.Member}' is not readable here, because nothing has " +
                $"established that '{name}' is '{suggestion.Name}'; " +
                $"check 'if ({name}.{suggestion.Name})' first, or switch over '{name}'");
            return new BoundErrorExpression(syntax.Span);
        }

        if (known.FindField(syntax.Member) is not { } field)
        {
            diagnostics.Error("SL0286", syntax.Span,
                $"'{name}' is known to be '{known.Name}' here, and '{known.Signature}' does " +
                $"not carry '{syntax.Member}'; that field belongs to " +
                Listed(carrying.Select(c => "'" + c.Name + "'")));
            return new BoundErrorExpression(syntax.Span);
        }

        return new BoundVariantPayload(syntax.Span, receiver, known, field);
    }

    /// <summary>The modules a name written in the current file resolves against.</summary>
    private IEnumerable<ModuleSymbol> VisibleModules()
    {
        if (_currentScope is null) return [];
        return _currentScope.Imports.Values.Prepend(_currentScope.Module).Distinct();
    }

    private static string SubjectName(object subject) => subject switch
    {
        LocalSymbol local => local.Name,
        ParameterSymbol parameter => parameter.Name,
        _ => "it",
    };

    /// <summary>"a, b and c" - for a diagnostic that lists what was available.</summary>
    private static string Listed(IEnumerable<string> items)
    {
        var list = items.ToList();
        return list.Count switch
        {
            0 => "nothing",
            1 => list[0],
            _ => string.Join(", ", list.Take(list.Count - 1)) + " and " + list[^1],
        };
    }

    private static string Counted(int count, string noun) =>
        count == 1 ? "1 " + noun : $"{count} {noun}s";

    /// <summary>"1 was given" / "3 were given", so the verb agrees with the count.</summary>
    private static string Given(int count) => count == 1 ? "1 was given" : $"{count} were given";

    private BoundExpression BindCall(CallSyntax syntax)
    {
        var arguments = syntax.Arguments.Select(BindArgument).ToList();

        // `base(...)` is the base constructor and `this(...)` another of this
        // class's own; neither is a member of anything.
        if (syntax.Callee is BaseSyntax) return BindBaseConstruction(syntax, arguments);
        if (syntax.Callee is ThisSyntax) return BindThisConstruction(syntax, arguments);

        // A bare `Ok(x)` builds a variant rather than calling anything. It has
        // to be decided here, before the name is looked up, because a draft has
        // no type yet and overload resolution has nothing to resolve against.
        // What keeps that unambiguous is SL0414: a module-level function may not
        // be named after a case of a variant this file can see. A method still
        // may, and is reached through its receiver.
        if (syntax.Callee is NameSyntax { Name.Parts: [var bare] } &&
            LookupLocal(bare) is null && CouldBeVariantCase(bare))
            return BindVariantDraft(syntax, bare, arguments);


        // `Shape.Circle(2.0)` names the variant as well as the case, so it
        // needs nothing from the surrounding expression to settle it.
        if (syntax.Callee is MemberAccessSyntax { } named &&
            ResolveVariantPrefix(named.Target) is { } prefix)
        {
            if (prefix.FindCase(named.Member) is not { } prefixCase)
            {
                diagnostics.Error("SL0435", named.Span,
                    $"variant '{prefix.Name}' has no case named '{named.Member}'; it has " +
                    Listed(prefix.Cases.Select(c => c.Name)));
                return new BoundErrorExpression(syntax.Span);
            }

            return BindVariantConstruction(prefix, prefixCase, arguments, syntax.Span);
        }

        // `receiver.Method(args)`, unless the receiver is really a module path.
        if (syntax.Callee is MemberAccessSyntax member)
        {
            if (ResolveModulePrefix(member.Target) is not { } module)
                return BindMethodCall(syntax, member, arguments);

            bool sameModule = module == _currentModule;
            var visible = module.FindFunctions(member.Member)
                .Where(f => sameModule || f.IsPublic)
                .ToList();

            if (visible.Any(f => AcceptsArguments(f, arguments)))
                return BindFunctionCall(syntax, visible, member.Member, arguments);

            var qualified = new QualifiedName(member.Span,
                [.. FlattenName(member.Target)!, member.Member]);
            if (TryBindGenericCall(syntax, qualified, arguments) is { } generic) return generic;

            return BindFunctionCall(syntax, visible, member.Member, arguments);
        }

        // A local, parameter or field holding a delegate is called indirectly,
        // and shadows any function of the same name -- the value is nearer.
        if (BindDelegateTarget(syntax.Callee) is { } indirect)
            return BuildIndirectCall(syntax, indirect, arguments);

        if (syntax.Callee is NameSyntax callee)
        {
            var candidates = ResolveFunctionCandidates(callee.Name);

            // An instantiation of a generic is an ordinary function with an
            // ordinary name, so it turns up here beside everything else. It must
            // not shadow the template it came from: `Sort(list)` instantiating
            // `Sort<Money>` cannot be what a later `Sort(numbers[2:5])` resolves
            // to. So the templates are tried whenever nothing already built fits.
            if (candidates.Any(c => AcceptsArguments(c, arguments)))
                return BindFunctionCall(syntax, candidates, callee.Name.Text, arguments);

            if (TryBindGenericCall(syntax, callee.Name, arguments) is { } generic) return generic;

            if (candidates.Count > 0)
                return BindFunctionCall(syntax, candidates, callee.Name.Text, arguments);

            // A method of the enclosing type, called without a receiver.
            if (callee.Name.Parts.Count == 1 &&
                _currentFunction?.ContainingType?.FindMethods(callee.Name.Text).ToList() is
                    { Count: > 0 } own)
            {
                var receiver = BindImplicitThis(callee.Span);
                if (receiver is not null)
                {
                    var method = ResolveOverload(own, arguments, callee.Span, callee.Name.Text);
                    if (method is null) return new BoundErrorExpression(syntax.Span);

                    // Inherited, so it may belong to a base in another module.
                    var owner = method.ContainingType ?? _currentFunction!.ContainingType!;
                    if (!CanReach(method.IsPublic, method.IsProtected, owner))
                    {
                        diagnostics.Error("SL0257", callee.Span,
                            NotVisible(owner, callee.Name.Text, method.IsProtected));
                        return new BoundErrorExpression(syntax.Span);
                    }

                    return BuildCall(syntax, method, receiver, arguments);
                }
            }

            if (callee.Name.Parts.Count == 1 && _currentFunction?.ContainingType is { } enclosing)
            {
                var generics = enclosing.GenericMethods.Where(m => m.Name == callee.Name.Text).ToList();
                if (generics.Count > 0)
                {
                    var instantiated = InferAndInstantiate(generics, syntax, arguments);
                    if (instantiated is null) return new BoundErrorExpression(syntax.Span);

                    var receiver = BindImplicitThis(callee.Span);
                    if (receiver is not null)
                        return BuildCall(syntax, instantiated, receiver, arguments);
                }
            }

            // Inside a lambda, a bare name may be a method of the object the
            // lambda was written in. That object is captured, and the call then
            // goes through the capture like any other member.
            if (callee.Name.Parts.Count == 1 && _closures.Count > 0 &&
                MethodsOfEnclosingThis(callee.Name.Text) is { Count: > 0 } outerMethods)
            {
                var outerMethod =
                    ResolveOverload(outerMethods, arguments, callee.Span, callee.Name.Text);
                if (outerMethod is null) return new BoundErrorExpression(syntax.Span);

                var captured = CaptureThis(_closures.Count - 1, callee.Span);
                if (captured.Type.IsError()) return new BoundErrorExpression(syntax.Span);
                return BuildCall(syntax, outerMethod, captured, arguments);
            }

            diagnostics.Error("SL0252", callee.Span, $"no function named '{callee.Name.Text}' is in scope");
            return new BoundErrorExpression(syntax.Span);
        }

        diagnostics.Error("SL0253", syntax.Span, "this expression is not callable");
        return new BoundErrorExpression(syntax.Span);
    }

    /// <summary>
    /// One argument, which may be written <c>ref x</c>.
    ///
    /// A <c>ref</c> argument is bound to the address of what it names, so what
    /// reaches the callee is a pointer and nothing in the emitter has to learn a
    /// new way to pass one. What it costs is a check that there is an address to
    /// take: a local, a parameter, a field, an array element or a dereference
    /// has one, and a call result or a literal does not.
    /// </summary>
    private BoundExpression BindArgument(ExpressionSyntax syntax)
    {
        if (syntax is not RefArgumentSyntax reference) return BindExpression(syntax);

        var target = BindExpression(reference.Value);
        if (target.Type.IsError()) return target;

        if (!IsAddressable(target))
        {
            diagnostics.Error("SL0443", reference.Span,
                "'ref' passes the storage this names rather than a copy of it, and this " +
                "expression has no storage to pass; put it in a local first");
            return new BoundErrorExpression(reference.Span);
        }

        if (IsReadOnlyTarget(target) is { } why)
        {
            diagnostics.Error("SL0444", reference.Span,
                $"'ref' lets the callee write to this, and {why}");
            return new BoundErrorExpression(reference.Span);
        }

        return new BoundAddressOf(
            reference.Span, new PointerTypeSymbol(target.Type), target)
        {
            FromRefKeyword = true,
        };
    }

    /// <summary>True for an expression that names storage rather than a value.</summary>
    private static bool IsAddressable(BoundExpression expression) => expression switch
    {
        // A bit-field is some of the bits of a byte, and there is no pointer to
        // that. It is why C refuses `&s.flags` too.
        BoundFieldAccess { Field.IsBitField: true } => false,

        BoundLocalAccess or BoundParameterAccess or BoundThis
            or BoundFieldAccess or BoundIndex or BoundDereference or BoundStaticAccess => true,
        _ => false,
    };

    /// <summary>Why this storage may not be written, or null when it may.</summary>
    private static string? IsReadOnlyTarget(BoundExpression expression) => expression switch
    {
        BoundLocalAccess { Local.IsConst: true } local =>
            $"'{local.Local.Name}' is a 'const'",
        BoundParameterAccess { Parameter.Mode: ParameterMode.In } parameter =>
            $"'{parameter.Parameter.Name}' is an 'in' parameter, which promises not to be written",
        BoundStaticAccess held =>
            $"'{held.Static.Name}' is a 'static readonly'",
        _ => null,
    };

    /// <summary>
    /// Binds a bare callee that names a value of delegate type, or returns null
    /// when it does not name one. Nothing is bound unless it really resolves to
    /// a delegate, so an ordinary call is never disturbed by this.
    /// </summary>
    private BoundExpression? BindDelegateTarget(ExpressionSyntax callee)
    {
        switch (callee)
        {
            case NameSyntax { Name.Parts.Count: 1 } name:
            {
                string text = name.Name.Parts[0];

                if (LookupLocal(text) is { Type: DelegateTypeSymbol } local)
                    return new BoundLocalAccess(name.Span, local);

                if (_currentFunction?.Parameters.FirstOrDefault(
                        p => p.Name == text && !p.IsThis) is { Type: DelegateTypeSymbol } parameter)
                    return new BoundParameterAccess(name.Span, parameter);

                if (_currentFunction?.ContainingType?.FindProperty(text)
                        is { Type: DelegateTypeSymbol } property)
                {
                    var receiver = BindImplicitThis(name.Span);
                    if (receiver is not null)
                        return BindPropertyRead(name.Span, receiver, property);
                }

                if (_currentFunction?.ContainingType?.FindField(text) is { Type: DelegateTypeSymbol } field)
                {
                    var receiver = BindImplicitThis(name.Span);
                    if (receiver is not null) return new BoundFieldAccess(name.Span, receiver, field);
                }

                return null;
            }

            // `receiver.field(...)` is handled by BindMethodCall instead, which
            // has already bound the receiver and so cannot bind it twice.
            default:
                return null;
        }
    }

    private BoundExpression BuildIndirectCall(
        CallSyntax syntax, BoundExpression target, List<BoundExpression> arguments)
    {
        var delegateType = (DelegateTypeSymbol)target.Type;

        if (arguments.Count != delegateType.Signature.Count)
        {
            diagnostics.Error("SL0363", syntax.Span,
                $"delegate '{delegateType.Name}' is '{delegateType.SignatureText}' and takes " +
                $"{delegateType.Signature.Count} argument{(delegateType.Signature.Count == 1 ? "" : "s")}, " +
                $"but {Given(arguments.Count)}");
            return new BoundErrorExpression(syntax.Span);
        }

        var converted = new List<BoundExpression>(arguments.Count);
        for (int i = 0; i < arguments.Count; i++)
        {
            var parameter = delegateType.Signature[i];
            var span = syntax.Arguments[i].Span;

            if (!ArgumentFits(arguments[i], parameter))
            {
                ReportArgumentMode(delegateType.Name, i, arguments[i], parameter);
                return new BoundErrorExpression(syntax.Span);
            }

            converted.Add(ConvertArgument(arguments[i], parameter, span));
        }

        return new BoundIndirectCall(syntax.Span, delegateType, target, converted);
    }

    private BoundExpression BindMethodCall(
        CallSyntax syntax, MemberAccessSyntax member, List<BoundExpression> arguments)
    {
        var receiver = member.Target is BaseSyntax
            ? BindBaseReceiver(member.Target.Span)
            : BindExpression(member.Target);

        if (receiver is null || receiver.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        if (ReachThroughPointer(member, receiver) is not { } reachedThrough)
            return new BoundErrorExpression(syntax.Span);
        receiver = reachedThrough;

        if (receiver.Type is OptionalTypeSymbol or WeakTypeSymbol)
        {
            diagnostics.Error("SL0254", member.Span,
                $"'{receiver.Type.Name}' may be null; check it against null before calling '{member.Member}'");
            return new BoundErrorExpression(syntax.Span);
        }

        // An enum has no methods, so `HasFlag` is the language spelling the test
        // out rather than a member being called: it becomes `(value & f) == f`,
        // which is the same thing written by hand and costs the same.
        if (receiver.Type is EnumTypeSymbol flagsEnum && member.Member == "HasFlag")
            return BindHasFlag(syntax, member, receiver, flagsEnum, arguments);

        if (TryBindIntrinsicMember(syntax, member, receiver, arguments) is { } intrinsic)
            return intrinsic;

        if (receiver.Type is not NamedTypeSymbol namedType)
        {
            diagnostics.Error("SL0255", member.Span,
                $"'{receiver.Type.Name}' has no method named '{member.Member}'");
            return new BoundErrorExpression(syntax.Span);
        }

        // A field holding a delegate is called through, not dispatched to. It is
        // checked before methods so that the field's own name is what is called;
        // a method of the same name would be a different thing entirely.
        if (namedType.FindProperty(member.Member) is { Type: DelegateTypeSymbol } callableProperty)
        {
            var read = BindPropertyRead(member.Span, receiver, callableProperty);
            return read.Type.IsError()
                ? new BoundErrorExpression(syntax.Span)
                : BuildIndirectCall(syntax, read, arguments);
        }

        if (namedType.FindField(member.Member) is { Type: DelegateTypeSymbol } callable)
        {
            if (!CanReach(callable.IsPublic, callable.IsProtected, callable.ContainingType))
            {
                diagnostics.Error("SL0249", member.Span,
                    NotVisible(callable.ContainingType, member.Member, callable.IsProtected));
                return new BoundErrorExpression(syntax.Span);
            }

            return BuildIndirectCall(
                syntax, new BoundFieldAccess(member.Span, receiver, callable), arguments);
        }

        var overloads = namedType.FindMethods(member.Member).ToList();

        if (overloads.Count == 0)
        {
            if (TryBindGenericMethodCall(syntax, member, namedType, receiver, arguments) is { } generic)
                return generic;

            diagnostics.Error("SL0256", member.Span,
                $"'{namedType.Name}' has no method named '{member.Member}'");
            return new BoundErrorExpression(syntax.Span);
        }

        // Which overload is decided by the arguments, the same way a call to a
        // module-level function is.
        var method = overloads.Count == 1
            ? overloads[0]
            : ResolveOverload(overloads, arguments, member.Span, $"{namedType.Name}.{member.Member}");

        if (method is null) return new BoundErrorExpression(syntax.Span);

        // The accessors are real methods, but they are the lowering rather than
        // the language: naming one directly is naming an implementation detail.
        if (method.Accessor is { } accessed)
        {
            diagnostics.Error("SL0398", member.Span,
                $"'{member.Member}' is the {(method.ReturnType.IsVoid() ? "setter" : "getter")} of " +
                $"property '{namedType.Name}.{accessed.Name}'; use the property itself");
            return new BoundErrorExpression(syntax.Span);
        }

        if (!CanReach(method.IsPublic, method.IsProtected, method.ContainingType ?? namedType))
        {
            diagnostics.Error("SL0257", member.Span,
                NotVisible(method.ContainingType ?? namedType, member.Member, method.IsProtected));
            return new BoundErrorExpression(syntax.Span);
        }

        // A struct method takes its receiver by pointer. A temporary is fine: the
        // emitter puts it in a slot first, and anything the method writes back is
        // discarded, exactly as it is in C#.
        if (namedType is StructTypeSymbol)
            receiver = new BoundAddressOf(member.Span, new PointerTypeSymbol(namedType), receiver);

        return BuildCall(syntax, method, receiver, arguments,
            nonVirtual: member.Target is BaseSyntax);
    }

    /// <summary>
    /// Lowers <c>value.HasFlag(f)</c> to <c>(value &amp; f) == f</c>.
    ///
    /// The flag is named twice by the lowering, so it has to be something that
    /// can be read twice. In practice it is always a member of the enum.
    /// </summary>
    private BoundExpression BindHasFlag(
        CallSyntax syntax, MemberAccessSyntax member, BoundExpression receiver,
        EnumTypeSymbol enumType, List<BoundExpression> arguments)
    {
        if (!IsFlags(enumType))
        {
            diagnostics.Error("SL0408", member.Span,
                $"'{enumType.Name}' is a choice among alternatives, so it holds one value " +
                "rather than a set of them; mark it '[Flags]' if its members are meant to combine");
            return new BoundErrorExpression(syntax.Span);
        }

        if (arguments.Count != 1)
        {
            diagnostics.Error("SL0409", syntax.Span,
                $"'HasFlag' takes one '{enumType.Name}', but {Given(arguments.Count)}");
            return new BoundErrorExpression(syntax.Span);
        }

        var flag = arguments[0];
        if (!flag.Type.Equals(enumType))
        {
            if (!flag.Type.IsError())
                diagnostics.Error("SL0409", syntax.Arguments[0].Span,
                    $"'HasFlag' takes one '{enumType.Name}', but this is '{flag.Type.Name}'");
            return new BoundErrorExpression(syntax.Span);
        }

        if (!IsRepeatable(flag))
        {
            diagnostics.Error("SL0410", syntax.Arguments[0].Span,
                "the flag is tested against itself, so it is read twice; " +
                "put this in a variable first");
            return new BoundErrorExpression(syntax.Span);
        }

        var masked = new BoundBinary(syntax.Span, enumType, receiver, BoundBinaryOp.BitAnd, flag);
        return new BoundBinary(
            syntax.Span, PrimitiveTypeSymbol.Bool, masked, BoundBinaryOp.Equal, flag);
    }

    /// <summary>
    /// Binds <c>CompareTo</c>, <c>EqualTo</c> and <c>HashCode</c> on a type that
    /// implements them without saying so, or returns null when this is an
    /// ordinary call.
    ///
    /// Each lowers to something that already exists: equality to the <c>==</c>
    /// the binder knows for that type, and the other two to a runtime call. A
    /// declared member always wins, because this runs only after lookup on a
    /// named type has failed.
    /// </summary>
    private BoundExpression? TryBindIntrinsicMember(
        CallSyntax syntax, MemberAccessSyntax member, BoundExpression receiver,
        List<BoundExpression> arguments)
    {
        var type = receiver.Type;
        if (!HasIntrinsicMembers(type)) return null;
        if (type is NamedTypeSymbol named && named.FindMethod(member.Member) is not null) return null;

        int wanted = member.Member == "HashCode" ? 0 : 1;
        if (member.Member is not ("CompareTo" or "EqualTo" or "HashCode")) return null;

        if (arguments.Count != wanted)
        {
            diagnostics.Error("SL0412", syntax.Span,
                $"'{type.Name}.{member.Member}' takes {wanted} " +
                $"argument{(wanted == 1 ? "" : "s")}, but {Given(arguments.Count)}");
            return new BoundErrorExpression(syntax.Span);
        }

        if (member.Member == "HashCode")
            return new BoundCall(syntax.Span, HashFor(type), null, [Widen(receiver, HashFor(type))]);

        var other = BindConversion(arguments[0], type, syntax.Arguments[0].Span);
        if (other.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        // Equality is the operator, which already knows how to compare a String
        // and how to compare an enum.
        if (member.Member == "EqualTo")
            return BindBinaryOperation(
                syntax.Span, receiver, BoundBinaryOp.Equal, other, TokenKind.EqualsEquals);

        var compare = CompareFor(type);
        return new BoundCall(
            syntax.Span, compare, null, [Widen(receiver, compare), Widen(other, compare)]);
    }

    /// <summary>The runtime comparison that orders values of this type.</summary>
    private FunctionSymbol CompareFor(TypeSymbol type) => type switch
    {
        _ when _builtins.IsString(type) => _builtins.CompareText,
        PrimitiveTypeSymbol { IsFloat: true } => _builtins.CompareDouble,
        PrimitiveTypeSymbol { IsSigned: true } => _builtins.CompareLong,
        EnumTypeSymbol { UnderlyingType.IsSigned: true } => _builtins.CompareLong,
        _ => _builtins.CompareULong,
    };

    private FunctionSymbol HashFor(TypeSymbol type) => type switch
    {
        _ when _builtins.IsString(type) => _builtins.HashText,
        PrimitiveTypeSymbol { IsFloat: true } => _builtins.HashDouble,
        _ => _builtins.HashInteger,
    };

    /// <summary>
    /// Widens a value to the parameter the runtime call takes. Written directly
    /// rather than through <see cref="BindConversion"/> because an enum does not
    /// convert implicitly to its integer, and here the compiler is the one
    /// asking rather than the programmer.
    /// </summary>
    private BoundExpression Widen(BoundExpression value, FunctionSymbol target)
    {
        var wanted = target.Parameters[0].Type;
        if (value.Type.Equals(wanted)) return value;
        if (_builtins.IsString(value.Type)) return value;

        var kind = value.Type switch
        {
            PrimitiveTypeSymbol { Kind: PrimitiveKind.Bool } => ConversionKind.BoolToInteger,
            PrimitiveTypeSymbol { IsFloat: true } => ConversionKind.FloatResize,
            _ => ConversionKind.IntegerWiden,
        };

        return new BoundConversion(value.Span, wanted, value, kind);
    }

    private List<FunctionSymbol> ResolveFunctionCandidates(QualifiedName name)
    {
        if (name.Parts.Count == 1)
        {
            var local = _currentModule!.FindFunctions(name.Parts[0]).ToList();
            if (local.Count > 0) return local;

            return _currentScope!.Imports.Values.Distinct()
                .SelectMany(m => m.FindFunctions(name.Parts[0]))
                .Where(f => f.IsPublic)
                .ToList();
        }

        // Qualified: everything before the last part names a module.
        string moduleName = string.Join('.', name.Parts.Take(name.Parts.Count - 1));
        if (_currentScope!.Imports.TryGetValue(moduleName, out var module) ||
            _modules.TryGetValue(moduleName, out module))
        {
            bool sameModule = module == _currentModule;
            return module.FindFunctions(name.Last).Where(f => sameModule || f.IsPublic).ToList();
        }

        return [];
    }

    private BoundExpression BindFunctionCall(
        CallSyntax syntax, List<FunctionSymbol> candidates, string name, List<BoundExpression> arguments)
    {
        if (candidates.Count == 0)
        {
            diagnostics.Error("SL0259", syntax.Span, $"no function named '{name}' is in scope");
            return new BoundErrorExpression(syntax.Span);
        }

        var function = ResolveOverload(candidates, arguments, syntax.Span, name);
        if (function is null) return new BoundErrorExpression(syntax.Span);

        return BuildCall(syntax, function, receiver: null, arguments);
    }

    private BoundExpression BuildCall(
        CallSyntax syntax, FunctionSymbol function, BoundExpression? receiver,
        List<BoundExpression> arguments, bool nonVirtual = false)
    {
        int expected = function.Parameters.Count(p => !p.IsThis);
        bool countOk = function.IsVariadic ? arguments.Count >= expected : arguments.Count == expected;

        if (!countOk)
        {
            diagnostics.Error("SL0260", syntax.Span,
                $"'{function.Name}' takes {expected}{(function.IsVariadic ? " or more" : "")} " +
                $"argument{(expected == 1 ? "" : "s")}, but {Given(arguments.Count)}");
            return new BoundErrorExpression(syntax.Span);
        }

        var converted = ConvertArguments(function, arguments, syntax.Arguments);
        return new BoundCall(syntax.Span, function, receiver, converted)
            { IsNonVirtual = nonVirtual };
    }

    private List<BoundExpression> ConvertArguments(
        FunctionSymbol function, List<BoundExpression> arguments, IReadOnlyList<ExpressionSyntax> syntax)
    {
        var parameters = function.Parameters.Where(p => !p.IsThis).ToList();
        var result = new List<BoundExpression>(arguments.Count);

        for (int i = 0; i < arguments.Count; i++)
        {
            var span = i < syntax.Count ? syntax[i].Span : arguments[i].Span;

            if (i >= parameters.Count)
            {
                result.Add(PromoteVariadic(arguments[i]));   // C varargs promotions
                continue;
            }

            result.Add(ConvertArgument(arguments[i], parameters[i], span));
        }

        return result;
    }

    /// <summary>
    /// One argument, converted for the parameter it is going to.
    ///
    /// A <c>ref</c> argument is already the address the callee wants and is
    /// deliberately not converted: the callee writes back through it, and a
    /// conversion would leave the result nowhere to go. An <c>in</c> argument is
    /// converted like a value one and then has its address taken here, because
    /// nothing at the call site said to; a value with no storage of its own gets
    /// a temporary, which lives as long as the frame does.
    /// </summary>
    private BoundExpression ConvertArgument(
        BoundExpression argument, ParameterSymbol parameter, SourceSpan span)
    {
        if (parameter.Mode == ParameterMode.Ref) return argument;

        var value = BindConversion(argument, parameter.Type, span);

        return parameter.Mode == ParameterMode.In && !value.Type.IsError()
            ? new BoundAddressOf(span, new PointerTypeSymbol(parameter.Type), value)
            : value;
    }

    /// <summary>C's default argument promotions: float widens to double, small ints to int.</summary>
    private BoundExpression PromoteVariadic(BoundExpression argument)
    {
        // A C variadic function has no declared parameter type to convert
        // against, so the String-to-bytes decision has to be made here instead.
        if (argument is BoundStringLiteral)
            return new BoundConversion(argument.Span, new PointerTypeSymbol(PrimitiveTypeSymbol.Byte),
                argument, ConversionKind.StringLiteralToPointer);

        if (_builtins.IsString(argument.Type))
        {
            diagnostics.Error("SL0294", argument.Span,
                "pass ToPointer() when giving a String to a C variadic function such as printf; " +
                "the String itself is an object, not a byte pointer");
            return new BoundErrorExpression(argument.Span);
        }

        if (argument.Type is PrimitiveTypeSymbol { Kind: PrimitiveKind.Float })
            return new BoundConversion(
                argument.Span, PrimitiveTypeSymbol.Double, argument, ConversionKind.FloatResize);

        if (argument.Type is PrimitiveTypeSymbol { IsInteger: true, Size: < 4 } or
            PrimitiveTypeSymbol { Kind: PrimitiveKind.Bool })
            return new BoundConversion(
                argument.Span, PrimitiveTypeSymbol.Int, argument, ConversionKind.IntegerWiden);

        return argument;
    }

    /// <summary>
    /// Explains why one argument does not fit, preferring the specific advice
    /// over the generic type mismatch when there is some.
    /// </summary>
    private void ReportArgumentMismatch(
        string name, int index, BoundExpression argument, TypeSymbol target)
    {
        if (_builtins.IsString(argument.Type) && IsBytePointer(target))
        {
            diagnostics.Error("SL0293", argument.Span,
                $"argument {index + 1} of '{name}' expects 'byte*'; a String does not convert to " +
                "one on its own. Call ToPointer() to hand its bytes to C, and keep the String " +
                "alive for as long as C holds the pointer");
            return;
        }

        diagnostics.Error("SL0262", argument.Span,
            $"argument {index + 1} of '{name}' expects '{target.Name}', " +
            $"but '{argument.Type.Name}' was given");
    }

    /// <summary>
    /// Whether <paramref name="argument"/> can be passed where
    /// <paramref name="target"/> is expected. This is expression-aware, not just
    /// type-aware: a string literal converts to <c>byte*</c> and a String
    /// variable does not, and overload resolution has to agree with
    /// <see cref="BindConversion"/> about that.
    /// </summary>
    private bool IsImplicitlyConvertible(BoundExpression argument, TypeSymbol target)
    {
        // A bare function name fits a delegate when one of its overloads has
        // that exact signature. The delegate is the only context a bare name
        // has, which is also how the overload gets chosen.
        if (argument is BoundFunctionGroup group)
            return target is DelegateTypeSymbol wanted && group.Candidates.Any(wanted.Accepts);

        if (argument is BoundLambda lambda)
            return target switch
            {
                DelegateTypeSymbol signature => signature.Signature.Count == lambda.Syntax.Parameters.Count,
                InterfaceTypeSymbol functional => SingleMethodOf(functional) is { } only &&
                    only.Parameters.Count(p => !p.IsThis) == lambda.Syntax.Parameters.Count,
                _ => false,
            };

        // A bare case name fits a variant with that case, on the same terms a
        // lambda fits an interface: the parameter is the only thing that says
        // which variant was meant, and the arity is what can be checked before
        // the arguments are converted against the fields.
        if (argument is BoundVariantDraft draft)
            return target is VariantTypeSymbol variant &&
                   variant.FindCase(draft.Case) is { } named &&
                   named.Fields.Count == draft.Arguments.Count;

        if (IsBytePointer(target))
        {
            if (argument is BoundStringLiteral) return true;
            if (_builtins.IsString(argument.Type)) return false;
        }

        if (ConstantFits(argument, target)) return true;

        return ClassifyConversion(argument.Type, target, explicitCast: false) is not null;
    }

    /// <summary>
    /// Whether an argument may be given to a parameter, mode and all.
    ///
    /// A <c>ref</c> parameter takes only an argument that said <c>ref</c>, and
    /// takes it at exactly its own type: the callee writes back through it, so
    /// a conversion on the way in would be a write to something the caller never
    /// named. An <c>in</c> parameter converts like a value one, because what it
    /// receives may be a temporary and a temporary may be converted.
    /// </summary>
    private bool ArgumentFits(BoundExpression argument, ParameterSymbol parameter)
    {
        // Already reported. Saying the mode is wrong as well would bury the
        // diagnostic that actually explains what happened.
        if (argument.Type.IsError()) return true;

        bool given = argument is BoundAddressOf { FromRefKeyword: true };

        if (parameter.Mode == ParameterMode.Ref)
            return given &&
                   ((BoundAddressOf)argument).Operand.Type.Equals(parameter.Type);

        return !given && IsImplicitlyConvertible(argument, parameter.Type);
    }

    /// <summary>
    /// Reports why an argument did not fit: the mode first, because a type
    /// mismatch reported against a 'ref' that should not be there reads as a
    /// puzzle rather than a mistake.
    /// </summary>
    private void ReportArgumentMode(
        string name, int index, BoundExpression argument, ParameterSymbol parameter)
    {
        bool given = argument is BoundAddressOf { FromRefKeyword: true };

        if (parameter.Mode == ParameterMode.Ref && !given)
        {
            diagnostics.Error("SL0445", argument.Span,
                $"argument {index + 1} of '{name}' is 'ref {parameter.Type.Name} " +
                $"{parameter.Name}', so the call must say so too: write " +
                "'ref' before it");
            return;
        }

        if (parameter.Mode != ParameterMode.Ref && given)
        {
            diagnostics.Error("SL0446", argument.Span,
                $"argument {index + 1} of '{name}' is " +
                (parameter.Mode == ParameterMode.In
                    ? $"'in {parameter.Type.Name} {parameter.Name}', which the callee promises " +
                      "not to write, so it is not passed with 'ref'"
                    : $"'{parameter.Type.Name} {parameter.Name}', which is passed by value; " +
                      "drop the 'ref'"));
            return;
        }

        var actual = argument is BoundAddressOf { FromRefKeyword: true, Operand: { } inner }
            ? inner
            : argument;

        if (parameter.Mode == ParameterMode.Ref)
        {
            diagnostics.Error("SL0447", argument.Span,
                $"argument {index + 1} of '{name}' is 'ref {parameter.Type.Name}', and this is " +
                $"'{actual.Type.Name}'. A 'ref' argument is not converted, because the callee " +
                "writes back through it and there would be nowhere for the result to go");
            return;
        }

        ReportArgumentMismatch(name, index, argument, parameter.Type);
    }

    /// <summary>Whether one candidate could take these arguments.</summary>
    private bool AcceptsArguments(FunctionSymbol candidate, List<BoundExpression> arguments)
    {
        int expected = candidate.Parameters.Count(p => !p.IsThis);
        if (candidate.IsVariadic ? arguments.Count < expected : arguments.Count != expected)
            return false;

        var parameters = candidate.Parameters.Where(p => !p.IsThis).ToList();
        for (int i = 0; i < parameters.Count; i++)
            if (!ArgumentFits(arguments[i], parameters[i]))
                return false;

        return true;
    }

    private FunctionSymbol? ResolveOverload(
        IReadOnlyList<FunctionSymbol> candidates, List<BoundExpression> arguments, SourceSpan span, string name)
    {
        var viable = candidates.Where(c => AcceptsArguments(c, arguments)).ToList();

        switch (viable.Count)
        {
            case 1:
                return viable[0];

            case 0:
                if (candidates.Count == 1)
                {
                    // One candidate: report the real mismatch rather than "no overload".
                    var only = candidates[0];
                    var parameters = only.Parameters.Where(p => !p.IsThis).ToList();
                    int expected = parameters.Count;

                    if (only.IsVariadic ? arguments.Count < expected : arguments.Count != expected)
                        diagnostics.Error("SL0261", span,
                            $"'{name}' takes {expected}{(only.IsVariadic ? " or more" : "")} " +
                            $"argument{(expected == 1 ? "" : "s")}, but {Given(arguments.Count)}");
                    else
                        for (int i = 0; i < parameters.Count; i++)
                            if (!ArgumentFits(arguments[i], parameters[i]))
                                ReportArgumentMode(name, i, arguments[i], parameters[i]);
                    return null;
                }

                diagnostics.Error("SL0263", span,
                    $"no overload of '{name}' accepts these {arguments.Count} argument(s)");
                return null;

            default:
                // Prefer an exact match before declaring ambiguity.
                var exact = viable.Where(candidate =>
                {
                    var parameters = candidate.Parameters.Where(p => !p.IsThis).ToList();
                    return parameters.Count == arguments.Count &&
                           parameters.Zip(arguments).All(pair => pair.First.Type.Equals(pair.Second.Type));
                }).ToList();

                if (exact.Count == 1) return exact[0];

                diagnostics.Error("SL0264", span, $"the call to '{name}' is ambiguous");
                return null;
        }
    }

    // ------------------------------------------------------------ conversions

    private BoundExpression BindConversion(BoundExpression expression, TypeSymbol target, SourceSpan span)
    {
        if (expression.Type.IsError() || target.IsError()) return expression;

        // A string literal may be handed straight to C: its bytes are static and
        // NUL-terminated, so there is no lifetime to get wrong. A String held in
        // a variable is a different matter, and must go through ToPointer().
        if (expression is BoundStringLiteral literal && IsBytePointer(target))
            return new BoundConversion(span, target, literal, ConversionKind.StringLiteralToPointer);

        // A function name becomes a delegate by naming the overload that matches.
        if (expression is BoundFunctionGroup group)
            return BindFunctionReference(group, target, span);

        // A lambda has no type until it is told what to be.
        if (expression is BoundLambda lambda)
            return BindLambda(lambda, target, span);

        // Nor has `Ok(x)`, for the same reason and by the same route.
        if (expression is BoundVariantDraft draft)
            return BindVariantSettle(draft, target, span);

        // A literal that fits simply adopts the target type; there is nothing to
        // convert at run time.
        if (ConstantFits(expression, target))
            return new BoundLiteral(span, target, ((BoundLiteral)expression).Value);

        if (_builtins.IsString(expression.Type) && IsBytePointer(target))
        {
            diagnostics.Error("SL0293", span,
                "a String does not convert to 'byte*' on its own; call ToPointer() to hand its " +
                "bytes to C, and keep the String alive for as long as C holds the pointer");
            return new BoundErrorExpression(span);
        }

        var kind = ClassifyConversion(expression.Type, target, explicitCast: false);
        if (kind is null)
        {
            string hint = ClassifyConversion(expression.Type, target, explicitCast: true) is not null
                ? $"; an explicit cast '({target.Name})' would allow it"
                : "";
            diagnostics.Error("SL0265", span,
                $"cannot convert '{expression.Type.Name}' to '{target.Name}'{hint}");
            return new BoundErrorExpression(span);
        }

        // An identity conversion still has to be recorded when the types differ,
        // as between an enum and its underlying integer: same bits, different type.
        if (kind == ConversionKind.Identity && expression.Type.Equals(target)) return expression;

        // Null adopts the target type rather than being converted at runtime.
        if (expression is BoundNullLiteral) return new BoundNullLiteral(span, target);

        return new BoundConversion(span, target, expression, kind.Value);
    }

    /// <summary>
    /// Resolves a bare function name against the delegate it is being stored in.
    /// Overloads are separated by the signature the delegate asks for, which is
    /// the only context a bare name has.
    /// </summary>
    private BoundExpression BindFunctionReference(
        BoundFunctionGroup group, TypeSymbol target, SourceSpan span)
    {
        if (target is not DelegateTypeSymbol wanted)
        {
            diagnostics.Error("SL0360", span,
                $"'{group.Name}' is a function; it converts to a delegate type, " +
                $"and '{target.Name}' is not one");
            return new BoundErrorExpression(span);
        }

        var matches = group.Candidates.Where(wanted.Accepts).ToList();

        if (matches.Count == 0)
        {
            diagnostics.Error("SL0361", span,
                $"no overload of '{group.Name}' matches delegate '{wanted.Name}', " +
                $"which is '{wanted.SignatureText}'");
            return new BoundErrorExpression(span);
        }

        if (matches.Count > 1)
        {
            diagnostics.Error("SL0362", span,
                $"'{group.Name}' is ambiguous for delegate '{wanted.Name}'");
            return new BoundErrorExpression(span);
        }

        return new BoundFunctionReference(span, wanted, matches[0]);
    }

    /// <summary>
    /// Returns how to get from <paramref name="from"/> to <paramref name="to"/>,
    /// or null when no such conversion exists.
    /// </summary>
    /// <summary>
    /// Whether an integer literal fits the target type exactly, as in C#, where
    /// <c>byte b = 200;</c> and <c>nuint n = 5;</c> need no cast because the
    /// compiler can see the value. Only a literal qualifies: anything computed
    /// still needs an explicit cast.
    /// </summary>
    private static bool ConstantFits(BoundExpression expression, TypeSymbol target)
    {
        if (expression is not BoundLiteral { Value: ulong value }) return false;
        if (expression.Type is not PrimitiveTypeSymbol { IsInteger: true }) return false;
        if (target is not PrimitiveTypeSymbol { IsInteger: true } integer) return false;

        ulong maximum = integer.Size >= 8
            ? (integer.IsSigned ? long.MaxValue : ulong.MaxValue)
            : (1UL << (integer.Bits - (integer.IsSigned ? 1 : 0))) - 1;

        return value <= maximum;
    }

    /// <summary>True for <c>byte*</c>, the shape C expects for text.</summary>
    private static bool IsBytePointer(TypeSymbol type) =>
        type is PointerTypeSymbol { Element: PrimitiveTypeSymbol { Kind: PrimitiveKind.Byte } };

    private ConversionKind? ClassifyConversion(TypeSymbol from, TypeSymbol to, bool explicitCast)
    {
        if (from.Equals(to)) return ConversionKind.Identity;

        // null literal -> any nullable representation. A delegate is a raw
        // function pointer, so a null one is exactly C's null callback.
        if (from is NullType)
            return to is PointerTypeSymbol or OptionalTypeSymbol or WeakTypeSymbol or DelegateTypeSymbol
                ? ConversionKind.NullToReference
                : null;

        // The whole of an array, as a slice of it.
        if (from is ArrayTypeSymbol whole && to is SliceTypeSymbol asSlice)
            return whole.Element.Equals(asSlice.Element) ? ConversionKind.ArrayToSlice : null;

        // A derived class is a base class. With single inheritance the base
        // subobject starts where the object does, so this is the same pointer
        // and emits nothing; the other direction is a check.
        if (from is ClassTypeSymbol fromDerived && to is ClassTypeSymbol toBase)
        {
            if (fromDerived.DerivesFrom(toBase)) return ConversionKind.Upcast;
            return explicitCast && toBase.DerivesFrom(fromDerived)
                ? ConversionKind.Downcast
                : null;
        }

        // A class converts to any interface it implements, and an interface to
        // any it extends. Because a reference is the same pointer either way,
        // this costs nothing at run time.
        if (from is NamedTypeSymbol { IsReferenceType: true } source2 && to is InterfaceTypeSymbol wanted)
            return source2.AllInterfaces().Contains(wanted) ? ConversionKind.ClassToInterface : null;

        if (from is ClassTypeSymbol optionalImplementer &&
            to is OptionalTypeSymbol { Element: InterfaceTypeSymbol optionalWanted })
            return optionalImplementer.Interfaces.Contains(optionalWanted)
                ? ConversionKind.ClassToInterface
                : null;

        // C -> C?  and  weak C? -> C? are reference identities at runtime, and
        // so is Derived -> Base?, which is both conversions at once and neither
        // of them any instructions.
        if (from is ClassTypeSymbol fromClass && to is OptionalTypeSymbol toOptional)
            return toOptional.Element is ClassTypeSymbol optionalBase && fromClass.DerivesFrom(optionalBase)
                ? ConversionKind.ReferenceToOptional
                : null;

        // Derived? -> Base?, for the same reason.
        if (from is OptionalTypeSymbol { Element: ClassTypeSymbol optionalDerived } &&
            to is OptionalTypeSymbol { Element: ClassTypeSymbol optionalWantedBase } &&
            optionalDerived.DerivesFrom(optionalWantedBase))
            return ConversionKind.Upcast;

        if (from is InterfaceTypeSymbol fromInterface && to is OptionalTypeSymbol toOptionalInterface)
            return fromInterface.Equals(toOptionalInterface.Element)
                ? ConversionKind.ReferenceToOptional
                : null;

        if (from is WeakTypeSymbol fromWeak && to is OptionalTypeSymbol weakTarget)
            return fromWeak.Element.Equals(weakTarget.Element) ? ConversionKind.ReferenceToOptional : null;

        // C -> weak C?  and  C? -> weak C?. This is the only way to break a
        // reference cycle, since ARC cannot collect one, so it is implicit: the
        // weak slot already says what is meant, and requiring a cast as well
        // would put punctuation between the programmer and the one escape hatch
        // they have.
        if (to is WeakTypeSymbol toWeak)
        {
            var referenced = from is OptionalTypeSymbol weakSource ? weakSource.Element : from;
            return referenced is NamedTypeSymbol { IsReferenceType: true } &&
                   referenced.Equals(toWeak.Element)
                ? ConversionKind.ReferenceToWeak
                : null;
        }

        // C? -> C discards a null check, so it must be explicit.
        if (from is OptionalTypeSymbol fromOptional && to is NamedTypeSymbol { IsReferenceType: true })
        {
            if (!explicitCast) return null;
            if (fromOptional.Element.Equals(to)) return ConversionKind.PointerCast;

            // Derived? -> Base loses the null and nothing else; Base? -> Derived
            // loses the null and checks what is left.
            return fromOptional.Element is ClassTypeSymbol optionalSource && to is ClassTypeSymbol castTarget
                ? optionalSource.DerivesFrom(castTarget) ? ConversionKind.PointerCast
                  : castTarget.DerivesFrom(optionalSource) ? ConversionKind.Downcast
                  : null
                : null;
        }

        if (from is PointerTypeSymbol && to is PointerTypeSymbol)
        {
            // Any pointer converts to byte* implicitly, mirroring C's void*.
            bool toBytePointer = to is PointerTypeSymbol { Element: PrimitiveTypeSymbol { Kind: PrimitiveKind.Byte } };
            return explicitCast || toBytePointer ? ConversionKind.PointerCast : null;
        }

        // A reference to a raw pointer, explicitly. Reflection needs it to read an
        // instance by field offset; the result is uncounted, so keep the
        // reference alive for as long as the pointer is used.
        if (from is NamedTypeSymbol { IsReferenceType: true } or ArrayTypeSymbol &&
            to is PointerTypeSymbol)
            return explicitCast ? ConversionKind.PointerCast : null;

        // And back again, which is what lets a C callback recover the object it
        // was given as context. Nothing checks that the pointer really points at
        // one of these, so the cast is an assertion by the programmer -- the same
        // bargain the other direction already makes.
        if (from is PointerTypeSymbol &&
            to is NamedTypeSymbol { IsReferenceType: true } or ArrayTypeSymbol)
            return explicitCast ? ConversionKind.PointerCast : null;

        if (from is PointerTypeSymbol && to is PrimitiveTypeSymbol { IsInteger: true, Size: 8 })
            return explicitCast ? ConversionKind.PointerToInteger : null;

        if (from is PrimitiveTypeSymbol { IsInteger: true, Size: 8 } && to is PointerTypeSymbol)
            return explicitCast ? ConversionKind.IntegerToPointer : null;

        // An enum never converts implicitly, in either direction. That is the
        // whole point of declaring one: a Level is not a byte that happens to be
        // small, and a byte is not a Level. An explicit cast is still available,
        // which is what interop and serialization need.
        if (from is EnumTypeSymbol || to is EnumTypeSymbol)
        {
            if (!explicitCast) return null;

            var fromCore = from is EnumTypeSymbol fromEnum ? fromEnum.UnderlyingType : from;
            var toCore = to is EnumTypeSymbol toEnum ? toEnum.UnderlyingType : to;

            if (fromCore is not PrimitiveTypeSymbol { IsInteger: true } ||
                toCore is not PrimitiveTypeSymbol { IsInteger: true })
                return null;

            return ClassifyConversion(fromCore, toCore, explicitCast: true);
        }

        if (from is not PrimitiveTypeSymbol source || to is not PrimitiveTypeSymbol target) return null;
        if (source.Kind == PrimitiveKind.Void || target.Kind == PrimitiveKind.Void) return null;

        if (source.Kind == PrimitiveKind.Bool)
            return target.IsInteger && explicitCast ? ConversionKind.BoolToInteger : null;
        if (target.Kind == PrimitiveKind.Bool) return null;

        if (source.IsFloat && target.IsFloat)
            return target.Size >= source.Size || explicitCast ? ConversionKind.FloatResize : null;

        if (source.IsInteger && target.IsFloat)
            return ConversionKind.IntToFloat;               // implicit, as in C#

        if (source.IsFloat && target.IsInteger)
            return explicitCast ? ConversionKind.FloatToInt : null;

        if (source.IsInteger && target.IsInteger)
        {
            if (target.Size > source.Size && (source.IsSigned == target.IsSigned || !source.IsSigned))
                return ConversionKind.IntegerWiden;
            if (target.Size == source.Size && source.IsSigned == target.IsSigned)
                return ConversionKind.Identity;
            if (!explicitCast) return null;
            return target.Size >= source.Size ? ConversionKind.IntegerWiden : ConversionKind.IntegerNarrow;
        }

        return null;
    }

    // ------------------------------------------------------------ type resolution

    /// <summary>
    /// Returns the single symbol for <c>T[]</c>, creating it on first use. One
    /// symbol per element type means one TypeInfo and one destroy hook, however
    /// many places mention the array.
    /// </summary>
    private ArrayTypeSymbol ArrayOf(TypeSymbol element)
    {
        if (_arrays.TryGetValue(element, out var existing)) return existing;
        var array = new ArrayTypeSymbol(element);
        _arrays[element] = array;
        return array;
    }

    /// <summary>
    /// <c>T[:]</c>, built once per element type.
    ///
    /// The three fields are hidden storage: a slice is reached through indexing
    /// and Length, and naming the array it came from would let a caller keep the
    /// whole of it alive on purpose and by accident alike.
    /// </summary>
    private SliceTypeSymbol SliceOf(TypeSymbol element)
    {
        if (_slices.TryGetValue(element, out var existing)) return existing;

        var slice = new SliceTypeSymbol
        {
            Element = element,
            SimpleName = element.Name + "[:]",
            ModuleName = Builtins.StandardModuleName,
        };

        slice.Fields.Add(new FieldSymbol(
            SliceTypeSymbol.ArrayFieldName, ArrayOf(element), slice, 0) { IsBackingField = true });
        slice.Fields.Add(new FieldSymbol(
            SliceTypeSymbol.OffsetFieldName, PrimitiveTypeSymbol.NUInt, slice, 1)
            { IsBackingField = true });
        slice.Fields.Add(new FieldSymbol(
            SliceTypeSymbol.LengthFieldName, PrimitiveTypeSymbol.NUInt, slice, 2)
            { IsBackingField = true });

        _slices[element] = slice;
        _structs.Add(slice);
        ComputeLayout(slice, []);
        return slice;
    }

    /// <summary>
    /// Resolves a written type, and insists it is one a value can be made of.
    ///
    /// An opaque type is the single exception, and only directly under a
    /// pointer: <c>HWND__*</c> is a pointer to something whose layout is
    /// declared elsewhere, which is the whole of what such a type is for. Doing
    /// the check here rather than at each use is what makes it complete --
    /// a field, a local, a parameter, a return type, an array element, a
    /// <c>sizeof</c> and a generic argument all arrive through this one door.
    /// </summary>
    private TypeSymbol ResolveType(TypeSyntax syntax, FileScope scope)
    {
        var resolved = ResolveTypeCore(syntax, scope);

        if (resolved is StructTypeSymbol { IsOpaque: true } opaque)
        {
            diagnostics.Error("SL0524", syntax.Span,
                $"'{opaque.Name}' is declared without a body, so its size is not known here " +
                $"and there is no value of it to have; write '{opaque.Name}*', which is what an " +
                "incomplete type is for");
            return ErrorTypeSymbol.Instance;
        }

        return resolved;
    }

    /// <summary>
    /// The resolution itself, without the completeness check. Only the pointer
    /// case calls it directly, which is exactly the exception it is making.
    /// </summary>
    private TypeSymbol ResolveTypeCore(TypeSyntax syntax, FileScope scope)
    {
        switch (syntax)
        {
            case SliceTypeSyntax sliceSyntax:
            {
                var element = ResolveType(sliceSyntax.Element, scope);
                if (element.IsError()) return element;

                if (element.IsVoid())
                {
                    diagnostics.Error("SL0451", sliceSyntax.Span,
                        "there is no slice of 'void'");
                    return ErrorTypeSymbol.Instance;
                }

                return SliceOf(element);
            }

            case ArrayTypeSyntax array:
            {
                var element = ResolveType(array.Element, scope);
                if (element.IsError()) return element;
                if (element.IsVoid())
                {
                    diagnostics.Error("SL0310", syntax.Span, "there is no array of 'void'");
                    return ErrorTypeSymbol.Instance;
                }
                return ArrayOf(element);
            }

            case FixedArrayTypeSyntax fixedArray:
                return ResolveFixedArray(fixedArray, scope);

            case PrimitiveTypeSyntax primitive:
                return PrimitiveFor(primitive.Keyword);

            case PointerTypeSyntax pointer:
            {
                // The one place an incomplete type may appear. C says the same,
                // and for the same reason: a pointer has a size whatever it
                // points at.
                var element = ResolveTypeCore(pointer.Element, scope);
                if (element.IsError()) return element;
                if (element is NamedTypeSymbol { IsReferenceType: true })
                {
                    diagnostics.Error("SL0270", syntax.Span,
                        $"'{element.Name}' is a reference type, so '{element.Name}*' is not " +
                        "allowed; it is already a managed pointer");
                    return ErrorTypeSymbol.Instance;
                }
                return new PointerTypeSymbol(element);
            }

            case NullableTypeSyntax nullable:
            {
                var element = ResolveType(nullable.Element, scope);
                if (element.IsError()) return element;
                if (element is not NamedTypeSymbol { IsReferenceType: true } referenceType)
                {
                    diagnostics.Error("SL0271", syntax.Span,
                        $"'{element.Name}?' is not valid; only class and interface references can " +
                        $"be optional (a '{element.Name}' is a value and is never null)");
                    return ErrorTypeSymbol.Instance;
                }
                return new OptionalTypeSymbol(referenceType);
            }

            case WeakTypeSyntax weak:
            {
                var element = ResolveType(weak.Element, scope);
                if (element.IsError()) return element;

                var referenced = element.AsReference();
                if (referenced is null)
                {
                    diagnostics.Error("SL0272", syntax.Span,
                        $"'weak' requires a class or interface reference, but '{element.Name}' is not one");
                    return ErrorTypeSymbol.Instance;
                }
                return new WeakTypeSymbol(referenced);
            }

            case NamedTypeSyntax named:
            {
                var resolved = ResolveNamedType(named, scope);
                if (resolved is AttributeTypeSymbol)
                {
                    diagnostics.Error("SL0345", syntax.Span,
                        $"'{resolved.Name}' is an attribute and cannot be used as a type; " +
                        $"write it as '[{resolved.Name}]' on a declaration instead");
                    return ErrorTypeSymbol.Instance;
                }
                return resolved;
            }

            default:
                return ErrorTypeSymbol.Instance;
        }
    }

    private TypeSymbol ResolveNamedType(NamedTypeSyntax syntax, FileScope scope)
    {
        var module = scope.Module;
        var parts = syntax.Name.Parts;

        // A bare name may be a type parameter of the instantiation being bound.
        if (parts.Count == 1 && syntax.TypeArguments.Count == 0 &&
            _substitution.TryGetValue(parts[0], out var substituted))
            return substituted;

        if (syntax.TypeArguments.Count > 0)
            return ResolveConstructedType(syntax, scope);

        if (parts.Count == 1)
        {
            if (module.Types.TryGetValue(parts[0], out var local)) return local;
            if (module.Aliases.TryGetValue(parts[0], out var ownAlias)) return ResolveAlias(ownAlias);

            // Naming a generic without arguments is a common slip; say so plainly.
            if (module.GenericTypes.TryGetValue(parts[0], out var template))
            {
                diagnostics.Error("SL0325", syntax.Span,
                    $"'{template.Name}' is generic and needs type arguments, " +
                    $"as in '{template.Name}<{string.Join(", ", template.Parameters)}>'");
                return ErrorTypeSymbol.Instance;
            }

            var visible = scope.Imports.Values.Distinct()
                .Where(imported => imported.Types.TryGetValue(parts[0], out var t) && t.IsPublic)
                .Select(imported => imported.Types[parts[0]])
                .Distinct()
                .ToList();

            // An imported alias is a name like any other, and is looked for only
            // when no imported type answered -- a type is the more direct thing.
            if (visible.Count == 0)
            {
                var aliases = scope.Imports.Values.Distinct()
                    .Where(i => i.Aliases.TryGetValue(parts[0], out var a) && a.IsPublic)
                    .Select(i => i.Aliases[parts[0]])
                    .Distinct()
                    .ToList();

                if (aliases.Count == 1) return ResolveAlias(aliases[0]);
                if (aliases.Count > 1)
                {
                    diagnostics.Error("SL0273", syntax.Span,
                        $"'{parts[0]}' is ambiguous between " +
                        string.Join(" and ", aliases.Select(a => $"'{a.QualifiedName}'")) +
                        "; qualify it with its module name");
                    return ErrorTypeSymbol.Instance;
                }
            }

            if (visible.Count == 1) return visible[0];
            if (visible.Count > 1)
            {
                diagnostics.Error("SL0273", syntax.Span,
                    $"'{parts[0]}' is ambiguous between " +
                    string.Join(" and ", visible.Select(t => $"'{t.QualifiedName}'")) +
                    "; qualify it with its module name");
                return ErrorTypeSymbol.Instance;
            }
        }
        else
        {
            string moduleName = string.Join('.', parts.Take(parts.Count - 1));
            if (scope.Imports.TryGetValue(moduleName, out var target) ||
                _modules.TryGetValue(moduleName, out target))
            {
                if (target.Types.TryGetValue(parts[^1], out var type))
                {
                    if (target != module && !type.IsPublic)
                    {
                        diagnostics.Error("SL0274", syntax.Span,
                            $"'{type.QualifiedName}' is not public");
                        return ErrorTypeSymbol.Instance;
                    }
                    return type;
                }

                if (target.Aliases.TryGetValue(parts[^1], out var qualifiedAlias))
                {
                    if (target != module && !qualifiedAlias.IsPublic)
                    {
                        diagnostics.Error("SL0274", syntax.Span,
                            $"'{qualifiedAlias.QualifiedName}' is not public");
                        return ErrorTypeSymbol.Instance;
                    }
                    return ResolveAlias(qualifiedAlias);
                }

                diagnostics.Error("SL0275", syntax.Span,
                    $"module '{target.Name}' does not declare a type named '{parts[^1]}'");
                return ErrorTypeSymbol.Instance;
            }
        }

        diagnostics.Error("SL0276", syntax.Span,
            $"the type '{syntax.Name.Text}' was not found; " +
            "check the spelling, or add an 'import' for the module that declares it");
        return ErrorTypeSymbol.Instance;
    }

    /// <summary>Resolves <c>Box&lt;int&gt;</c> by finding the template and instantiating it.</summary>
    private TypeSymbol ResolveConstructedType(NamedTypeSyntax syntax, FileScope scope)
    {
        var module = scope.Module;
        var arguments = syntax.TypeArguments.Select(a => ResolveType(a, scope)).ToList();
        if (arguments.Any(a => a.IsError())) return ErrorTypeSymbol.Instance;

        var template = FindGenericType(syntax.Name, scope);
        if (template is null)
        {
            diagnostics.Error("SL0326", syntax.Span,
                $"no generic type named '{syntax.Name.Text}' is in scope");
            return ErrorTypeSymbol.Instance;
        }

        return Instantiate(template, arguments, syntax.Span);
    }

    private GenericTypeTemplate? FindGenericType(QualifiedName name, FileScope scope)
    {
        var module = scope.Module;
        if (name.Parts.Count == 1)
        {
            if (module.GenericTypes.TryGetValue(name.Parts[0], out var local)) return local;

            return scope.Imports.Values.Distinct()
                .Select(m => m.GenericTypes.TryGetValue(name.Parts[0], out var t) && t.IsPublic ? t : null)
                .FirstOrDefault(t => t is not null);
        }

        string moduleName = string.Join('.', name.Parts.Take(name.Parts.Count - 1));
        if (scope.Imports.TryGetValue(moduleName, out var target) ||
            _modules.TryGetValue(moduleName, out target))
        {
            if (target.GenericTypes.TryGetValue(name.Last, out var found) &&
                (target == module || found.IsPublic))
                return found;
        }

        return null;
    }

    /// <summary>Finds a generic function template visible from the current module.</summary>
    private List<GenericFunctionTemplate> FindGenericFunctions(QualifiedName name)
    {
        if (name.Parts.Count == 1)
        {
            var local = _currentModule!.GenericFunctions.Where(f => f.Name == name.Parts[0]).ToList();
            if (local.Count > 0) return local;

            return _currentScope!.Imports.Values.Distinct()
                .SelectMany(m => m.GenericFunctions)
                .Where(f => f.Name == name.Parts[0] && f.IsPublic)
                .ToList();
        }

        string moduleName = string.Join('.', name.Parts.Take(name.Parts.Count - 1));
        if (_currentScope!.Imports.TryGetValue(moduleName, out var target) ||
            _modules.TryGetValue(moduleName, out target))
        {
            bool sameModule = target == _currentModule;
            return target.GenericFunctions
                .Where(f => f.Name == name.Last && (sameModule || f.IsPublic))
                .ToList();
        }

        return [];
    }

    /// <summary>
    /// Binds a call to a generic function by inferring its type arguments from
    /// the arguments actually passed, then instantiating it.
    /// </summary>
    private BoundExpression? TryBindGenericCall(
        CallSyntax syntax, QualifiedName name, List<BoundExpression> arguments)
    {
        var candidates = FindGenericFunctions(name);
        if (candidates.Count == 0) return null;

        var function = InferAndInstantiate(candidates, syntax, arguments);
        return function is null
            ? new BoundErrorExpression(syntax.Span)
            : BuildCall(syntax, function, receiver: null, arguments);
    }

    /// <summary>
    /// Chooses a template, infers its type arguments from the values passed, and
    /// instantiates it. Shared by generic free functions and generic methods,
    /// which differ only in whether a receiver comes along.
    /// </summary>
    private FunctionSymbol? InferAndInstantiate(
        IReadOnlyList<GenericFunctionTemplate> candidates,
        CallSyntax syntax,
        List<BoundExpression> arguments)
    {
        var viable = candidates
            .Where(c => c.Declaration.Parameters.Count == arguments.Count)
            .ToList();

        if (viable.Count == 0) viable = [candidates[0]];

        // Every candidate of the right arity is tried, and one that infers but
        // then would not accept the arguments is not a candidate. Two templates
        // may take one argument and differ in its shape -- `Sort(T[:])` and
        // `Sort(IList<T>)` do -- and picking the first would make the second
        // unreachable.
        var fitting = new List<(GenericFunctionTemplate Template, List<TypeSymbol> Arguments)>();
        Dictionary<string, TypeSymbol>? firstFailure = null;
        GenericFunctionTemplate? failed = null;

        // A candidate whose parameters were all worked out and which still would
        // not take the arguments. It is the better thing to report: the reader
        // has an argument that does not fit, not a type nobody could name.
        (GenericFunctionTemplate Template, Dictionary<string, TypeSymbol> Inferred)? nearMiss = null;

        foreach (var candidate in viable)
        {
            var names = candidate.Parameters.ToHashSet(StringComparer.Ordinal);
            var inferred = new Dictionary<string, TypeSymbol>(StringComparer.Ordinal);

            // An enclosing type's parameters are already fixed, so they are
            // given rather than inferred; only the method's own are worked out.
            foreach (var (name, type) in candidate.OuterSubstitution) inferred.TryAdd(name, type);

            int shared = Math.Min(arguments.Count, candidate.Declaration.Parameters.Count);
            for (int i = 0; i < shared; i++)
                Infer(candidate.Declaration.Parameters[i].Type, arguments[i].Type,
                    names, inferred, candidate.Scope);

            if (candidate.Parameters.Any(p => !inferred.ContainsKey(p)))
            {
                firstFailure ??= inferred;
                failed ??= candidate;
                continue;
            }

            if (Accepts(candidate, inferred, arguments))
                fitting.Add((candidate, candidate.Parameters.Select(p => inferred[p]).ToList()));
            else
                nearMiss ??= (candidate, inferred);
        }

        if (fitting.Count == 1)
            return InstantiateFunction(fitting[0].Template, fitting[0].Arguments, syntax.Span);

        if (fitting.Count > 1)
        {
            diagnostics.Error("SL0453", syntax.Span,
                $"'{candidates[0].Name}' is ambiguous here: " +
                string.Join(" and ", fitting.Select(f =>
                    $"'{f.Template.Name}<{string.Join(", ", f.Arguments.Select(a => a.Name))}>'")) +
                " both accept these arguments");
            return null;
        }

        // Everything was worked out and an argument still did not fit: say which.
        if (nearMiss is { } near)
        {
            Accepts(near.Template, near.Inferred, arguments, report: near.Template.Name);
            return null;
        }

        var template = failed ?? viable[0];
        var reported = firstFailure ?? new Dictionary<string, TypeSymbol>(StringComparer.Ordinal);
        var missing = template.Parameters.Where(p => !reported.ContainsKey(p)).ToList();

        diagnostics.Error("SL0327", syntax.Span,
            $"cannot infer {string.Join(" and ", missing.Select(m => "'" + m + "'"))} " +
            $"for '{template.Name}' from these arguments; " +
            "Stainless infers type arguments only from the values passed");
        return null;
    }

    /// <summary>
    /// Whether a template, with its parameters worked out, would take the
    /// arguments given.
    ///
    /// The parameter types are resolved under the inferred substitution rather
    /// than by instantiating: instantiating queues a body to be bound, and a
    /// candidate that loses should not leave one behind.
    /// </summary>
    private bool Accepts(
        GenericFunctionTemplate template,
        Dictionary<string, TypeSymbol> inferred,
        List<BoundExpression> arguments,
        string? report = null)
    {
        var previous = _substitution;
        _substitution = inferred;

        try
        {
            for (int i = 0; i < arguments.Count; i++)
            {
                var wanted = ResolveType(template.Declaration.Parameters[i].Type, template.Scope);
                if (wanted.IsError()) return false;
                if (IsImplicitlyConvertible(arguments[i], wanted)) continue;

                if (report is not null) ReportArgumentMismatch(report, i, arguments[i], wanted);
                return false;
            }

            return true;
        }
        finally
        {
            _substitution = previous;
        }
    }

    /// <summary>
    /// A generic method reached through a receiver. It stays a template until the
    /// arguments say what its type parameters are, so it cannot be found by the
    /// ordinary method lookup.
    /// </summary>
    private BoundExpression? TryBindGenericMethodCall(
        CallSyntax syntax, MemberAccessSyntax member, NamedTypeSymbol type,
        BoundExpression receiver, List<BoundExpression> arguments)
    {
        var candidates = type.GenericMethods.Where(m => m.Name == member.Member).ToList();
        if (candidates.Count == 0) return null;

        if (!candidates[0].IsPublic && type.ModuleName != _currentModule!.Name)
        {
            diagnostics.Error("SL0257", member.Span, $"'{type.Name}.{member.Member}' is not public");
            return new BoundErrorExpression(syntax.Span);
        }

        var function = InferAndInstantiate(candidates, syntax, arguments);
        if (function is null) return new BoundErrorExpression(syntax.Span);

        // A struct method takes its receiver by pointer, as everywhere else.
        var self = type is StructTypeSymbol
            ? new BoundAddressOf(member.Span, new PointerTypeSymbol(type), receiver)
            : receiver;

        return BuildCall(syntax, function, self, arguments);
    }

    private static PrimitiveTypeSymbol PrimitiveFor(TokenKind keyword) => keyword switch
    {
        TokenKind.VoidKeyword => PrimitiveTypeSymbol.Void,
        TokenKind.BoolKeyword => PrimitiveTypeSymbol.Bool,
        TokenKind.CharKeyword => PrimitiveTypeSymbol.Char,
        TokenKind.SByteKeyword => PrimitiveTypeSymbol.SByte,
        TokenKind.ShortKeyword => PrimitiveTypeSymbol.Short,
        TokenKind.IntKeyword => PrimitiveTypeSymbol.Int,
        TokenKind.LongKeyword => PrimitiveTypeSymbol.Long,
        TokenKind.NIntKeyword => PrimitiveTypeSymbol.NInt,
        TokenKind.ByteKeyword => PrimitiveTypeSymbol.Byte,
        TokenKind.UShortKeyword => PrimitiveTypeSymbol.UShort,
        TokenKind.UIntKeyword => PrimitiveTypeSymbol.UInt,
        TokenKind.ULongKeyword => PrimitiveTypeSymbol.ULong,
        TokenKind.NUIntKeyword => PrimitiveTypeSymbol.NUInt,
        TokenKind.FloatKeyword => PrimitiveTypeSymbol.Float,
        _ => PrimitiveTypeSymbol.Double,
    };

    // ------------------------------------------------------------ entry point

    private FunctionSymbol? FindEntryPoint()
    {
        var candidates = _modules.Values
            .SelectMany(m => m.Functions)
            .Where(f => f.Name == "Main" && f.ContainingType is null && f.HasBody)
            .ToList();

        if (candidates.Count == 0) return null;

        if (candidates.Count > 1)
        {
            diagnostics.Error("SL0280", candidates[1].Span,
                "more than one 'Main' was found: " +
                string.Join(", ", candidates.Select(c => c.ModuleName + ".Main")));
            return candidates[0];
        }

        var entry = candidates[0];
        bool returnsInt = entry.ReturnType is PrimitiveTypeSymbol { Kind: PrimitiveKind.Int };
        if (!returnsInt && !entry.ReturnType.IsVoid())
            diagnostics.Error("SL0281", entry.Span,
                $"'Main' must return 'int' or 'void', not '{entry.ReturnType.Name}'");

        if (entry.Parameters.Count > 0)
            diagnostics.Error("SL0282", entry.Span,
                "'Main' cannot take parameters yet");

        return entry;
    }
}

/// <summary>
/// The type of the <c>null</c> literal before it adopts a target type. It never
/// appears in a declaration, only briefly during binding.
/// </summary>


/// <summary>Finds the statics an initializer reads, so they can be ordered first.</summary>
internal sealed class StaticReferenceWalker
{
    public HashSet<StaticSymbol> Found { get; } = [];

    public void Visit(BoundExpression? expression)
    {
        switch (expression)
        {
            case null: return;

            case BoundStaticAccess access: Found.Add(access.Static); break;

            case BoundFieldAccess field: Visit(field.Receiver); break;

            case BoundCall call:
                Visit(call.Receiver);
                foreach (var argument in call.Arguments) Visit(argument);
                break;

            case BoundIndirectCall call:
                Visit(call.Target);
                foreach (var argument in call.Arguments) Visit(argument);
                break;

            case BoundUnary unary: Visit(unary.Operand); break;
            case BoundBinary binary: Visit(binary.Left); Visit(binary.Right); break;

            case BoundConditional conditional:
                Visit(conditional.Condition);
                Visit(conditional.WhenTrue);
                Visit(conditional.WhenFalse);
                break;

            case BoundAssignment assignment: Visit(assignment.Target); Visit(assignment.Value); break;

            case BoundPropertyAssignment written:
                Visit(written.Receiver); Visit(written.Value);
                break;

            case BoundConversion conversion: Visit(conversion.Operand); break;
            case BoundTypeTest test: Visit(test.Value); break;

            case BoundNew created:
                foreach (var argument in created.Arguments) Visit(argument);
                break;

            case BoundDereference dereference: Visit(dereference.Operand); break;
            case BoundAddressOf address: Visit(address.Operand); break;
            case BoundNewArray array: Visit(array.Length); break;
            case BoundArrayLength length: Visit(length.Array); break;
            case BoundIndex index: Visit(index.Target); Visit(index.Index); break;
        }
    }
}

/// <summary>
/// Finds what a <c>parallel for</c> body reaches outside itself.
///
/// Anything declared within the body belongs to one iteration and is ignored.
/// Everything else is captured by address, so the chunks share the parent's
/// storage rather than a copy — which is the point for an array being written
/// through, and a race for a variable being assigned. Assignments are collected
/// separately so the binder can reject exactly those.
/// </summary>
internal sealed class CaptureWalker(LocalSymbol loopVariable)
{
    private readonly HashSet<object> _declared = [loopVariable];
    private readonly HashSet<object> _seen = [];
    private readonly List<object> _captures = [];

    public IReadOnlyList<object> Captures => _captures;

    public List<(object Symbol, SourceSpan Span, string Name)> Assignments { get; } = [];

    private void Capture(object symbol)
    {
        if (_declared.Contains(symbol) || !_seen.Add(symbol)) return;
        _captures.Add(symbol);
    }

    private void Assigned(BoundExpression target)
    {
        switch (target)
        {
            case BoundLocalAccess local when !_declared.Contains(local.Local):
                Assignments.Add((local.Local, local.Span, local.Local.Name));
                break;

            case BoundParameterAccess parameter when !_declared.Contains(parameter.Parameter):
                Assignments.Add((parameter.Parameter, parameter.Span, parameter.Parameter.Name));
                break;
        }
    }

    public void Visit(BoundStatement? statement)
    {
        switch (statement)
        {
            case null: return;

            case BoundBlock block:
                foreach (var inner in block.Statements) Visit(inner);
                break;

            case BoundLocalDeclaration declaration:
                _declared.Add(declaration.Local);
                Visit(declaration.Initializer);
                break;

            case BoundExpressionStatement expression: Visit(expression.Expression); break;

            case BoundIf branch:
                Visit(branch.Condition); Visit(branch.Then); Visit(branch.Else);
                break;

            case BoundWhile loop:
                Visit(loop.Condition); Visit(loop.Body);
                break;

            case BoundFor loop:
                foreach (var local in loop.Locals) _declared.Add(local);
                Visit(loop.Initializer); Visit(loop.Condition); Visit(loop.Step); Visit(loop.Body);
                break;

            case BoundParallel nested: Visit(nested.Body); break;

            case BoundSpawn spawn:
                Visit(spawn.Target); Visit(spawn.Call);
                break;

            case BoundParallelFor nested:
                _declared.Add(nested.Variable);
                Visit(nested.Start); Visit(nested.Limit); Visit(nested.Stride); Visit(nested.Body);
                break;

            case BoundReturn returned: Visit(returned.Value); break;
        }
    }

    public void Visit(BoundExpression? expression)
    {
        switch (expression)
        {
            case null: return;

            case BoundLocalAccess local: Capture(local.Local); break;
            case BoundParameterAccess parameter: Capture(parameter.Parameter); break;
            case BoundThis self: Capture(self.Parameter); break;

            case BoundFieldAccess field: Visit(field.Receiver); break;

            case BoundCall call:
                Visit(call.Receiver);
                foreach (var argument in call.Arguments) Visit(argument);
                break;

            case BoundIndirectCall call:
                Visit(call.Target);
                foreach (var argument in call.Arguments) Visit(argument);
                break;

            case BoundUnary unary: Visit(unary.Operand); break;

            case BoundBinary binary:
                Visit(binary.Left); Visit(binary.Right);
                break;

            case BoundConditional conditional:
                Visit(conditional.Condition);
                Visit(conditional.WhenTrue);
                Visit(conditional.WhenFalse);
                break;

            case BoundAssignment assignment:
                Assigned(assignment.Target);
                Visit(assignment.Target); Visit(assignment.Value);
                break;

            // A property write goes through a method, so it changes the object
            // rather than the captured variable naming it; only the reads count.
            case BoundPropertyAssignment written:
                Visit(written.Receiver); Visit(written.Value);
                break;

            case BoundConversion conversion: Visit(conversion.Operand); break;
            case BoundTypeTest test: Visit(test.Value); break;

            case BoundNew created:
                foreach (var argument in created.Arguments) Visit(argument);
                break;

            case BoundDereference dereference: Visit(dereference.Operand); break;
            case BoundAddressOf address: Visit(address.Operand); break;
            case BoundNewArray array: Visit(array.Length); break;
            case BoundArrayLength length: Visit(length.Array); break;

            case BoundIndex index:
                Visit(index.Target); Visit(index.Index);
                break;
        }
    }
}

/// <summary>
/// The type of a lambda before something tells it what to be. It never reaches
/// the emitter: a conversion either resolves it or reports an error.
/// </summary>
public sealed class LambdaType : TypeSymbol
{
    public static readonly LambdaType Instance = new();
    private LambdaType() { }
    public override string Name => "lambda";
    public override int Size => 8;
    public override int Alignment => 8;
}

/// <summary>
/// The type of a bare case name before something says which variant it builds.
///
/// One value cannot say what a variant's type arguments are -- <c>Ok(4)</c>
/// knows T and nothing about E -- and type arguments cannot be written at a
/// call. So construction is target-typed, exactly as a lambda is, and this is
/// the placeholder that carries the pieces until a conversion resolves it. It
/// never reaches the emitter.
/// </summary>
public sealed class VariantDraftType : TypeSymbol
{
    public static readonly VariantDraftType Instance = new();
    private VariantDraftType() { }
    public override string Name => "a variant's case";
    public override int Size => 0;
    public override int Alignment => 1;
}

/// <summary>A <c>Case(...)</c> awaiting the variant type it belongs to.</summary>
public sealed class BoundVariantDraft(
    SourceSpan span, string variantCase, IReadOnlyList<BoundExpression> arguments)
    : BoundExpression(span, VariantDraftType.Instance)
{
    public string Case { get; } = variantCase;
    public IReadOnlyList<BoundExpression> Arguments { get; } = arguments;
}

/// <summary>
/// The type of a bare function name before a delegate gives it one. It never
/// reaches the emitter: a conversion either resolves it or reports an error.
/// </summary>
public sealed class FunctionGroupType : TypeSymbol
{
    public static readonly FunctionGroupType Instance = new();
    private FunctionGroupType() { }
    public override string Name => "function";
    public override int Size => 8;
    public override int Alignment => 8;
}

public sealed class NullType : TypeSymbol
{
    public static readonly NullType Instance = new();
    private NullType() { }
    public override string Name => "null";
    public override int Size => 8;
    public override int Alignment => 8;
}
