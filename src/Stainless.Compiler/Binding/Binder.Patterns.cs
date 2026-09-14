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
/// Patterns, and the two things written with them: a <c>switch</c> expression,
/// and a <c>case</c> label that is not a constant.
///
/// <para>
/// A pattern is a question about a value, and everything here turns one into
/// the <c>bool</c> that asks it. That is the whole design: there is no matching
/// machinery underneath, only comparisons, tag tests and <c>is</c> -- each of
/// which the language already had, and each of which the emitter already knew
/// how to write.
/// </para>
///
/// <para>
/// A pattern that names something produces that name separately, as the
/// expression it was extracted from. It is used twice where there is a guard:
/// once inside the guard, held in a <see cref="BoundLet"/> so that the
/// extraction happens only after the test said yes, and once in the body, where
/// it is an ordinary local. Both are pure reads of a value that is already
/// held in a name, so the second costs a load and nothing else.
/// </para>
/// </summary>
public sealed partial class Binder
{
    /// <summary>
    /// One pattern, bound against a value: the test that asks it, and the name
    /// it puts in scope where the answer was yes.
    /// </summary>
    private sealed record BoundPattern(
        BoundExpression Test,
        string? Name = null,
        SourceSpan NameSpan = default,
        TypeSymbol? NameType = null,
        BoundExpression? Extraction = null,
        VariantCaseSymbol? Case = null)
    {
        /// <summary>True for a pattern that asks nothing: <c>_</c>.</summary>
        public bool IsIrrefutable => Test is BoundLiteral { Value: true };
    }

    /// <summary>
    /// Turns a pattern into the test it stands for, against a value that may be
    /// read as many times as the pattern needs -- so the caller has already put
    /// it in a name.
    /// </summary>
    private BoundPattern? BindPattern(PatternSyntax syntax, BoundExpression subject)
    {
        switch (syntax)
        {
            case DiscardPatternSyntax discard:
                return new BoundPattern(new BoundLiteral(discard.Span, PrimitiveTypeSymbol.Bool, true));

            case ConstantPatternSyntax constant:
                return BindConstantPattern(constant, subject);

            case RelationalPatternSyntax relational:
            {
                var bound = BindExpression(relational.Value);
                var written = BindConversion(bound, subject.Type, relational.Value.Span);
                if (written.Type.IsError()) return null;

                var (op, token) = (Comparison(relational.Operator), relational.Operator);
                var test = BindBinaryOperation(relational.Span, subject, op, written, token);

                return test.Type.IsError() ? null : new BoundPattern(test);
            }

            case TypePatternSyntax typed:
                return BindTypePattern(typed, subject);

            case NotPatternSyntax negated:
            {
                var inner = BindPattern(negated.Operand, subject);
                if (inner is null) return null;

                if (inner.Name is not null)
                {
                    diagnostics.Error("SL0619", negated.Span,
                        $"'{inner.Name}' is named by a pattern under a 'not', and what a 'not' " +
                        "matches is everything that pattern did not -- so there would be " +
                        "nothing for the name to be");
                    return null;
                }

                return new BoundPattern(new BoundUnary(
                    negated.Span, PrimitiveTypeSymbol.Bool, BoundUnaryOp.LogicalNot, inner.Test));
            }

            case BinaryPatternSyntax combined:
            {
                var left = BindPattern(combined.Left, subject);
                var right = BindPattern(combined.Right, subject);
                if (left is null || right is null) return null;

                if (left.Name is not null || right.Name is not null)
                {
                    diagnostics.Error("SL0619", combined.Span,
                        "a pattern joined with 'and' or 'or' may not name anything: which of " +
                        "the two matched is not known where the name would be used");
                    return null;
                }

                return new BoundPattern(new BoundBinary(
                    combined.Span, PrimitiveTypeSymbol.Bool, left.Test,
                    combined.IsOr ? BoundBinaryOp.LogicalOr : BoundBinaryOp.LogicalAnd,
                    right.Test));
            }

            default:
                return null;
        }
    }

    private static BoundBinaryOp Comparison(TokenKind token) => token switch
    {
        TokenKind.Less => BoundBinaryOp.Less,
        TokenKind.LessEquals => BoundBinaryOp.LessEqual,
        TokenKind.Greater => BoundBinaryOp.Greater,
        _ => BoundBinaryOp.GreaterEqual,
    };

