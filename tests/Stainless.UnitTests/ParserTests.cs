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

using Stainless.Syntax;
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// The shape the parser gives an expression, which nothing downstream can
/// disagree with.
///
/// A program that runs proves its arithmetic came out right, and would go on
/// proving it if precedence were wrong in a way the test's own numbers hid.
/// These ask for the tree.
/// </summary>
public class ParserTests
{
    /// <summary>
    /// A parenthesised rendering of an expression tree, so a test can state the
    /// shape it wants in one line instead of walking it.
    /// </summary>
    private static string Shape(string source) => Render(Front.Expression(source));

    private static string Render(ExpressionSyntax? expression) => expression switch
    {
        LiteralSyntax literal => literal.Value?.ToString() ?? "null",
        NameSyntax name => name.Name.Text + Arguments(name.TypeArguments),
        ThisSyntax => "this",
        BaseSyntax => "base",
        UnarySyntax unary => $"({unary.Operator.FixedText()} {Render(unary.Operand)})",
        BinarySyntax binary =>
            $"({binary.Operator.FixedText()} {Render(binary.Left)} {Render(binary.Right)})",
        AssignmentSyntax assignment =>
            $"({assignment.Operator.FixedText()} {Render(assignment.Target)} " +
            $"{Render(assignment.Value)})",
        ConditionalSyntax conditional =>
            $"(?: {Render(conditional.Condition)} {Render(conditional.WhenTrue)} " +
            $"{Render(conditional.WhenFalse)})",
        MemberAccessSyntax member =>
            $"({(member.Conditional ? "?." : ".")} {Render(member.Target)} " +
            $"{member.Member}{Arguments(member.TypeArguments)})",
        IndexSyntax index =>
            $"({(index.Conditional ? "?[]" : "[]")} {Render(index.Target)}" +
            $"{string.Concat(index.Indices.Select(i => " " + Render(i)))})",
        SliceSyntax slice =>
            $"({(slice.Conditional ? "?[:]" : "[:]")} {Render(slice.Target)} " +
            $"{Render(slice.Start)} {Render(slice.End)})",
        NullForgivingSyntax forgiven => $"(forgive {Render(forgiven.Operand)})",
        DefaultSyntax zeroed => zeroed.Type is null ? "default" : $"default({Render(zeroed.Type)})",
        CallSyntax call =>
            $"(call {Render(call.Callee)}{string.Concat(call.Arguments.Select(a => " " + Render(a)))})",
        CastSyntax cast => $"(cast {Render(cast.Operand)})",
        IsPatternSyntax test => $"(is {Render(test.Value)} {Render(test.Pattern)})",
        NewSyntax made => made.Type is null ? "new()" : "new",
        ArrayLiteralSyntax array =>
            $"[{string.Join(" ", array.Elements.Select(Render))}]",
        IndexFromEndSyntax fromEnd => $"(hat {Render(fromEnd.Operand)})",
        RangeSyntax range => $"(.. {Render(range.Start)} {Render(range.End)})",
        SpreadElementSyntax spread => $"(spread {Render(spread.Operand)})",
        TupleSyntax tuple => $"(tuple {string.Join(" ", tuple.Elements.Select(Render))})",
        DeclarationExpressionSyntax declared =>
            $"(declare {(declared.Type is null ? "var" : Render(declared.Type))} {declared.Name})",
        null => "_",
        _ => expression.GetType().Name,
    };

    private static string Render(PatternSyntax pattern) => pattern switch
    {
        DiscardPatternSyntax => "_",
        VarPatternSyntax named => $"(var {named.Name})",
        ConstantPatternSyntax constant => Render(constant.Value),
        RelationalPatternSyntax relational => $"({relational.Operator.FixedText()} {Render(relational.Value)})",
        TypePatternSyntax typed => $"(type {Render(typed.Type)}{(typed.Binding is null ? "" : " " + typed.Binding)})",
        NotPatternSyntax negated => $"(not {Render(negated.Operand)})",
        BinaryPatternSyntax combined =>
            $"({(combined.IsOr ? "or" : "and")} {Render(combined.Left)} {Render(combined.Right)})",
        RecursivePatternSyntax recursive =>
            "(match" + (recursive.Type is null ? "" : " " + Render(recursive.Type)) +
            (recursive.Positional is null ? "" : " (" + string.Join(" ", recursive.Positional.Select(Render)) + ")") +
            (recursive.Properties is null ? "" : " {" + string.Join(" ", recursive.Properties.Select(Render)) + "}") +
            (recursive.Binding is null ? "" : " " + recursive.Binding) + ")",
        ListPatternSyntax list =>
            "[" + string.Join(" ", list.Elements.Select(Render)) + "]" +
            (list.Binding is null ? "" : " " + list.Binding),
        SlicePatternSyntax slice => slice.Pattern is null ? ".." : $"(.. {Render(slice.Pattern)})",
        _ => pattern.GetType().Name,
    };

    private static string Render(SubpatternSyntax element) =>
        (element.Path.Count == 0 ? "" : string.Join(".", element.Path) + ": ") + Render(element.Pattern);

    private static string Render(TypeSyntax type) => type switch
    {
        PrimitiveTypeSyntax primitive => primitive.Keyword.FixedText() ?? "?",
        NamedTypeSyntax named => named.Name.Text + Arguments(named.TypeArguments),
        NullableTypeSyntax nullable => Render(nullable.Element) + "?",
        ArrayTypeSyntax array => Render(array.Element) + "[]",
        _ => type.GetType().Name,
    };

    private static string Arguments(IReadOnlyList<TypeSyntax>? arguments) =>
        arguments is null or { Count: 0 } ? "" : $"<{string.Join(",", arguments.Select(Render))}>";

    // ---------------------------------------------------------- precedence

    [Theory]
    [InlineData("1 + 2 * 3", "(+ 1 (* 2 3))")]
    [InlineData("1 * 2 + 3", "(+ (* 1 2) 3)")]
    [InlineData("1 + 2 - 3", "(- (+ 1 2) 3)")]
    [InlineData("1 << 2 + 3", "(<< 1 (+ 2 3))")]
    [InlineData("1 & 2 | 3", "(| (& 1 2) 3)")]
    [InlineData("1 | 2 ^ 3", "(| 1 (^ 2 3))")]
    [InlineData("a && b || c", "(|| (&& a b) c)")]
    [InlineData("a == b && c", "(&& (== a b) c)")]
    [InlineData("a < b == c", "(== (< a b) c)")]
    [InlineData("a + b < c + d", "(< (+ a b) (+ c d))")]
    public void BinaryOperatorsBindByPrecedence(string source, string shape) =>
        Assert.Equal(shape, Shape(source));

    /// <summary>
    /// Arithmetic is left-associative, which only a tree can show: <c>1 - 2 -
    /// 3</c> evaluates to -4 either way round in most test programs.
    /// </summary>
    [Theory]
    [InlineData("1 - 2 - 3", "(- (- 1 2) 3)")]
    [InlineData("1 / 2 / 3", "(/ (/ 1 2) 3)")]
    [InlineData("1 % 2 % 3", "(% (% 1 2) 3)")]
    [InlineData("a . b . c", "(. (. a b) c)")]
    public void BinaryOperatorsAreLeftAssociative(string source, string shape) =>
        Assert.Equal(shape, Shape(source));

