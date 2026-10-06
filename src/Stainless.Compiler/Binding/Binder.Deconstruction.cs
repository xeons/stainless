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
/// Binding says what each element of the left side is and what it is given,
/// as a <see cref="BoundDeconstruction"/>; lowering evaluates them in C#'s
/// order and stores.
/// </para>
/// <para>
/// A value that is not a tuple is taken apart by its <c>Deconstruct</c>, a
/// method or a free function with one <c>out</c> parameter per element.
/// <see cref="BindDeconstructCall"/> is the one place that is looked for.
/// </para>
/// </summary>
public sealed partial class Binder
{
    /// <summary>One element of the left side while it is bound, and what it is given.</summary>
    private sealed class DeconstructionTarget(DeconstructionKind kind, SourceSpan span)
    {
        public DeconstructionKind Kind { get; } = kind;
        public SourceSpan Span { get; } = span;

        /// <summary>The written type; null for <c>var</c> until a value supplies it.</summary>
        public TypeSymbol? Type { get; set; }

        public string Name { get; init; } = "";
        public SourceSpan NameSpan { get; init; }
        public LocalSymbol? Local { get; set; }

        public BoundExpression? Place { get; init; }
        public BoundExpression? Receiver { get; init; }
        public PropertySymbol? Property { get; init; }
        public IReadOnlyList<BoundExpression> Indices { get; init; } = [];
        public bool IsNonVirtual { get; init; }

        public List<DeconstructionTarget> Elements { get; } = [];

        public DeconstructionSupply Supply { get; set; }
        public BoundExpression? Value { get; set; }
        public bool IsStable { get; set; }
        public BoundPlaceholder? Whole { get; set; }
        public TupleTypeSymbol? Stored { get; set; }
    }

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

    /// <summary>The locals a deconstruction declares, and the deconstruction.</summary>
    /// <param name="value">
    /// A value already bound, which nothing the deconstruction writes can
    /// change; null to bind <paramref name="valueSyntax"/>.
    /// </param>
    private (List<BoundLocalDeclaration> Declared, BoundExpression Expression)? BindDeconstruction(
        TupleSyntax targetSyntax, ExpressionSyntax? valueSyntax, BoundExpression? value,
        SourceSpan span, DeconstructionUse use)
    {
        if (BindDeconstructionTarget(targetSyntax, use) is not { } target) return null;

        if (!SupplyDeconstruction(target, valueSyntax, value, stable: value is not null))
            return null;

        var declared = new List<BoundLocalDeclaration>();
        TypeSymbol? last = null;
        DeclareDeconstructed(target, declared, use == DeconstructionUse.Value, ref last);

        var type = use == DeconstructionUse.Value ? target.Stored! : last ?? PrimitiveTypeSymbol.Bool;
        return (declared, new BoundDeconstruction(span, type, Freeze(target), use == DeconstructionUse.Value));
    }

    /// <summary>The left side: what each element is, and the storage it names.</summary>
    private DeconstructionTarget? BindDeconstructionTarget(ExpressionSyntax syntax, DeconstructionUse use)
    {
        switch (syntax)
        {
            case TupleSyntax tuple:
            {
                var nested = new DeconstructionTarget(DeconstructionKind.Nested, tuple.Span);
                bool failed = false;

                foreach (var element in tuple.Elements)
                {
                    if (BindDeconstructionTarget(element, use) is { } bound)
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
                    diagnostics.Report(Codes.DeclarationOutsideDeconstruction, declaration.Span,
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
            diagnostics.Report(Codes.ForeachDeconstructionWithoutDeclaration, syntax.Span,
                "a 'foreach' declares the names it takes an element apart into, and this " +
                "names something that already exists; write 'var' or a type in front of it, " +
                "or assign it inside the loop");
            return null;
        }

        return BindDeconstructionPlace(syntax);
    }

    /// <summary>An element that is somewhere to store: a variable, a field, an element or a property.</summary>
    private DeconstructionTarget? BindDeconstructionPlace(ExpressionSyntax syntax)
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
                    Place = storage,
                };
            }

            NoteMemberWritten(property);

            return new DeconstructionTarget(DeconstructionKind.Property, syntax.Span)
            {
                Type = property.Type,
                Receiver = receiver,
                Property = property,
                Indices = property.IsIndexer ? read.Arguments : [],
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
            Place = target,
        };
    }

