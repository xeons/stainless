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
        if (function.Event is not null) { BindEventAccessor(function); return; }
        if (function.Body is null) return;
        if (!_boundFunctions.Add(function)) return;

        // Bound against the imports of the file it was written in.
        if (function.Scope is not null) _currentScope = function.Scope;

        _currentFunction = function;
        _scopes.Clear();
        _loopDepth = 0;
        _switchDepth = 0;
        _variantFacts = [];
        _labels.Clear();
        _checkedArithmetic = false;

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

        // BindBlock pushes one more for the body's own block, and that is the
        // depth a label has to be at.
        _bodyDepth = _scopes.Count + 1;

        var body = BindBlock(function.Body);
        PopScope();

        // What a getter reads, so that capturing the property can be tested
        // against what is written the way capturing a field already is.
        NoteGetterReads(function, body);

        _constructorChain = null;

        // A jump with nowhere to land, and a label nothing lands on. The first
        // is an error; the second is a warning, because a label costs nothing
        // and deleting the last jump to one is an ordinary edit.
        foreach (var label in _labels.Values)
        {
            if (label.Declared is null && label.FirstUse is { } used)
                diagnostics.Error("SL0589", used,
                    $"there is no label '{label.Name}' in '{function.Name}'; a 'goto' names a " +
                    "label in the function it is written in, and nowhere else");
            else if (label.Declared is { } declared && !label.IsUsed)
                diagnostics.Warning("SL0591", declared,
                    $"nothing jumps to '{label.Name}'");
        }

        if (function.Kind == FunctionKind.Constructor)
        {
            body = WithFieldInitializers(function, body);
            body = WithBaseConstruction(function, body);
        }

        if (!function.ReturnType.IsVoid() && !function.ReturnType.IsError() && !AlwaysReturns(body))
            diagnostics.Error("SL0217", function.Span,
                $"not all paths through '{function.Name}' return a value of type '{function.ReturnType.Name}'");

        CheckOutParametersAssigned(function, body);

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
    /// Puts the field initializers at the head of a constructor, in the order
    /// they were declared.
    ///
    /// <para>
    /// <b>After the base construction and before the body.</b> A field
    /// initializer may not read anything -- it is bound with <c>this</c> out of
    /// reach -- so nothing in it can see whether the base has run; what the
    /// order buys is that the constructor's own body has the last word, which
    /// is what somebody writing <c>Width = width;</c> beside <c>int Width =
    /// 80;</c> means.
    /// </para>
    ///
    /// <para>
    /// <b>Not in a constructor that chains to <c>this(...)</c>.</b> The one it
    /// delegates to runs them, and running them again would undo whatever that
    /// constructor had decided. It is the same rule C# keeps, for the same
    /// reason as the base chain's.
    /// </para>
    ///
    /// <para>
    /// The initializers of a base class are not here either: the base's own
    /// constructor runs them, and that call is what this constructor starts
    /// with.
    /// </para>
    /// </summary>
    private BoundBlock WithFieldInitializers(FunctionSymbol constructor, BoundBlock body)
    {
        if (constructor.ContainingType is not ClassTypeSymbol classType) return body;
        if (_delegated.ContainsKey(constructor)) return body;

        var initialized = classType.Fields
            .Where(f => f.InitializerSyntax is not null)
            .ToList();

        if (initialized.Count == 0) return body;

        var self = constructor.Parameters[0];
        var savedScope = _currentScope;
        var statements = new List<BoundStatement>();

        foreach (var field in initialized)
        {
            // Bound against the file the *field* was written in, which is not
            // necessarily this constructor's: a type may be declared across
            // files, and a name means what it meant where it was written.
            if (field.InitializerScope is not null) _currentScope = field.InitializerScope;

            var written = field.InitializerSyntax!;

            // With `this` out of reach, so an initializer cannot read a field
            // that has not been given its value yet -- the mistake C# also
            // refuses, and the reason it refuses it.
            _initializingField = true;
            _reportedFieldInitializerReach = false;
            var value = BindConversion(BindExpression(written), field.Type, written.Span);
            _initializingField = false;

            var target = new BoundFieldAccess(
                written.Span, new BoundThis(written.Span, classType, self), field);

            statements.Add(new BoundExpressionStatement(
                written.Span, new BoundAssignment(written.Span, target, value)));
        }

        _currentScope = savedScope;

        // After an explicit `base(...)` or the chain check would move it; the
        // implicit one is prepended after this runs.
        int at = _boundExplicitChain && body.Statements.Count > 0 ? 1 : 0;

        return new BoundBlock(body.Span,
            [.. body.Statements.Take(at), .. statements, .. body.Statements.Skip(at)]);
    }

    /// <summary>
    /// Set while a field initializer is being bound, which is the one place
    /// <c>this</c> is out of reach inside a constructor.
    /// </summary>
    private bool _initializingField;

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

    /// <summary>
    /// Supplies the body of <c>add_Name</c> or <c>remove_Name</c>, neither of
    /// which has syntax to bind.
    ///
    /// Both **replace** the array rather than change it, which is the one
    /// decision in here worth the words. A raise reads the field once and walks
    /// what it read, so a handler that unsubscribes while the event is being
    /// raised leaves that walk alone -- it is looking at the old array, which
    /// still holds exactly the subscribers that were there when the raise
    /// began. Mutating in place would have that walk skip a handler, or run off
    /// the end. It is also why the storage is an array and not a list.
    ///
    /// Built as bound nodes rather than as synthesised source, for the reason
    /// <see cref="BindAutoAccessor"/> is: the storage stays unnameable, because
    /// there is no point at which a name has to resolve to it.
    /// </summary>
    private void BindEventAccessor(FunctionSymbol accessor)
    {
        if (!_boundFunctions.Add(accessor)) return;
        if (accessor.Event?.BackingField is not { } field) return;

        if (ReferenceEquals(accessor, accessor.Event.Raise))
        {
            BindEventRaiser(accessor, field);
            return;
        }

        var span = accessor.Span;
        var closure = accessor.Event.Type;
        var array = ArrayOf(closure);
        var count = PrimitiveTypeSymbol.NUInt;

        var receiver = Receiver(span, accessor.Parameters[0]);
        var handler = new BoundParameterAccess(span, accessor.Parameters[1]);

        // `this.<name>`, read afresh at each mention: the field is assigned
        // near the end, and everything before it must see what is there now.
        BoundExpression Storage() => new BoundFieldAccess(span, receiver, field);

        BoundExpression Number(ulong value) => new BoundLiteral(span, count, value);

        BoundExpression Arithmetic(BoundExpression left, BoundBinaryOp op, BoundExpression right) =>
            new BoundBinary(span, count, left, op, right);

        BoundExpression Compare(BoundExpression left, BoundBinaryOp op, BoundExpression right) =>
            new BoundBinary(span, PrimitiveTypeSymbol.Bool, left, op, right);

        var statements = new List<BoundStatement>();
        var locals = new List<LocalSymbol>();

        LocalSymbol Declare(string name, TypeSymbol type, BoundExpression initial)
        {
            var local = new LocalSymbol(name, type, isConst: false);
            locals.Add(local);
            statements.Add(new BoundLocalDeclaration(span, local, initial));
            return local;
        }

        // A counted loop over the old array: `for (nuint i = 0; i < n; i++)`.
        BoundStatement Walk(LocalSymbol limit, Func<LocalSymbol, BoundStatement> body)
        {
            var index = new LocalSymbol("i", count, isConst: false);
            var declaration = new BoundLocalDeclaration(span, index, Number(0));

            var loop = new BoundFor(
                span,
                declaration,
                Compare(new BoundLocalAccess(span, index), BoundBinaryOp.Less,
                    new BoundLocalAccess(span, limit)),
                new BoundIncrement(span, new BoundLocalAccess(span, index),
                    isPrefix: false, isIncrement: true),
                body(index));

            var block = new BoundBlock(span, [loop]);
            block.Locals.Add(index);
            return block;
        }

        BoundExpression At(LocalSymbol source, LocalSymbol index) =>
            new BoundIndex(span, closure, new BoundLocalAccess(span, source),
                new BoundLocalAccess(span, index));

        var was = Declare("was", array, Storage());
        var length = Declare("length", count, new BoundArrayLength(span, count,
            new BoundLocalAccess(span, was)));

        if (accessor.IsEventAdd)
        {
            // One longer, everything copied across, the new one last. Appending
            // rather than prepending is what makes subscribers run in the order
            // they subscribed, which is the order anyone reading the code
            // expects and the only one worth promising.
            var grown = Declare("grown", array, new BoundNewArray(span, array,
                Arithmetic(new BoundLocalAccess(span, length), BoundBinaryOp.Add, Number(1))));

            statements.Add(Walk(length, i => new BoundExpressionStatement(span,
                new BoundAssignment(span, At(grown, i), At(was, i)))));

            statements.Add(new BoundExpressionStatement(span, new BoundAssignment(
                span,
                new BoundIndex(span, closure, new BoundLocalAccess(span, grown),
                    new BoundLocalAccess(span, length)),
                handler)));

            statements.Add(new BoundExpressionStatement(span,
                new BoundAssignment(span, Storage(), new BoundLocalAccess(span, grown))));

            Finish();
            return;
        }

        // Removing. The first equal subscriber goes and the rest stay, which
        // matters because the same handler may be subscribed twice: `-=` undoes
        // one `+=`, not every one of them.
        //
        // Found by walking the whole array rather than stopping, so this needs
        // no break and no early return -- `found == length` means "not there",
        // and the first match wins because later ones see it already set.
        var found = Declare("found", count, new BoundLocalAccess(span, length));

        statements.Add(Walk(length, i => new BoundIf(
            span,
            new BoundBinary(
                span, PrimitiveTypeSymbol.Bool,
                Compare(new BoundLocalAccess(span, found), BoundBinaryOp.Equal,
                    new BoundLocalAccess(span, length)),
                BoundBinaryOp.LogicalAnd,
                new BoundClosureEqual(span, closure, At(was, i), handler, negated: false)),
            new BoundExpressionStatement(span, new BoundAssignment(
                span, new BoundLocalAccess(span, found), new BoundLocalAccess(span, i))),
            null)));

        // Nothing to do, and nothing said: unsubscribing something that was
        // never subscribed is how a tidy-up runs twice, not a mistake.
        var shrunk = new LocalSymbol("shrunk", array, isConst: false);

        var removal = new BoundBlock(span, [
            new BoundLocalDeclaration(span, shrunk, new BoundNewArray(span, array,
                Arithmetic(new BoundLocalAccess(span, length), BoundBinaryOp.Subtract, Number(1)))),

            Walk(length, i => new BoundIf(
                span,
                Compare(new BoundLocalAccess(span, i), BoundBinaryOp.NotEqual,
                    new BoundLocalAccess(span, found)),
                new BoundExpressionStatement(span, new BoundAssignment(
                    span,
                    new BoundIndex(span, closure, new BoundLocalAccess(span, shrunk),
                        // Everything after the one that went shifts down by one.
                        new BoundConditional(
                            span, count,
                            Compare(new BoundLocalAccess(span, i), BoundBinaryOp.Less,
                                new BoundLocalAccess(span, found)),
                            new BoundLocalAccess(span, i),
                            Arithmetic(new BoundLocalAccess(span, i), BoundBinaryOp.Subtract,
                                Number(1)))),
                    At(was, i))),
                null)),

            new BoundExpressionStatement(span,
                new BoundAssignment(span, Storage(), new BoundLocalAccess(span, shrunk))),
        ]);

        removal.Locals.Add(shrunk);

        statements.Add(new BoundIf(
            span,
            Compare(new BoundLocalAccess(span, found), BoundBinaryOp.Less,
                new BoundLocalAccess(span, length)),
            removal,
            null));

        Finish();

        void Finish()
        {
            var block = new BoundBlock(span, statements);
            block.Locals.AddRange(locals);
            _functions.Add(new BoundFunction(accessor, block));
        }
    }

    /// <summary>
    /// Supplies the body of <c>raise_Name</c>: every subscriber, in the order
    /// they subscribed, each given the arguments the raise was written with.
    ///
    /// The array is read once, into a local, and that local is what the loop
    /// walks. Everything about raising being safe rests on that one line: a
    /// handler may subscribe or unsubscribe while it runs, and both replace the
    /// field with a different array, which this loop is no longer looking at.
    /// So the subscribers that were there when the raise began are exactly the
    /// ones that run -- no more, no fewer, and none of them twice.
    /// </summary>
    private void BindEventRaiser(FunctionSymbol raiser, FieldSymbol field)
    {
        var span = raiser.Span;
        var closure = raiser.Event!.Type;
        var array = ArrayOf(closure);
        var count = PrimitiveTypeSymbol.NUInt;

        var receiver = Receiver(span, raiser.Parameters[0]);

        var was = new LocalSymbol("was", array, isConst: false);
        var index = new LocalSymbol("i", count, isConst: false);

        var arguments = raiser.Parameters
            .Where(p => !p.IsThis)
            .Select(BoundExpression (p) => new BoundParameterAccess(span, p))
            .ToList();

        var call = new BoundClosureCall(
            span, closure,
            new BoundIndex(span, closure,
                new BoundLocalAccess(span, was), new BoundLocalAccess(span, index)),
            arguments);

        var loop = new BoundFor(
            span,
            new BoundLocalDeclaration(span, index, new BoundLiteral(span, count, 0UL)),
            new BoundBinary(
                span, PrimitiveTypeSymbol.Bool,
                new BoundLocalAccess(span, index), BoundBinaryOp.Less,
                new BoundArrayLength(span, count, new BoundLocalAccess(span, was))),
            new BoundIncrement(span, new BoundLocalAccess(span, index),
                isPrefix: false, isIncrement: true),
            new BoundExpressionStatement(span, call));

        var inner = new BoundBlock(span, [loop]);
        inner.Locals.Add(index);

        var block = new BoundBlock(span, [
            new BoundLocalDeclaration(span, was, new BoundFieldAccess(span, receiver, field)),
            inner,
        ]);

        block.Locals.Add(was);

        _functions.Add(new BoundFunction(raiser, block));
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
    /// The two names <c>x is Case n</c> needs, on their way to the statements
    /// that will declare them.
    ///
    /// A binding is only meaningful where the test succeeded, so nothing here
    /// is a declaration yet: the <see cref="Spills"/> are declared around the
    /// <c>if</c> -- they hold the thing tested, evaluated once -- and the
    /// <see cref="Bindings"/> at the top of the branch the test proved. That
    /// is also why the form is the whole of a condition and not part of one:
    /// under a <c>&amp;&amp;</c> the spill would run when the test did not.
    /// </summary>
    private sealed class PatternScope
    {
        public List<BoundStatement> Spills { get; } = [];

        public List<(string Name, TypeSymbol Type, SourceSpan Span, BoundExpression Value)>
            Bindings { get; } = [];
    }

    /// <summary>Non-null only while the whole condition of an `if` is being bound.</summary>
    private PatternScope? _patterns;

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

        if (node is Syntax.AsmOperandSyntax { Direction: not Syntax.AsmDirection.In } output &&
            RootName(output.Value) is { } stored)
            names.Add(stored);

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

    /// <summary>
    /// Every <c>out</c> parameter is written before the function returns.
    ///
    /// This is the one place the language does definite-assignment analysis,
    /// and it is here because <c>out</c> is the one place it is load-bearing:
    /// the caller's variable may never have held anything, and the promise the
    /// keyword makes is that it does now. A local read before it is written is
    /// still nobody's business but the author's, which is a gap, but a
    /// consistent one.
    ///
    /// The caller's storage is also cleared before the call, so the worst a
    /// hole here can produce is a zero rather than whatever the stack held.
    /// </summary>
    private void CheckOutParametersAssigned(FunctionSymbol function, BoundBlock body)
    {
        var outward = function.Parameters
            .Where(p => p.Mode == ParameterMode.Out)
            .ToList();

        if (outward.Count == 0) return;

        // A jump can arrive at a label from anywhere, so "what has been written
        // by the time control reaches here" stops being a question this walk
        // can answer. Rather than guess, the check stands down -- and the
        // clearing at the call site is what still holds.
        if (_labels.Count > 0) return;

        foreach (var parameter in outward)
            if (!Assigns(body, parameter, false, function) && !AlwaysReturns(body))
                diagnostics.Error("SL0600", function.Span,
                    $"'{function.Name}' can return without writing to '{parameter.Name}', " +
                    "which is what 'out' promises the caller. Assign it on every path, or " +
                    "make it 'ref' and let the caller decide what it starts as");
    }

    /// <summary>
    /// Whether the parameter is certainly written by the time this statement is
    /// through, reporting any <c>return</c> reached before it was.
    /// </summary>
    private bool Assigns(
        BoundStatement statement, ParameterSymbol target, bool assigned, FunctionSymbol owner)
    {
        switch (statement)
        {
            case BoundBlock block:
                foreach (var inner in block.Statements)
                    assigned = Assigns(inner, target, assigned, owner);
                return assigned;

            case BoundExpressionStatement expression:
                return assigned || Writes(expression.Expression, target);

            case BoundLocalDeclaration declaration:
                return assigned || Writes(declaration.Initializer, target);

            case BoundReturn returned:
                if (!assigned && !Writes(returned.Value, target))
                    diagnostics.Error("SL0600", returned.Span,
                        $"'{owner.Name}' returns here without having written to " +
                        $"'{target.Name}', which is what 'out' promises the caller");

                // Nothing follows a return, so whatever it left is not read.
                return true;

            case BoundIf branch:
            {
                bool then = Assigns(branch.Then, target, assigned || Writes(branch.Condition, target), owner);
                bool otherwise = branch.Else is null
                    ? assigned || Writes(branch.Condition, target)
                    : Assigns(branch.Else, target, assigned || Writes(branch.Condition, target), owner);
                return then && otherwise;
            }

            // A `do` body always runs, so what it writes is written. Every
            // other loop may run no times at all.
            case BoundDoWhile loop:
                return Assigns(loop.Body, target, assigned, owner);

            case BoundWhile loop:
                Assigns(loop.Body, target, assigned, owner);
                return assigned;

            case BoundFor loop:
                Assigns(loop.Body, target, assigned, owner);
                return assigned;

            case BoundSwitch chosen:
            {
                bool everyArm = chosen.IsExhaustive || chosen.Sections.Any(s => s.IsDefault);
                bool all = everyArm && chosen.Sections.Count > 0;

                foreach (var section in chosen.Sections)
                    all &= Assigns(section.Body, target, assigned, owner);

                return assigned || all;
            }

            case BoundParallel parallel:
                Assigns(parallel.Body, target, assigned, owner);
                return assigned;

            // An output is stored once the block has run, which is as certain
            // as an assignment: nothing in the language can leave the block
            // any other way.
            case BoundAsm assembly:
                return assigned || assembly.IsIncomplete || assembly.Operands.Any(o =>
                    o.IsOutput
                        ? o.Value is BoundParameterAccess written &&
                          ReferenceEquals(written.Parameter, target)
                        : Writes(o.Value, target));

            default:
                return assigned;
        }
    }

    /// <summary>
    /// Whether evaluating this expression certainly writes the parameter --
    /// by assignment, or by handing it on as somebody else's <c>out</c>.
    /// </summary>
    private static bool Writes(BoundExpression? expression, ParameterSymbol target) =>
        expression switch
        {
            null => false,

            BoundAssignment { Target: BoundParameterAccess written } assignment =>
                ReferenceEquals(written.Parameter, target) || Writes(assignment.Value, target),

            BoundAssignment assignment => Writes(assignment.Value, target),

            // `Inner(out mine)` is a write, because Inner is held to the same
            // promise this function is.
            BoundAddressOf { FromOutKeyword: true, Operand: BoundParameterAccess passed } =>
                ReferenceEquals(passed.Parameter, target),

            BoundCall call =>
                Writes(call.Receiver, target) || call.Arguments.Any(a => Writes(a, target)),

            BoundIndirectCall call =>
                Writes(call.Target, target) || call.Arguments.Any(a => Writes(a, target)),

            BoundConversion conversion => Writes(conversion.Operand, target),
            BoundBinary binary => Writes(binary.Left, target) || Writes(binary.Right, target),
            BoundUnary unary => Writes(unary.Operand, target),

            // Only the condition is certain: an arm may not be the one taken.
            BoundConditional conditional => Writes(conditional.Condition, target),

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

    private BoundStatement BindStatement(StatementSyntax syntax)
    {
        if (++_bindDepth > Source.Recursion.MaxDepth)
        {
            _bindDepth--;
            return new BoundExpressionStatement(
                syntax.Span, new BoundErrorExpression(syntax.Span));
        }

        try { return BindStatementCore(syntax); }
        finally { _bindDepth--; }
    }

    private BoundStatement BindStatementCore(StatementSyntax syntax) => syntax switch
    {
        BlockSyntax block => BindBlock(block),
        LocalDeclSyntax local => BindLocalDeclaration(local),
        DeconstructSyntax taken => BindDeconstruct(taken),
        ExpressionStatementSyntax expression => BindExpressionStatement(expression),
        IfSyntax ifStatement => BindIf(ifStatement),
        WhileSyntax whileStatement => BindWhile(whileStatement),
        DoWhileSyntax doWhile => BindDoWhile(doWhile),
        LabelSyntax label => BindLabel(label),
        GotoSyntax jump => BindGoto(jump),
        CheckedBlockSyntax guarded => BindCheckedBlock(guarded),
        AsmSyntax assembly => BindAsm(assembly),
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
                    // A lambda that wrote its parameter types out has said
                    // everything but its result, and binding the body answers
                    // that -- so it has a type of its own and `var` can hold
                    // it. One that did not has nothing to infer from, and
                    // without this the declaration bound cleanly and emitted
                    // `store ptr 0`, which clang rejected as a compiler bug
                    // rather than as this mistake.
                    var written = ((BoundLambda)initializer).Syntax;

                    if (NaturalClosureType(written) is { } natural)
                    {
                        type = natural;
                        initializer = BindConversion(initializer, natural, syntax.Initializer.Span);
                    }
                    else
                    {
                        diagnostics.Error("SL0553", syntax.Initializer.Span,
                            $"'{syntax.Name}' cannot be a 'var': " +
                            (written.Expression is null
                                ? "a lambda with a block body takes its result from what its " +
                                  "'return's agree on, and that is decided by the type it is " +
                                  "becoming rather than the other way round. Write the type " +
                                  "out, or make the body one expression"
                                : "this lambda does not say what its parameters are, so there " +
                                  "is nothing here to infer from. Write them -- " +
                                  "'(int x) => x * 2' -- or write the type out"));
                        type = ErrorTypeSymbol.Instance;
                    }
                }
                else if (type is FunctionGroupType)
                {
                    // The same hole as the lambda above, and it emitted the
                    // same `store ptr 0`. A function name names an overload
                    // set, not a value: what settles it is the delegate or
                    // closure it is stored in, and `var` supplies neither.
                    bool bound = initializer is BoundFunctionGroup { Receiver: not null };

                    diagnostics.Error("SL0553", syntax.Initializer.Span,
                        $"'{syntax.Name}' cannot be a 'var': " +
                        (bound
                            ? "a method reached through an object is a closure, and which " +
                              "closure it is has to be written out. Give the type, or call it " +
                              "with '()'"
                            : "a function name is an overload set rather than a value, and what " +
                              "picks the overload is the delegate it is stored in. Write the " +
                              "type out, or call it with '()'"));
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

    /// <summary>
    /// Whether evaluating this does something, or only produces a value that
    /// a statement then drops.
    ///
    /// A `?.` and a `??=` are a conditional wrapped in a let, and what makes
    /// them worth writing is inside: `a?.Save()` is a call that may not happen,
    /// which is an effect. So this looks through both rather than judging the
    /// shape it arrived in.
    /// </summary>
    private static bool Effective(BoundExpression expression) => expression switch
    {
        BoundAssignment or BoundPropertyAssignment or BoundCall or BoundIndirectCall
            or BoundClosureCall or BoundIncrement or BoundPropertyIncrement
            or BoundNew or BoundErrorExpression => true,

        BoundLet held => Effective(held.Body),
        BoundConditional chosen => Effective(chosen.WhenTrue) || Effective(chosen.WhenFalse),
        _ => false,
    };

    /// <summary>
    /// <c>var (count, name) = Split(line);</c>.
    ///
    /// The tuple is held in a local of its own so that whatever produced it is
    /// evaluated once, and each name is then a local initialised from one of
    /// its fields. Names are wanted here rather than in the type: a tuple's own
    /// fields are <c>Item1</c> upwards, and what they mean is a property of the
    /// call that answered with them.
    /// </summary>
    private BoundStatement BindDeconstruct(DeconstructSyntax syntax)
    {
        var value = BindExpression(syntax.Value);
        if (value.Type.IsError()) return new BoundBlock(syntax.Span, []);

        if (value.Type is not TupleTypeSymbol tuple)
        {
            diagnostics.Error("SL0608", syntax.Value.Span,
                $"'{value.Type.Name}' is not a tuple, so there is nothing here to take apart");
            return new BoundBlock(syntax.Span, []);
        }

        if (tuple.Elements.Count != syntax.Names.Count)
        {
            diagnostics.Error("SL0609", syntax.Span,
                $"'{tuple.Name}' has {Counted(tuple.Elements.Count, "element")}, and this " +
                $"names {syntax.Names.Count}");
            return new BoundBlock(syntax.Span, []);
        }

        var source = new LocalSymbol(SyntheticName("taken"), tuple, isConst: false);

        var names = new List<LocalSymbol>(syntax.Names.Count);
        for (int i = 0; i < syntax.Names.Count; i++)
            names.Add(DeclareLocal(
                syntax.Names[i], tuple.Elements[i], isConst: false, syntax.NameSpans[i]));

        return new BoundDeconstruct(syntax.Span, source, value, names);
    }

    private BoundStatement BindExpressionStatement(ExpressionStatementSyntax syntax)
    {
        var expression = BindExpression(syntax.Expression);

        bool hasEffect = Effective(expression);
        if (!hasEffect)
            diagnostics.Warning("SL0222", syntax.Span,
                "this expression has no effect; its result is discarded");

        return new BoundExpressionStatement(syntax.Span, expression);
    }

    private BoundStatement BindIf(IfSyntax syntax)
    {
        // A binding is offered only where one can be given a scope, which is
        // the whole of a condition. Parentheses are not a node here, so
        // `if ((x is Circle c))` arrives as the test itself and works too.
        var outer = _patterns;
        _patterns = syntax.Condition is TypeTestSyntax ? new PatternScope() : null;

        var condition = BindCondition(syntax.Condition);

        var patterns = _patterns;
        _patterns = outer;

        var (whenTrue, whenFalse) = ConditionFacts(condition);

        var entry = SnapshotFacts();

        ApplyFacts(whenTrue);
        var then = BindPatternBranch(patterns, syntax.Then);

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

        BoundStatement result = new BoundIf(syntax.Span, condition, then, otherwise);

        // The thing tested is evaluated once, before the test, so its name is
        // declared around the whole `if` rather than inside either branch.
        return patterns is null || patterns.Spills.Count == 0
            ? result
            : new BoundBlock(syntax.Span, [.. patterns.Spills, result]);
    }

    /// <summary>
    /// The branch a test proved, with what it found declared at the top of it.
    ///
    /// The declarations go here rather than beside the spill because this is
    /// the only place they are true: reading a case's payload where the tag
    /// says something else would be reading one type's bytes as another, and
    /// for a payload holding a reference it would be retaining a value that
    /// was never there.
    /// </summary>
    private BoundStatement BindPatternBranch(PatternScope? patterns, StatementSyntax body)
    {
        if (patterns is null || patterns.Bindings.Count == 0) return BindStatement(body);

        PushScope();

        var statements = new List<BoundStatement>();
        foreach (var (name, type, span, value) in patterns.Bindings)
        {
            var local = DeclareLocal(name, type, isConst: true, span);
            statements.Add(new BoundLocalDeclaration(span, local, value));
        }

        statements.Add(BindStatement(body));

        PopScope();
        return new BoundBlock(body.Span, statements);
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

    /// <summary>
    /// <c>do { ... } while (c);</c>.
    ///
    /// The body is bound the way a <c>while</c>'s is -- what it assigns to is
    /// unknown inside it, and the condition proves nothing after it -- with one
    /// difference that matters: the condition has not been tested when the body
    /// first runs, so nothing it would prove may be applied going in.
    /// </summary>
    private BoundStatement BindDoWhile(DoWhileSyntax syntax)
    {
        if (_variantFacts.Count > 0) InvalidateAssignedIn(syntax.Body);

        var entry = SnapshotFacts();

        _loopDepth++;
        var body = BindStatement(syntax.Body);
        _loopDepth--;

        var condition = BindCondition(syntax.Condition);

        _variantFacts = entry;
        return new BoundDoWhile(syntax.Span, body, condition);
    }

    /// <summary>
    /// <c>name:</c>.
    ///
    /// Labels are per function rather than per block, which is C's rule and
    /// C#'s: a jump may leave a block, and a label a jump could not reach would
    /// be a label for nothing.
    /// </summary>
    private BoundStatement BindLabel(LabelSyntax syntax)
    {
        var label = LabelNamed(syntax.Name);

        if (label.Declared is not null)
        {
            diagnostics.Error("SL0588", syntax.Span,
                $"'{syntax.Name}' is already a label in this function; a 'goto' names one " +
                "place, so two of a name would be a jump with two destinations");
            return new BoundBlock(syntax.Span, []);
        }

        // A label only at the top level of the function body, which is what
        // makes the jump's reference counting decidable: everything a `goto`
        // has to release is exactly the scopes between it and there, and a
        // label nested somewhere else would mean the answer depended on which
        // jump arrived. Every use a `goto` is actually for -- out of nested
        // loops, forward to a cleanup, back to a retry -- names one of these.
        if (_scopes.Count != _bodyDepth)
        {
            diagnostics.Error("SL0595", syntax.Span,
                $"label '{syntax.Name}' is inside a block; a label goes at the top level of " +
                "the function, so that what a jump to it has to release is the same whichever " +
                "jump arrives");
            return new BoundBlock(syntax.Span, []);
        }

        label.Declared = syntax.Span;

        // A variant narrowed above a label is not narrowed at it: a jump from
        // anywhere in the function arrives here, and what it proved on the way
        // is not what the fall-through proved.
        _variantFacts = [];
        return new BoundLabel(syntax.Span, label);
    }

    private BoundStatement BindGoto(GotoSyntax syntax)
    {
        var label = LabelNamed(syntax.Label);
        label.IsUsed = true;
        label.FirstUse ??= syntax.LabelSpan;

        // Every label is at the top level of the function, so every label is
        // outside the `parallel` block this jump is in -- which makes this a
        // jump out of work that has to finish where it was started.
        if (_parallelDepth > 0)
            diagnostics.Error("SL0590", syntax.Span,
                $"'goto {syntax.Label}' is inside a 'parallel' block, and every label is " +
                "outside one; the work queued in a block has to finish there, so there is " +
                "nothing a jump out of it could mean. Leave with a flag the block sets");

        return new BoundGoto(syntax.Span, label);
    }

    /// <summary>The label of that name in this function, made on first mention.</summary>
    private LabelSymbol LabelNamed(string name)
    {
        if (_labels.TryGetValue(name, out var existing)) return existing;
        return _labels[name] = new LabelSymbol(name);
    }

    /// <summary>
    /// <c>checked { ... }</c> and <c>unchecked { ... }</c>: the arithmetic
    /// written inside is bound with overflow noticed, or with it ignored.
    /// </summary>
    private BoundStatement BindCheckedBlock(CheckedBlockSyntax syntax)
    {
        bool previous = _checkedArithmetic;
        _checkedArithmetic = syntax.IsChecked;
        var body = BindBlock(syntax.Body);
        _checkedArithmetic = previous;
        return body;
    }

    /// <summary>
    /// <c>asm (in rcx = n, out rax = r) { ... }</c>.
    ///
    /// The text is not looked at: it is the target assembler's, and that
    /// assembler is where a mistake in it is found (SL0723, from the driver).
    /// What is checked here is everything the assembler cannot see — which
    /// registers exist on this target, what a value may be to travel in one,
    /// and whether an output has somewhere to go.
    /// </summary>
    private BoundStatement BindAsm(AsmSyntax syntax)
    {
        var target = TargetPlatform.Current;
        var operands = new List<BoundAsmOperand>();
        var named = new Dictionary<string, AsmOperandSyntax>(StringComparer.Ordinal);

        foreach (var operand in syntax.Operands)
        {
            // Bound first, so that a mistake in the expression is reported even
            // when the register is also wrong.
            var value = BindExpression(operand.Value);

            if (AsmRegisters.Find(target, operand.Register) is not { } register)
            {
                diagnostics.Error("SL0716", operand.RegisterSpan,
                    $"'{operand.Register}' is not a register an operand can name on " +
                    $"{AsmRegisters.ArchitectureName(target)}, which is what this build is " +
                    $"for; the registers are {AsmRegisters.Examples(target)}");
                continue;
            }

            if (register.Refusal is { } refusal)
            {
                diagnostics.Error("SL0717", operand.RegisterSpan,
                    $"'{register.Name}' cannot be an 'asm' operand: it is {refusal}");
                continue;
            }

            // One `in` and one `out` may share a register: the value goes in from
            // one place and comes out to another, which is `inout` with the two
            // places different, and the first thing anyone writes for it.
            string direction = operand.Direction switch
            {
                AsmDirection.In => "in",
                AsmDirection.Out => "out",
                _ => "inout",
            };

            if (named.TryGetValue(register.Whole + "/" + direction, out var earlier) ||
                named.TryGetValue(register.Whole + "/inout", out earlier) ||
                (operand.Direction == AsmDirection.InOut &&
                 (named.TryGetValue(register.Whole + "/in", out earlier) ||
                  named.TryGetValue(register.Whole + "/out", out earlier))))
            {
                bool sameName = string.Equals(
                    earlier.Register, operand.Register, StringComparison.OrdinalIgnoreCase);

                diagnostics.Error("SL0718", operand.RegisterSpan,
                    $"'{operand.Register}' is named twice" +
                    (sameName ? "" : $", the first time as '{earlier.Register}'") +
                    "; a register holds one value going in and one coming out, so it may be " +
                    "one 'in' and one 'out', or one 'inout'");
                continue;
            }

            named[register.Whole + "/" + direction] = operand;

            if (value.Type.IsError()) continue;

            if (operand.Direction != AsmDirection.Out)
                value = AsmLiteral(value, register);

            if (!AsmValueFits(operand, register, value)) continue;

            if (operand.Direction != AsmDirection.In && !AsmPlace(operand, value)) continue;

            bool single = value.Type is PrimitiveTypeSymbol { Kind: PrimitiveKind.Float };
            operands.Add(new BoundAsmOperand(
                operand.Span, operand.Direction, register,
                AsmRegisters.Constraint(target, register, single), value));
        }

        var clobbers = AsmRegisters.Clobbers(target, operands.Select(o => o.Register));
        return new BoundAsm(syntax.Span, syntax.Text, syntax.TextSpan, operands, clobbers)
        {
            IsIncomplete = operands.Count != syntax.Operands.Count,
        };
    }

    /// <summary>
    /// An integer literal given to a register takes the register's width when
    /// it fits there, as it would a declaration's: <c>in al = 200</c> is a
    /// byte, not an <c>int</c> too wide for the register. Given to a vector
    /// register, it is the floating-point number it names.
    /// </summary>
    private BoundExpression AsmLiteral(BoundExpression value, AsmRegister register)
    {
        if (IntegerLiteral(value) is not { } written) return value;

        TypeSymbol wanted = register switch
        {
            { Kind: AsmRegisterKind.Vector, Bits: 32 } => PrimitiveTypeSymbol.Float,
            { Kind: AsmRegisterKind.Vector } => PrimitiveTypeSymbol.Double,
            { Bits: 8 } => written.Negative ? PrimitiveTypeSymbol.SByte : PrimitiveTypeSymbol.Byte,
            { Bits: 16 } => written.Negative ? PrimitiveTypeSymbol.Short : PrimitiveTypeSymbol.UShort,
            { Bits: 32 } => written.Negative ? PrimitiveTypeSymbol.Int : PrimitiveTypeSymbol.UInt,
            _ => written.Negative ? PrimitiveTypeSymbol.Long : PrimitiveTypeSymbol.ULong,
        };

        // One that does not fit keeps its own type, and the width check below
        // is what says so.
        return ConstantFits(value, wanted) ? BindConversion(value, wanted, value.Span) : value;
    }

    /// <summary>
    /// Whether a value of this type may travel in this register: plain data of
    /// the register's kind, no wider than the register is.
    /// </summary>
    private bool AsmValueFits(AsmOperandSyntax operand, AsmRegister register, BoundExpression value)
    {
        var type = value.Type;

        bool general = type is EnumTypeSymbol or PointerTypeSymbol or DelegateTypeSymbol ||
                       type is PrimitiveTypeSymbol { IsInteger: true } ||
                       type is PrimitiveTypeSymbol { Kind: PrimitiveKind.Bool };
        bool floating = type is PrimitiveTypeSymbol { IsFloat: true };

        if (!general && !floating)
        {
            diagnostics.Error("SL0719", operand.Value.Span,
                $"'{type.Name}' cannot travel in a register. An 'asm' operand is an integer, " +
                "a 'bool', a character, an enum, a pointer or a delegate, or a 'float' or " +
                "'double' in a vector register" +
                (type.CarriesReferences()
                    ? "; a counted reference would leave the block with nothing keeping " +
                      "count of it, so pass its address as a pointer instead"
                    : type is StructTypeSymbol
                        ? "; a struct is several values, so pass its address, or one field " +
                          "per register"
                        : ""));
            return false;
        }

        if (general != (register.Kind == AsmRegisterKind.General))
        {
            diagnostics.Error("SL0721", operand.Value.Span,
                register.Kind == AsmRegisterKind.Vector
                    ? $"'{register.Name}' is a vector register, which an operand uses for a " +
                      $"'float' or a 'double', and this is '{type.Name}'"
                    : $"'{register.Name}' is an integer register, and '{type.Name}' belongs " +
                      "in a vector register; its bits would have to be converted to be " +
                      "anything here, so convert them before the block");
            return false;
        }

        // A vector register named whole takes either width.
        if (register.Bits == 0) return true;

        int bits = type is PrimitiveTypeSymbol { Kind: PrimitiveKind.Bool } ? 8 : type.Size * 8;
        if (bits <= register.Bits) return true;

        diagnostics.Error("SL0720", operand.Value.Span,
            $"'{type.Name}' is {bits} bits and '{register.Name}' holds {register.Bits}, so " +
            "the value would not fit; name the wider register" +
            (type is PrimitiveTypeSymbol { Kind: PrimitiveKind.Double }
                ? ", or write the literal with 'f' if it was meant to be a 'float'"
                : ", or narrow the value with a cast first"));
        return false;
    }

    /// <summary>
    /// Whether an <c>out</c> or <c>inout</c> operand has a place to write to,
    /// with every check an assignment makes and the bookkeeping one does.
    ///
    /// A bit-field is refused where an assignment would take it: the address
    /// of every output is worked out before the block runs, so that each place
    /// is evaluated once, and a bit-field is the one place with no address.
    /// </summary>
    private bool AsmPlace(AsmOperandSyntax operand, BoundExpression place)
    {
        string written = operand.Direction == AsmDirection.Out ? "out" : "inout";
        if (!Writable(place, operand.Value.Span, $"{written} {operand.Register}")) return false;

        if (place is BoundFieldAccess { Field.IsBitField: true } bits)
        {
            diagnostics.Error("SL0722", operand.Value.Span,
                $"'{bits.Field.Name}' is a bit-field, and an 'asm' output is written through " +
                "its place's address, which a bit-field does not have. Take the value into a " +
                "local and assign the field from it");
            return false;
        }

        InvalidateVariantFact(place);
        if (WrittenParameter(place) is { } parameter) parameter.IsAssigned = true;
        NoteMemberWritten(place);
        return true;
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

        // `Current` is a property, so what is looked for first is its getter,
        // `get_Current`. A method of the bare name is still accepted: it is
        // what an enumerator written before this looked like, and the two
        // lower to the same single call.
        var enumerator = getEnumerator.ReturnType as NamedTypeSymbol;
        var current = enumerator is null ? null
            : enumerator.FindMethod("get_Current") ?? enumerator.FindMethod("Current");

        if (enumerator is null ||
            enumerator.FindMethod("MoveNext") is not { } moveNext ||
            !moveNext.ReturnType.IsBool() ||
            moveNext.Parameters.Count(p => !p.IsThis) != 0 ||
            current is null ||
            current.Parameters.Count(p => !p.IsThis) != 0 ||
            current.ReturnType.IsVoid())
        {
            diagnostics.Error("SL0357", syntax.Collection.Span,
                $"'{sequence.Type.Name}.GetEnumerator()' returns '{getEnumerator.ReturnType.Name}', " +
                "which is not an enumerator; that needs a 'bool MoveNext()' and a 'Current' " +
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
    /// <c>for parallel</c>. The iteration space is computed once and split into
    /// chunks, so the loop has to be a counted one: <c>i = start</c>,
    /// <c>i &lt; limit</c>, <c>i++</c> or <c>i += stride</c>. A general C-style <c>for</c>
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
                "a 'for parallel' must start by declaring an integer loop variable, " +
                "as in 'for parallel (int i = 0; ...)'");
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
                $"a 'for parallel' condition must be '{variable.Name} < limit' or " +
                $"'{variable.Name} <= limit'; the loop is split before it runs, so its " +
                "trip count has to be known up front");
            return new BoundBlock(syntax.Span, []);
        }

        var step = BindExpression(syntax.Step);
        BoundExpression stride;

        // `i++` and `++i` are a stride of one, and the house style's way of
        // writing it; which of the two values the expression has is never read.
        if (step is BoundIncrement { IsIncrement: true, Target: BoundLocalAccess bumped } &&
            bumped.Local == variable)
        {
            stride = new BoundLiteral(syntax.Step.Span, variable.Type, 1UL);
        }
        else if (step is BoundAssignment
                 {
                     Target: BoundLocalAccess stepped,
                     Value: BoundBinary { Operator: BoundBinaryOp.Add } increment,
                 } &&
                 stepped.Local == variable &&
                 Underlying(increment.Left) is BoundLocalAccess from && from.Local == variable)
        {
            stride = increment.Right;
        }
        else
        {
            diagnostics.Error("SL0371", syntax.Step.Span,
                $"a 'for parallel' step must be '{variable.Name}++', " +
                $"'{variable.Name} += stride' or '{variable.Name} = {variable.Name} + stride'");
            return new BoundBlock(syntax.Span, []);
        }

        // A non-constant stride could be zero or negative, and either makes the
        // trip count meaningless. A literal can simply be checked.
        if (Underlying(stride) is not BoundLiteral { Value: ulong raw } || raw == 0)
        {
            diagnostics.Error("SL0372", syntax.Step.Span,
                "the stride of a 'for parallel' must be a positive integer literal, " +
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
                $"'{name}' is declared outside this 'for parallel', so assigning to it " +
                "races between chunks; accumulate into an AtomicLong, or into a " +
                "distinct element per iteration");
        }

        return new BoundParallelFor(
            syntax.Span, variable, start, test.Right, stride,
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
                // Advice, not a refusal: the spawn still compiles.
                ReportNotSendable(receiver.Type, receiver.Span, "the receiver of this spawned call");
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
                ReportNotSendable(argument.Type, argument.Span, "this argument to a spawned call");
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
        BoundStringLiteral or BoundNullLiteral or BoundEmbed => true,
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
