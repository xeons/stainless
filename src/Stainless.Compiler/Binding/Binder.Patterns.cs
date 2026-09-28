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
/// Patterns, and the three things written with them: <c>is</c>, a
/// <c>switch</c> expression, and a <c>case</c> label that is not a constant.
///
/// <para>
/// A pattern is a question about a value, and binding one says what it asks:
/// the tests, the values read to ask further questions of, and the names it
/// gives. Each test and read is an expression over a
/// <see cref="BoundPlaceholder"/> standing for the value it is asked of.
/// How the questions are asked -- in what order, which of them once for a
/// whole switch, what is held where -- is lowering's to decide. One routine
/// binds a pattern wherever it is written, so <c>x is (1, _)</c>,
/// <c>case (1, _):</c> and <c>(1, _) =&gt; ...</c> are the same question.
/// </para>
///
/// <para>
/// A name a pattern binds is a local given its value where the pattern has
/// proved what it holds. Whoever the pattern belongs to decides where the name
/// is in scope, which is wherever the pattern is known to have come out the
/// way that assigned it.
/// </para>
/// </summary>
public sealed partial class Binder
{
    /// <summary>A name a pattern binds, and the local that holds it.</summary>
    private sealed record PatternVariable(string Name, LocalSymbol Local, SourceSpan Span);

    /// <summary>Where a pattern is written, which decides the codes its mistakes report under.</summary>
    private enum PatternSite { Is, Switch }

    /// <summary>What binding one whole pattern carries down into its parts.</summary>
    private sealed class PatternContext(PatternSite site, PatternSyntax root)
    {
        public PatternSite Site { get; } = site;
        public PatternSyntax Root { get; } = root;

        /// <summary>Every name bound so far, so two places cannot bind one.</summary>
        public HashSet<string> Names { get; } = new(StringComparer.Ordinal);
    }

    /// <summary>
    /// One pattern, bound against a value: what it asks, what it names, and
    /// what a match proves.
    /// </summary>
    private sealed record PatternMatch(BoundPattern Node)
    {
        /// <summary>The names assigned where the pattern matched.</summary>
        public IReadOnlyList<PatternVariable> WhenTrue { get; init; } = [];

        /// <summary>The names assigned where the pattern did not match: those under a <c>not</c>.</summary>
        public IReadOnlyList<PatternVariable> WhenFalse { get; init; } = [];

        /// <summary>Values this certainly matches, for exhaustiveness.</summary>
        public Space Under { get; init; } = Space.None;

        /// <summary>Values this could match, for reachability.</summary>
        public Space Over { get; init; } = Space.Any;

        public VariantCaseSymbol? CaseWhenTrue { get; init; }
        public VariantCaseSymbol? CaseWhenFalse { get; init; }
        public bool NotNullWhenTrue { get; init; }
        public bool NotNullWhenFalse { get; init; }

        /// <summary>True for a pattern that matches everything, null included.</summary>
        public bool IsIrrefutable => Under is AnySpace;
    }

    private static BoundDiscardPattern Anything(SourceSpan span) => new(span);

    /// <summary>Every part in order, leaving out one that asks nothing.</summary>
    private static BoundPattern All(SourceSpan span, IEnumerable<BoundPattern> parts)
    {
        var asked = parts.Where(p => p is not BoundDiscardPattern).ToList();

        return asked.Count switch
        {
            0 => Anything(span),
            1 => asked[0],
            _ => new BoundAndPattern(span, asked),
        };
    }

    private static BoundPattern Both(SourceSpan span, BoundPattern first, BoundPattern second) =>
        All(span, [first, second]);

    // ================================================================ binding

    /// <summary>A whole pattern, against the value <paramref name="subject"/> stands for.</summary>
    private PatternMatch? BindTopPattern(PatternSyntax syntax, BoundPlaceholder subject, PatternSite site)
    {
        var context = new PatternContext(site, syntax);
        var bound = BindPattern(syntax, subject, context);
        if (bound is null)
            return null;

        // A label is reached where its pattern matched, so a name only a
        // failed match would have assigned has nowhere to be.
        if (site == PatternSite.Switch && bound.WhenFalse.Count > 0)
        {
            var lost = bound.WhenFalse[0];
            diagnostics.Error("SL0619", lost.Span,
                $"'{lost.Name}' is named under a 'not', so it is assigned only where this " +
                "pattern did not match -- and that is never where the arm runs");
            return null;
        }

        return bound;
    }

