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
/// The things a <c>where</c> clause can demand, and how each is refused.
///
/// A constraint is verified against its argument where the generic is
/// instantiated, so most of these need a call to reach the check. Whether the
/// clauses make sense on their own is checked where they are written, used or
/// not; the last section is those.
/// </summary>
public class ConstraintTests
{
    private const string Types = """
        public interface INamed { String Name(); }

        public class Animal : INamed {
            public Animal() { }
            public virtual String Name() { return "animal"; }
        }

        public class Dog : Animal {
            public Dog() { }
            public override String Name() { return "dog"; }
        }

        public class NeedsAnArgument {
            public NeedsAnArgument(int x) { }
        }

        public class Hidden {
            Hidden() { }
        }

        public struct Point { public int X; }

        """;

    private static string[] With(string declaration, string body) =>
        Front.ModuleCodes(Types + declaration + "\nint Main() {\n" + body + "\n    return 0;\n}");

    // -------------------------------------------------------------- class

    [Theory]
    [InlineData("var d = Ref(new Dog());")]
    [InlineData("String s = \"x\"; var t = Ref(s);")]
    public void ClassAcceptsAReferenceType(string body) =>
        Assert.Empty(With("T Ref<T>(T v) where T : class { return v; }", body));

    [Theory]
    [InlineData("Point p; var q = Ref(p);")]
    [InlineData("var n = Ref(1);")]
    public void ClassRefusesAValueType(string body) =>
        Assert.Contains("SL0328", With("T Ref<T>(T v) where T : class { return v; }", body));

    // ------------------------------------------------------------- struct

    [Theory]
    [InlineData("Point p; var q = Val(p);")]
    [InlineData("var n = Val(1);")]
    public void StructAcceptsAValueType(string body) =>
        Assert.Empty(With("T Val<T>(T v) where T : struct { return v; }", body));

    [Fact]
    public void StructRefusesAClass() =>
        Assert.Contains("SL0328",
            With("T Val<T>(T v) where T : struct { return v; }", "var d = Val(new Dog());"));

    // -------------------------------------------------------------- new()

    [Fact]
    public void NewAcceptsAParameterlessConstructor() =>
        Assert.Empty(With("T Fresh<T>(T v) where T : new() { return new T(); }",
            "var d = Fresh(new Dog());"));

    /// <summary>
    /// And only a class. C# admits a struct because there `new T()` on a value
    /// type is default-initialization; here `new` allocates, so a struct would
    /// satisfy a constraint whose only purpose it then failed.
    /// </summary>
    [Fact]
    public void NewRefusesAValueType() =>
        Assert.Contains("SL0328", With("T Fresh<T>(T v) where T : new() { return new T(); }",
            "Point p; var q = Fresh(p);"));

    [Theory]
    [InlineData("var n = Fresh(new NeedsAnArgument(1));")]
    [InlineData("var h = Fresh(Made());")]
    [InlineData("var a = Fresh(Abstract());")]
    public void NewRefusesWhatItCannotMake(string body) =>
        Assert.Contains("SL0328",
            With("T Fresh<T>(T v) where T : new() { return new T(); }\n" +
                 "Hidden Made() { return null; }\n" +
                 "public abstract class Shape { }\n" +
                 "Shape Abstract() { return null; }", body));

    /// <summary>
    /// A class that declares no constructor is given one taking no arguments
    /// (spec §2.4.1), so <c>new()</c> must accept what <c>new</c> accepts. It
    /// used to look only at the constructors the class had, and one with no
    /// field initializers -- nothing to synthesize a constructor for -- had
    /// none, and was refused.
    /// </summary>
    [Theory]
    [InlineData("var b = Fresh(new Bare());")]
    [InlineData("var h = new Holder<Bare>();")]
    [InlineData("var h = new Holder<Initialized>();")]
    [InlineData("var h = new Holder<DerivedBare>();")]
    public void NewAcceptsAClassThatDeclaresNoConstructor(string body) =>
        Assert.Empty(
            With("T Fresh<T>(T v) where T : new() { return new T(); }\n" +
                 "public class Bare { }\n" +
                 "public class Initialized { public int Size = 3; }\n" +
                 "public class DerivedBare : Animal { }\n" +
                 "public class Holder<T> where T : new() { }", body));

