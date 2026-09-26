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
/// Deconstruction: <c>(a, b) = (b, a)</c>, <c>var (x, y) = point</c>, and the
/// <c>foreach</c> that takes each element apart.
///
/// <para>
/// It is lowered here, to lets and assignments the emitter already knows, in
/// C#'s order: the targets' receivers and indices left to right, then every
/// value on the right, then the stores left to right. Nothing is stored until
/// everything has been read, which is what makes a swap a swap.
/// </para>
/// <para>
/// A value that is not a tuple is taken apart by its <c>Deconstruct</c>, a
/// method or a free function with one <c>out</c> parameter per element.
/// <see cref="BindDeconstructCall"/> is the one place that is looked for.
/// </para>
/// </summary>
public sealed partial class Binder
{
    private enum DeconstructionKind { Discard, Declare, Place, Property, Nested }

    /// <summary>One element of the left side, and what is stored into it.</summary>
    private sealed class DeconstructionTarget(DeconstructionKind kind, SourceSpan span)
    {
        public DeconstructionKind Kind { get; } = kind;
        public SourceSpan Span { get; } = span;

        /// <summary>The written type; null for <c>var</c> until a value supplies it.</summary>
        public TypeSymbol? Type { get; set; }

        public string Name { get; init; } = "";
        public SourceSpan NameSpan { get; init; }

        /// <summary>The storage a <see cref="DeconstructionKind.Place"/> writes, held.</summary>
        public BoundExpression? Place { get; init; }

        public BoundExpression? Receiver { get; init; }
        public PropertySymbol? Property { get; init; }
        public IReadOnlyList<BoundExpression> Indices { get; init; } = [];
        public bool IsNonVirtual { get; init; }

        public List<DeconstructionTarget> Elements { get; } = [];

        /// <summary>The value this element is given, already converted to <see cref="Type"/>.</summary>
        public BoundExpression? Source { get; set; }
    }

    /// <summary>
    /// A value evaluated before any store: a let when it has a
    /// <see cref="Local"/>, otherwise an expression run for what it does.
    /// </summary>
    private readonly record struct DeconstructionStep(
        LocalSymbol? Local, BoundExpression Value, bool IsOwned);

    /// <summary><c>(int a, b) = t;</c>, where it stands as a statement.</summary>
    private BoundStatement BindDeconstructionStatement(AssignmentSyntax syntax)
    {
        var target = (TupleSyntax)syntax.Target;
        if (BindDeconstruction(target, syntax.Value, null, syntax.Span, DeconstructionUse.Statement)
            is not var (declared, expression))
        {
            DeclareUnbound(target);
            return new BoundExpressionStatement(syntax.Span, new BoundErrorExpression(syntax.Span));
        }

        return declared.Count == 0
            ? new BoundExpressionStatement(syntax.Span, expression)
            : new BoundDeconstruct(syntax.Span, declared, expression);
    }

    /// <summary>
    /// <c>(a, b) = t</c> inside an expression. Its value is the tuple stored,
    /// so <c>(a, b) = (c, d) = t</c> chains as it does in C#.
    /// </summary>
    private BoundExpression BindDeconstructionExpression(AssignmentSyntax syntax)
    {
        var target = (TupleSyntax)syntax.Target;
        return BindDeconstruction(target, syntax.Value, null, syntax.Span, DeconstructionUse.Value)
            is var (_, expression)
            ? expression
            : new BoundErrorExpression(syntax.Span);
    }

    /// <summary>
    /// <c>foreach (var (k, v) in pairs)</c>: the element, already in a local
    /// of the loop's own, taken apart into the names the loop declares.
    /// </summary>
    private BoundStatement BindForEachDeconstruction(
        TupleSyntax target, LocalSymbol element, SourceSpan span)
    {
        var value = new BoundLocalAccess(target.Span, element);
        if (BindDeconstruction(target, null, value, span, DeconstructionUse.ForEach)
            is not var (declared, expression))
        {
            DeclareUnbound(target);
            return new BoundExpressionStatement(span, new BoundErrorExpression(span));
        }

        return new BoundDeconstruct(span, declared, expression);
    }