    private PatternMatch? BindPattern(PatternSyntax syntax, BoundPlaceholder subject, PatternContext context)
    {
        switch (syntax)
        {
            case DiscardPatternSyntax discard:
                return new PatternMatch(Anything(discard.Span)) { Under = Space.Any, Over = Space.Any };

            case VarPatternSyntax named:
            {
                if (subject.Type.IsError())
                    return null;

                var variables = new List<PatternVariable>();
                var assigned = BindPatternVariable(
                    named.Name, named.NameSpan, subject.Type, subject, context, variables);

                return new PatternMatch(assigned)
                {
                    WhenTrue = variables,
                    Under = Space.Any,
                    Over = Space.Any,
                };
            }

            case ConstantPatternSyntax constant:
                return BindConstantPattern(constant, subject, context);

            case RelationalPatternSyntax relational:
            {
                var bound = BindExpression(relational.Value);
                var written = BindConversion(bound, subject.Type, relational.Value.Span);
                if (written.Type.IsError())
                    return null;

                var (op, token) = (Comparison(relational.Operator), relational.Operator);
                var test = BindBinaryOperation(relational.Span, subject, op, written, token);

                return test.Type.IsError()
                    ? null
                    : new PatternMatch(new BoundTestPattern(relational.Span, subject, test, null));
            }

            case TypePatternSyntax typed:
                return BindTypePattern(typed, subject, context);

            case RecursivePatternSyntax recursive:
                return BindRecursivePattern(recursive, subject, context);

            case ListPatternSyntax list:
                return BindListPattern(list, subject, context);

            case SlicePatternSyntax slice:
                diagnostics.Error("SL0775", slice.Span,
                    "'..' stands for the run of elements a list pattern does not name, so it " +
                    "belongs directly inside '[...]'");
                return null;

            case NotPatternSyntax negated:
            {
                var inner = BindPattern(negated.Operand, subject, context);
                if (inner is null)
                    return null;

                return new PatternMatch(new BoundNotPattern(negated.Span, inner.Node))
                {
                    WhenTrue = inner.WhenFalse,
                    WhenFalse = inner.WhenTrue,
                    Under = Complement(inner.Over, subject.Type, under: true),
                    Over = Complement(inner.Under, subject.Type, under: false),
                    CaseWhenTrue = inner.CaseWhenFalse,
                    CaseWhenFalse = inner.CaseWhenTrue,
                    NotNullWhenTrue = inner.NotNullWhenFalse,
                    NotNullWhenFalse = inner.NotNullWhenTrue,
                };
            }

            case BinaryPatternSyntax combined:
                return BindBinaryPattern(combined, subject, context);

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
    /// <c>p and q</c>, <c>p or q</c>. A name survives only where it is known
    /// to have been assigned: under <c>and</c>, where both matched, and under
    /// <c>or</c> nowhere, because which side matched is not known.
    /// </summary>
    private PatternMatch? BindBinaryPattern(
        BinaryPatternSyntax syntax, BoundPlaceholder subject, PatternContext context)
    {
        var left = BindPattern(syntax.Left, subject, context);
        var right = BindPattern(syntax.Right, subject, context);
        if (left is null || right is null)
            return null;

        if (syntax.IsOr)
        {
            if (left.WhenTrue.Concat(right.WhenTrue).FirstOrDefault() is { } lost)
            {
                diagnostics.Error("SL0619", lost.Span,
                    $"'{lost.Name}' is named on one side of an 'or', and which side matched is " +
                    "not known where the name would be used");
                return null;
            }

            return new PatternMatch(new BoundOrPattern(syntax.Span, left.Node, right.Node))
            {
                WhenFalse = [.. left.WhenFalse, .. right.WhenFalse],
                Under = Space.Union(left.Under, right.Under),
                Over = Space.Union(left.Over, right.Over),
                CaseWhenTrue = left.CaseWhenTrue == right.CaseWhenTrue ? left.CaseWhenTrue : null,
                CaseWhenFalse = left.CaseWhenFalse ?? right.CaseWhenFalse,
                NotNullWhenTrue = left.NotNullWhenTrue && right.NotNullWhenTrue,
                NotNullWhenFalse = left.NotNullWhenFalse || right.NotNullWhenFalse,
            };
        }

        if (left.WhenFalse.Concat(right.WhenFalse).FirstOrDefault() is { } unassigned)
        {
            diagnostics.Error("SL0619", unassigned.Span,
                $"'{unassigned.Name}' is named under a 'not' joined by 'and', so there is no " +
                "outcome of the whole in which it is known to have been assigned");
            return null;
        }

        return new PatternMatch(new BoundAndPattern(syntax.Span, [left.Node, right.Node]))
        {
            WhenTrue = [.. left.WhenTrue, .. right.WhenTrue],
            Under = Space.Intersection(left.Under, right.Under, under: true),
            Over = Space.Intersection(left.Over, right.Over, under: false),
            CaseWhenTrue = left.CaseWhenTrue ?? right.CaseWhenTrue,
            NotNullWhenTrue = left.NotNullWhenTrue || right.NotNullWhenTrue,
        };
    }

    /// <summary>A name given a value: a local, which the pattern declares.</summary>
    private BoundPattern BindPatternVariable(
        string name, SourceSpan span, TypeSymbol type, BoundExpression value,
        PatternContext context, List<PatternVariable> into)
    {
        if (!context.Names.Add(name) || LookupLocal(name) is not null)
            diagnostics.Error("SL0218", span, $"'{name}' is already declared in this scope");
        else if (_context.Function?.Parameters.Any(p => p.Name == name) == true)
            diagnostics.Error("SL0219", span, $"'{name}' is already the name of a parameter");

        var local = new LocalSymbol(name, type, isConst: true);
        into.Add(new PatternVariable(name, local, span));
        Remember(_patternVariableNames, name);

        return new BoundDeclarationPattern(span, local, value);
    }

    /// <summary>
    /// A value read from the inputs, and what it has to match. The input
    /// itself is matched as it is: it is already a value the pattern holds.
    /// </summary>
    private static PatternMatch? MatchRead(BoundExpression value, Func<BoundPlaceholder, PatternMatch?> match)
    {
        if (value is BoundPlaceholder input)
            return match(input);

        var read = new BoundPlaceholder(value.Span, value.Type);
        var inner = match(read);

        return inner is null
            ? null
            : inner with { Node = new BoundReadPattern(value.Span, read, value, inner.Node) };
    }

    // ------------------------------------------------------------- constants

    /// <summary>
    /// <c>3</c>, <c>"text"</c>, <c>Level.Low</c>, <c>null</c> -- and a bare
    /// name, which over a variant means one of its cases and over a reference
    /// may mean a type.
    /// </summary>
    private PatternMatch? BindConstantPattern(
        ConstantPatternSyntax syntax, BoundPlaceholder subject, PatternContext context)
    {
        if (subject.Type is VariantTypeSymbol variant &&
            syntax.Value is NameSyntax { Name.Parts: [var only], TypeArguments: null } &&
            variant.FindCase(only) is { } named)
            return CasePattern(syntax.Span, subject, named, []);

        // `case Twig:` is a type and not a value, and over anything but a
        // reference it is the mistake of asking a value what class it is.
        if (syntax.Value is NameSyntax typeName && LooksLikeType(typeName))
            return BindTypePattern(
                new TypePatternSyntax(
                    syntax.Span,
                    new NamedTypeSyntax(typeName.Span, typeName.Name),
                    Binding: null,
                    BindingSpan: syntax.Span),
                subject, context, written: syntax);

        var bound = BindExpression(syntax.Value);

        if (bound is BoundNullLiteral)
            return NullPattern(syntax.Span, subject, bound);

        var written = BindConversion(bound, subject.Type, syntax.Value.Span);
        if (written.Type.IsError())
            return null;

        var test = BindBinaryOperation(
            syntax.Span, subject, BoundBinaryOp.Equal, written, TokenKind.EqualsEquals);
        if (test.Type.IsError())
            return null;

        bool optional = subject.Type is OptionalTypeSymbol;
        var key = ConstantKeyOf(written);

        return new PatternMatch(new BoundTestPattern(syntax.Span, subject, test,
            key is null || optional ? null : new PatternTestKey(PatternTestKind.Constant, key.Value)))
        {
            Under = key is null || optional ? Space.None : new ConstructorSpace(key, []),
            Over = key is null ? Space.Any
                 : optional ? new ConstructorSpace(InstanceKey.Instance, [])
                 : new ConstructorSpace(key, []),
            NotNullWhenTrue = optional,
        };
    }

    /// <summary><c>null</c>: the one question an optional can be asked without a type.</summary>
    private PatternMatch? NullPattern(SourceSpan span, BoundPlaceholder subject, BoundExpression nothing)
    {
        var test = BindBinaryOperation(
            span, subject, BoundBinaryOp.Equal, nothing, TokenKind.EqualsEquals);
        if (test.Type.IsError())
            return null;

        var space = new ConstructorSpace(NullKey.Instance, []);
        return new PatternMatch(new BoundTestPattern(span, subject, test,
            new PatternTestKey(PatternTestKind.Null, null)))
        {
            Under = space,
            Over = space,
            NotNullWhenFalse = true,
        };
    }

    /// <summary><c>subject != null</c>: an optional asked whether there is anything to look at.</summary>
    private static BoundTestPattern PresentTest(SourceSpan span, BoundPlaceholder subject) =>
        new(span, subject,
            subject.Type is ClosureTypeSymbol closure
                ? new BoundClosureEqual(span, closure, subject, new BoundDefault(span, closure),
                    negated: true)
                : new BoundBinary(span, PrimitiveTypeSymbol.Bool, subject, BoundBinaryOp.NotEqual,
                    new BoundNullLiteral(span, subject.Type)),
            new PatternTestKey(PatternTestKind.Null, null, Negated: true));

    /// <summary>What a folded constant is, as far as coverage is concerned.</summary>
    private static ValueKey? ConstantKeyOf(BoundExpression value) =>
        FoldSwitchLabel(value) is { } bits ? new ValueKey(bits)
        : Underlying(value) is BoundStringLiteral text ? new ValueKey(text.Value)
        : null;

    /// <summary>
    /// Whether a bare name in a pattern names a type that is in scope.
    ///
    /// Quietly: nothing is reported if it does not, because the name is then an
    /// ordinary constant and the constant path will say what is wrong with it.
    /// </summary>
    private bool LooksLikeType(NameSyntax name)
    {
        var resolved = ResolveTypeQuietly(
            new NamedTypeSyntax(name.Span, name.Name), _context.File!);
        return resolved is NamedTypeSymbol { IsReferenceType: true };
    }

    // ----------------------------------------------------------------- types

    /// <summary>What a type in a pattern asked, and the value it proved.</summary>
    /// <param name="Value">
    /// The subject as the type asked for, or null where the pattern reaches a
    /// variant's payload instead.
    /// </param>
    private sealed record TypeMatch(
        BoundPattern Test, BoundExpression? Value, VariantCaseSymbol? Case, object Key);

    /// <summary>
    /// <c>Square s</c> over a reference, and <c>Circle c</c> over a variant --
    /// the same shape asking two different questions, told apart by what is
    /// being matched.
    /// </summary>
    private PatternMatch? BindTypePattern(
        TypePatternSyntax syntax, BoundPlaceholder subject, PatternContext context,
        PatternSyntax? written = null)
    {
        if (BindPatternType(syntax.Type, syntax.Span, subject, context, written ?? syntax)
            is not { } match)
            return null;

        var variables = new List<PatternVariable>();
        var node = match.Test;

        if (syntax.Binding is { } name)
        {
            if (NamedValue(match, subject, name, syntax.BindingSpan, context) is not { } value)
                return null;

            node = Both(syntax.Span, node, BindPatternVariable(
                name, syntax.BindingSpan, value.Type, value, context, variables));
        }

        var space = new ConstructorSpace(match.Key, []);
        bool always = match.Key is InstanceKey && subject.Type is not OptionalTypeSymbol;

        return new PatternMatch(node)
        {
            WhenTrue = variables,
            Under = always ? Space.Any : space,
            Over = always ? Space.Any : space,
            CaseWhenTrue = match.Case,
            NotNullWhenTrue = subject.Type.AsReference() is not null,
        };
    }

    /// <summary>
    /// The value a name after a type pattern stands for: the payload of the
    /// case, or the object under the type asked about.
    /// </summary>
    private BoundExpression? NamedValue(
        TypeMatch match, BoundPlaceholder subject, string name, SourceSpan span,
        PatternContext context)
    {
        if (match.Case is { } matched)
        {
            if (matched.Payload is null)
            {
                diagnostics.Error(context.Site == PatternSite.Is ? "SL0586" : "SL0619", span,
                    $"case '{matched.Name}' carries nothing, so there is nothing for " +
                    $"'{name}' to be; the test on its own is the whole question");
                return null;
            }

            return new BoundVariantPayload(span, subject, matched, null);
        }

        if (match.Value is null)
        {
            diagnostics.Error(context.Site == PatternSite.Is ? "SL0587" : "SL0619", span,
                $"a reference does not convert down to an interface, so there is nothing " +
                $"for '{name}' to be; match the type without a name and reach the object " +
                "through the interface it already has");
            return null;
        }

        return match.Value;
    }

    /// <summary>
    /// The test a type asks of a subject, and the subject as that type.
    ///
    /// A variant is asked which case it holds. A reference is asked what its
    /// object really is, unless the answer is in its type already. Any other
    /// value is exactly what it was declared to be, so the only type it can be
    /// matched against is its own.
    /// </summary>
    private TypeMatch? BindPatternType(
        TypeSyntax typeSyntax, SourceSpan span, BoundPlaceholder subject, PatternContext context,
        PatternSyntax written)
    {
        bool inIs = context.Site == PatternSite.Is;

        if (subject.Type is VariantTypeSymbol variant)
        {
            if (typeSyntax is NamedTypeSyntax { Name.Parts: [var only], TypeArguments.Count: 0 } &&
                variant.FindCase(only) is { } named)
                return new TypeMatch(CaseTest(span, subject, named), null, named, named);

            diagnostics.Error(inIs ? "SL0518" : "SL0619", span,
                $"'{variant.Name}' is a variant and has no case named " +
                $"'{typeSyntax.Span.File.Text[typeSyntax.Span.Start..typeSyntax.Span.End]}'; " +
                "what a pattern asks a variant is which case it holds, and those are " +
                Listed(variant.Cases.Select(c => c.Name)),
                variant);
            return null;
        }

        if (subject.Type is WeakTypeSymbol)
        {
            diagnostics.Error(inIs ? "SL0518" : "SL0619", span,
                $"'{subject.Type.Name}' may already have died, so what it is cannot be asked " +
                "directly; read it into an optional first, which is the check that makes it " +
                "safe to look at",
                subject.Type);
            return null;
        }

        if (subject.Type.AsReference() is null)
        {
            // `(int x, var y)` over a tuple of ints: the one type an int can
            // be asked about is int, and the answer is yes.
            var same = ResolveTypeQuietly(typeSyntax, _context.File!);

            if (same.Equals(subject.Type))
                return new TypeMatch(Anything(span), subject, null, InstanceKey.Instance);

            if (inIs)
                diagnostics.Error("SL0518", span,
                    $"'{subject.Type.Name}' is not a reference to an object, so 'is' has no type " +
                    "to ask about: a value is exactly what it was declared to be",
                    subject.Type);
            else
                diagnostics.Error("SL0438", span,
                    $"this matches a variant's case or an object's class, and " +
                    $"'{subject.Type.Name}' is neither: a value of it is exactly what it was " +
                    "declared to be. Match it against a value instead",
                    subject.Type);
            return null;
        }

        var tested = ResolveType(typeSyntax, _context.File!);
        if (tested.IsError())
            return null;

        string code = inIs ? "SL0518" : "SL0619";

        if (tested is not NamedTypeSymbol { IsReferenceType: true } wanted)
        {
            diagnostics.Error(code, span,
                $"'{tested.Name}' is not a class or an interface, so there is nothing to ask " +
                "about it: every other type is known exactly where it is written",
                tested);
            return null;
        }

        if (subject.Type.AsReference() is not NamedTypeSymbol reference)
        {
            diagnostics.Error(code, span,
                $"'{subject.Type.Name}' is not a reference to an object, so what it really is " +
                "is not a question",
                subject.Type);
            return null;
        }

        if (wanted is ComInterfaceTypeSymbol || reference is ComInterfaceTypeSymbol)
        {
            if (!CanAskCom(code, span, reference, wanted))
                return null;

            // A COM object answers for itself, even about a type it already
            // has, and a name here would be a second question to it.
            return new TypeMatch(
                new BoundTestPattern(span, subject,
                    new BoundTypeTest(span, PrimitiveTypeSymbol.Bool, subject, wanted), null),
                null, null, new TypeKey(wanted));
        }

        // Two classes in different families: no object is ever both.
        if (reference is ClassTypeSymbol subjectClass && wanted is ClassTypeSymbol wantedClass &&
            !subjectClass.DerivesFrom(wantedClass) && !wantedClass.DerivesFrom(subjectClass))
        {
            diagnostics.Error(code, span,
                $"no object is both a '{subjectClass.Name}' and a '{wantedClass.Name}': " +
                "neither derives from the other",
                subjectClass, wantedClass);
            return null;
        }

        // Upwards the answer is in the type, except through an optional,
        // where it still says 'and not null'.
        if (ClassifyConversion(reference, wanted, explicitCast: false) is { } widening)
        {
            bool optional = subject.Type is OptionalTypeSymbol;

            if (inIs && !optional && ReferenceEquals(written, context.Root) &&
                reference is ClassTypeSymbol && wanted is ClassTypeSymbol)
                diagnostics.Warning("SL0520", span,
                    $"every '{reference.Name}' is a '{wanted.Name}', so this is always true",
                    reference, wanted);

            BoundPattern present = optional ? PresentTest(span, subject) : Anything(span);

            BoundExpression held = optional
                ? new BoundConversion(span, reference, subject, ConversionKind.NarrowOptional)
                : subject;

            var viewed = wanted.Equals(reference)
                ? held
                : new BoundConversion(span, wanted, held, widening);

            return new TypeMatch(present, wanted is ClassTypeSymbol ? viewed : null, null,
                InstanceKey.Instance);
        }

        var test = new BoundTestPattern(span, subject,
            new BoundTypeTest(span, PrimitiveTypeSymbol.Bool, subject, wanted),
            new PatternTestKey(PatternTestKind.Type, wanted));

        BoundExpression? downcast = null;
        if (wanted is ClassTypeSymbol &&
            ClassifyConversion(subject.Type, wanted, explicitCast: true) is { } kind)
            downcast = new BoundConversion(span, wanted, subject, kind);

        return new TypeMatch(test, downcast, null, new TypeKey(wanted));
    }

    /// <summary>Whether a variant holds a case.</summary>
    private static BoundTestPattern CaseTest(SourceSpan span, BoundPlaceholder subject, VariantCaseSymbol named) =>
        new(span, subject, new BoundVariantTest(span, PrimitiveTypeSymbol.Bool, subject, named),
            new PatternTestKey(PatternTestKind.Case, named));

    /// <summary>A case of a variant, with what its payload's fields must match.</summary>
    private static PatternMatch CasePattern(
        SourceSpan span, BoundPlaceholder subject, VariantCaseSymbol named,
        IReadOnlyList<SpaceMember> members) =>
        new(CaseTest(span, subject, named))
        {
            Under = new ConstructorSpace(named, members),
            Over = new ConstructorSpace(named, members),
            CaseWhenTrue = named,
        };

    // ------------------------------------------------------------- recursive

    /// <summary>
    /// <c>Point(0, var y)</c>, <c>{ Radius: &gt; 1 }</c>, <c>var (a, b)</c>:
    /// a value asked what it is, if a type is written, and then taken apart --
    /// by position through a tuple's elements, a case's payload or a
    /// <c>Deconstruct</c>, and by name through its fields and properties.
    /// </summary>
    private PatternMatch? BindRecursivePattern(
        RecursivePatternSyntax syntax, BoundPlaceholder subject, PatternContext context)
    {
        if (subject.Type.IsError())
            return null;

        TypeMatch match;

        if (syntax.Type is { } written)
        {
            if (BindPatternType(written, written.Span, subject, context, syntax) is not { } typed)
                return null;
            match = typed;
        }
        else if (subject.Type.NonNullForm() is { } held)
        {
            match = new TypeMatch(
                PresentTest(syntax.Span, subject),
                new BoundConversion(syntax.Span, held, subject, ConversionKind.NarrowOptional),
                null, InstanceKey.Instance);
        }
        else if (subject.Type is WeakTypeSymbol or VariantTypeSymbol)
        {
            diagnostics.Error(context.Site == PatternSite.Is ? "SL0518" : "SL0619", syntax.Span,
                subject.Type is WeakTypeSymbol
                    ? $"'{subject.Type.Name}' may already have died, so it cannot be taken apart " +
                      "directly; read it into an optional first"
                    : $"'{subject.Type.Name}' is a variant, and what it holds depends on its case; " +
                      "name the case first, as in 'Circle(var r)' or 'Circle { Radius: > 1 }'",
                subject.Type);
            return null;
        }
        else
        {
            match = new TypeMatch(Anything(syntax.Span), subject, null, InstanceKey.Instance);
        }

        if (match.Case is null && match.Value is null && (syntax.Positional is not null ||
            syntax.Properties is not null || syntax.Binding is not null))
        {
            diagnostics.Error(context.Site == PatternSite.Is ? "SL0587" : "SL0619", syntax.Span,
                "a reference does not convert down to an interface, so there is nothing here " +
                "to take apart or name; match the type on its own");
            return null;
        }

        var parts = match.Case is not null
            ? BindRecursiveParts(syntax, subject, match, context)
            : MatchRead(match.Value!, viewed => BindRecursiveParts(syntax, viewed, match, context));

        if (parts is null)
            return null;

        bool notNull = subject.Type.NonNullForm() is not null || subject.Type.AsReference() is not null;

        return parts with
        {
            Node = Both(syntax.Span, match.Test, parts.Node),
            CaseWhenTrue = match.Case,
            NotNullWhenTrue = notNull,
        };
    }

    /// <summary>
    /// Everything after the type: the positions, the members and the name,
    /// against a value already known to be what the type asked.
    /// </summary>
    private PatternMatch? BindRecursiveParts(
        RecursivePatternSyntax syntax, BoundPlaceholder viewed, TypeMatch match,
        PatternContext context)
    {
        var parts = new List<BoundPattern>();
        var variables = new List<PatternVariable>();
        var under = new List<SpaceMember>();
        var over = new List<SpaceMember>();

        if (syntax.Positional is { } positional)
        {
            var named = BindPositionalParts(syntax, positional, viewed, match, context, parts, under, over);
            if (named is null)
                return null;
            variables.AddRange(named);
        }

        bool failed = false;

        foreach (var member in syntax.Properties ?? [])
        {
            var value = PatternMember(member, viewed, match);
            if (value is null)
            {
                failed = true;
                continue;
            }

            // `Owner.Name: "a"` is `Owner: { Name: "a" }`, which asks that the
            // owner is there before it asks anything of it.
            PatternSyntax rest = member.Path.Count == 1
                ? member.Pattern
                : new RecursivePatternSyntax(member.Span, null, null,
                    [new SubpatternSyntax(member.Span, member.Path.Skip(1).ToList(),
                        member.PathSpan, member.Pattern)],
                    null, default);

            var part = MatchRead(value, held => BindPattern(rest, held, context));
            if (part is null)
            {
                failed = true;
                continue;
            }

            parts.Add(part.Node);
            variables.AddRange(part.WhenTrue);
            under.Add(new SpaceMember(member.Path[0], value.Type, part.Under));
            over.Add(new SpaceMember(member.Path[0], value.Type, part.Over));
        }

        if (failed)
            return null;

        if (syntax.Binding is { } name)
        {
            var whole = match.Case is not null
                ? NamedValue(match, viewed, name, syntax.BindingSpan, context)
                : viewed;
            if (whole is null)
                return null;

            parts.Add(BindPatternVariable(name, syntax.BindingSpan, whole.Type, whole, context, variables));
        }

        return new PatternMatch(All(syntax.Span, parts))
        {
            WhenTrue = variables,
            Under = under.Any(m => m.Space is NoSpace)
                ? Space.None
                : new ConstructorSpace(match.Key, under),
            Over = new ConstructorSpace(match.Key, over),
        };
    }

    /// <summary>
    /// The parenthesised part: a case's payload fields, a tuple's elements, or
    /// what a <c>Deconstruct</c> hands back, in order.
    /// </summary>
    private List<PatternVariable>? BindPositionalParts(
        RecursivePatternSyntax syntax, IReadOnlyList<SubpatternSyntax> positional,
        BoundPlaceholder viewed, TypeMatch match, PatternContext context,
        List<BoundPattern> parts, List<SpaceMember> under, List<SpaceMember> over)
    {
        var values = new List<(object Key, string? Name, BoundExpression Value)>();

        if (match.Case is { } matched)
        {
            if (!PositionsAgree(matched.Fields.Count, positional.Count, $"case '{matched.Name}'",
                    "field", syntax.Span))
                return null;

            foreach (var field in matched.Fields)
                values.Add((field.Name, field.Name,
                    new BoundVariantPayload(syntax.Span, viewed, matched, field)));
        }
        else if (viewed.Type is TupleTypeSymbol tuple)
        {
            if (!PositionsAgree(tuple.Elements.Count, positional.Count, $"'{tuple.Name}'",
                    "element", syntax.Span))
                return null;

            for (int i = 0; i < tuple.Elements.Count; i++)
                values.Add((tuple.Fields[i].Name, tuple.Fields[i].Name,
                    new BoundFieldAccess(syntax.Span, viewed, tuple.Fields[i])));
        }
        else
        {
            if (BindDeconstructCall(viewed, positional.Count, syntax.Span) is not var (call, outs))
                return null;

            parts.Add(new BoundEffectPattern(syntax.Span, call));

            var outward = call is BoundCall { Function: var chosen }
                ? chosen.Parameters.Where(p => p.Mode == ParameterMode.Out).ToList()
                : [];

            for (int i = 0; i < outs.Count; i++)
                values.Add(("$" + i, i < outward.Count ? outward[i].Name : null,
                    new BoundLocalAccess(syntax.Span, outs[i])));
        }

        var variables = new List<PatternVariable>();
        bool failed = false;

        for (int i = 0; i < positional.Count; i++)
        {
            var element = positional[i];
            var (key, name, value) = values[i];

            if (element.Path is [var written] && written != name)
            {
                diagnostics.Error("SL0776", element.PathSpan,
                    name is null
                        ? $"this position has no name to check '{written}' against"
                        : $"position {i + 1} is '{name}', not '{written}'");
                failed = true;
                continue;
            }

            var part = MatchRead(value, held => BindPattern(element.Pattern, held, context));
            if (part is null)
            {
                failed = true;
                continue;
            }

            parts.Add(part.Node);
            variables.AddRange(part.WhenTrue);
            under.Add(new SpaceMember(key, value.Type, part.Under));
            over.Add(new SpaceMember(key, value.Type, part.Over));
        }

        return failed ? null : variables;
    }

    private bool PositionsAgree(int count, int written, string what, string noun, SourceSpan span)
    {
        if (count == written)
            return true;

        diagnostics.Error("SL0609", span,
            $"{what} has {Counted(count, noun)}, and this pattern names {written}");
        return false;
    }

    /// <summary>One member a property pattern reads: a payload's field, or a field or property.</summary>
    private BoundExpression? PatternMember(
        SubpatternSyntax member, BoundPlaceholder viewed, TypeMatch match)
    {
        string name = member.Path[0];

        if (match.Case is { } matched)
        {
            if (matched.FindField(name) is { } field)
                return new BoundVariantPayload(member.PathSpan, viewed, matched, field);

            diagnostics.Error("SL0247", member.PathSpan,
                $"case '{matched.Name}' carries no '{name}'; it carries " +
                (matched.Fields.Count == 0 ? "nothing" : matched.Signature),
                [.. matched.Fields.Select(f => f.Type)]);
            return null;
        }

        var access = new MemberAccessSyntax(member.PathSpan,
            new NameSyntax(member.PathSpan, new QualifiedName(member.PathSpan, ["$matched"])), name);

        var value = BindMemberOf(viewed, access);
        if (value.Type.IsError())
            return null;

        if (value is BoundFunctionGroup || value.Type.IsVoid())
        {
            diagnostics.Error("SL0776", member.PathSpan,
                $"'{name}' is a method, and a property pattern reads a field or a property; " +
                "call it in a 'when' instead");
            return null;
        }

        return value;
    }

    // ------------------------------------------------------------------ lists

    /// <summary>
    /// <c>[1, .., var last]</c>: the length asked first, then each element by
    /// its index from whichever end it is written against.
    ///
    /// An array, a slice or an inline array is indexed directly; a type with a
    /// <c>Count</c> or <c>Length</c> and an integer indexer goes through those.
    /// What <c>..</c> names is a slice of the array, which shares its storage
    /// rather than copying it, so only an array or a slice can give one.
    /// </summary>
    private PatternMatch? BindListPattern(
        ListPatternSyntax syntax, BoundPlaceholder subject, PatternContext context)
    {
        if (subject.Type.IsError())
            return null;

        BoundPattern present = Anything(syntax.Span);
        BoundExpression viewed = subject;

        if (subject.Type is OptionalTypeSymbol optional)
        {
            present = PresentTest(syntax.Span, subject);
            viewed = new BoundConversion(
                syntax.Span, optional.Element, subject, ConversionKind.NarrowOptional);
        }

        var slices = syntax.Elements.OfType<SlicePatternSyntax>().ToList();
        if (slices.Count > 1)
        {
            diagnostics.Error("SL0775", slices[1].Span,
                "a list pattern has one '..' at most: with two, which elements each stood " +
                "for would not be known");
            return null;
        }

        var parts = MatchRead(viewed, held => BindListParts(syntax, held, context));
        if (parts is null)
            return null;

        if (subject.Type is not OptionalTypeSymbol)
            return parts with { Node = Both(syntax.Span, present, parts.Node) };

        // Over an optional the elements are asked of what is there, which is
        // a member of "not null" as coverage sees it.
        return parts with
        {
            Node = Both(syntax.Span, present, parts.Node),
            Under = parts.Under is NoSpace
                ? Space.None
                : new ConstructorSpace(InstanceKey.Instance,
                    [new SpaceMember(ListPosition.Whole, viewed.Type, parts.Under)]),
            Over = new ConstructorSpace(InstanceKey.Instance,
                [new SpaceMember(ListPosition.Whole, viewed.Type, parts.Over)]),
            NotNullWhenTrue = true,
        };
    }

    private PatternMatch? BindListParts(
        ListPatternSyntax syntax, BoundPlaceholder viewed, PatternContext context)
    {
        var span = syntax.Span;

        if (ListShape(viewed, span) is not var (length, element, slice))
        {
            diagnostics.Error("SL0774", span,
                $"'{viewed.Type.Name}' cannot be matched element by element: a list pattern " +
                "takes an array, a slice, an inline array, or a type with a 'Count' or " +
                "'Length' and an integer indexer",
                viewed.Type);
            return null;
        }

        int sliceAt = syntax.Elements.ToList().FindIndex(e => e is SlicePatternSyntax);
        int fixedCount = syntax.Elements.Count - (sliceAt < 0 ? 0 : 1);

        // The length is read once, and everything after it names it.
        var counted = new BoundPlaceholder(span, PrimitiveTypeSymbol.NUInt);

        var parts = new List<BoundPattern>
        {
            new BoundTestPattern(span, counted,
                BindBinaryOperation(span, counted,
                    sliceAt < 0 ? BoundBinaryOp.Equal : BoundBinaryOp.GreaterEqual,
                    Index(span, fixedCount),
                    sliceAt < 0 ? TokenKind.EqualsEquals : TokenKind.GreaterEquals),
                sliceAt < 0 ? new PatternTestKey(PatternTestKind.Constant, (ulong)fixedCount) : null),
        };

        var variables = new List<PatternVariable>();
        var under = new List<SpaceMember>();
        var over = new List<SpaceMember>();
        bool failed = false;
        bool runIsAnything = true;

        for (int i = 0; i < syntax.Elements.Count; i++)
        {
            var written = syntax.Elements[i];
            PatternMatch? part;
            TypeSymbol partType;

            if (written is SlicePatternSyntax run)
            {
                if (run.Pattern is null)
                    continue;

                var start = Index(span, i);
                var end = BindBinaryOperation(span, counted, BoundBinaryOp.Subtract,
                    Index(span, syntax.Elements.Count - 1 - i), TokenKind.Minus);

                if (slice(start, end) is not { } taken)
                {
                    diagnostics.Error("SL0775", run.Span,
                        $"'..' can name what it skipped only as a slice of an array or another " +
                        $"slice, or as what a type's 'Slice(start, length)' answers, and " +
                        $"'{viewed.Type.Name}' has neither; write '..' on its own",
                        viewed.Type);
                    failed = true;
                    continue;
                }

                part = MatchRead(taken, held => BindPattern(run.Pattern, held, context));
                partType = taken.Type;
            }
            else
            {
                var index = sliceAt < 0 || i < sliceAt
                    ? Index(span, i)
                    : BindBinaryOperation(span, counted, BoundBinaryOp.Subtract,
                        Index(span, syntax.Elements.Count - i), TokenKind.Minus);

                var value = element(index);
                if (value.Type.IsError())
                {
                    failed = true;
                    continue;
                }

                part = MatchRead(value, held => BindPattern(written, held, context));
                partType = value.Type;
            }

            if (part is null)
            {
                failed = true;
                continue;
            }

            parts.Add(part.Node);
            variables.AddRange(part.WhenTrue);

            // Coverage follows the elements by where they stand -- from the
            // front before the '..', from the back after it -- and not what
            // the '..' itself is asked, which only makes a match rarer.
            if (written is SlicePatternSyntax)
            {
                runIsAnything = part.IsIrrefutable;
                continue;
            }

            object position = sliceAt < 0 || i < sliceAt
                ? ListPosition.FromStart(i)
                : ListPosition.FromEnd(syntax.Elements.Count - i);

            under.Add(new SpaceMember(position, partType, part.Under));
            over.Add(new SpaceMember(position, partType, part.Over));
        }

        if (failed)
            return null;

        if (syntax.Binding is { } name)
            parts.Add(BindPatternVariable(
                name, syntax.BindingSpan, viewed.Type, viewed, context, variables));

        var shape = new ListKey(
            sliceAt < 0 ? fixedCount : sliceAt,
            sliceAt < 0 ? 0 : syntax.Elements.Count - 1 - sliceAt,
            Open: sliceAt >= 0,
            ElementOf(viewed.Type));

        return new PatternMatch(new BoundReadPattern(span, counted, length, All(span, parts)))
        {
            WhenTrue = variables,
            Under = !runIsAnything || under.Any(m => m.Space is NoSpace)
                ? Space.None
                : new ConstructorSpace(shape, under),
            Over = new ConstructorSpace(shape, over),
        };
    }

    /// <summary>What a list pattern's elements are, for coverage.</summary>
    private static TypeSymbol ElementOf(TypeSymbol sequence) => sequence switch
    {
        ArrayTypeSymbol array => array.Element,
        SliceTypeSymbol slice => slice.Element,
        FixedArrayTypeSymbol inline => inline.Element,
        NamedTypeSymbol named => named.Properties
            .FirstOrDefault(p => p.IsIndexer)?.Type ?? ErrorTypeSymbol.Instance,
        _ => ErrorTypeSymbol.Instance,
    };

    /// <summary>A <c>nuint</c> index.</summary>
    private static BoundLiteral Index(SourceSpan span, int value) =>
        new(span, PrimitiveTypeSymbol.NUInt, (ulong)value);

    /// <summary>
    /// How to read a sequence: its length, an element at an index, and a
    /// slice between two indices where one can be taken.
    /// </summary>
    private (BoundExpression Length,
             Func<BoundExpression, BoundExpression> Element,
             Func<BoundExpression, BoundExpression, BoundExpression?> Slice)?
        ListShape(BoundExpression viewed, SourceSpan span)
    {
        switch (viewed.Type)
        {
            case ArrayTypeSymbol array:
                return (new BoundArrayLength(span, PrimitiveTypeSymbol.NUInt, viewed),
                        index => new BoundIndex(span, array.Element, viewed, index),
                        (from, to) => new BoundSlice(span, SliceOf(array.Element, readOnly: false), viewed, from, to));

            case SliceTypeSymbol slice:
                return (new BoundArrayLength(span, PrimitiveTypeSymbol.NUInt, viewed),
                        index => new BoundIndex(span, slice.Element, viewed, index),
                        (from, to) => new BoundSlice(span, SliceOf(slice.Element, slice.IsReadOnly), viewed, from, to));

            case FixedArrayTypeSymbol inline:
                return (Index(span, inline.Length),
                        index => new BoundIndex(span, inline.Element, viewed, index),
                        (_, _) => null);

            case NamedTypeSymbol named:
            {
                var counter = named.FindProperty("Count") ?? named.FindProperty("Length");
                if (counter is not { Type: PrimitiveTypeSymbol { IsInteger: true } countType } ||
                    counter.Getter is null)
                    return null;

                var sample = Index(span, 0);
                var indexer = named.Properties
                    .Where(p => p.IsIndexer && p.Getter is not null)
                    .Select(p => p.Getter!)
                    .FirstOrDefault(g => g.Parameters.Where(p => !p.IsThis).ToList() is
                        [{ Type: PrimitiveTypeSymbol { IsInteger: true } }]);

                if (indexer is null)
                    return null;

                var indexType = (PrimitiveTypeSymbol)indexer.Parameters.First(p => !p.IsThis).Type;
                var slicer = SliceMethodOf(named);

                return (AsInteger(BindPropertyRead(span, viewed, counter), PrimitiveTypeSymbol.NUInt),
                        index => BuildIndexerCall(span, indexer, viewed, [AsInteger(index, indexType)], null),
                        (from, to) => slicer is null ? null : SliceCall(slicer, named, viewed, from, to, span));
            }

            default:
                return null;
        }
    }

    /// <summary>
    /// <c>Slice(from, to - from)</c>. Both bounds are constants or reads of a
    /// held count, so naming <paramref name="from"/> twice evaluates nothing twice.
    /// </summary>
    private BoundExpression SliceCall(
        FunctionSymbol slicer, NamedTypeSymbol type, BoundExpression viewed,
        BoundExpression from, BoundExpression to, SourceSpan span)
    {
        var parameters = slicer.Parameters.Where(p => !p.IsThis).ToList();
        var count = new BoundBinary(span, PrimitiveTypeSymbol.NUInt, to, BoundBinaryOp.Subtract, from);

        return new BoundCall(span, slicer, AsReceiver(viewed, type),
        [
            AsInteger(from, (PrimitiveTypeSymbol)parameters[0].Type),
            AsInteger(count, (PrimitiveTypeSymbol)parameters[1].Type),
        ]);
    }

    /// <summary>An integer as another integer type, by the explicit conversion a cast would make.</summary>
    private BoundExpression AsInteger(BoundExpression value, PrimitiveTypeSymbol wanted)
    {
        if (value.Type.IsError() || value.Type.Equals(wanted))
            return value;

        return ClassifyConversion(value.Type, wanted, explicitCast: true) is { } kind
            ? new BoundConversion(value.Span, wanted, value, kind)
            : new BoundErrorExpression(value.Span);
    }

    // =============================================================== is

    /// <summary>
    /// <c>value is pattern</c>. What the pattern names is declared where the
    /// pattern assigns it; the condition the test stands in says where it is
    /// in scope.
    /// </summary>
    private BoundExpression BindIsPattern(IsPatternSyntax syntax)
    {
        var value = BindExpression(syntax.Value);
        if (value.Type.IsError())
            return new BoundErrorExpression(syntax.Span);
        if (RefuseUntyped(value))
            return new BoundErrorExpression(syntax.Span);

        var subject = new BoundPlaceholder(syntax.Value.Span, value.Type);
        var pattern = BindTopPattern(syntax.Pattern, subject, PatternSite.Is);
        if (pattern is null)
            return new BoundErrorExpression(syntax.Span);

        return new BoundIsPattern(syntax.Span, value, subject, pattern.Node)
        {
            AssignedWhenTrue = pattern.WhenTrue.Select(v => v.Local).ToList(),
            AssignedWhenFalse = pattern.WhenFalse.Select(v => v.Local).ToList(),
            CaseWhenTrue = pattern.CaseWhenTrue,
            CaseWhenFalse = pattern.CaseWhenFalse,
            NotNullWhenTrue = pattern.NotNullWhenTrue,
            NotNullWhenFalse = pattern.NotNullWhenFalse,
            BindsAtOnce = BindsAtOnce(syntax.Pattern),
        };
    }

    /// <summary>Whether a pattern names its subject with nothing but a type test first.</summary>
    private static bool BindsAtOnce(PatternSyntax pattern) =>
        pattern is TypePatternSyntax { Binding: not null } or VarPatternSyntax;

    /// <summary>
    /// The names a condition assigns when it is true and when it is false,
    /// through <c>!</c>, <c>&amp;&amp;</c> and <c>||</c>.
    /// </summary>
    private static (List<LocalSymbol> WhenTrue, List<LocalSymbol> WhenFalse) AssignedNames(
        BoundExpression condition)
    {
        switch (condition)
        {
            case BoundIsPattern test:
                return ([.. test.AssignedWhenTrue], [.. test.AssignedWhenFalse]);

            case BoundUnary { Operator: BoundUnaryOp.LogicalNot } negation:
            {
                var (whenTrue, whenFalse) = AssignedNames(negation.Operand);
                return (whenFalse, whenTrue);
            }

            case BoundBinary { Operator: BoundBinaryOp.LogicalAnd } and:
                return ([.. AssignedNames(and.Left).WhenTrue, .. AssignedNames(and.Right).WhenTrue], []);

            case BoundBinary { Operator: BoundBinaryOp.LogicalOr } or:
                return ([], [.. AssignedNames(or.Left).WhenFalse, .. AssignedNames(or.Right).WhenFalse]);

            default:
                return ([], []);
        }
    }

    /// <summary>Puts names into the innermost scope, which the caller has just pushed.</summary>
    private void ExposeNames(IEnumerable<LocalSymbol> names)
    {
        foreach (var local in names)
            _context.Locals[^1][local.Name] = local;
    }

    /// <summary>
    /// Binds something that runs only where <paramref name="condition"/> came
    /// out <paramref name="whenTrue"/>, with the names that outcome assigned in
    /// scope.
    ///
    /// An expression may declare as it goes -- <c>out var x</c> -- and what it
    /// declares belongs to the statement around it, so for an expression that
    /// is kept when the names are taken away again.
    /// </summary>
    private T BindWhereAssigned<T>(
        BoundExpression condition, bool whenTrue, Func<T> bind, bool isExpression = false)
    {
        var (assignedTrue, assignedFalse) = AssignedNames(condition);
        var names = whenTrue ? assignedTrue : assignedFalse;

        if (names.Count == 0)
            return bind();

        PushScope();
        ExposeNames(names);

        try
        {
            return bind();
        }
        finally
        {
            var inner = _context.Locals[^1];
            PopScope();

            if (isExpression)
                foreach (var (name, local) in inner.Where(pair => !names.Contains(pair.Value)))
                    _context.Locals[^1][name] = local;
        }
    }

    // ------------------------------------------------------------- guards

    /// <summary>
    /// A <c>when</c>, bound where what the pattern named is in scope. It is
    /// asked only where the pattern matched, so it reads what the pattern
    /// assigned.
    /// </summary>
    private BoundExpression? BindGuard(ExpressionSyntax? guard)
    {
        if (guard is null)
            return null;

        var condition = BindCondition(guard);
        return condition.Type.IsError() ? null : condition;
    }

    /// <summary>What a pattern proves about the value switched on, applied where it matched.</summary>
    private void ApplyPatternFacts(PatternMatch pattern, BoundExpression subject)
    {
        if (NarrowableSubject(subject) is not { } narrowed)
            return;

        if (pattern.CaseWhenTrue is { } only)
            _context.VariantFacts[narrowed] = Fact.Holding(only);
        else if (pattern.NotNullWhenTrue && subject.Type is OptionalTypeSymbol)
            _context.VariantFacts[narrowed] = Fact.NotNull;
    }

    // ------------------------------------------------------- switch statement

    /// <summary>
    /// Whether a label asks something other than "is it this constant" -- a
    /// type, a range, a <c>when</c>, a value taken apart -- which the checks
    /// the constant and variant forms make do not cover.
    /// </summary>
    private static bool NeedsPatterns(SwitchSyntax syntax, TypeSymbol subject) =>
        syntax.Sections.Any(section =>
            section.Guards.Any(guard => guard is not null) ||
            section.Patterns.Any(pattern => pattern switch
            {
                ConstantPatternSyntax => false,

                // Over a variant this is `case Circle c:`, which the variant
                // form checks; over anything else it is a type test.
                TypePatternSyntax { Binding: not null } => subject is not VariantTypeSymbol,
                TypePatternSyntax => true,
                _ => true,
            }));

    /// <summary>
    /// A switch whose labels are patterns: a pattern and a guard per label,
    /// asked in order.
    ///
    /// Everything else about it is the statement's own machinery -- sections
    /// that may not fall through, <c>break</c> that belongs to the switch,
    /// <c>default</c> where nothing matched -- because what changed is how a
    /// section is reached and nothing else.
    /// </summary>
    private BoundStatement BindPatternSwitch(SwitchSyntax syntax, BoundExpression value)
    {
        var subject = new BoundPlaceholder(syntax.Value.Span, value.Type);
        var sections = new List<BoundSwitchSection>();
        var covered = new Dictionary<VariantCaseSymbol, SourceSpan>();
        var rows = new List<Space>();
        bool sawDefault = false;
        var frame = OpenSwitchFrame(value.Type, overVariant: false);

        _context.SwitchDepth++;

        foreach (var section in syntax.Sections)
        {
            var labels = new List<BoundSwitchLabel>();
            var matched = new List<PatternMatch>();
            var guards = new List<ExpressionSyntax?>();
            var spans = new List<SourceSpan>();

            for (int i = 0; i < section.Patterns.Count; i++)
            {
                var pattern = BindTopPattern(section.Patterns[i], subject, PatternSite.Switch);
                if (pattern is null)
                    continue;

                var guard = i < section.Guards.Count ? section.Guards[i] : null;
                bool duplicate = false;

                if (WholeCase(pattern) is { } named && guard is null && !covered.TryAdd(named, section.Span))
                {
                    diagnostics.Error("SL0405", section.Span,
                        $"this switch already has a case for '{named.Name}'");
                    duplicate = true;
                }

                if (!duplicate && !IsReachable(rows, pattern.Over, value.Type))
                    diagnostics.Warning("SL0621", section.Patterns[i].Span,
                        "nothing reaches this label: the ones before it match everything it does");

                if (guard is null)
                {
                    rows.Add(pattern.Under);

                    // `case 3:` among patterns is still somewhere `goto case 3` lands.
                    if (pattern.Under is ConstructorSpace { Key: ValueKey constant, Members.Count: 0 })
                        frame.Cases.TryAdd(constant.Value, sections.Count);
                }

                matched.Add(pattern);
                guards.Add(guard);
                spans.Add(section.Patterns[i].Span);
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

            // A name belongs to one label: a section reached by two of them has
            // proved nothing about which, so there is nothing for a name to be.
            var naming = matched.FirstOrDefault(p => p.WhenTrue.Count > 0);

            if (naming is not null && matched.Count > 1)
            {
                diagnostics.Error("SL0619", section.Span,
                    $"'{naming.WhenTrue[0].Name}' is named by one label of a section with " +
                    "several, and which of them matched is not known in the body; give this " +
                    "label a section of its own");
                naming = null;
            }

            // The guards and the body see what the label named, and a label
            // that settles the governor narrows it for both.
            var saved = SnapshotFacts();
            PushScope();

            for (int i = 0; i < matched.Count; i++)
            {
                if (guards[i] is null)
                {
                    labels.Add(new BoundSwitchLabel(spans[i], matched[i].Node, null));
                    continue;
                }

                var entry = SnapshotFacts();
                PushScope();
                ExposeNames(matched[i].WhenTrue.Select(v => v.Local));
                ApplyPatternFacts(matched[i], value);
                labels.Add(new BoundSwitchLabel(spans[i], matched[i].Node, BindGuard(guards[i])));
                PopScope();
                _context.VariantFacts = entry;
            }

            if (naming is not null)
                ExposeNames(naming.WhenTrue.Select(v => v.Local));
            if (matched.Count == 1)
                ApplyPatternFacts(matched[0], value);

            var body = new BoundBlock(section.Span, BindStatementList(section.Statements));

            PopScope();
            _context.VariantFacts = saved;

            if (EndIsReachable(body))
                diagnostics.Error("SL0407", section.Span,
                    "a switch section must not run off its end; finish it with 'break', " +
                    "'return', 'continue' or 'goto'. Stack the labels instead, as in " +
                    "'case 1: case 2:', when two of them share a body");

            sections.Add(new BoundSwitchSection(section.Span, labels, section.HasDefault, body));
        }

        _context.SwitchDepth--;
        CloseSwitchFrame(frame, sections);

        // A statement over an enum is not exhaustive, as in C#: the value need
        // not be one of the members, and one that is none of them falls past.
        bool exhaustive = !IsReachable(rows, Space.Any, value.Type);

        if (!exhaustive && !sawDefault && value.Type is VariantTypeSymbol variant)
            diagnostics.Error("SL0436", syntax.Span,
                $"this switch over '{variant.Name}' does not cover " +
                Listed(UncoveredCases(rows, variant).Select(c => "'" + c.Name + "'")) +
                "; a variant is the choice between its cases, so a switch that leaves one " +
                "out has no answer for it. Add the case, or a 'default'",
                variant);

        return new BoundSwitch(syntax.Span, value, subject, sections) { IsExhaustive = exhaustive };
    }

    /// <summary>The case a pattern matches all of, where it is exactly a case and nothing more.</summary>
    private static VariantCaseSymbol? WholeCase(PatternMatch pattern) =>
        pattern.Under is ConstructorSpace { Key: VariantCaseSymbol whole } space &&
        space.Members.All(m => m.Space is AnySpace)
            ? whole
            : null;

    // ------------------------------------------------------ switch expression

    /// <summary>
    /// <c>value switch { pattern =&gt; result, ... }</c>.
    ///
    /// <para>
    /// <b>It has to be exhaustive</b> (SL0620), which is the one rule the
    /// statement does not have. A statement that matches nothing falls past
    /// itself; an expression that matched nothing would have no value to be,
    /// and there are no exceptions here to throw at the hole. An enum counts
    /// as covered once every member is named, and a value that is none of
    /// them ends the program where it arrives.
    /// </para>
    /// </summary>
    private BoundExpression BindSwitchExpression(SwitchExpressionSyntax syntax)
    {
        var value = BindExpression(syntax.Value);
        if (value.Type.IsError())
            return new BoundErrorExpression(syntax.Span);
        if (RefuseUntyped(value))
            return new BoundErrorExpression(syntax.Span);

        if (syntax.Arms.Count == 0)
        {
            diagnostics.Error("SL0620", syntax.Span,
                "this switch has no arms, so there is no value it could produce");
            return new BoundErrorExpression(syntax.Span);
        }

        var subject = new BoundPlaceholder(syntax.Value.Span, value.Type);
        var arms = new List<(PatternMatch Pattern, BoundExpression? Guard, BoundExpression Value)>();
        var covered = new Dictionary<VariantCaseSymbol, SourceSpan>();
        var rows = new List<Space>();

        foreach (var arm in syntax.Arms)
        {
            var pattern = BindTopPattern(arm.Pattern, subject, PatternSite.Switch);
            if (pattern is null)
                return new BoundErrorExpression(syntax.Span);

            bool duplicate = false;
            if (WholeCase(pattern) is { } matched && arm.Guard is null &&
                !covered.TryAdd(matched, arm.Span))
            {
                diagnostics.Error("SL0405", arm.Span,
                    $"this switch already has an arm for '{matched.Name}'");
                duplicate = true;
            }

            if (!duplicate && !IsReachable(rows, pattern.Over, value.Type))
                diagnostics.Warning("SL0621", arm.Span,
                    rows.Count > 0 && rows[^1] is AnySpace
                        ? "nothing reaches this arm: an earlier one matches everything"
                        : "nothing reaches this arm: the ones before it match everything it does");

            if (arm.Guard is null)
                rows.Add(pattern.Under);

            // The names, the guard and the value that may read them, where the
            // pattern matched and proved what it proved.
            var saved = SnapshotFacts();
            PushScope();

            ExposeNames(pattern.WhenTrue.Select(v => v.Local));
            ApplyPatternFacts(pattern, value);

            var guard = BindGuard(arm.Guard);
            var result = BindExpression(arm.Value);

            PopScope();
            _context.VariantFacts = saved;

            if (result.Type.IsError())
                return new BoundErrorExpression(syntax.Span);

            arms.Add((pattern, guard, result));
        }

        bool total = !IsReachable(rows, Space.Any, value.Type);
        bool totalAsNamed = total || !IsReachable(rows, Space.Any, value.Type, closedEnums: true);

        if (!totalAsNamed)
        {
            diagnostics.Error("SL0620", syntax.Span, Uncovered(rows, value.Type));
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

        var bound = new List<BoundSwitchArm>(arms.Count);
        for (int i = 0; i < arms.Count; i++)
            bound.Add(new BoundSwitchArm(syntax.Arms[i].Span,
                arms[i].Pattern.Node,
                arms[i].Guard,
                BindConversion(arms[i].Value, resultType, syntax.Arms[i].Value.Span)));

        return new BoundSwitchExpression(syntax.Span, resultType, value, subject, bound) { IsTotal = total };
    }
}
