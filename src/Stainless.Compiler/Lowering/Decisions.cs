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
/// The decision tree a list of arms becomes: which question is asked next,
/// which value is read and held, and which arm is chosen where.
///
/// <para>
/// Every construct that matches -- a switch statement, a switch expression,
/// <c>is</c> -- is a list of arms, each a pattern with a guard, and is built
/// into one of these by <see cref="DecisionBuilder"/>. Only what the tree is
/// written out as differs: a statement's jumps and dispatches, or an
/// expression's conditionals.
/// </para>
/// </summary>
internal abstract class Decision;

/// <summary>A question, and where each answer goes.</summary>
/// <param name="Question">
/// What is asked, where it can be compared with another question -- the value
/// asked about and what is asked of it -- or null.
/// </param>
/// <param name="YesWhenTrue">Whether the condition is true where the answer to the question is yes.</param>
internal sealed class TestDecision(
    BoundExpression condition, Decision whenTrue, Decision whenFalse,
    Question? question, bool yesWhenTrue) : Decision
{
    public BoundExpression Condition { get; } = condition;
    public Decision WhenTrue { get; } = whenTrue;
    public Decision WhenFalse { get; } = whenFalse;
    public Question? Question { get; } = question;
    public bool YesWhenTrue { get; } = yesWhenTrue;

    public Decision Yes => YesWhenTrue ? WhenTrue : WhenFalse;
    public Decision No => YesWhenTrue ? WhenFalse : WhenTrue;
}

/// <summary>A value read once and held under a name for what comes after.</summary>
internal sealed class HoldDecision(LocalSymbol local, BoundExpression value, Holding holding, Decision next)
    : Decision
{
    public LocalSymbol Local { get; } = local;
    public BoundExpression Value { get; } = value;
    public Holding Holding { get; } = holding;
    public Decision Next { get; } = next;
}

/// <summary>Something done for what it leaves behind: a <c>Deconstruct</c>'s call.</summary>
internal sealed class EffectDecision(BoundExpression effect, Decision next) : Decision
{
    public BoundExpression Effect { get; } = effect;
    public Decision Next { get; } = next;
}

/// <summary>
/// An arm whose pattern matched: the names it gives, then its guard, and
/// where to go on when the guard says no.
/// </summary>
internal sealed class LeafDecision(
    int arm, IReadOnlyList<(LocalSymbol Local, BoundExpression Value)> bindings,
    BoundExpression? guard, Decision? guardFailed) : Decision
{
    public int Arm { get; } = arm;
    public IReadOnlyList<(LocalSymbol Local, BoundExpression Value)> Bindings { get; } = bindings;
    public BoundExpression? Guard { get; } = guard;
    public Decision? GuardFailed { get; } = guardFailed;
}

/// <summary>No arm matched.</summary>
internal sealed class NoMatchDecision : Decision
{
    public static readonly NoMatchDecision Instance = new();
}

/// <summary>How a held value counts.</summary>
internal enum Holding
{
    /// <summary>Nothing to count: a number, a pointer.</summary>
    Uncounted,

    /// <summary>A +1 of its own: retained when it was borrowed, moved when it was made.</summary>
    Owned,

    /// <summary>
    /// Borrowed from what it views, which outlives it: an object seen as a
    /// class it was found to be.
    /// </summary>
    Borrowed,
}

/// <summary>What a test asks of which value, compared by what they are rather than by which object.</summary>
internal sealed record Question(ExpressionKey Subject, PatternTestKind Kind, object? Value, BoundExpression Asked);

/// <summary>One arm to be matched: a pattern, a guard, and which arm it is.</summary>
internal sealed record DecisionArm(int Index, BoundPattern Pattern, BoundExpression? Guard);

