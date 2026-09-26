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

using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// Working out a type parameter that appears only in a lambda's result.
///
/// The end-to-end case in <c>tests/cases/sequences</c> proves the answers are
/// right. These are about the reasoning that produces them, and about the
/// cases where it must give up rather than guess -- neither of which an
/// <c>expected.txt</c> can show, because a program that does not compile has
/// no output to compare.
/// </summary>
public class InferenceTests
{
    /// <summary>
    /// The shapes under test, ahead of each body: a transform whose result type
    /// is nowhere else, a predicate whose target is settled by the input alone,
    /// and a fold that gets its accumulator from a seed.
    /// </summary>
    private const string Shapes = """
        public interface IFunc<T, R> { R Apply(T value); }
        public interface IPredicate<T> { bool Test(T value); }
        public interface IFold<A, T> { A Apply(A total, T value); }

        public R Transform<T, R>(T[:] items, IFunc<T, R> f) { return f.Apply(items[0u]); }
        public bool Keep<T>(T[:] items, IPredicate<T> p) { return p.Test(items[0u]); }
        public A Fold<T, A>(T[:] items, A seed, IFold<A, T> f) { return f.Apply(seed, items[0u]); }

        """;

    /// <summary>
    /// A body, with its inputs named first.
    ///
    /// An array literal has no type of its own and takes one from where it is
    /// going -- and a generic parameter is not a place that settles one. That
    /// is a separate rule from the one under test here, so these name the array
    /// rather than writing it at the call.
    /// </summary>
    private static string[] Body(string body) =>
        Front.ModuleCodes(
            Shapes + "int Main()\n{\n" +
            "    var numbers = [1, 2];\n" +
            "    var words = [\"a\", \"b\"];\n" +
            body + "\n    return 0;\n}");

    // ------------------------------------------------- the result is inferred

    /// <summary>
    /// The chain this exists for: <c>T</c> comes from the array, which gives
    /// the lambda its parameter type, which lets its body be bound, which is
    /// what says what <c>R</c> is. Each result type is checked by using it.
    /// </summary>
    [Theory]
    [InlineData("int result = Transform(numbers, n => n * 2);")]
    [InlineData("String result = Transform(numbers, n => Text.FromInteger((long)n));")]
    [InlineData("double result = Transform(numbers, n => (double)n / 2.0);")]
    [InlineData("bool result = Transform(numbers, n => n > 1);")]
    [InlineData("long result = Transform(words, s => (long)s.ByteLength());")]
    public void AResultTypeIsReadOffTheBody(string body) => Assert.Empty(Body(body));

    /// <summary>
    /// And it is the *right* type, not merely some type: assigning the result
    /// to the wrong one has to be refused.
    /// </summary>
    [Fact]
    public void TheResultTypeIsNotGuessed() =>
        Assert.Contains("SL0265", Body("String wrong = Transform(numbers, n => n * 2);"));

    /// <summary>A lambda body that reaches outside itself still binds.</summary>
    [Fact]
    public void ABodyMayCaptureWhileItIsBeingProbed() =>
        Assert.Empty(Body("""
            int factor = 3;
            int result = Transform(numbers, n => n * factor);
            """));

    // ---------------------------------------------- the ones already working

    /// <summary>
    /// Nothing above should have disturbed the case that needed no help: a
    /// lambda whose target is settled by the other arguments alone.
    /// </summary>
    [Theory]
    [InlineData("bool kept = Keep(numbers, n => n > 1);")]
    [InlineData("long total = Fold(numbers, (long)0, (sum, n) => sum + (long)n);")]
    [InlineData("String run = Fold(numbers, \"\", (text, n) => text + Text.FromInteger((long)n));")]
    public void ASettledTargetStillWorks(string body) => Assert.Empty(Body(body));

    // ------------------------------------------------------- and giving up

    /// <summary>
    /// A body that cannot bind is not an inference: the call is refused, and
    /// the muting that a trial runs under must not swallow the report.
    /// </summary>
    [Fact]
    public void ABodyThatCannotBindIsStillReported() =>
        Assert.NotEmpty(Body("int result = Transform(numbers, n => n.NoSuchMethod());"));

    /// <summary>
    /// And what is reported is the body's own error, not SL0327: every
    /// parameter was known, so the body is the reason, and a failed inference
    /// would send the reader to the call instead.
    /// </summary>
    [Theory]
    [InlineData("int result = Transform(numbers, n => n.NoSuchMethod());", "SL0255")]
    [InlineData("int result = Transform(words, (String w) => w.NoSuchField);", "SL0247")]
    [InlineData("int result = Transform(numbers, n => NoSuchFunction(n));", "SL0252")]
    public void ABodyThatCannotBindReportsItsOwnError(string body, string code)
    {
        var codes = Body(body);
        Assert.Contains(code, codes);
        Assert.DoesNotContain("SL0327", codes);
    }

    /// <summary>
    /// The same for a lambda given to <c>var</c>: its parameters are written,
    /// so its body is why it has no type, and SL0553 would hide what is wrong.
    /// A call through the refused local says nothing more.
    /// </summary>
    [Fact]
    public void AVarLambdaReportsItsBodysError()
    {
        var codes = Body("var f = (int n) => n.NoSuchField;\n    int k = f(2);");
        Assert.Contains("SL0247", codes);
        Assert.DoesNotContain("SL0553", codes);
        Assert.DoesNotContain("SL0252", codes);
    }