    [Theory]
    [InlineData("a = b = c", "(= a (= b c))")]
    [InlineData("a += b += c", "(+= a (+= b c))")]
    [InlineData("a ? b : c ? d : e", "(?: a b (?: c d e))")]
    public void AssignmentAndTheConditionalAreRightAssociative(
        string source, string shape) => Assert.Equal(shape, Shape(source));

    [Theory]
    [InlineData("a = b + c", "(= a (+ b c))")]
    [InlineData("a + b ? c : d", "(?: (+ a b) c d)")]
    [InlineData("a = b ? c : d", "(= a (?: b c d))")]
    public void AssignmentBindsLastOfAll(string source, string shape) =>
        Assert.Equal(shape, Shape(source));

    [Theory]
    [InlineData("(1 + 2) * 3", "(* (+ 1 2) 3)")]
    [InlineData("1 * (2 + 3)", "(* 1 (+ 2 3))")]
    public void ParenthesesOverridePrecedence(string source, string shape) =>
        Assert.Equal(shape, Shape(source));

    // ------------------------------------------------------------- unary

    [Theory]
    [InlineData("-a * b", "(* (- a) b)")]
    [InlineData("-a.b", "(- (. a b))")]
    [InlineData("!a && b", "(&& (! a) b)")]
    [InlineData("!a.b", "(! (. a b))")]
    [InlineData("~a + b", "(+ (~ a) b)")]
    [InlineData("-a[0]", "(- ([] a 0))")]
    [InlineData("-f(x)", "(- (call f x))")]
    public void UnaryBindsTighterThanBinaryAndLooserThanPostfix(
        string source, string shape) => Assert.Equal(shape, Shape(source));

    // ------------------------------------------------------------ postfix

    [Theory]
    [InlineData("a.b.c", "(. (. a b) c)")]
    [InlineData("a.b(c)", "(call (. a b) c)")]
    [InlineData("f(a)(b)", "(call (call f a) b)")]
    [InlineData("a[0][1]", "([] ([] a 0) 1)")]
    [InlineData("f(a).b", "(. (call f a) b)")]
    [InlineData("a[0].b", "(. ([] a 0) b)")]
    public void PostfixChainsLeftToRight(string source, string shape) =>
        Assert.Equal(shape, Shape(source));

    [Theory]
    [InlineData("f()", "(call f)")]
    [InlineData("f(a)", "(call f a)")]
    [InlineData("f(a, b, c)", "(call f a b c)")]
    public void ArgumentsAreCollectedInOrder(string source, string shape) =>
        Assert.Equal(shape, Shape(source));

    // ------------------------------------------------------ type arguments

    /// <summary>
    /// C#'s rule for a <c>&lt;</c> after a name: type arguments when what is
    /// inside parses as types and the token after the <c>&gt;</c> is one that
    /// could follow them, and a less-than otherwise.
    /// </summary>
    [Theory]
    [InlineData("F<int>(x)", "(call F<int> x)")]
    [InlineData("F<A, B>(7)", "(call F<A,B> 7)")]
    [InlineData("F(G<A, B>(7))", "(call F (call G<A,B> 7))")]
    [InlineData("F<List<int>>()", "(call F<List<int>>)")]
    [InlineData("F<List<List<int>>>()", "(call F<List<List<int>>>)")]
    [InlineData("Box<int>.Create()", "(call (. Box<int> Create))")]
    [InlineData("Box<int>.Count", "(. Box<int> Count)")]
    [InlineData("a.M<T>()", "(call (. a M<T>))")]
    [InlineData("a?.M<T>()", "(call (?. a M<T>))")]
    [InlineData("A.B<int>.C", "(. (. A B<int>) C)")]
    [InlineData("F<int> == x", "(== F<int> x)")]
    public void ALessThanAfterANameMayOpenTypeArguments(string source, string shape) =>
        Assert.Equal(shape, Shape(source));

    [Theory]
    [InlineData("F(a < b, c > d)", "(call F (< a b) (> c d))")]
    [InlineData("a < b > c", "(> (< a b) c)")]
    [InlineData("a < b == c > d", "(== (< a b) (> c d))")]
    [InlineData("a < b && c > d", "(&& (< a b) (> c d))")]
    [InlineData("x < y >> 1", "(< x (>> y 1))")]
    [InlineData("i < n ? a : b", "(?: (< i n) a b)")]
    [InlineData("F(a < b, c >= d)", "(call F (< a b) (>= c d))")]
    [InlineData("F(a < b, c > -1)", "(call F (< a b) (> c (- 1)))")]
    [InlineData("a < b[0]", "(< a ([] b 0))")]
    public void ALessThanThatCannotOpenTypeArgumentsIsAComparison(string source, string shape) =>
        Assert.Equal(shape, Shape(source));

    // --------------------------------------------------- ?[ and postfix !

    /// <summary>
    /// <c>?[</c> is <c>a?[i]</c> unless a <c>:</c> follows the expression
    /// after the <c>?</c>, which makes it a conditional with an array literal
    /// in its true arm. Roslyn's rule, including the re-parse of an enclosing
    /// conditional's true arm that lost its <c>:</c> to the guess.
    /// </summary>
    [Theory]
    [InlineData("a?[0]", "(?[] a 0)")]
    [InlineData("a?[0]?.Name", "(?. (?[] a 0) Name)")]
    [InlineData("a?[i:j]", "(?[:] a i j)")]
    [InlineData("a?[0] ?? b", "(?? (?[] a 0) b)")]
    [InlineData("a ? [0] : [1]", "(?: a [0] [1])")]
    [InlineData("a ?[0] : b", "(?: a [0] b)")]
    [InlineData("c ? a?[i] : b", "(?: c (?[] a i) b)")]
    [InlineData("c ? a?[i] : d ? [1] : [2]", "(?: c (?[] a i) (?: d [1] [2]))")]
    public void AQuestionBracketIsAnElementAccessUnlessAColonFollows(string source, string shape) =>
        Assert.Equal(shape, Shape(source));

    [Theory]
    [InlineData("x!", "(forgive x)")]
    [InlineData("a!.b", "(. (forgive a) b)")]
    [InlineData("a![0]", "([] (forgive a) 0)")]
    [InlineData("F()!", "(forgive (call F))")]
    [InlineData("!a!", "(! (forgive a))")]
    [InlineData("a != b", "(!= a b)")]
    [InlineData("a! != b", "(!= (forgive a) b)")]
    [InlineData("(a)!.b", "(. (forgive a) b)")]
    [InlineData("(a)!b", "(cast (! b))")]
    public void APostfixBangForgivesANull(string source, string shape) =>
        Assert.Equal(shape, Shape(source));

    // ------------------------------------------------- new() and default