    // --------------------------------------------------------- a base class

    [Theory]
    [InlineData("var s = Named(new Dog());")]
    [InlineData("var s = Named(new Animal());")]
    public void ABaseClassAcceptsItselfAndItsDerived(string body) =>
        Assert.Empty(With("String Named<T>(T v) where T : Animal { return v.Name(); }", body));

    [Fact]
    public void ABaseClassRefusesSomethingElse() =>
        Assert.Contains("SL0328",
            With("String Named<T>(T v) where T : Animal { return \"\"; }", "Point p; var s = Named(p);"));

    /// <summary>
    /// A struct has neither implementers nor derived types, so a parameter
    /// constrained to one could only ever be that struct.
    /// </summary>
    [Fact]
    public void AValueTypeCannotConstrain() =>
        Assert.Contains("SL0329",
            With("T By<T>(T v) where T : Point { return v; }", "Point p; var q = By(p);"));

    // ------------------------------------------------------ one by another

    [Fact]
    public void AParameterMayConstrainAnother() =>
        Assert.Empty(With(
            "String Two<T, U>(T a, U b) where T : U where U : INamed { return b.Name(); }",
            "var s = Two(new Dog(), new Animal());"));

    [Fact]
    public void AndIsCheckedBothWays() =>
        Assert.Contains("SL0328", With(
            "String Two<T, U>(T a, U b) where T : U where U : INamed { return b.Name(); }",
            "Point p; var s = Two(p, new Animal());"));

    // --------------------------------------------------------- threadsafe

    [Fact]
    public void ThreadsafeAcceptsWhatClaimsIt() => Assert.Empty(Front.ModuleCodes("""
        public threadsafe class Guarded { public Guarded() { } }
        long Held<T>(T v) where T : threadsafe { return 1; }
        int Main() { return (int)Held(new Guarded()); }
        """));

    /// <summary>
    /// The one place the same fact is an error rather than a warning: here a
    /// library author asked for it in their own signature.
    /// </summary>
    [Fact]
    public void ThreadsafeRefusesWhatDoesNot() => Assert.Contains("SL0328", Front.ModuleCodes("""
        public class Plain { public Plain() { } }
        long Held<T>(T v) where T : threadsafe { return 1; }
        int Main() { return (int)Held(new Plain()); }
        """));

    // ------------------------------------------------------------- writing

    [Theory]
    [InlineData("where T : INamed, class")]
    [InlineData("where T : INamed, struct")]
    [InlineData("where T : new(), INamed")]
    public void TheKindComesFirstAndNewComesLast(string clause) =>
        Assert.Contains("SL0580", Front.ModuleCodes(
            Types + "T F<T>(T v) " + clause + " { return v; }\nint Main() { return 0; }"));

    [Theory]
    [InlineData("where T : class, struct")]
    [InlineData("where T : struct, new()")]
    public void ContradictoryKindsAreRefused(string clause) =>
        Assert.Contains("SL0581", Front.ModuleCodes(
            "T F<T>(T v) " + clause + " { return v; }\nint Main() { return 0; }"));

    [Theory]
    [InlineData("where T : INamed, unmanaged")]
    [InlineData("where T : INamed, notnull")]
    public void TheNewKindsComeFirstToo(string clause) =>
        Assert.Contains("SL0580", Front.ModuleCodes(
            Types + "T F<T>(T v) " + clause + " { return v; }\nint Main() { return 0; }"));

    [Theory]
    [InlineData("where T : unmanaged, new()")]
    [InlineData("where T : class, notnull")]
    [InlineData("where T : unmanaged, struct")]
    [InlineData("where T : struct, Animal")]
    public void TheNewKindsContradictToo(string clause) =>
        Assert.Contains("SL0581", Front.ModuleCodes(
            Types + "T F<T>(T v) " + clause + " { return v; }\nint Main() { return 0; }"));

    /// <summary>
    /// Only the parameterless form. A body wanting arguments would have to know
    /// their types, which is a promise a single type parameter cannot make.
    /// </summary>
    [Fact]
    public void NewTakesNoParameters() =>
        Assert.Contains("SL0579", Front.ModuleCodes(
            "T F<T>(T v) where T : new(int) { return v; }\nint Main() { return 0; }"));

