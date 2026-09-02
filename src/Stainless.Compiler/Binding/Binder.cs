using Stainless.Source;
using Stainless.Syntax;

namespace Stainless.Binding;

/// <summary>The fully resolved program handed to the emitter.</summary>
public sealed class BoundProgram
{
    public required IReadOnlyList<ModuleSymbol> Modules { get; init; }
    public required IReadOnlyList<BoundFunction> Functions { get; init; }
    public required IReadOnlyList<ClassTypeSymbol> Classes { get; init; }
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
public sealed class Binder(DiagnosticBag diagnostics)
{
    private readonly Dictionary<string, ModuleSymbol> _modules = new(StringComparer.Ordinal);
    private readonly List<(ModuleSymbol Module, CompilationUnitSyntax Unit)> _units = [];
    private readonly List<BoundFunction> _functions = [];
    private readonly List<ClassTypeSymbol> _classes = [];

    // Per-function binding state.
    private FunctionSymbol? _currentFunction;
    private ModuleSymbol? _currentModule;
    private readonly List<Dictionary<string, LocalSymbol>> _scopes = [];
    private int _loopDepth;

    public BoundProgram Bind(IReadOnlyList<CompilationUnitSyntax> units)
    {
        DeclareModules(units);      // pass 1: every module exists
        DeclareTypes();             // pass 2: every type name exists
        ResolveImports();           // pass 3: every module can see its imports
        DeclareMembers();           // pass 4: every signature and field type is resolved
        ComputeLayouts();           // pass 5: every value type has a size
        BindBodies();               // pass 6: only now is any code checked

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
            ExternalFunctions = external,
            EntryPoint = FindEntryPoint(),
        };
    }

    // ============================================================ pass 1

    private void DeclareModules(IReadOnlyList<CompilationUnitSyntax> units)
    {
        foreach (var unit in units)
        {
            string name = unit.ModuleName?.Text ?? InferModuleName(unit.File.Path);

            if (_modules.TryGetValue(name, out var existing))
            {
                diagnostics.Error("SL0200", unit.ModuleName?.Span ?? unit.Span,
                    $"module '{name}' is already declared in {existing.Syntax?.File.Path}; " +
                    "one module is exactly one file");
                continue;
            }

            var module = new ModuleSymbol(name) { Syntax = unit };
            _modules[name] = module;
            _units.Add((module, unit));
        }
    }

    private static string InferModuleName(string path) =>
        Path.GetFileNameWithoutExtension(path);

    // ============================================================ pass 2

    private void DeclareTypes()
    {
        foreach (var (module, unit) in _units)
        {
            foreach (var declaration in unit.Declarations.OfType<TypeDeclSyntax>())
            {
                if (module.Types.ContainsKey(declaration.Name))
                {
                    diagnostics.Error("SL0201", declaration.Span,
                        $"'{declaration.Name}' is already declared in module '{module.Name}'");
                    continue;
                }

                NamedTypeSymbol type = declaration.Kind == TypeDeclKind.Class
                    ? new ClassTypeSymbol
                    {
                        SimpleName = declaration.Name,
                        ModuleName = module.Name,
                        IsPublic = declaration.Modifiers.HasFlag(Modifiers.Public),
                    }
                    : new StructTypeSymbol
                    {
                        SimpleName = declaration.Name,
                        ModuleName = module.Name,
                        IsPublic = declaration.Modifiers.HasFlag(Modifiers.Public),
                    };

                module.Types[declaration.Name] = type;
                if (type is ClassTypeSymbol classType) _classes.Add(classType);
            }
        }
    }

    // ============================================================ pass 3

    private void ResolveImports()
    {
        foreach (var (module, unit) in _units)
        {
            foreach (var import in unit.Imports)
            {
                if (!_modules.TryGetValue(import.Name.Text, out var target))
                {
                    diagnostics.Error("SL0202", import.Span,
                        $"module '{import.Name.Text}' was not found among the compiled sources");
                    continue;
                }

                if (target == module)
                {
                    diagnostics.Warning("SL0203", import.Span, "a module cannot import itself");
                    continue;
                }

                string key = import.Alias ?? import.Name.Last;
                module.Imports[key] = target;

                // The full dotted name always works too, so `import A.B;` lets you
                // write both `B.Thing` and `A.B.Thing`.
                module.Imports[import.Name.Text] = target;
            }
        }
    }

    // ============================================================ pass 4