/// <summary>
/// Builds the tree for a list of arms.
///
/// <para>
/// The arms are tried in order, and each is asked its questions in the order
/// its pattern wrote them. What makes it a tree rather than a chain is that a
/// question is asked once on any path: an answer is remembered, and a later
/// arm that asks the same thing of the same value -- or something the answer
/// settles, such as another case of a variant already known to be this one --
/// has it answered without asking. A value read from the subject is read once
/// on any path, and held when reading it again would not be free.
/// </para>
///
/// <para>
/// A pattern under <c>or</c> or <c>not</c> that is more than one question is
/// asked as a whole, as one condition. It is rare, and taking it apart would
/// buy nothing a single test does not.
/// </para>
///
/// <para>
/// A tree can repeat itself where two paths reach the same later question,
/// and in the worst case it grows with the product of what the arms ask. Past
/// <see cref="Budget"/> decisions it is built again with each arm asked as one
/// condition, which is the chain every arm would be without sharing, and
/// grows with the arms.
/// </para>
/// </summary>
internal sealed class DecisionBuilder(Lowerer lowerer, bool total)
{
    /// <summary>How many decisions a tree may hold before the arms are asked whole.</summary>
    private const int Budget = 4096;

    private int _made;

    /// <summary>
    /// The tree for <paramref name="arms"/>, matching <paramref name="subject"/>
    /// as <paramref name="input"/> names it.
    /// </summary>
    public Decision Build(IReadOnlyList<DecisionArm> arms, BoundPatternInput input, BoundExpression subject)
    {
        var start = new Path();
        start.Values[input] = subject;

        _made = 0;
        var tree = Build(Begin(arms, whole: false), start);
        return _made <= Budget ? tree : Build(Begin(arms, whole: true), start);
    }

    /// <summary>
    /// The tree for one pattern whose inputs a path has already named. One
    /// arm is a chain whatever it asks, so it is never asked whole.
    /// </summary>
    public Decision Build(BoundPattern pattern, Path path) =>
        Build(Begin([new DecisionArm(0, pattern, null)], whole: false), path);

    private static List<ArmState> Begin(IReadOnlyList<DecisionArm> arms, bool whole)
    {
        var states = new List<ArmState>(arms.Count);

        foreach (var arm in arms)
        {
            var steps = new List<Step>();
            if (whole)
                steps.Add(new WholeStep(arm.Pattern));
            else
                Flatten(arm.Pattern, steps);

            states.Add(new ArmState(arm.Index, steps, 0, arm.Guard, [], arm.Index == arms[^1].Index));
        }

        return states;
    }

    // ------------------------------------------------------------ steps

    private abstract record Step;

    /// <summary>A value read from the inputs, which <see cref="Output"/> then names.</summary>
    private sealed record ReadStep(BoundPatternInput Output, BoundExpression Read) : Step;

    private sealed record TestStep(BoundPatternInput Input, BoundExpression Test, PatternTestKey? Key, bool Negated)
        : Step;

    private sealed record EffectStep(BoundExpression Effect) : Step;

    private sealed record BindStep(LocalSymbol Local, BoundExpression Value) : Step;

    /// <summary>A pattern asked as one condition; the names it gives are given inside it.</summary>
    private sealed record WholeStep(BoundPattern Pattern, bool Negated = false) : Step;

    /// <summary>A pattern as the steps it asks and reads in, in order.</summary>
    private static void Flatten(BoundPattern pattern, List<Step> into)
    {
        switch (pattern)
        {
            case BoundDiscardPattern:
                break;

            case BoundDeclarationPattern named:
                into.Add(new BindStep(named.Local, named.Value));
                break;

            case BoundTestPattern test:
                into.Add(new TestStep(test.Input, test.Test, test.Key, false));
                break;

            case BoundReadPattern read:
                into.Add(new ReadStep(read.Input, read.Read));
                Flatten(read.Pattern, into);
                break;

            case BoundEffectPattern effect:
                into.Add(new EffectStep(effect.Effect));
                break;

            case BoundAndPattern both:
                foreach (var part in both.Parts)
                    Flatten(part, into);
                break;

            case BoundNotPattern { Operand: BoundTestPattern test }:
                into.Add(new TestStep(test.Input, test.Test, test.Key, true));
                break;

            case BoundNotPattern negated:
                into.Add(new WholeStep(negated.Operand, Negated: true));
                break;

            case BoundOrPattern:
                into.Add(new WholeStep(pattern));
                break;

            default:
                throw new InternalCompilerError(
                    $"lowering has no case for the pattern {pattern.GetType().Name}", pattern.Span);
        }
    }