    [Theory]
    [InlineData("new(1, 2)", "new()")]
    [InlineData("new()", "new()")]
    [InlineData("new Point(1)", "new")]
    [InlineData("default", "default")]
    [InlineData("default(int)", "default(int)")]
    [InlineData("x == default", "(== x default)")]
    [InlineData("F(default, new())", "(call F default new())")]
    public void NewAndDefaultMayLeaveTheirTypeOff(string source, string shape) =>
        Assert.Equal(shape, Shape(source));

    [Fact]
    public void ABareDefaultIsNotAPattern()
    {
        var diagnostics = ParseMalformed("""
            module A;
            int F(int x)
            {
                switch (x)
                {
                    case default:
                        return 1;
                }
                return 0;
            }
            """);
        Assert.Contains("SL0758", diagnostics);
    }

    [Fact]
    public void TheDefaultLabelStillWorks()
    {
        Front.Parse("""
            module A;
            int F(int x)
            {
                switch (x)
                {
                    case 1:
                        return 1;
                    default:
                        return default;
                }
            }
            """, out var diagnostics);
        Assert.False(diagnostics.HasErrors);
    }

    /// <summary>
    /// <c>goto case</c> and <c>goto default</c> are their own statement; a
    /// plain <c>goto</c> still names a label.
    /// </summary>
    [Fact]
    public void GotoCaseAndGotoDefaultNameASection()
    {
        var unit = Front.Parse("""
            module A;
            void F(int x)
            {
                switch (x)
                {
                    case 1: goto case 2 + 1;
                    case 3: goto default;
                    default: goto done;
                }
            done:
                return;
            }
            """, out var diagnostics);
        Assert.False(diagnostics.HasErrors);

        var function = Assert.IsType<FunctionDeclSyntax>(unit.Declarations[0]);
        var chosen = Assert.IsType<SwitchSyntax>(function.Body!.Statements[0]);

        var toCase = Assert.IsType<GotoCaseSyntax>(chosen.Sections[0].Statements[0]);
        Assert.IsType<BinarySyntax>(toCase.Value);
        Assert.Null(Assert.IsType<GotoCaseSyntax>(chosen.Sections[1].Statements[0]).Value);
        Assert.Equal("done", Assert.IsType<GotoSyntax>(chosen.Sections[2].Statements[0]).Label);
    }

    // ------------------------------------------------------------- slices

    /// <summary>
    /// A slice bound may be left out at either end, and the parser has to tell
    /// <c>a[1]</c> from <c>a[1:]</c> without backtracking.
    /// </summary>
    [Theory]
    [InlineData("a[1:2]", "([:] a 1 2)")]
    [InlineData("a[1:]", "([:] a 1 _)")]
    [InlineData("a[:2]", "([:] a _ 2)")]
    [InlineData("a[:]", "([:] a _ _)")]
    [InlineData("a[1]", "([] a 1)")]
    public void SliceBoundsMayBeOmitted(string source, string shape) =>
        Assert.Equal(shape, Shape(source));

    /// <summary>
    /// A statement that opens with <c>a[:]</c> is tried as a declaration of a
    /// <c>T[:]</c> first. That guess is put back when it fails, and so is its
    /// complaint about how a slice is spelled.
    /// </summary>
    [Theory]
    [InlineData("a[:].CopyTo(b);")]
    [InlineData("a[:][0u] = 1;")]
    [InlineData("a[:][1:].CopyTo(b);")]
    public void AWholeSliceOpeningAStatementIsAnExpression(string statement)
    {
        Front.Parse($"module A;\nvoid F(int[] a, int[] b) {{ {statement} }}", out var diagnostics);
        Assert.DoesNotContain(diagnostics.Items, d => d.Code == "SL0807");
    }

    /// <summary>And a slice's type written that way is still told how it is spelled.</summary>
    [Fact]
    public void ASliceTypeWrittenWithBracketsIsStillRefused()
    {
        Front.Parse("module A;\nvoid F(int[] a) { int[:] c = a[:]; }", out var diagnostics);
        Assert.Contains(diagnostics.Items, d => d.Code == "SL0807");
    }

    // ------------------------------------------------- indexes and ranges

    /// <summary>
    /// <c>^</c> in front of an operand counts from the end, and <c>..</c>
    /// binds tighter than any binary operator, as in C#, so <c>0..n - 1</c>
    /// is a range minus one rather than a range to <c>n - 1</c>.
    /// </summary>
    [Theory]
    [InlineData("a[^1]", "([] a (hat 1))")]
    [InlineData("a ^ ^b", "(^ a (hat b))")]
    [InlineData("a[1..^1]", "([] a (.. 1 (hat 1)))")]
    [InlineData("a[..]", "([] a (.. _ _))")]
    [InlineData("a[..2]", "([] a (.. _ 2))")]
    [InlineData("a[i..]", "([] a (.. i _))")]
    [InlineData("a[^2..]", "([] a (.. (hat 2) _))")]
    [InlineData("a[1:^1]", "([:] a 1 (hat 1))")]
    [InlineData("1..2", "(.. 1 2)")]
    [InlineData("0..n - 1", "(- (.. 0 n) 1)")]
    [InlineData("x.y..z.w", "(.. (. x y) (. z w))")]
    [InlineData("-a..b", "(.. (- a) b)")]
    [InlineData("f(1.., ..2)", "(call f (.. 1 _) (.. _ 2))")]
    public void IndexesAndRangesParse(string source, string shape) =>
        Assert.Equal(shape, Shape(source));

    [Theory]
    [InlineData("a >>> b", "(>>> a b)")]
    [InlineData("a >>> b >> c", "(>> (>>> a b) c)")]
    [InlineData("a + b >>> c", "(>>> (+ a b) c)")]
    [InlineData("a >>>= 2", "(>>>= a 2)")]
    [InlineData("F<List<List<List<int>>>>()", "(call F<List<List<List<int>>>>)")]
    public void UnsignedShiftParsesAsAShift(string source, string shape) =>
        Assert.Equal(shape, Shape(source));

    // -------------------------------------------------------- array literals

    [Theory]
    [InlineData("[]", "[]")]
    [InlineData("[1]", "[1]")]
    [InlineData("[1, 2, 3]", "[1 2 3]")]
    [InlineData("[1 + 2, 3]", "[(+ 1 2) 3]")]
    [InlineData("[..a]", "[(spread a)]")]
    [InlineData("[1, ..a, ..b.c, 2]", "[1 (spread a) (spread (. b c)) 2]")]
    [InlineData("[(..a)]", "[(.. _ a)]")]
    [InlineData("[..a[1..]]", "[(spread ([] a (.. 1 _)))]")]
    public void ArrayLiteralsCollectTheirElements(string source, string shape) =>
        Assert.Equal(shape, Shape(source));

    /// <summary>A trailing comma is allowed, so a generated list need not care.</summary>
    [Fact]
    public void AnArrayLiteralMayEndWithAComma() =>
        Assert.Equal("[1 2]", Shape("[1, 2,]"));

    // ------------------------------------------------------------ literals

    [Fact]
    public void TrueAndFalseAreLiterals()
    {
        Assert.IsType<LiteralSyntax>(Front.Expression("true"));
        Assert.IsType<LiteralSyntax>(Front.Expression("false"));
        Assert.Equal(true, ((LiteralSyntax)Front.Expression("true")).Value);
    }

