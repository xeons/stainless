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
/// Calls, and the overload resolution behind them.
///
/// Argument conversion, variadic promotion, and the diagnostics that
/// say why no candidate matched -- which is most of the file, because a
/// failed call is where a type error usually surfaces.
/// </summary>
public sealed partial class Binder
{
    private BoundExpression BindCall(CallSyntax syntax)
    {
        // `a?.M(x)`: the receiver is asked about before the method is reached,
        // and the whole call is nothing when it was nothing.
        if (syntax.Callee is MemberAccessSyntax { Conditional: true } asked)
            return BindConditionalAccess(asked, null, syntax);

        var arguments = syntax.Arguments.Select(BindArgument).ToList();
        RefuseNamesWithoutParameters(syntax);

        // `base(...)` is the base constructor and `this(...)` another of this
        // class's own; neither is a member of anything.
        if (syntax.Callee is BaseSyntax) return BindBaseConstruction(syntax, arguments);
        if (syntax.Callee is ThisSyntax) return BindThisConstruction(syntax, arguments);

        if (TryBindEventClear(syntax, arguments) is { } cleared) return cleared;

        // A bare `Ok(x)` builds a variant rather than calling anything. It has
        // to be decided here, before the name is looked up, because a draft has
        // no type yet and overload resolution has nothing to resolve against.
        // What keeps that unambiguous is SL0414: a module-level function may not
        // be named after a case of a variant this file can see. A method still
        // may, and is reached through its receiver.
        if (syntax.Callee is NameSyntax { Name.Parts: [var bare], TypeArguments: null } &&
            LookupLocal(bare) is null && CouldBeVariantCase(bare))
            return BindVariantDraft(syntax, bare, arguments);


        if (syntax.Callee is MemberAccessSyntax { TypeArguments: null, ThroughPointer: false } vectorCall &&
            VectorPrefix(vectorCall.Target) is { } vectorType)
            return BindVectorFunction(syntax, vectorCall.Member, vectorType, arguments);

        if (TryBindVaList(syntax, arguments) is { } varargs) return varargs;

        // `Shape.Circle(2.0)` names the variant as well as the case, so it
        // needs nothing from the surrounding expression to settle it.
        if (syntax.Callee is MemberAccessSyntax { TypeArguments: null } named &&
            ResolveVariantPrefix(named.Target) is { } prefix)
        {
            if (prefix.FindCase(named.Member) is not { } prefixCase)
            {
                diagnostics.Error("SL0435", named.Span,
                    $"variant '{prefix.Name}' has no case named '{named.Member}'; it has " +
                    Listed(prefix.Cases.Select(c => c.Name)),
                    prefix);
                return new BoundErrorExpression(syntax.Span);
            }

            return BindVariantConstruction(prefix, prefixCase, arguments, syntax.Span);
        }

        // `FileStream.Open(path)` names a type, not a value: a static method
        // belongs to the type and has no receiver to be reached through.
        //
        // It is tried before the module path, and only when the type really has
        // a static method of that name, so a module and a type of the same name
        // each keep what was already theirs.
        // A generic one is counted here too. It is a template until its
        // arguments say what it is, so `FindMethods` does not see it -- and
        // without this the whole static path was skipped, the type name was
        // bound as though it were a value, and the error was that the *type*
        // did not exist. `Helper.Take(() => 5)` said "'Helper' is not defined",
        // which is true of nothing and sends the reader to the wrong file.
        if (syntax.Callee is MemberAccessSyntax { ThroughPointer: false } onType &&
            ResolveTypePrefix(onType.Target, onType.Member) is { } staticOwner &&
            (staticOwner.FindMethods(onType.Member).ToList() is { Count: > 0 } named2
                 && (named2.Any(m => m.IsStatic) || ResolveModulePrefix(onType.Target) is null)
             || staticOwner.GenericMethods.Any(m => m.Name == onType.Member)
             || (NamesTypeParameter(onType.Target) &&
                 StaticDefaults(staticOwner, onType.Member).Count > 0)))
            return BindStaticCall(syntax, onType, staticOwner, arguments);

        // `K.Handler(2)` and `Module.s_handler(2)`: a static holding a closure
        // or a delegate, reached through the type or the module that owns it.
        if (syntax.Callee is MemberAccessSyntax { ThroughPointer: false } held &&
            (ResolveTypePrefix(held.Target, held.Member) is not null || ResolveModulePrefix(held.Target) is { } holder &&
                !holder.FindFunctions(held.Member).Any()) &&
            BindCallableValue(held) is { } heldValue)
            return BuildIndirectCall(syntax, heldValue, arguments);

        // `receiver.Method(args)`, unless the receiver is really a module path.
        if (syntax.Callee is MemberAccessSyntax member)
        {
            if (ResolveModulePrefix(member.Target) is not { } module)
                return BindMethodCall(syntax, member, arguments);

            bool sameModule = module == _currentModule;
            var visible = module.FindFunctions(member.Member)
                .Where(f => sameModule || f.IsPublic)
                .ToList();

            bool written = member.TypeArguments is not null;

            if (!written && visible.Any(f => AcceptsArguments(f, arguments, syntax.Arguments)))
                return BindFunctionCall(syntax, visible, member.Member, arguments);

            var qualified = new QualifiedName(member.Span,
                [.. FlattenName(member.Target)!, member.Member]);
            if (TryBindGenericCall(syntax, qualified, arguments) is { } generic) return generic;

            if (written)
                return RefuseTypeArgumentsOnPlainFunction(member, member.Member, visible.Count > 0);

            return BindFunctionCall(syntax, visible, member.Member, arguments);
        }

        if (syntax.Callee is NameSyntax { TypeArguments: not null } explicitly)
            return BindCallWithTypeArguments(syntax, explicitly, arguments);

        // A local whose declaration was already refused: what it would have
        // held is unknown, and that was reported where it was declared.
        if (syntax.Callee is NameSyntax { Name.Parts: [var refused], TypeArguments: null } &&
            LookupLocal(refused) is { } unusable && unusable.Type.IsError())
            return new BoundErrorExpression(syntax.Span);

        // A local, parameter or field holding a delegate is called indirectly,
        // and shadows any function of the same name -- the value is nearer.
        if (BindDelegateTarget(syntax.Callee) is { } indirect)
            return BuildIndirectCall(syntax, indirect, arguments);

        if (syntax.Callee is NameSyntax { Name.Parts.Count: 1 } near &&
            LookupLocalFunction(near.Name.Text) is { } local)
            return BindLocalFunctionCall(syntax, near, local, arguments);

        if (syntax.Callee is NameSyntax callee)
        {
            // A method of the enclosing type, called without a receiver.
            //
            // First, because inside a type a bare name means that type's
            // member: a public function in an imported module does not get to
            // take the call instead. A method that does not accept these
            // arguments is still an error about the method, not a licence to go
            // looking for something else with the same name.
            if (callee.Name.Parts.Count == 1 &&
                _context.Function?.ContainingType?.FindMethods(callee.Name.Text).ToList() is
                    { Count: > 0 } own)
            {
                var method = ResolveOverload(own, arguments, callee.Span, callee.Name.Text, syntax.Arguments);
                if (method is null) return new BoundErrorExpression(syntax.Span);

                // A static one needs nothing to be called on; an instance one
                // needs the enclosing `this`, which a static method has not got.
                var receiver = method.IsStatic ? null : BindImplicitThis(callee.Span);

                if (method.IsStatic || receiver is not null)
                {
                    // Inherited, so it may belong to a base in another module.
                    var owner = method.ContainingType ?? _context.Function!.ContainingType!;
                    if (!CanReach(method.IsPublic, method.IsProtected, owner))
                    {
                        diagnostics.Error("SL0257", callee.Span,
                            NotVisible(owner, callee.Name.Text, method.IsProtected));
                        return new BoundErrorExpression(syntax.Span);
                    }

                    return BuildCall(syntax, method, receiver, arguments);
                }

                if (_context.Function is { IsStatic: true } enclosingStatic)
                {
                    diagnostics.Error("SL0576", callee.Span,
                        $"'{callee.Name.Text}' is an instance method of " +
                        $"'{enclosingStatic.ContainingType!.Name}', and '{enclosingStatic.Name}' " +
                        "is static, so there is no object to call it on. Take one as a " +
                        "parameter, or make this a method",
                        enclosingStatic.ContainingType);
                    return new BoundErrorExpression(syntax.Span);
                }
            }

            // A generic method of the enclosing type, for the same reason.
            if (callee.Name.Parts.Count == 1 && _context.Function?.ContainingType is { } enclosing &&
                GenericMethodsNamed(enclosing, callee.Name.Text) is { Count: > 0 } generics)
            {
                var instantiated = InferAndInstantiate(generics, syntax, arguments);
                if (instantiated is null) return new BoundErrorExpression(syntax.Span);

                if (instantiated.IsStatic)
                    return BuildCall(syntax, instantiated, receiver: null, arguments);

                var receiver = BindImplicitThis(callee.Span);
                if (receiver is not null)
                    return BuildCall(syntax, instantiated, receiver, arguments);
            }

            var candidates = ResolveFunctionCandidates(callee.Name);

            // An instantiation of a generic is an ordinary function with an
            // ordinary name, so it turns up here beside everything else. It must
            // not shadow the template it came from: `Sort(list)` instantiating
            // `Sort<Money>` cannot be what a later `Sort(numbers[2:5])` resolves
            // to. So the templates are tried whenever nothing already built fits.
            if (candidates.Any(c => AcceptsArguments(c, arguments, syntax.Arguments)))
                return BindFunctionCall(syntax, candidates, callee.Name.Text, arguments);

            if (TryBindGenericCall(syntax, callee.Name, arguments) is { } generic) return generic;

            if (candidates.Count > 0)
                return BindFunctionCall(syntax, candidates, callee.Name.Text, arguments);

            // Inside a lambda, a bare name may be a method of the object the
            // lambda was written in. That object is captured, and the call then
            // goes through the capture like any other member.
            if (callee.Name.Parts.Count == 1 && _context.Closures.Count > 0 &&
                MethodsOfEnclosingThis(callee.Name.Text) is { Count: > 0 } outerMethods)
            {
                var outerMethod =
                    ResolveOverload(outerMethods, arguments, callee.Span, callee.Name.Text, syntax.Arguments);
                if (outerMethod is null) return new BoundErrorExpression(syntax.Span);

                // A static one is called on nothing, so there is no object to
                // capture; a lambda in a static initializer has none to give.
                if (outerMethod.IsStatic)
                    return BuildCall(syntax, outerMethod, receiver: null, arguments);

                var captured = CaptureThis(_context.Closures.Count - 1, callee.Span);
                if (captured.Type.IsError()) return new BoundErrorExpression(syntax.Span);
                return BuildCall(syntax, outerMethod, captured, arguments);
            }

            // A closure or delegate held by a static, or captured by the
            // lambda this call is inside: binding the name is what creates the
            // capture, so it is tried here rather than in BindDelegateTarget,
            // which runs before any of the name lookups above.
            if (BindCallableValue(callee) is { } value)
                return BuildIndirectCall(syntax, value, arguments);

            // `Fired(value)` where Fired is one of this type's events: raising
            // it. Only from inside the type that declared it, and only by name
            // -- `publisher.Fired(...)` is a caller raising somebody else's
            // event, which is the thing an event exists to prevent.
            if (callee.Name.Parts.Count == 1 &&
                _context.Function?.ContainingType?.FindEvent(callee.Name.Last) is { } raised)
            {
                if (raised.ContainingType != _context.Function.ContainingType)
                {
                    diagnostics.Error("SL0823", callee.Span,
                        $"'{raised.Name}' is declared by '{raised.ContainingType.Name}', and only " +
                        "the type that declares an event may raise it. A derived class raises " +
                        "one through a protected method its base provides for that",
                        raised.ContainingType);
                    return new BoundErrorExpression(syntax.Span);
                }

                if (raised.Raise is not { } raiser) return new BoundErrorExpression(syntax.Span);

                var self = BindImplicitThis(callee.Span);
                if (self is null)
                {
                    diagnostics.Error("SL0822", callee.Span,
                        $"'{raised.Name}' is an event and belongs to an instance, so it cannot " +
                        "be raised from a static method");
                    return new BoundErrorExpression(syntax.Span);
                }

                return BuildCall(syntax, raiser, self, arguments);
            }

            diagnostics.Error("SL0252", callee.Span, $"no function named '{callee.Name.Text}' is in scope");
            return new BoundErrorExpression(syntax.Span);
        }

        // Anything else that produced something callable: `handlers.At(i)(1)`,
        // where the callee is neither a name nor a member but a value of a
        // closure or delegate type. Bound last, because every shape above is a
        // name to look up rather than an expression to evaluate.
        var produced = BindExpression(syntax.Callee);

        if (IsCallableValue(produced.Type))
            return BuildIndirectCall(syntax, produced, arguments);

        if (produced.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        diagnostics.Error("SL0253", syntax.Span,
            $"this expression is not callable: it is '{produced.Type.Name}', and only a " +
            "delegate or a closure is called through",
            produced.Type);
        return new BoundErrorExpression(syntax.Span);
    }

    /// <summary>
    /// <c>Pick&lt;int&gt;(a, b)</c>: a generic method of the enclosing type, or
    /// a generic function, with its type arguments written rather than
    /// inferred. Nothing that is not generic is a candidate, as in C#.
    /// </summary>
    private BoundExpression BindCallWithTypeArguments(
        CallSyntax syntax, NameSyntax callee, List<BoundExpression> arguments)
    {
        string name = callee.Name.Text;

        if (callee.Name.Parts.Count == 1 && LookupLocalFunction(name) is { } local)
        {
            if (local.Template is null)
            {
                diagnostics.Error("SL0759", callee.Span,
                    $"'{name}' is not generic, so it takes no type arguments; leave the " +
                    "'<...>' off");
                return new BoundErrorExpression(callee.Span);
            }

            return BindLocalFunctionCall(syntax, callee, local, arguments);
        }

        if (callee.Name.Parts.Count == 1 && _context.Function?.ContainingType is { } enclosing &&
            GenericMethodsNamed(enclosing, name) is { Count: > 0 } own)
        {
            var instantiated = InferAndInstantiate(own, syntax, arguments);
            if (instantiated is null)
                return new BoundErrorExpression(syntax.Span);

            if (instantiated.IsStatic)
                return BuildCall(syntax, instantiated, receiver: null, arguments);

            var receiver = BindImplicitThis(callee.Span);
            if (receiver is not null)
                return BuildCall(syntax, instantiated, receiver, arguments);

            diagnostics.Error("SL0576", callee.Span,
                $"'{name}' is an instance method of '{enclosing.Name}', and there is no object " +
                "here to call it on",
                enclosing);
            return new BoundErrorExpression(syntax.Span);
        }

        if (TryBindGenericCall(syntax, callee.Name, arguments) is { } generic)
            return generic;

        bool plain = ResolveFunctionCandidates(callee.Name).Count > 0 ||
                     _context.Function?.ContainingType?.FindMethods(name).Any() == true;
        return RefuseTypeArgumentsOnPlainFunction(callee, name, plain);
    }

    /// <summary>Type arguments written on a call to something that takes none.</summary>
    private BoundExpression RefuseTypeArgumentsOnPlainFunction(
        ExpressionSyntax callee, string name, bool exists)
    {
        if (exists)
        {
            diagnostics.Error("SL0759", callee.Span,
                $"'{name}' is not generic, so it takes no type arguments; leave the " +
                "'<...>' off");
        }
        else
        {
            diagnostics.Error("SL0252", callee.Span, $"no function named '{name}' is in scope");
        }

        return new BoundErrorExpression(callee.Span);
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
        // The name says where the value goes, not what it is, so binding it is
        // binding the value.
        if (syntax is NamedArgumentSyntax named) syntax = named.Value;

        if (syntax is OutArgumentSyntax outgoing) return BindOutArgument(outgoing);
        if (syntax is not RefArgumentSyntax reference) return BindExpression(syntax);

        // A narrowed optional is passed as the storage it is: the callee may
        // write anything its type allows, so what was proved is forgotten.
        var target = Widened(BindExpression(reference.Value));
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

        ForgetWrittenThrough(target);
        NoteWriteTo(target);

        return new BoundAddressOf(
            reference.Span, target.Type.MakePointerType(), target)
        {
            FromRefKeyword = true,
        };
    }

    /// <summary>
    /// A call on a receiver that has already been bound.
    ///
    /// The ordinary path binds the receiver itself, which <c>a?.M()</c> cannot
    /// use: it holds the receiver first, so that asking whether it is there and
    /// reaching through it are one evaluation rather than two.
    /// </summary>
    private BoundExpression BindCallOn(
        BoundExpression receiver, MemberAccessSyntax member, CallSyntax syntax)
    {
        var arguments = syntax.Arguments.Select(BindArgument).ToList();
        RefuseNamesWithoutParameters(syntax);

        return BindMethodCallOn(receiver, syntax, member, arguments);
    }

    /// <summary>
    /// <c>x.F(y)</c> where <c>x</c> has no member <c>F</c>, read as
    /// <c>F(x, y)</c>.
    ///
    /// This is uniform call syntax, and it is here rather than C#'s extension
    /// methods because this language has what C# was working around: a module
    /// is a scope, so a function need not be wrapped in a static class to
    /// exist. There is nothing for a <c>this</c> modifier to add — every free
    /// function in scope is already a candidate, and the only question is
    /// whether its first parameter fits.
    ///
    /// What it buys is the shape a pipeline wants:
    ///
    ///     names.Filter((n) =&gt; n.ByteLength() &gt; 3u).Map(Upper).ToArray()
    ///
    /// read inside out before, and the same functions either way.
    ///
    /// **A member always wins.** This is reached only where lookup has already
    /// failed, so adding a method to a type can never be shadowed by a function
    /// somebody wrote elsewhere, and the reverse — a new free function quietly
    /// taking over a call — cannot happen either.
    ///
    /// Visibility is the ordinary rule: the function has to be one this file
    /// could have called by name. There is no separate import for it, and no
    /// way for a function the file cannot see to attach itself to a type.
    /// </summary>
    private BoundExpression? TryBindAsFreeFunction(
        CallSyntax syntax, MemberAccessSyntax member,
        BoundExpression receiver, List<BoundExpression> arguments)
    {
        // `p->F(x)` insists there was a pointer to follow, which is a statement
        // about a member. A free function is not one.
        if (member.ThroughPointer) return null;

        var written = new List<ExpressionSyntax> { member.Target };
        written.AddRange(syntax.Arguments);

        var whole = new List<BoundExpression> { receiver };
        whole.AddRange(arguments);

        var call = new CallSyntax(
            syntax.Span,
            new NameSyntax(member.Span, new QualifiedName(member.Span, [member.Member]))
                { TypeArguments = member.TypeArguments },
            written);

        var viable = member.TypeArguments is not null
            ? []
            : VisibleFunctions(member.Member)
                .Where(c => AcceptsArguments(c, whole, written))
                .ToList();

        if (viable.Count == 1) return BuildCall(call, viable[0], receiver: null, whole);

        // Nothing fits and nothing is ambiguous, so try the generic templates.
        // Almost everything worth chaining is one -- `Where`, `Select`, `Sort`
        // are all generic -- so this is the common path rather than the
        // fallback it looks like.
        if (viable.Count > 1) return null;

        var templates = FindGenericFunctions(new QualifiedName(member.Span, [member.Member]));
        if (templates.Count == 0) return null;

        // A quiet trial: this is a guess, and its failure is not the program's
        // error. The caller has a better one to report.
        FunctionSymbol? instantiated;
        using (var trial = BeginTrial())
        {
            instantiated = InferAndInstantiate(templates, call, whole);
            if (instantiated is not null) trial.Accept();
        }

        return instantiated is null ? null : BuildCall(call, instantiated, receiver: null, whole);
    }

    /// <summary>Every module-level function of that name this file may call.</summary>
    private List<FunctionSymbol> VisibleFunctions(string name)
    {
        var found = _currentModule!.Functions
            .Where(f => f.Name == name && f.ContainingType is null)
            .ToList();

        foreach (var imported in _context.File!.ImportedModules)
            if (imported != _currentModule)
                found.AddRange(imported.Functions.Where(
                    f => f.Name == name && f.ContainingType is null && f.IsPublic));

        return found;
    }

    /// <summary>
    /// The second half of "no method of that name", when a free function of it
    /// exists but did not fit. Silence there would be the worst of both: the
    /// reader can see a function with the right name and is told only that the
    /// type has no method.
    /// </summary>
    private string NoFreeFunctionEither(string name) =>
        VisibleFunctions(name).Count == 0
            ? ""
            : $", and no function '{name}' in scope takes it as a first argument";

    /// <summary>
    /// <c>out x</c>, and the two forms that declare what they name.
    ///
    /// A declaring form goes out as a draft, because <c>out var x</c> says
    /// nothing about which overload was meant and must not pretend to. The
    /// local is declared once one has been chosen, in
    /// <see cref="SettleOutDraft"/>, with the type its parameter says.
    /// </summary>
    private BoundExpression BindOutArgument(OutArgumentSyntax syntax)
    {
        if (syntax.DeclaredName is { } name)
        {
            var declared = syntax.DeclaredType is null
                ? ErrorTypeSymbol.Instance
                : ResolveType(syntax.DeclaredType, _context.File!);

            return new BoundOutDraft(syntax.Span, declared, name, syntax.NameSpan);
        }

        var target = Widened(BindExpression(syntax.Value!));
        if (target.Type.IsError()) return target;

        if (!IsAddressable(target))
        {
            diagnostics.Error("SL0443", syntax.Span,
                "'out' passes the storage this names rather than a copy of it, and this " +
                "expression has no storage to pass; put it in a local first, or write " +
                "'out var' to declare one here");
            return new BoundErrorExpression(syntax.Span);
        }

        if (IsReadOnlyTarget(target) is { } why)
        {
            diagnostics.Error("SL0444", syntax.Span,
                $"'out' lets the callee write to this, and {why}");
            return new BoundErrorExpression(syntax.Span);
        }

        ForgetWrittenThrough(target);
        NoteWriteTo(target);

        return new BoundAddressOf(syntax.Span, target.Type.MakePointerType(), target)
        {
            FromOutKeyword = true,
        };
    }

    /// <summary>
    /// What passing storage by <c>ref</c> or <c>out</c> costs the caller: the
    /// callee may write it, so nothing proved about it survives the call.
    /// </summary>
    private void ForgetWrittenThrough(BoundExpression target)
    {
        InvalidateVariantFact(target);
        if (WrittenParameter(target) is { } parameter) MarkAssigned(parameter);
    }

    /// <summary>
    /// Declares the local an <c>out var x</c> promised, now that a parameter
    /// has said what type it is.
    /// </summary>
    private BoundExpression SettleOutDraft(BoundOutDraft draft, ParameterSymbol parameter)
    {
        var type = draft.NeedsType ? parameter.Type : draft.Type;
        var local = DeclareLocal(draft.Name, type, isConst: false, draft.NameSpan);

        return new BoundAddressOf(
            draft.Span, type.MakePointerType(),
            new BoundLocalAccess(draft.NameSpan, local))
        {
            FromOutKeyword = true,
            DeclaresLocal = local,
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
    private static string? IsReadOnlyTarget(BoundExpression expression) => BaseOf(expression) switch
    {
        BoundIndex { Target.Type: SliceTypeSymbol { IsReadOnly: true } slice } =>
            $"it is an element of a '{slice.Name}', which only reads",
        BoundLocalAccess { Local.IsConst: true } local =>
            $"'{local.Local.Name}' is a 'const'",
        BoundParameterAccess { Parameter.Mode: ParameterMode.In } parameter =>
            $"'{parameter.Parameter.Name}' is an 'in' parameter, which promises not to be written",
        BoundParameterAccess { Parameter.CaptureOrigin: not null } copied =>
            $"'{copied.Parameter.Name}' is a local function's copy of a variable around it",
        BoundStaticAccess { Static.IsReadonly: true } held =>
            $"'{held.Static.Name}' is a 'static readonly'",
        BoundStaticAccess { Static.IsImported: true } foreign when IsObjCReference(foreign.Type) =>
            $"'{foreign.Static.Name}' is an Objective-C object a C library holds, and only reads",
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

                if (LookupLocal(text) is { } local && IsCallableValue(local.Type))
                    return Narrowed(new BoundLocalAccess(name.Span, local), local);

                if (_context.Function?.Parameters.FirstOrDefault(
                        p => p.Name == text && !p.IsThis) is { } parameter &&
                    IsCallableValue(parameter.Type))
                    return Narrowed(new BoundParameterAccess(name.Span, parameter), parameter);

                if (_context.Function is { } function &&
                    (function.Captures.FirstOrDefault(c => c.Name == text)?.Type ??
                     _localFunctionOf.GetValueOrDefault(function)?.Visible?.GetValueOrDefault(text).Type)
                    is { } capturedType && IsCallableValue(capturedType))
                    return TryCaptureIntoLocalFunction(text, name.Span);

                if (_context.Function?.ContainingType?.FindProperty(text) is { } property &&
                    IsCallableValue(property.Type))
                {
                    var receiver = BindImplicitThis(name.Span);
                    if (receiver is not null)
                        return BindPropertyRead(name.Span, receiver, property);
                }

                if (_context.Function?.ContainingType?.FindField(text) is { } field &&
                    IsCallableValue(field.Type))
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

    /// <summary>
    /// The callee bound as a value, when it is one that can be called; null,
    /// with nothing reported, when it is not.
    /// </summary>
    private BoundExpression? BindCallableValue(ExpressionSyntax callee)
    {
        // Bound twice, so the first is a trial nothing keeps.
        bool callable;
        using (BeginTrial())
            callable = IsCallableValue(BindExpression(callee).Type);

        return callable ? BindExpression(callee) : null;
    }

    /// <summary>A value that is called rather than dispatched to.</summary>
    private static bool IsCallableValue(TypeSymbol type) =>
        type is DelegateTypeSymbol or ClosureTypeSymbol or ObjCBlockTypeSymbol;

    private BoundExpression BuildIndirectCall(
        CallSyntax syntax, BoundExpression target, List<BoundExpression> arguments)
    {
        if (target.Type is ClosureTypeSymbol { IsNullable: true } maybe)
        {
            diagnostics.Error("SL0248", syntax.Callee.Span,
                $"'{maybe.Name}' may be null, so it cannot be called until a check says it holds " +
                $"a closure: test it against null, or name what it holds with 'is {{ }} handler'",
                maybe);
            return new BoundErrorExpression(syntax.Span);
        }

        if (target.Type is ClosureTypeSymbol closure)
            return BuildClosureCall(syntax, closure, target, arguments);

        if (target.Type is ObjCBlockTypeSymbol block)
            return BuildBlockCall(syntax, block, target, arguments);

        var delegateType = (DelegateTypeSymbol)target.Type;

        if (ArrangeThroughSignature(syntax, delegateType.Name, delegateType.SignatureText,
                delegateType.ReturnType, delegateType.Signature, arguments, out var order) is not { } converted)
            return new BoundErrorExpression(syntax.Span);

        return new BoundIndirectCall(syntax.Span, delegateType, target, converted)
            { EvaluationOrder = order };
    }

    /// <summary>
    /// The same, through a closure. The receiver it carries goes in first and
    /// is not one of the arguments written, so the count is checked against the
    /// signature exactly as a delegate's is.
    /// </summary>
    private BoundExpression BuildClosureCall(
        CallSyntax syntax, ClosureTypeSymbol closure,
        BoundExpression target, List<BoundExpression> arguments)
    {
        if (ArrangeThroughSignature(syntax, closure.Name, closure.SignatureText,
                closure.ReturnType, closure.Signature, arguments, out var order) is not { } converted)
            return new BoundErrorExpression(syntax.Span);

        return new BoundClosureCall(syntax.Span, closure, target, converted)
            { EvaluationOrder = order };
    }

    /// <summary>
    /// The arguments of a call through a delegate or a closure, one per
    /// parameter of its signature and converted to it. A name reaches the
    /// parameter the signature calls that, and a default is filled in where a
    /// lambda's own type has one (<c>var f = (int x = 1) =&gt; x;</c>).
    /// </summary>
    private List<BoundExpression>? ArrangeThroughSignature(
        CallSyntax syntax, string name, string shape, TypeSymbol returnType,
        IReadOnlyList<ParameterSymbol> signature, List<BoundExpression> arguments, out int[]? order)
    {
        order = null;
        int required = signature.Count(p => !p.IsOptional);

        if (arguments.Count < required || arguments.Count > signature.Count)
        {
            diagnostics.Error("SL0363", syntax.Span,
                $"'{name}' is '{shape}' and takes " +
                (required == signature.Count
                    ? Counted(signature.Count, "argument")
                    : $"{required} to {signature.Count} arguments") +
                $", but {Given(arguments.Count)}",
                [returnType, .. signature.Select(p => p.Type)]);
            return null;
        }

        int[]? map = MapArguments(signature, arguments.Count, syntax.Arguments, false, out string? why);
        if (map is null)
        {
            diagnostics.Error("SL0601", syntax.Span,
                $"the call to '{name}' does not fit: " + (why ?? "the names do not match its parameters"));
            return null;
        }

        var converted = new List<BoundExpression>(signature.Count);
        for (int p = 0; p < signature.Count; p++)
        {
            var parameter = signature[p];

            if (map[p] < 0)
            {
                converted.Add(parameter.Default ?? new BoundErrorExpression(syntax.Span));
                continue;
            }

            var argument = arguments[map[p]];
            if (!ArgumentFits(argument, parameter))
            {
                ReportArgumentMode(name, p, argument, parameter);
                return null;
            }

            converted.Add(ConvertArgument(argument, parameter, syntax.Arguments[map[p]].Span));
        }

        order = WrittenOrder(map, converted.Count);
        return converted;
    }

    /// <summary>
    /// <c>FileStream.Open(path)</c>: a method of the type, called with no
    /// receiver.
    ///
    /// From here on it is an ordinary direct call -- the same shape a
    /// module-level function's is -- so nothing downstream has to know that the
    /// name was qualified by a type rather than by a module.
    /// </summary>
    private BoundExpression BindStaticCall(
        CallSyntax syntax, MemberAccessSyntax member, NamedTypeSymbol type,
        List<BoundExpression> arguments)
    {
        var overloads = type.FindMethods(member.Member).ToList();

        // Through a type parameter, a type that supplies nothing of this name
        // falls back on its interfaces' `static virtual` bodies.
        if (!overloads.Any(m => m.IsStatic) && NamesTypeParameter(member.Target))
            overloads = StaticDefaults(type, member.Member);

        // A generic method is a template rather than a method, so it is not
        // among the overloads and has to be looked for where templates live.
        //
        // **When nothing non-generic fits, not only when nothing exists.** One
        // name may have both -- `Run(Action, Action)` beside
        // `Run<T>(IProduce<T>, IConsume<T>)` -- and then the arguments are what
        // decide. Asking only whether the overload list was empty let the
        // non-generic one answer for every call, so the generic one was
        // unreachable and the error was about the lambda not fitting `Action`.
        bool written = member.TypeArguments is not null;

        if (type.GenericMethods.Where(m => m.Name == member.Member).ToList() is { Count: > 0 } templates
            && (written ||
                !overloads.Any(m => m.IsStatic && AcceptsArguments(m, arguments, syntax.Arguments))))
        {
            if (!templates[0].IsPublic && type.ModuleName != _currentModule!.Name)
            {
                diagnostics.Error("SL0257", member.Span,
                    $"'{type.Name}.{member.Member}' is not public",
                    type);
                return new BoundErrorExpression(syntax.Span);
            }

            var instantiated = InferAndInstantiate(templates, syntax, arguments);
            if (instantiated is null) return new BoundErrorExpression(syntax.Span);

            if (!instantiated.IsStatic)
            {
                diagnostics.Error("SL0576", member.Span,
                    $"'{type.Name}.{member.Member}' is not static, so it needs an object to be " +
                    "called on; name one instead of the type",
                    type);
                return new BoundErrorExpression(syntax.Span);
            }

            return BuildCall(syntax, instantiated, receiver: null, arguments);
        }

        if (written)
            return RefuseTypeArgumentsOnPlainFunction(member, member.Member, exists: true);

        // An instance method reached through the type name is the mistake this
        // is worth naming: the call is missing the thing it is about.
        if (overloads.All(m => !m.IsStatic))
        {
            diagnostics.Error("SL0576", member.Span,
                $"'{type.Name}.{member.Member}' is not static, so it needs an object to be " +
                "called on; name one instead of the type",
                type);
            return new BoundErrorExpression(syntax.Span);
        }

        var statics = overloads.Where(m => m.IsStatic).ToList();

        var method = statics.Count == 1
            ? statics[0]
            : ResolveOverload(statics, arguments, member.Span, $"{type.Name}.{member.Member}", syntax.Arguments);

        if (method is null) return new BoundErrorExpression(syntax.Span);

        if (RefuseStaticRequirement(method, type, member.Span))
            return new BoundErrorExpression(syntax.Span);

        if (!CanReach(method.IsPublic, method.IsProtected, method.ContainingType ?? type))
        {
            diagnostics.Error("SL0257", member.Span,
                NotVisible(method.ContainingType ?? type, member.Member, method.IsProtected));
            return new BoundErrorExpression(syntax.Span);
        }

        return BuildCall(syntax, method, receiver: null, arguments, named: type);
    }

    private BoundExpression BindMethodCall(
        CallSyntax syntax, MemberAccessSyntax member, List<BoundExpression> arguments)
    {
        if (!member.ThroughPointer && ConstructedTypeNamed(member.Target) is { } constructed)
        {
            diagnostics.Error("SL0255", member.Span,
                $"'{constructed.Name}' has no static method named '{member.Member}'",
                constructed);
            return new BoundErrorExpression(syntax.Span);
        }

        var bound = member.Target is BaseSyntax
            ? BindBaseReceiver(member.Target.Span)
            : BindExpression(member.Target);

        if (bound is null || bound.Type.IsError()) return new BoundErrorExpression(syntax.Span);
        if (RefuseUntyped(bound))
            return new BoundErrorExpression(syntax.Span);

        if (ReachThroughPointer(member, bound) is not { } reachedThrough)
            return new BoundErrorExpression(syntax.Span);

        return BindMethodCallOn(reachedThrough, syntax, member, arguments);
    }

    /// <summary>
    /// The same on a receiver already bound, which is what <c>a?.M()</c> needs:
    /// it holds the receiver first, so that asking whether it is there and
    /// reaching through it are one evaluation rather than two.
    /// </summary>
    private BoundExpression BindMethodCallOn(
        BoundExpression receiver, CallSyntax syntax, MemberAccessSyntax member,
        List<BoundExpression> arguments)
    {

        if (receiver.Type is OptionalTypeSymbol or WeakTypeSymbol)
        {
            diagnostics.Error("SL0254", member.Span,
                $"'{receiver.Type.Name}' may be null; check it against null before calling '{member.Member}'",
                receiver.Type);
            return new BoundErrorExpression(syntax.Span);
        }

        // An enum has no methods, so `HasFlag` is the language spelling the test
        // out rather than a member being called: it becomes `(value & f) == f`,
        // which is the same thing written by hand and costs the same.
        if (receiver.Type is EnumTypeSymbol flagsEnum && member.Member == "HasFlag")
            return BindHasFlag(syntax, member, receiver, flagsEnum, arguments);

        // `ToText` is the other: the text an interpolation writes, as a
        // String of its own.
        if (receiver.Type is EnumTypeSymbol named && member.Member == "ToText")
        {
            if (arguments.Count == 0)
                return EnumText(receiver, named, syntax.Span);

            diagnostics.Error("SL0260", syntax.Span,
                $"'{named.Name}.ToText' takes no arguments, but {Given(arguments.Count)}; " +
                "an enum's text has no format",
                named);
            return new BoundErrorExpression(syntax.Span);
        }

        if (member.TypeArguments is not null && receiver.Type is not NamedTypeSymbol)
        {
            return TryBindAsFreeFunction(syntax, member, receiver, arguments)
                ?? RefuseTypeArgumentsOnPlainFunction(member, member.Member, exists: false);
        }

        if (TryBindIntrinsicMember(syntax, member, receiver, arguments) is { } intrinsic)
            return intrinsic;

        if (receiver.Type is not NamedTypeSymbol namedType)
        {
            if (TryBindAsFreeFunction(syntax, member, receiver, arguments) is { } chained)
                return chained;

            diagnostics.Error("SL0255", member.Span,
                $"'{receiver.Type.Name}' has no method named '{member.Member}'" +
                NoFreeFunctionEither(member.Member),
                receiver.Type);
            return new BoundErrorExpression(syntax.Span);
        }

        // A field holding a delegate is called through, not dispatched to. It is
        // checked before methods so that the field's own name is what is called;
        // a method of the same name would be a different thing entirely.
        if (namedType.FindProperty(member.Member) is { } callableProperty &&
            IsCallableValue(callableProperty.Type))
        {
            var read = BindPropertyRead(member.Span, receiver, callableProperty,
                                        nonVirtual: member.Target is BaseSyntax);
            return read.Type.IsError()
                ? new BoundErrorExpression(syntax.Span)
                : BuildIndirectCall(syntax, read, arguments);
        }

        if (namedType.FindField(member.Member) is { } callable && IsCallableValue(callable.Type))
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

        // Type arguments written: only a generic method is a candidate.
        if (member.TypeArguments is not null)
        {
            if (TryBindGenericMethodCall(syntax, member, namedType, receiver, arguments) is { } asked)
                return asked;

            if (TryBindAsFreeFunction(syntax, member, receiver, arguments) is { } chainedGeneric)
                return chainedGeneric;

            return RefuseTypeArgumentsOnPlainFunction(member, member.Member, overloads.Count > 0);
        }

        // The generic sibling of this name is tried whenever nothing here fits,
        // for the reason spelled out in BindStaticCall: a name may carry both a
        // generic method and a plain one, and only the arguments say which was
        // meant.
        if (overloads.Count > 0 &&
            !overloads.Any(m => AcceptsArguments(m, arguments, syntax.Arguments)) &&
            TryBindGenericMethodCall(syntax, member, namedType, receiver, arguments) is { } sibling)
            return sibling;

        if (overloads.Count == 0)
        {
            if (TryBindGenericMethodCall(syntax, member, namedType, receiver, arguments) is { } generic)
                return generic;

            if (TryBindAsFreeFunction(syntax, member, receiver, arguments) is { } chained)
                return chained;

            // `publisher.Fired(...)` is a caller raising somebody else's event,
            // which is the one thing having a word for it prevents.
            if (namedType.FindEvent(member.Member) is { } raised)
            {
                diagnostics.Error("SL0823", member.Span,
                    $"'{namedType.Name}.{member.Member}' is an event, and only " +
                    $"'{raised.ContainingType.Name}' may raise it -- from inside, by writing " +
                    $"'{member.Member}(...)'. From out here an event can only be subscribed to " +
                    "with '+=' and unsubscribed from with '-='",
                    namedType, raised.ContainingType);
                return new BoundErrorExpression(syntax.Span);
            }

            diagnostics.Error("SL0255", member.Span,
                $"'{namedType.Name}' has no method named '{member.Member}'" +
                NoFreeFunctionEither(member.Member),
                namedType);
            return new BoundErrorExpression(syntax.Span);
        }

        // A static method is reached through the type, never through an
        // object. Allowing both would let a reader think the receiver was
        // being used for something.
        if (overloads.All(m => m.IsStatic))
        {
            diagnostics.Error("SL0576", member.Span,
                $"'{namedType.Name}.{member.Member}' is static, so it is called on the type " +
                $"rather than on a value: write '{namedType.SimpleName}.{member.Member}(...)'",
                namedType);
            return new BoundErrorExpression(syntax.Span);
        }

        overloads = overloads.Where(m => !m.IsStatic).ToList();

        // Which overload is decided by the arguments, the same way a call to a
        // module-level function is.
        var method = overloads.Count == 1
            ? overloads[0]
            : ResolveOverload(overloads, arguments, member.Span, $"{namedType.Name}.{member.Member}", syntax.Arguments);

        if (method is null) return new BoundErrorExpression(syntax.Span);

        // The accessors are real methods, but they are the lowering rather than
        // the language: naming one directly is naming an implementation detail.
        if (method.Accessor is { } accessed)
        {
            diagnostics.Error("SL0398", member.Span,
                $"'{member.Member}' is the {(method.ReturnType.IsVoid() ? "setter" : "getter")} of " +
                $"property '{namedType.Name}.{accessed.Name}'; use the property itself",
                namedType);
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
            receiver = new BoundAddressOf(member.Span, namedType.MakePointerType(), receiver);

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
                "rather than a set of them; mark it '[Flags]' if its members are meant to combine",
                enumType);
            return new BoundErrorExpression(syntax.Span);
        }

        if (arguments.Count != 1)
        {
            diagnostics.Error("SL0409", syntax.Span,
                $"'HasFlag' takes one '{enumType.Name}', but {Given(arguments.Count)}",
                enumType);
            return new BoundErrorExpression(syntax.Span);
        }

        var flag = arguments[0];
        if (!flag.Type.Equals(enumType))
        {
            if (!flag.Type.IsError())
                diagnostics.Error("SL0409", syntax.Arguments[0].Span,
                    $"'HasFlag' takes one '{enumType.Name}', but this is '{flag.Type.Name}'",
                    enumType, flag.Type);
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
    /// Binds <c>CompareTo</c>, <c>Equals</c> and <c>GetHashCode</c> on a type that
    /// implements them without saying so, or returns null when this is an
    /// ordinary call.
    ///
    /// Each lowers to something that already exists: equality to the <c>==</c>
    /// the binder knows for that type, and the other two to a runtime call. A
    /// declared member always wins, because this runs only after lookup on a
    /// named type has failed.
    /// </summary>
    /// <summary>
    /// <c>Fired.Clear()</c> inside the type that declared <c>Fired</c>: drops
    /// every subscriber at once.
    ///
    /// The declaring type's alone, for the reason only it may raise the event:
    /// a subscriber that could clear the list could throw away everybody
    /// else's subscriptions. The publisher can, and a publisher that is being
    /// taken apart -- a control removed from its form -- is the one that
    /// knows its subscribers are no longer wanted.
    /// </summary>
    private BoundExpression? TryBindEventClear(CallSyntax syntax, List<BoundExpression> arguments)
    {
        if (syntax.Callee is not MemberAccessSyntax
            {
                Member: "Clear", Conditional: false, Target: NameSyntax { Name.Parts.Count: 1 } named,
            })
            return null;
        if (LookupLocal(named.Name.Last) is not null) return null;
        if (_context.Function?.ContainingType is not { } owner) return null;
        if (owner.FindEvent(named.Name.Last) is not { } cleared) return null;
        if (cleared.ContainingType != owner || cleared.BackingField is not { } field) return null;

        if (arguments.Count != 0)
        {
            diagnostics.Error("SL0412", syntax.Span,
                $"'{cleared.Name}.Clear' takes no arguments, but {Given(arguments.Count)}");
            return new BoundErrorExpression(syntax.Span);
        }

        if (BindImplicitThis(syntax.Span) is not { } receiver)
        {
            diagnostics.Error("SL0822", syntax.Span,
                $"'{cleared.Name}' is an event and belongs to an instance, so it cannot be " +
                "reached from a static method");
            return new BoundErrorExpression(syntax.Span);
        }

        var array = ArrayOf(cleared.Type);
        return new BoundAssignment(syntax.Span,
            new BoundFieldAccess(syntax.Span, receiver, field),
            new BoundNewArray(syntax.Span, array,
                new BoundLiteral(syntax.Span, PrimitiveTypeSymbol.NUInt, 0UL)));
    }

    private BoundExpression? TryBindIntrinsicMember(
        CallSyntax syntax, MemberAccessSyntax member, BoundExpression receiver,
        List<BoundExpression> arguments)
    {
        var type = receiver.Type;
        if (!HasIntrinsicMembers(type)) return null;
        if (type is NamedTypeSymbol named && named.FindMethod(member.Member) is not null) return null;

        int wanted = member.Member == "GetHashCode" ? 0 : 1;
        if (member.Member is not ("CompareTo" or "Equals" or "GetHashCode")) return null;

        if (arguments.Count != wanted)
        {
            diagnostics.Error("SL0412", syntax.Span,
                $"'{type.Name}.{member.Member}' takes {wanted} " +
                $"argument{(wanted == 1 ? "" : "s")}, but {Given(arguments.Count)}",
                type);
            return new BoundErrorExpression(syntax.Span);
        }

        if (member.Member == "GetHashCode")
            return new BoundCall(syntax.Span, HashFor(type), null, [Widen(receiver, HashFor(type))]);

        var other = BindConversion(arguments[0], type, syntax.Arguments[0].Span);
        if (other.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        // A float's Equals is CompareTo's equality rather than IEEE's, so NaN
        // equals NaN as HashDouble already assumes. With `==` a NaN key in a
        // Dictionary could never be found, and every Set added another.
        if (member.Member == "Equals" && type is PrimitiveTypeSymbol { IsFloat: true })
        {
            var ordering = _builtins.CompareDouble;
            var compared = new BoundCall(
                syntax.Span, ordering, null, [Widen(receiver, ordering), Widen(other, ordering)]);
            return BindBinaryOperation(
                syntax.Span, compared, BoundBinaryOp.Equal,
                new BoundLiteral(syntax.Span, PrimitiveTypeSymbol.Int, 0UL), TokenKind.EqualsEquals);
        }

        // Equality is the operator, which already knows how to compare a String
        // and how to compare an enum.
        if (member.Member == "Equals")
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

            return _context.File!.ImportedModules
                .SelectMany(m => m.FindFunctions(name.Parts[0]))
                .Where(f => f.IsPublic)
                .ToList();
        }

        // Qualified: everything before the last part names a module.
        string moduleName = string.Join('.', name.Parts.Take(name.Parts.Count - 1));
        if (_context.File!.Imports.TryGetValue(moduleName, out var module) ||
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
            diagnostics.Error("SL0252", syntax.Span, $"no function named '{name}' is in scope");
            return new BoundErrorExpression(syntax.Span);
        }

        var function = ResolveOverload(candidates, arguments, syntax.Span, name, syntax.Arguments);
        if (function is null) return new BoundErrorExpression(syntax.Span);

        return BuildCall(syntax, function, receiver: null, arguments);
    }

    /// <param name="named">The type a static call was written through, which a class message is sent to.</param>
    private BoundExpression BuildCall(
        CallSyntax syntax, FunctionSymbol function, BoundExpression? receiver,
        List<BoundExpression> arguments, bool nonVirtual = false, NamedTypeSymbol? named = null)
    {
        if (nonVirtual && function.IsAbstract)
            return RefuseAbstractBase(function.Name, syntax.Span);

        var parameters = function.Parameters.Where(p => !p.IsThis).ToList();
        var written = GatherParams(function, ref arguments, syntax.Arguments, syntax.Span);

        if (!CheckArity(function.Name, parameters, arguments.Count, function.IsVariadic, syntax.Span))
            return new BoundErrorExpression(syntax.Span);

        // This is the one place every ordinary call passes through, so it is
        // where the names are turned back into positions and where a parameter
        // the call left out is filled in from its default -- everything after
        // it sees one argument per parameter, in the order they were declared.
        int[]? map = MapArguments(
            parameters, arguments.Count, written, function.IsVariadic, out string? why);

        if (map is null)
        {
            diagnostics.Error("SL0601", syntax.Span,
                $"the call to '{function.Name}' does not fit: " +
                (why ?? "the names do not match its parameters"));
            return new BoundErrorExpression(syntax.Span);
        }

        var (ordered, spans) = Arrange(
            function, parameters, arguments, written, map, syntax.Span);

        if (_builtins.IsReferenceQuery(function))
            return new BoundLiteral(syntax.Span, PrimitiveTypeSymbol.Bool,
                function.TypeArguments[0].IsReferenceOrContainsReferences());

        if (_builtins.IsTypeNameQuery(function))
            return new BoundStringLiteral(syntax.Span, _builtins.String,
                FullTypeName(function.TypeArguments[0]));

        var converted = ConvertArguments(function, ordered, spans);
        var order = WrittenOrder(map, converted.Count);

        if (ExpandActivatorCall(syntax, function, converted) is { } expanded)
            return expanded;

        if (_builtins.IsArrayCreate(function) && order is null &&
            converted is [var count, { Type: ClosureTypeSymbol } make])
            return new BoundArrayCreate(syntax.Span, (ArrayTypeSymbol)function.ReturnType, count, make);

        if (function.IsMessage)
            return SendMessage(syntax.Span, function, receiver, converted, order, nonVirtual, named);

        return new BoundCall(syntax.Span, function, receiver, converted)
            { IsNonVirtual = nonVirtual, EvaluationOrder = order };
    }

    /// <summary>
    /// A type's name with every named type in it qualified, its type arguments
    /// included: <c>Standard.Collections.List&lt;App.Point&gt;</c>.
    /// </summary>
    private static string FullTypeName(TypeSymbol type) => type switch
    {
        NamedTypeSymbol { Template: { } template, TypeArguments.Count: > 0 } named =>
            (string.IsNullOrEmpty(named.ModuleName) ? "" : named.ModuleName + ".") + template.Name +
            "<" + string.Join(", ", named.TypeArguments.Select(FullTypeName)) + ">",
        NamedTypeSymbol named => named.QualifiedName,
        ArrayTypeSymbol array => FullTypeName(array.Element) + "[]",
        OptionalTypeSymbol optional => FullTypeName(optional.Element) + "?",
        PointerTypeSymbol pointer => FullTypeName(pointer.Element) + "*",
        _ => type.Name,
    };

    /// <summary><c>base.M()</c> where the base only declares <c>M</c>: there is no body to call.</summary>
    private BoundErrorExpression RefuseAbstractBase(string name, SourceSpan span)
    {
        diagnostics.Error("SL0806", span,
            $"'{name}' is abstract where 'base' looks, so there is no body there to call; " +
            "'base' names the implementation this class replaced, and this one replaces none");
        return new BoundErrorExpression(span);
    }

    /// <summary>
    /// The declared positions in the order the call wrote them, or null when
    /// the two agree. Arguments are evaluated as written, as C#'s are; a
    /// default is a constant and goes last.
    /// </summary>
    private static int[]? WrittenOrder(int[] map, int count)
    {
        var order = Enumerable.Range(0, count)
            .Where(p => p >= map.Length || map[p] >= 0)
            .OrderBy(p => p < map.Length ? map[p] : p)
            .Concat(Enumerable.Range(0, map.Length).Where(p => map[p] < 0))
            .ToArray();

        for (int i = 0; i < order.Length; i++)
            if (order[i] != i)
                return order;

        return null;
    }

    private List<BoundExpression> ConvertArguments(
        FunctionSymbol function, List<BoundExpression> arguments, IReadOnlyList<SourceSpan> spans)
    {
        var parameters = function.Parameters.Where(p => !p.IsThis).ToList();
        var result = new List<BoundExpression>(arguments.Count);

        for (int i = 0; i < arguments.Count; i++)
        {
            var span = i < spans.Count ? spans[i] : arguments[i].Span;

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
        // A draft has been waiting for exactly this: the parameter is what
        // says the type of the variable it declares.
        if (argument is BoundOutDraft draft) return SettleOutDraft(draft, parameter);

        if (parameter.Mode is ParameterMode.Ref or ParameterMode.Out) return argument;

        var value = BindConversion(argument, parameter.Type, span);

        return parameter.Mode == ParameterMode.In && !value.Type.IsError()
            ? new BoundAddressOf(span, parameter.Type.MakePointerType(), value)
            : value;
    }

    private static string DescribeUnsettled(TypeSymbol unsettled) => unsettled switch
    {
        LambdaType => "a lambda",
        FunctionGroupType => "a function's name",
        ArrayDraftType => "an array literal",
        _ => "a case of a variant",
    };

    /// <summary>C's default argument promotions: float widens to double, small ints to int.</summary>
    private BoundExpression PromoteVariadic(BoundExpression argument)
    {
        if (RefuseUntyped(argument))
            return new BoundErrorExpression(argument.Span);

        // Nothing declares what a variadic argument must be, so nothing else
        // would notice there is no value to pass.
        if (argument.Type.IsVoid())
        {
            diagnostics.Error("SL0265", argument.Span,
                "cannot pass 'void' to a C variadic function; 'void' is the absence of a value");
            return new BoundErrorExpression(argument.Span);
        }

        // A lambda, a function's name, an array literal and a case take their
        // type from a parameter, and '...' declares none.
        if (argument.Type is LambdaType or FunctionGroupType or ArrayDraftType or VariantDraftType)
        {
            diagnostics.Error("SL0805", argument.Span,
                $"cannot pass {DescribeUnsettled(argument.Type)} to a C variadic function; it takes its " +
                "type from the parameter it is given to, and '...' declares none. Convert it " +
                "to the type the function expects first");
            return new BoundErrorExpression(argument.Span);
        }

        // A C variadic function has no declared parameter type to convert
        // against, so the String-to-bytes decision has to be made here instead.
        if (argument is BoundStringLiteral)
            return new BoundConversion(argument.Span, PrimitiveTypeSymbol.Byte.MakePointerType(),
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

        // "an array literal was given" says nothing a reader did not already
        // know. Settling it against the parameter reports what is actually
        // wrong -- an element that does not fit, or a length that does not.
        if (argument is BoundArrayDraft draft)
        {
            BindArraySettle(draft, target, argument.Span);
            return;
        }

        if (RefusedStructAsInterface(argument.Type, target, argument.Span))
            return;

        diagnostics.Error("SL0262", argument.Span,
            $"argument {index + 1} of '{name}' expects '{target.Name}', " +
            $"but '{argument.Type.Name}' was given",
            target, argument.Type);
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
            return target switch
            {
                DelegateTypeSymbol wanted => group.Candidates.Any(wanted.Accepts),

                // A method fits a closure the same way, and the receiver plays
                // no part in the match: what the closure carries is the object,
                // and what its signature describes is the call.
                ClosureTypeSymbol bound => group.Candidates.Any(bound.Accepts),
                _ => false,
            };

        if (argument is BoundLambda lambda)
            return target switch
            {
                DelegateTypeSymbol signature =>
                    signature.Signature.Count == lambda.Syntax.Parameters.Count &&
                    WrittenResultFits(lambda.Syntax, signature.ReturnType) &&
                    ProducedResultFits(lambda.Syntax, signature),
                ClosureTypeSymbol bound =>
                    bound.Signature.Count == lambda.Syntax.Parameters.Count &&
                    WrittenResultFits(lambda.Syntax, bound.ReturnType) &&
                    ProducedResultFits(lambda.Syntax, bound),
                InterfaceTypeSymbol functional => SingleMethodOf(functional) is { } only &&
                    only.Parameters.Count(p => !p.IsThis) == lambda.Syntax.Parameters.Count &&
                    WrittenResultFits(lambda.Syntax, only.ReturnType),
                _ => false,
            };

        // A conditional whose arms both wait fits where each of them would.
        if (argument is BoundConditional
            {
                Type: DefaultLiteralType or NewDraftType or ArrayDraftType or TupleDraftType
                    or VariantDraftType,
            } either)
            return IsImplicitlyConvertible(either.WhenTrue, target) &&
                   IsImplicitlyConvertible(either.WhenFalse, target);

        // C#'s rule for `default`: it fits anything with a value, so two such
        // overloads are ambiguous rather than one of them chosen. `new(...)`
        // fits anything `new` could make.
        if (argument.Type is DefaultLiteralType)
            return !target.IsVoid();

        if (argument.Type is NewDraftType)
            return CouldBeMadeByNew(target);

        var written = argument switch
        {
            BoundTupleDraft waiting => waiting.Elements,
            BoundTupleCreate literal when target is TupleTypeSymbol && !literal.Type.Equals(target)
                => literal.Elements,
            _ => null,
        };

        if (written is not null)
            return target is TupleTypeSymbol wanted &&
                   wanted.Elements.Count == written.Count &&
                   written.Select((e, i) => IsImplicitlyConvertible(e, wanted.Elements[i])).All(x => x);

        if (argument is BoundArrayDraft draft2)
            return CollectionFits(draft2, target);

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
        if (CharacterFits(argument, target)) return true;

        // A value fits the `Optional<T>` holding it. Asked here as well as in
        // BindConversion so that overload resolution and the conversion itself
        // agree about what is possible.
        if (PromotedToOptional(argument, target) is not null) return true;
        if (FillsSlot(argument, target) is not null) return true;

        if (ClassifyConversion(argument.Type, target, explicitCast: false) is not null) return true;

        // A declared conversion makes an argument fit, so that overload
        // resolution and the conversion itself agree about what is possible.
        return HasUserConversion(argument, target);
    }

    /// <summary>
    /// Whether a result a lambda wrote out is the one a target returns. It is
    /// not converted, so it votes on the overload the way a written parameter
    /// type would.
    /// </summary>
    private bool WrittenResultFits(LambdaSyntax syntax, TypeSymbol returns)
    {
        if (syntax.ReturnType is null) return true;

        var written = ResolveTypeQuietly(syntax.ReturnType, _context.File!, allowVoid: true);
        return written.IsError() || written.Equals(returns);
    }

    /// <summary>
    /// Whether what a lambda's body produces converts to what the delegate
    /// returns, as C# asks: <c>i =&gt; i.Price</c> is not a
    /// <c>Func&lt;Item, int&gt;</c> when the price is a <c>double</c>. A body
    /// that cannot be probed, or a delegate that returns nothing, is not held
    /// against the lambda here; binding it says what is wrong.
    /// </summary>
    private bool ProducedResultFits(LambdaSyntax syntax, TypeSymbol target)
    {
        if (syntax.ReturnType is not null) return true;
        if (CallShapeOf(target) is not { } shape || shape.Result.IsVoid()) return true;
        if (shape.Parameters.Any(p => p.IsError())) return true;

        return ProbeLambdaResult(syntax, shape.Parameters) is not { } produced ||
               produced.IsError() ||
               ClassifyConversion(produced, shape.Result, explicitCast: false) is not null;
    }

    /// <summary>What a delegate or closure takes and returns, or null for any other type.</summary>
    private static (IReadOnlyList<TypeSymbol> Parameters, TypeSymbol Result)? CallShapeOf(TypeSymbol type) =>
        type switch
        {
            DelegateTypeSymbol wanted => (wanted.Signature.Select(p => p.Type).ToList(), wanted.ReturnType),
            ClosureTypeSymbol bound => (bound.Signature.Select(p => p.Type).ToList(), bound.ReturnType),
            _ => null,
        };

    /// <summary>
    /// C#'s better conversion from a lambda: between two delegates taking the
    /// same parameters, the one whose result the body produces, or converts to
    /// better, and one with a result over one without. Zero when that does not
    /// decide it.
    /// </summary>
    private int CompareLambdaResults(BoundLambda lambda, TypeSymbol first, TypeSymbol second)
    {
        if (lambda.Syntax.ReturnType is not null) return 0;
        if (CallShapeOf(first) is not { } one || CallShapeOf(second) is not { } other) return 0;
        if (!one.Parameters.SequenceEqual(other.Parameters)) return 0;
        if (ProbeLambdaResult(lambda.Syntax, one.Parameters) is not { } produced || produced.IsError())
            return 0;

        if (one.Result.IsVoid() != other.Result.IsVoid())
            return one.Result.IsVoid() ? -1 : 1;

        bool oneExact = one.Result.Equals(produced);
        bool otherExact = other.Result.Equals(produced);
        if (oneExact != otherExact) return oneExact ? 1 : -1;

        bool oneToOther = ClassifyConversion(one.Result, other.Result, explicitCast: false) is not null;
        bool otherToOne = ClassifyConversion(other.Result, one.Result, explicitCast: false) is not null;
        return oneToOther == otherToOne ? 0 : oneToOther ? 1 : -1;
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

        // A declaring `out` fits any `out` parameter whose type it did not
        // already name, which is what makes `out var` say nothing about which
        // overload was meant.
        if (argument is BoundOutDraft draft)
            return parameter.Mode == ParameterMode.Out &&
                   (draft.NeedsType || draft.Type.Equals(parameter.Type));

        bool given = argument is BoundAddressOf { FromRefKeyword: true };
        bool outward = argument is BoundAddressOf { FromOutKeyword: true };

        if (parameter.Mode == ParameterMode.Out)
            return outward &&
                   ((BoundAddressOf)argument).Operand.Type.Equals(parameter.Type);

        if (parameter.Mode == ParameterMode.Ref)
            return given &&
                   ((BoundAddressOf)argument).Operand.Type.Equals(parameter.Type);

        return !given && !outward && IsImplicitlyConvertible(argument, parameter.Type);
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
        bool outward = argument is BoundAddressOf { FromOutKeyword: true } or BoundOutDraft;

        if (parameter.Mode == ParameterMode.Out && !outward)
        {
            diagnostics.Error("SL0597", argument.Span,
                $"argument {index + 1} of '{name}' is 'out {parameter.Type.Name} " +
                $"{parameter.Name}', so the call must say so too: write 'out' before it, or " +
                "'out var' to declare the variable right there",
                parameter.Type);
            return;
        }

        if (parameter.Mode != ParameterMode.Out && outward)
        {
            diagnostics.Error("SL0598", argument.Span,
                $"argument {index + 1} of '{name}' is " +
                (parameter.Mode == ParameterMode.Ref
                    ? $"'ref {parameter.Type.Name} {parameter.Name}', which the caller has to " +
                      "have filled in already; write 'ref' rather than 'out'"
                    : $"'{parameter.Type.Name} {parameter.Name}', which is passed by value; " +
                      "drop the 'out'"),
                parameter.Type);
            return;
        }

        if (parameter.Mode == ParameterMode.Ref && !given)
        {
            diagnostics.Error("SL0445", argument.Span,
                $"argument {index + 1} of '{name}' is 'ref {parameter.Type.Name} " +
                $"{parameter.Name}', so the call must say so too: write " +
                "'ref' before it",
                parameter.Type);
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
                      "drop the 'ref'"),
                parameter.Type);
            return;
        }

        var actual = argument is BoundAddressOf { FromRefKeyword: true, Operand: { } inner }
            ? inner
            : argument;

        if (parameter.Mode is ParameterMode.Ref or ParameterMode.Out)
        {
            string word = parameter.Mode == ParameterMode.Out ? "out" : "ref";
            diagnostics.Error("SL0447", argument.Span,
                $"argument {index + 1} of '{name}' is '{word} {parameter.Type.Name}', and this " +
                $"is '{actual.Type.Name}'. It is not converted, because the callee writes back " +
                "through it and there would be nowhere for the result to go",
                parameter.Type, actual.Type);
            return;
        }

        ReportArgumentMismatch(name, index, argument, parameter.Type);
    }

    /// <summary>
    /// Whether one candidate could take these arguments, as declared or with
    /// its <c>params</c> parameter given element by element.
    /// </summary>
    private bool AcceptsArguments(
        FunctionSymbol candidate, List<BoundExpression> arguments,
        IReadOnlyList<ExpressionSyntax>? written = null) =>
        FormOf(candidate, arguments, written, out _) is not null;

    /// <summary>
    /// The parameters a call to <paramref name="candidate"/> fills: the ones
    /// declared, or -- when only that fits -- the expanded form, with one per
    /// element in place of the <c>params</c> array. Null when neither fits.
    ///
    /// The declared form is asked first and wins where both fit, as in C#:
    /// <c>F(values)</c> with an <c>int[]</c> passes the array rather than an
    /// array holding it.
    /// </summary>
    private List<ParameterSymbol>? FormOf(
        FunctionSymbol candidate, List<BoundExpression> arguments,
        IReadOnlyList<ExpressionSyntax>? written, out bool expanded)
    {
        expanded = false;

        var declared = candidate.Parameters.Where(p => !p.IsThis).ToList();
        if (Fits(candidate, declared, arguments, written)) return declared;

        if (ExpandedParameters(candidate, arguments.Count, written) is not { } elements ||
            !Fits(candidate, elements, arguments, written))
            return null;

        expanded = true;
        return elements;
    }

    /// <summary>
    /// The expanded form of a call to a function with a <c>params</c>
    /// parameter: the parameters before it, then one of the element type for
    /// each positional argument past them. Null when there is no such
    /// parameter, or when a name gives it -- a name passes the array whole.
    /// </summary>
    private static List<ParameterSymbol>? ExpandedParameters(
        FunctionSymbol candidate, int given, IReadOnlyList<ExpressionSyntax>? written)
    {
        var declared = candidate.Parameters.Where(p => !p.IsThis).ToList();
        if (declared.Count == 0 || declared[^1].ParamsElement is not { } element) return null;

        var gathered = declared[^1];
        if (written is not null &&
            written.Any(a => a is NamedArgumentSyntax named && named.Name == gathered.Name))
            return null;

        int fixedCount = declared.Count - 1;
        int elements = Math.Max(0, PositionalCount(given, written) - fixedCount);

        var expanded = declared.Take(fixedCount).ToList();

        // Named so that no argument can name one: an element is reached by
        // position or not at all.
        for (int i = 0; i < elements; i++)
            expanded.Add(new ParameterSymbol($"{gathered.Name}[{i}]", element, gathered.Index + i));

        return expanded;
    }

    /// <summary>How many arguments come before the first named one.</summary>
    private static int PositionalCount(int given, IReadOnlyList<ExpressionSyntax>? written) =>
        written is null ? given : written.TakeWhile(a => a is not NamedArgumentSyntax).Count();

    /// <summary>
    /// Rewrites a call that uses the expanded form of a <c>params</c> parameter
    /// into one that passes the array, as a <see cref="BoundParamsArray"/>.
    /// Answers the written arguments to go with the new list; a call in the
    /// declared form is left as it was.
    /// </summary>
    private IReadOnlyList<ExpressionSyntax>? GatherParams(
        FunctionSymbol function, ref List<BoundExpression> arguments,
        IReadOnlyList<ExpressionSyntax>? written, SourceSpan callSpan)
    {
        if (FormOf(function, arguments, written, out bool expanded) is null || !expanded)
            return written;

        var declared = function.Parameters.Where(p => !p.IsThis).ToList();
        var gathered = declared[^1];
        var element = gathered.ParamsElement!;

        int fixedCount = declared.Count - 1;
        int positional = PositionalCount(arguments.Count, written);
        int count = Math.Max(0, positional - fixedCount);
        int at = Math.Min(positional, fixedCount);

        var elements = arguments.GetRange(at, count);
        var span = count == 0 ? callSpan : SourceSpan.Merge(elements[0].Span, elements[^1].Span);

        var items = elements.Select(e => BindConversion(e, element, e.Span)).ToList();
        bool viewed = gathered.Type is SliceTypeSymbol;
        var packed = new BoundParamsArray(span, gathered.Type,
            viewed ? ArrayOf(element) : (ArrayTypeSymbol)gathered.Type, items)
        {
            InFrame = viewed,
        };

        var rewritten = new List<BoundExpression>(arguments);
        rewritten.RemoveRange(at, count);

        var syntax = new ArrayLiteralSyntax(span,
            written is null ? [] : written.Skip(at).Take(count).ToList());

        // Short of the parameters before it, the array cannot be positional:
        // it would land on one of them. With no names written the ones missing
        // are defaults, filled here; with names, the array takes one too.
        if (positional < fixedCount && !HasNames(written))
        {
            for (int p = positional; p < fixedCount; p++)
                rewritten.Add(EnsureDefault(function, declared[p]) ?? new BoundErrorExpression(callSpan));

            rewritten.Add(packed);
            arguments = rewritten;
            return null;
        }

        rewritten.Insert(at, packed);
        arguments = rewritten;

        if (written is null) return null;

        var result = new List<ExpressionSyntax>(written);
        result.RemoveRange(at, count);
        result.Insert(at, positional < fixedCount
            ? new NamedArgumentSyntax(span, gathered.Name, span, syntax)
            : syntax);
        return result;
    }

    /// <summary>
    /// Whether one form of a candidate takes these arguments: the count, the
    /// names, and each argument against the parameter it lands on.
    /// </summary>
    private bool Fits(
        FunctionSymbol candidate, List<ParameterSymbol> parameters,
        List<BoundExpression> arguments, IReadOnlyList<ExpressionSyntax>? written)
    {
        int required = parameters.Count(p => !p.IsOptional);

        if (candidate.IsVariadic
                ? arguments.Count < parameters.Count
                : arguments.Count < required || arguments.Count > parameters.Count)
            return false;

        // A name may put the arguments in a different order for this candidate
        // than for the last one, and a default may fill a different hole, so
        // the mapping is worked out per candidate rather than once.
        int[]? map = MapArguments(
            parameters, arguments.Count, written, candidate.IsVariadic, out _);

        if (map is null) return false;

        for (int i = 0; i < parameters.Count; i++)
            if (map[i] >= 0 && !ArgumentFits(arguments[map[i]], parameters[i]))
                return false;

        return true;
    }

    /// <summary>
    /// Refuses <c>name: value</c> where the thing being called has no declared
    /// parameter names to match it against.
    ///
    /// A variant case's fields have names, but the call is a construction and
    /// takes them in order; a delegate and a closure carry a signature rather
    /// than a declaration. Saying so is better than accepting the name and
    /// quietly using the position.
    /// </summary>
    private void RefuseNamesWithoutParameters(CallSyntax syntax)
    {
        if (!HasNames(syntax.Arguments)) return;

        string? kind = syntax.Callee switch
        {
            BaseSyntax => "a base constructor call",
            ThisSyntax => "a call to another constructor",
            _ => null,
        };

        if (kind is null) return;

        diagnostics.Error("SL0602", syntax.Span,
            $"{kind} takes its arguments in order, so a name has nothing here to match");
    }

    /// <summary>Whether any argument was written <c>name: value</c>.</summary>
    private static bool HasNames(IReadOnlyList<ExpressionSyntax>? written) =>
        written is not null && written.Any(a => a is NamedArgumentSyntax);

    /// <summary>
    /// Whether this many arguments could fill these parameters at all.
    ///
    /// A range rather than a number, now that a parameter may have a default:
    /// what a call must supply is the ones that have none, and those are the
    /// front of the list.
    /// </summary>
    private bool CheckArity(
        string name, IReadOnlyList<ParameterSymbol> parameters, int given, bool isVariadic,
        SourceSpan span)
    {
        int total = parameters.Count;
        int required = parameters.Count(p => !p.IsOptional);

        if (isVariadic ? given >= total : given >= required && given <= total) return true;

        string wanted = isVariadic
            ? $"{total} or more arguments"
            : required == total
                ? Counted(total, "argument")
                : $"{required} to {total} arguments";

        diagnostics.Error("SL0260", span, $"'{name}' takes {wanted}, but {Given(given)}");
        return false;
    }

    /// <summary>
    /// Which argument fills each parameter, with -1 where the parameter's own
    /// default fills it. Null when the call cannot be made to fit.
    ///
    /// Positional arguments fill from the left, and each named one goes to the
    /// parameter it names. The result is indexed by parameter, so a caller
    /// permutes with it rather than reasoning about the order itself.
    /// </summary>
    private static int[]? MapArguments(
        IReadOnlyList<ParameterSymbol> parameters,
        int given,
        IReadOnlyList<ExpressionSyntax>? written,
        bool isVariadic,
        out string? why)
    {
        why = null;

        var order = new int[parameters.Count];
        Array.Fill(order, -1);

        // Nothing named: they fill from the left, and whatever is past the end
        // is a C variadic's.
        if (!HasNames(written))
        {
            if (given > parameters.Count && !isVariadic) return null;

            for (int i = 0; i < given && i < parameters.Count; i++) order[i] = i;
            return Complete(parameters, order, out why) ? order : null;
        }

        bool naming = false;

        for (int i = 0; i < written!.Count; i++)
        {
            if (written[i] is not NamedArgumentSyntax named)
            {
                // A positional argument after a named one would leave a reader
                // counting past the names to see where it lands.
                if (naming)
                {
                    why = "a positional argument cannot come after a named one";
                    return null;
                }

                if (i >= parameters.Count)
                {
                    why = isVariadic
                        ? "the arguments a '...' takes are positional, so none may be named"
                        : "it is given more arguments than it has parameters";
                    return null;
                }

                order[i] = i;
                continue;
            }

            naming = true;

            int at = -1;
            for (int p = 0; p < parameters.Count; p++)
                if (parameters[p].Name == named.Name) { at = p; break; }

            if (at < 0)
            {
                why = $"there is no parameter named '{named.Name}'";
                return null;
            }

            if (order[at] >= 0)
            {
                why = $"'{named.Name}' is given twice";
                return null;
            }

            order[at] = i;
        }

        return Complete(parameters, order, out why) ? order : null;
    }

    /// <summary>
    /// Whether every parameter is accounted for: either something was given
    /// for it, or it has a default to fall back on.
    /// </summary>
    private static bool Complete(
        IReadOnlyList<ParameterSymbol> parameters, int[] order, out string? why)
    {
        why = null;

        for (int p = 0; p < parameters.Count; p++)
            if (order[p] < 0 && !parameters[p].IsOptional)
            {
                why = $"nothing was given for '{parameters[p].Name}'";
                return false;
            }

        return true;
    }

    /// <summary>
    /// The arguments in declared order, each with the span to report against,
    /// and every parameter the call left out filled in from its default.
    ///
    /// The default expression is shared between every call site that omitted
    /// it. That is sound because it is a constant -- which is the whole reason
    /// a default must be one.
    /// </summary>
    private (List<BoundExpression> Arguments, List<SourceSpan> Spans) Arrange(
        FunctionSymbol function,
        IReadOnlyList<ParameterSymbol> parameters,
        List<BoundExpression> arguments,
        IReadOnlyList<ExpressionSyntax>? written,
        int[] map,
        SourceSpan callSpan)
    {
        var values = new List<BoundExpression>(map.Length);
        var spans = new List<SourceSpan>(map.Length);

        for (int p = 0; p < map.Length; p++)
        {
            if (map[p] < 0)
            {
                values.Add(EnsureDefault(function, parameters[p])
                           ?? new BoundErrorExpression(callSpan));
                spans.Add(callSpan);
                continue;
            }

            values.Add(arguments[map[p]]);
            spans.Add(written is not null && map[p] < written.Count
                ? written[map[p]].Span
                : arguments[map[p]].Span);
        }

        // Anything past the declared parameters is a C variadic's, and those
        // are positional by construction.
        for (int i = parameters.Count; i < arguments.Count; i++)
        {
            values.Add(arguments[i]);
            spans.Add(written is not null && i < written.Count ? written[i].Span : arguments[i].Span);
        }

        return (values, spans);
    }

    private FunctionSymbol? ResolveOverload(
        IReadOnlyList<FunctionSymbol> candidates, List<BoundExpression> arguments, SourceSpan span, string name,
        IReadOnlyList<ExpressionSyntax>? written = null)
    {
        // An argument that did not bind has already been reported, and it
        // matches every overload and none: saying the call is ambiguous on top
        // of that is a second message about the first one's consequence, and
        // it is the one printed first.
        //
        // The test is the node and not its type, because a draft -- `out var
        // x`, an array literal, `Ok(v)` -- carries an error type precisely
        // while it waits to be told what it is, and refusing to resolve is how
        // it would never be told.
        if (arguments.Any(a => a is BoundErrorExpression)) return null;

        var viable = candidates.Where(c => AcceptsArguments(c, arguments, written)).ToList();

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

                    // Against the elements, where the call was plainly giving
                    // them one by one: "expects 'int[]'" of a lone argument
                    // would be true and no help.
                    if (ExpandedParameters(only, arguments.Count, written) is { } expanded &&
                        (arguments.Count != parameters.Count ||
                         !ArgumentFits(arguments[^1], parameters[^1])))
                        parameters = expanded;

                    // A name that does not fit is the whole story; reporting a
                    // type mismatch on top of it would be reporting the
                    // consequence rather than the cause.
                    int[]? map = MapArguments(
                        parameters, arguments.Count, written, only.IsVariadic, out string? why);

                    if (map is null && why is not null && HasNames(written))
                    {
                        diagnostics.Error("SL0601", span,
                            $"the call to '{name}' does not fit: {why}");
                        return null;
                    }

                    int reported = diagnostics.ErrorCount;

                    if (CheckArity(name, parameters, arguments.Count, only.IsVariadic, span))
                        for (int i = 0; i < parameters.Count; i++)
                            if (map is not null && map[i] >= 0 &&
                                !ArgumentFits(arguments[map[i]], parameters[i]))
                                ReportArgumentMode(name, i, arguments[map[i]], parameters[i]);

                    // The call is refused either way, so it MUST say why -- unless a
                    // parameter's type did not resolve, which was said where it was
                    // written.
                    if (diagnostics.ErrorCount == reported && !diagnostics.IsMuted &&
                        !parameters.Any(p => p.Type.IsError()))
                        diagnostics.Error("SL0263", span,
                            $"no overload of '{name}' accepts these {arguments.Count} argument(s)");
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

                if (Best(viable, arguments, written) is { } best) return best;

                diagnostics.Error("SL0264", span, $"the call to '{name}' is ambiguous");
                return null;
        }
    }

    /// <summary>
    /// The one candidate whose every argument converts at least as well as it
    /// does for each of the others, and one of them better -- or null when
    /// there is no such candidate.
    ///
    /// C#'s rule, and for the reason C# has it. Without it only an exact match
    /// could win, so `Text.FromInteger` of a `byte`, a `uint` or an integer
    /// literal was ambiguous between its `long`, `ulong` and `nuint` overloads
    /// on every target: each widens to all three, and "fits several" was
    /// treated as "fits several equally". A `byte` fits a `long` better than a
    /// `ulong`, and saying so is what the spec's "equally" already implied.
    /// </summary>
    private FunctionSymbol? Best(
        List<FunctionSymbol> viable, List<BoundExpression> arguments,
        IReadOnlyList<ExpressionSyntax>? written)
    {
        var expanded = new bool[viable.Count];
        var shapes = viable
            .Select((c, i) => ParameterTypesByArgument(c, arguments, written, out expanded[i]))
            .ToList();

        // C#'s last word on a tie: where every argument converts as well either
        // way, the candidate taken as declared beats one that had to be given
        // its elements one by one.
        bool Beats(int i, int j) =>
            IsBetter(shapes[i], shapes[j], arguments) ||
            (!expanded[i] && expanded[j] && !IsBetter(shapes[j], shapes[i], arguments));

        var winners = viable
            .Where((_, i) => Enumerable.Range(0, viable.Count).All(j => j == i || Beats(i, j)))
            .ToList();

        return winners.Count == 1 ? winners[0] : null;
    }

    /// <summary>
    /// The parameter type each argument lands on for one candidate, in the
    /// form that takes them, or null past the declared parameters, where a C
    /// variadic's arguments go.
    /// </summary>
    private TypeSymbol?[] ParameterTypesByArgument(
        FunctionSymbol candidate, List<BoundExpression> arguments,
        IReadOnlyList<ExpressionSyntax>? written, out bool expanded)
    {
        int count = arguments.Count;
        var parameters = FormOf(candidate, arguments, written, out expanded)
                         ?? candidate.Parameters.Where(p => !p.IsThis).ToList();
        var types = new TypeSymbol?[count];
        int[]? map = MapArguments(parameters, count, written, candidate.IsVariadic, out _);
        if (map is null) return types;

        for (int p = 0; p < parameters.Count; p++)
            if (map[p] >= 0)
                types[map[p]] = parameters[p].Type;

        return types;
    }

    /// <summary>No argument converts worse to <paramref name="first"/>, and one converts better.</summary>
    private bool IsBetter(TypeSymbol?[] first, TypeSymbol?[] second, List<BoundExpression> arguments)
    {
        bool better = false;

        for (int i = 0; i < arguments.Count; i++)
        {
            int comparison = CompareConversions(arguments[i], first[i], second[i]);
            if (comparison < 0) return false;
            if (comparison > 0) better = true;
        }

        return better;
    }

    /// <summary>
    /// Positive when <paramref name="argument"/> converts better to
    /// <paramref name="first"/> than to <paramref name="second"/>, negative for
    /// the reverse, and zero when neither is better.
    ///
    /// Identity is best. Otherwise the target that converts to the other and
    /// not back is the more specific, as <c>long</c> is to <c>double</c> and a
    /// derived class is to its base. Two integers neither of which holds the
    /// other are settled towards the signed one, as C# settles them: a
    /// <c>uint</c> reaching <c>long</c> or <c>ulong</c> keeps its value
    /// either way, and the signed type is the one arithmetic expects.
    /// </summary>
    private int CompareConversions(BoundExpression argument, TypeSymbol? first, TypeSymbol? second)
    {
        if (first is null || second is null || first.Equals(second)) return 0;

        // A draft waiting to be told its type, or an argument already reported,
        // has no conversion to rank.
        if (argument.Type.IsError()) return 0;

        if (argument.Type.Equals(first)) return 1;
        if (argument.Type.Equals(second)) return -1;

        if (argument is BoundLambda lambda && CompareLambdaResults(lambda, first, second) is not 0 and var byResult)
            return byResult;

        // An array literal is an array first, as C# prefers a span or an
        // array to a type it would have to call `Add` on.
        if (argument is BoundArrayDraft)
        {
            bool firstIsArray = first is ArrayTypeSymbol or SliceTypeSymbol or FixedArrayTypeSymbol;
            bool secondIsArray = second is ArrayTypeSymbol or SliceTypeSymbol or FixedArrayTypeSymbol;
            if (firstIsArray != secondIsArray)
                return firstIsArray ? 1 : -1;
        }

        bool firstToSecond = ClassifyConversion(first, second, explicitCast: false) is not null;
        bool secondToFirst = ClassifyConversion(second, first, explicitCast: false) is not null;
        if (firstToSecond != secondToFirst) return firstToSecond ? 1 : -1;

        if (first is PrimitiveTypeSymbol { IsInteger: true, IsCodeUnit: false } a &&
            second is PrimitiveTypeSymbol { IsInteger: true, IsCodeUnit: false } b &&
            a.IsSigned != b.IsSigned)
        {
            var (signed, unsigned) = a.IsSigned ? (a, b) : (b, a);
            if (unsigned.Size >= signed.Size) return a.IsSigned ? 1 : -1;
        }

        return 0;
    }
}