    // ------------------------------------------------------------ paths

    /// <summary>What an arm has left to ask, and the names it has been given so far.</summary>
    private sealed record ArmState(
        int Index, List<Step> Steps, int At, BoundExpression? Guard,
        IReadOnlyList<BindStep> Bindings, bool IsLast)
    {
        public Step? Next => At < Steps.Count ? Steps[At] : null;

        public ArmState Advance() => this with { At = At + 1 };
    }

    /// <summary>
    /// What is known at one place in the tree: what each input stands for,
    /// what has been read, and what each question was answered.
    /// </summary>
    internal sealed class Path
    {
        public Dictionary<BoundPatternInput, BoundExpression> Values { get; } = [];
        public Dictionary<ExpressionKey, BoundExpression> Reads { get; } = [];
        public Dictionary<(ExpressionKey, PatternTestKind, object?), bool> Answers { get; } = [];

        public Path Copy()
        {
            var copy = new Path();
            foreach (var (input, value) in Values) copy.Values[input] = value;
            foreach (var (read, value) in Reads) copy.Reads[read] = value;
            foreach (var (question, answer) in Answers) copy.Answers[question] = answer;
            return copy;
        }

        /// <summary>What the question's answer is here, when anything asked before settles it.</summary>
        public bool? Known(ExpressionKey subject, PatternTestKind kind, object? value)
        {
            if (Answers.TryGetValue((subject, kind, value), out bool answer))
                return answer;

            // A variant holds one case, a value equals one constant, and
            // equal to a constant is not null.
            foreach (var ((asked, askedKind, askedValue), yes) in Answers)
            {
                if (!yes || !asked.Equals(subject))
                    continue;

                if (askedKind == kind && kind is PatternTestKind.Case or PatternTestKind.Constant &&
                    !Equals(askedValue, value))
                    return false;

                if (askedKind == PatternTestKind.Constant && kind == PatternTestKind.Null)
                    return false;
            }

            return null;
        }
    }

    // ------------------------------------------------------------ building

    private Decision Build(List<ArmState> arms, Path path)
    {
        _made++;

        if (arms.Count == 0)
            return NoMatchDecision.Instance;

        var arm = arms[0];

        // Covered by the arms, the last is reached only by what it matches,
        // so it is not asked: only read from, for the names it gives.
        if (total && arm.IsLast && arms.Count == 1 && arm.Guard is null &&
            arm.Steps.Skip(arm.At).Any(IsQuestion))
        {
            arm = arm with { Steps = [.. arm.Steps.Skip(arm.At).Where(s => !IsQuestion(s))], At = 0 };
            arms = [arm];
        }

        switch (arm.Next)
        {
            case null:
            {
                var bindings = arm.Bindings
                    .Select(b => (b.Local, Substitute(b.Value, path)))
                    .ToList();

                return arm.Guard is null
                    ? new LeafDecision(arm.Index, bindings, null, null)
                    : new LeafDecision(arm.Index, bindings, arm.Guard, Build([.. arms.Skip(1)], path));
            }

            case BindStep bind:
                return Build(Replace(arms, arm.Advance() with { Bindings = [.. arm.Bindings, bind] }), path);

            case EffectStep effect:
                return new EffectDecision(Substitute(effect.Effect, path), Build(Replace(arms, arm.Advance()), path));

            case ReadStep read:
                return BuildRead(read, arms, path);

            case TestStep test:
                return BuildTest(test, arms, path);

            case WholeStep whole:
            {
                var condition = lowerer.Condition(whole.Pattern, path);
                if (whole.Negated)
                    condition = Lowerer.Not(condition);

                var rest = arms.Skip(1).ToList();
                return new TestDecision(condition,
                    Build(Replace(arms, arm.Advance()), path.Copy()),
                    Build(rest, path.Copy()),
                    null, yesWhenTrue: true);
            }

            default:
                throw new InternalCompilerError($"lowering has no case for the step {arm.Next.GetType().Name}");
        }
    }