    [Fact]
    public void NullIsALiteral() =>
        Assert.Equal(TokenKind.NullKeyword, ((LiteralSyntax)Front.Expression("null")).Kind);

    // -------------------------------------------------------------- spans

    /// <summary>
    /// An expression's span covers all of it. Every caret under a type error
    /// is this, and no end-to-end case can see it.
    /// </summary>
    [Theory]
    [InlineData("1 + 2 * 3")]
    [InlineData("f(a, b)")]
    [InlineData("a.b[c]")]
    [InlineData("-x")]
    [InlineData("a ? b : c")]
    public void AnExpressionSpansItsWholeText(string source)
    {
        var span = Front.Expression(source).Span;
        Assert.Equal(0, span.Start);
        Assert.Equal(source.Length, span.End);
    }

    [Fact]
    public void ASubexpressionSpansOnlyItself()
    {
        const string source = "1000 + 2";
        var binary = (BinarySyntax)Front.Expression(source);

        Assert.Equal("1000", source[binary.Left.Span.Start..binary.Left.Span.End]);
        Assert.Equal("2", source[binary.Right.Span.Start..binary.Right.Span.End]);
    }

    // --------------------------------------------------------- declarations

    [Fact]
    public void AFileRemembersItsModule()
    {
        var unit = Front.Parse("module App.Thing;");
        Assert.Equal("App.Thing", unit.ModuleName?.Text);
    }

    [Fact]
    public void ImportsAreCollected()
    {
        var unit = Front.Parse("module A;\nimport B;\nimport C.D;");
        Assert.Equal(["B", "C.D"], unit.Imports.Select(i => i.Name.Text));
    }

    [Fact]
    public void AFunctionCollectsItsParameters()
    {
        var unit = Front.Parse("module A;\nint F(int a, string b) { return 0; }");
        var function = Assert.IsType<FunctionDeclSyntax>(unit.Declarations[0]);

        Assert.Equal("F", function.Name);
        Assert.Equal(["a", "b"], function.Parameters.Select(p => p.Name));
    }

    [Theory]
    [InlineData("int F(params int[] values)", true)]
    [InlineData("int F(params Span<int> values)", true)]
    [InlineData("int F(ref params int[] values)", true)]
    [InlineData("int F(params values)", false)]
    [InlineData("int F(params values, int b)", false)]
    public void ParamsIsAModifierOnlyWhereATypeFollows(string head, bool gathers)
    {
        var unit = Front.Parse("module A;\n" + head + " => 0;", out var diagnostics);
        var function = Assert.IsType<FunctionDeclSyntax>(unit.Declarations[0]);

        Assert.Empty(diagnostics.Items);
        Assert.Equal(gathers, function.Parameters[0].IsParams);
    }

    [Fact]
    public void AStaticLambdaSaysSo()
    {
        var lambda = Assert.IsType<LambdaSyntax>(Front.Expression("static (int x) => x"));
        Assert.True(lambda.IsStatic);
        Assert.Null(lambda.ReturnType);
    }

    [Theory]
    [InlineData("int (x) => x")]
    [InlineData("Node? () => null")]
    [InlineData("List<int> (int n) => { return null; }")]
    [InlineData("(int, String) (int n) => (n, \"\")")]
    [InlineData("static long (int a, int b) => a")]
    public void ALambdaMayWriteItsResult(string source)
    {
        var lambda = Assert.IsType<LambdaSyntax>(Front.Expression(source, out var diagnostics));
        Assert.Empty(diagnostics.Items);
        Assert.NotNull(lambda.ReturnType);
    }

    /// <summary>Up to the arrow a written result is a call, so a call stays one.</summary>
    [Theory]
    [InlineData("F(x)")]
    [InlineData("F(x) + 1")]
    [InlineData("List<int>(n)")]
    public void ACallIsNotALambda(string source) =>
        Assert.IsNotType<LambdaSyntax>(Front.Expression(source));

    [Fact]
    public void ALambdaParameterMayHaveADefault()
    {
        var lambda = Assert.IsType<LambdaSyntax>(Front.Expression("(int x = 1, int y = -2) => x"));
        Assert.All(lambda.Parameters, p => Assert.NotNull(p.Default));
    }

    /// <summary>
    /// A <c>?</c> after the type in <c>is</c> or <c>as</c> is a conditional's
    /// where an expression and a colon follow it, as C# reads it.
    /// </summary>
    [Theory]
    [InlineData("x is Node ? 1 : 2")]
    [InlineData("x as Node ? a : b")]
    [InlineData("x is int ? \"yes\" : \"no\"")]
    public void AQuestionAfterATypeTestMayBeAConditional(string source) =>
        Assert.IsType<ConditionalSyntax>(Front.Expression(source));

    [Fact]
    public void ANullableTypeTestStaysOne()
    {
        var test = Assert.IsType<IsPatternSyntax>(Front.Expression("x is Node? found"));
        var typed = Assert.IsType<TypePatternSyntax>(test.Pattern);
        Assert.IsType<NullableTypeSyntax>(typed.Type);
    }

    /// <summary>
    /// What follows <c>is</c> is a pattern, and each shape of one parses to the
    /// node it names.
    /// </summary>
    [Theory]
    [InlineData("x is null", "(is x null)")]
    [InlineData("x is not null", "(is x (not null))")]
    [InlineData("x is > 5 and < 10", "(is x (and (> 5) (< 10)))")]
    [InlineData("x is 1 or 2", "(is x (or 1 2))")]
    [InlineData("x is Circle c", "(is x (type Circle c))")]
    [InlineData("x is Level.Low", "(is x (. Level Low))")]
    [InlineData("x is List<int>", "(is x (type List<int>))")]
    [InlineData("x is int[]", "(is x (type int[]))")]
    [InlineData("x is Circle { Radius: > 1 } c", "(is x (match Circle {Radius: (> 1)} c))")]
    [InlineData("x is { Owner.Name: \"a\" }", "(is x (match {Owner.Name: a}))")]
    [InlineData("x is { }", "(is x (match {}))")]
    [InlineData("x is (1, _)", "(is x (match (1 _)))")]
    [InlineData("x is (X: 1, Y: var y)", "(is x (match (X: 1 Y: (var y))))")]
    [InlineData("x is Point(0, var y)", "(is x (match Point (0 (var y))))")]
    [InlineData("x is var (a, b)", "(is x (match ((var a) (var b))))")]
    [InlineData("x is var _", "(is x _)")]
    [InlineData("x is (Circle or Square)", "(is x (or Circle Square))")]
    [InlineData("x is [1, .., var last]", "(is x [1 .. (var last)])")]
    [InlineData("x is [.. var rest] all", "(is x [(.. (var rest))] all)")]
    [InlineData("x is []", "(is x [])")]
    [InlineData("x is Value()", "(is x (call Value))")]
    [InlineData("x is (byte)1", "(is x (cast 1))")]
    public void APatternFollowsIs(string source, string shape) =>
        Assert.Equal(shape, Shape(source));

