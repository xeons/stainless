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
    /// A block-bodied lambda has no expression to read a type off, and binding
    /// one needs the return type that is being worked out. It reaches SL0327
    /// rather than a wrong answer.
    /// </summary>
    [Fact]
    public void ABlockBodyIsNotProbed() =>
        Assert.Contains("SL0327", Body("var result = Transform(numbers, n => { return n * 2; });"));

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
}
