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

using Stainless.Binding;
using Stainless.Source;
using static Stainless.Binding.BoundValues;

namespace Stainless.Lowering;

/// <summary>
/// Matching: a switch statement, a switch expression and <c>is</c>, each
/// built into a <see cref="Decision"/> tree and written out as the core.
///
/// <para>
/// A statement's tree becomes jumps. A run of questions of one value against
/// constants, or of one variant against its cases, is one
/// <see cref="BoundSwitchDispatch"/>, which is one LLVM <c>switch</c>; any
/// other question is an <c>if</c>. An arm that matched goes to its section,
/// and the sections follow the tree, each reached by a label, with
/// <c>break</c> a jump past the last of them.
/// </para>
///
/// <para>
/// An expression's tree becomes conditionals, and a value held while the
/// tree asks about it is a <c>let</c> around what comes after. A result
/// that is a <c>bool</c> -- every <c>is</c> -- is written with <c>&amp;&amp;</c>
/// and <c>||</c> where an answer is a constant.
/// </para>
/// </summary>
public sealed partial class Lowerer
{
    internal static BoundExpression Not(BoundExpression condition) =>
        condition is BoundUnary { Operator: BoundUnaryOp.LogicalNot } negated
            ? negated.Operand
            : new BoundUnary(condition.Span, PrimitiveTypeSymbol.Bool, BoundUnaryOp.LogicalNot, condition);

    /// <summary>
    /// A pattern asked as one condition, true where it matched, with the inputs
    /// it names already standing for something on <paramref name="path"/>.
    /// </summary>
    internal BoundExpression Condition(BoundPattern pattern, DecisionBuilder.Path path)
    {
        switch (pattern)
        {
            case BoundOrPattern either:
                return new BoundBinary(either.Span, PrimitiveTypeSymbol.Bool,
                    Condition(either.Left, path), BoundBinaryOp.LogicalOr, Condition(either.Right, path));

            case BoundNotPattern negated:
                return Not(Condition(negated.Operand, path));
        }

        var tree = new DecisionBuilder(this, total: false).Build(pattern, path);
        return new ExpressionWriter(PrimitiveTypeSymbol.Bool, pattern.Span,
            arm => True(pattern.Span), () => False(pattern.Span)).Write(tree);
    }

    private static BoundLiteral True(SourceSpan span) => new(span, PrimitiveTypeSymbol.Bool, true);
    private static BoundLiteral False(SourceSpan span) => new(span, PrimitiveTypeSymbol.Bool, false);

    // ------------------------------------------------------------ is

    /// <summary>
    /// <c>value is pattern</c>. The value is held once unless it is a name
    /// already, or the pattern reads it only once.
    /// </summary>
    private BoundExpression LowerIsPattern(BoundIsPattern matched)
    {
        var value = Rewrite(matched.Subject);
        var pattern = Rewrite(matched.Pattern);

        LocalSymbol? held = null;
        BoundExpression subject = value;

        if (NarrowableSubject(value) is null && !AsksOnce(pattern))
        {
            held = Synthetic("is", value.Type);
            subject = new BoundLocalAccess(matched.Subject.Span, held);
        }

        var tree = new DecisionBuilder(this, total: false)
            .Build([new DecisionArm(0, pattern, null)], matched.Input, subject);
        var test = new ExpressionWriter(PrimitiveTypeSymbol.Bool, matched.Span,
            arm => True(matched.Span), () => False(matched.Span)).Write(tree);

        if (held is null)
            return test;

        // Borrowed where the name is given its value before anything but the
        // type test has run: the name keeps a reference of its own from then
        // on, and nothing before it could have released the one borrowed.
        return new BoundLet(matched.Span, held, value, test)
        {
            IsOwned = !IsMade(value) &&
                      (value.Type.NeedsArc() && !matched.BindsAtOnce ||
                       value.Type is StructTypeSymbol or FixedArrayTypeSymbol),
        };
    }