    /// <summary>
    /// A block-bodied lambda's result is the one type its <c>return</c>s agree
    /// on, so it is read off them.
    /// </summary>
    [Theory]
    [InlineData("int result = Transform(numbers, n => { return n * 2; });")]
    [InlineData("long result = Transform(numbers, n => { if (n > 1) { return 1; } return 2L; });")]
    [InlineData("String result = Transform(numbers, n => { return \"x\"; });")]
    public void ABlockBodyIsReadOffItsReturns(string body) => Assert.Empty(Body(body));

    /// <summary>Returns that agree on nothing say nothing, and the call is SL0327.</summary>
    [Fact]
    public void ReturnsThatDisagreeAreNotAnAnswer() =>
        Assert.Contains("SL0327",
            Body("var result = Transform(numbers, n => { if (n > 1) { return 1; } return \"x\"; });"));

    /// <summary>
    /// A lambda with nothing at all to become is an error.
    ///
    /// It used to be worse than that: the declaration bound cleanly, and the
    /// emitter wrote <c>store ptr 0</c>, which clang rejected as a compiler
    /// bug. Writing this test is what turned it up.
    /// </summary>
    [Fact]
    public void ALambdaWithNoTargetIsRefused() =>
        Assert.Contains("SL0553", Body("var f = x => x;"));

    // ------------------------------------------- a function passed by name

    /// <summary>
    /// Closures rather than interfaces, because a function converts to a
    /// closure; and two <c>Twice</c>s, so which one is meant has to be chosen
    /// by the type already inferred rather than by being the only one.
    /// </summary>
    private const string Named = """
        public closure R Func<T, R>(T value);

        public R Apply<T, R>(T[:] items, Func<T, R> f) { return f(items[0u]); }
        public R Call<T, R>(Func<T, R> f, T value) { return f(value); }
        public nuint Shapes<T, R>(Func<T, R> f) { return 0u; }

        String Spell(int n) => "n";
        long Twice(int n) => (long)n * 2;
        double Twice(double n) => n * 2.0;
        int Pick(int n) => n;
        String Pick(String s) => s;

        int Main()
        {
            var numbers = [1, 2];

        """;

    private static string[] NamedBody(string body) =>
        Front.ModuleCodes(Named + body + "\n    return 0;\n}");

    /// <summary>
    /// The result is read off the declaration, as it would be off a lambda's
    /// body. This was SL0327 -- only a lambda was read -- and before that the
    /// function could not become a closure at all.
    /// </summary>
    [Theory]
    [InlineData("String result = Apply(numbers, Spell);")]
    [InlineData("String result = numbers.Apply(Spell);")]
    [InlineData("long result = Apply(numbers, Twice);")]
    [InlineData("String result = Call(Spell, 3);")]
    public void AResultTypeIsReadOffANamedFunction(string body) => Assert.Empty(NamedBody(body));

    /// <summary>
    /// And it is the right type: the overload the argument chose, whose
    /// <c>long</c> will not quietly become a <c>double</c> or a <c>String</c>.
    /// </summary>
    [Theory]
    [InlineData("int wrong = Apply(numbers, Twice);")]
    [InlineData("String wrong = Apply(numbers, Twice);")]
    public void TheOverloadIsChosenByTheInferredParameter(string body)
    {
        var codes = NamedBody(body);
        Assert.NotEmpty(codes);
        Assert.DoesNotContain("SL0327", codes);
    }

    /// <summary>
    /// A name with one function of the arity settles the parameter types as
    /// well; an overloaded one, with nothing else to choose by, is not guessed.
    /// </summary>
    [Fact]
    public void AnUnoverloadedNameSettlesItsParameters() =>
        Assert.Empty(NamedBody("nuint result = Shapes(Spell);"));

    [Fact]
    public void AnOverloadNothingNarrowsIsNotGuessed() =>
        Assert.Equal(["SL0327"], NamedBody("nuint result = Shapes(Pick);"));

    // ------------------------------------------------------ nothing leaks

    /// <summary>
    /// A trial binds a body and then throws the result away. If it kept what it
    /// built, the closure class would be emitted twice -- once for the trial and
    /// once for the real thing -- so the count of them is what proves it did not.
    /// </summary>
    [Fact]
    public void ATrialLeavesNoClosureBehind()
    {
        string ir = Front.ModuleIr(Shapes + """
            public int Once() {
                var numbers = [1, 2];
                return Transform(numbers, n => n * 2);
            }
            """);

        // One closure class for the one lambda in the source: its Apply, and
        // nothing left over from working out what R was.
        int applies = ir.Split('\n')
            .Count(l => l.StartsWith("define", StringComparison.Ordinal) &&
                        l.Contains("Closure", StringComparison.Ordinal) &&
                        l.Contains("Apply", StringComparison.Ordinal));

        Assert.Equal(1, applies);
    }

    /// <summary>A closure held in a variable says what its arguments are.</summary>
    [Fact]
    public void AClosureInAVariableIsReadOffItsType() =>
        Assert.Empty(Front.ModuleCodes(
            """
            import Standard.Collections;

            String First(List<int> numbers)
            {
                Func<int, String> show = n => Text.FromInteger(n);
                var shown = Select(numbers, show);
                return shown[0];
            }
            """));
}