    /// <summary>A pattern ends where the expression around it goes on.</summary>
    [Theory]
    [InlineData("x is null && y", "(&& (is x null) y)")]
    [InlineData("x is Node n || y", "(|| (is x (type Node n)) y)")]
    [InlineData("!(x is 1 or 2)", "(! (is x (or 1 2)))")]
    public void APatternStopsAtTheExpressionAroundIt(string source, string shape) =>
        Assert.Equal(shape, Shape(source));

    [Fact]
    public void ATypeCollectsItsMembers()
    {
        var unit = Front.Parse("module A;\nclass C { int x; int F() { return 0; } }");
        var type = Assert.IsType<TypeDeclSyntax>(unit.Declarations[0]);

        Assert.Equal("C", type.Name);
        Assert.Single(type.Members.OfType<FieldDeclSyntax>());
        Assert.Single(type.Members.OfType<FunctionDeclSyntax>());
    }

    private static PropertyDeclSyntax OnlyProperty(string members)
    {
        var unit = Front.Parse("module A;\nclass C { " + members + " }");
        var type = Assert.IsType<TypeDeclSyntax>(unit.Declarations[0]);
        return Assert.Single(type.Members.OfType<PropertyDeclSyntax>());
    }

    [Fact]
    public void AnInitAccessorIsASetterThatSaysSo()
    {
        var property = OnlyProperty("public int X { get; init; }");

        Assert.False(property.Accessors[0].IsInit);
        Assert.False(property.Accessors[1].IsGetter);
        Assert.True(property.Accessors[1].IsInit);
    }

    [Theory]
    [InlineData("int X { get => field; }", true)]
    [InlineData("int X { get; set => field = value; }", true)]
    [InlineData("int X => field + 1;", true)]
    [InlineData("int X { get => @field; }", false)]
    [InlineData("int X { get => this.field; }", false)]
    public void FieldInAnAccessorNamesTheStorage(string member, bool storage) =>
        Assert.Equal(storage, OnlyProperty(member).Accessors.Any(a => a.UsesField));

    [Fact]
    public void FieldOutsideAnAccessorIsAName() =>
        Assert.Equal("(+ field 1)", Shape("field + 1"));

    [Theory]
    [InlineData("required int X;", true)]
    [InlineData("public required String Name { get; init; }", true)]
    [InlineData("required List<int> Items;", true)]
    [InlineData("required value;", false)]
    public void RequiredIsAModifierOnlyBeforeAMember(string member, bool required)
    {
        var unit = Front.Parse("module A;\nclass C { " + member + " }");
        var type = Assert.IsType<TypeDeclSyntax>(unit.Declarations[0]);

        Assert.Equal(required, type.Members[0].Modifiers.HasFlag(Modifiers.Required));
    }

    [Theory]
    [InlineData("internal class C { }")]
    [InlineData("internal int Count() => 0;")]
    [InlineData("internal const int Limit = 4;")]
    [InlineData("internal enum Level { Low }")]
    [InlineData("internal using Handle = void*;")]
    [InlineData("internal extern \"C\" int abs(int value);")]
    public void InternalIsAModifier(string declaration)
    {
        var unit = Front.Parse("module A;\n" + declaration, out var diagnostics);

        Assert.Empty(Front.Codes(diagnostics));
        Assert.True(unit.Declarations[0].Modifiers.HasFlag(Modifiers.Internal));
    }

    [Theory]
    [InlineData("internal int X;")]
    [InlineData("protected internal int X;")]
    [InlineData("internal protected int X;")]
    [InlineData("public int X { get; internal set; }")]
    public void InternalIsAMemberModifier(string member)
    {
        Front.Parse("module A;\nclass C { " + member + " }", out var diagnostics);
        Assert.Empty(Front.Codes(diagnostics));
    }

    [Theory]
    [InlineData("public internal int X;")]
    [InlineData("private internal int X;")]
    [InlineData("public private int X;")]
    [InlineData("public protected int X;")]
    [InlineData("private protected int X;")]
    [InlineData("internal internal int X;")]
    [InlineData("static static int X;")]
    [InlineData("public public int X;")]
    public void AModifierIsWrittenOnceAndAVisibilityOnce(string member)
    {
        Front.Parse("module A;\nclass C { " + member + " }", out var diagnostics);
        Assert.Equal(["SL0109"], Front.Codes(diagnostics));
    }

    [Fact]
    public void AMemberOfAnExternBlockKeepsItsOwnVisibility()
    {
        var unit = Front.Parse(
            "module A;\npublic extern \"C\" { int abs(int v); internal int labs(int v); }",
            out var diagnostics);

        Assert.Empty(Front.Codes(diagnostics));
        Assert.True(unit.Declarations[0].Modifiers.HasFlag(Modifiers.Public));
        Assert.Equal(
            Modifiers.Internal,
            unit.Declarations[1].Modifiers & (Modifiers.Public | Modifiers.Internal));
    }

    [Fact]
    public void APrimaryParameterListIsAConstructor()
    {
        var unit = Front.Parse("module A;\nclass D(int x, String s) : B(x), I { }");
        var type = Assert.IsType<TypeDeclSyntax>(unit.Declarations[0]);
        var constructor = Assert.Single(type.Members.OfType<ConstructorDeclSyntax>());

        Assert.True(constructor.IsPrimary);
        Assert.Equal(["x", "s"], constructor.Parameters.Select(p => p.Name));
        Assert.Equal(["x", "s"], type.PrimaryParameters.Select(p => p.Name));
        Assert.Equal(2, type.Implements.Count);

        var chain = Assert.IsType<ExpressionStatementSyntax>(constructor.Body.Statements[0]);
        Assert.IsType<BaseSyntax>(Assert.IsType<CallSyntax>(chain.Expression).Callee);
    }

    [Fact]
    public void AClassWithAPrimaryConstructorMayEndAtASemicolon()
    {
        var unit = Front.Parse("module A;\nclass P(int x);");
        var type = Assert.IsType<TypeDeclSyntax>(unit.Declarations[0]);

        Assert.False(type.IsOpaque);
        Assert.True(Assert.Single(type.Members.OfType<ConstructorDeclSyntax>()).IsPrimary);
    }

    [Fact]
    public void SetsRequiredMembersIsReadOffAConstructor()
    {
        var unit = Front.Parse(
            "module A;\nclass C { [SetsRequiredMembers] C(int x) { } C() { } }",
            out var diagnostics);
        var type = Assert.IsType<TypeDeclSyntax>(unit.Declarations[0]);

        Assert.False(diagnostics.HasErrors);
        Assert.Equal([true, false],
            type.Members.OfType<ConstructorDeclSyntax>().Select(c => c.SetsRequiredMembers));
    }

    // -------------------------------------------------------------- errors

    /// <summary>
    /// A missing token is reported once and the parse goes on, so a file with
    /// one mistake in it does not produce a page of noise.
    /// </summary>
    [Fact]
    public void OneMissingSemicolonIsOneDiagnostic()
    {
        Front.Parse("module A;\nint F() { int x = 1 return 0; }", out var diagnostics);
        Assert.Single(diagnostics.Items);
    }