    // ---------------------------------------------------------- unmanaged

    [Theory]
    [InlineData("var n = Size(1);")]
    [InlineData("Point p; var n = Size(p);")]
    [InlineData("int x = 1; var n = Size(&x);")]
    [InlineData("var n = Size((1, 2.0));")]
    public void UnmanagedAcceptsPlainBytes(string body) =>
        Assert.Empty(With("nuint Size<T>(T v) where T : unmanaged { return 0; }", body));

    [Theory]
    [InlineData("var n = Size(\"text\");")]
    [InlineData("var n = Size(new Dog());")]
    [InlineData("Holder h; var n = Size(h);")]
    [InlineData("var n = Size((1, \"text\"));")]
    public void UnmanagedRefusesAnythingCounted(string body) =>
        Assert.Contains("SL0328", With(
            "nuint Size<T>(T v) where T : unmanaged { return 0; }\n" +
            "public struct Holder { public String Text; }", body));

    // ------------------------------------------------------------ notnull

    [Theory]
    [InlineData("var n = Keep(1);")]
    [InlineData("var d = Keep(new Dog());")]
    public void NotNullAcceptsWhatCannotBeNull(string body) =>
        Assert.Empty(With("T Keep<T>(T v) where T : notnull { return v; }", body));

    [Fact]
    public void NotNullRefusesAnOptional() =>
        Assert.Contains("SL0328", With("T Keep<T>(T v) where T : notnull { return v; }",
            "Dog? d = null; var k = Keep(d);"));

    // ------------------------------------------------ where they are written

    [Fact]
    public void AnUnknownParameterIsReportedUnused() =>
        Assert.Equal(["SL0330"], Front.ModuleCodes("T F<T>(T v) where U : class { return v; }"));

    [Fact]
    public void AnUnknownParameterIsReportedOnce() =>
        Assert.Equal(["SL0330"], Front.ModuleCodes(
            "T F<T>(T v) where U : class { return v; }\nint Main() { F(1); return 0; }"));

    [Fact]
    public void AParameterHasOneClause() =>
        Assert.Equal(["SL0788"], Front.ModuleCodes(Types +
            "T F<T>(T v) where T : class where T : INamed { return v; }"));

    [Fact]
    public void AConstraintIsWrittenOnce() =>
        Assert.Equal(["SL0789"], Front.ModuleCodes(Types +
            "T F<T>(T v) where T : INamed, INamed { return v; }"));

    [Fact]
    public void AParameterHasOneBaseClass() =>
        Assert.Equal(["SL0790"], Front.ModuleCodes(Types +
            "T F<T>(T v) where T : Animal, Dog { return v; }"));

    [Theory]
    [InlineData("where T : U where U : T")]
    [InlineData("where T : U where U : V where V : T")]
    public void ParametersMayNotConstrainEachOtherInACircle(string clauses) =>
        Assert.Equal(["SL0791"], Front.ModuleCodes(
            "T F<T, U, V>(T a, U b, V c) " + clauses + " { return a; }"));

    [Fact]
    public void ASealedClassCannotConstrain() =>
        Assert.Equal(["SL0329"], Front.ModuleCodes(
            "public sealed class Leaf { }\nT F<T>(T v) where T : Leaf { return v; }"));

    [Fact]
    public void AStructCannotConstrainEvenUnused() =>
        Assert.Equal(["SL0329"], Front.ModuleCodes(Types +
            "T F<T>(T v) where T : Point { return v; }"));

    [Fact]
    public void AGenericStructCannotConstrain() =>
        Assert.Equal(["SL0329"], Front.ModuleCodes(
            "public struct Cell<T> { public T Value; }\n" +
            "T F<T>(T v) where T : Cell<T> { return v; }"));

    [Fact]
    public void AMethodOfAGenericTypeIsCheckedToo() =>
        Assert.Equal(["SL0788"], Front.ModuleCodes(Types +
            "public class Box<T> { public U Get<U>(U v) where U : class where U : INamed " +
            "{ return v; } }"));

    [Fact]
    public void DefaultIsOnlyForAnOverride() =>
        Assert.Equal(["SL0792"], Front.ModuleCodes("T F<T>(T v) where T : default { return v; }"));
}