    /// <summary>A step that only asks, which a match that is certain can leave out.</summary>
    private static bool IsQuestion(Step step) =>
        step is TestStep || step is WholeStep whole && !Declares(whole.Pattern);

    private static bool Declares(BoundPattern pattern) => pattern switch
    {
        BoundDeclarationPattern => true,
        BoundReadPattern read => Declares(read.Pattern),
        BoundAndPattern both => both.Parts.Any(Declares),
        BoundOrPattern either => Declares(either.Left) || Declares(either.Right),
        BoundNotPattern negated => Declares(negated.Operand),
        _ => false,
    };

    private static List<ArmState> Replace(List<ArmState> arms, ArmState first)
    {
        var replaced = new List<ArmState>(arms) { [0] = first };
        return replaced;
    }

    private Decision BuildRead(ReadStep read, List<ArmState> arms, Path path)
    {
        var arm = arms[0];
        var value = Substitute(read.Read, path);
        var key = ExpressionKey.Of(value);

        if (key is not null && path.Reads.TryGetValue(key, out var known))
        {
            var reused = path.Copy();
            reused.Values[read.Output] = known;
            return Build(Replace(arms, arm.Advance()), reused);
        }

        var next = path.Copy();

        if (IsSteadyRead(value))
        {
            next.Values[read.Output] = value;
            if (key is not null)
                next.Reads[key] = value;
            return Build(Replace(arms, arm.Advance()), next);
        }

        var local = lowerer.Synthetic("matched", value.Type);
        var held = new BoundLocalAccess(value.Span, local);
        next.Values[read.Output] = held;
        if (key is not null)
            next.Reads[key] = held;

        return new HoldDecision(local, value, HoldingOf(value), Build(Replace(arms, arm.Advance()), next));
    }

    /// <summary>
    /// How a held value counts. Owned unless this statement made it or it
    /// only views a steady value: a getter called by a later part of the
    /// pattern may release what a field read borrowed.
    /// </summary>
    private static Holding HoldingOf(BoundExpression value)
    {
        bool counted = value.Type.NeedsArc() || value.Type is StructTypeSymbol or FixedArrayTypeSymbol;
        if (!counted)
            return Holding.Uncounted;

        return IsSteadyConversion(value) ? Holding.Borrowed : Holding.Owned;
    }

    private Decision BuildTest(TestStep test, List<ArmState> arms, Path path)
    {
        var arm = arms[0];
        var subject = path.Values.TryGetValue(test.Input, out var value)
            ? value
            : throw new InternalCompilerError("a pattern asks about a value nothing read", test.Test.Span);

        var subjectKey = test.Key is null ? null : ExpressionKey.Of(subject);

        // Negated twice over -- `not (x != null)` -- is the question itself.
        bool negated = test.Negated != (test.Key?.Negated ?? false);

        if (subjectKey is not null && path.Known(subjectKey, test.Key!.Kind, test.Key.Value) is bool answer)
        {
            bool passes = answer != negated;
            return passes
                ? Build(Replace(arms, arm.Advance()), path)
                : Build([.. arms.Skip(1)], path);
        }

        var condition = Substitute(test.Test, path);
        if (test.Negated)
            condition = Lowerer.Not(condition);

        var whenTrue = path.Copy();
        var whenFalse = path.Copy();
        Question? question = null;

        if (subjectKey is not null)
        {
            var asked = (subjectKey, test.Key!.Kind, test.Key.Value);
            whenTrue.Answers[asked] = !negated;
            whenFalse.Answers[asked] = negated;
            question = new Question(subjectKey, test.Key.Kind, test.Key.Value, subject);
        }

        return new TestDecision(condition,
            Build(Replace(arms, arm.Advance()), whenTrue),
            Build([.. arms.Skip(1)], whenFalse),
            question, yesWhenTrue: !negated);
    }

    /// <summary>An expression from a pattern, with each input it names replaced by what stands for it here.</summary>
    public static BoundExpression Substitute(BoundExpression expression, Path path) =>
        new InputReplacer(path).Rewrite(expression);

