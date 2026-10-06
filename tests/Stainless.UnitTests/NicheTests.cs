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

using System.Text.RegularExpressions;
using Stainless.Binding;
using Stainless.Emit;
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// A variant of two cases, the first carrying nothing and the second a
/// never-null reference, has no tag: the first case is that reference being
/// null (docs/abi.md 2.3).
/// </summary>
public class NicheTests
{
    private const string Types = """
        public class Node { public Node() { } }
        public interface INamed { String Name { get; } }
        public struct Holder { public byte[] Data; public int Count; }
        public struct Entry { public int Id; public String Name; }
        public struct Wrapped { public Result<String, int> Inner; public int Count; }
        public struct Mixed { public Result<String, int> Inner; public String Name; }
        [Packed] public struct Squeezed { public byte Flag; public String Name; }
        public variant Labelled { Blank; Named(String Name); }
        public variant Backwards { Named(String Name); Blank; }
        public variant Two { Blank; Pair(int Id, String Name); }
        public variant Plain { Blank; Number(int Value); }
        public variant Three { Blank; Named(String Name); Other; }
        """;

    private static void Under(TargetPlatform target, Action body)
    {
        var before = TargetPlatform.Current;
        TargetPlatform.Current = target;
        try { body(); }
        finally { TargetPlatform.Current = before; }
    }

    private static VariantTypeSymbol OptionalOf(string type) =>
        Assert.IsType<VariantTypeSymbol>(
            Front.Struct(Types + $"public struct Probe {{ public Optional<{type}> Held; }}", "Probe")
                .Fields[0].Type);

    private static VariantTypeSymbol Variant(string name) =>
        Assert.IsType<VariantTypeSymbol>(Front.Struct(Types, name));

    [Theory]
    [InlineData("String", 8, false)]
    [InlineData("Node", 8, false)]
    [InlineData("INamed", 8, false)]
    [InlineData("int[]", 8, false)]
    [InlineData("Entry", 16, false)]
    [InlineData("Squeezed", 9, false)]
    [InlineData("Func<int, int>", 16, false)]
    [InlineData("Optional<String>", 16, true)]
    [InlineData("int", 8, true)]
    [InlineData("long", 16, true)]
    [InlineData("Node?", 16, true)]
    [InlineData("Result<String, int>", 24, true)]
    public void AnOptionalIsTaglessExactlyWhenItsValueHasANiche(string type, int size, bool tagged)
    {
        var optional = OptionalOf(type);
        Assert.Equal(size, optional.Size);
        Assert.Equal(tagged, optional.HasTag);
        Assert.Equal(tagged, optional.TagField is not null);
    }

    [Theory]
    [InlineData("String", 4)]
    [InlineData("Entry", 8)]
    [InlineData("Optional<String>", 8)]
    [InlineData("long", 16)]
    public void OnX86AnOptionalOfAReferenceIsFourBytes(string type, int size) =>
        Under(TargetPlatform.X86Windows, () => Assert.Equal(size, OptionalOf(type).Size));

    [Theory]
    [InlineData("Labelled", 8, false)]
    [InlineData("Two", 16, false)]
    [InlineData("Backwards", 16, true)]
    [InlineData("Plain", 8, true)]
    [InlineData("Three", 16, true)]
    public void AnyVariantOfThatShapeLosesItsTag(string name, int size, bool tagged)
    {
        var variant = Variant(name);
        Assert.Equal(size, variant.Size);
        Assert.Equal(tagged, variant.HasTag);
    }

    [Fact]
    public void TheNicheIsWhereTheReferenceIs()
    {
        Assert.Equal(8, Variant("Two").NicheOffset);
        Assert.Equal(1, OptionalOf("Squeezed").NicheOffset);
        Assert.Equal(0, OptionalOf("String").NicheOffset);
    }

    /// <summary>
    /// A type has no zero value exactly when it holds a never-null reference,
    /// and the first such reference is the niche -- unless what has no zero
    /// is a tagged variant inside it, whose tag has no spare null to lend.
    /// </summary>
    [Theory]
    [InlineData("String", false)]
    [InlineData("Node", false)]
    [InlineData("INamed", false)]
    [InlineData("Holder", false)]
    [InlineData("Entry", false)]
    [InlineData("Squeezed", false)]
    [InlineData("Mixed", false)]
    [InlineData("Func<int, int>", false)]
    [InlineData("(int, String)", false)]
    [InlineData("int", false)]
    [InlineData("Node?", false)]
    [InlineData("Optional<String>", false)]
    [InlineData("Labelled", false)]
    [InlineData("Result<String, int>", true)]
    [InlineData("Wrapped", true)]
    public void NoZeroValueMeansANicheUnlessATaggedVariantHasNone(string type, bool taggedVariantInside)
    {
        bool hasZero = !Front.ModuleCodes(Types + $"void F() {{ {type} probe = default; }}")
            .Contains("SLO0027");
        bool niche = !OptionalOf(type).HasTag;

        Assert.False(hasZero && niche, $"'{type}' has a zero value and a niche");
        Assert.Equal(!hasZero && !taggedVariantInside, niche);
    }

