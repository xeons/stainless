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
        NameSyntax name => name.Name.Text,
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
        MemberAccessSyntax member => $"(. {Render(member.Target)} {member.Member})",
        IndexSyntax index => $"([] {Render(index.Target)} {Render(index.Index)})",
        SliceSyntax slice =>
            $"([:] {Render(slice.Target)} {Render(slice.Start)} {Render(slice.End)})",
        CallSyntax call =>
            $"(call {Render(call.Callee)}{string.Concat(call.Arguments.Select(a => " " + Render(a)))})",
        CastSyntax cast => $"(cast {Render(cast.Operand)})",
        TypeTestSyntax test => $"(is {Render(test.Value)})",
        NewSyntax => "new",
        ArrayLiteralSyntax array =>
            $"[{string.Join(" ", array.Elements.Select(Render))}]",
        null => "_",
        _ => expression.GetType().Name,
    };

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

    // -------------------------------------------------------- array literals

    [Theory]
    [InlineData("[]", "[]")]
    [InlineData("[1]", "[1]")]
    [InlineData("[1, 2, 3]", "[1 2 3]")]
    [InlineData("[1 + 2, 3]", "[(+ 1 2) 3]")]
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

    [Fact]
    public void ATypeCollectsItsMembers()
    {
        var unit = Front.Parse("module A;\nclass C { int x; int F() { return 0; } }");
        var type = Assert.IsType<TypeDeclSyntax>(unit.Declarations[0]);

        Assert.Equal("C", type.Name);
        Assert.Single(type.Members.OfType<FieldDeclSyntax>());
        Assert.Single(type.Members.OfType<FunctionDeclSyntax>());
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
}