    /// <summary>Whether a pattern reads its input once at most, so it need not be held.</summary>
    private static bool AsksOnce(BoundPattern pattern) => pattern switch
    {
        BoundDiscardPattern or BoundTestPattern => true,
        BoundNotPattern negated => AsksOnce(negated.Operand),
        _ => false,
    };

    // ------------------------------------------------------------ switch expression

    /// <summary>
    /// <c>value switch { ... }</c>: the value held in a name unless it is one,
    /// and the tree its arms make, as conditionals.
    /// </summary>
    private BoundExpression LowerSwitchExpression(BoundSwitchExpression chosen)
    {
        var value = Rewrite(chosen.Subject);
        var arms = new List<DecisionArm>(chosen.Arms.Count);
        var values = new List<BoundExpression>(chosen.Arms.Count);

        for (int i = 0; i < chosen.Arms.Count; i++)
        {
            var arm = chosen.Arms[i];
            arms.Add(new DecisionArm(i, Rewrite(arm.Pattern), RewriteOptional(arm.Guard)));
            values.Add(Rewrite(arm.Value));
        }

        LocalSymbol? held = null;
        BoundExpression subject = value;

        if (NarrowableSubject(value) is null)
        {
            held = Synthetic("switch", value.Type, isConst: true);
            subject = new BoundLocalAccess(chosen.Subject.Span, held);
        }

        var tree = new DecisionBuilder(this, chosen.IsTotal).Build(arms, chosen.Input, subject);
        var unmatched = () => (BoundExpression)new BoundUnmatchedSwitch(chosen.Span, chosen.Type, value.Type);

        BoundExpression result;
        if (LeavesOf(tree).GroupBy(leaf => leaf.Arm).All(arm => arm.Count() == 1))
        {
            result = new ExpressionWriter(chosen.Type, chosen.Span, arm => values[arm], unmatched)
                .Write(tree);
        }
        else
        {
            // An arm reached from more than one place is chosen by number,
            // so its value is written once.
            var chosenArm = Synthetic("arm", PrimitiveTypeSymbol.Int);
            var number = new ExpressionWriter(PrimitiveTypeSymbol.Int, chosen.Span,
                arm => Number(chosen.Span, arm), () => Number(chosen.Span, values.Count)).Write(tree);

            BoundExpression select = unmatched();
            for (int i = values.Count - 1; i >= 0; i--)
                select = new BoundConditional(chosen.Arms[i].Span, chosen.Type,
                    new BoundBinary(chosen.Arms[i].Span, PrimitiveTypeSymbol.Bool,
                        new BoundLocalAccess(chosen.Span, chosenArm), BoundBinaryOp.Equal,
                        Number(chosen.Span, i)),
                    values[i], select);

            result = new BoundLet(chosen.Span, chosenArm, number, select);
        }

        return held is null ? result : new BoundLet(chosen.Span, held, value, result);
    }

    private static BoundLiteral Number(SourceSpan span, int value) =>
        new(span, PrimitiveTypeSymbol.Int, (ulong)value);

    private static IEnumerable<LeafDecision> LeavesOf(Decision decision)
    {
        switch (decision)
        {
            case TestDecision test:
                foreach (var leaf in LeavesOf(test.WhenTrue).Concat(LeavesOf(test.WhenFalse)))
                    yield return leaf;
                break;

            case HoldDecision hold:
                foreach (var leaf in LeavesOf(hold.Next))
                    yield return leaf;
                break;

            case EffectDecision effect:
                foreach (var leaf in LeavesOf(effect.Next))
                    yield return leaf;
                break;

            case LeafDecision leaf:
                yield return leaf;
                if (leaf.GuardFailed is { } rest)
                    foreach (var later in LeavesOf(rest))
                        yield return later;
                break;
        }
    }