    private enum DeconstructionUse { Statement, Value, ForEach }

    /// <summary>
    /// Declares what a deconstruction that failed would have declared, as
    /// errors, so that each later use is not reported again as undefined.
    /// </summary>
    private void DeclareUnbound(ExpressionSyntax syntax)
    {
        switch (syntax)
        {
            case TupleSyntax tuple:
                foreach (var element in tuple.Elements)
                    DeclareUnbound(element);
                break;

            case DeclarationExpressionSyntax { Name: not "_" } declaration
                when !_context.Locals[^1].ContainsKey(declaration.Name):
                DeclareLocal(declaration.Name, ErrorTypeSymbol.Instance, isConst: false,
                    declaration.NameSpan);
                break;
        }
    }

    /// <summary>
    /// The whole of a deconstruction: the locals it declares, and the
    /// expression that evaluates everything and then stores it.
    /// </summary>
    /// <param name="value">
    /// A value already bound, which nothing the deconstruction writes can
    /// change; null to bind <paramref name="valueSyntax"/>.
    /// </param>
    private (List<BoundLocalDeclaration> Declared, BoundExpression Expression)? BindDeconstruction(
        TupleSyntax targetSyntax, ExpressionSyntax? valueSyntax, BoundExpression? value,
        SourceSpan span, DeconstructionUse use)
    {
        var held = new List<HeldValue>();
        if (BindDeconstructionTarget(targetSyntax, held, use) is not { } target) return null;

        var steps = new List<DeconstructionStep>();
        if (!SupplyDeconstruction(target, valueSyntax, value, steps, stable: value is not null))
            return null;

        var declared = new List<BoundLocalDeclaration>();
        var writes = new List<BoundExpression>();
        WriteDeconstruction(target, declared, writes);

        BoundExpression body;
        if (use == DeconstructionUse.Value)
        {
            var result = DeconstructedValue(target);
            body = writes.Count == 0 ? result : new BoundSequence(span, writes, result);
        }
        else if (writes.Count == 0)
        {
            // Every element was a discard, and the values are evaluated for
            // what they do.
            body = new BoundLiteral(span, PrimitiveTypeSymbol.Bool, true);
        }
        else
        {
            body = new BoundSequence(span, writes.Take(writes.Count - 1).ToList(), writes[^1]);
        }

        for (int i = steps.Count - 1; i >= 0; i--)
        {
            var step = steps[i];
            body = step.Local is null
                ? new BoundSequence(span, [step.Value], body)
                : new BoundLet(span, step.Local, step.Value, body) { IsOwned = step.IsOwned };
        }

        return (declared, WithHeld(span, held, body));
    }

