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
/// Functions declared in a block.
///
/// <para>
/// A local function is an ordinary function with a name nothing outside its
/// block can write. What it reads of the function around it -- a local, a
/// parameter, <c>this</c> -- it is passed at every call, as parameters the
/// source never wrote: by value, so it sees what each variable holds when it
/// is called and may not assign one. One that reads nothing is a plain
/// function, and becomes a <c>delegate</c> like any other.
/// </para>
///
/// <para>
/// <b>What it captures is learned by binding it.</b> A call may come before
/// the declaration, from another local function, or from a lambda, and each
/// has to pass what the callee reads. Where a call was bound before the
/// callee's list was complete, the whole of the function around them is bound
/// again with the lists it learned. The lists only grow, so that settles.
/// </para>
/// </summary>
public sealed partial class Binder
{
    /// <summary>What a local function was learned to read, kept across rebinds.</summary>
    private sealed class LocalFunctionData
    {
        /// <summary>The variables it reads, by name, in the order its hidden parameters take.</summary>
        public List<string> Captures { get; } = [];

        /// <summary>Whether it reaches the object of the method around it.</summary>
        public bool NeedsThis { get; set; }
    }

    /// <summary>One local function, for one binding of the block it is in.</summary>
    private sealed class LocalFunction
    {
        public required LocalFunctionSyntax Syntax { get; init; }
        public required LocalFunctionData Data { get; init; }
        public required string Path { get; init; }
        public bool IsStatic => Syntax.Declaration.Modifiers.HasFlag(Modifiers.Static);

        /// <summary>The symbol, for one that is not generic.</summary>
        public FunctionSymbol? Symbol { get; set; }

        /// <summary>The template, for one that is.</summary>
        public GenericFunctionTemplate? Template { get; set; }

        public Dictionary<TypeList, FunctionSymbol> Instances { get; } = [];

        /// <summary>Instances asked for before the declaration was reached.</summary>
        public List<(FunctionSymbol Symbol, Dictionary<string, TypeSymbol> Substitution)> Waiting { get; } = [];

        /// <summary>The local functions its body can name, as the declaration saw them.</summary>
        public required List<Dictionary<string, LocalFunction>> Scopes { get; init; }

        /// <summary>The type whose object it may reach, and that object's type.</summary>
        public NamedTypeSymbol? Owner { get; init; }
        public TypeSymbol? ThisType { get; init; }

        /// <summary>The type arguments of what it was declared in.</summary>
        public required IReadOnlyList<TypeSymbol> OuterTypeArguments { get; init; }

        /// <summary>
        /// Every variable its body could read from around it, by name, with
        /// the variable itself -- a local, or a parameter nothing wrote -- and
        /// its type. Null until the declaration is reached: a variable declared
        /// after it is not one of these, as in C#.
        /// </summary>
        public Dictionary<string, (object Origin, TypeSymbol Type)>? Visible { get; set; }

        /// <summary>How many calls and mentions were bound with the lists as they then stood.</summary>
        public int Uses { get; set; }

        /// <summary>Captures passed by calls bound before the declaration, to be checked there.</summary>
        public List<(string Name, object Origin, SourceSpan Span)> ForwardUses { get; } = [];
    }

    private readonly Dictionary<LocalFunctionSyntax, LocalFunctionData> _localFunctionData =
        new(ReferenceEqualityComparer.Instance);

    private readonly Dictionary<FunctionSymbol, LocalFunction> _localFunctionOf = [];

    /// <summary>The paths already given out, so that two in one program differ.</summary>
    private readonly HashSet<string> _localPaths = new(StringComparer.Ordinal);

    /// <summary>
    /// Set when something was bound against a capture list that has since
    /// grown, so the function being bound has to be bound again.
    /// </summary>
    private bool _rebindNeeded;

    /// <summary>True while the function being bound can be bound again.</summary>
    private bool _rebindable;

    /// <summary>Closure classes and functions a discarded binding takes back with it.</summary>
    private readonly HashSet<object> _generated = new(ReferenceEqualityComparer.Instance);

    /// <summary>For each closure field, the variable it holds a copy of.</summary>
    private readonly Dictionary<FieldSymbol, object> _captureOrigins = [];

    // ============================================================ declaring

    /// <summary>
    /// Makes every local function of a block nameable from the top of it, so a
    /// call may come before the declaration and two may call each other.
    /// </summary>
    private void DeclareLocalFunctions(BlockSyntax block, Dictionary<string, LocalFunction> scope)
    {
        foreach (var statement in block.Statements)
            if (statement is LocalFunctionSyntax local)
                DeclareLocalFunction(local, scope);
    }