    /// <summary>Gives every element of <paramref name="target"/> its value.</summary>
    /// <param name="stable">
    /// True when <paramref name="value"/> is a read of something the stores
    /// cannot reach.
    /// </param>
    private bool SupplyDeconstruction(
        DeconstructionTarget target, ExpressionSyntax? valueSyntax, BoundExpression? value, bool stable)
    {
        // `(a, b) = (b, a)`: each element is its own value, so no tuple is made.
        if (target.Kind == DeconstructionKind.Nested && value is null &&
            valueSyntax is TupleSyntax written)
        {
            if (!DeconstructionCountsAgree(target, written.Elements.Count, "the tuple", written.Span))
                return false;

            target.Supply = DeconstructionSupply.Elements;

            bool supplied = true;
            for (int i = 0; i < written.Elements.Count; i++)
                supplied &= SupplyDeconstruction(target.Elements[i], written.Elements[i], null, stable: false);

            return supplied;
        }

        value ??= BindExpression(valueSyntax!);
        if (value.Type.IsError()) return false;

        if (target.Kind != DeconstructionKind.Nested)
            return SupplyDeconstructionElement(target, value, stable);

        if (value.Type is TupleTypeSymbol tuple)
        {
            if (!DeconstructionCountsAgree(target, tuple.Elements.Count, $"'{tuple.Name}'", value.Span))
                return false;

            // Storage where what stands for it will be: a name it is held in,
            // or the read itself.
            var whole = new BoundPlaceholder(value.Span, value.Type) { IsStorage = !stable || value.IsLValue };
            target.Supply = DeconstructionSupply.Tuple;
            target.Value = value;
            target.IsStable = stable;
            target.Whole = whole;

            bool supplied = true;
            for (int i = 0; i < tuple.Elements.Count; i++)
            {
                var field = new BoundFieldAccess(value.Span, whole, tuple.Fields[i]);
                supplied &= SupplyDeconstruction(target.Elements[i], null, field, stable: true);
            }

            return supplied;
        }

        if (BindDeconstructCall(value, target.Elements.Count, target.Span) is not var (call, parts))
            return false;

        target.Supply = DeconstructionSupply.Deconstruct;
        target.Value = call;

        bool all = true;
        for (int i = 0; i < parts.Count; i++)
        {
            var part = new BoundLocalAccess(value.Span, parts[i]);
            all &= SupplyDeconstruction(target.Elements[i], null, part, stable: true);
        }

        return all;
    }

    private bool DeconstructionCountsAgree(
        DeconstructionTarget target, int count, string what, SourceSpan span)
    {
        if (target.Elements.Count == count) return true;

        diagnostics.Report(Codes.DeconstructionArityMismatch, span,
            $"{what} has {Counted(count, "element")}, and this names {target.Elements.Count}");
        return false;
    }

    /// <summary>One element given one value, converted to what it is stored as.</summary>
    private bool SupplyDeconstructionElement(DeconstructionTarget target, BoundExpression value, bool stable)
    {
        if (value is BoundArrayDraft loose && target.Type is null)
            value = SettleArrayFromElements(loose);
        if (RefuseUntyped(value)) return false;

        if (value.Type.IsVoid())
        {
            diagnostics.Report(Codes.TupleElementHasNoValue, value.Span,
                "an element of a tuple has to be a value, and this produces none");
            return false;
        }

        if (target.Type is null && !HasOwnType(value))
        {
            diagnostics.Report(Codes.VarCannotInfer, value.Span,
                (target.Kind == DeconstructionKind.Declare ? $"'{target.Name}'" : "a discard") +
                " cannot be a 'var': this takes its type from where it is going, and a 'var' " +
                "is waiting to be told. Write the type in its place");
            return false;
        }

        target.Type ??= value.Type;
        var converted = BindConversion(value, target.Type, value.Span);
        if (converted.Type.IsError()) return false;

        target.Value = converted;
        target.IsStable = stable;
        return true;
    }

    /// <summary>
    /// Declares the locals, left to right, after every value was bound, so no
    /// value can read a name it is about to give a value to. Notes the type
    /// of the last store, and where the whole is read, the tuple of each
    /// nested target's stores.
    /// </summary>
    private void DeclareDeconstructed(
        DeconstructionTarget target, List<BoundLocalDeclaration> declared, bool read, ref TypeSymbol? last)
    {
        switch (target.Kind)
        {
            case DeconstructionKind.Nested:
                foreach (var element in target.Elements)
                    DeclareDeconstructed(element, declared, read, ref last);

                if (read)
                    target.Stored = TupleOf(target.Elements.Select(e => e.Stored ?? e.Type!).ToList());
                break;

            case DeconstructionKind.Declare:
                target.Local = DeclareLocal(target.Name, target.Type!, isConst: false, target.NameSpan);
                declared.Add(new BoundLocalDeclaration(target.NameSpan, target.Local, null));
                last = target.Type;
                break;

            case DeconstructionKind.Place or DeconstructionKind.Property:
                last = target.Type;
                break;
        }
    }

    private static BoundDeconstructionTarget Freeze(DeconstructionTarget target) =>
        new(target.Span, target.Kind, target.Stored ?? target.Type)
        {
            Local = target.Local,
            NameSpan = target.NameSpan,
            Place = target.Place,
            Receiver = target.Receiver,
            Property = target.Property,
            Indices = target.Indices,
            IsNonVirtual = target.IsNonVirtual,
            Elements = target.Elements.Select(Freeze).ToList(),
            Supply = target.Supply,
            Value = target.Value,
            IsStable = target.IsStable,
            Whole = target.Whole,
        };

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

        // Held rather than muted: a call that is kept can still hold an error,
        // such as a 'new(...)' its parameter cannot make, and that is said.
        BoundExpression call;
        List<LocalSymbol> parts;
        List<Diagnostic> said;
        using (var trial = BeginTrial(quiet: false))
        {
            using (var hold = diagnostics.Holding())
            {
                call = BindCallOn(value, member, syntax);
                said = hold.Items;
            }

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
            diagnostics.Report(Codes.ValueCannotBeDeconstructed, value.Span,
                $"'{value.Type.Name}' is not a tuple and has no 'Deconstruct' with " +
                $"{Counted(arity, "'out' parameter")}, so it cannot be taken apart " +
                $"into {arity}",
                value.Type);
            return null;
        }

        foreach (var diagnostic in said)
            diagnostics.Report(diagnostic);

        return (call, parts);
    }
}