    /// <summary>
    /// <c>3</c>, <c>"text"</c>, <c>Level.Low</c> -- and a bare name, which over
    /// a variant means one of its cases and everywhere else means a constant.
    /// </summary>
    private BoundPattern? BindConstantPattern(ConstantPatternSyntax syntax, BoundExpression subject)
    {
        if (subject.Type is VariantTypeSymbol variant &&
            syntax.Value is NameSyntax { Name.Parts: [var only] } &&
            variant.FindCase(only) is { } named)
            return new BoundPattern(
                new BoundVariantTest(syntax.Span, PrimitiveTypeSymbol.Bool, subject, named),
                Case: named);

        // `case Twig:` over a reference is a type and not a value. Asked only
        // where the subject is a reference, so a constant of some type that
        // happens to share a name with one is unaffected.
        if (subject.Type.AsReference() is not null &&
            syntax.Value is NameSyntax typeName &&
            LooksLikeType(typeName))
            return BindTypePattern(
                new TypePatternSyntax(
                    syntax.Span,
                    new NamedTypeSyntax(typeName.Span, typeName.Name),
                    Binding: null,
                    BindingSpan: syntax.Span),
                subject);

        var bound = BindExpression(syntax.Value);
        var written = BindConversion(bound, subject.Type, syntax.Value.Span);
        if (written.Type.IsError()) return null;

        var test = BindBinaryOperation(
            syntax.Span, subject, BoundBinaryOp.Equal, written, TokenKind.EqualsEquals);

        return test.Type.IsError() ? null : new BoundPattern(test);
    }

    /// <summary>
    /// Whether a bare name in a pattern names a type that is in scope.
    ///
    /// Quietly: nothing is reported if it does not, because the name is then an
    /// ordinary constant and the constant path will say what is wrong with it.
    /// </summary>
    private bool LooksLikeType(NameSyntax name)
    {
        using (diagnostics.Muted())
        {
            var resolved = ResolveType(
                new NamedTypeSyntax(name.Span, name.Name), _currentScope!);

            return resolved is NamedTypeSymbol { IsReferenceType: true };
        }
    }

    /// <summary>
    /// <c>Square s</c> over a reference, and <c>Circle c</c> over a variant --
    /// the same shape asking two different questions, told apart by what is
    /// being matched.
    /// </summary>
    private BoundPattern? BindTypePattern(TypePatternSyntax syntax, BoundExpression subject)
    {
        if (subject.Type is VariantTypeSymbol variant &&
            syntax.Type is NamedTypeSyntax { Name.Parts: [var only], TypeArguments.Count: 0 } &&
            variant.FindCase(only) is { } named)
        {
            var test = new BoundVariantTest(
                syntax.Span, PrimitiveTypeSymbol.Bool, subject, named);

            if (syntax.Binding is null) return new BoundPattern(test, Case: named);

            if (named.Payload is null)
            {
                diagnostics.Error("SL0619", syntax.BindingSpan,
                    $"case '{named.Name}' carries nothing, so there is nothing for " +
                    $"'{syntax.Binding}' to be; the test on its own is the whole question");
                return null;
            }

            return new BoundPattern(test, syntax.Binding, syntax.BindingSpan, named.Payload,
                new BoundVariantPayload(syntax.BindingSpan, subject, named, null), named);
        }

        // A value that is neither a reference nor a variant is exactly what it
        // was declared to be, so there is no second thing it could turn out to
        // be. Said before the type is resolved, because "'int' is not a
        // variant" is the mistake and "there is no type 'Circle'" is a
        // consequence of it.
        if (subject.Type.AsReference() is null && subject.Type is not VariantTypeSymbol)
        {
            diagnostics.Error("SL0438", syntax.Span,
                $"this matches a variant's case or an object's class, and " +
                $"'{subject.Type.Name}' is neither: a value of it is exactly what it was " +
                "declared to be. Match it against a value instead");
            return null;
        }

        var tested = ResolveType(syntax.Type, _currentScope!);
        if (tested.IsError()) return null;

        if (subject.Type is VariantTypeSymbol whole)
        {
            diagnostics.Error("SL0619", syntax.Span,
                $"'{whole.Name}' is a variant and has no case named '{tested.Name}'; what a " +
                "pattern asks a variant is which case it holds, and those are " +
                Listed(whole.Cases.Select(c => c.Name)));
            return null;
        }

        if (tested is not NamedTypeSymbol { IsReferenceType: true } wanted)
        {
            diagnostics.Error("SL0619", syntax.Span,
                $"'{tested.Name}' is not a class or an interface, so there is nothing to ask " +
                "about it: every other type is known exactly where it is written. Match it " +
                "against a value instead");
            return null;
        }

        if (subject.Type.AsReference() is not NamedTypeSymbol)
        {
            diagnostics.Error("SL0619", syntax.Span,
                $"'{subject.Type.Name}' is not a reference to an object, so what it really is " +
                "is not a question");
            return null;
        }

        var reference = new BoundTypeTest(syntax.Span, PrimitiveTypeSymbol.Bool, subject, wanted);

        if (syntax.Binding is null) return new BoundPattern(reference);

        if (wanted is not ClassTypeSymbol)
        {
            diagnostics.Error("SL0619", syntax.BindingSpan,
                $"'{wanted.Name}' is an interface, and a reference does not convert down to " +
                $"one, so there is nothing for '{syntax.Binding}' to be; match the type " +
                "without a name and reach the object through the interface it already has");
            return null;
        }

        if (ClassifyConversion(subject.Type, wanted, explicitCast: true) is not { } kind)
        {
            diagnostics.Error("SL0619", syntax.BindingSpan,
                $"'{subject.Type.Name}' does not convert to '{wanted.Name}', so the test can " +
                "be asked but its answer cannot be named");
            return null;
        }

        return new BoundPattern(reference, syntax.Binding, syntax.BindingSpan, wanted,
            new BoundConversion(syntax.BindingSpan, wanted, subject, kind));
    }

