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
