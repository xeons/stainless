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
public sealed class Binder(DiagnosticBag diagnostics, bool requireEntryPoint = true)
{
    private readonly Builtins _builtins = new();
    private readonly Dictionary<string, ModuleSymbol> _modules = new(StringComparer.Ordinal);
    private readonly List<(FileScope Scope, CompilationUnitSyntax Unit)> _units = [];
    private readonly List<BoundFunction> _functions = [];
    private readonly List<ClassTypeSymbol> _classes = [];
    private readonly List<InterfaceTypeSymbol> _interfaces = [];
    private readonly Dictionary<TypeSymbol, ArrayTypeSymbol> _arrays = [];

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

        DeclareModules(units);      // pass 1: every module exists
        DeclareTypes();             // pass 2: every type name exists
        ResolveImports();           // pass 3: every module can see its imports
        DeclareMembers();           // pass 4: every signature and field type is resolved
        ResolveInterfaces();        // pass 5: every class satisfies what it claims
        ResolveAttributes();        // pass 6: attributes fold to constants
        ComputeLayouts();           // pass 7: every value type has a size
        BindBodies();               // pass 8: only now is any code checked
        BindStatics();              // pass 9: static initializers, then their order
        DrainPending();             // pass 10: bodies of everything instantiated along the way

        // Interface ids are assigned last, because instantiating a generic can
        // introduce a new interface at any point up to here.
        for (int id = 0; id < _interfaces.Count; id++) _interfaces[id].Id = id;

        var external = _modules.Values
            .SelectMany(m => m.Functions)
            .Where(f => f.Linkage == LinkageKind.ExternC)
            .GroupBy(f => f.MangledName)
            .Select(g => g.First())
            .ToList();

