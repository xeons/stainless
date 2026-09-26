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
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// What an interface may declare and what an override may narrow.
///
/// The end-to-end cases prove the dispatch comes out right. These are the rules
/// around it, most of which are refusals.
/// </summary>
public class InterfaceTests
{
    // ------------------------------------------------------------ overloads

    [Fact]
    public void EachOverloadOfAnInterfaceMethodTakesItsOwnSlot()
    {
        var program = Front.BindModule(
            """
            public interface IWriter
            {
                void Write(int value);
                void Write(String value);
            }
            """, out var diagnostics);

        Assert.Empty(Front.Codes(diagnostics));

        var writer = program.Interfaces.Single(i => i.Name == "IWriter");
        var overloads = writer.Methods.Where(m => m.Name == "Write").ToList();

        Assert.Equal(2, overloads.Count);
        Assert.NotEqual(writer.SlotOf(overloads[0]), writer.SlotOf(overloads[1]));
    }

    [Fact]
    public void AnInterfaceOverloadStillNeedsDifferentParameters() =>
        Assert.Equal(["SL0211"], Front.ModuleCodes(
            """
            public interface IWriter
            {
                void Write(int value);
                int Write(int other);
            }
            """));

    [Fact]
    public void AClassMustImplementEveryOverload() =>
        Assert.Equal(["SL0305"], Front.ModuleCodes(
            """
            public interface IWriter
            {
                void Write(int value);
                void Write(String value);
                void Write(long value);
            }

            public class Half : IWriter
            {
                public void Write(int value) { }
                public void Write(String value) { }
            }
            """));

    // ------------------------------------------------------------- defaults

    [Fact]
    public void AMemberWithADefaultNeedNotBeImplemented() =>
        Assert.Empty(Front.ModuleCodes(
            """
            public interface IGreeter { String Greet() => "hello"; }
            public class Quiet : IGreeter { }
            """));

    [Fact]
    public void ADefaultIsNotAMemberOfTheClass() =>
        Assert.Equal(["SL0255"], Front.ModuleCodes(
            """
            public interface IGreeter { String Greet() => "hello"; }
            public class Quiet : IGreeter { }
            String Ask(Quiet quiet) => quiet.Greet();
            """));

    [Fact]
    public void ADefaultSeesItsObjectAsTheInterface()
    {
        var program = Front.BindModule(
            """
            public interface IGreeter { String Name(); String Greet() => Name(); }
            """, out var diagnostics);

        Assert.Empty(Front.Codes(diagnostics));
        var greet = program.Interfaces.Single(i => i.Name == "IGreeter").FindMethod("Greet")!;
        Assert.IsType<InterfaceTypeSymbol>(greet.Parameters.Single(p => p.IsThis).Type);
    }

    [Fact]
    public void AClassMemberWinsOverTheDefault()
    {
        var program = Front.BindModule(
            """
            public interface IGreeter { String Greet() => "hello"; }
            public class Loud : IGreeter { public String Greet() => "HELLO"; }
            """, out _);

        var greeter = program.Interfaces.Single(i => i.Name == "IGreeter");
        var loud = program.Classes.Single(c => c.Name == "Loud");
        Assert.Same(loud.Methods.Single(), loud.ImplementationOf(greeter.Methods.Single()));
    }

    [Fact]
    public void TheMostSpecificDefaultIsChosen()
    {
        var program = Front.BindModule(
            """
            public interface IA { String Which() => "A"; }
            public interface IB : IA { String IA.Which() => "B"; }
            public class OnlyB : IB { }
            """, out var diagnostics);

        Assert.Empty(Front.Codes(diagnostics));
        var which = program.Interfaces.Single(i => i.Name == "IA").Methods.Single();
        var chosen = program.Classes.Single(c => c.Name == "OnlyB").ImplementationOf(which)!;
        Assert.Equal("IB", chosen.ContainingType!.Name);
    }

    [Fact]
    public void TwoDefaultsNeitherMoreSpecificAreAmbiguous() =>
        Assert.Equal(["SL0796"], Front.ModuleCodes(
            """
            public interface IA { String Which() => "A"; }
            public interface IB : IA { String IA.Which() => "B"; }
            public interface IC : IA { String IA.Which() => "C"; }
            public class Both : IB, IC { }
            """));

    [Fact]
    public void AnInterfaceMayTakeADefaultAwayAgain() =>
        Assert.Equal(["SL0305"], Front.ModuleCodes(
            """
            public interface IA { String Which() => "A"; }
            public interface IB : IA { String IA.Which(); }
            public class OnlyB : IB { }
            """));

    [Fact]
    public void AnExplicitMemberIsNotReachedByName() =>
        Assert.Equal(["SL0255"], Front.ModuleCodes(
            """
            public interface IShape { double Area(); }
            public class Square : IShape { double IShape.Area() => 1.0; }
            double Measure(Square square) => square.Area();
            """));

    // ------------------------------------------------------ static members

    private const string Additive = """
        public interface IAdditive<TSelf> where TSelf : IAdditive<TSelf>
        {
            static abstract TSelf Zero { get; }
            static abstract TSelf operator +(TSelf a, TSelf b);
            static virtual TSelf Twice(TSelf x) => x + x;
        }

        """;

    private const string Money = """
        public struct Money : IAdditive<Money>
        {
            public long Cents;
            public Money(long cents) { Cents = cents; }
            public static Money Zero => new Money(0);
            public static Money operator +(Money a, Money b) => new Money(a.Cents + b.Cents);
        }

        """;