    private void DeclareMembers()
    {
        foreach (var (module, unit) in _units)
        {
            _currentModule = module;

            foreach (var declaration in unit.Declarations)
            {
                switch (declaration)
                {
                    case FunctionDeclSyntax function:
                        DeclareFunction(module, containingType: null, function);
                        break;

                    case TypeDeclSyntax typeDecl:
                        DeclareTypeMembers(module, typeDecl);
                        break;

                    case GlobalConstDeclSyntax constant:
                        DeclareGlobalConstant(module, constant);
                        break;

                    case FieldDeclSyntax field:
                        diagnostics.Error("SL0204", field.Span,
                            $"'{field.Name}' is a module-level variable; only 'const' values are " +
                            "allowed at module scope");
                        break;
                }
            }
        }

        _currentModule = null;
    }

    private void DeclareTypeMembers(ModuleSymbol module, TypeDeclSyntax declaration)
    {
        var type = module.Types[declaration.Name];
        var classType = type as ClassTypeSymbol;

        foreach (var member in declaration.Members)
        {
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

                    var fieldType = ResolveType(field.Type, module);

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
                    DeclareFunction(module, type, method);
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
                        IsPublic = constructor.Modifiers.HasFlag(Modifiers.Public),
                    };
                    symbol.Parameters.Add(new ParameterSymbol("this", classType, 0) { IsThis = true });
                    AddParameters(symbol, constructor.Parameters, module);
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
                    };
                    symbol.Parameters.Add(new ParameterSymbol("this", classType, 0) { IsThis = true });
                    classType.Destructor = symbol;
                    break;
                }
            }
        }
    }

    private void DeclareFunction(ModuleSymbol module, NamedTypeSymbol? containingType, FunctionDeclSyntax declaration)
    {
        var returnType = ResolveType(declaration.ReturnType, module);

        var symbol = new FunctionSymbol
        {
            Name = declaration.Name,
            ModuleName = module.Name,
            ReturnType = returnType,
            Linkage = declaration.Linkage,
            Kind = containingType is null ? FunctionKind.Function : FunctionKind.Method,
            ContainingType = containingType,
            IsPublic = declaration.Modifiers.HasFlag(Modifiers.Public),
            IsVariadic = declaration.IsVariadic,
            Body = declaration.Body,
            Span = declaration.Span,
        };

        if (containingType is not null)
        {
            // A method receives its instance: classes by reference, structs by pointer.
            TypeSymbol thisType = containingType is ClassTypeSymbol c
                ? c
                : new PointerTypeSymbol(containingType);
            symbol.Parameters.Add(new ParameterSymbol("this", thisType, 0) { IsThis = true });
        }

        AddParameters(symbol, declaration.Parameters, module);

        if (declaration.Linkage != LinkageKind.ExternC && declaration.Body is null)
            diagnostics.Error("SL0210", declaration.Span,
                $"'{declaration.Name}' has no body; Stainless has no forward declarations, " +
                "because declaration order never matters");

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

    private void AddParameters(FunctionSymbol symbol, IReadOnlyList<ParameterSyntax> parameters, ModuleSymbol module)
    {
        foreach (var parameter in parameters)
        {
            if (symbol.Parameters.Any(p => p.Name == parameter.Name))
            {
                diagnostics.Error("SL0212", parameter.Span,
                    $"duplicate parameter name '{parameter.Name}'");
                continue;
            }

            var type = ResolveType(parameter.Type, module);
            if (type.IsVoid())
                diagnostics.Error("SL0213", parameter.Span,
                    $"parameter '{parameter.Name}' cannot have type 'void'");

            symbol.Parameters.Add(new ParameterSymbol(parameter.Name, type, symbol.Parameters.Count));
        }
    }

    private void DeclareGlobalConstant(ModuleSymbol module, GlobalConstDeclSyntax declaration)
    {
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
            : ResolveType(declaration.Type, module);

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

    // ============================================================ pass 6

    private void BindBodies()
    {
        foreach (var (module, _) in _units)
        {
            _currentModule = module;

            foreach (var function in module.Functions.Where(f => f.HasBody))
                BindFunctionBody(function);

            foreach (var type in module.Types.Values.OfType<ClassTypeSymbol>())
            {
                foreach (var constructor in type.Constructors) BindFunctionBody(constructor);
                if (type.Destructor is not null) BindFunctionBody(type.Destructor);
            }
        }

        _currentModule = null;
    }

    private void BindFunctionBody(FunctionSymbol function)
    {
        if (function.Body is null) return;

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
            type = ResolveType(syntax.Type, _currentModule!);
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
        CastSyntax cast => BindCast(cast),
        SizeofSyntax sizeofExpression => BindSizeof(sizeofExpression),
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
            syntax.Span, new PointerTypeSymbol(PrimitiveTypeSymbol.Byte), (string)syntax.Value!),
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

            foreach (var import in _currentModule.Imports.Values.Distinct())
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
        type is PointerTypeSymbol or ClassTypeSymbol or OptionalTypeSymbol or WeakTypeSymbol
            or NullType;

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

        if (target.Type is not PointerTypeSymbol pointer)
        {
            diagnostics.Error("SL0241", syntax.Span,
                $"cannot index '{target.Type.Name}'; only pointers support indexing");
            return new BoundErrorExpression(syntax.Span);
        }

        if (index.Type is not PrimitiveTypeSymbol { IsInteger: true })
        {
            diagnostics.Error("SL0242", syntax.Index.Span,
                $"an index must be an integer, but this is '{index.Type.Name}'");
            return new BoundErrorExpression(syntax.Span);
        }

        return new BoundIndex(syntax.Span, pointer.Element, target, PromoteToInt(index));
    }

    private BoundExpression BindSizeof(SizeofSyntax syntax)
    {
        var measured = ResolveType(syntax.Type, _currentModule!);
        return new BoundSizeof(syntax.Span, PrimitiveTypeSymbol.NUInt, measured);
    }

    private BoundExpression BindCast(CastSyntax syntax)
    {
        var targetType = ResolveType(syntax.Type, _currentModule!);
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
        var type = ResolveType(syntax.Type, _currentModule!);
        if (type.IsError()) return new BoundErrorExpression(syntax.Span);

        if (type is not ClassTypeSymbol classType)
        {
            diagnostics.Error("SL0244", syntax.Span,
                $"'{type.Name}' is not a class; only classes are heap allocated. " +
                (type is StructTypeSymbol
                    ? "Declare a struct as a plain value instead."
                    : "Use a pointer and an allocator for raw memory."));
            return new BoundErrorExpression(syntax.Span);
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
        if (_currentModule!.Imports.TryGetValue(name, out var module)) return module;
        return _modules.TryGetValue(name, out module) ? module : null;
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

            return BindFunctionCall(syntax, visible, member.Member, arguments);
        }

        if (syntax.Callee is NameSyntax callee)
        {
            var candidates = ResolveFunctionCandidates(callee.Name);
            if (candidates.Count > 0)
                return BindFunctionCall(syntax, candidates, callee.Name.Text, arguments);

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

        // A struct method takes its receiver by pointer, so the receiver must be storage.
        if (namedType is StructTypeSymbol)
        {
            if (!receiver.IsLValue)
            {
                diagnostics.Error("SL0258", member.Span,
                    $"cannot call '{member.Member}' on a temporary '{namedType.Name}'; " +
                    "assign it to a variable first");
                return new BoundErrorExpression(syntax.Span);
            }
            receiver = new BoundAddressOf(member.Span, new PointerTypeSymbol(namedType), receiver);
        }

        return BuildCall(syntax, method, receiver, arguments);
    }

    private List<FunctionSymbol> ResolveFunctionCandidates(QualifiedName name)
    {
        if (name.Parts.Count == 1)
        {
            var local = _currentModule!.FindFunctions(name.Parts[0]).ToList();
            if (local.Count > 0) return local;

            return _currentModule.Imports.Values.Distinct()
                .SelectMany(m => m.FindFunctions(name.Parts[0]))
                .Where(f => f.IsPublic)
                .ToList();
        }

        // Qualified: everything before the last part names a module.
        string moduleName = string.Join('.', name.Parts.Take(name.Parts.Count - 1));
        if (_currentModule!.Imports.TryGetValue(moduleName, out var module) ||
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
        if (argument.Type is PrimitiveTypeSymbol { Kind: PrimitiveKind.Float })
            return new BoundConversion(
                argument.Span, PrimitiveTypeSymbol.Double, argument, ConversionKind.FloatResize);

        if (argument.Type is PrimitiveTypeSymbol { IsInteger: true, Size: < 4 } or
            PrimitiveTypeSymbol { Kind: PrimitiveKind.Bool })
            return new BoundConversion(
                argument.Span, PrimitiveTypeSymbol.Int, argument, ConversionKind.IntegerWiden);

        return argument;
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
                if (ClassifyConversion(arguments[i].Type, parameters[i].Type, explicitCast: false) is null)
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
                            if (ClassifyConversion(arguments[i].Type, parameters[i].Type, false) is null)
                                diagnostics.Error("SL0262", arguments[i].Span,
                                    $"argument {i + 1} of '{name}' expects '{parameters[i].Type.Name}', " +
                                    $"but '{arguments[i].Type.Name}' was given");
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
    private ConversionKind? ClassifyConversion(TypeSymbol from, TypeSymbol to, bool explicitCast)
    {
        if (from.Equals(to)) return ConversionKind.Identity;

        // null literal -> any nullable representation
        if (from is NullType)
            return to is PointerTypeSymbol or OptionalTypeSymbol or WeakTypeSymbol
                ? ConversionKind.NullToReference
                : null;

        // C -> C?  and  weak C? -> C? are reference identities at runtime.
        if (from is ClassTypeSymbol fromClass && to is OptionalTypeSymbol toOptional)
            return fromClass.Equals(toOptional.Element) ? ConversionKind.ReferenceToOptional : null;

        if (from is WeakTypeSymbol fromWeak && to is OptionalTypeSymbol weakTarget)
            return fromWeak.Element.Equals(weakTarget.Element) ? ConversionKind.ReferenceToOptional : null;

        // C? -> C discards a null check, so it must be explicit.
        if (from is OptionalTypeSymbol fromOptional && to is ClassTypeSymbol toClass)
            return explicitCast && fromOptional.Element.Equals(toClass)
                ? ConversionKind.PointerCast
                : null;

        if (from is PointerTypeSymbol && to is PointerTypeSymbol)
        {
            // Any pointer converts to byte* implicitly, mirroring C's void*.
            bool toBytePointer = to is PointerTypeSymbol { Element: PrimitiveTypeSymbol { Kind: PrimitiveKind.Byte } };
            return explicitCast || toBytePointer ? ConversionKind.PointerCast : null;
        }

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

    private TypeSymbol ResolveType(TypeSyntax syntax, ModuleSymbol module)
    {
        switch (syntax)
        {
            case PrimitiveTypeSyntax primitive:
                return PrimitiveFor(primitive.Keyword);

            case PointerTypeSyntax pointer:
            {
                var element = ResolveType(pointer.Element, module);
                if (element.IsError()) return element;
                if (element is ClassTypeSymbol)
                {
                    diagnostics.Error("SL0270", syntax.Span,
                        $"'{element.Name}' is a class, so '{element.Name}*' is not allowed; " +
                        "a class reference is already a managed pointer");
                    return ErrorTypeSymbol.Instance;
                }
                return new PointerTypeSymbol(element);
            }

            case NullableTypeSyntax nullable:
            {
                var element = ResolveType(nullable.Element, module);
                if (element.IsError()) return element;
                if (element is not ClassTypeSymbol classType)
                {
                    diagnostics.Error("SL0271", syntax.Span,
                        $"'{element.Name}?' is not valid; only class references can be optional " +
                        $"(a '{element.Name}' is a value and is never null)");
                    return ErrorTypeSymbol.Instance;
                }
                return new OptionalTypeSymbol(classType);
            }

            case WeakTypeSyntax weak:
            {
                var element = ResolveType(weak.Element, module);
                if (element.IsError()) return element;

                var classType = element.AsClass();
                if (classType is null)
                {
                    diagnostics.Error("SL0272", syntax.Span,
                        $"'weak' requires a class reference, but '{element.Name}' is not one");
                    return ErrorTypeSymbol.Instance;
                }
                return new WeakTypeSymbol(classType);
            }

            case NamedTypeSyntax named:
                return ResolveNamedType(named, module);

            default:
                return ErrorTypeSymbol.Instance;
        }
    }

    private TypeSymbol ResolveNamedType(NamedTypeSyntax syntax, ModuleSymbol module)
    {
        var parts = syntax.Name.Parts;

        if (parts.Count == 1)
        {
            if (module.Types.TryGetValue(parts[0], out var local)) return local;

            var visible = module.Imports.Values.Distinct()
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
            if (module.Imports.TryGetValue(moduleName, out var target) ||
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