    /// <summary>
    /// And the parse really does go on: the declaration after the mistake is
    /// still there to be bound.
    /// </summary>
    [Fact]
    public void RecoveryReachesTheNextDeclaration()
    {
        var unit = Front.Parse(
            "module A;\nint F() { int x = 1 return 0; }\nint G() { return 0; }",
            out var diagnostics);

        Assert.True(diagnostics.HasErrors);
        Assert.Equal(["F", "G"], unit.Declarations.OfType<FunctionDeclSyntax>()
            .Select(f => f.Name));
    }

    [Fact]
    public void AnUnterminatedBlockDoesNotHang()
    {
        Front.Parse("module A;\nint F() { if (true) {", out var diagnostics);
        Assert.True(diagnostics.HasErrors);
    }

    // ------------------------------------------------------ malformed input

    /// <summary>
    /// Parses a file on the stack a compilation gets, and asks that the parse
    /// came back, said something, and pointed every message at text that is
    /// there. An exception fails the test by escaping it.
    /// </summary>
    private static string[] ParseMalformed(string source)
    {
        var diagnostics = Source.Recursion.OnADeepStack(() =>
        {
            Front.Parse(source, out var bag);
            return bag;
        });

        Assert.True(diagnostics.HasErrors);
        foreach (var diagnostic in diagnostics.Items)
        {
            Assert.True(0 <= diagnostic.Span.Start &&
                        diagnostic.Span.Start <= diagnostic.Span.End &&
                        diagnostic.Span.End <= source.Length,
                $"{diagnostic.Code} has span {diagnostic.Span.Start}..{diagnostic.Span.End} " +
                $"in a file of {source.Length}");
        }

        return Front.Codes(diagnostics);
    }

    private static string Repeat(string text, int count) => string.Concat(Enumerable.Repeat(text, count));

    /// <summary>
    /// Input the fuzzer found. Each reached the end of the file with something
    /// still open -- most by passing the depth limit, which jumps there -- and
    /// the recovery that followed consumed "one more" token at the end.
    /// That walked the position past the last token, and the next span taken
    /// from it indexed outside the list.
    /// </summary>
    [Theory]
    [InlineData(" Main(\n{ ", "switch ", 600)]
    [InlineData(" Main(\n{ ", "2 ? canvas ? ", 600)]
    [InlineData(" Main(\n{\n", "    while ;\n", 600)]
    [InlineData(" Total(\n    {\n", "        if (total {\n", 600)]
    [InlineData("class Parent Parent", "(", 600)]
    [InlineData("    [( (", "", 0)]
    public void RecoveryAtTheEndOfTheFileDoesNotThrow(string head, string repeated, int count) =>
        ParseMalformed(head + Repeat(repeated, count));

    /// <summary>
    /// A span over nothing is empty where it would have begun. Taken from the
    /// start token to the last token consumed, it ran backwards instead -- the
    /// last token consumed was the one before the start -- and a caret drawn
    /// from it has a negative width.
    /// </summary>
    [Theory]
    [InlineData("extern __stdcall\n{ 0")]
    [InlineData("<>( where : INamed, class , class")]
    [InlineData(" static explicit operator operator")]
    public void ASpanOverNothingIsEmptyRatherThanBackwards(string source) =>
        ParseMalformed(source);

    /// <summary>
    /// A conversion is named for its target type and nothing else. The name was
    /// taken from the type's first token to the last token consumed, after the
    /// parameters and body had been, so the body's text was part of the symbol.
    /// </summary>
    [Fact]
    public void AConversionIsNamedForItsTargetAlone()
    {
        var unit = Front.Parse("""
            module A;
            public struct Money
            {
                long _cents;
                public static implicit operator Money(long cents) { return Of(cents); }
            }
            """, out var diagnostics);

        Assert.False(diagnostics.HasErrors);
        var conversion = Assert.IsType<TypeDeclSyntax>(unit.Declarations[0])
            .Members.OfType<FunctionDeclSyntax>().Single(f => f.IsConversion);
        Assert.Equal("op_ToMoney", conversion.Name);
    }

    /// <summary>
    /// A lambda's parameter types and a cast's type may both hold a fixed-array
    /// length, which is an expression. So every open parenthesis was parsed
    /// once as each guess and once for real, and the time doubled per level:
    /// the fuzzer's forty levels would not have finished this year.
    /// </summary>
    [Fact]
    public void NestedGuessesAreNotRepeated()
    {
        string source = "module A;\nint Main() { var n = " +
                        Repeat("( [", 40) + "1" + Repeat("] )", 40) + "; return 0; }";

        var parse = Task.Run(() => Front.Parse(source));
        Assert.True(parse.Wait(TimeSpan.FromSeconds(30)), "the parse did not finish");
    }

    /// <summary>
    /// Each <c>?[</c> looks ahead for a <c>:</c>, and each conditional whose
    /// true arm lost one parses that arm again. Neither may cost a doubling per
    /// level, and a nested <c>&lt;</c> guess may not either.
    /// </summary>
    [Theory]
    [InlineData("a?[", "0", "]", 300)]
    [InlineData("c ? a?[", "0", "] : b", 60)]
    [InlineData("c ? ", "x?[0]", " : d", 60)]
    [InlineData("F<", "int", ">(x)", 60)]
    [InlineData("a < (", "b", ")", 60)]
    public void NestedLookaheadIsNotRepeated(string open, string middle, string close, int depth)
    {
        string source = "module A;\nint Main() { var n = " +
                        Repeat(open, depth) + middle + Repeat(close, depth) + "; return 0; }";

        var parse = Task.Run(() => Source.Recursion.OnADeepStack(() => Front.Parse(source)));
        Assert.True(parse.Wait(TimeSpan.FromSeconds(30)), "the parse did not finish");
    }

    /// <summary>
    /// A <c>?</c> after the type an <c>is</c> or <c>as</c> took is a
    /// conditional's only when a true arm and a colon follow, and finding out
    /// parses everything after it. That answer is asked once per position.
    /// </summary>
    [Theory]
    [InlineData("", "Alpha? twice = int as Alpha? ", "", "", 200)]
    [InlineData("var y = ", "x is Node ? (", "1", ") : 0", 200)]
    [InlineData("var y = ", "x as Node ? (", "1", ") : 0", 200)]
    public void AQuestionAfterATypeTestIsDecidedOnce(
        string head, string open, string middle, string close, int depth)
    {
        string source = "module A;\nclass Alpha {}\nclass Node {}\nvoid Main() { object x = null; " +
                        head + Repeat(open, depth) + middle + Repeat(close, depth) + "; }";

        var parse = Task.Run(() => Source.Recursion.OnADeepStack(() => Front.Parse(source)));
        Assert.True(parse.Wait(TimeSpan.FromSeconds(30)), "the parse did not finish");
    }

    /// <summary>
    /// A <c>&gt;&gt;</c> split in two by a guess that was then abandoned is
    /// whole again for the parse that follows. The lambda guess comes first,
    /// and it left the halves behind, so the cast saw one <c>&gt;</c> too few.
    /// </summary>
    [Fact]
    public void AnAbandonedGuessPutsItsSplitShiftBack()
    {
        Assert.Equal("(cast x)", Shape("(List<List<int>>)x"));
        Front.Expression("(List<List<int>>)x", out var diagnostics);
        Assert.False(diagnostics.HasErrors);
    }