        return new BoundProgram
        {
            Modules = _modules.Values.ToList(),
            Functions = _functions,
            Classes = _classes,
            Interfaces = _interfaces,
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
                    if (module.GenericTypes.ContainsKey(declaration.Name))
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
                    },
                    TypeDeclKind.Interface => new InterfaceTypeSymbol
                    {
                        SimpleName = declaration.Name,
                        ModuleName = module.Name,
                        IsPublic = isPublic,
                    },
                    TypeDeclKind.Attribute => new AttributeTypeSymbol
                    {
                        SimpleName = declaration.Name,
                        ModuleName = module.Name,
                        IsPublic = isPublic,
                    },
                    _ => new StructTypeSymbol
                    {
                        SimpleName = declaration.Name,
                        ModuleName = module.Name,
                        IsPublic = isPublic,
                    },
                };

                module.Types[declaration.Name] = type;
                _typeSyntax[type] = (declaration, scope);

                if (type is ClassTypeSymbol { IsIntrinsic: false } classType) _classes.Add(classType);
                if (type is InterfaceTypeSymbol interfaceType) _interfaces.Add(interfaceType);
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
                };

                module.Types[declaration.Name] = enumType;
                _enumSyntax[enumType] = (declaration, scope);
            }
        }
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

            type.Signature.Add(new ParameterSymbol(parameter.Name, parameterType, i));
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

    private void DeclareTypeMembers(
        FileScope scope, TypeDeclSyntax declaration, NamedTypeSymbol type)
    {
        var module = scope.Module;
        var classType = type as ClassTypeSymbol;

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

                    // A struct is a plain C value: it is copied without any hook, so it
                    // cannot own a reference count. Keeping that rule is what lets a
                    // Stainless struct stay bit-identical to a C struct.
                    if (type is StructTypeSymbol && (fieldType.NeedsArc() || fieldType is WeakTypeSymbol))
                        diagnostics.Error("SL0283", field.Span,
                            $"struct '{type.Name}' cannot hold '{fieldType.Name}', because structs are " +
                            "copied as raw bytes and cannot maintain a reference count; " +
                            $"make '{type.Name}' a class, or store a raw pointer instead");

                    type.Fields.Add(new FieldSymbol(field.Name, fieldType, type, type.Fields.Count)
                    {
                        IsPublic = field.Modifiers.HasFlag(Modifiers.Public),
                    });
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
        bool wantsStorage = false;

        if (isInterface)
        {
            foreach (var accessor in declaration.Accessors.Where(a => a.Body is not null))
                diagnostics.Error("SL0392", accessor.Span,
                    $"'{type.Name}.{declaration.Name}' is an interface property, so its " +
                    $"{(accessor.IsGetter ? "getter" : "setter")} cannot have a body; " +
                    "interfaces declare signatures only");
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
            // The same rule a plain field obeys, for the same reason: a struct is
            // copied as raw bytes and has nowhere to keep a reference count.
            if (type is StructTypeSymbol &&
                (propertyType.NeedsArc() || propertyType is WeakTypeSymbol))
            {
                diagnostics.Error("SL0283", declaration.Span,
                    $"struct '{type.Name}' cannot hold '{propertyType.Name}', and the automatic " +
                    $"property '{declaration.Name}' would make it; structs are copied as raw " +
                    "bytes and cannot maintain a reference count");
            }

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
            BackingField = backing,
        };

        property.Getter = DeclareAccessor(scope, type, property, getter, isSetter: false);
        if (setter is not null)
            property.Setter = DeclareAccessor(scope, type, property, setter, isSetter: true);

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
        AccessorSyntax accessor, bool isSetter)
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
            Body = accessor.Body,
            Span = accessor.Span,
            Scope = scope,
            Accessor = property,
            IsAutoAccessor = accessor.Body is null && type is not InterfaceTypeSymbol,
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

        if (containingType is InterfaceTypeSymbol)
        {
            if (declaration.Body is not null)
                diagnostics.Error("SL0301", declaration.Span,
                    $"'{declaration.Name}' is an interface method and cannot have a body; " +
                    "interfaces declare signatures only");
        }
        else if (declaration.Linkage != LinkageKind.ExternC && declaration.Body is null)
        {
            diagnostics.Error("SL0210", declaration.Span,
                $"'{declaration.Name}' has no body; Stainless has no forward declarations, " +
                "because declaration order never matters");
        }

        if (containingType is not null)
        {
            if (containingType.FindMethod(declaration.Name) is not null)
                diagnostics.Error("SL0211", declaration.Span,
                    $"'{containingType.Name}' already declares a method named '{declaration.Name}'; " +
                    "overloading is not supported yet");
            containingType.Methods.Add(symbol);
        }

        module.Functions.Add(symbol);
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

            symbol.Parameters.Add(new ParameterSymbol(parameter.Name, type, symbol.Parameters.Count));
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

        // Module constants must fold at compile time, so only literals are allowed for now.
        object? value = null;
        TypeSymbol type = declaration.Type is null
            ? PrimitiveTypeSymbol.Int
            : ResolveType(declaration.Type, scope);

        if (declaration.Value is LiteralSyntax literal)
        {
            value = literal.Value;
            if (declaration.Type is null)
                type = literal.Kind switch
                {
                    TokenKind.FloatLiteral => PrimitiveTypeSymbol.Double,
                    TokenKind.TrueKeyword or TokenKind.FalseKeyword => PrimitiveTypeSymbol.Bool,
                    TokenKind.CharLiteral => PrimitiveTypeSymbol.Char,
                    _ => PrimitiveTypeSymbol.Int,
                };
        }
        else
        {
            diagnostics.Error("SL0215", declaration.Value.Span,
                "a module-level 'const' must be initialized with a literal");
        }

        module.Constants[declaration.Name] = new ConstantSymbol(declaration.Name, type, value)
        {
            IsPublic = declaration.Modifiers.HasFlag(Modifiers.Public),
        };
    }

    // ============================================================ pass 5

    /// <summary>
    /// Resolves each class's declared interfaces and checks that it really
    /// implements them, then numbers the interfaces for dispatch.
    ///
    /// Ids are assigned across the whole program, which is what lets a class's
    /// dispatch table be indexed directly instead of searched.
    /// </summary>
    private void ResolveInterfaces()
    {
        foreach (var (type, entry) in _typeSyntax.Where(e => e.Key is InterfaceTypeSymbol))
            ResolveImplements(type, entry.Declaration, entry.Scope);

        foreach (var (type, entry) in _typeSyntax.Where(e => e.Key is not InterfaceTypeSymbol))
            ResolveImplements(type, entry.Declaration, entry.Scope);
    }

    private void ResolveImplements(
        NamedTypeSymbol type, TypeDeclSyntax declaration, FileScope scope)
    {
        {
            if (declaration.Implements.Count == 0) return;

            if (type is StructTypeSymbol)
            {
                diagnostics.Error("SL0302", declaration.Span,
                    $"struct '{type.Name}' cannot implement an interface; an interface " +
                    "reference is a counted pointer, and structs are plain C values");
                return;
            }

            foreach (var implemented in declaration.Implements)
            {
                var resolved = ResolveType(implemented, scope);
                if (resolved.IsError()) continue;

                if (resolved is not InterfaceTypeSymbol interfaceType)
                {
                    diagnostics.Error("SL0303", implemented.Span,
                        $"'{resolved.Name}' is not an interface, so '{type.Name}' cannot " +
                        (type is InterfaceTypeSymbol ? "extend" : "implement") +
                        " it; Stainless has no class inheritance");
                    continue;
                }

                if (type.Interfaces.Contains(interfaceType))
                {
                    diagnostics.Warning("SL0304", implemented.Span,
                        $"'{type.Name}' already lists '{interfaceType.Name}'");
                    continue;
                }

                if (interfaceType == type || interfaceType.AllInterfaces().Contains(type))
                {
                    diagnostics.Error("SL0333", implemented.Span,
                        $"'{type.Name}' and '{interfaceType.Name}' extend each other");
                    continue;
                }

                type.Interfaces.Add(interfaceType);

                // Only a class has to supply implementations. An interface
                // extending another merely widens its own contract.
                if (type is ClassTypeSymbol classType)
                    VerifyImplements(classType, interfaceType, implemented.Span);
            }
        }

    }

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
                if (type is ClassTypeSymbol or StructTypeSymbol) type.IsReflected = true;
                else
                    diagnostics.Error("SL0341", entry.Declaration.Span,
                        $"'[Reflect]' applies to a class or a struct; '{type.Name}' is neither");
            }

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
                    $"but {attribute.Arguments.Count} were given");
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
            var found = classType.FindMethod(required.Name);

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

            var wanted = required.Parameters.Where(p => !p.IsThis).Select(p => p.Type).ToList();
            var actual = found.Parameters.Where(p => !p.IsThis).Select(p => p.Type).ToList();

            if (!found.ReturnType.Equals(required.ReturnType) ||
                wanted.Count != actual.Count ||
                !wanted.Zip(actual).All(pair => pair.First.Equals(pair.Second)))
            {
                diagnostics.Error("SL0307", found.Span,
                    $"'{classType.Name}.{found.Name}' does not match " +
                    $"'{interfaceType.Name}.{required.Name}'; expected " +
                    $"'{required.ReturnType.Name} {required.Name}(" +
                    string.Join(", ", wanted.Select(t => t.Name)) + ")'");
            }
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

        int offset = 0, alignment = 1;
        foreach (var field in type.Fields)
        {
            // Only a struct field forces its type to be laid out first.
            if (field.Type is StructTypeSymbol nested)
                ComputeLayout(nested, inProgress);

            int fieldAlignment = Math.Max(1, field.Type.Alignment);
            offset = TypeExtensions.AlignTo(offset, fieldAlignment);
            field.Offset = offset;
            offset += field.Type.Size;
            alignment = Math.Max(alignment, fieldAlignment);
        }

        type.SetLayout(TypeExtensions.AlignTo(offset, alignment), alignment);
        inProgress.Remove(type);
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
                $"but {arguments.Count} were given");
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
                Template = template, TypeArguments = arguments,
            },
            TypeDeclKind.Interface => new InterfaceTypeSymbol
            {
                SimpleName = displayName, ModuleName = template.Module.Name, IsPublic = isPublic,
                Template = template, TypeArguments = arguments,
            },
            _ => new StructTypeSymbol
            {
                SimpleName = displayName, ModuleName = template.Module.Name, IsPublic = isPublic,
                Template = template, TypeArguments = arguments,
            },
        };

        // Registered before its members are declared, so a self-referential
        // template such as `class Node<T> { Node<T>? next; }` terminates.
        _instantiatedTypes[key] = type;
        if (type is ClassTypeSymbol instantiatedClass) _classes.Add(instantiatedClass);
        if (type is InterfaceTypeSymbol instantiatedInterface) _interfaces.Add(instantiatedInterface);

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
            type is ClassTypeSymbol or StructTypeSymbol)
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

        string key = InstantiationKey(owner + "." + template.Name, arguments);
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

        PushScope();
        var body = BindBlock(function.Body);
        PopScope();

        if (!function.ReturnType.IsVoid() && !AlwaysReturns(body))
            diagnostics.Error("SL0217", function.Span,
                $"not all paths through '{function.Name}' return a value of type '{function.ReturnType.Name}'");

        _functions.Add(new BoundFunction(function, body));
        _currentFunction = null;
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
            chosen.Sections.Any(s => s.IsDefault) &&
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
        var then = BindStatement(syntax.Then);
        var otherwise = syntax.Else is null ? null : BindStatement(syntax.Else);
        return new BoundIf(syntax.Span, condition, then, otherwise);
    }

    private BoundStatement BindWhile(WhileSyntax syntax)
    {
        var condition = BindCondition(syntax.Condition);
        _loopDepth++;
        var body = BindStatement(syntax.Body);
        _loopDepth--;
        return new BoundWhile(syntax.Span, condition, body);
    }

    private BoundStatement BindFor(ForSyntax syntax)
    {
        PushScope();

        BoundStatement? initializer = syntax.Initializer is null ? null : BindStatement(syntax.Initializer);
        var condition = syntax.Condition is null ? null : BindCondition(syntax.Condition);
        var step = syntax.Step is null ? null : BindExpression(syntax.Step);

        _loopDepth++;
        var body = BindStatement(syntax.Body);
        _loopDepth--;

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
            statements.Add(BuildArrayLoop(syntax, sequence, array));
        else if (BuildEnumeratorLoop(syntax, sequence, outer, statements) is { } loop)
            statements.Add(loop);

        PopScope();
        return outer;
    }

    /// <summary>The array fast path: an ordinary indexed <c>for</c>.</summary>
    private BoundStatement BuildArrayLoop(
        ForEachSyntax syntax, LocalSymbol sequence, ArrayTypeSymbol array)
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

        var element = new BoundIndex(syntax.Span, array.Element,
            new BoundLocalAccess(syntax.Span, sequence),
            new BoundLocalAccess(syntax.Span, index));

        var body = BindForEachBody(syntax, element);

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
    /// This is the rule the whole concurrency model rests on, and it is narrow
    /// on purpose. Reference counts are not atomic, so anything two threads can
    /// both retain is a race that nothing would report. Three cases are safe:
    ///
    ///   plain data       no reference count exists to race over
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

        // A struct cannot hold a reference, so it is bytes and nothing else.
        StructTypeSymbol => true,

        ArrayTypeSymbol array => IsPlainData(array.Element),

        _ when _builtins.IsString(type) => true,

        NamedTypeSymbol named => IsShared(named),

        OptionalTypeSymbol optional => IsSendable(optional.Element),

        _ => false,
    };

    private bool IsPlainData(TypeSymbol type) =>
        type is PrimitiveTypeSymbol or PointerTypeSymbol or EnumTypeSymbol
             or DelegateTypeSymbol or StructTypeSymbol;

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
            $"{what} is '{type.Name}', which more than one thread would reach. " +
            "Reference counts are not atomic, so this is a race the runtime cannot " +
            "detect. Pass plain data or a String, guard it with 'Mutex<T>', or mark " +
            $"'{type.Name}' with [Shared] if it already synchronizes itself");
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
        return index > 0 ? CaptureFrom(index - 1, name, span) : null;
    }

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
        UnarySyntax unary => BindUnary(unary),
        BinarySyntax binary => BindBinary(binary),
        AssignmentSyntax assignment => BindAssignment(assignment),
        CallSyntax call => BindCall(call),
        MemberAccessSyntax member => BindMemberAccess(member),
        IndexSyntax index => BindIndex(index),
        NewSyntax newExpression => BindNew(newExpression),
        NewArraySyntax newArray => BindNewArray(newArray),
        ConditionalSyntax conditional => BindConditional(conditional),
        LambdaSyntax lambda => new BoundLambda(lambda.Span, LambdaType.Instance, lambda),
        CastSyntax cast => BindCast(cast),
        SizeofSyntax sizeofExpression => BindSizeof(sizeofExpression),
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

        // Shifts keep the left type; only the left operand promotes.
        if (op is BoundBinaryOp.ShiftLeft or BoundBinaryOp.ShiftRight)
        {
            if (!leftPrimitive.IsInteger || !rightPrimitive.IsInteger)
            {
                diagnostics.Error("SL0235", span, "shift operators require integer operands");
                return new BoundErrorExpression(span);
            }
            var shifted = PromoteToInt(left);
            return new BoundBinary(span, shifted.Type, shifted, op, PromoteToInt(right));
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
        var whenTrue = BindExpression(syntax.WhenTrue);
        var whenFalse = BindExpression(syntax.WhenFalse);

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

        if (!getter.IsPublic && property.ContainingType.ModuleName != _currentModule!.Name)
        {
            diagnostics.Error("SL0249", span,
                $"'{property.ContainingType.Name}.{property.Name}' is not public");
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

        if (!setter.IsPublic && property.ContainingType.ModuleName != _currentModule!.Name)
        {
            diagnostics.Error("SL0396", syntax.Target.Span,
                $"'{property.ContainingType.Name}.{property.Name}' can be read from anywhere " +
                "but only written inside its own module");
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

        if (target.Type is not (PointerTypeSymbol or ArrayTypeSymbol))
        {
            diagnostics.Error("SL0241", syntax.Span,
                $"cannot index '{target.Type.Name}'; only arrays and pointers support indexing");
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
        if (target.Type is ArrayTypeSymbol array)
            return new BoundIndex(syntax.Span, array.Element, target, PromoteToInt(index));

        var pointer = (PointerTypeSymbol)target.Type;
        return new BoundIndex(syntax.Span, pointer.Element, target, PromoteToInt(index));
    }

    private BoundExpression BindSizeof(SizeofSyntax syntax)
    {
        var measured = ResolveType(syntax.Type, _currentScope!);
        return new BoundSizeof(syntax.Span, PrimitiveTypeSymbol.NUInt, measured);
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
            return new BoundNew(syntax.Span, classType, null, []);
        }

        var constructor = ResolveOverload(classType.Constructors, arguments, syntax.Span, $"new {classType.Name}");
        if (constructor is null) return new BoundErrorExpression(syntax.Span);

        var converted = ConvertArguments(constructor, arguments, syntax.Arguments);
        return new BoundNew(syntax.Span, classType, constructor, converted);
    }

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
        // `Module.Member` is a qualified name, not a value access.
        if (ResolveModulePrefix(syntax.Target) is { } importedModule)
        {
            if (importedModule.Constants.TryGetValue(syntax.Member, out var constant) && constant.IsPublic)
                return new BoundConstantAccess(syntax.Span, constant);

            if (importedModule.Statics.TryGetValue(syntax.Member, out var shared) && shared.IsPublic)
                return new BoundStaticAccess(syntax.Span, shared);

            diagnostics.Error("SL0246", syntax.Span,
                $"module '{importedModule.Name}' has no public member named '{syntax.Member}'");
            return new BoundErrorExpression(syntax.Span);
        }

        // `Color.Red` names a constant of an enum type, not a member of a value.
        if (ResolveEnumPrefix(syntax.Target) is { } enumType)
        {
            if (enumType.FindMember(syntax.Member) is { } member)
                return new BoundLiteral(syntax.Span, enumType, member.Value);

            diagnostics.Error("SL0355", syntax.Span,
                $"enum '{enumType.Name}' has no member named '{syntax.Member}'");
            return new BoundErrorExpression(syntax.Span);
        }

        var receiver = BindExpression(syntax.Target);
        if (receiver.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        // An array's only member is its length, which lives in the header.
        if (receiver.Type is ArrayTypeSymbol)
        {
            if (syntax.Member == "Length")
                return new BoundArrayLength(syntax.Span, PrimitiveTypeSymbol.NUInt, receiver);

            diagnostics.Error("SL0313", syntax.Span,
                $"'{receiver.Type.Name}' has no member named '{syntax.Member}'; " +
                "an array has only 'Length'");
            return new BoundErrorExpression(syntax.Span);
        }

        // `p.field` on a pointer to a struct means `(*p).field`, as in C's `->`.
        if (receiver.Type is PointerTypeSymbol { Element: NamedTypeSymbol } pointer)
            receiver = new BoundDereference(syntax.Span, pointer.Element, receiver);

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

        // Properties come first: an automatic one has a field of the same name,
        // and reaching that field directly would skip the accessor and, through
        // an interface, skip dispatch with it.
        if (namedType.FindProperty(syntax.Member) is { } property)
            return BindPropertyRead(syntax.Span, receiver, property);

        if (namedType.FindField(syntax.Member) is { } field)
        {
            if (!field.IsPublic && namedType.ModuleName != _currentModule!.Name)
            {
                diagnostics.Error("SL0249", syntax.Span,
                    $"'{namedType.Name}.{syntax.Member}' is not public");
                return new BoundErrorExpression(syntax.Span);
            }
            return new BoundFieldAccess(syntax.Span, receiver, field);
        }

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

    private BoundExpression BindCall(CallSyntax syntax)
    {
        var arguments = syntax.Arguments.Select(BindExpression).ToList();

        // `receiver.Method(args)`, unless the receiver is really a module path.
        if (syntax.Callee is MemberAccessSyntax member)
        {
            if (ResolveModulePrefix(member.Target) is not { } module)
                return BindMethodCall(syntax, member, arguments);

            bool sameModule = module == _currentModule;
            var visible = module.FindFunctions(member.Member)
                .Where(f => sameModule || f.IsPublic)
                .ToList();

            if (visible.Count > 0)
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
            if (candidates.Count > 0)
                return BindFunctionCall(syntax, candidates, callee.Name.Text, arguments);

            if (TryBindGenericCall(syntax, callee.Name, arguments) is { } generic) return generic;

            // A method of the enclosing type, called without a receiver.
            if (_currentFunction?.ContainingType?.FindMethod(callee.Name.Text) is { } method &&
                callee.Name.Parts.Count == 1)
            {
                var receiver = BindImplicitThis(callee.Span);
                if (receiver is not null)
                    return BuildCall(syntax, method, receiver, arguments);
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

            diagnostics.Error("SL0252", callee.Span, $"no function named '{callee.Name.Text}' is in scope");
            return new BoundErrorExpression(syntax.Span);
        }

        diagnostics.Error("SL0253", syntax.Span, "this expression is not callable");
        return new BoundErrorExpression(syntax.Span);
    }

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
                $"but {arguments.Count} were given");
            return new BoundErrorExpression(syntax.Span);
        }

        var converted = new List<BoundExpression>(arguments.Count);
        for (int i = 0; i < arguments.Count; i++)
            converted.Add(BindConversion(
                arguments[i], delegateType.Signature[i].Type, syntax.Arguments[i].Span));

        return new BoundIndirectCall(syntax.Span, delegateType, target, converted);
    }

    private BoundExpression BindMethodCall(
        CallSyntax syntax, MemberAccessSyntax member, List<BoundExpression> arguments)
    {
        var receiver = BindExpression(member.Target);
        if (receiver.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        if (receiver.Type is PointerTypeSymbol { Element: NamedTypeSymbol } pointer)
            receiver = new BoundDereference(member.Span, pointer.Element, receiver);

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
            if (!callable.IsPublic && namedType.ModuleName != _currentModule!.Name)
            {
                diagnostics.Error("SL0249", member.Span,
                    $"'{namedType.Name}.{member.Member}' is not public");
                return new BoundErrorExpression(syntax.Span);
            }

            return BuildIndirectCall(
                syntax, new BoundFieldAccess(member.Span, receiver, callable), arguments);
        }

        if (namedType.FindMethod(member.Member) is not { } method)
        {
            if (TryBindGenericMethodCall(syntax, member, namedType, receiver, arguments) is { } generic)
                return generic;

            diagnostics.Error("SL0256", member.Span,
                $"'{namedType.Name}' has no method named '{member.Member}'");
            return new BoundErrorExpression(syntax.Span);
        }

        // The accessors are real methods, but they are the lowering rather than
        // the language: naming one directly is naming an implementation detail.
        if (method.Accessor is { } accessed)
        {
            diagnostics.Error("SL0398", member.Span,
                $"'{member.Member}' is the {(method.ReturnType.IsVoid() ? "setter" : "getter")} of " +
                $"property '{namedType.Name}.{accessed.Name}'; use the property itself");
            return new BoundErrorExpression(syntax.Span);
        }

        if (!method.IsPublic && namedType.ModuleName != _currentModule!.Name)
        {
            diagnostics.Error("SL0257", member.Span, $"'{namedType.Name}.{member.Member}' is not public");
            return new BoundErrorExpression(syntax.Span);
        }

        // A struct method takes its receiver by pointer. A temporary is fine: the
        // emitter puts it in a slot first, and anything the method writes back is
        // discarded, exactly as it is in C#.
        if (namedType is StructTypeSymbol)
            receiver = new BoundAddressOf(member.Span, new PointerTypeSymbol(namedType), receiver);

        return BuildCall(syntax, method, receiver, arguments);
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
                $"'HasFlag' takes one '{enumType.Name}', but {arguments.Count} arguments were given");
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
                $"argument{(wanted == 1 ? "" : "s")}, but {arguments.Count} were given");
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
        CallSyntax syntax, FunctionSymbol function, BoundExpression? receiver, List<BoundExpression> arguments)
    {
        int expected = function.Parameters.Count(p => !p.IsThis);
        bool countOk = function.IsVariadic ? arguments.Count >= expected : arguments.Count == expected;

        if (!countOk)
        {
            diagnostics.Error("SL0260", syntax.Span,
                $"'{function.Name}' takes {expected}{(function.IsVariadic ? " or more" : "")} " +
                $"argument{(expected == 1 ? "" : "s")}, but {arguments.Count} were given");
            return new BoundErrorExpression(syntax.Span);
        }

        var converted = ConvertArguments(function, arguments, syntax.Arguments);
        return new BoundCall(syntax.Span, function, receiver, converted);
    }

    private List<BoundExpression> ConvertArguments(
        FunctionSymbol function, List<BoundExpression> arguments, IReadOnlyList<ExpressionSyntax> syntax)
    {
        var parameters = function.Parameters.Where(p => !p.IsThis).ToList();
        var result = new List<BoundExpression>(arguments.Count);

        for (int i = 0; i < arguments.Count; i++)
        {
            var span = i < syntax.Count ? syntax[i].Span : arguments[i].Span;
            result.Add(i < parameters.Count
                ? BindConversion(arguments[i], parameters[i].Type, span)
                : PromoteVariadic(arguments[i]));       // C varargs default promotions
        }

        return result;
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

        if (IsBytePointer(target))
        {
            if (argument is BoundStringLiteral) return true;
            if (_builtins.IsString(argument.Type)) return false;
        }

        if (ConstantFits(argument, target)) return true;

        return ClassifyConversion(argument.Type, target, explicitCast: false) is not null;
    }

    private FunctionSymbol? ResolveOverload(
        IReadOnlyList<FunctionSymbol> candidates, List<BoundExpression> arguments, SourceSpan span, string name)
    {
        var viable = candidates.Where(candidate =>
        {
            int expected = candidate.Parameters.Count(p => !p.IsThis);
            if (candidate.IsVariadic ? arguments.Count < expected : arguments.Count != expected)
                return false;

            var parameters = candidate.Parameters.Where(p => !p.IsThis).ToList();
            for (int i = 0; i < parameters.Count; i++)
                if (!IsImplicitlyConvertible(arguments[i], parameters[i].Type))
                    return false;

            return true;
        }).ToList();

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
                            $"argument{(expected == 1 ? "" : "s")}, but {arguments.Count} were given");
                    else
                        for (int i = 0; i < parameters.Count; i++)
                            if (!IsImplicitlyConvertible(arguments[i], parameters[i].Type))
                                ReportArgumentMismatch(name, i, arguments[i], parameters[i].Type);
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

        // C -> C?  and  weak C? -> C? are reference identities at runtime.
        if (from is ClassTypeSymbol fromClass && to is OptionalTypeSymbol toOptional)
            return fromClass.Equals(toOptional.Element) ? ConversionKind.ReferenceToOptional : null;

        if (from is InterfaceTypeSymbol fromInterface && to is OptionalTypeSymbol toOptionalInterface)
            return fromInterface.Equals(toOptionalInterface.Element)
                ? ConversionKind.ReferenceToOptional
                : null;

        if (from is WeakTypeSymbol fromWeak && to is OptionalTypeSymbol weakTarget)
            return fromWeak.Element.Equals(weakTarget.Element) ? ConversionKind.ReferenceToOptional : null;

        // C? -> C discards a null check, so it must be explicit.
        if (from is OptionalTypeSymbol fromOptional && to is NamedTypeSymbol { IsReferenceType: true })
            return explicitCast && fromOptional.Element.Equals(to)
                ? ConversionKind.PointerCast
                : null;

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

    private TypeSymbol ResolveType(TypeSyntax syntax, FileScope scope)
    {
        switch (syntax)
        {
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

            case PrimitiveTypeSyntax primitive:
                return PrimitiveFor(primitive.Keyword);

            case PointerTypeSyntax pointer:
            {
                var element = ResolveType(pointer.Element, scope);
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
        // Only arity distinguishes candidates for now; inference does the rest.
        var template = candidates.FirstOrDefault(c => c.Declaration.Parameters.Count == arguments.Count)
                       ?? candidates[0];

        var parameters = template.Parameters.ToHashSet(StringComparer.Ordinal);
        var inferred = new Dictionary<string, TypeSymbol>(StringComparer.Ordinal);

        // An enclosing type's parameters are already fixed, so they are given
        // rather than inferred; only the method's own have to be worked out.
        foreach (var (name, type) in template.OuterSubstitution) inferred.TryAdd(name, type);

        int shared = Math.Min(arguments.Count, template.Declaration.Parameters.Count);
        for (int i = 0; i < shared; i++)
            Infer(template.Declaration.Parameters[i].Type, arguments[i].Type,
                parameters, inferred, template.Scope);

        var missing = template.Parameters.Where(p => !inferred.ContainsKey(p)).ToList();
        if (missing.Count > 0)
        {
            diagnostics.Error("SL0327", syntax.Span,
                $"cannot infer {string.Join(" and ", missing.Select(m => "'" + m + "'"))} " +
                $"for '{template.Name}' from these arguments; " +
                "Stainless infers type arguments only from the values passed");
            return null;
        }

        var typeArguments = template.Parameters.Select(p => inferred[p]).ToList();
        return InstantiateFunction(template, typeArguments, syntax.Span);
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
