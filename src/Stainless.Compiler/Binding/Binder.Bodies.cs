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
using static Stainless.Binding.BoundValues;

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

            foreach (var type in module.Types.Values.ToList())
            {
                foreach (var constructor in type.Constructors.ToList()) BindFunctionBody(constructor);
                if (type is ClassTypeSymbol { Destructor: { } destructor })
                    BindFunctionBody(destructor);
            }
        }

        _context.File = null;
    }

    private void BindFunctionBody(FunctionSymbol function)
    {
        if (function.LocalPath is not null || _rebindable) BindFunctionBodyCore(function);
        else BindFunctionBodyUntilSettled(function);
    }

    private void BindFunctionBodyCore(FunctionSymbol function)
    {
        if (function.IsAutoAccessor) { BindAutoAccessor(function); return; }
        if (function.Event is not null) { BindEventAccessor(function); return; }
        if (function.IsRecordClone) { BindRecordClone(function); return; }
        if (function.Body is null) return;
        if (!_boundFunctions.Add(function)) return;

        _patternVariableNames.Clear();
        int semantic = SemanticNodes.Made;

        // `this(...)` is only a statement at the very head of a constructor,
        // and `base(...)` only a statement of its body's own, after what gives
        // the fields their values. The one place either may appear is found
        // before anything is bound, and every other appearance is refused
        // where it stands.
        var chain = function.Kind == FunctionKind.Constructor
            ? FindConstructorChain(function.Body, function.ContainingType is ClassTypeSymbol { IsObjC: true })
            : null;

        // Bound against the imports of the file it was written in.
        using var entered = Enter(_context with
        {
            File = function.Scope ?? _context.File,
            Function = function,
            Locals = [],
            LoopDepth = 0,
            SwitchDepth = 0,
            VariantFacts = [],
            Jumps = new JumpState(),
            CheckedArithmetic = false,
            ConstructorChain = chain,
        });

        PushScope();
        var body = BindBlock(function.Body);
        PopScope();
        ReportUnavailableMembers(body);

        // What a getter reads, so that capturing the property can be tested
        // against what is written the way capturing a field already is.
        NoteGetterReads(function, body);

        _context.ConstructorChain = null;

        CheckJumps($"'{function.Name}'");

        if (function.IsObjCFieldInitializer)
            body = WithFieldInitializers(function, body);

        if (function.Kind == FunctionKind.Constructor)
        {
            CheckChainsToPrimary(function);
            body = WithFieldInitializers(function, body);
            body = WithBaseConstruction(function, body);
            body = WithPrimaryCaptures(function, body);
            if (chain is { Callee: BaseSyntax, IsClause: true })
                body = WithClauseBaseAtFirstReach(function, body);
            RecordFirstPhase(function, body);
        }

        SettleUnsetLocals(body);

        if (!function.ReturnType.IsVoid() && !function.ReturnType.IsError() && EndIsReachable(body))
            diagnostics.Report(Codes.NotAllPathsReturn, function.Span,
                $"not all paths through '{function.Name}' return a value of type '{function.ReturnType.Name}'",
                function.ReturnType);

        CheckOutParametersAssigned(function, body);

        // A constructor holds its field initializers too, which were bound
        // somewhere else.
        _functions.Add(new BoundFunction(function, body)
        {
            NeedsLowering = function.Kind == FunctionKind.Constructor || SemanticNodes.Made != semantic,
        });
    }

    /// <summary>
    /// The <c>this(...)</c> that heads a constructor, or the first
    /// <c>base(...)</c> among its body's own statements. An Objective-C
    /// class's <c>base(...)</c> is <c>[super init...]</c>, which answers the
    /// object the rest works on, so there it heads the body too.
    /// </summary>
    private static CallSyntax? FindConstructorChain(BlockSyntax body, bool objectiveC)
    {
        if (body.Statements.FirstOrDefault() is
            ExpressionStatementSyntax { Expression: CallSyntax { Callee: ThisSyntax or BaseSyntax } first } &&
            (objectiveC || first.Callee is ThisSyntax))
            return first;
        if (objectiveC)
            return null;

        foreach (var statement in body.Statements)
            if (statement is ExpressionStatementSyntax { Expression: CallSyntax { Callee: BaseSyntax } built })
                return built;
        return null;
    }

    /// <summary>
    /// Puts the base construction into a constructor whose source did not
    /// write one.
    ///
    /// A base class is constructed before the derived body reaches the
    /// object, always: the derived body may read what the base set up, and
    /// nothing else would make that safe. Left out, it is the base's
    /// parameterless constructor, run at the end of the first phase -- before
    /// the first statement that reaches the object or returns -- and there
    /// being none is an error rather than a class that skips it.
    /// </summary>
    private BoundBlock WithBaseConstruction(FunctionSymbol constructor, BoundBlock body)
    {
        // Taken first, whatever this constructor is: left set by a struct's
        // `: this(...)`, it would tell the next class to skip its base.
        bool explicitChain = _boundExplicitChain;
        _boundExplicitChain = false;

        if (constructor.ContainingType is not ClassTypeSymbol classType) return body;
        if (classType.BaseClass is null) return body;

        // Written out; BindBaseConstruction already put it first.
        if (explicitChain) return body;

        if (classType.ObjC == ObjCClassKind.Defined)
            return _delegated.ContainsKey(constructor)
                ? body
                : WithObjCBaseConstruction(constructor, classType, body);

        if (!TryImplicitBaseConstructor(classType, out var chained))
        {
            diagnostics.Report(Codes.BaseConstructorCallMismatch, constructor.Span,
                $"'{NearestConstructing(classType)!.Name}' has no constructor that takes no " +
                $"arguments, so '{classType.Name}' has to say which one to run: write " +
                "'base(...)' in its constructor, after the statements that give its fields " +
                "their values",
                classType);
            return body;
        }

        if (chained is null) return body;

        var self = new BoundThis(constructor.Span, classType, constructor.Parameters[0]);
        var call = new BoundCall(constructor.Span, chained,
            new BoundConversion(constructor.Span, chained.ContainingType!, self, ConversionKind.Upcast),
            []) { IsNonVirtual = true };
        var statement = new BoundExpressionStatement(constructor.Span, call);
        _implicitBaseCall = statement;

        int at = FindFirstReach(constructor, body.Statements);
        return new BoundBlock(body.Span,
            [.. body.Statements.Take(at), statement, .. body.Statements.Skip(at)]);
    }

    /// <summary>Set while binding a constructor whose source wrote its own chain.</summary>
    private bool _boundExplicitChain;

    /// <summary>
    /// Puts the field initializers at the head of a constructor, in the order
    /// they were declared.
    ///
    /// <para>
    /// <b>Before the base construction and the body.</b> A field initializer
    /// may not read anything -- it is bound with <c>this</c> out of reach --
    /// so it belongs to the first phase, and a base that calls a virtual
    /// method finds the field set. The constructor's own body still has the
    /// last word, which is what somebody writing <c>Width = width;</c> beside
    /// <c>int Width = 80;</c> means.
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
        if (constructor.ContainingType is not { } classType) return body;
        if (_delegated.ContainsKey(constructor)) return body;

        // A class defined for Objective-C has run them already, in
        // .cxx_construct.
        if (classType is ClassTypeSymbol { IsObjC: true } && !constructor.IsObjCFieldInitializer)
            return body;

        var initialized = classType.Fields
            .Where(f => f.InitializerSyntax is not null)
            .ToList();

        if (initialized.Count == 0) return body;

        var self = constructor.Parameters[0];
        var statements = new List<BoundStatement>();

        foreach (var field in initialized)
        {
            var written = field.InitializerSyntax!;

            // Bound against the file the *field* was written in, which is not
            // necessarily this constructor's: a type may be declared across
            // files, and a name means what it meant where it was written.
            //
            // With `this` out of reach, so an initializer cannot read a field
            // that has not been given its value yet -- the mistake C# also
            // refuses, and the reason it refuses it.
            _reportedFieldInitializerReach = false;
            BoundExpression value;
            using (Enter(_context with
                   {
                       File = field.InitializerScope ?? _context.File,
                       InitializingField = true,
                   }))
                value = BindConversion(BindExpression(written), field.Type, written.Span);

            var target = new BoundFieldAccess(written.Span, Receiver(written.Span, self), field);

            statements.Add(new BoundExpressionStatement(
                written.Span, new BoundAssignment(written.Span, target, value)));
        }

        return new BoundBlock(body.Span, [.. statements, .. body.Statements]);
    }

    /// <summary>
    /// <c>base(args)</c> at the head of a constructor: run the base's
    /// constructor over this same object, before this one's body.
    /// </summary>
    private BoundExpression BindBaseConstruction(CallSyntax syntax, List<BoundExpression> arguments)
    {
        if (!ReferenceEquals(syntax, _context.ConstructorChain))
        {
            diagnostics.Report(Codes.ConstructorCallMisplaced, syntax.Span,
                _context.Function?.Kind == FunctionKind.Constructor
                    ? "'base(...)' is a statement of the constructor's body itself, once: the base " +
                      "class is built exactly once, on every path, when this class's fields have " +
                      "their values"
                    : "'base(...)' constructs the base class, so it belongs in a constructor and " +
                      "nowhere else");
            return new BoundErrorExpression(syntax.Span);
        }

        if (_context.Function!.ContainingType is not ClassTypeSymbol classType)
        {
            diagnostics.Report(Codes.NoBaseToReach, syntax.Span,
                $"'{_context.Function.ContainingType!.Name}' is a struct, so there is nothing " +
                "above it to construct; only a class derives from another",
                _context.Function.ContainingType);
            return new BoundErrorExpression(syntax.Span);
        }

        if (classType.BaseClass is not { } baseClass)
        {
            diagnostics.Report(Codes.NoBaseToReach, syntax.Span,
                $"'{classType.Name}' derives from nothing, so it has no base to construct",
                classType);
            return new BoundErrorExpression(syntax.Span);
        }

        if (classType.ObjC == ObjCClassKind.Defined)
            return BindObjCBaseConstruction(syntax, classType, arguments);

        // Past any class that declares no constructor: there is nothing there
        // to run, and what is above it still has to be built.
        if (NearestConstructing(classType) is not { } ancestor)
        {
            diagnostics.Report(Codes.BaseConstructorCallMismatch, syntax.Span,
                $"nothing '{classType.Name}' derives from declares a constructor, so there is " +
                "none to call; remove the 'base(...)'",
                classType);
            return new BoundErrorExpression(syntax.Span);
        }

        var chosen = ResolveOverload(
            ancestor.Constructors, arguments, syntax.Span, $"base {ancestor.Name}");
        if (chosen is null) return new BoundErrorExpression(syntax.Span);

        var self = new BoundThis(syntax.Span, classType, _context.Function.Parameters[0]);
        var receiver = new BoundConversion(syntax.Span, ancestor, self, ConversionKind.Upcast);

        _boundExplicitChain = true;
        var call = BuildCall(syntax, chosen, receiver, arguments, nonVirtual: true);
        _writtenBaseCall = call;
        return call;
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
        if (!ReferenceEquals(syntax, _context.ConstructorChain))
        {
            diagnostics.Report(Codes.ConstructorCallMisplaced, syntax.Span,
                _context.Function?.Kind == FunctionKind.Constructor
                    ? "'this(...)' has to be the first statement of the constructor: it is what " +
                      "builds the object, and a body that had already run would be overwritten " +
                      "by it"
                    : "'this(...)' runs another constructor of this class, so it belongs at the " +
                      "head of a constructor and nowhere else");
            return new BoundErrorExpression(syntax.Span);
        }

        var owner = _context.Function!.ContainingType!;

        var chosen = ResolveOverload(
            owner.Constructors, arguments, syntax.Span, $"this {owner.Name}");
        if (chosen is null) return new BoundErrorExpression(syntax.Span);

        if (chosen == _context.Function)
        {
            diagnostics.Report(Codes.CircularConstructorDelegation, syntax.Span,
                $"this constructor of '{owner.Name}' delegates to itself",
                owner);
            return new BoundErrorExpression(syntax.Span);
        }

        _delegated[_context.Function] = chosen;

        // The receiver is what the constructor was handed: a class reference,
        // or the address of the struct being filled in.
        var receiver = _context.Function.Parameters[0];
        var self = new BoundThis(syntax.Span, receiver.Type, receiver);

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

                diagnostics.Report(Codes.CircularConstructorDelegation, start.Span,
                    $"the constructors of '{start.ContainingType!.Name}' delegate to each other " +
                    "in a ring, so none of them ever builds anything",
                    start.ContainingType);
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

        var span = accessor.Span;
        BoundExpression storage;
        if (accessor.Accessor?.StaticBacking is { } shared)
            storage = new BoundStaticAccess(span, shared);
        else if (accessor.Accessor?.BackingField is { } field)
            storage = new BoundFieldAccess(span, Receiver(span, accessor.Parameters[0]), field);
        else
            return;

        BoundStatement statement = accessor.ReturnType.IsVoid()
            ? new BoundExpressionStatement(span, new BoundAssignment(
                span, storage, new BoundParameterAccess(span, accessor.Parameters[^1])))
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

        if (ReferenceEquals(accessor, accessor.Event.WeakCall))
        {
            BindEventWeakCall(accessor);
            return;
        }

        if (ReferenceEquals(accessor, accessor.Event.AddWeak))
        {
            BindEventWeakAdd(accessor, field);
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

        // A weak subscription is the same subscriber behind a cell, so it
        // matches the handler that made it: the thunk in the function word,
        // and the handler's method and object in the cell.
        BoundExpression Matches(LocalSymbol index)
        {
            BoundExpression same = new BoundClosureEqual(span, closure, At(was, index), handler,
                negated: false);
            if (accessor.Event.WeakCall is not { } thunk) return same;

            return new BoundBinary(span, PrimitiveTypeSymbol.Bool, same, BoundBinaryOp.LogicalOr,
                new BoundBinary(span, PrimitiveTypeSymbol.Bool,
                    IsWeakEntry(span, closure, At(was, index), thunk),
                    BoundBinaryOp.LogicalAnd,
                    new BoundBinary(span, PrimitiveTypeSymbol.Bool,
                        new BoundCall(span, _builtins.WeakCellMatches, null, [
                            ReceiverAsPointer(span, closure, At(was, index)),
                            new BoundFieldAccess(span, handler, closure.Function!),
                            ReceiverAsPointer(span, closure, handler),
                        ]),
                        BoundBinaryOp.NotEqual,
                        new BoundLiteral(span, PrimitiveTypeSymbol.Int, 0UL))));
        }

        statements.Add(Walk(length, i => new BoundIf(
            span,
            new BoundBinary(
                span, PrimitiveTypeSymbol.Bool,
                Compare(new BoundLocalAccess(span, found), BoundBinaryOp.Equal,
                    new BoundLocalAccess(span, length)),
                BoundBinaryOp.LogicalAnd,
                Matches(i)),
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

    /// <summary>A closure's receiver word, as the runtime's <c>byte*</c>.</summary>
    private static BoundExpression ReceiverAsPointer(
        SourceSpan span, ClosureTypeSymbol closure, BoundExpression value) =>
        new BoundConversion(span, PrimitiveTypeSymbol.Byte.MakePointerType(),
            new BoundFieldAccess(span, value, closure.Receiver!), ConversionKind.PointerCast);

    /// <summary>Whether a stored subscriber is a weak one: its function is the thunk.</summary>
    private static BoundExpression IsWeakEntry(
        SourceSpan span, ClosureTypeSymbol closure, BoundExpression value, FunctionSymbol thunk) =>
        new BoundBinary(span, PrimitiveTypeSymbol.Bool,
            new BoundFieldAccess(span, value, closure.Function!),
            BoundBinaryOp.Equal,
            new BoundFunctionReference(span, PrimitiveTypeSymbol.Byte.MakePointerType(), thunk));

    /// <summary>
    /// Supplies the body of <c>weakcall_Name</c>, the function a weak
    /// subscription holds:
    ///
    /// <code>
    /// byte* method = null;
    /// byte* target = sl_weak_cell_load(cell, &amp;method);
    /// if (target == null) return;
    /// Closure call;                      // the event's own closure type
    /// call.$function = method;
    /// call.$receiver = (Object)target;   // retained by the store
    /// sl_release(target);
    /// call(arguments);
    /// </code>
    ///
    /// A subscriber that has died is skipped, which is always well defined:
    /// an event's handlers return nothing, so there is no value to invent.
    /// </summary>
    private void BindEventWeakCall(FunctionSymbol thunk)
    {
        var span = thunk.Span;
        var closure = thunk.Event!.Type;
        var bytes = PrimitiveTypeSymbol.Byte.MakePointerType();

        var method = new LocalSymbol("method", bytes, isConst: false);
        var target = new LocalSymbol("target", bytes, isConst: false);
        var call = new LocalSymbol("call", closure, isConst: false);

        var arguments = thunk.Parameters
            .Skip(1)
            .Select(BoundExpression (p) => new BoundParameterAccess(span, p))
            .ToList();

        var block = new BoundBlock(span, [
            new BoundLocalDeclaration(span, method, new BoundNullLiteral(span, bytes)),
            new BoundLocalDeclaration(span, target, new BoundCall(span, _builtins.WeakCellLoad, null, [
                new BoundParameterAccess(span, thunk.Parameters[0]),
                new BoundAddressOf(span, bytes.MakePointerType(), new BoundLocalAccess(span, method)),
            ])),
            new BoundIf(span,
                new BoundBinary(span, PrimitiveTypeSymbol.Bool,
                    new BoundLocalAccess(span, target), BoundBinaryOp.Equal,
                    new BoundNullLiteral(span, bytes)),
                new BoundReturn(span, null),
                null),
            new BoundLocalDeclaration(span, call, null),
            new BoundExpressionStatement(span, new BoundAssignment(span,
                new BoundFieldAccess(span, new BoundLocalAccess(span, call), closure.Function!),
                new BoundLocalAccess(span, method))),
            new BoundExpressionStatement(span, new BoundAssignment(span,
                new BoundFieldAccess(span, new BoundLocalAccess(span, call), closure.Receiver!),
                new BoundConversion(span, closure.Receiver!.Type,
                    new BoundLocalAccess(span, target), ConversionKind.PointerCast))),
            new BoundExpressionStatement(span, new BoundCall(span, _builtins.ReleaseObject, null,
                [new BoundLocalAccess(span, target)])),
            new BoundExpressionStatement(span, new BoundClosureCall(span, closure,
                new BoundLocalAccess(span, call), arguments)),
        ]);

        block.Locals.AddRange([method, target, call]);
        _functions.Add(new BoundFunction(thunk, block));
    }

    /// <summary>
    /// Supplies the body of <c>addweak_Name</c>: the handler's method and
    /// object go into a cell that holds the object weakly, and the event is
    /// given a closure of the thunk and the cell.
    ///
    /// Subscribers that have died are dropped first, so an event on a
    /// long-lived object that transient ones keep subscribing to holds only
    /// the living.
    /// </summary>
    private void BindEventWeakAdd(FunctionSymbol accessor, FieldSymbol field)
    {
        var span = accessor.Span;
        var closure = accessor.Event!.Type;
        var thunk = accessor.Event.WeakCall!;
        var array = ArrayOf(closure);
        var count = PrimitiveTypeSymbol.NUInt;
        var bytes = PrimitiveTypeSymbol.Byte.MakePointerType();

        var receiver = Receiver(span, accessor.Parameters[0]);
        var handler = new BoundParameterAccess(span, accessor.Parameters[1]);

        BoundExpression Storage() => new BoundFieldAccess(span, receiver, field);
        BoundExpression Local(LocalSymbol local) => new BoundLocalAccess(span, local);
        BoundExpression Number(ulong value) => new BoundLiteral(span, count, value);

        BoundExpression At(LocalSymbol source, LocalSymbol index) =>
            new BoundIndex(span, closure, Local(source), Local(index));

        BoundExpression IsLiving(LocalSymbol source, LocalSymbol index) =>
            new BoundBinary(span, PrimitiveTypeSymbol.Bool,
                new BoundBinary(span, PrimitiveTypeSymbol.Bool,
                    new BoundFieldAccess(span, At(source, index), closure.Function!),
                    BoundBinaryOp.NotEqual,
                    new BoundFunctionReference(span, bytes, thunk)),
                BoundBinaryOp.LogicalOr,
                new BoundBinary(span, PrimitiveTypeSymbol.Bool,
                    new BoundCall(span, _builtins.WeakCellIsDead, null,
                        [ReceiverAsPointer(span, closure, At(source, index))]),
                    BoundBinaryOp.Equal,
                    new BoundLiteral(span, PrimitiveTypeSymbol.Int, 0UL)));

        BoundStatement Walk(LocalSymbol limit, Func<LocalSymbol, BoundStatement> body)
        {
            var index = new LocalSymbol("i", count, isConst: false);
            var loop = new BoundFor(span,
                new BoundLocalDeclaration(span, index, Number(0)),
                new BoundBinary(span, PrimitiveTypeSymbol.Bool, Local(index), BoundBinaryOp.Less,
                    Local(limit)),
                new BoundIncrement(span, Local(index), isPrefix: false, isIncrement: true),
                body(index));
            var block = new BoundBlock(span, [loop]);
            block.Locals.Add(index);
            return block;
        }

        var was = new LocalSymbol("was", array, isConst: false);
        var length = new LocalSymbol("length", count, isConst: false);
        var living = new LocalSymbol("living", count, isConst: false);
        var kept = new LocalSymbol("kept", array, isConst: false);
        var at = new LocalSymbol("at", count, isConst: false);
        var cell = new LocalSymbol("cell", bytes, isConst: false);
        var wrapped = new LocalSymbol("wrapped", closure, isConst: false);

        BoundStatement BuildPrune()
        {
            var prune = new BoundBlock(span, [
                new BoundLocalDeclaration(span, kept, new BoundNewArray(span, array, Local(living))),
                new BoundLocalDeclaration(span, at, Number(0)),
                Walk(length, i => new BoundIf(span,
                    IsLiving(was, i),
                    new BoundBlock(span, [
                        new BoundExpressionStatement(span, new BoundAssignment(span,
                            new BoundIndex(span, closure, Local(kept), Local(at)), At(was, i))),
                        new BoundExpressionStatement(span,
                            new BoundIncrement(span, Local(at), isPrefix: false, isIncrement: true)),
                    ]),
                    null)),
                new BoundExpressionStatement(span, new BoundAssignment(span, Storage(), Local(kept))),
            ]);
            prune.Locals.AddRange([kept, at]);
            return prune;
        }

        var statements = new List<BoundStatement>
        {
            new BoundLocalDeclaration(span, was, Storage()),
            new BoundLocalDeclaration(span, length, new BoundArrayLength(span, count, Local(was))),

            // Count the living, then copy them across in order only if any died.
            new BoundLocalDeclaration(span, living, Number(0)),
            Walk(length, i => new BoundIf(span,
                IsLiving(was, i),
                new BoundExpressionStatement(span,
                    new BoundIncrement(span, Local(living), isPrefix: false, isIncrement: true)),
                null)),
            new BoundIf(span,
                new BoundBinary(span, PrimitiveTypeSymbol.Bool, Local(living), BoundBinaryOp.NotEqual,
                    Local(length)),
                BuildPrune(),
                null),

            new BoundLocalDeclaration(span, cell, new BoundCall(span, _builtins.WeakCellNew, null, [
                new BoundFieldAccess(span, handler, closure.Function!),
                ReceiverAsPointer(span, closure, handler),
            ])),
            new BoundLocalDeclaration(span, wrapped, null),
            new BoundExpressionStatement(span, new BoundAssignment(span,
                new BoundFieldAccess(span, Local(wrapped), closure.Function!),
                new BoundFunctionReference(span, bytes, thunk))),
            new BoundExpressionStatement(span, new BoundAssignment(span,
                new BoundFieldAccess(span, Local(wrapped), closure.Receiver!),
                new BoundConversion(span, closure.Receiver!.Type, Local(cell),
                    ConversionKind.PointerCast))),

            // The store retained the cell, so the reference the runtime made
            // it with is given back.
            new BoundExpressionStatement(span, new BoundCall(span, _builtins.ReleaseObject, null,
                [Local(cell)])),
            new BoundExpressionStatement(span, new BoundCall(span, accessor.Event.Add!, receiver,
                [Local(wrapped)])),
        };

        var block = new BoundBlock(span, statements);
        block.Locals.AddRange([was, length, living, cell, wrapped]);
        _functions.Add(new BoundFunction(accessor, block));
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
    /// The subjects each enclosing right operand of <c>&amp;&amp;</c> or
    /// <c>||</c> has assigned so far, innermost last.
    /// </summary>
    private readonly List<HashSet<object>> _writtenWitnesses = [];

    /// <summary>What a right operand assigned, by the operand, for <see cref="ConditionFacts"/>.</summary>
    private readonly Dictionary<BoundExpression, HashSet<object>> _writtenIn = [];

    /// <summary>
    /// Every name a pattern in this function has bound, so a read of one where
    /// it is not in scope is reported as that rather than as an unknown name.
    /// </summary>
    private readonly HashSet<string> _patternVariableNames = new(StringComparer.Ordinal);

    /// <summary>
    /// The statement being bound directly in a block's list, which is the one
    /// place an <c>if</c> may leave what its condition named in scope after it.
    /// </summary>
    private StatementSyntax? _listedStatement;

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

            _context.VariantFacts.Remove(subject);
            foreach (var witness in _writtenWitnesses) witness.Add(subject);
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

            // `x is P`, which says what it proved in either outcome.
            case BoundIsPattern test when NarrowableSubject(test.Subject) is { } tested:
            {
                return (Proved(test.CaseWhenTrue, test.NotNullWhenTrue),
                        Proved(test.CaseWhenFalse, test.NotNullWhenFalse));

                Dictionary<object, Fact> Proved(VariantCaseSymbol? held, bool present) =>
                    held is not null ? new() { [tested] = Fact.Holding(held) }
                    : present && test.Subject.Type.NonNullForm() is not null
                        ? new() { [tested] = Fact.NotNull }
                    : [];
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

            // The same of a nullable closure, whose null is compared as both
            // words.
            case BoundClosureEqual { ClosureType.IsNullable: true } test
                when (test.Right is BoundDefault ? test.Left : test.Left is BoundDefault ? test.Right
                         : null) is { } other &&
                     NarrowableSubject(other) is { } checkedClosure:
            {
                var proved = new Dictionary<object, Fact> { [checkedClosure] = Fact.NotNull };
                return test.Negated ? (proved, []) : ([], proved);
            }

            case BoundUnary { Operator: BoundUnaryOp.LogicalNot } negation:
            {
                var (whenTrue, whenFalse) = ConditionFacts(negation.Operand);
                return (whenFalse, whenTrue);
            }

            // `a && b` proves both only when it is true; either could be the
            // false one, so falsehood proves nothing. `a || b` is the mirror.
            // What the right side assigns, it has unproved: `n != null &&
            // (n = null) == null` says nothing about n by the time it is true.
            case BoundBinary { Operator: BoundBinaryOp.LogicalAnd } and:
            {
                var left = ConditionFacts(and.Left);
                var right = ConditionFacts(and.Right);
                return (Merge(Unwritten(left.WhenTrue, and.Right), right.WhenTrue), []);
            }

            case BoundBinary { Operator: BoundBinaryOp.LogicalOr } or:
            {
                var left = ConditionFacts(or.Left);
                var right = ConditionFacts(or.Right);
                return ([], Merge(Unwritten(left.WhenFalse, or.Right), right.WhenFalse));
            }

            default:
                return ([], []);
        }
    }

    /// <summary>The facts in <paramref name="facts"/> that <paramref name="after"/> did not assign away.</summary>
    private Dictionary<object, Fact> Unwritten(Dictionary<object, Fact> facts, BoundExpression after)
    {
        if (!_writtenIn.TryGetValue(after, out var written)) return facts;

        return facts.Where(fact => !written.Contains(fact.Key))
                    .ToDictionary(fact => fact.Key, fact => fact.Value);
    }

    private static Dictionary<object, Fact> Merge(
        Dictionary<object, Fact> first, Dictionary<object, Fact> second)
    {
        var merged = new Dictionary<object, Fact>(first);
        foreach (var (key, value) in second) merged[key] = value;
        return merged;
    }

    private Dictionary<object, Fact> SnapshotFacts() => new(_context.VariantFacts);

    private void ApplyFacts(Dictionary<object, Fact> facts)
    {
        foreach (var (key, value) in facts) _context.VariantFacts[key] = value;
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

        foreach (var subject in _context.VariantFacts.Keys.ToList())
        {
            string name = subject switch
            {
                LocalSymbol local => local.Name,
                ParameterSymbol parameter => parameter.Name,
                _ => "",
            };

            if (assigned.Contains(name)) _context.VariantFacts.Remove(subject);
        }
    }

    private static void CollectAssignedNames(Syntax.SyntaxNode? node, HashSet<string> names)
    {
        if (node is null) return;

        if (node is Syntax.AssignmentSyntax assignment)
            CollectAssignedRoots(assignment.Target, names);

        // `ref x` and `out x` hand the callee the storage to write.
        if (node is Syntax.RefArgumentSyntax { Value: var byReference } &&
            RootName(byReference) is { } passed)
            names.Add(passed);

        if (node is Syntax.OutArgumentSyntax { Value: { } outward } &&
            RootName(outward) is { } filled)
            names.Add(filled);

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
    /// <summary>The names an assignment writes, each element of a tuple being taken apart included.</summary>
    private static void CollectAssignedRoots(Syntax.ExpressionSyntax target, HashSet<string> names)
    {
        if (target is Syntax.TupleSyntax tuple)
        {
            foreach (var element in tuple.Elements) CollectAssignedRoots(element, names);
        }
        else if (RootName(target) is { } assigned)
        {
            names.Add(assigned);
        }
    }

    private static string? RootName(Syntax.ExpressionSyntax expression) => expression switch
    {
        Syntax.NameSyntax name when name.Name.Parts.Count == 1 => name.Name.Parts[0],
        Syntax.MemberAccessSyntax member => RootName(member.Target),
        Syntax.IndexSyntax index => RootName(index.Target),
        _ => null,
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
        if (_context.Jumps.Labels.Count > 0 || _context.Jumps.Jumps.Count > 0) return;

        foreach (var parameter in outward)
            if (!Assigns(body, new OutParameterPlace(parameter, function, diagnostics), false) &&
                EndIsReachable(body))
                diagnostics.Report(Codes.OutParameterNotAssigned, function.Span,
                    $"'{function.Name}' can return without writing to '{parameter.Name}', " +
                    "which is what 'out' promises the caller. Assign it on every path, or " +
                    "make it 'ref' and let the caller decide what it starts as");
    }

    /// <summary>An <c>out</c> parameter, which every path out of its function writes.</summary>
    private sealed class OutParameterPlace(
        ParameterSymbol parameter, FunctionSymbol owner, DiagnosticBag diagnostics) : AssignedPlace
    {
        public override bool IsPlace(BoundExpression expression) =>
            expression is BoundParameterAccess named && ReferenceEquals(named.Parameter, parameter);

        public override void ReportReturn(SourceSpan span) =>
            diagnostics.Report(Codes.OutParameterNotAssigned, span,
                $"'{owner.Name}' returns here without having written to " +
                $"'{parameter.Name}', which is what 'out' promises the caller");

        public override void ReportEarlyReturn(SourceSpan span) =>
            diagnostics.Report(Codes.OutParameterNotAssigned, span,
                $"'{owner.Name}' returns here if this fails, without having written to " +
                $"'{parameter.Name}', which is what 'out' promises the caller");
    }

    /// <summary>
    /// Whether the place is certainly written by the time this statement is
    /// through, reporting any <c>return</c> reached before it was.
    ///
    /// A path that jumps away is through: it reaches nothing after it. What a
    /// <c>break</c> or a <c>continue</c> held is kept for the statement it
    /// leaves, which is where that path goes on.
    /// </summary>
    private bool Assigns(BoundStatement statement, AssignedPlace target, bool assigned)
    {
        switch (statement)
        {
            case BoundBlock block:
                foreach (var inner in block.Statements)
                    assigned = Assigns(inner, target, assigned);
                return assigned;

            // Nothing follows a call that never returns, so nothing after it
            // can read what it left.
            case BoundExpressionStatement { Expression: BoundCall { Function.DoesNotReturn: true } } ended:
                Evaluates(ended.Expression, target, assigned);
                return true;

            case BoundExpressionStatement expression:
                return Evaluates(expression.Expression, target, assigned);

            // Declared again each time a loop comes round to it.
            case BoundLocalDeclaration declaration when target.IsDeclaredBy(declaration.Local):
                return false;

            case BoundLocalDeclaration declaration:
                return Evaluates(declaration.Initializer, target, assigned);

            case BoundDeconstruct taken:
                return Evaluates(taken.Expression, target, assigned);

            case BoundReturn returned:
                if (!Evaluates(returned.Value, target, assigned))
                    target.ReportReturn(returned.Span);

                // Nothing follows a return, so whatever it left is not read.
                return true;

            case BoundBreak:
                if (_assignmentBreaks.Count > 0)
                    _assignmentBreaks.Peek().Add(assigned);
                return true;

            case BoundContinue:
                if (_assignmentContinues.Count > 0)
                    _assignmentContinues.Peek().Add(assigned);
                return true;

            case BoundIf branch:
            {
                assigned = Evaluates(branch.Condition, target, assigned);
                bool then = Assigns(branch.Then, target, assigned);
                bool otherwise = branch.Else is null
                    ? assigned
                    : Assigns(branch.Else, target, assigned);
                return then && otherwise;
            }

            // A `do` body always runs, and so does every loop's first test.
            // Any other body may run no times at all, and whatever leaves one
            // early has at least what the loop started with.
            case BoundDoWhile loop:
            {
                var (end, breaks, continues) = AssignsInLoop(loop.Body, target, assigned);
                bool tested = Evaluates(loop.Condition, target, end && continues.All(c => c));
                return tested && breaks.All(b => b);
            }

            case BoundWhile loop:
                assigned = Evaluates(loop.Condition, target, assigned);
                AssignsInLoop(loop.Body, target, assigned);
                return assigned;

            case BoundForEach loop:
                assigned = Evaluates(loop.Collection, target, assigned);
                AssignsInLoop(loop.Body, target, assigned);
                return assigned;

            case BoundFor loop:
                if (loop.Initializer is not null)
                    assigned = Assigns(loop.Initializer, target, assigned);
                assigned = Evaluates(loop.Condition, target, assigned);
                AssignsInLoop(loop.Body, target, assigned);
                Evaluates(loop.Step, target, true);
                return assigned;

            case BoundSwitch chosen:
            {
                assigned = Evaluates(chosen.Subject, target, assigned);

                bool everyArm = chosen.IsExhaustive || chosen.Sections.Any(s => s.IsDefault);
                bool all = everyArm && chosen.Sections.Count > 0;

                var breaks = new List<bool>();
                _assignmentBreaks.Push(breaks);
                foreach (var section in chosen.Sections)
                    all &= Assigns(section.Body, target, assigned);
                _assignmentBreaks.Pop();

                return assigned || all && breaks.All(b => b);
            }

            case BoundParallel parallel:
                Assigns(parallel.Body, target, assigned);
                return assigned;

            // An output is stored once the block has run, which is as certain
            // as an assignment: nothing in the language can leave the block
            // any other way.
            case BoundAsm assembly:
                return assigned || assembly.IsIncomplete || assembly.Operands.Any(o =>
                    o.IsOutput
                        ? target.IsPlace(o.Value)
                        : Evaluates(o.Value, target, false));

            // Whatever else it holds may still read the place.
            default:
                if (target.ChecksReads)
                    new PlaceWriteTracker(target, assigned).Visit(statement);
                return assigned;
        }
    }

    /// <summary>What a loop's body ends with, and what each <c>break</c> and <c>continue</c> in it held.</summary>
    private (bool End, List<bool> Breaks, List<bool> Continues) AssignsInLoop(
        BoundStatement body, AssignedPlace target, bool assigned)
    {
        var breaks = new List<bool>();
        var continues = new List<bool>();
        _assignmentBreaks.Push(breaks);
        _assignmentContinues.Push(continues);

        bool end = Assigns(body, target, assigned);

        _assignmentContinues.Pop();
        _assignmentBreaks.Pop();
        return (end, breaks, continues);
    }

    private readonly Stack<List<bool>> _assignmentBreaks = new();
    private readonly Stack<List<bool>> _assignmentContinues = new();

    /// <summary>
    /// Whether the place is certainly written once the expression has been
    /// evaluated, reporting a <c>try</c> that can return before it was.
    /// </summary>
    private static bool Evaluates(BoundExpression? expression, AssignedPlace target, bool assigned)
    {
        var tracker = new PlaceWriteTracker(target, assigned);
        tracker.Visit(expression);

        foreach (var early in tracker.EarlyReturns)
            target.ReportEarlyReturn(early);

        return tracker.Written;
    }

    // ------------------------------------------------------------ scopes

    private void PushScope() =>
        _context.Locals.Add(new Dictionary<string, LocalSymbol>(StringComparer.Ordinal));
    private void PopScope() => _context.Locals.RemoveAt(_context.Locals.Count - 1);

    private LocalSymbol? LookupLocal(string name)
    {
        for (int i = _context.Locals.Count - 1; i >= 0; i--)
            if (_context.Locals[i].TryGetValue(name, out var local)) return local;
        return null;
    }

    private LocalSymbol DeclareLocal(string name, TypeSymbol type, bool isConst, SourceSpan span)
    {
        var local = new LocalSymbol(name, type, isConst);
        if (LookupLocal(name) is not null ||
            _context.LocalFunctionScopes.Count > 0 &&
            _context.LocalFunctionScopes[^1].ContainsKey(name))
            diagnostics.Report(Codes.DuplicateLocalName, span,
                $"'{name}' is already declared in this scope");
        else if (_context.Function?.Parameters.Any(p => p.Name == name) == true)
            diagnostics.Report(Codes.LocalShadowsParameter, span,
                $"'{name}' is already the name of a parameter");
        _context.Locals[^1][name] = local;
        return local;
    }

    // ------------------------------------------------------------ statements

    private BoundBlock BindBlock(BlockSyntax syntax)
    {
        PushScope();
        var statements = new List<BoundStatement>();
        var block = new BoundBlock(syntax.Span, statements);

        var functions = new Dictionary<string, LocalFunction>(StringComparer.Ordinal);
        _context.LocalFunctionScopes.Add(functions);
        DeclareLocalFunctions(syntax, functions);

        foreach (var bound in BindStatementList(syntax.Statements))
        {
            if (bound is BoundLocalDeclaration declaration) block.Locals.Add(declaration.Local);
            if (bound is BoundDeconstruct taken)
                block.Locals.AddRange(taken.Declarations.Select(d => d.Local));
            statements.Add(bound);
        }

        _context.LocalFunctionScopes.RemoveAt(_context.LocalFunctionScopes.Count - 1);
        PopScope();
        return block;
    }

    /// <summary>
    /// The statements of a block or a switch section, each one marked as
    /// standing in a list while it is bound.
    /// </summary>
    private List<BoundStatement> BindStatementList(IEnumerable<StatementSyntax> statements)
    {
        var bound = new List<BoundStatement>();

        foreach (var statement in statements)
        {
            var enclosing = _listedStatement;
            _listedStatement = statement;
            bound.Add(BindStatement(statement));
            _listedStatement = enclosing;
        }

        return bound;
    }

    private BoundStatement BindStatement(StatementSyntax syntax)
    {
        if (++_bindDepth > Source.Recursion.MaxDepth)
        {
            _bindDepth--;
            return new BoundExpressionStatement(
                syntax.Span, new BoundErrorExpression(syntax.Span));
        }

        try
        {
            int semantic = SemanticNodes.Made;
            var bound = BindStatementCore(syntax);
            bound.IsCore = SemanticNodes.Made == semantic;
            return bound;
        }
        finally
        {
            _bindDepth--;
        }
    }

    private BoundStatement BindStatementCore(StatementSyntax syntax) => syntax switch
    {
        BlockSyntax block => BindBlock(block),
        LocalDeclSyntax local => BindLocalDeclaration(local),
        LocalFunctionSyntax function => BindLocalFunctionDeclaration(function),
        ExpressionStatementSyntax expression => BindExpressionStatement(expression),
        IfSyntax ifStatement => BindIf(ifStatement),
        WhileSyntax whileStatement => BindWhile(whileStatement),
        DoWhileSyntax doWhile => BindDoWhile(doWhile),
        LabelSyntax label => BindLabel(label),
        GotoSyntax jump => BindGoto(jump),
        GotoCaseSyntax jump => BindGotoCase(jump),
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
                diagnostics.Report(Codes.VarWithoutInitializer, syntax.Span,
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
                else if (initializer is BoundConditional { Type: ArrayDraftType } chosen)
                    initializer = SettleArraysFromElements(chosen);

                type = initializer.Type;
                if (RefuseUntyped(initializer))
                {
                    type = ErrorTypeSymbol.Instance;
                }
                else if (type.IsVoid())
                {
                    diagnostics.Report(Codes.VarCannotInfer, syntax.Initializer.Span,
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
                    else if (ReportedLambdaBody(written))
                    {
                        type = ErrorTypeSymbol.Instance;
                    }
                    else
                    {
                        diagnostics.Report(Codes.VarCannotInfer, syntax.Initializer.Span,
                            $"'{syntax.Name}' cannot be a 'var': " +
                            (written.Parameters.Any(p => p.Type is null)
                                ? "this lambda does not say what its parameters are, so there " +
                                  "is nothing here to infer from. Write them -- " +
                                  "'(int x) => x * 2' -- or write the type out"
                                : written.Expression is null
                                ? "its 'return's do not agree on one type -- or one returns a " +
                                  "value and another does not -- so there is no result to give " +
                                  "it. Write the result in front of the parameters, as " +
                                  "'int (x) => { ... }', or write the type out"
                                : written.Expression is DefaultSyntax { Type: null } or
                                                        NewSyntax { Type: null }
                                ? "its body is a bare 'default' or a 'new(...)', which takes " +
                                  "its type from where it is going rather than giving the " +
                                  "lambda one. Write the type out"
                                : "its body has no type to give it. Write the result in " +
                                  "front of the parameters, or write the type out"));
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

                    diagnostics.Report(Codes.VarCannotInfer, syntax.Initializer.Span,
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
                    diagnostics.Report(Codes.VarCannotInfer, syntax.Initializer.Span,
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
            type = ResolveType(syntax.Type, _context.File!);
            if (syntax.Initializer is not null)
                initializer = BindConversion(BindExpression(syntax.Initializer), type, syntax.Initializer.Span);
        }

        var local = DeclareLocal(syntax.Name, type, syntax.IsConst, syntax.Span);
        if (initializer is null)
            NoteUnsetLocal(local);
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
        BoundAssignment or BoundMemberAssignment or BoundPropertyAssignment or BoundCompoundAssignment
            or BoundSwizzleAssignment
            or BoundCall or BoundIndirectCall or BoundClosureCall or BoundIncrement or BoundPropertyIncrement
            or BoundNew or BoundStructNew or BoundErrorExpression => true,

        // It returns on a failure, whatever its operand is.
        BoundTry => true,

        BoundLet held => Effective(held.Body),
        BoundConditional chosen => Effective(chosen.WhenTrue) || Effective(chosen.WhenFalse),
        BoundConditionalAccess asked => Effective(asked.Access) || Effective(asked.WhenNothing),
        BoundNullFallback fallback => Effective(fallback.Fallback),
        BoundSwitchExpression chosen => chosen.Arms.Any(arm => Effective(arm.Value)),
        BoundRangeSlice sliced => Effective(sliced.Access),
        _ => false,
    };

    private BoundStatement BindExpressionStatement(ExpressionStatementSyntax syntax)
    {
        if (syntax.Expression is AssignmentSyntax { Operator: TokenKind.Equals, Target: TupleSyntax }
            taken)
            return BindDeconstructionStatement(taken);

        var expression = BindExpression(syntax.Expression);
        if (RefuseUntyped(expression))
            return new BoundExpressionStatement(syntax.Span, new BoundErrorExpression(syntax.Span));

        bool hasEffect = Effective(expression);
        if (!hasEffect)
            diagnostics.Report(Codes.ExpressionHasNoEffect, syntax.Span,
                "this expression has no effect; its result is discarded");

        return Discarding(expression, syntax.Span);
    }

    /// <summary>
    /// A statement that evaluates an expression and drops its value.
    ///
    /// A value with no type of its own is never made. What it was built from is
    /// evaluated for its effects, and nothing else is.
    /// </summary>
    private BoundStatement Discarding(BoundExpression expression, SourceSpan span)
    {
        if (expression.Type is LambdaType or FunctionGroupType or ArrayDraftType
            or VariantDraftType or NullType)
        {
            var parts = new List<BoundExpression>();
            CollectDraftParts(expression, parts);
            return new BoundBlock(span,
                [.. parts.Select(part => new BoundExpressionStatement(part.Span, part))]);
        }

        return new BoundExpressionStatement(span, expression);
    }

    /// <summary>The parts of an unsettled value that do have a type, in the order they were written.</summary>
    private static void CollectDraftParts(BoundExpression expression, List<BoundExpression> into)
    {
        switch (expression)
        {
            case BoundLambda or BoundNullLiteral:
                break;

            case BoundFunctionGroup group:
                if (group.Receiver is not null)
                    CollectDraftParts(group.Receiver, into);
                break;

            case BoundArrayDraft array:
                foreach (var element in array.Elements)
                    CollectDraftParts(element, into);
                break;

            case BoundSpread spread:
                CollectDraftParts(spread.Source, into);
                break;

            case BoundVariantDraft built:
                foreach (var argument in built.Arguments)
                    CollectDraftParts(argument, into);
                break;

            case BoundTupleDraft tuple:
                foreach (var element in tuple.Elements)
                    CollectDraftParts(element, into);
                break;

            case BoundNewDraft created:
                foreach (var argument in created.Arguments)
                    CollectDraftParts(argument, into);
                break;

            default:
                if (HasOwnType(expression) || expression.Type.IsVoid())
                    into.Add(expression);
                break;
        }
    }

    private BoundStatement BindIf(IfSyntax syntax)
    {
        bool listed = ReferenceEquals(_listedStatement, syntax);
        _listedStatement = null;

        var condition = BindCondition(syntax.Condition);

        var (whenTrue, whenFalse) = ConditionFacts(condition);
        var (assignedTrue, assignedFalse) = AssignedNames(condition);

        var entry = SnapshotFacts();

        ApplyFacts(whenTrue);
        var then = BindWhereAssigned(condition, whenTrue: true, () => BindStatement(syntax.Then));

        _context.VariantFacts = new Dictionary<object, Fact>(entry);
        ApplyFacts(whenFalse);
        var otherwise = syntax.Else is null
            ? null
            : BindWhereAssigned(condition, whenTrue: false, () => BindStatement(syntax.Else));

        _context.VariantFacts = entry;

        // A branch that always leaves proves its opposite for everything after
        // the `if`. This is what makes the early return read the way it should:
        // `if (!read.Ok) { return Fail(read.Error); }` and the rest of the
        // function is holding a value -- and `if (x is not Node n) return;`
        // leaves `n` for the rest of the block.
        bool thenExits = !EndIsReachable(then);
        bool elseExits = otherwise is not null && !EndIsReachable(otherwise);
        bool outlived = false;

        if (thenExits && !elseExits)
        {
            ApplyFacts(whenFalse);
            if (listed)
                ExposeNames(assignedFalse);
            outlived = listed && assignedFalse.Count > 0;
        }
        else if (elseExits && !thenExits)
        {
            ApplyFacts(whenTrue);
            if (listed)
                ExposeNames(assignedTrue);
            outlived = listed && assignedTrue.Count > 0;
        }

        BoundStatement result = new BoundIf(syntax.Span, condition, then, otherwise);

        // What the condition named is released where the `if` ends, unless it
        // stays in scope after it.
        return outlived || assignedTrue.Count + assignedFalse.Count == 0
            ? result
            : new BoundBlock(syntax.Span, [result]);
    }

    /// <summary>
    /// <c>while (c) { ... }</c>, and <c>while (x is Some v)</c> with it.
    ///
    /// What the condition names is in scope in the body, for the reason it is
    /// in an <c>if</c>'s branch: the body is the place the test proved. The
    /// condition assigns the names on every pass, so <c>continue</c> takes
    /// them again, which is what continuing a <c>while</c> means.
    /// </summary>
    private BoundStatement BindWhile(WhileSyntax syntax)
    {
        var condition = BindCondition(syntax.Condition);

        // A loop body runs again, so anything it assigns to is unknown inside it
        // however the loop was entered.
        if (_context.VariantFacts.Count > 0) InvalidateAssignedIn(syntax.Body);

        var entry = SnapshotFacts();
        ApplyFacts(ConditionFacts(condition).WhenTrue);

        _context.LoopDepth++;
        var body = BindWhereAssigned(condition, whenTrue: true, () => BindStatement(syntax.Body));
        _context.LoopDepth--;

        // Nothing the condition proved survives the loop: it is also left by
        // failing that same condition.
        _context.VariantFacts = entry;

        // And what it named is released where the loop ends.
        BoundStatement loop = new BoundWhile(syntax.Span, condition, body);
        var (assignedTrue, assignedFalse) = AssignedNames(condition);

        return assignedTrue.Count + assignedFalse.Count == 0
            ? loop
            : new BoundBlock(syntax.Span, [loop]);
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
        if (_context.VariantFacts.Count > 0) InvalidateAssignedIn(syntax.Body);

        var entry = SnapshotFacts();

        _context.LoopDepth++;
        var body = BindStatement(syntax.Body);
        _context.LoopDepth--;

        var condition = BindCondition(syntax.Condition);

        _context.VariantFacts = entry;
        return new BoundDoWhile(syntax.Span, body, condition);
    }

    /// <summary>
    /// <c>checked { ... }</c> and <c>unchecked { ... }</c>: the arithmetic
    /// written inside is bound with overflow noticed, or with it ignored.
    /// </summary>
    private BoundStatement BindCheckedBlock(CheckedBlockSyntax syntax)
    {
        bool previous = _context.CheckedArithmetic;
        _context.CheckedArithmetic = syntax.IsChecked;
        var body = BindBlock(syntax.Body);
        _context.CheckedArithmetic = previous;
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
                diagnostics.Report(Codes.AsmRegisterUnknown, operand.RegisterSpan,
                    $"'{operand.Register}' is not a register an operand can name on " +
                    $"{AsmRegisters.ArchitectureName(target)}, which is what this build is " +
                    $"for; the registers are {AsmRegisters.Examples(target)}");
                continue;
            }

            if (register.Refusal is { } refusal)
            {
                diagnostics.Report(Codes.AsmRegisterNotAllowed, operand.RegisterSpan,
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

                diagnostics.Report(Codes.AsmRegisterNamedTwice, operand.RegisterSpan,
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
            diagnostics.Report(Codes.AsmOperandTypeNotAllowed, operand.Value.Span,
                $"'{type.Name}' cannot travel in a register. An 'asm' operand is an integer, " +
                "a 'bool', a character, an enum, a pointer or a delegate, or a 'float' or " +
                "'double' in a vector register" +
                (type.CarriesReferences()
                    ? "; a counted reference would leave the block with nothing keeping " +
                      "count of it, so pass its address as a pointer instead"
                    : type is StructTypeSymbol
                        ? "; a struct is several values, so pass its address, or one field " +
                          "per register"
                        : ""),
                type);
            return false;
        }

        if (general != (register.Kind == AsmRegisterKind.General))
        {
            diagnostics.Report(Codes.AsmRegisterKindMismatch, operand.Value.Span,
                register.Kind == AsmRegisterKind.Vector
                    ? $"'{register.Name}' is a vector register, which an operand uses for a " +
                      $"'float' or a 'double', and this is '{type.Name}'"
                    : $"'{register.Name}' is an integer register, and '{type.Name}' belongs " +
                      "in a vector register; its bits would have to be converted to be " +
                      "anything here, so convert them before the block",
                type);
            return false;
        }

        // A vector register named whole takes either width.
        if (register.Bits == 0) return true;

        int bits = type is PrimitiveTypeSymbol { Kind: PrimitiveKind.Bool } ? 8 : type.Size * 8;
        if (bits <= register.Bits) return true;

        diagnostics.Report(Codes.AsmOperandTooWide, operand.Value.Span,
            $"'{type.Name}' is {bits} bits and '{register.Name}' holds {register.Bits}, so " +
            "the value would not fit; name the wider register" +
            (type is PrimitiveTypeSymbol { Kind: PrimitiveKind.Double }
                ? ", or write the literal with 'f' if it was meant to be a 'float'"
                : ", or narrow the value with a cast first"),
            type);
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
            diagnostics.Report(Codes.AsmOutputToBitField, operand.Value.Span,
                $"'{bits.Field.Name}' is a bit-field, and an 'asm' output is written through " +
                "its place's address, which a bit-field does not have. Take the value into a " +
                "local and assign the field from it");
            return false;
        }

        InvalidateVariantFact(place);
        if (WrittenParameter(place) is { } parameter) MarkAssigned(parameter);
        NoteMemberWritten(place);
        return true;
    }

    private BoundStatement BindFor(ForSyntax syntax)
    {
        PushScope();

        BoundStatement? initializer = syntax.Initializer is null ? null : BindStatement(syntax.Initializer);
        var condition = syntax.Condition is null ? null : BindCondition(syntax.Condition);
        var step = syntax.Step is null ? null : BindStep(syntax.Step);

        // The same rule a `while` obeys: what the body assigns to is unknown
        // inside it, and the condition proves nothing after it.
        if (_context.VariantFacts.Count > 0) InvalidateAssignedIn(syntax.Body);
        var entry = SnapshotFacts();
        if (condition is not null) ApplyFacts(ConditionFacts(condition).WhenTrue);

        _context.LoopDepth++;
        var body = condition is null
            ? BindStatement(syntax.Body)
            : BindWhereAssigned(condition, whenTrue: true, () => BindStatement(syntax.Body));
        _context.LoopDepth--;
        _context.VariantFacts = entry;

        var result = new BoundFor(syntax.Span, initializer, condition, step, body);
        if (initializer is BoundLocalDeclaration declaration) result.Locals.Add(declaration.Local);
        if (initializer is BoundDeconstruct taken)
            result.Locals.AddRange(taken.Declarations.Select(d => d.Local));

        PopScope();
        return result;
    }

    /// <summary>
    /// A <c>for</c>'s step, which is evaluated and dropped as an expression
    /// statement is. A value with no type of its own is never made, and what it
    /// was built from is evaluated for its effects; null when that is nothing.
    /// </summary>
    private BoundExpression? BindStep(ExpressionSyntax syntax)
    {
        var step = BindExpression(syntax);
        if (RefuseUntyped(step))
            return new BoundErrorExpression(syntax.Span);

        if (step.Type is not (LambdaType or FunctionGroupType or ArrayDraftType or VariantDraftType or NullType))
            return step;

        diagnostics.Report(Codes.ExpressionHasNoEffect, syntax.Span,
            "this expression has no effect; its result is discarded");

        var parts = new List<BoundExpression>();
        CollectDraftParts(step, parts);
        return parts.Count == 0 ? null : new BoundSequence(syntax.Span, parts[..^1], parts[^1]);
    }

    /// <summary>
    /// <c>foreach</c>: the collection, the element each pass names, and the
    /// body. How it iterates is lowering's, and depends on what the
    /// collection is.
    ///
    /// An array or a slice iterates by index, which costs no allocation and
    /// no dispatch. Anything else is asked for a <c>GetEnumerator()</c>, found
    /// by name rather than by interface, so a type can be iterable without
    /// Standard.Collections appearing anywhere in the program.
    /// </summary>
    private BoundStatement BindForEach(ForEachSyntax syntax)
    {
        PushScope();

        // `foreach (var n in [1, 2, 3])`: nothing says what the literal is, so
        // its elements do, as they do for `var`.
        var collection = BindExpression(syntax.Collection);
        if (collection is BoundArrayDraft loose)
            collection = SettleArrayFromElements(loose);
        else if (collection is BoundConditional { Type: ArrayDraftType } chosen)
            collection = SettleArraysFromElements(chosen);
        if (collection.Type.IsError())
        {
            PopScope();
            return new BoundBlock(syntax.Span, []);
        }

        TypeSymbol element;
        (FunctionSymbol GetEnumerator, FunctionSymbol MoveNext, FunctionSymbol Current)? enumerator = null;

        if (collection.Type is ArrayTypeSymbol array)
            element = array.Element;
        else if (collection.Type is SliceTypeSymbol slice)
            element = slice.Element;
        else if (FindEnumerator(syntax, collection.Type) is { } found)
            (enumerator, element) = (found, found.Current.ReturnType);
        else
        {
            PopScope();
            return new BoundBlock(syntax.Span, []);
        }

        var input = new BoundPlaceholder(syntax.Span, element);
        var (variable, value, deconstruction, body) = BindForEachBody(syntax, input);
        PopScope();

        return new BoundForEach(syntax.Span, collection, variable, input, value, deconstruction, body)
        {
            GetEnumerator = enumerator?.GetEnumerator,
            MoveNext = enumerator?.MoveNext,
            Current = enumerator?.Current,
        };
    }

    /// <summary>
    /// What makes a collection that is not an array iterable: a
    /// <c>GetEnumerator()</c>, whose result has a <c>bool MoveNext()</c> and a
    /// <c>Current</c>.
    /// </summary>
    private (FunctionSymbol GetEnumerator, FunctionSymbol MoveNext, FunctionSymbol Current)? FindEnumerator(
        ForEachSyntax syntax, TypeSymbol collection)
    {
        if (collection is not NamedTypeSymbol source ||
            source.FindMethod("GetEnumerator") is not { } getEnumerator ||
            getEnumerator.Parameters.Count(p => !p.IsThis) != 0)
        {
            diagnostics.Report(Codes.ForEachNotEnumerable, syntax.Collection.Span,
                $"'{collection.Name}' cannot be iterated; it is not an array and has no " +
                "'GetEnumerator()' method taking no arguments",
                collection);
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
            diagnostics.Report(Codes.GetEnumeratorReturnsNonEnumerator, syntax.Collection.Span,
                $"'{collection.Name}.GetEnumerator()' returns '{getEnumerator.ReturnType.Name}', " +
                "which is not an enumerator; that needs a 'bool MoveNext()' and a 'Current' " +
                "returning the element",
                collection, getEnumerator.ReturnType);
            return null;
        }

        return (getEnumerator, moveNext, current);
    }

    /// <summary>
    /// The loop variable, what it is given from the element, and the body
    /// around it. The variable lives inside the loop, so a managed element is
    /// released at the end of each pass rather than at the end of the loop.
    /// </summary>
    private (LocalSymbol Variable, BoundExpression Value, BoundStatement? Deconstruction, BoundStatement Body)
        BindForEachBody(ForEachSyntax syntax, BoundPlaceholder element)
    {
        PushScope();
        if (_context.VariantFacts.Count > 0) InvalidateAssignedIn(syntax.Body);

        var type = syntax.Type is null
            ? element.Type
            : ResolveType(syntax.Type, _context.File!);

        var value = syntax.Type is null
            ? element
            : BindConversion(element, type, syntax.Collection.Span);

        // A loop that takes its element apart holds it under a name of its own.
        var variable = DeclareLocal(
            syntax.Deconstruction is null ? syntax.Name : SyntheticName("element"),
            type, isConst: false, syntax.Span);

        var deconstruction = syntax.Deconstruction is { } taken
            ? BindForEachDeconstruction(taken, variable, taken.Span)
            : null;

        _context.LoopDepth++;
        var body = BindStatement(syntax.Body);
        _context.LoopDepth--;

        PopScope();
        return (variable, value, deconstruction, body);
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
        int enclosingLoops = _context.LoopDepth;
        int enclosingSwitches = _context.SwitchDepth;
        int enclosingBase = _context.Jumps.ParallelBase;
        _context.LoopDepth = 0;
        _context.SwitchDepth = 0;
        _context.ParallelDepth++;
        _context.Jumps.ParallelBase = _context.Locals.Count;

        var body = BindBlock(syntax.Body);

        _context.Jumps.ParallelBase = enclosingBase;
        _context.ParallelDepth--;
        _context.LoopDepth = enclosingLoops;
        _context.SwitchDepth = enclosingSwitches;

        return new BoundParallel(syntax.Span, body);
    }

    private BoundStatement BindSpawn(SpawnSyntax syntax)
    {
        if (_context.ParallelDepth == 0)
        {
            diagnostics.Report(Codes.SpawnOutsideParallel, syntax.Span,
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
            diagnostics.Report(Codes.SpawnTargetNotCall, syntax.Call.Span,
                "'spawn' takes a function or method call; there is nothing else " +
                "for a worker thread to run");
            return new BoundBlock(syntax.Span, []);
        }

        if (!CheckSpawnArguments(spawned)) return new BoundBlock(syntax.Span, []);

        // The caller's statement is over long before the worker is, so the
        // elements of a `params` slice go on the heap here.
        foreach (var argument in spawned.Arguments)
            if (argument is BoundParamsArray { InFrame: true } gathered)
                gathered.InFrame = false;

        if (syntax.Target is null)
            return new BoundSpawn(syntax.Span, null, spawned);

        var target = BindExpression(syntax.Target);
        if (target.Type.IsError()) return new BoundBlock(syntax.Span, []);

        if (RefusedThroughReadOnlySlice(target, syntax.Target.Span))
            return new BoundBlock(syntax.Span, []);

        NoteWriteTo(target);

        if (!target.IsLValue)
        {
            diagnostics.Report(Codes.SpawnResultNotStorable, syntax.Target.Span,
                "a spawned result must be stored in a variable, field or element; " +
                "the worker writes it there while the parent waits");
            return new BoundBlock(syntax.Span, []);
        }

        if (spawned.Type.IsVoid())
        {
            diagnostics.Report(Codes.SpawnResultIsVoid, syntax.Span,
                $"'{spawned.Function.Name}' returns nothing, so there is no result to store");
            return new BoundBlock(syntax.Span, []);
        }

        // The conversion has to be settled here: the worker stores into the
        // parent's slot, so the value must already have that slot's type.
        var converted = BindConversion(spawned, target.Type, syntax.Span);
        if (converted is not BoundCall matched)
        {
            diagnostics.Report(Codes.SpawnResultNeedsConversion, syntax.Span,
                $"'{spawned.Function.Name}' returns '{spawned.Type.Name}', which needs a " +
                $"conversion to '{target.Type.Name}'; assign it after the 'parallel' block instead",
                spawned.Type, target.Type);
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
        int enclosingBase = _context.Jumps.ParallelBase;
        _context.Jumps.ParallelBase = _context.Locals.Count;
        PushScope();

        int enclosingLoops = _context.LoopDepth;
        int enclosingSwitches = _context.SwitchDepth;
        _context.LoopDepth = 0;
        _context.SwitchDepth = 0;
        _context.ParallelDepth++;

        var result = BindParallelForCore(syntax);

        _context.ParallelDepth--;
        _context.LoopDepth = enclosingLoops;
        _context.SwitchDepth = enclosingSwitches;

        PopScope();
        _context.Jumps.ParallelBase = enclosingBase;
        return result;
    }

    private BoundStatement BindParallelForCore(ParallelForSyntax syntax)
    {
        var initializer = BindStatement(syntax.Initializer);

        if (initializer is not BoundLocalDeclaration { Initializer: { } start } declaration ||
            declaration.Local.Type is not PrimitiveTypeSymbol { IsInteger: true })
        {
            diagnostics.Report(Codes.ParallelForVariableMissing, syntax.Initializer.Span,
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
            diagnostics.Report(Codes.ParallelForConditionInvalid, syntax.Condition.Span,
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
        else if (step is BoundCompoundAssignment
                 {
                     Property: null,
                     IsFallback: false,
                     Target: BoundLocalAccess compounded,
                     Combined: BoundBinary { Operator: BoundBinaryOp.Add } added,
                 } compound &&
                 compounded.Local == variable &&
                 ReferenceEquals(Underlying(added.Left), compound.Current))
        {
            stride = added.Right;
        }
        else
        {
            diagnostics.Report(Codes.ParallelForStepInvalid, syntax.Step.Span,
                $"a 'for parallel' step must be '{variable.Name}++', " +
                $"'{variable.Name} += stride' or '{variable.Name} = {variable.Name} + stride'");
            return new BoundBlock(syntax.Span, []);
        }

        // A non-constant stride could be zero or negative, and either makes the
        // trip count meaningless. A literal can simply be checked.
        if (Underlying(stride) is not BoundLiteral { Value: ulong raw } || raw == 0)
        {
            diagnostics.Report(Codes.ParallelForStrideNotLiteral, syntax.Step.Span,
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
            diagnostics.Report(Codes.ParallelForOuterAssignment, span,
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
            diagnostics.Report(Codes.SpawnedCallTakesReference, call.Span,
                $"'{call.Function.Name}' takes '{Spelled(parameter)} {parameter.Name}', and a " +
                "spawned call would hand a job the address of the caller's storage; two jobs " +
                "given the same one would race on it. Pass a copy, or guard it with 'Mutex<T>'");
            ok = false;
        }

        if (call.Receiver is { } receiver)
        {
            if (receiver.Type.NeedsArc() && !IsHeldElsewhere(receiver))
            {
                diagnostics.Report(Codes.SpawnBorrowsTemporary, receiver.Span,
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
                diagnostics.Report(Codes.SpawnBorrowsTemporary, argument.Span,
                    $"a spawned call borrows its arguments, so this '{argument.Type.Name}' must be " +
                    "held in a variable or field first; a temporary is destroyed at the end of " +
                    "this statement, before the job runs",
                    argument.Type);
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
        BoundStringLiteral or BoundUtf8Literal or BoundNullLiteral => true,
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

    /// <summary>
    /// The storage a write reaches, for the questions that are about the
    /// storage rather than the value: a <c>static readonly</c>, an <c>in</c>
    /// parameter.
    ///
    /// <b>A step that crosses a reference ends the walk.</b> A struct field and
    /// an inline array element live inside the base, so writing one writes it.
    /// An array element and a class field do not: they are another object's
    /// storage, reached through a reference the base merely holds. That is what
    /// makes <c>readonly</c> a promise about the slot rather than about
    /// everything under it, which is C#'s rule and the one
    /// <c>BindPropertyAssignment</c> already applies to a setter.
    /// </summary>
    private static BoundExpression BaseOf(BoundExpression expression) => expression switch
    {
        BoundFieldAccess { Receiver: { } receiver }
            when receiver.Type is StructTypeSymbol => BaseOf(receiver),

        BoundIndex index when index.Target.Type.HoldsElementsInline() => BaseOf(index.Target),

        BoundConversion conversion => BaseOf(conversion.Operand),

        // A struct receiver is passed by address, so the address of a thing is
        // still that thing as far as ownership goes.
        BoundAddressOf address => BaseOf(address.Operand),
        _ => expression,
    };

    /// <summary>
    /// The read-only slice a write to this place would land in, or null when
    /// it lands anywhere else.
    /// </summary>
    private static SliceTypeSymbol? ReadOnlySliceUnder(BoundExpression place) =>
        BaseOf(place) is BoundIndex { Target.Type: SliceTypeSymbol { IsReadOnly: true } slice }
            ? slice
            : null;

    /// <summary>Reports a write through a read-only slice, and answers whether there was one.</summary>
    private bool RefusedThroughReadOnlySlice(BoundExpression place, SourceSpan span)
    {
        if (ReadOnlySliceUnder(place) is not { } slice) return false;

        diagnostics.Report(Codes.ReadOnlySpanElementWritten, span,
            $"this writes an element of a '{slice.Name}', which is a view that only reads; " +
            $"take a 'Span<{slice.Element.Name}>' where the elements are meant to change",
            slice);
        return true;
    }

    /// <summary>Strips conversions, so a widened loop variable still matches.</summary>
    private static BoundExpression Underlying(BoundExpression expression) =>
        expression is BoundConversion conversion ? Underlying(conversion.Operand) : expression;
}