    /// <summary>
    /// The left side, with every receiver and index a store will need held in
    /// <paramref name="held"/>, left to right.
    /// </summary>
    private DeconstructionTarget? BindDeconstructionTarget(
        ExpressionSyntax syntax, List<HeldValue> held, DeconstructionUse use)
    {
        switch (syntax)
        {
            case TupleSyntax tuple:
            {
                var nested = new DeconstructionTarget(DeconstructionKind.Nested, tuple.Span);
                bool failed = false;

                foreach (var element in tuple.Elements)
                {
                    if (BindDeconstructionTarget(element, held, use) is { } bound)
                    {
                        nested.Elements.Add(bound);
                    }
                    else
                    {
                        failed = true;
                    }
                }

                return failed ? null : nested;
            }

            case DeclarationExpressionSyntax declaration:
            {
                if (use == DeconstructionUse.Value)
                {
                    diagnostics.Error("SL0771", declaration.Span,
                        $"'{declaration.Name}' is declared inside an expression, where there is " +
                        "no statement for it to belong to; a deconstruction that declares has " +
                        "to be a statement of its own");
                    return null;
                }

                var type = declaration.Type is null
                    ? null
                    : ResolveType(declaration.Type, _context.File!);
                if (type is not null && type.IsError()) return null;

                return new DeconstructionTarget(
                    declaration.Name == "_" ? DeconstructionKind.Discard : DeconstructionKind.Declare,
                    declaration.Span)
                {
                    Type = type,
                    Name = declaration.Name,
                    NameSpan = declaration.NameSpan,
                };
            }

            // `_` is a discard unless something in scope is called that.
            case NameSyntax { Name.Parts: ["_"], TypeArguments: null } discard
                when LookupLocal("_") is null &&
                     _context.Function?.Parameters.Any(p => p.Name == "_") != true:
                return new DeconstructionTarget(DeconstructionKind.Discard, discard.Span);
        }

        if (use == DeconstructionUse.ForEach)
        {
            diagnostics.Error("SL0772", syntax.Span,
                "a 'foreach' declares the names it takes an element apart into, and this " +
                "names something that already exists; write 'var' or a type in front of it, " +
                "or assign it inside the loop");
            return null;
        }

        return BindDeconstructionPlace(syntax, held);
    }

    /// <summary>An element that is somewhere to store: a variable, a field, an element or a property.</summary>
    private DeconstructionTarget? BindDeconstructionPlace(ExpressionSyntax syntax, List<HeldValue> held)
    {
        if (RefuseConditionalTarget(syntax)) return null;

        var target = Widened(BindExpression(syntax));
        if (target.Type.IsError()) return null;

        if (target is BoundCall { Function.Accessor: { } property } read)
        {
            var receiver = read.Receiver;
            if (receiver is not null)
            {
                if (WrittenParameter(receiver) is { } mutated) MarkAssigned(mutated);
                InvalidateVariantFact(receiver);
            }

            if (!CanWriteProperty(syntax.Span, receiver, property, plain: true, out var storage))
                return null;

            if (storage is not null)
            {
                return new DeconstructionTarget(DeconstructionKind.Place, syntax.Span)
                {
                    Type = property.Type,
                    Place = HoldPlace(storage, held, everything: true),
                };
            }

            NoteMemberWritten(property);

            return new DeconstructionTarget(DeconstructionKind.Property, syntax.Span)
            {
                Type = property.Type,
                Receiver = receiver is null ? null : HoldReceiver(receiver, held, everything: true),
                Property = property,
                Indices = property.IsIndexer
                    ? read.Arguments.Select(index => HoldValue(index, held, everything: true)).ToList()
                    : [],
                IsNonVirtual = read.IsNonVirtual,
            };
        }

        if (!Writable(target, syntax.Span, "=")) return null;

        InvalidateVariantFact(target);
        if (WrittenParameter(target) is { } written) MarkAssigned(written);
        NoteMemberWritten(target);

        return new DeconstructionTarget(DeconstructionKind.Place, syntax.Span)
        {
            Type = target.Type,
            Place = HoldPlace(target, held, everything: true),
        };
    }