    private LocalFunction? DeclareLocalFunction(LocalFunctionSyntax syntax, Dictionary<string, LocalFunction> scope)
    {
        var declaration = syntax.Declaration;

        if (scope.ContainsKey(declaration.Name) || LookupLocal(declaration.Name) is not null)
        {
            diagnostics.Report(Codes.DuplicateLocalName, declaration.Span,
                $"'{declaration.Name}' is already declared in this scope; local functions are " +
                "not overloaded, as in C#");
            return null;
        }

        if (!_localFunctionData.TryGetValue(syntax, out var data))
        {
            data = new LocalFunctionData();
            _localFunctionData[syntax] = data;
        }

        // The function whose object a body here would mean by `this`: past any
        // lambda, to the function the outermost one was written in.
        var user = _context.Closures.Count > 0
            ? _context.Closures[0].OuterFunction
            : _context.Function;
        var parent = user is null ? null : _localFunctionOf.GetValueOrDefault(user);

        var local = new LocalFunction
        {
            Syntax = syntax,
            Data = data,
            Path = UniquePath(LocalPathOf(_context.Function) + "." + declaration.Name),
            Scopes = [.. _context.LocalFunctionScopes],
            Owner = parent?.Owner ?? user?.ContainingType,
            ThisType = parent is not null
                ? parent.ThisType
                : user?.Parameters.FirstOrDefault(p => p.IsThis)?.Type,
            OuterTypeArguments = user?.TypeArguments ?? [],
        };

        if (declaration.TypeParameters.Count > 0)
        {
            local.Template = new GenericFunctionTemplate(declaration.Name, _context.File!, declaration)
            {
                ContainingType = local.Owner,
                OuterSubstitution = new Dictionary<string, TypeSymbol>(
                    _context.Substitution, StringComparer.Ordinal),
                Local = local,
            };
        }
        else
        {
            local.Symbol = NewLocalFunctionSymbol(local, []);
        }

        scope[declaration.Name] = local;
        return local;
    }

    /// <summary>A path no other local function in the program has.</summary>
    private string UniquePath(string wanted)
    {
        string path = wanted;
        for (int n = 2; !Remember(_localPaths, path); n++) path = $"{wanted}.{n}";
        return path;
    }

    /// <summary>What a local function declared in <paramref name="function"/> is named under.</summary>
    private string LocalPathOf(FunctionSymbol? function) => function switch
    {
        null => "",
        { LocalPath: { } path } => path,
        { ContainingType: ClassTypeSymbol closure } when _generated.Contains(closure) =>
            closure.SimpleName + "." + function.Name,
        _ => function.Name,
    };

    private FunctionSymbol NewLocalFunctionSymbol(LocalFunction local, IReadOnlyList<TypeSymbol> own)
    {
        var declaration = local.Syntax.Declaration;
        bool hasThis = local.Data.NeedsThis && local.ThisType is not null && !local.IsStatic;

        var symbol = new FunctionSymbol
        {
            Name = declaration.Name,
            ModuleName = _currentModule!.Name,
            ReturnType = ResolveType(declaration.ReturnType, _context.File!, allowVoid: true),
            Linkage = LinkageKind.Stainless,
            Kind = local.Owner is null ? FunctionKind.Function : FunctionKind.Method,
            ContainingType = local.Owner,
            IsPublic = false,
            IsStatic = local.Owner is not null && !hasThis,
            Body = declaration.Body,
            Span = declaration.Span,
            Scope = _context.File,
            TypeArguments = [.. local.OuterTypeArguments, .. own],
            LocalPath = local.Path,
        };

        if (hasThis)
            symbol.Parameters.Add(new ParameterSymbol("this", local.ThisType!, 0) { IsThis = true });

        AddParameters(symbol, declaration.Parameters, _context.File!);

        _localFunctionOf[symbol] = local;
        _generated.Add(symbol);
        return symbol;
    }