    /// <summary>Writes a tree as one expression of a given type.</summary>
    private sealed class ExpressionWriter(
        TypeSymbol type, SourceSpan span,
        Func<int, BoundExpression> matched, Func<BoundExpression> unmatched)
    {
        public BoundExpression Write(Decision decision)
        {
            switch (decision)
            {
                case TestDecision test:
                    return Choose(test.Condition, Write(test.WhenTrue), Write(test.WhenFalse));

                case HoldDecision hold:
                {
                    var next = Write(hold.Next);
                    return new BoundLet(hold.Value.Span, hold.Local, hold.Value, next)
                    {
                        IsOwned = hold.Holding == Holding.Owned && !IsMade(hold.Value),
                    };
                }

                case EffectDecision effect:
                    return new BoundSequence(effect.Effect.Span, [effect.Effect], Write(effect.Next));

                case LeafDecision leaf:
                {
                    var value = matched(leaf.Arm);
                    if (leaf.Guard is { } guard)
                        value = Choose(guard, value, Write(leaf.GuardFailed!));

                    if (leaf.Bindings.Count == 0)
                        return value;

                    var stores = leaf.Bindings
                        .Select(b => (BoundExpression)new BoundAssignment(
                            b.Value.Span, new BoundLocalAccess(b.Value.Span, b.Local), b.Value)
                        {
                            DeclaresLocal = b.Local,
                        })
                        .ToList();
                    return new BoundSequence(leaf.Bindings[0].Value.Span, stores, value);
                }

                case NoMatchDecision:
                    return unmatched();

                default:
                    throw new InternalCompilerError(
                        $"lowering has no case for the decision {decision.GetType().Name}", span);
            }
        }

        /// <summary>
        /// <c>condition ? whenTrue : whenFalse</c>, written with <c>&amp;&amp;</c>,
        /// <c>||</c> or <c>!</c> where the value is a <c>bool</c> and an arm a constant.
        /// </summary>
        private BoundExpression Choose(BoundExpression condition, BoundExpression whenTrue, BoundExpression whenFalse)
        {
            if (type.IsBool())
            {
                bool? yes = Constant(whenTrue);
                bool? no = Constant(whenFalse);

                if (yes == true && no == false)
                    return condition;
                if (yes == false && no == true)
                    return Not(condition);
                if (no == false)
                    return Logical(condition, BoundBinaryOp.LogicalAnd, whenTrue);
                if (yes == true)
                    return Logical(condition, BoundBinaryOp.LogicalOr, whenFalse);
            }

            return new BoundConditional(condition.Span, type, condition, whenTrue, whenFalse);
        }

        private static bool? Constant(BoundExpression value) =>
            value is BoundLiteral { Value: bool constant } ? constant : null;

        private static BoundBinary Logical(BoundExpression left, BoundBinaryOp op, BoundExpression right) =>
            new(left.Span, PrimitiveTypeSymbol.Bool, left, op, right);
    }

    // ------------------------------------------------------------ switch statement

