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
/// Pass 7: statements, the scopes they declare into, and the facts a
/// condition establishes about what a value is holding.
///
/// The facts are here rather than with the expressions that consult
/// them because their difficulty is a statement's: surviving a branch,
/// merging at a join, and being forgotten by an assignment.
/// </summary>
public sealed partial class Binder
{
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
    /// What a check established about a local or a parameter.
    ///
    /// Two kinds: which case a variant is holding, and that an optional is not
    /// null. They share one table because the difficulty is never the fact, it
    /// is its lifetime -- surviving a branch, merging at a join, and being
    /// forgotten by an assignment or by anything a loop might do -- and that is
    /// the same work whichever kind it is.
    /// </summary>
    private sealed record Fact
    {
        /// <summary>The case a variant holds, or null when this is an optional.</summary>
        public VariantCaseSymbol? Case { get; private init; }

        public static Fact Holding(VariantCaseSymbol held) => new() { Case = held };

        /// <summary>An optional that has been checked and is not null.</summary>
        public static readonly Fact NotNull = new();

        public bool ProvesNotNull => Case is null;
    }

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

    /// <summary>
    /// The subject of <c>x != null</c> or <c>null == x</c>, when one side is
    /// the null literal and the other is a narrowable optional.
    ///
    /// A <c>weak C?</c> is deliberately not one. It may die between the check
    /// and the use, which is the whole of what weak means, and the only safe
    /// way to look at one is to read it into a strong optional first.
    /// </summary>
    private static object? NullComparison(BoundBinary test)
    {
        var other = test.Left is BoundNullLiteral ? test.Right
                  : test.Right is BoundNullLiteral ? test.Left
                  : null;

        if (other is null) return null;

        // The access may already have been narrowed by an earlier check, in
        // which case it is not an optional any more and there is nothing to
        // prove.
        if (other.Type is not OptionalTypeSymbol) return null;

        return NarrowableSubject(other);
    }

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
    private (Dictionary<object, Fact> WhenTrue, Dictionary<object, Fact> WhenFalse)
        ConditionFacts(BoundExpression condition)
    {
        switch (condition)
        {
            case BoundVariantTest test
                when NarrowableSubject(test.Value) is { } subject:
            {
                var variant = test.Case.DeclaringVariant;
                var whenTrue = new Dictionary<object, Fact>
                    { [subject] = Fact.Holding(test.Case) };

                var others = variant.Cases.Where(c => c != test.Case).ToList();
                var whenFalse = others.Count == 1
                    ? new Dictionary<object, Fact> { [subject] = Fact.Holding(others[0]) }
                    : [];

                return (whenTrue, whenFalse);
            }

            // `x != null` and `x == null`, in either order. The whole of
            // what an optional can be asked, and the reason `is` was never the
            // shape for this: an optional is not a second type to test for, it
            // is the same type and a null.
            case BoundBinary { Operator: BoundBinaryOp.Equal or BoundBinaryOp.NotEqual } test
                when NullComparison(test) is { } checkedSubject:
            {
                var proved = new Dictionary<object, Fact> { [checkedSubject] = Fact.NotNull };

                return test.Operator == BoundBinaryOp.NotEqual
                    ? (proved, [])
                    : ([], proved);
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

    private static Dictionary<object, Fact> Merge(
        Dictionary<object, Fact> first, Dictionary<object, Fact> second)
    {
        var merged = new Dictionary<object, Fact>(first);
        foreach (var (key, value) in second) merged[key] = value;
        return merged;
    }

    private Dictionary<object, Fact> SnapshotFacts() => new(_variantFacts);

    private void ApplyFacts(Dictionary<object, Fact> facts)
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

    /// <summary>
    /// Which properties of each node kind hold children, worked out once.
    ///
    /// Concurrent because it is the only state in the binder that outlives one
    /// <see cref="Binder"/>, and a plain dictionary written from two of them at
    /// once corrupts rather than merely races. The compiler builds one program
    /// per process today, so nothing in it noticed; the unit tests run classes
    /// in parallel and did, immediately.
    /// </summary>
    private static readonly System.Collections.Concurrent
        .ConcurrentDictionary<Type, System.Reflection.PropertyInfo[]> ChildProperties = new();

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
        var properties = ChildProperties.GetOrAdd(node.GetType(), static type =>
            type.GetProperties()
                .Where(p => p.GetIndexParameters().Length == 0 &&
                            (typeof(Syntax.SyntaxNode).IsAssignableFrom(p.PropertyType) ||
                             typeof(System.Collections.IEnumerable).IsAssignableFrom(p.PropertyType)))
                .ToArray());

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

                // `var xs = [1, 2, 3]`. Unlike a lambda or a bare case name, an
                // array literal carries values, and values have types -- so
                // there is something to infer from and no need to write it out.
                if (initializer is BoundArrayDraft loose)
                    initializer = SettleArrayFromElements(loose);

                type = initializer.Type;
                if (type.IsVoid())
                {
                    diagnostics.Error("SL0221", syntax.Initializer.Span,
                        "cannot infer a type from an expression of type 'void'");
                    type = ErrorTypeSymbol.Instance;
                }
                else if (type is LambdaType)
                {
                    // A lambda has no type of its own -- it becomes whatever it
                    // is assigned to -- and `var` is the one place with nothing
                    // to tell it what that is. Without this the declaration
                    // bound cleanly and emitted `store ptr 0`, which clang
                    // rejected as a compiler bug rather than as this mistake.
                    diagnostics.Error("SL0553", syntax.Initializer.Span,
                        $"'{syntax.Name}' cannot be a 'var': a lambda has no type of its own " +
                        "and becomes what it is assigned to, so there is nothing here to infer " +
                        "from. Write the type out -- a delegate, or an interface with exactly " +
                        "one method");
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

        _variantFacts = new Dictionary<object, Fact>(entry);
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
}