    /// <summary>
    /// The declaration itself: where the variables it may read are settled, and
    /// where its body is bound. It leaves nothing to run.
    /// </summary>
    private BoundStatement BindLocalFunctionDeclaration(LocalFunctionSyntax syntax)
    {
        var scope = _context.LocalFunctionScopes[^1];
        string name = syntax.Declaration.Name;

        // Declared already at the top of the block, or refused there.
        LocalFunction? local;
        if (scope.TryGetValue(name, out var declared))
        {
            if (!ReferenceEquals(declared.Syntax, syntax)) return new BoundBlock(syntax.Span, []);
            local = declared;
        }
        else
        {
            local = DeclareLocalFunction(syntax, scope);
        }

        if (local is null) return new BoundBlock(syntax.Span, []);

        local.Visible = VisibleVariables();

        foreach (var (used, origin, span) in local.ForwardUses)
            if (!local.Visible.TryGetValue(used, out var seen) || !ReferenceEquals(seen.Origin, origin))
                ReportCaptureNotHere(local, used, span);

        if (local.Symbol is { } symbol)
        {
            AttachCaptures(local, symbol);
            BindLocalFunctionBody(local, symbol, _context.Substitution);
        }

        foreach (var (waiting, substitution) in local.Waiting)
        {
            AttachCaptures(local, waiting);
            BindLocalFunctionBody(local, waiting, substitution);
        }

        local.Waiting.Clear();
        return new BoundBlock(syntax.Span, []);
    }

    /// <summary>
    /// Every variable in reach here, innermost first: this function's locals
    /// and parameters, what it captured if it is a local function, and past
    /// any lambda, the same of what the lambda was written in.
    /// </summary>
    private Dictionary<string, (object Origin, TypeSymbol Type)> VisibleVariables()
    {
        var visible = new Dictionary<string, (object, TypeSymbol)>(StringComparer.Ordinal);

        void AddScopes(IReadOnlyList<Dictionary<string, LocalSymbol>> scopes)
        {
            for (int i = scopes.Count - 1; i >= 0; i--)
                foreach (var local in scopes[i].Values)
                    visible.TryAdd(local.Name, (local, local.Type));
        }

        void AddFunction(FunctionSymbol? function)
        {
            if (function is null) return;
            foreach (var parameter in function.Parameters.Where(p => !p.IsThis))
                visible.TryAdd(parameter.Name, (OriginOf(parameter), parameter.Type));
            foreach (var captured in function.Captures)
                visible.TryAdd(captured.Name, (captured.CaptureOrigin!, captured.Type));

            // A local function reaches whatever its own declaration could, so
            // one declared inside it does too, by way of it.
            if (_localFunctionOf.GetValueOrDefault(function)?.Visible is { } around)
                foreach (var (name, variable) in around)
                    visible.TryAdd(name, variable);
        }

        AddScopes(_context.Locals);
        AddFunction(_context.Function);

        for (int i = _context.Closures.Count - 1; i >= 0; i--)
        {
            AddScopes(_context.Closures[i].OuterScopes);
            AddFunction(_context.Closures[i].OuterFunction);
        }

        return visible;
    }

    private static object OriginOf(ParameterSymbol parameter) => parameter.CaptureOrigin ?? parameter;

    /// <summary>Gives a symbol the hidden parameters its capture list calls for.</summary>
    private void AttachCaptures(LocalFunction local, FunctionSymbol symbol)
    {
        foreach (string name in local.Data.Captures)
        {
            if (symbol.Captures.Any(c => c.Name == name)) continue;
            if (!local.Visible!.TryGetValue(name, out var variable)) continue;

            symbol.Captures.Add(new ParameterSymbol(
                name, variable.Type, symbol.Parameters.Count + symbol.Captures.Count)
            {
                CaptureOrigin = variable.Origin,
            });
        }
    }

    /// <summary>
    /// Binds a local function's body as the function it is, with the enclosing
    /// function's state put aside and brought back afterwards.
    /// </summary>
    private void BindLocalFunctionBody(
        LocalFunction local, FunctionSymbol symbol, Dictionary<string, TypeSymbol> substitution)
    {
        var body = _context.ForBody(null) with
        {
            Closures = [],
            LocalFunctionScopes = [.. local.Scopes],
            Substitution = substitution,
            InitializingField = false,
        };

        using (Enter(body))
            BindFunctionBody(symbol);
    }

