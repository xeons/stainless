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

    // Per-function binding state.
    private FunctionSymbol? _currentFunction;

    /// <summary>The file being bound. Imports are per-file, so this is the unit of lookup.</summary>
    private FileScope? _currentScope;
    private ModuleSymbol? _currentModule => _currentScope?.Module;
    private readonly List<Dictionary<string, LocalSymbol>> _scopes = [];
    private int _loopDepth;

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
        DrainPending();             // pass 9: bodies of everything instantiated along the way

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

                    case GlobalConstDeclSyntax constant:
                        DeclareGlobalConstant(scope, constant);
                        break;

                    case FieldDeclSyntax field:
                        diagnostics.Error("SL0204", field.Span,
                            $"'{field.Name}' is a module-level variable; only 'const' values are " +
                            "allowed at module scope");
                        break;
                }
            }
        }

        _currentScope = null;
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

            if (type is InterfaceTypeSymbol && member is not FunctionDeclSyntax)
            {
                diagnostics.Error("SL0300", member.Span,
                    $"interface '{type.Name}' may only declare methods; " +
                    "it has no state, no constructor and no destructor");
                continue;
            }

            switch (member)
            {
                case FieldDeclSyntax field:
                {
                    if (type.FindField(field.Name) is not null)
                    {
                        diagnostics.Error("SL0205", field.Span,
                            $"'{type.Name}' already declares a field named '{field.Name}'");
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
                        diagnostics.Error("SL0322", method.Span,
                            $"'{method.Name}' is a generic method, which is not supported yet; " +
                            "make the enclosing type generic instead");
                        break;
                    }
                    DeclareFunction(scope, type, method);
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

            if (found is null)
            {
                diagnostics.Error("SL0305", span,
                    $"'{classType.Name}' does not implement '{interfaceType.Name}.{required.Name}'; " +
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

        string key = InstantiationKey(template.Module.Name + "." + template.Name, arguments);
        if (_instantiatedFunctions.TryGetValue(key, out var existing)) return existing;

        var substitution = new Dictionary<string, TypeSymbol>(StringComparer.Ordinal);
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
            IsPublic = template.IsPublic,
            Body = declaration.Body,
            Span = declaration.Span,
            TypeArguments = arguments.ToList(),
            Scope = template.Scope,
        };
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
    private static bool Satisfies(TypeSymbol argument, InterfaceTypeSymbol required) => argument switch
    {
        ClassTypeSymbol implementer => implementer.AllInterfaces().Contains(required),
        InterfaceTypeSymbol self => self.Equals(required) || self.AllInterfaces().Contains(required),
        _ => false,
    };

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
            foreach (var function in module.Functions.Where(f => f.HasBody).ToList())
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
        if (function.Body is null) return;
        if (!_boundFunctions.Add(function)) return;

        // Bound against the imports of the file it was written in.
        if (function.Scope is not null) _currentScope = function.Scope;

        _currentFunction = function;
        _scopes.Clear();
        _loopDepth = 0;

        PushScope();
        var body = BindBlock(function.Body);
        PopScope();

        if (!function.ReturnType.IsVoid() && !AlwaysReturns(body))
            diagnostics.Error("SL0217", function.Span,
                $"not all paths through '{function.Name}' return a value of type '{function.ReturnType.Name}'");

        _functions.Add(new BoundFunction(function, body));
        _currentFunction = null;
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
        _ => false,
    };

    private static bool ContainsBreak(BoundStatement statement) => statement switch
    {
        BoundBreak => true,
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
        ReturnSyntax returnStatement => BindReturn(returnStatement),
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

        bool hasEffect = expression is BoundAssignment or BoundCall or BoundNew or BoundErrorExpression;
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

    private BoundStatement BindReturn(ReturnSyntax syntax)
    {
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
        if (_loopDepth == 0)
            diagnostics.Error("SL0225", syntax.Span, "'break' is only valid inside a loop");
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

            // An unqualified field name inside a method means `this.field`.
            if (_currentFunction?.ContainingType?.FindField(name) is { } field)
            {
                var receiver = BindImplicitThis(syntax.Span);
                if (receiver is not null) return new BoundFieldAccess(syntax.Span, receiver, field);
            }

            if (_currentModule!.Constants.TryGetValue(name, out var constant))
                return new BoundConstantAccess(syntax.Span, constant);

            foreach (var import in _currentScope!.Imports.Values.Distinct())
                if (import.Constants.TryGetValue(name, out var imported) && imported.IsPublic)
                    return new BoundConstantAccess(syntax.Span, imported);
        }

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
                operand.Type is PrimitiveTypeSymbol { IsInteger: true }),
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
            or OptionalTypeSymbol or WeakTypeSymbol or NullType;

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

    private BoundExpression BindAssignment(AssignmentSyntax syntax)
    {
        var target = BindExpression(syntax.Target);
        var value = BindExpression(syntax.Value);

        if (target.Type.IsError() || value.Type.IsError())
            return new BoundErrorExpression(syntax.Span);

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
            var (op, token) = syntax.Operator switch
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

            value = BindBinaryOperation(syntax.Span, target, op, value, token);
            if (value.Type.IsError()) return new BoundErrorExpression(syntax.Span);
        }

        return new BoundAssignment(syntax.Span, target, BindConversion(value, target.Type, syntax.Value.Span));
    }

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

        return kind == ConversionKind.Identity
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

        string name = string.Join('.', parts);
        if (_currentScope!.Imports.TryGetValue(name, out var module)) return module;
        return _modules.TryGetValue(name, out module) ? module : null;
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

            diagnostics.Error("SL0246", syntax.Span,
                $"module '{importedModule.Name}' has no public member named '{syntax.Member}'");
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

            diagnostics.Error("SL0252", callee.Span, $"no function named '{callee.Name.Text}' is in scope");
            return new BoundErrorExpression(syntax.Span);
        }

        diagnostics.Error("SL0253", syntax.Span, "this expression is not callable");
        return new BoundErrorExpression(syntax.Span);
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

        if (receiver.Type is not NamedTypeSymbol namedType)
        {
            diagnostics.Error("SL0255", member.Span,
                $"'{receiver.Type.Name}' has no method named '{member.Member}'");
            return new BoundErrorExpression(syntax.Span);
        }

        if (namedType.FindMethod(member.Member) is not { } method)
        {
            diagnostics.Error("SL0256", member.Span,
                $"'{namedType.Name}' has no method named '{member.Member}'");
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

        if (kind == ConversionKind.Identity) return expression;

        // Null adopts the target type rather than being converted at runtime.
        if (expression is BoundNullLiteral) return new BoundNullLiteral(span, target);

        return new BoundConversion(span, target, expression, kind.Value);
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

        // null literal -> any nullable representation
        if (from is NullType)
            return to is PointerTypeSymbol or OptionalTypeSymbol or WeakTypeSymbol
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

        if (from is PointerTypeSymbol && to is PrimitiveTypeSymbol { IsInteger: true, Size: 8 })
            return explicitCast ? ConversionKind.PointerToInteger : null;

        if (from is PrimitiveTypeSymbol { IsInteger: true, Size: 8 } && to is PointerTypeSymbol)
            return explicitCast ? ConversionKind.IntegerToPointer : null;

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

        // Only arity distinguishes candidates for now; inference does the rest.
        var template = candidates.FirstOrDefault(c => c.Declaration.Parameters.Count == arguments.Count)
                       ?? candidates[0];

        var parameters = template.Parameters.ToHashSet(StringComparer.Ordinal);
        var inferred = new Dictionary<string, TypeSymbol>(StringComparer.Ordinal);

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
            return new BoundErrorExpression(syntax.Span);
        }

        var typeArguments = template.Parameters.Select(p => inferred[p]).ToList();
        var function = InstantiateFunction(template, typeArguments, syntax.Span);
        if (function is null) return new BoundErrorExpression(syntax.Span);

        return BuildCall(syntax, function, receiver: null, arguments);
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
public sealed class NullType : TypeSymbol
{
    public static readonly NullType Instance = new();
    private NullType() { }
    public override string Name => "null";
    public override int Size => 8;
    public override int Alignment => 8;
}