    /// <summary>
    /// The test a pattern and its <c>when</c> ask together.
    ///
    /// The guard is held behind the pattern's own test by <c>&amp;&amp;</c>,
    /// which short-circuits -- so a guard that reads what the pattern named
    /// runs only where the pattern matched, and the extraction it needs is
    /// safe. The name is a <see cref="BoundLet"/> rather than a local because
    /// the guard is an expression and there is nowhere in one to put a
    /// declaration.
    /// </summary>
    private BoundExpression Guarded(BoundPattern pattern, ExpressionSyntax? guard)
    {
        if (guard is null) return pattern.Test;

        PushScope();

        LocalSymbol? named = null;
        if (pattern is { Name: not null, NameType: not null })
            named = DeclareLocal(pattern.Name, pattern.NameType, isConst: true, pattern.NameSpan);

        var condition = BindCondition(guard);
        PopScope();

        if (condition.Type.IsError()) return pattern.Test;

        var held = named is null
            ? condition
            : new BoundLet(guard.Span, named, pattern.Extraction!, condition);

        return new BoundBinary(
            guard.Span, PrimitiveTypeSymbol.Bool, pattern.Test, BoundBinaryOp.LogicalAnd, held);
    }

    // ------------------------------------------------------- switch statement

    /// <summary>
    /// Whether this switch has to become a chain of tests rather than a jump
    /// table.
    ///
    /// Most switches do not: a list of constants, or a list of a variant's
    /// cases, is one LLVM <c>switch</c> instruction and stays one. What takes a
    /// switch off that path is a label that asks something else -- a type, a
    /// range, a <c>when</c> -- because none of those is a value the governor
    /// could equal.
    /// </summary>
    private static bool NeedsPatterns(SwitchSyntax syntax, TypeSymbol subject) =>
        syntax.Sections.Any(section =>
            section.Guards.Any(guard => guard is not null) ||
            section.Patterns.Any(pattern => pattern switch
            {
                ConstantPatternSyntax => false,

                // Over a variant this is `case Circle c:`, which the older path
                // handles; over anything else it is a type test.
                TypePatternSyntax => subject is not VariantTypeSymbol,
                _ => true,
            }));