    private sealed class InputReplacer(Path path) : BoundTreeRewriter
    {
        public override BoundExpression Rewrite(BoundExpression expression) =>
            expression is BoundPatternInput input
                ? path.Values.TryGetValue(input, out var value)
                    ? value
                    : throw new InternalCompilerError("a pattern reads a value nothing read", input.Span)
                : base.Rewrite(expression);
    }
}

/// <summary>
/// A value's identity for the tree: two reads are the same read, and two
/// questions ask about the same value, when their keys are equal. Only reads
/// that give the same answer asked twice have one; anything else has none,
/// and is never taken for another.
/// </summary>
internal sealed class ExpressionKey : IEquatable<ExpressionKey>
{
    private readonly object?[] _parts;
    private readonly int _hash;

    private ExpressionKey(params object?[] parts)
    {
        _parts = parts;

        var hash = new HashCode();
        foreach (var part in parts)
            hash.Add(part);
        _hash = hash.ToHashCode();
    }

    public static ExpressionKey? Of(BoundExpression? expression)
    {
        switch (expression)
        {
            case null:
                return null;
            case BoundLocalAccess local:
                return new ExpressionKey("local", local.Local);
            case BoundParameterAccess parameter:
                return new ExpressionKey("parameter", parameter.Parameter);
            case BoundThis self:
                return new ExpressionKey("this", self.Parameter);
            case BoundLiteral literal:
                return new ExpressionKey("literal", literal.Type, literal.Value);
            case BoundConstantAccess constant:
                return new ExpressionKey("constant", constant.Constant);
            case BoundNullLiteral nothing:
                return new ExpressionKey("null", nothing.Type);

            case BoundFieldAccess field:
                return field.Receiver is null || Of(field.Receiver) is not null
                    ? new ExpressionKey("field", field.Field, Of(field.Receiver))
                    : null;

            case BoundVariantPayload payload:
                return Of(payload.Receiver) is { } of
                    ? new ExpressionKey("payload", payload.Case, payload.Field, of)
                    : null;

            case BoundConversion conversion:
                return Of(conversion.Operand) is { } operand
                    ? new ExpressionKey("conversion", conversion.Kind, conversion.Type, operand)
                    : null;

            case BoundArrayLength length:
                return Of(length.Array) is { } array ? new ExpressionKey("length", array) : null;

            case BoundIndex index:
                return Of(index.Target) is { } target && Of(index.Index) is { } at
                    ? new ExpressionKey("index", index.Origin, target, at)
                    : null;

            case BoundBinary binary:
                return Of(binary.Left) is { } left && Of(binary.Right) is { } right
                    ? new ExpressionKey("binary", binary.Operator, binary.Type, left, right)
                    : null;

            case BoundSlice slice:
                return Of(slice.Target) is { } sliced &&
                       (slice.Start is null || Of(slice.Start) is not null) &&
                       (slice.End is null || Of(slice.End) is not null)
                    ? new ExpressionKey("slice", slice.StartOrigin, slice.EndOrigin, sliced,
                        Of(slice.Start), Of(slice.End))
                    : null;

            // A getter, an indexer or a Slice: the same call on the same
            // values, which a pattern reads as the same member.
            case BoundCall call:
            {
                var parts = new List<object?> { "call", call.Function, call.IsNonVirtual };
                if (call.Receiver is not null)
                {
                    if (Of(call.Receiver) is not { } receiver)
                        return null;
                    parts.Add(receiver);
                }

                foreach (var argument in call.Arguments)
                {
                    if (Of(argument) is not { } part)
                        return null;
                    parts.Add(part);
                }

                return new ExpressionKey([.. parts]);
            }

            default:
                return null;
        }
    }

    public bool Equals(ExpressionKey? other)
    {
        if (other is null || other._hash != _hash || other._parts.Length != _parts.Length)
            return false;

        for (int i = 0; i < _parts.Length; i++)
            if (!Equals(_parts[i], other._parts[i]))
                return false;

        return true;
    }

    public override bool Equals(object? other) => Equals(other as ExpressionKey);

    public override int GetHashCode() => _hash;
}
