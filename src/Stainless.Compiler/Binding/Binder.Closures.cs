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
/// Lambdas: what a body can see of the scope it was written in, and the
/// class that gets generated to carry it.
/// </summary>
public sealed partial class Binder
{
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

        /// <summary>
        /// Whether a captured <c>this</c> is held weakly: true for a lambda
        /// that is the handler of a <c>+=</c>, so that it cannot keep alive
        /// the object that subscribed it.
        /// </summary>
        public bool WeakThis { get; init; }

        /// <summary>A <c>static</c> lambda, which may capture nothing.</summary>
        public bool IsStatic { get; init; }

        /// <summary>
        /// The local the body reads a weakly captured <c>this</c> through,
        /// loaded once at the top; null until something captures it.
        /// </summary>
        public LocalSymbol? WeakSelf { get; set; }

        public FieldSymbol? WeakSelfField { get; set; }
    }

    private int _closureCount;

    // ============================== a captured member that something changes

    /// <summary>
    /// Every member a lambda captured by reading it, and where.
    ///
    /// <para>
    /// A member read inside a lambda is captured <i>by value</i>, the same as a
    /// local (spec §2.15): the closure holds what the member said when it was
    /// made, not a route back to the object. That is the language's rule and it
    /// is the right one -- a closure may outlive the object, and by-value
    /// capture is what means there is no lifetime question to answer.
    /// </para>
    ///
    /// <para>
    /// It is also the one capture rule that looks like the opposite of itself.
    /// <c>if (busy)</c> inside a handler is a line nobody reads twice, and it
    /// means "if the flag was set when this handler was connected" -- which is
    /// almost always no. So where a captured member is <i>also written</i>
    /// somewhere, the reader is warned that the two are not connected.
    /// </para>
    ///
    /// <para>
    /// <b>Naming the receiver is the fix, on a class.</b> <c>this.busy</c>
    /// captures <c>this</c> by the same by-value rule -- but the value of a
    /// class <c>this</c> is a counted reference, so the copy still names the
    /// one object and reading through it is live. A method call does the same
    /// thing for the same reason. Only the bare name copies, because only a
    /// bare name resolved to a read in the enclosing scope rather than to a
    /// member of something the closure holds.
    /// </para>
    ///
    /// <para>
    /// <b>On a struct there is no such fix</b>, because <c>this</c> there is
    /// the struct and copying it copies the value. Both spellings are stale
    /// and the warning says so rather than naming a cure that is not one.
    /// </para>
    /// </summary>
    private readonly List<(object Member, string Name, NamedTypeSymbol Owner, SourceSpan Span)>
        _memberCaptures = [];

    /// <summary>
    /// Every field and property assigned outside a constructor.
    ///
    /// <b>Outside</b>, because a member a constructor sets and nothing else
    /// changes cannot surprise a closure: whatever it captured is what the
    /// member will say for ever. Warning about those would put the diagnostic
    /// on almost every capture there is, and a warning that fires on the
    /// ordinary case is one people learn to pass over.
    /// </summary>
    private readonly HashSet<object> _membersWritten = [];

    /// <summary>
    /// The fields each property's getter reads.
    ///
    /// <para>
    /// Capturing <c>Busy</c> is exactly as stale as capturing <c>_busy</c>, but
    /// the two are different symbols: the capture is recorded against the
    /// property and the write against the field, so matching one list against
    /// the other found nothing. A <c>bool Busy => _busy;</c> guard read bare
    /// inside a handler is therefore frozen at whatever it said when the
    /// handler was connected, and nothing said so.
    /// </para>
    ///
    /// <para>
    /// This is not a hypothetical. Every <c>Echoing</c> guard in the GTK backend
    /// was written as a method and called as one, precisely so that it would be
    /// live; turning them into properties turned the call sites into bare reads
    /// and every guard stopped guarding. One of them recursed until the stack
    /// ran out. The warning that exists to catch this missed all ten, and this
    /// map is what closes the gap.
    /// </para>
    ///
    /// <para>
    /// A getter this cannot read through -- one that calls out to C, or reads a
    /// field of something else -- contributes nothing, so the warning is missed
    /// rather than invented. That is the right direction to fail in.
    /// </para>
    /// </summary>
    private readonly Dictionary<PropertySymbol, HashSet<FieldSymbol>> _propertyReads = [];

    /// <summary>
    /// Remembers what a property getter read, once its body is bound.
    /// </summary>
    private void NoteGetterReads(FunctionSymbol function, BoundStatement body)
    {
        if (function.Accessor is not { } property) return;
        if (!ReferenceEquals(property.Getter, function)) return;

        var fields = new HashSet<FieldSymbol>();
        new FieldReadCollector(fields).Visit(body);
        if (fields.Count > 0) _propertyReads[property] = fields;
    }

    /// <summary>
    /// Remembers that a member was written, for the check at the end of
    /// binding. Called from every place an assignment is bound.
    ///
    /// <para>
    /// A write <i>inside</i> a lambda needs no test here and gets none: the
    /// name resolved to the closure's own field on the way in, so the symbol
    /// recorded is the copy's and never matches the member's. That is the
    /// same thing the warning is about, seen from the other side.
    /// </para>
    /// </summary>
    private void NoteMemberWritten(BoundExpression target)
    {
        if (_context.Function?.Kind is FunctionKind.Constructor) return;

        switch (target)
        {
            case BoundFieldAccess field: Remember(_membersWritten, field.Field); break;
            case BoundCall { Function.Accessor: { } property }:
                Remember(_membersWritten, property);
                break;
        }
    }

    /// <summary>Remembers a property written through its setter.</summary>
    private void NoteMemberWritten(PropertySymbol property)
    {
        if (_context.Function?.Kind is FunctionKind.Constructor) return;
        Remember(_membersWritten, property);
    }

    /// <summary>
    /// Warns about every captured member that something goes on to change.
    ///
    /// Run once, after every body is bound, because neither half of the
    /// question is answerable before then: a member may be captured in one
    /// file and written in another, and the write may be in a method declared
    /// after the lambda that reads it.
    /// </summary>
    /// <summary>
    /// Whether what a capture holds can go on to say something else: the member
    /// itself was assigned, or -- for a property -- a field its getter reads
    /// was.
    /// </summary>
    private bool IsChanged(object member, out string? through)
    {
        through = null;
        if (_membersWritten.Contains(member)) return true;

        if (member is not PropertySymbol property) return false;
        if (!_propertyReads.TryGetValue(property, out var fields)) return false;

        // Named, because "the property is assigned elsewhere" would not be true
        // -- the property may have no setter at all -- and a reader sent to look
        // for an assignment that is not there stops believing the warning.
        var written = fields.FirstOrDefault(_membersWritten.Contains);
        if (written is null) return false;

        through = written.Name;
        return true;
    }

    private void ReportCapturedMembersThatChange()
    {
        foreach (var (member, name, owner, span) in _memberCaptures)
        {
            if (!IsChanged(member, out string? through)) continue;

            // **The fix differs by what `this` is.** A class reference copied
            // into the closure still names the one object, so reading through
            // it is live. A struct `this` is the struct, copied -- so there is
            // no spelling that reads the original, and saying otherwise would
            // send a reader after something that does not exist.
            string advice = owner is ClassTypeSymbol
                ? $"Write 'this.{name}' if it should see the current value, which captures " +
                  "the object and reads through it; assign it to a local first if it should not"
                : $"'{owner.Name}' is a struct, so a lambda inside it captures a copy of the " +
                  "whole value and 'this." + name + "' copies too -- pass what the lambda " +
                  "needs as a parameter, or make it a method on the struct";

            string changes = through is null
                ? $"'{owner.Name}.{name}' is assigned elsewhere"
                : $"'{owner.Name}.{name}' reads '{through}', which is assigned elsewhere";

            diagnostics.Warning("SL0610", span,
                $"this lambda captures '{name}' by value, and {changes} -- so it will keep " +
                "reading what it said here, not what it says when the lambda runs. " +
                advice);
        }
    }

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
        _context.Closures.Count == 0 ? null : CaptureFrom(_context.Closures.Count - 1, name, span);

    private BoundExpression? CaptureFrom(int index, string name, SourceSpan span, bool variablesOnly = false)
    {
        var closure = _context.Closures[index];

        if (closure.Captured.TryGetValue(name, out var already))
            return new BoundFieldAccess(
                span, new BoundThis(span, closure.Type!, closure.This!), already);

        var outer = ResolveOutside(index, name, span, variablesOnly);
        if (outer is null) return null;

        if (closure.IsStatic)
        {
            ReportStaticCapture(name, span);
            return new BoundErrorExpression(span);
        }

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
        AddCapture(closure, name, field, outer);

        if (VariableOf(outer) is { } origin) Remember(_captureOrigins, field, origin);

        return new BoundFieldAccess(span, new BoundThis(span, closure.Type, closure.This!), field);
    }

    /// <summary>The variable an expression reads, when it reads one directly.</summary>
    private object? VariableOf(BoundExpression expression) => expression switch
    {
        BoundLocalAccess local => local.Local,
        BoundParameterAccess parameter => OriginOf(parameter.Parameter),
        BoundFieldAccess field => _captureOrigins.GetValueOrDefault(field.Field),
        _ => null,
    };

    /// <summary>Reads a name in the context the closure at <paramref name="index"/> was written in.</summary>
    private BoundExpression? ResolveOutside(int index, string name, SourceSpan span, bool variablesOnly = false)
    {
        var closure = _context.Closures[index];

        for (int i = closure.OuterScopes.Count - 1; i >= 0; i--)
            if (closure.OuterScopes[i].TryGetValue(name, out var local))
                return new BoundLocalAccess(span, local);

        if (closure.OuterFunction?.Parameters.FirstOrDefault(p => p.Name == name && !p.IsThis)
            is { } parameter)
            return new BoundParameterAccess(span, parameter);

        // A lambda inside a local function reaches past it the way the local
        // function itself does: through what every call passes it.
        if (closure.OuterFunction is { } outerFunction &&
            _localFunctionOf.GetValueOrDefault(outerFunction) is { } local2 &&
            (outerFunction.Captures.Any(c => c.Name == name) ||
             local2.Visible?.ContainsKey(name) == true))
            return CaptureInto(local2, outerFunction, name, span) is { } hidden
                ? new BoundParameterAccess(span, hidden)
                : new BoundErrorExpression(span);

        // The lambda that encloses this one may be able to reach it.
        if (index > 0) return CaptureFrom(index - 1, name, span, variablesOnly);

        if (variablesOnly) return null;

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
        {
            _memberCaptures.Add((property, name, owner, span));
            return BindPropertyRead(span, receiver, property);
        }

        if (owner.FindField(name) is not { } field)
        {
            // A primary constructor parameter is the object's, as a field is.
            return owner.PrimaryCaptures.TryGetValue(name, out var kept)
                ? new BoundFieldAccess(span, receiver, kept)
                : null;
        }

        _memberCaptures.Add((field, name, owner, span));
        return new BoundFieldAccess(span, receiver, field);
    }

    /// <summary>
    /// A method of the type the outermost lambda was written inside, which a
    /// bare call in a lambda body may mean.
    /// </summary>
    private List<FunctionSymbol> MethodsOfEnclosingThis(string name) =>
        _context.Closures.Count == 0
            ? []
            : _context.Closures[0].OuterFunction?.ContainingType?.FindMethods(name).ToList() ?? [];

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
        var closure = _context.Closures[index];

        if (closure.WeakSelf is { } alive)
            return ReadWeakSelf(span, alive);

        if (closure.Captured.TryGetValue(ThisCaptureName, out var already))
            return new BoundFieldAccess(
                span, new BoundThis(span, closure.Type!, closure.This!), already);

        var outer = index > 0 ? CaptureThis(index - 1, span) : EnclosingThis(closure, span);

        if (outer is null && index == 0 && TryGiveLocalFunctionThis(closure.OuterFunction, span))
            return new BoundErrorExpression(span);

        if (outer is null)
        {
            diagnostics.Error("SL0228", span,
                "'this' is only valid inside a method, constructor or destructor");
            return new BoundErrorExpression(span);
        }

        if (outer.Type.IsError()) return new BoundErrorExpression(span);

        if (closure.IsStatic)
        {
            ReportStaticCapture("this", span);
            return new BoundErrorExpression(span);
        }

        if (closure.Type is null)
        {
            diagnostics.Error("SL0381", span,
                "this lambda reads 'this' from around it, so it cannot become a delegate; " +
                "a delegate is a bare function pointer with nowhere to keep what was " +
                "captured. Convert it to a single-method interface instead");
            return new BoundErrorExpression(span);
        }

        // A subscribed lambda holds the object weakly, and the body reads it
        // through a local loaded once at the top, which ends the call early
        // when the object has gone. See BindLambdaAsMethodPointer.
        if (closure.WeakThis && outer.Type is NamedTypeSymbol { IsReferenceType: true } referenced)
        {
            var weakField = new FieldSymbol(
                ThisCaptureName, referenced.MakeWeakType(), closure.Type,
                closure.Type.Fields.Count);
            AddCapture(closure, ThisCaptureName, weakField, new BoundConversion(
                span, weakField.Type, outer, ConversionKind.ReferenceToWeak));

            closure.WeakSelfField = weakField;
            closure.WeakSelf = new LocalSymbol(WeakSelfName, referenced.MakeOptionalType(),
                isConst: false);
            return ReadWeakSelf(span, closure.WeakSelf);
        }

        var field = new FieldSymbol(
            ThisCaptureName, outer.Type, closure.Type, closure.Type.Fields.Count);
        AddCapture(closure, ThisCaptureName, field, outer);

        return new BoundFieldAccess(span, new BoundThis(span, closure.Type, closure.This!), field);
    }

    /// <summary>
    /// A field of the closure holding what <paramref name="value"/> read where
    /// the lambda was made. A discarded trial takes it back.
    /// </summary>
    private void AddCapture(
        ClosureContext closure, string name, FieldSymbol field, BoundExpression value)
    {
        var fields = closure.Type!.Fields;
        fields.Add(field);
        closure.Captured[name] = field;
        closure.Captures.Add((field, value));

        UndoOnDiscard(() =>
        {
            fields.Remove(field);
            closure.Captured.Remove(name);
            closure.Captures.RemoveAll(c => c.Field == field);
        });
    }

    private void ReportStaticCapture(string name, SourceSpan span) =>
        diagnostics.Error("SL0764", span,
            $"this lambda is 'static', so it cannot read '{name}' from around it; a static " +
            "lambda captures nothing. Pass it in as a parameter, or drop 'static'");

    /// <summary>
    /// The local a weakly captured <c>this</c> is read through, as the class
    /// it names. The body runs only once the prologue has checked it.
    /// </summary>
    private static BoundExpression ReadWeakSelf(SourceSpan span, LocalSymbol alive) =>
        new BoundConversion(span, ((OptionalTypeSymbol)alive.Type).Element,
            new BoundLocalAccess(span, alive), ConversionKind.PointerCast);

    /// <summary>
    /// The local a weakly captured <c>this</c> lands in. No source identifier
    /// can be this, for the reason <see cref="ThisCaptureName"/> gives.
    /// </summary>
    private const string WeakSelfName = "this?";

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

        if (target is DelegateTypeSymbol && lambda.LocalFunction is { } named)
        {
            diagnostics.Error("SL0381", span,
                $"'{named}' reads variables of the function around it, or its object, so it " +
                "cannot become a delegate; a delegate is a bare function pointer with nowhere " +
                "to keep them. Convert it to a closure instead");
            return new BoundErrorExpression(span);
        }

        if (target is ClosureTypeSymbol asMethodPointer)
            return BindLambdaAsMethodPointer(syntax, asMethodPointer, span);

        if (target is DelegateTypeSymbol asDelegate)
            return BindLambdaAsFunction(syntax, asDelegate, span);

        if (target is InterfaceTypeSymbol asInterface && SingleMethodOf(asInterface) is { } method)
            return BindLambdaAsClosure(syntax, asInterface, method, span);

        diagnostics.Error("SL0382", span,
            $"a lambda becomes a delegate or an interface with exactly one method, " +
            $"and '{target.Name}' is neither",
            target);
        return new BoundErrorExpression(span);
    }

    /// <summary>The lone method of a functional interface, or null if it is not one.</summary>
    private static FunctionSymbol? SingleMethodOf(InterfaceTypeSymbol type) =>
        type.Methods.Count == 1 && type.Interfaces.Count == 0 ? type.Methods[0] : null;

    /// <summary>
    /// What a lambda's body would produce, given types for its parameters --
    /// asked before anything has settled what the lambda is going to become.
    ///
    /// This exists for one case, and it is the case that makes `Select` writable:
    /// a type parameter that appears nowhere but in the result of a lambda.
    /// `Select&lt;T, R&gt;(T[:], IFunc&lt;T, R&gt;)` can work out T from the array, and then
    /// nothing else mentions R -- so R has to come from the body, and the body
    /// cannot be bound until T has given it its parameter types. That ordering
    /// is the whole of the trick.
    ///
    /// It is a trial, and a kept one: the answer may be a type the body
    /// instantiated, so what the body instantiated stays unless a trial around
    /// this one is discarded. Diagnostics are muted, because a failure here
    /// means "this candidate does not fit" rather than "this program is wrong",
    /// and the real bind will report properly if there is anything to report.
    /// The closure class and functions the body generated are taken back
    /// whatever happens, since the real bind makes its own.
    ///
    /// Returns null when the answer cannot be had: a block body, whose result
    /// is whatever its `return`s agree on and which needs a declared return
    /// type to bind at all, and anything that fails to bind. With
    /// <paramref name="report"/>, what fails to bind is reported.
    /// </summary>
    private TypeSymbol? ProbeLambdaResult(
        LambdaSyntax syntax, IReadOnlyList<TypeSymbol> parameterTypes, bool allowVoid = false,
        bool report = false)
    {
        if (syntax.Parameters.Count != parameterTypes.Count) return null;

        // Written out, it is the answer, and nothing needs binding to learn it.
        if (syntax.ReturnType is not null)
        {
            var written = ResolveTypeQuietly(syntax.ReturnType, _context.File!, allowVoid: true);
            return written.IsError() || (written.IsVoid() && !allowVoid) ? null : written;
        }

        int classes = _classes.Count;
        int functions = _functions.Count;
        int closureCount = _closureCount;
        int memberCaptures = _memberCaptures.Count;

        // A throwaway class to be the closure, so that a body reading something
        // from around it captures into this rather than being told it cannot
        // become a delegate. It is never added to _classes and never laid out;
        // it exists so the capture path has somewhere to put a field.
        var probeType = new ClassTypeSymbol
        {
            SimpleName = $"Probe.{_closureCount++}",
            ModuleName = _currentModule!.Name,
            Span = syntax.Span,
        };

        var probe = new FunctionSymbol
        {
            Name = "Apply",
            ModuleName = probeType.ModuleName,
            ReturnType = PrimitiveTypeSymbol.Void,
            Linkage = LinkageKind.Stainless,
            Kind = FunctionKind.Method,
            ContainingType = probeType,
            IsPublic = false,
            Span = syntax.Span,
            Scope = _context.File,
        };

        var self = new ParameterSymbol("this", probeType, 0) { IsThis = true };
        probe.Parameters.Add(self);

        for (int i = 0; i < syntax.Parameters.Count; i++)
            probe.Parameters.Add(
                new ParameterSymbol(syntax.Parameters[i].Name, parameterTypes[i], i + 1));

        var context = new ClosureContext
        {
            Type = probeType,
            This = self,
            OuterScopes = [.. _context.Locals],
            OuterFunction = _context.Function,
            IsStatic = syntax.IsStatic,
        };

        var body = _context.ForBody(probe);
        body.Closures.Add(context);
        body.InferringReturnsOf = probe;

        // Kept, because the answer may name a type the body instantiated.
        using var trial = BeginTrial(quiet: !report);

        TypeSymbol? produced;
        using (Enter(body))
        {
            PushScope();

            if (syntax.Block is not null)
            {
                BindBlock(syntax.Block);
                produced = AgreedReturnType(_context.ReturnsFound);
            }
            else
            {
                var value = BindExpression(syntax.Expression!);
                produced = value.Type.IsError() || IsTargetTyped(value) ? null
                    : value is BoundLambda inner ? NaturalClosureType(inner.Syntax)
                    : value.Type;
            }

            if (produced is not null && produced.IsVoid() && !allowVoid) produced = null;

            // A lambda has no type until something gives it one, so it cannot
            // be what a type parameter is inferred to be.
            if (produced is LambdaType) produced = null;

            PopScope();
        }

        // The closure it built is a throwaway, and what the body captured is
        // captured again by the bind that keeps it.
        DiscardGenerated(classes, functions);
        _closureCount = closureCount;
        _memberCaptures.RemoveRange(memberCaptures, _memberCaptures.Count - memberCaptures);

        trial.Accept();
        return produced;
    }

    /// <summary>
    /// The type a lambda has when nothing else says what it should be.
    ///
    /// <para>
    /// A lambda is ordinarily typed by what it is assigned to, and for most of
    /// them that is the only thing that could type it: <c>x =&gt; x</c> says
    /// nothing about what <c>x</c> is. But a lambda that writes its parameter
    /// types out has said everything but the result, and the result is what
    /// binding the body answers -- so <c>var double = (int x) =&gt; x * 2;</c>
    /// has a type, and it is a <c>closure</c>.
    /// </para>
    ///
    /// <para>
    /// <b>A closure and not a delegate</b>, because a lambda may capture, and a
    /// delegate is one pointer with nowhere to keep what was captured. The type
    /// is cached by signature, so two lambdas of the same shape get the same
    /// type and are interchangeable; a declared <c>closure</c> of that shape is
    /// interchangeable with them too (§2.14.1), since the two are the same two
    /// words.
    /// </para>
    ///
    /// <para>
    /// Null when the lambda has not said enough: a parameter without a type,
    /// or a block body, whose result is whatever its <c>return</c>s agree on
    /// and which needs a declared return type to bind at all.
    /// </para>
    /// </summary>
    private ClosureTypeSymbol? NaturalClosureType(LambdaSyntax syntax)
    {
        var parameterTypes = new List<TypeSymbol>();

        foreach (var parameter in syntax.Parameters)
        {
            if (parameter.Type is null) return null;

            var resolved = ResolveType(parameter.Type, _context.File!);
            if (resolved.IsError() || resolved.IsVoid()) return null;

            parameterTypes.Add(resolved);
        }

        // The body, bound once against those parameter types and thrown away.
        // This is the same trial `Select(numbers, n => n * 2)` already makes to
        // work out a type parameter that appears only in a lambda's result.
        if (ProbeLambdaResult(syntax, parameterTypes, allowVoid: true) is not { } result)
            return null;
        if (result.IsError()) return null;

        // A default is part of the type: it is what a call through this type
        // fills in, and a call through any other type never sees it.
        var defaults = new List<BoundExpression?>();
        for (int i = 0; i < parameterTypes.Count; i++)
            defaults.Add(syntax.Parameters[i].Default is { } written
                ? BindLambdaDefault(syntax.Parameters[i], written, parameterTypes[i])
                : null);

        string Signature(Func<TypeSymbol, string> name) =>
            $"{name(result)}(" + string.Join(", ", parameterTypes.Select((t, i) =>
                defaults[i] is { } fallback ? $"{name(t)} = {ConstantKey(fallback)}" : name(t))) + ")";

        string key = Signature(TypeIdentity);
        if (_naturalClosures.TryGetValue(key, out var existing)) return existing;

        var type = NewClosureType(
            "closure " + MadeTypeName(_currentModule!.Name, Signature(t => t.Name), () => Signature(TypeIdentity)),
            _currentModule.Name, syntax.Span, isPublic: false, []);

        type.ReturnType = result;

        for (int i = 0; i < parameterTypes.Count; i++)
            type.Signature.Add(new ParameterSymbol(syntax.Parameters[i].Name, parameterTypes[i], i)
            {
                Default = defaults[i],
            });

        // Registered so that the emitter writes its TypeInfo and the reference
        // walk that retains its receiver is generated, exactly as for one
        // somebody declared.
        Remember(_currentModule.Types, type.SimpleName, type);
        Remember(_naturalClosures, key, (ClosureTypeSymbol)type);

        return type;
    }

    /// <summary>
    /// Binds the body of a lambda whose parameter types are all written, and
    /// reports what does not bind in it. True when that reported anything:
    /// the body's own error is then the reason it has no type.
    /// </summary>
    private bool ReportedLambdaBody(LambdaSyntax syntax)
    {
        var parameterTypes = new List<TypeSymbol>();
        foreach (var parameter in syntax.Parameters)
        {
            if (parameter.Type is null) return false;

            var resolved = ResolveTypeQuietly(parameter.Type, _context.File!);
            if (resolved.IsError() || resolved.IsVoid()) return false;
            parameterTypes.Add(resolved);
        }

        int before = diagnostics.ErrorCount;
        ProbeLambdaResult(syntax, parameterTypes, allowVoid: true, report: true);
        return diagnostics.ErrorCount > before;
    }

    /// <summary>
    /// The closure type each signature got, so that two lambdas of the same
    /// shape are the same type rather than two types that look alike.
    /// </summary>
    private readonly Dictionary<string, ClosureTypeSymbol> _naturalClosures =
        new(StringComparer.Ordinal);

    /// <summary>
    /// The one type every <c>return</c> reaches, which is the question a
    /// ternary's two arms ask. A body that returns nothing is <c>void</c>, and
    /// one that returns a value on one path and nothing on another has no answer.
    /// </summary>
    private TypeSymbol? AgreedReturnType(List<BoundExpression?> returns)
    {
        if (returns.Count == 0 || returns.All(r => r is null)) return PrimitiveTypeSymbol.Void;
        if (returns.Any(r => r is null)) return null;

        var values = returns.Select(r => r!).ToList();
        if (values.Any(v => v.Type.IsError())) return null;

        var typed = values.Where(v => !IsTargetTyped(v)).ToList();
        if (typed.Count == 0) return null;

        var agreed = typed[0].Type;
        foreach (var next in typed.Skip(1))
        {
            if (IsImplicitlyConvertible(next, agreed)) continue;

            if (!typed.All(v => IsImplicitlyConvertible(v, next.Type))) return null;
            agreed = next.Type;
        }

        return values.All(v => IsImplicitlyConvertible(v, agreed)) ? agreed : null;
    }

    /// <summary>
    /// A lambda parameter's default, bound where the lambda was written. A
    /// constant, on the terms a function's default is (§7.1.2).
    /// </summary>
    private BoundExpression? BindLambdaDefault(
        LambdaParameterSyntax parameter, ExpressionSyntax written, TypeSymbol type)
    {
        // Once per type: the natural type and the conversion to it both ask,
        // and a mistake is reported once.
        if (_lambdaDefaults.TryGetValue((parameter, type), out var known)) return known;

        var bound = BindConversion(BindExpression(written), type, written.Span);
        bool constant = !bound.Type.IsError() && IsConstantDefault(bound);
        if (!diagnostics.IsMuted)
            Remember(_lambdaDefaults, (parameter, type), constant ? bound : null);

        if (bound.Type.IsError()) return null;
        if (constant) return bound;

        diagnostics.Error("SL0613", written.Span,
            $"the default for '{parameter.Name}' is not a constant, and a default is written " +
            "into every call that leaves it out. A literal, 'null', a 'const', an enum member " +
            "or 'default(T)' is what it may be");
        return null;
    }

    private readonly Dictionary<(LambdaParameterSyntax, TypeSymbol), BoundExpression?> _lambdaDefaults = [];

    /// <summary>A constant spelled so that two equal ones compare equal.</summary>
    private static string ConstantKey(BoundExpression constant) => constant switch
    {
        BoundLiteral literal => Convert.ToString(literal.Value, System.Globalization.CultureInfo.InvariantCulture) ?? "",
        BoundStringLiteral text => "\"" + text.Value + "\"",
        BoundNullLiteral => "null",
        BoundDefault => "default",
        BoundConstantAccess named => Convert.ToString(named.Constant.Value, System.Globalization.CultureInfo.InvariantCulture) ?? "",
        BoundConversion conversion => ConstantKey(conversion.Operand),
        BoundUnary { Operator: BoundUnaryOp.Negate } negated => "-" + ConstantKey(negated.Operand),
        _ => constant.GetType().Name,
    };

    /// <summary>
    /// What a lambda wrote about itself, checked against what it is becoming:
    /// a result written out has to be the target's, and a default is seen only
    /// through a type that has one.
    /// </summary>
    private bool CheckLambdaAgainst(
        LambdaSyntax syntax, TypeSymbol returns, IReadOnlyList<ParameterSymbol> wanted,
        string target, SourceSpan span)
    {
        if (syntax.ReturnType is not null)
        {
            var written = ResolveType(syntax.ReturnType, _context.File!, allowVoid: true);
            if (!written.IsError() && !written.Equals(returns))
            {
                diagnostics.Error("SL0765", syntax.ReturnType.Span,
                    $"this lambda returns '{written.Name}', and '{target}' returns " +
                    $"'{returns.Name}'; a result written out is not converted",
                    written, returns);
                return false;
            }
        }

        for (int i = 0; i < syntax.Parameters.Count && i < wanted.Count; i++)
        {
            var parameter = syntax.Parameters[i];
            if (parameter.Default is not { } written) continue;

            var bound = BindLambdaDefault(parameter, written, wanted[i].Type);
            if (bound is null) continue;

            if (wanted[i].Default is { } theirs && ConstantKey(theirs) == ConstantKey(bound))
                continue;

            diagnostics.Warning("SL0766", written.Span,
                $"'{target}' gives '{parameter.Name}' " +
                (wanted[i].Default is null ? "no default" : "a different default") +
                ", so a call through it never sees this one. A default on a lambda is " +
                "seen only through the lambda's own type, as 'var' holds it");
        }

        return true;
    }

    /// <summary>
    /// The names a lambda's parameters are bound under. Two or more written
    /// <c>_</c> are discards, and none of them can be read; one alone is a
    /// name, as it always was.
    /// </summary>
    private static List<string> LambdaParameterNames(LambdaSyntax syntax)
    {
        int discards = syntax.Parameters.Count(p => p.Name == "_");

        return syntax.Parameters
            .Select((p, i) => discards > 1 && p.Name == "_" ? $"_?{i}" : p.Name)
            .ToList();
    }

    private BoundExpression BindLambdaAsClosure(
        LambdaSyntax syntax, InterfaceTypeSymbol target, FunctionSymbol method, SourceSpan span)
    {
        var wanted = method.Parameters.Where(p => !p.IsThis).ToList();
        if (!CheckLambdaArity(syntax, wanted.Count, target.Name, span)) return new BoundErrorExpression(span);
        if (!CheckLambdaAgainst(syntax, method.ReturnType, wanted, target.Name, span))
            return new BoundErrorExpression(span);

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
            Scope = _context.File,
        };

        var self = new ParameterSymbol("this", closureType, 0) { IsThis = true };
        symbol.Parameters.Add(self);
        AddLambdaParameters(symbol, syntax, wanted);

        closureType.Methods.Add(symbol);
        _generated.Add(closureType);
        _generated.Add(symbol);

        var context = new ClosureContext
        {
            Type = closureType,
            This = self,
            OuterScopes = [.. _context.Locals],
            OuterFunction = _context.Function,
            IsStatic = syntax.IsStatic,
        };

        var body = BindLambdaBody(syntax, symbol, context);

        // The fields are known only now, so the layout waits for the body.
        ComputeLayout(closureType, []);
        _classes.Add(closureType);
        _functions.Add(new BoundFunction(symbol, body));

        return new BoundClosure(span, target, closureType, context.Captures);
    }

    /// <summary>
    /// A lambda becoming a <c>closure</c>: the same generated class, bound to
    /// as a method pointer rather than reached through an interface.
    ///
    /// The generated object *is* the receiver. Its method already takes that
    /// object as argument zero, which is the shape a closure calls -- so a
    /// lambda and a bound method produce the identical two words, and nothing
    /// downstream can tell which it was given.
    ///
    /// **No interface is involved.** The class implements none, is never
    /// dispatched through, and exists only to hold what the lambda captured.
    /// </summary>
    private BoundExpression BindLambdaAsMethodPointer(
        LambdaSyntax syntax, ClosureTypeSymbol target, SourceSpan span)
    {
        if (!CheckLambdaArity(syntax, target.Signature.Count, target.Name, span))
            return new BoundErrorExpression(span);
        if (!CheckLambdaAgainst(syntax, target.ReturnType, target.Signature, target.Name, span))
            return new BoundErrorExpression(span);

        var closureType = new ClassTypeSymbol
        {
            SimpleName = $"Closure.{_closureCount++}",
            ModuleName = _currentModule!.Name,
            Span = span,
        };

        var symbol = new FunctionSymbol
        {
            Name = "Invoke",
            ModuleName = closureType.ModuleName,
            ReturnType = target.ReturnType,
            Linkage = LinkageKind.Stainless,
            Kind = FunctionKind.Method,
            ContainingType = closureType,
            IsPublic = true,
            Span = syntax.Span,
            Scope = _context.File,
        };

        var self = new ParameterSymbol("this", closureType, 0) { IsThis = true };
        symbol.Parameters.Add(self);
        AddLambdaParameters(symbol, syntax, target.Signature);

        closureType.Methods.Add(symbol);
        _generated.Add(closureType);
        _generated.Add(symbol);

        // Consumed here so that a lambda nested inside this one is bound as an
        // ordinary lambda.
        bool subscribed = _subscribingLambda && target.ReturnType.IsVoid();
        _subscribingLambda = false;

        var context = new ClosureContext
        {
            Type = closureType,
            This = self,
            OuterScopes = [.. _context.Locals],
            OuterFunction = _context.Function,
            WeakThis = subscribed,
            IsStatic = syntax.IsStatic,
        };

        var body = BindLambdaBody(syntax, symbol, context);

        // A subscribed lambda that uses `this` begins by loading it, and does
        // nothing once it has gone -- which is well defined, since a handler
        // returns nothing:
        //
        //     Outer? this? = (Outer?)this.this;
        //     if (this? == null) return;
        if (context.WeakSelf is { } alive && context.WeakSelfField is { } weakField)
        {
            var prologue = new BoundBlock(span, [
                new BoundLocalDeclaration(span, alive, new BoundConversion(span, alive.Type,
                    new BoundFieldAccess(span, new BoundThis(span, closureType, self), weakField),
                    ConversionKind.ReferenceToOptional)),
                new BoundIf(span,
                    new BoundBinary(span, PrimitiveTypeSymbol.Bool,
                        new BoundLocalAccess(span, alive), BoundBinaryOp.Equal,
                        new BoundNullLiteral(span, alive.Type)),
                    new BoundReturn(span, null),
                    null),
                body,
            ]);
            prologue.Locals.Add(alive);
            body = prologue;
        }

        ComputeLayout(closureType, []);
        _classes.Add(closureType);
        _functions.Add(new BoundFunction(symbol, body));

        var made = new BoundClosure(span, closureType, closureType, context.Captures);
        return new BoundClosureCreate(span, target, symbol, made);
    }

    private BoundExpression BindLambdaAsFunction(
        LambdaSyntax syntax, DelegateTypeSymbol target, SourceSpan span)
    {
        if (!CheckLambdaArity(syntax, target.Signature.Count, target.Name, span))
            return new BoundErrorExpression(span);
        if (!CheckLambdaAgainst(syntax, target.ReturnType, target.Signature, target.Name, span))
            return new BoundErrorExpression(span);

        var symbol = new FunctionSymbol
        {
            Name = $"Lambda.{_closureCount++}",
            ModuleName = _currentModule!.Name,
            ReturnType = target.ReturnType,
            Linkage = LinkageKind.Stainless,
            IsPublic = false,
            Span = syntax.Span,
            Scope = _context.File,
        };

        AddLambdaParameters(symbol, syntax, target.Signature);
        _generated.Add(symbol);

        var context = new ClosureContext
        {
            OuterScopes = [.. _context.Locals],
            OuterFunction = _context.Function,
            IsStatic = syntax.IsStatic,
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
        var names = LambdaParameterNames(syntax);

        for (int i = 0; i < syntax.Parameters.Count && i < wanted.Count; i++)
        {
            var declared = syntax.Parameters[i];
            var type = wanted[i].Type;

            if (declared.Type is not null)
            {
                var written = ResolveType(declared.Type, _context.File!);
                if (!written.IsError() && !written.Equals(type))
                    diagnostics.Error("SL0384", declared.Span,
                        $"parameter '{declared.Name}' is '{written.Name}', but the target " +
                        $"expects '{type.Name}'",
                        written, type);
            }

            symbol.Parameters.Add(new ParameterSymbol(names[i], type, symbol.Parameters.Count));
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
        var inner = _context.ForBody(symbol);
        inner.Closures.Add(context);
        using var entered = Enter(inner);

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
            var span = syntax.Expression!.Span;
            BoundStatement statement;

            if (!symbol.ReturnType.IsVoid())
            {
                statement = new BoundReturn(span, BindConversion(value, symbol.ReturnType, span));
            }
            else if (RefuseUntyped(value))
            {
                statement = new BoundExpressionStatement(span, new BoundErrorExpression(value.Span));
            }
            else
            {
                statement = Discarding(value, span);
            }

            body = new BoundBlock(syntax.Span, [statement]);
        }

        PopScope();
        CheckJumps("this lambda");

        if (!symbol.ReturnType.IsVoid() && EndIsReachable(body))
            diagnostics.Error("SL0217", syntax.Span,
                $"not all paths through this lambda return a value of type '{symbol.ReturnType.Name}'",
                symbol.ReturnType);

        return body;
    }

    /// <summary>
    /// Binds a switch: one governing value, and sections whose labels are
    /// constants of its type. Each label is the pattern that asks for that
    /// constant, which is what lets one lowering reach every kind of section.
    /// </summary>
    private BoundStatement BindSwitch(SwitchSyntax syntax)
    {
        var value = BindExpression(syntax.Value);
        if (value.Type.IsError()) return new BoundBlock(syntax.Span, []);

        // A label that asks anything but "is it this constant" -- or any label
        // with a `when` on it -- takes the whole switch down the pattern path,
        // where it becomes a chain of tests rather than a jump table.
        if (NeedsPatterns(syntax, value.Type)) return BindPatternSwitch(syntax, value);

        if (value.Type is VariantTypeSymbol variant)
            return BindVariantSwitch(syntax, value, variant);

        foreach (var binding in syntax.Sections.SelectMany(section => section.Bindings))
            diagnostics.Error("SL0438", binding.Span,
                $"'case {binding.Case} {binding.Name}' matches a variant's case and binds what " +
                $"it carries, and '{value.Type.Name}' is not a variant",
                value.Type);

        bool onText = _builtins.IsString(value.Type);
        bool onOrdinal = value.Type is PrimitiveTypeSymbol { IsInteger: true } or EnumTypeSymbol
                         || value.Type.IsBool();

        if (!onText && !onOrdinal)
        {
            diagnostics.Error("SL0403", syntax.Value.Span,
                $"'{value.Type.Name}' cannot be switched on; a switch needs a value with " +
                "constant labels, so it takes an integer, 'char', 'bool', an enum or a String",
                value.Type);
            return new BoundBlock(syntax.Span, []);
        }

        var input = new BoundPlaceholder(syntax.Value.Span, value.Type);
        var sections = new List<BoundSwitchSection>();
        var seenOrdinals = new Dictionary<ulong, SourceSpan>();
        var seenText = new Dictionary<string, SourceSpan>(StringComparer.Ordinal);
        bool sawDefault = false;
        var frame = OpenSwitchFrame(value.Type, overVariant: false);

        _context.SwitchDepth++;

        foreach (var section in syntax.Sections)
        {
            var labels = new List<BoundSwitchLabel>();
            int index = sections.Count;

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
                    {
                        labels.Add(ConstantLabel(label.Span, input, text, text.Value));
                        frame.Cases[text.Value] = index;
                    }

                    continue;
                }

                if (FoldSwitchLabel(bound) is not { } bits)
                {
                    diagnostics.Error("SL0404", label.Span,
                        $"a 'case' label must be a constant of type '{value.Type.Name}', " +
                        "and this is not one",
                        value.Type);
                    continue;
                }

                if (!seenOrdinals.TryAdd(bits, label.Span))
                    diagnostics.Error("SL0405", label.Span,
                        "this switch already has a case for that value");
                else
                {
                    // The folded value, not the expression it was written as:
                    // `case -1:` is a negation, and an LLVM switch arm has to
                    // be a constant rather than an instruction.
                    labels.Add(ConstantLabel(
                        label.Span, input, new BoundLiteral(label.Span, value.Type, bits), bits));
                    frame.Cases[bits] = index;
                }
            }

            if (section.HasDefault)
            {
                if (sawDefault)
                    diagnostics.Error("SL0406", section.Span,
                        "this switch already has a 'default' section");
                else
                    frame.Default = index;
                sawDefault = true;
            }

            PushScope();
            var body = new BoundBlock(section.Span,
                BindStatementList(section.Statements));
            PopScope();

            // No fall-through, as in C#. A section that runs off its end is
            // almost always a forgotten 'break', and the reader of one that
            // meant it has no way to tell.
            if (EndIsReachable(body))
                diagnostics.Error("SL0407", section.Span,
                    "a switch section must not run off its end; finish it with 'break', " +
                    "'return', 'continue' or 'goto'. Stack the labels instead, as in " +
                    "'case 1: case 2:', when two values share a body, or end one section " +
                    "with 'goto case' to run another");

            sections.Add(new BoundSwitchSection(
                section.Span, labels, section.HasDefault, body));
        }

        _context.SwitchDepth--;
        CloseSwitchFrame(frame, sections);

        return new BoundSwitch(syntax.Span, value, input, sections);
    }

    /// <summary><c>case 3:</c>, as the pattern that asks for equality with the folded constant.</summary>
    private BoundSwitchLabel ConstantLabel(
        SourceSpan span, BoundPlaceholder input, BoundExpression constant, object folded)
    {
        var test = BindBinaryOperation(span, input, BoundBinaryOp.Equal, constant, TokenKind.EqualsEquals);
        return new BoundSwitchLabel(span,
            new BoundTestPattern(span, input, test, new PatternTestKey(PatternTestKind.Constant, folded)),
            null);
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
        var input = new BoundPlaceholder(syntax.Value.Span, value.Type);
        var subject = NarrowableSubject(value);
        var sections = new List<BoundSwitchSection>();
        var covered = new Dictionary<VariantCaseSymbol, SourceSpan>();
        bool sawDefault = false;
        var frame = OpenSwitchFrame(variant, overVariant: true);

        _context.SwitchDepth++;

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
                    "they are " + Listed(variant.Cases.Select(c => c.Name)),
                    variant);
            }

            foreach (var declared in section.Bindings)
            {
                if (variant.FindCase(declared.Case) is not { } matched)
                {
                    diagnostics.Error("SL0435", declared.Span,
                        $"variant '{variant.Name}' has no case named '{declared.Case}'; it has " +
                        Listed(variant.Cases.Select(c => c.Name)),
                        variant);
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
                else
                    frame.Default = sections.Count;
                sawDefault = true;
            }

            // Inside the arm, the value is that case. One case only: a section
            // reached by two of them has proved nothing about which.
            var saved = SnapshotFacts();
            if (subject is not null && cases.Count == 1)
                _context.VariantFacts[subject] = Fact.Holding(cases[0]);
            else if (subject is not null) _context.VariantFacts.Remove(subject);

            PushScope();

            var labels = new List<BoundSwitchLabel>();
            foreach (var matched in cases)
            {
                BoundPattern pattern = CaseTest(section.Span, input, matched);

                if (ReferenceEquals(matched, bound))
                {
                    var binding = DeclareLocal(boundName, bound.Payload!, isConst: true, boundSpan);
                    pattern = new BoundAndPattern(boundSpan,
                    [
                        pattern,
                        new BoundDeclarationPattern(boundSpan, binding,
                            new BoundVariantPayload(boundSpan, input, bound, null)),
                    ]);
                }

                labels.Add(new BoundSwitchLabel(section.Span, pattern, null));
            }

            var body = new BoundBlock(section.Span, BindStatementList(section.Statements));

            PopScope();
            _context.VariantFacts = saved;

            if (EndIsReachable(body))
                diagnostics.Error("SL0407", section.Span,
                    "a switch section must not run off its end; finish it with 'break', " +
                    "'return', 'continue' or 'goto'. Stack the labels instead, as in " +
                    "'case Circle: case Rect:', when two cases share a body");

            sections.Add(new BoundSwitchSection(section.Span, labels, section.HasDefault, body));
        }

        _context.SwitchDepth--;
        CloseSwitchFrame(frame, sections);

        var missing = variant.Uncovered(covered.Keys).ToList();

        if (missing.Count > 0 && !sawDefault)
            diagnostics.Error("SL0436", syntax.Span,
                $"this switch over '{variant.Name}' does not cover " +
                Listed(missing.Select(c => "'" + c.Name + "'")) +
                "; a variant is the choice between its cases, so a switch that leaves one out " +
                "has no answer for it. Add the case, or a 'default'",
                variant);

        return new BoundSwitch(syntax.Span, value, input, sections)
        {
            IsExhaustive = missing.Count == 0,
        };
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
        BoundLiteral { Value: int scalar } => (ulong)scalar,
        BoundUnary { Operator: BoundUnaryOp.Negate, Operand: var operand }
            when FoldSwitchLabel(operand) is { } magnitude => unchecked((ulong)-(long)magnitude),
        BoundConstantAccess { Constant.Value: ulong bits } => bits,
        BoundConstantAccess { Constant.Value: bool flag } => flag ? 1UL : 0UL,
        BoundConstantAccess { Constant.Value: int scalar } => (ulong)scalar,
        _ => null,
    };

    private BoundStatement BindReturn(ReturnSyntax syntax)
    {
        if (_context.ParallelDepth > 0)
        {
            diagnostics.Error("SL0374", syntax.Span,
                "'return' cannot leave a 'parallel' block; the join at its closing brace " +
                "would be skipped and the jobs left running against a dead frame");
            return new BoundReturn(syntax.Span, null);
        }

        // A block-bodied lambda whose result is being worked out: what each
        // return gives back is the evidence, and nothing is converted yet.
        if (_context.InferringReturnsOf is not null &&
            ReferenceEquals(_context.Function, _context.InferringReturnsOf))
        {
            var found = syntax.Value is null ? null : BindExpression(syntax.Value);
            _context.ReturnsFound.Add(found);
            return new BoundReturn(syntax.Span, found);
        }

        var expected = _context.Function?.ReturnType ?? PrimitiveTypeSymbol.Void;

        if (syntax.Value is null)
        {
            if (!expected.IsVoid())
                diagnostics.Error("SL0223", syntax.Span,
                    $"this function must return a value of type '{expected.Name}'",
                    expected);
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
        if (_context.LoopDepth == 0 && _context.SwitchDepth == 0)
            diagnostics.Error("SL0225", syntax.Span,
                "'break' is only valid inside a loop or a switch");
        return new BoundBreak(syntax.Span);
    }

    private BoundStatement BindContinue(ContinueSyntax syntax)
    {
        if (_context.LoopDepth == 0)
            diagnostics.Error("SL0226", syntax.Span, "'continue' is only valid inside a loop");
        return new BoundContinue(syntax.Span);
    }

    private BoundExpression BindCondition(ExpressionSyntax syntax)
    {
        var condition = BindExpression(syntax);
        if (!condition.Type.IsBool() && !condition.Type.IsError())
            diagnostics.Error("SL0227", syntax.Span,
                $"a condition must be 'bool', but this is '{condition.Type.Name}'; " +
                "Stainless has no implicit conversion to 'bool'",
                condition.Type);
        return condition;
    }
}