    /// <summary>A generic local function at one set of type arguments.</summary>
    private FunctionSymbol InstantiateLocalFunction(
        LocalFunction local, GenericFunctionTemplate template, IReadOnlyList<TypeSymbol> arguments,
        SourceSpan span)
    {
        var key = new TypeList(arguments.ToList());
        if (local.Instances.TryGetValue(key, out var existing)) return existing;

        // The body is bound here and not again, so what it reports is the
        // instantiation's.
        using var owed = OweToTrial();

        var substitution = new Dictionary<string, TypeSymbol>(
            template.OuterSubstitution, StringComparer.Ordinal);
        for (int i = 0; i < arguments.Count; i++) substitution[template.Parameters[i]] = arguments[i];

        VerifyConstraints(template.Declaration.Constraints, template.Parameters, substitution,
            template.Scope, $"'{template.Name}'", span, checkedWhereDeclared: false);

        FunctionSymbol symbol;
        using (Enter(_context with { Substitution = substitution }))
            symbol = NewLocalFunctionSymbol(local, arguments);

        Remember(local.Instances, key, symbol);

        if (local.Visible is null)
        {
            local.Waiting.Add((symbol, substitution));
        }
        else
        {
            AttachCaptures(local, symbol);
            BindLocalFunctionBody(local, symbol, substitution);
        }

        return symbol;
    }

    // ============================================================ using one

    private LocalFunction? LookupLocalFunction(string name)
    {
        for (int i = _context.LocalFunctionScopes.Count - 1; i >= 0; i--)
            if (_context.LocalFunctionScopes[i].TryGetValue(name, out var local)) return local;
        return null;
    }

    /// <summary>
    /// <c>Square(3)</c>, where <c>Square</c> is declared in a block around the
    /// call: the arguments written, then the object if it reaches one, then
    /// the value of every variable it reads, as it stands at the call.
    /// </summary>
    private BoundExpression BindLocalFunctionCall(
        CallSyntax syntax, NameSyntax callee, LocalFunction local, List<BoundExpression> arguments)
    {
        FunctionSymbol target;

        if (local.Template is { } template)
        {
            if (InferAndInstantiate([template], syntax, arguments) is not { } instance)
                return new BoundErrorExpression(syntax.Span);
            target = instance;
        }
        else
        {
            target = local.Symbol!;
        }

        local.Uses++;

        // Inside a lambda the object is the one the lambda was written in,
        // which the lambda captures, and not the closure it became.
        BoundExpression? receiver = null;
        if (target.Parameters.Any(p => p.IsThis))
        {
            receiver = _context.Closures.Count > 0
                ? CaptureThis(_context.Closures.Count - 1, callee.Span)
                : BindImplicitThis(callee.Span);
            if (receiver is null || receiver.Type.IsError()) return new BoundErrorExpression(syntax.Span);
        }

        var call = BuildCall(syntax, target, receiver, arguments);
        if (call is not BoundCall bound || local.Data.Captures.Count == 0) return call;

        var captured = local.Data.Captures
            .Select(name => BindCapturedVariable(local, name, callee.Span))
            .ToList();

        var order = bound.EvaluationOrder is null
            ? null
            : bound.EvaluationOrder.Concat(Enumerable.Range(bound.Arguments.Count, captured.Count)).ToArray();

        return new BoundCall(bound.Span, bound.Function, bound.Receiver, [.. bound.Arguments, .. captured])
        {
            IsNonVirtual = bound.IsNonVirtual,
            EvaluationOrder = order,
        };
    }

    /// <summary>
    /// A local function named without a call. One that reads nothing from
    /// around it is a function like any other; one that does becomes a lambda
    /// that calls it, and so captures what it reads now, by value, as a lambda
    /// does.
    /// </summary>
    private BoundExpression LocalFunctionValue(LocalFunction local, SourceSpan span)
    {
        var declaration = local.Syntax.Declaration;

        if (local.Template is not null)
        {
            diagnostics.Report(Codes.TypeUsedAsValue, span,
                $"'{declaration.Name}' is generic, and a local function's type arguments come " +
                "from a call; wrap the call in a lambda to make a value of one instantiation");
            return new BoundErrorExpression(span);
        }

        local.Uses++;

        if (local.Data.Captures.Count == 0 && !local.Symbol!.Parameters.Any(p => p.IsThis))
            return new BoundFunctionGroup(span, FunctionGroupType.Instance, declaration.Name, [local.Symbol]);

        var parameters = declaration.Parameters
            .Select((_, i) => new LambdaParameterSyntax(span, null, $"${i}"))
            .ToList();

        var call = new CallSyntax(span,
            new NameSyntax(span, new QualifiedName(span, [declaration.Name])),
            parameters.Select(p => (ExpressionSyntax)new NameSyntax(span, new QualifiedName(span, [p.Name])))
                .ToList());

        return new BoundLambda(span, LambdaType.Instance, new LambdaSyntax(span, parameters, call, null))
        {
            LocalFunction = declaration.Name,
        };
    }