    /// <summary>
    /// A switch whose labels are patterns: the governor in a name, and a test
    /// per label, asked in order.
    ///
    /// Everything else about it is the statement's own machinery -- sections
    /// that may not fall through, <c>break</c> that belongs to the switch,
    /// <c>default</c> where nothing matched -- because what changed is how a
    /// section is reached and nothing else.
    /// </summary>
    private BoundStatement BindPatternSwitch(SwitchSyntax syntax, BoundExpression value)
    {
        // Read once, and read by every test. A local is what makes that true
        // whatever produced the value.
        var held = DeclareLocal(
            SyntheticName("switch"), value.Type, isConst: true, syntax.Value.Span);

        var spill = new BoundLocalDeclaration(syntax.Value.Span, held, value);
        var subject = new BoundLocalAccess(syntax.Value.Span, held);

        var sections = new List<BoundSwitchSection>();
        var covered = new Dictionary<VariantCaseSymbol, SourceSpan>();
        bool sawDefault = false;

        _switchDepth++;

        foreach (var section in syntax.Sections)
        {
            var tests = new List<BoundExpression>();
            var matched = new List<BoundPattern>();

            for (int i = 0; i < section.Patterns.Count; i++)
            {
                var pattern = BindPattern(section.Patterns[i], subject);
                if (pattern is null) continue;

                var guard = i < section.Guards.Count ? section.Guards[i] : null;

                if (pattern.Case is { } named && guard is null && !covered.TryAdd(named, section.Span))
                    diagnostics.Error("SL0405", section.Span,
                        $"this switch already has a case for '{named.Name}'");

                tests.Add(Guarded(pattern, guard));
                matched.Add(pattern);
            }

            if (section.HasDefault)
            {
                if (sawDefault)
                    diagnostics.Error("SL0406", section.Span,
                        "this switch already has a 'default' section");
                sawDefault = true;
            }

            // A name belongs to one label: a section reached by two of them has
            // proved nothing about which, so there is nothing for a name to be.
            var naming = matched.Where(p => p.Name is not null).ToList();

            if (naming.Count > 0 && matched.Count > 1)
            {
                diagnostics.Error("SL0619", section.Span,
                    $"'{naming[0].Name}' is named by one label of a section with several, and " +
                    "which of them matched is not known in the body; give this label a section " +
                    "of its own");
                naming.Clear();
            }

            // Inside the section, a variant is known to hold that case, so its
            // fields are readable under their own names.
            var saved = SnapshotFacts();

            if (matched.Count == 1 && matched[0].Case is { } only &&
                NarrowableSubject(subject) is { } narrowed)
                _variantFacts[narrowed] = Fact.Holding(only);

            PushScope();

            var statements = new List<BoundStatement>();
            LocalSymbol? binding = null;

            if (naming.Count == 1)
            {
                var named = naming[0];
                binding = DeclareLocal(named.Name!, named.NameType!, isConst: true, named.NameSpan);
                statements.Add(new BoundLocalDeclaration(named.NameSpan, binding, named.Extraction!));
            }

            statements.AddRange(section.Statements.Select(BindStatement));
            var body = new BoundBlock(section.Span, statements);

            PopScope();
            _variantFacts = saved;

            if (!AlwaysExits(body))
                diagnostics.Error("SL0407", section.Span,
                    "a switch section must not run off its end; finish it with 'break', " +
                    "'return' or 'continue'. Stack the labels instead, as in " +
                    "'case 1: case 2:', when two of them share a body");

            sections.Add(new BoundSwitchSection(section.Span, [], section.HasDefault, body)
            {
                Tests = tests,
                Binding = binding,
            });
        }

        _switchDepth--;

        // A variant switch is still the one that may be exhaustive, and a
        // guarded label proves nothing about coverage -- which is why the
        // dictionary above only counts the unguarded ones.
        bool exhaustive = false;

        if (value.Type is VariantTypeSymbol variant)
        {
            var missing = variant.Uncovered(covered.Keys).ToList();
            exhaustive = missing.Count == 0;

            if (!exhaustive && !sawDefault)
                diagnostics.Error("SL0436", syntax.Span,
                    $"this switch over '{variant.Name}' does not cover " +
                    Listed(missing.Select(c => "'" + c.Name + "'")) +
                    "; a variant is the choice between its cases, so a switch that leaves one " +
                    "out has no answer for it. Add the case, or a 'default'");
        }

        return new BoundBlock(syntax.Span,
        [
            spill,
            new BoundSwitch(syntax.Span, subject, sections) { IsExhaustive = exhaustive },
        ]);
    }

    // ------------------------------------------------------ switch expression