    /// <summary>
    /// Gives every element of <paramref name="target"/> its value, evaluating
    /// into <paramref name="steps"/> whatever has to be read before the first
    /// store.
    /// </summary>
    /// <param name="stable">
    /// True when <paramref name="value"/> is a read of something the stores
    /// cannot reach, so it need not be held again.
    /// </param>
    private bool SupplyDeconstruction(
        DeconstructionTarget target, ExpressionSyntax? valueSyntax, BoundExpression? value,
        List<DeconstructionStep> steps, bool stable)
    {
        // `(a, b) = (b, a)`: each element is its own value, so no tuple is made.
        if (target.Kind == DeconstructionKind.Nested && value is null &&
            valueSyntax is TupleSyntax written)
        {
            if (!DeconstructionCountsAgree(target, written.Elements.Count, "the tuple", written.Span))
                return false;

            bool supplied = true;
            for (int i = 0; i < written.Elements.Count; i++)
            {
                supplied &= SupplyDeconstruction(
                    target.Elements[i], written.Elements[i], null, steps, stable: false);
            }

            return supplied;
        }

        value ??= BindExpression(valueSyntax!);
        if (value.Type.IsError()) return false;

        if (target.Kind != DeconstructionKind.Nested)
            return SupplyDeconstructionElement(target, value, steps, stable);

        if (value.Type is TupleTypeSymbol tuple)
        {
            if (!DeconstructionCountsAgree(target, tuple.Elements.Count, $"'{tuple.Name}'", value.Span))
                return false;

            var whole = stable ? value : HoldDeconstructed(value, steps);

            bool supplied = true;
            for (int i = 0; i < tuple.Elements.Count; i++)
            {
                var field = new BoundFieldAccess(value.Span, whole, tuple.Fields[i]);
                supplied &= SupplyDeconstruction(target.Elements[i], null, field, steps, stable: true);
            }

            return supplied;
        }

        if (BindDeconstructCall(value, target.Elements.Count, target.Span) is not var (call, parts))
            return false;

        steps.Add(new DeconstructionStep(null, call, IsOwned: false));

        bool all = true;
        for (int i = 0; i < parts.Count; i++)
        {
            var part = new BoundLocalAccess(value.Span, parts[i]);
            all &= SupplyDeconstruction(target.Elements[i], null, part, steps, stable: true);
        }

        return all;
    }

    private bool DeconstructionCountsAgree(
        DeconstructionTarget target, int count, string what, SourceSpan span)
    {
        if (target.Elements.Count == count) return true;

        diagnostics.Error("SL0609", span,
            $"{what} has {Counted(count, "element")}, and this names {target.Elements.Count}");
        return false;
    }

    /// <summary>One element given one value, converted to what it is stored as.</summary>
    private bool SupplyDeconstructionElement(
        DeconstructionTarget target, BoundExpression value, List<DeconstructionStep> steps,
        bool stable)
    {
        if (value is BoundArrayDraft loose && target.Type is null)
            value = SettleArrayFromElements(loose);
        if (RefuseUntyped(value)) return false;

        if (value.Type.IsVoid())
        {
            diagnostics.Error("SL0607", value.Span,
                "an element of a tuple has to be a value, and this produces none");
            return false;
        }

        if (target.Type is null && !HasOwnType(value))
        {
            diagnostics.Error("SL0553", value.Span,
                (target.Kind == DeconstructionKind.Declare ? $"'{target.Name}'" : "a discard") +
                " cannot be a 'var': this takes its type from where it is going, and a 'var' " +
                "is waiting to be told. Write the type in its place");
            return false;
        }

        target.Type ??= value.Type;
        var converted = BindConversion(value, target.Type, value.Span);
        if (converted.Type.IsError()) return false;

        target.Source = stable && IsRepeatable(converted)
            ? converted
            : HoldDeconstructed(converted, steps);
        return true;
    }

    /// <summary>
    /// A value read now and stored later. A copy is owned unless the value
    /// is one this statement made, because a store before it is read may drop
    /// what it came from.
    /// </summary>
    private BoundExpression HoldDeconstructed(BoundExpression value, List<DeconstructionStep> steps)
    {
        if (IsFixed(value)) return value;

        var local = new LocalSymbol(SyntheticName("taken"), value.Type, isConst: false);
        bool owned = !IsMade(value) &&
                     (value.Type.NeedsArc() || value.Type is StructTypeSymbol or FixedArrayTypeSymbol);
        steps.Add(new DeconstructionStep(local, value, owned));
        return new BoundLocalAccess(value.Span, local);
    }