    // ============================================================ capturing

    /// <summary>
    /// The value a call passes for one variable a local function reads: that
    /// variable, reached from where the call is -- directly, through a local
    /// function that captures it in turn, or through a lambda.
    /// </summary>
    private BoundExpression BindCapturedVariable(LocalFunction local, string name, SourceSpan span)
    {
        object? expected = local.Visible is { } visible && visible.TryGetValue(name, out var known)
            ? known.Origin
            : null;

        if (ReachVariable(name, expected, span) is not { } reached)
        {
            ReportCaptureNotHere(local, name, span);
            return new BoundErrorExpression(span);
        }

        if (expected is null) local.ForwardUses.Add((name, reached.Origin, span));
        return reached.Value;
    }

    private void ReportCaptureNotHere(LocalFunction local, string name, SourceSpan span) =>
        diagnostics.Report(Codes.LocalFunctionCaptureNotInScope, span,
            $"'{local.Syntax.Declaration.Name}' reads '{name}' from around it, which every call " +
            $"passes it, and that '{name}' is not in reach here -- it is declared later, or " +
            "another variable has its name. Call it where the variable is in scope");

    /// <summary>
    /// The variable <paramref name="name"/> from here, when it is the one
    /// <paramref name="expected"/> names (or any variable, when that is null).
    /// </summary>
    private (BoundExpression Value, object Origin)? ReachVariable(string name, object? expected, SourceSpan span)
    {
        if (LookupLocal(name) is { } found && (expected is null || ReferenceEquals(found, expected)))
            return (new BoundLocalAccess(span, found), found);

        if (_context.Function is { } function)
        {
            foreach (var parameter in function.Parameters.Where(p => !p.IsThis).Concat(function.Captures))
                if (parameter.Name == name &&
                    (expected is null || ReferenceEquals(OriginOf(parameter), expected)))
                    return (new BoundParameterAccess(span, parameter), OriginOf(parameter));

            if (_localFunctionOf.GetValueOrDefault(function) is { Visible: { } seen } here &&
                seen.TryGetValue(name, out var variable) &&
                (expected is null || ReferenceEquals(variable.Origin, expected)) &&
                CaptureInto(here, function, name, span) is { } parameter2)
                return (new BoundParameterAccess(span, parameter2), variable.Origin);
        }

        if (_context.Closures.Count > 0 &&
            CaptureFrom(_context.Closures.Count - 1, name, span, variablesOnly: true)
                is BoundFieldAccess field &&
            _captureOrigins.TryGetValue(field.Field, out var origin) &&
            (expected is null || ReferenceEquals(origin, expected)))
            return (field, origin);

        return null;
    }

    /// <summary>
    /// A name a local function's body did not declare, looked for among the
    /// variables around its declaration. Found, it becomes one of the hidden
    /// parameters every call passes.
    /// </summary>
    private BoundExpression? TryCaptureIntoLocalFunction(string name, SourceSpan span)
    {
        if (_context.Function is not { } function) return null;

        if (function.Captures.FirstOrDefault(c => c.Name == name) is { } known)
            return new BoundParameterAccess(span, known);

        if (_localFunctionOf.GetValueOrDefault(function) is not { Visible: { } seen } local) return null;
        if (!seen.ContainsKey(name)) return null;

        return CaptureInto(local, function, name, span) is { } parameter
            ? new BoundParameterAccess(span, parameter)
            : new BoundErrorExpression(span);
    }

    /// <summary>Adds a variable to what a local function captures, and says what that costs.</summary>
    private ParameterSymbol? CaptureInto(LocalFunction local, FunctionSymbol function, string name, SourceSpan span)
    {
        if (function.Captures.FirstOrDefault(c => c.Name == name) is { } already) return already;

        if (local.IsStatic)
        {
            diagnostics.Report(Codes.StaticBodyCaptures, span,
                $"'{local.Syntax.Declaration.Name}' is a static local function, so it cannot read " +
                $"'{name}' from the function around it. Pass it in as a parameter, or drop 'static'");
            return null;
        }

        var (origin, type) = local.Visible![name];

        if (!local.Data.Captures.Contains(name))
        {
            local.Data.Captures.Add(name);
            if (local.Uses > 0 || local.Instances.Count > 1) RequestRebind(span);
        }

        var parameter = new ParameterSymbol(
            name, type, function.Parameters.Count + function.Captures.Count)
        {
            CaptureOrigin = origin,
        };
        function.Captures.Add(parameter);
        return parameter;
    }