    /// <summary>
    /// <c>value switch { pattern =&gt; result, ... }</c>.
    ///
    /// <para>
    /// It lowers to the value held in a name and then a conditional per arm,
    /// which is what it means: <c>t is P1 ? e1 : t is P2 ? e2 : e3</c>. Nothing
    /// is duplicated, because the arm a test fails falls into the next
    /// conditional rather than into a copy of the rest.
    /// </para>
    ///
    /// <para>
    /// <b>It has to be exhaustive</b> (SL0620), which is the one rule the
    /// statement does not have. A statement that matches nothing falls past
    /// itself; an expression that matched nothing would have no value to be,
    /// and there are no exceptions here to throw at the hole. So the last arm
    /// is <c>_</c>, or the arms cover every case of a variant.
    /// </para>
    /// </summary>
    private BoundExpression BindSwitchExpression(SwitchExpressionSyntax syntax)
    {
        var value = BindExpression(syntax.Value);
        if (value.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        if (syntax.Arms.Count == 0)
        {
            diagnostics.Error("SL0620", syntax.Span,
                "this switch has no arms, so there is no value it could produce");
            return new BoundErrorExpression(syntax.Span);
        }

        // Read once, and read by every arm's test. A local is what makes that
        // true whatever the value was made by.
        var held = new LocalSymbol(SyntheticName("switch"), value.Type, isConst: true);
        var subject = new BoundLocalAccess(syntax.Value.Span, held);

        var arms = new List<(BoundExpression? Test, BoundPattern Pattern, BoundExpression Value)>();
        var covered = new Dictionary<VariantCaseSymbol, SourceSpan>();
        bool total = false;

        foreach (var arm in syntax.Arms)
        {
            if (total)
                diagnostics.Warning("SL0621", arm.Span,
                    "nothing reaches this arm: an earlier one matches everything");

            var pattern = BindPattern(arm.Pattern, subject);
            if (pattern is null) return new BoundErrorExpression(syntax.Span);

            if (pattern.Case is { } matched && arm.Guard is null &&
                !covered.TryAdd(matched, arm.Span))
                diagnostics.Error("SL0405", arm.Span,
                    $"this switch already has an arm for '{matched.Name}'");

            // The name, and then the value that may read it.
            PushScope();

            LocalSymbol? named = null;
            if (pattern is { Name: not null, NameType: not null })
                named = DeclareLocal(pattern.Name, pattern.NameType, isConst: true, pattern.NameSpan);

            // Inside the arm, a variant is known to hold that case, so its
            // fields are readable under their own names -- the same proof a
            // section of the statement gets.
            var saved = SnapshotFacts();
            if (pattern.Case is { } only && NarrowableSubject(subject) is { } narrowed)
                _variantFacts[narrowed] = Fact.Holding(only);

            var result = BindExpression(arm.Value);

            _variantFacts = saved;
            PopScope();

            if (result.Type.IsError()) return new BoundErrorExpression(syntax.Span);

            if (named is not null)
                result = new BoundLet(arm.Value.Span, named, pattern.Extraction!, result);

            bool always = pattern.IsIrrefutable && arm.Guard is null;
            total |= always;

            arms.Add((always ? null : Guarded(pattern, arm.Guard), pattern, result));
        }

        // Every case of a variant, which is the other way to be exhaustive.
        if (!total && value.Type is VariantTypeSymbol variant && !variant.Uncovered(covered.Keys).Any())
            total = true;

        if (!total)
        {
            diagnostics.Error("SL0620", syntax.Span,
                value.Type is VariantTypeSymbol incomplete
                    ? $"this switch does not cover " +
                      Listed(incomplete.Uncovered(covered.Keys).Select(c => "'" + c.Name + "'")) +
                      ", and an expression has to produce a value whatever it is given; add " +
                      "the case, or a '_ => ...' arm"
                    : "this switch has no '_ => ...' arm, and an expression has to produce a " +
                      "value whatever it is given -- there is no exception here to throw at a " +
                      "value that matched nothing"
            );
            return new BoundErrorExpression(syntax.Span);
        }

        // What they all are. A later arm converts to the first one's type, which
        // is the rule the ternary keeps.
        var resultType = arms[0].Value.Type;

        if (resultType.IsVoid())
        {
            diagnostics.Error("SL0620", syntax.Arms[0].Value.Span,
                "an arm of a switch expression produces a value, and this one produces " +
                "nothing; write a statement switch instead");
            return new BoundErrorExpression(syntax.Span);
        }

        // The last arm is the one nothing tests: it is either `_` or the case
        // that completes a variant, and either way reaching it means it matched.
        BoundExpression chain = BindConversion(
            arms[^1].Value, resultType, syntax.Arms[^1].Value.Span);

        for (int i = arms.Count - 2; i >= 0; i--)
        {
            var converted = BindConversion(arms[i].Value, resultType, syntax.Arms[i].Value.Span);

            chain = new BoundConditional(
                syntax.Arms[i].Span, resultType,
                arms[i].Test ?? new BoundLiteral(syntax.Span, PrimitiveTypeSymbol.Bool, true),
                converted, chain);
        }

        return new BoundLet(syntax.Span, held, value, chain);
    }
}