    /// <summary>
    /// A type declared inside a type is a level of nesting, and past the limit
    /// it is SL0108 like a block inside a block. It was not counted, so the
    /// fuzzer's three thousand `public interface`s each opened a level nothing
    /// bounded -- and hoisting copies every inner type once per level above it,
    /// which made that half a minute of parsing.
    /// </summary>
    [Fact]
    public void ATypeInsideATypeCountsTowardTheNestingLimit()
    {
        string source = "module A;\n" + Repeat("interface I {\n", 4000) + Repeat("}", 4000);

        var parse = Task.Run(() => Source.Recursion.OnADeepStack(() =>
        {
            Front.Parse(source, out var diagnostics);
            return diagnostics;
        }));

        Assert.True(parse.Wait(TimeSpan.FromSeconds(30)), "the parse did not finish");
        Assert.Contains("SL0108", Front.Codes(parse.Result));
    }

    // ------------------------------------------------------------------ asm

    /// <summary>The first statement of the one function a source declares.</summary>
    private static StatementSyntax FirstStatement(string body, out Source.DiagnosticBag diagnostics)
    {
        var unit = Front.Parse("module Test;\nvoid F()\n{\n" + body + "\n}", out diagnostics);
        return unit.Declarations.OfType<FunctionDeclSyntax>().Single().Body!.Statements[0];
    }

    [Theory]
    [InlineData("int Square(int x) => x * x;", false)]
    [InlineData("int Square(int x) { return x * x; }", false)]
    [InlineData("static int Square(int x) => x * x;", true)]
    [InlineData("T Same<T>(T x) => x;", false)]
    [InlineData("List<int> Make() => new List<int>();", false)]
    [InlineData("(int, int) Pair() => (1, 2);", false)]
    public void AFunctionMayBeDeclaredInABlock(string body, bool isStatic)
    {
        var statement = FirstStatement(body, out var diagnostics);

        Assert.Empty(diagnostics.Items);
        var local = Assert.IsType<LocalFunctionSyntax>(statement);
        Assert.Equal(isStatic, local.Declaration.Modifiers.HasFlag(Modifiers.Static));
    }

    /// <summary>A type, a name and a parenthesis is a local function; nothing else is.</summary>
    [Theory]
    [InlineData("x = F(y);")]
    [InlineData("F(y);")]
    [InlineData("Console.WriteLine(y);")]
    [InlineData("List<int> xs = new List<int>();")]
    [InlineData("F<int>(y);")]
    public void AStatementThatLooksLikeACallIsOne(string body) =>
        Assert.IsNotType<LocalFunctionSyntax>(FirstStatement(body, out _));

    // ----------------------------------------------------- deconstruction

    [Theory]
    [InlineData("(a, b) = (b, a)", "(= (tuple a b) (tuple b a))")]
    [InlineData("(int a, var b) = t", "(= (tuple (declare int a) (declare var b)) t)")]
    [InlineData("(a, (int b, _)) = t", "(= (tuple a (tuple (declare int b) _)) t)")]
    [InlineData("(x, var (y, z)) = t", "(= (tuple x (tuple (declare var y) (declare var z))) t)")]
    [InlineData("(List<int> xs, p.Q) = t", "(= (tuple (declare List<int> xs) (. p Q)) t)")]
    [InlineData("(a[i], b) = t", "(= (tuple ([] a i) b) t)")]
    [InlineData("(a, b) = (c, d) = t", "(= (tuple a b) (= (tuple c d) t))")]
    [InlineData("(x) = 5", "(= x 5)")]
    public void ATupleBeforeAnEqualsIsTakenApart(string source, string shape) =>
        Assert.Equal(shape, Shape(source));

    /// <summary>Only an `=` after the parenthesis makes it a deconstruction.</summary>
    [Theory]
    [InlineData("(int)x", "(cast x)")]
    [InlineData("(a, b) == t", "(== (tuple a b) t)")]
    [InlineData("(a) + b", "(+ a b)")]
    public void AParenthesisWithNoEqualsAfterItIsNotTakenApart(string source, string shape) =>
        Assert.Equal(shape, Shape(source));

    [Theory]
    [InlineData("var (a, b) = t;", "(= (tuple (declare var a) (declare var b)) t)")]
    [InlineData("var (a, (b, _)) = t;",
        "(= (tuple (declare var a) (tuple (declare var b) (declare var _))) t)")]
    [InlineData("(int a, String b) = t;", "(= (tuple (declare int a) (declare String b)) t)")]
    public void ADeconstructionMayStandAsAStatement(string body, string shape)
    {
        var statement = FirstStatement(body, out var diagnostics);

        Assert.Empty(diagnostics.Items);
        var expression = Assert.IsType<ExpressionStatementSyntax>(statement);
        Assert.Equal(shape, Render(expression.Expression));
    }

    [Theory]
    [InlineData("foreach (var (k, v) in pairs) { }", "(tuple (declare var k) (declare var v))")]
    [InlineData("foreach ((int k, var v) in pairs) { }", "(tuple (declare int k) (declare var v))")]
    [InlineData("foreach ((int, String) pair in pairs) { }", null)]
    public void AForeachMayTakeItsElementApart(string body, string? shape)
    {
        var statement = FirstStatement(body, out var diagnostics);

        Assert.Empty(diagnostics.Items);
        var loop = Assert.IsType<ForEachSyntax>(statement);
        Assert.Equal(shape, loop.Deconstruction is null ? null : Render(loop.Deconstruction));
    }

    [Fact]
    public void AStaticLocalVariableIsRefused()
    {
        FirstStatement("static int count = 0;", out var diagnostics);
        Assert.Contains("SL0770", Front.Codes(diagnostics));
    }

    [Fact]
    public void AsmOperandsKeepTheirDirectionRegisterAndValue()
    {
        var statement = FirstStatement(
            "asm (in rcx = count + 1, out rax = low, inout RDX = totals[i]) { rdtsc }",
            out var diagnostics);

        Assert.Empty(diagnostics.Items);
        var asm = Assert.IsType<AsmSyntax>(statement);

        Assert.Equal([AsmDirection.In, AsmDirection.Out, AsmDirection.InOut],
                     asm.Operands.Select(o => o.Direction));
        Assert.Equal(["rcx", "rax", "RDX"], asm.Operands.Select(o => o.Register));
        Assert.Equal(["(+ count 1)", "low", "([] totals i)"],
                     asm.Operands.Select(o => Render(o.Value)));
        Assert.Equal(" rdtsc ", asm.Text);
    }

    [Theory]
    [InlineData("asm { nop }", 0)]
    [InlineData("asm () { nop }", 0)]
    [InlineData("asm (out rax = r) { nop }", 1)]
    public void AsmOperandsAreOptional(string body, int count)
    {
        var statement = FirstStatement(body, out var diagnostics);

        Assert.Empty(diagnostics.Items);
        Assert.Equal(count, Assert.IsType<AsmSyntax>(statement).Operands.Count);
    }