    /// <summary>
    /// Whether a local function without an object may be given one, and if so
    /// notes that it is to be. Answers false where there is no object to give,
    /// and the caller reports that as it would for any static method.
    /// </summary>
    private bool TryGiveLocalFunctionThis(FunctionSymbol? function, SourceSpan span)
    {
        if (function is null || _localFunctionOf.GetValueOrDefault(function) is not { } local)
            return false;

        if (local.IsStatic)
        {
            diagnostics.Report(Codes.StaticBodyCaptures, span,
                $"'{local.Syntax.Declaration.Name}' is a static local function, so it has no " +
                "'this' and cannot reach the object of the method around it. Pass what it " +
                "needs as a parameter, or drop 'static'");
            return true;
        }

        if (local.ThisType is null) return false;

        if (!local.Data.NeedsThis)
        {
            local.Data.NeedsThis = true;
            RequestRebind(span);
        }

        return true;
    }

    /// <summary>
    /// Asks for the function being bound to be bound again. Where that cannot
    /// happen -- an initializer outside any function -- the use has to follow
    /// the declaration, and saying so is the whole of the answer.
    /// </summary>
    private void RequestRebind(SourceSpan span)
    {
        if (_rebindable)
        {
            _rebindNeeded = true;
            return;
        }

        diagnostics.Report(Codes.LocalFunctionCaptureNotInScope, span,
            "a local function here is used before what it reads from around it is known; " +
            "declare it before it is first used");
    }

    // ============================================================ rebinding

    /// <summary>
    /// Binds a function body, and binds it again for as long as a local
    /// function inside it learned something a call bound earlier did not know.
    /// </summary>
    private void BindFunctionBodyUntilSettled(FunctionSymbol function)
    {
        bool outerRebindable = _rebindable;
        bool outerNeeded = _rebindNeeded;
        var outerOwed = _owedAcrossRebinds;
        var owed = new List<Diagnostic>();
        _rebindable = true;
        _owedAcrossRebinds = owed;

        // Every round learns at least one capture, and there are finitely many
        // names; the bound is a guard against a mistake here, not a limit a
        // program can reach.
        for (int round = 0; ; round++)
        {
            int classes = _classes.Count;
            int functions = _functions.Count;
            int closureCount = _closureCount;
            int memberCaptures = _memberCaptures.Count;
            int reported = diagnostics.Items.Count;
            int owedBefore = owed.Count;
            var paths = new HashSet<string>(_localPaths, StringComparer.Ordinal);

            _rebindNeeded = false;
            using (Enter(_context with { LocalFunctionScopes = [] }))
                BindFunctionBodyCore(function);

            if (!_rebindNeeded || round == 64) break;

            DiscardGenerated(classes, functions);
            _functions.RemoveAll(f => ReferenceEquals(f.Symbol, function));
            _boundFunctions.Remove(function);
            _closureCount = closureCount;
            _memberCaptures.RemoveRange(memberCaptures, _memberCaptures.Count - memberCaptures);
            diagnostics.RewindTo(reported);
            for (int i = owedBefore; i < owed.Count; i++) diagnostics.Report(owed[i]);
            _localPaths.IntersectWith(paths);
        }

        _rebindable = outerRebindable;
        _rebindNeeded = outerNeeded;
        _owedAcrossRebinds = outerOwed;
        outerOwed?.AddRange(owed);
    }

    /// <summary>
    /// Takes back the closure classes and generated functions made since the
    /// marks, and nothing else: an instantiation made on the way is kept,
    /// because its cache would otherwise name something never emitted.
    /// </summary>
    private void DiscardGenerated(int classes, int functions)
    {
        for (int i = _classes.Count - 1; i >= classes; i--)
            if (_generated.Contains(_classes[i])) _classes.RemoveAt(i);

        for (int i = _functions.Count - 1; i >= functions; i--)
            if (_generated.Contains(_functions[i].Symbol)) _functions.RemoveAt(i);
    }

    /// <summary>
    /// Once every body is bound, what each local function captured becomes the
    /// tail of its parameter list, which is all the emitter needs to know.
    /// </summary>
    private void SealLocalFunctions()
    {
        foreach (var function in _functions.Select(f => f.Symbol))
        {
            if (function.LocalPath is null || function.Captures.Count == 0) continue;
            function.Parameters.AddRange(function.Captures);
            function.Captures.Clear();
        }
    }
}