    [Fact]
    public void ACaseTestReadsTheNullInPlaceOfATag()
    {
        string ir = Front.ModuleIr("""
            public bool Has(Optional<String> value) => value is Some;
            public bool Empty(Optional<String> value) => value is None;
            """);

        Assert.Contains("%struct.Standard_Optional_String_ = type { %struct.Standard_Optional_String__payload }", ir);

        string has = Front.TestFunction(ir, "Has");
        Assert.Contains("icmp ne ptr", has);
        Assert.DoesNotContain("load i8", has);
        Assert.Contains("icmp eq ptr", Front.TestFunction(ir, "Empty"));
    }

    /// <summary>A pointer-wide optional is one integer, and travels in a register.</summary>
    [Theory]
    [InlineData(CppAbi.Microsoft)]
    [InlineData(CppAbi.Itanium)]
    public void AnOptionalReferenceIsPassedInARegister(CppAbi abi)
    {
        string ir = Front.ModuleIr("public bool Has(Optional<String> value) => value is Some;", abi);
        Assert.Matches(@"define [^\n]*Has[^\n]*\(i64 %arg\.value\)", ir);
    }

    [Fact]
    public void ASwitchOverATaglessVariantSwitchesOnTheNull()
    {
        string body = Front.TestFunction(Front.ModuleIr("""
            public int F(Optional<String> value)
            {
                switch (value)
                {
                    case Some: return 1;
                    case None: return 0;
                }
            }
            """), "F");

        Assert.Contains("icmp ne ptr", body);
        Assert.Contains("switch i8 ", body);
    }

    private const string Described = """
        public int F(Optional<String> value)
        {
            Optional<String> held = value;
            return held is Some ? 1 : 0;
        }
        """;

    /// <summary>The metadata nodes a described type's elements tuple lists.</summary>
    private static string[] ElementsOf(string ir, string name)
    {
        var described = Regex.Match(ir, "name: \"" + Regex.Escape(name) + @"""[^\n]*elements: !(\d+)");
        Assert.True(described.Success, name);

        string elements = Front.MetadataNode(ir, int.Parse(described.Groups[1].Value));
        return Regex.Matches(elements[(elements.IndexOf('{') + 1)..], @"!(\d+)")
            .Select(m => Front.MetadataNode(ir, int.Parse(m.Groups[1].Value)))
            .ToArray();
    }

    /// <summary>CodeView has no variant part, so there the payload is the one member.</summary>
    [Fact]
    public void CodeViewSeesATaglessVariantAsItsPayload()
    {
        string ir = Front.ModuleDebugIr(Described, format: DebugFormat.CodeView);
        var member = Assert.Single(ElementsOf(ir, "Standard.Optional<String>"));
        Assert.Contains("name: \"Some\"", member);
    }

    /// <summary>
    /// DWARF says which case it is: a variant part discriminated by the niche,
    /// the empty case claiming zero and the other case the rest.
    /// </summary>
    [Fact]
    public void DwarfDescribesATaglessVariantAsAVariantPart()
    {
        string ir = Front.ModuleDebugIr(Described, format: DebugFormat.Dwarf);
        var part = Assert.Single(ElementsOf(ir, "Standard.Optional<String>"));
        Assert.Contains("tag: DW_TAG_variant_part", part);
        Assert.Matches(@"discriminator: !\d+", part);

        string tuple = Front.MetadataNode(ir,
            int.Parse(Regex.Match(part, @"elements: !(\d+)").Groups[1].Value));
        var cases = Regex.Matches(tuple[(tuple.IndexOf('{') + 1)..], @"!(\d+)")
            .Select(m => Front.MetadataNode(ir, int.Parse(m.Groups[1].Value)))
            .ToArray();
        Assert.Equal(2, cases.Length);
        Assert.Contains("name: \"None\"", cases[0]);
        Assert.Contains("extraData: i64 0", cases[0]);
        Assert.Contains("name: \"Some\"", cases[1]);
        Assert.DoesNotContain("extraData", cases[1]);
    }
}