    /// <summary>
    /// A switch statement: the value held unless it is a name already, the
    /// tree its labels make as jumps, then its sections.
    /// </summary>
    private BoundStatement LowerSwitch(BoundSwitch chosen)
    {
        var value = Rewrite(chosen.Subject);
        var statements = new List<BoundStatement>();
        var block = new BoundBlock(chosen.Span, statements);

        BoundExpression subject = value;

        // A name is read where it is. So is a constant, and an integer that
        // is steady to read again; anything else is read once and held for
        // every question.
        bool ordinal = value.Type is PrimitiveTypeSymbol { IsInteger: true } or EnumTypeSymbol ||
                       value.Type.IsBool();
        if (ordinal ? !IsSteadyRead(value) : NarrowableSubject(value) is null)
        {
            var held = Synthetic("switch", value.Type, isConst: true);
            statements.Add(new BoundLocalDeclaration(chosen.Subject.Span, held, value));
            block.Locals.Add(held);
            subject = new BoundLocalAccess(chosen.Subject.Span, held);
        }

        var end = ForwardLabel("switch.end");
        var targets = new List<LabelSymbol>();
        var arms = new List<DecisionArm>();
        var sectionOf = new List<int>();
        LabelSymbol? otherwise = null;

        for (int i = 0; i < chosen.Sections.Count; i++)
        {
            var section = chosen.Sections[i];
            targets.Add(section.Entry ?? ForwardLabel("switch.section"));
            if (section.IsDefault)
                otherwise = targets[i];

            foreach (var label in section.Labels)
            {
                arms.Add(new DecisionArm(arms.Count, Rewrite(label.Pattern), RewriteOptional(label.Guard)));
                sectionOf.Add(i);
            }
        }

        var tree = new DecisionBuilder(this, total: false).Build(arms, chosen.Input, subject);
        var inSection = NamedInSection(tree, arms);

        // What a label names where the value would not outlive the jump to
        // its section lives as long as the switch, and is given its value
        // once on any path before the jump.
        foreach (var named in arms
                     .Where(a => !inSection.ContainsKey(a.Index))
                     .SelectMany(a => DeclaredBy(a.Pattern))
                     .Distinct())
        {
            statements.Add(new BoundLocalDeclaration(chosen.Span, named, null));
            block.Locals.Add(named);
        }

        var writer = new StatementWriter(
            chosen.Span, arm => targets[sectionOf[arm]], otherwise ?? end, inSection.ContainsKey);
        writer.Write(tree, statements);

        var jumps = new BreakRewriter(end);
        for (int i = 0; i < chosen.Sections.Count; i++)
        {
            var section = chosen.Sections[i];
            var body = jumps.Rewrite(Rewrite(section.Body));

            // Anything else a label names is the section's own, declared as
            // it begins, and let go of where the section ends.
            int index = sectionOf.IndexOf(i);
            if (index >= 0 && inSection.TryGetValue(index, out var bindings))
            {
                var opened = new BoundBlock(section.Span,
                [
                    .. bindings.Select(b => (BoundStatement)new BoundLocalDeclaration(b.Value.Span, b.Local, b.Value)),
                    body,
                ]);
                opened.Locals.AddRange(bindings.Select(b => b.Local));
                body = opened;
            }

            statements.Add(new BoundLabel(section.Span, targets[i]));
            statements.Add(body);
        }

        statements.Add(new BoundLabel(chosen.Span, end));
        return block;
    }

    /// <summary>
    /// The arms whose names can be given their values where their section
    /// begins, rather than before the jump there: an arm with no guard to read
    /// them first, whose every path gives each name the same value, read from
    /// what the switch holds rather than from a value the tree held on the way.
    /// That is every <c>case Circle c:</c>, and it keeps the name the
    /// section's, as a declaration in it would be.
    /// </summary>
    private static Dictionary<int, IReadOnlyList<(LocalSymbol Local, BoundExpression Value)>> NamedInSection(
        Decision tree, IReadOnlyList<DecisionArm> arms)
    {
        var passing = new HashSet<LocalSymbol>();
        CollectPassing(tree, passing);

        var named = new Dictionary<int, IReadOnlyList<(LocalSymbol Local, BoundExpression Value)>>();

        foreach (var arm in arms)
        {
            if (arm.Guard is not null)
                continue;

            var leaves = LeavesOf(tree).Where(l => l.Arm == arm.Index).ToList();
            if (leaves.Count == 0 || leaves[0].Bindings.Count == 0)
                continue;

            var first = leaves[0].Bindings;
            bool steady = first.All(b => ExpressionKey.Of(b.Value) is not null && !Reads(b.Value, passing)) &&
                          leaves.All(l => l.Bindings.Count == first.Count &&
                                          l.Bindings.Zip(first).All(pair =>
                                              ReferenceEquals(pair.First.Local, pair.Second.Local) &&
                                              Equals(ExpressionKey.Of(pair.First.Value),
                                                     ExpressionKey.Of(pair.Second.Value))));
            if (steady)
                named[arm.Index] = first;
        }

        return named;
    }