    [Fact]
    public void AStructMayImplementAStaticOnlyInterface() =>
        Assert.Empty(Front.ModuleCodes(Additive + Money));

    [Fact]
    public void AStructMayNotImplementAnInterfaceAnObjectAnswers() =>
        Assert.Equal(["SL0302"], Front.ModuleCodes(
            "public interface IShape { double Area(); }\n" +
            "public struct Flat : IShape { public double Area() => 0.0; }"));

    [Fact]
    public void AStaticRequirementMustBeSupplied() =>
        Assert.Contains("SL0305", Front.ModuleCodes(Additive +
            "public struct Bare : IAdditive<Bare> { }"));

    [Fact]
    public void AStaticRequirementIsReachedThroughATypeParameter() =>
        Assert.Empty(Front.ModuleCodes(Additive + Money +
            """
            T Start<T>() where T : IAdditive<T> => T.Zero;
            T Double<T>(T x) where T : IAdditive<T> => T.Twice(x);
            long Use() => Start<Money>().Cents + Double(new Money(2)).Cents;
            """));

    [Theory]
    [InlineData("var zero = IAdditive<Money>.Zero;")]
    [InlineData("var two = IAdditive<Money>.Twice(new Money(1));")]
    public void AStaticRequirementIsNotReachedThroughItsInterface(string statement) =>
        Assert.Equal(["SL0797"], Front.ModuleCodes(Additive + Money +
            "void Use() { " + statement + " }"));

    /// <summary>
    /// As in C#: the default belongs to the interface, and a type that does
    /// not declare the member does not have it.
    /// </summary>
    [Fact]
    public void AStaticDefaultIsNotAMemberOfTheType() =>
        Assert.NotEmpty(Front.ModuleCodes(Additive + Money +
            "Money Use() => Money.Twice(new Money(1));"));

    [Fact]
    public void AnFBoundedInterfaceAcceptsTheClassNamingIt() =>
        Assert.Empty(Front.ModuleCodes(
            """
            public interface ISelf<TSelf> where TSelf : ISelf<TSelf> { TSelf Me(); }
            public class Node : ISelf<Node> { public Node Me() => this; }
            """));

    /// <summary>
    /// A field's type is resolved before any base list is read, and the
    /// constraint waits for them.
    /// </summary>
    [Fact]
    public void AConstraintOnAFieldTypeWaitsForTheBaseLists() =>
        Assert.Empty(Front.ModuleCodes(
            """
            public interface INamed { String Name(); }
            public class Box<T> where T : INamed { }
            public class Holder { public Box<Named>? Kept; }
            public class Named : INamed { public String Name() => "x"; }
            """));

    // ------------------------------------------------------ covariant returns

    private const string Animals = """
        public class Animal { }
        public class Dog : Animal { }
        """;

    [Theory]
    [InlineData("Animal", "Dog")]
    [InlineData("Animal?", "Dog")]
    [InlineData("Animal?", "Dog?")]
    public void AnOverrideMayNarrowWhatItReturns(string declared, string narrowed) =>
        Assert.Empty(Front.ModuleCodes(Animals +
            $$"""
            public class Shelter { public virtual {{declared}} Adopt() => new Dog(); }
            public class Kennel : Shelter { public override {{narrowed}} Adopt() => new Dog(); }
            """));

    [Theory]
    [InlineData("Dog", "Animal")]              // wider
    [InlineData("Dog", "Dog?")]                // loses the promise it is not null
    [InlineData("long", "int")]                // a value is not a reference
    public void AnOverrideMayNotReturnSomethingElse(string declared, string written) =>
        Assert.Equal(["SL0502"], Front.ModuleCodes(Animals +
            $$"""
            public class Shelter { public virtual {{declared}} Adopt() => default; }
            public class Kennel : Shelter { public override {{written}} Adopt() => default; }
            """));

    [Fact]
    public void ACallThroughTheDerivedTypeSeesTheNarrowerType() =>
        Assert.Empty(Front.ModuleCodes(Animals +
            """
            public class Shelter { public virtual Animal Adopt() => new Dog(); }
            public class Kennel : Shelter { public override Dog Adopt() => new Dog(); }
            Dog Take(Kennel kennel) => kennel.Adopt();
            """));

    [Fact]
    public void ACallThroughTheBaseSeesTheBaseType() =>
        Assert.Equal(["SL0265"], Front.ModuleCodes(Animals +
            """
            public class Shelter { public virtual Animal Adopt() => new Dog(); }
            public class Kennel : Shelter { public override Dog Adopt() => new Dog(); }
            Dog Take(Shelter shelter) => shelter.Adopt();
            """));

    [Fact]
    public void AGetOnlyPropertyMayNarrowItsType() =>
        Assert.Empty(Front.ModuleCodes(Animals +
            """
            public class Shelter { public virtual Animal Favorite => new Dog(); }
            public class Kennel : Shelter { public override Dog Favorite => new Dog(); }
            """));

    [Fact]
    public void AWritablePropertyMayNotNarrowItsType() =>
        Assert.Equal(["SL0502"], Front.ModuleCodes(Animals +
            """
            public class Shelter { public virtual Animal Pet { get; set; } }
            public class Kennel : Shelter { public override Dog Pet { get; set; } }
            """));

    [Fact]
    public void AnInterfaceImplementationMayNotNarrow() =>
        Assert.Equal(["SL0307"], Front.ModuleCodes(Animals +
            """
            public interface IShelter { Animal Adopt(); }
            public class Kennel : IShelter { public Dog Adopt() => new Dog(); }
            """));
}
