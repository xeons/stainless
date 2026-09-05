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
            if (subject is not null && cases.Count == 1)
                _variantFacts[subject] = Fact.Holding(cases[0]);
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
        BoundLiteral { Value: int scalar } => (ulong)scalar,
        BoundUnary { Operator: BoundUnaryOp.Negate, Operand: var operand }
            when FoldSwitchLabel(operand) is { } magnitude => unchecked((ulong)-(long)magnitude),
        BoundConstantAccess { Constant.Value: ulong bits } => bits,
        BoundConstantAccess { Constant.Value: bool flag } => flag ? 1UL : 0UL,
        BoundConstantAccess { Constant.Value: int scalar } => (ulong)scalar,
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
}