    /// <summary>The names the tree holds values in on the way, which are gone once it jumps.</summary>
    private static void CollectPassing(Decision decision, HashSet<LocalSymbol> into)
    {
        switch (decision)
        {
            case TestDecision test:
                CollectPassing(test.WhenTrue, into);
                CollectPassing(test.WhenFalse, into);
                break;

            case HoldDecision hold:
                into.Add(hold.Local);
                CollectPassing(hold.Next, into);
                break;

            case EffectDecision effect:
                into.UnionWith(Declared(effect.Effect));
                CollectPassing(effect.Next, into);
                break;

            case LeafDecision { GuardFailed: { } rest }:
                CollectPassing(rest, into);
                break;
        }
    }

    private static IEnumerable<LocalSymbol> Declared(BoundExpression expression)
    {
        var finder = new DeclarationFinder();
        finder.Visit(expression);
        return finder.Found;
    }

    private static bool Reads(BoundExpression expression, HashSet<LocalSymbol> locals) =>
        locals.Any(local => LocalUseCounter.Uses(expression, local) > 0);

    /// <summary>The locals an expression brings into being as it runs: an <c>out var</c>, a name a pattern binds.</summary>
    private sealed class DeclarationFinder : BoundTreeWalker
    {
        public List<LocalSymbol> Found { get; } = [];

        public override void Visit(BoundExpression? expression)
        {
            switch (expression)
            {
                case BoundAddressOf { DeclaresLocal: { } introduced }:
                    Found.Add(introduced);
                    break;
                case BoundAssignment { DeclaresLocal: { } assigned }:
                    Found.Add(assigned);
                    break;
            }

            base.Visit(expression);
        }
    }

    /// <summary>A label only jumps from before it reach.</summary>
    private LabelSymbol ForwardLabel(string name) => new($"{name}.{_synthetic++}") { IsForwardOnly = true };

    /// <summary>The locals a pattern gives values to.</summary>
    private static IEnumerable<LocalSymbol> DeclaredBy(BoundPattern pattern) => pattern switch
    {
        BoundDeclarationPattern named => [named.Local],
        BoundReadPattern read => DeclaredBy(read.Pattern),
        BoundAndPattern both => both.Parts.SelectMany(DeclaredBy),
        BoundOrPattern either => DeclaredBy(either.Left).Concat(DeclaredBy(either.Right)),
        BoundNotPattern negated => DeclaredBy(negated.Operand),
        _ => [],
    };