    /// <summary>Whether a value is a temporary this statement made and will drop.</summary>
    private static bool IsMade(BoundExpression value) => value switch
    {
        BoundCall or BoundNew or BoundIndirectCall or BoundClosureCall => true,
        BoundTupleCreate or BoundStructNew or BoundVariantConstruction => true,
        BoundLet held => IsMade(held.Body),
        BoundSequence sequence => IsMade(sequence.Value),
        _ => false,
    };

    /// <summary>
    /// The stores, left to right, and the locals they declare. Declared here,
    /// after every value was bound, so no value can read a name it is about
    /// to give a value to.
    /// </summary>
    private void WriteDeconstruction(
        DeconstructionTarget target, List<BoundLocalDeclaration> declared, List<BoundExpression> writes)
    {
        switch (target.Kind)
        {
            case DeconstructionKind.Nested:
                foreach (var element in target.Elements)
                    WriteDeconstruction(element, declared, writes);
                break;

            case DeconstructionKind.Declare:
            {
                var local = DeclareLocal(target.Name, target.Type!, isConst: false, target.NameSpan);
                declared.Add(new BoundLocalDeclaration(target.NameSpan, local, null));
                writes.Add(new BoundAssignment(target.Span,
                    new BoundLocalAccess(target.NameSpan, local), target.Source!));
                break;
            }

            case DeconstructionKind.Place:
                writes.Add(new BoundAssignment(target.Span, target.Place!, target.Source!));
                break;

            case DeconstructionKind.Property:
                writes.Add(new BoundPropertyAssignment(
                    target.Span, target.Receiver, target.Property!, target.Source!)
                {
                    Indices = target.Indices,
                    IsNonVirtual = target.IsNonVirtual,
                });
                break;
        }
    }

    /// <summary>What <c>(a, b) = t</c> evaluates to: the tuple of what was stored.</summary>
    private BoundExpression DeconstructedValue(DeconstructionTarget target)
    {
        if (target.Kind != DeconstructionKind.Nested) return target.Source!;

        var elements = target.Elements.Select(DeconstructedValue).ToList();
        return new BoundTupleCreate(
            target.Span, TupleOf(elements.Select(e => e.Type).ToList()), elements);
    }

    /// <summary>
    /// <c>value.Deconstruct(out var a, out var b)</c>, for a value that is not
    /// a tuple: a method of its type, or a free function taking it first, with
    /// <paramref name="arity"/> <c>out</c> parameters. Overloads are chosen by
    /// that count, as a call with that many arguments would choose them.
    /// </summary>
    /// <returns>
    /// The call, and the locals it writes, one per element; null, reported,
    /// when there is no such <c>Deconstruct</c>.
    /// </returns>
    private (BoundExpression Call, List<LocalSymbol> Parts)? BindDeconstructCall(
        BoundExpression value, int arity, SourceSpan span)
    {
        var arguments = new List<ExpressionSyntax>(arity);
        for (int i = 0; i < arity; i++)
            arguments.Add(new OutArgumentSyntax(span, null, null, SyntheticName("part"), span));

        var member = new MemberAccessSyntax(
            span, new NameSyntax(value.Span, new QualifiedName(value.Span, ["$deconstructed"])),
            "Deconstruct");
        var syntax = new CallSyntax(span, member, arguments);

        BoundExpression call;
        List<LocalSymbol> parts;
        using (var trial = BeginTrial())
        {
            call = BindCallOn(value, member, syntax);
            parts = call is BoundCall bound
                ? bound.Arguments.OfType<BoundAddressOf>()
                    .Select(a => a.DeclaresLocal)
                    .OfType<LocalSymbol>()
                    .ToList()
                : [];

            if (!call.Type.IsError() && parts.Count == arity) trial.Accept();
        }

        if (call.Type.IsError() || parts.Count != arity)
        {
            diagnostics.Error("SL0608", value.Span,
                $"'{value.Type.Name}' is not a tuple and has no 'Deconstruct' with " +
                $"{Counted(arity, "'out' parameter")}, so it cannot be taken apart " +
                $"into {arity}");
            return null;
        }

        return (call, parts);
    }
}