    /// <summary>
    /// An operand's value is a conditional, not an assignment: the <c>=</c>
    /// after the register is the operand's own, and a second one is not read
    /// as part of the value.
    /// </summary>
    [Fact]
    public void AnAsmOperandValueIsNotAnAssignment()
    {
        FirstStatement("asm (in rax = a = b) { nop }", out var diagnostics);
        Assert.Contains("SL0100", Front.Codes(diagnostics));
    }

    /// <summary>
    /// <c>out</c> and <c>inout</c> are words, as <c>out</c> is at a call, and
    /// stay names everywhere else.
    /// </summary>
    [Fact]
    public void OutAndInoutRemainNames()
    {
        Front.Parse("module Test;\nvoid F()\n{\n    int out = 1;\n    int inout = out;\n}",
                    out var diagnostics);
        Assert.Empty(diagnostics.Items);
    }

    [Fact]
    public void AnAsmOperandWithNoDirectionIsReportedAndStillRead()
    {
        var statement = FirstStatement("asm (rax = total) { nop }", out var diagnostics);

        Assert.Equal(["SL0715"], Front.Codes(diagnostics));
        var operand = Assert.Single(Assert.IsType<AsmSyntax>(statement).Operands);
        Assert.Equal("rax", operand.Register);
    }

    [Theory]
    [InlineData("asm (out rax = r);")]
    [InlineData("asm (out rax = r) nop;")]
    public void AsmWithNoBodyIsReported(string body)
    {
        FirstStatement(body, out var diagnostics);
        Assert.Contains("SL0714", Front.Codes(diagnostics));
    }

    /// <summary>
    /// A body that never closed took the rest of the file, and the one message
    /// about it is the lexer's: the function and anything else it left open
    /// say nothing more.
    /// </summary>
    [Fact]
    public void AnUnterminatedAsmBodyIsTheOnlyComplaint()
    {
        Front.Parse("module Test;\nclass C\n{\n    void F()\n    {\n        asm { {k1 {k2 {k3 }\n    }\n}",
                    out var diagnostics);

        Assert.Equal(["SL0713"], Front.Codes(diagnostics));
    }

    // ------------------------------------------------------------ constraints

    private static ConstraintSyntax OnlyConstraint(string clause)
    {
        var function = Assert.IsType<FunctionDeclSyntax>(
            Front.Declaration("T F<T>(T v) " + clause + " => v;"));
        return Assert.Single(Assert.Single(function.Constraints).Constraints);
    }

    [Theory]
    [InlineData("where T : unmanaged", ConstraintKind.Unmanaged)]
    [InlineData("where T : notnull", ConstraintKind.NotNull)]
    [InlineData("where T : default", ConstraintKind.Default)]
    public void TheConstraintWordsAreRead(string clause, ConstraintKind kind) =>
        Assert.Equal(kind, OnlyConstraint(clause).Kind);

    /// <summary>
    /// Contextual, as in C#: a type of that name, qualified or given arguments,
    /// is still a type.
    /// </summary>
    [Theory]
    [InlineData("where T : unmanaged<int>")]
    [InlineData("where T : notnull.Thing")]
    public void AConstraintWordWithMoreAfterItIsAType(string clause) =>
        Assert.Equal(ConstraintKind.Type, OnlyConstraint(clause).Kind);

    // ----------------------------------------------- members named for an interface

    private static Declaration OnlyMember(string member) =>
        Assert.IsType<TypeDeclSyntax>(Front.Declaration("class C\n{\n    " + member + "\n}"))
            .Members.Single();

    [Theory]
    [InlineData("void IShape.Draw() { }", "IShape", "Draw")]
    [InlineData("String App.INamed.Name() => \"x\";", "App.INamed", "Name")]
    [InlineData("int IList<T>.Count() => 0;", "IList", "Count")]
    public void AMethodNamedForAnInterfaceIsRead(string member, string contract, string name)
    {
        var function = Assert.IsType<FunctionDeclSyntax>(OnlyMember(member));
        var written = Assert.IsType<NamedTypeSyntax>(function.ExplicitInterface);

        Assert.Equal(contract, written.Name.Text);
        Assert.Equal(name, function.Name);
    }

    [Fact]
    public void APropertyNamedForAnInterfaceIsRead()
    {
        var property = Assert.IsType<PropertyDeclSyntax>(OnlyMember("int ISized.Size => 1;"));
        Assert.Equal("ISized", Assert.IsType<NamedTypeSyntax>(property.ExplicitInterface).Name.Text);
        Assert.Equal("Size", property.Name);
    }

    [Fact]
    public void AGenericMethodIsNotNamedForAnInterface()
    {
        var function = Assert.IsType<FunctionDeclSyntax>(OnlyMember("T Max<T>(T a, T b) => a;"));
        Assert.Null(function.ExplicitInterface);
        Assert.Equal(["T"], function.TypeParameters);
    }

    [Fact]
    public void AFieldCannotBeNamedForAnInterface()
    {
        Front.Parse("module Test;\nclass C\n{\n    int IShape.Corners;\n}", out var diagnostics);
        Assert.Equal(["SL0793"], Front.Codes(diagnostics));
    }

    // ------------------------------------------------------------- variance

    [Fact]
    public void AnInterfaceReadsItsVariance()
    {
        var declared = Assert.IsType<TypeDeclSyntax>(
            Front.Declaration("interface IMap<in TKey, out TValue, TOther> { }"));

        Assert.Equal(["TKey", "TValue", "TOther"], declared.TypeParameters);
        Assert.Equal([Variance.In, Variance.Out, Variance.None], declared.TypeParameterVariance);
    }

    [Fact]
    public void AClosureReadsItsVariance()
    {
        var declared = Assert.IsType<DelegateDeclSyntax>(
            Front.Declaration("closure TResult Func<in T, out TResult>(T value);"));

        Assert.Equal([Variance.In, Variance.Out], declared.TypeParameterVariance);
    }

    /// <summary>`out` is a word, and a parameter may still be called it.</summary>
    [Fact]
    public void OutAloneIsAParameterName()
    {
        var declared = Assert.IsType<TypeDeclSyntax>(Front.Declaration("interface IHold<out> { }"));

        Assert.Equal(["out"], declared.TypeParameters);
        Assert.Equal([Variance.None], declared.TypeParameterVariance);
    }

    [Theory]
    [InlineData("class Box<out T> { }")]
    [InlineData("struct Pair<in T> { }")]
    [InlineData("T Pick<out T>(T value) => value;")]
    public void OnlyAnInterfaceOrADelegateHasVariance(string declaration)
    {
        Front.Parse("module Test;\n" + declaration, out var diagnostics);
        Assert.Equal(["SL0800"], Front.Codes(diagnostics));
    }

    [Fact]
    public void UnmanagedAndNotnullRemainNames()
    {
        Front.Parse("module Test;\nvoid F()\n{\n    int unmanaged = 1;\n    int notnull = unmanaged;\n}",
                    out var diagnostics);
        Assert.Empty(diagnostics.Items);
    }
}