    /// <summary>Writes a tree as statements that end every path in a jump.</summary>
    private sealed class StatementWriter(
        SourceSpan span, Func<int, LabelSymbol> target, LabelSymbol unmatched, Func<int, bool> namedInSection)
    {
        public void Write(Decision decision, List<BoundStatement> into)
        {
            switch (decision)
            {
                case TestDecision test when Dispatchable(test) is { } run:
                    WriteDispatch(test, run, into);
                    break;

                case TestDecision test:
                    into.Add(new BoundIf(test.Condition.Span, test.Condition,
                        Block(test.WhenTrue), Block(test.WhenFalse)));
                    break;

                // A block of its own, so a jump out of what follows lets go
                // of what the name holds.
                case HoldDecision hold:
                {
                    var inner = new List<BoundStatement>
                    {
                        new BoundLocalDeclaration(hold.Value.Span, hold.Local, hold.Value)
                        {
                            IsBorrowed = hold.Holding == Holding.Borrowed,
                        },
                    };
                    Write(hold.Next, inner);

                    var block = new BoundBlock(hold.Value.Span, inner);
                    block.Locals.Add(hold.Local);
                    into.Add(block);
                    break;
                }

                case EffectDecision effect:
                {
                    var inner = new List<BoundStatement> { new BoundExpressionStatement(effect.Effect.Span, effect.Effect) };
                    Write(effect.Next, inner);
                    into.Add(new BoundBlock(effect.Effect.Span, inner));
                    break;
                }

                case LeafDecision leaf:
                {
                    foreach (var (local, value) in namedInSection(leaf.Arm) ? [] : leaf.Bindings)
                        into.Add(new BoundExpressionStatement(value.Span,
                            new BoundAssignment(value.Span, new BoundLocalAccess(value.Span, local), value)
                            {
                                IsInitialization = true,
                            }));

                    var jump = new BoundGoto(span, target(leaf.Arm));
                    if (leaf.Guard is { } guard)
                        into.Add(new BoundIf(guard.Span, guard, jump, Block(leaf.GuardFailed!)));
                    else
                        into.Add(jump);
                    break;
                }

                case NoMatchDecision:
                    into.Add(new BoundGoto(span, unmatched));
                    break;

                default:
                    throw new InternalCompilerError(
                        $"lowering has no case for the decision {decision.GetType().Name}", span);
            }
        }

        private BoundStatement Block(Decision decision)
        {
            var inner = new List<BoundStatement>();
            Write(decision, inner);
            return inner.Count == 1 ? inner[0] : new BoundBlock(span, inner);
        }

        /// <summary>
        /// The run of questions of one value against constants or cases that
        /// starts here, each asked where the one before said no; or null.
        /// </summary>
        private static List<TestDecision>? Dispatchable(TestDecision first)
        {
            if (first.Question is not { } question || !CanDispatch(question))
                return null;

            var run = new List<TestDecision> { first };
            var seen = new HashSet<object?> { question.Value };

            while (run[^1].No is TestDecision next &&
                   next.Question is { } asked &&
                   asked.Kind == question.Kind &&
                   asked.Subject.Equals(question.Subject) &&
                   seen.Add(asked.Value))
                run.Add(next);

            return run;
        }

        private static bool CanDispatch(Question question) => question.Kind switch
        {
            PatternTestKind.Case => question.Asked.Type is VariantTypeSymbol,
            PatternTestKind.Constant => question.Value is ulong &&
                (question.Asked.Type is PrimitiveTypeSymbol { IsInteger: true } or EnumTypeSymbol ||
                 question.Asked.Type.IsBool()),
            _ => false,
        };

        private void WriteDispatch(TestDecision first, List<TestDecision> run, List<BoundStatement> into)
        {
            var arms = new List<BoundDispatchArm>();
            var bodies = new List<(LabelSymbol Label, Decision Decision)>();

            foreach (var test in run)
            {
                var label = new LabelSymbol("dispatch") { IsForwardOnly = true };
                var asked = test.Question!;
                arms.Add(asked.Kind == PatternTestKind.Case
                    ? new BoundDispatchArm(0, (VariantCaseSymbol)asked.Value!, label)
                    : new BoundDispatchArm((ulong)asked.Value!, null, label));
                bodies.Add((label, test.Yes));
            }

            var otherwise = new LabelSymbol("dispatch.default") { IsForwardOnly = true };
            bodies.Add((otherwise, run[^1].No));

            into.Add(new BoundSwitchDispatch(first.Condition.Span, first.Question!.Asked, arms, otherwise));

            foreach (var (label, decision) in bodies)
            {
                into.Add(new BoundLabel(span, label));
                Write(decision, into);
            }
        }
    }

    /// <summary>
    /// A switch section's <c>break</c>, as the jump past the switch it means.
    /// A loop inside the section has breaks of its own, and is left alone.
    /// </summary>
    private sealed class BreakRewriter(LabelSymbol end) : BoundTreeRewriter
    {
        public override BoundStatement Rewrite(BoundStatement statement) => statement switch
        {
            BoundBreak => new BoundGoto(statement.Span, end),
            BoundWhile or BoundDoWhile or BoundFor or BoundForEach or BoundParallelFor or BoundParallel => statement,
            _ => base.Rewrite(statement),
        };

        // A statement inside an expression is a return, never a break.
        public override BoundExpression Rewrite(BoundExpression expression) => expression;
    }
}
