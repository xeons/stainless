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

using Stainless.Binding;
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// The type symbols: what they measure, where their fields sit, and the
/// orderings other code silently depends on.
/// </summary>
public class TypeSystemTests
{
    // ------------------------------------------------------------ primitives

    /// <summary>
    /// The sizes are the language's, not the host's -- a pointer and an
    /// <c>nint</c> are eight bytes because there is no 32-bit target, which is
    /// also why there is no calling convention to choose.
    /// </summary>
    [Theory]
    [InlineData("bool", 1)]
    [InlineData("char", 1)]
    [InlineData("char16", 2)]
    [InlineData("char32", 4)]
    [InlineData("sbyte", 1)]
    [InlineData("byte", 1)]
    [InlineData("short", 2)]
    [InlineData("ushort", 2)]
    [InlineData("int", 4)]
    [InlineData("uint", 4)]
    [InlineData("long", 8)]
    [InlineData("ulong", 8)]
    [InlineData("nint", 8)]
    [InlineData("nuint", 8)]
    [InlineData("float", 4)]
    [InlineData("double", 8)]
    public void PrimitivesAreTheSizeTheLanguageSays(string name, int size)
    {
        var type = Assert.IsType<PrimitiveTypeSymbol>(Named(name));
        Assert.Equal(size, type.Size);
        Assert.Equal(size * 8, type.Bits);
    }

    /// <summary>
    /// <c>IsInteger</c> is a range test over the enum, so the order of the
    /// members is load-bearing. Inserting a kind in the wrong place would make
    /// a float an integer, or stop a <c>char</c> being one, and nothing would
    /// say so.
    /// </summary>
    [Fact]
    public void TheIntegerKindsAreContiguous()
    {
        foreach (var kind in Enum.GetValues<PrimitiveKind>())
        {
            bool inRange = kind is >= PrimitiveKind.Char and <= PrimitiveKind.NUInt;
            bool isInteger = kind is not (PrimitiveKind.Void or PrimitiveKind.Bool
                or PrimitiveKind.Float or PrimitiveKind.Double);

            Assert.Equal(isInteger, inRange);
        }
    }

    /// <summary>
    /// The three code units are integers -- they compare and index like any
    /// other -- and are the only three, which is what makes the encoding rule
    /// apply to exactly them.
    /// </summary>
    [Theory]
    [InlineData("char", true)]
    [InlineData("char16", true)]
    [InlineData("char32", true)]
    [InlineData("byte", false)]
    [InlineData("ushort", false)]
    [InlineData("uint", false)]
    [InlineData("int", false)]
    public void OnlyTheThreeEncodingsAreCodeUnits(string name, bool expected)
    {
        var type = (PrimitiveTypeSymbol)Named(name);
        Assert.Equal(expected, type.IsCodeUnit);
        Assert.True(type.IsInteger);
    }

    [Theory]
    [InlineData("sbyte", true)]
    [InlineData("short", true)]
    [InlineData("int", true)]
    [InlineData("long", true)]
    [InlineData("nint", true)]
    [InlineData("byte", false)]
    [InlineData("ushort", false)]
    [InlineData("uint", false)]
    [InlineData("ulong", false)]
    [InlineData("nuint", false)]
    [InlineData("char", false)]
    public void SignednessIsWhatItLooksLike(string name, bool signed) =>
        Assert.Equal(signed, ((PrimitiveTypeSymbol)Named(name)).IsSigned);

    /// <summary>
    /// The symbol for a named primitive, taken off a parameter -- which needs
    /// no value, and so cannot fail for a reason that is not about the type.
    /// </summary>
    private static TypeSymbol Named(string name)
    {
        var program = Front.BindModule($"public void F({name} p) {{ }}", out var diagnostics);
        Assert.Empty(Front.Codes(diagnostics));

        return program.Modules.SelectMany(m => m.Functions)
            .First(f => f.Name == "F" && f.ModuleName == "Test")
            .Parameters[0].Type;
    }

    // ---------------------------------------------------------------- layout

    /// <summary>
    /// A struct is laid out by the platform C rules, so a field's offset is
    /// where C would put it and the size is rounded up to the alignment.
    /// </summary>
    [Fact]
    public void AStructIsLaidOutLikeC()
    {
        var type = Front.Struct("public struct S { public sbyte A; public int B; public sbyte C; }", "S");

        Assert.Equal(0, type.Fields[0].Offset);
        Assert.Equal(4, type.Fields[1].Offset);
        Assert.Equal(8, type.Fields[2].Offset);
        Assert.Equal(4, type.Alignment);
        Assert.Equal(12, type.Size);
    }

    [Fact]
    public void AStructTakesItsAlignmentFromItsWidestField()
    {
        Assert.Equal(1, Front.Struct("public struct S { public sbyte A; }", "S").Alignment);
        Assert.Equal(4, Front.Struct("public struct S { public int A; }", "S").Alignment);
        Assert.Equal(8, Front.Struct("public struct S { public double A; }", "S").Alignment);
    }

    /// <summary>
    /// A nested struct is laid out inline, taking its own alignment with it
    /// rather than being flattened into the outer one.
    /// </summary>
    [Fact]
    public void ANestedStructKeepsItsAlignment()
    {
        var type = Front.Struct(
            """
            public struct Inner { public double A; }
            public struct S { public sbyte A; public Inner B; }
            """, "S");

        Assert.Equal(8, type.Fields[1].Offset);
        Assert.Equal(16, type.Size);
    }

    /// <summary>
    /// An empty struct is one byte, following C++ rather than the GNU
    /// zero-size extension. Zero would make an array of them meaningless.
    /// </summary>
    [Fact]
    public void AnEmptyStructIsOneByte() =>
        Assert.Equal(1, Front.Struct("public struct S { }", "S").Size);

    // ----------------------------------------------------------- class layout

    /// <summary>
    /// A class instance is the header plus its fields, and the header is where
    /// the reference counts and the TypeInfo live. The number is an ABI: the
    /// runtime's C reaches these offsets by hand.
    /// </summary>
    [Fact]
    public void AClassInstanceIsTheHeaderPlusItsFields()
    {
        var type = ClassNamed("public class C { public int A; public int B; }", "C");

        Assert.Equal(24, ClassTypeSymbol.HeaderSize);
        Assert.Equal(8, type.FieldsSize);
        Assert.Equal(32, type.InstanceSize);
    }

    /// <summary>A derived class's fields come after the ones it inherited.</summary>
    [Fact]
    public void ADerivedClassAppendsItsFields()
    {
        var derived = ClassNamed(
            """
            public class Base { public int A; }
            public class Derived : Base { public int B; }
            """, "Derived");

        Assert.Equal(4, derived.InheritedFieldsSize);
        Assert.Equal(8, derived.FieldsSize);
    }

    private static ClassTypeSymbol ClassNamed(string declarations, string name)
    {
        var program = Front.BindModule(declarations, out var diagnostics);
        Assert.Empty(Front.Codes(diagnostics));
        return program.Classes.First(c => c.Name == name);
    }

    // -------------------------------------------------------------- COM

    private const string ComShapes = """
        import Standard.Com;

        [Guid("11111111-1111-1111-1111-111111111111")]
        public com interface IFirst { void A(); void B(); }

        [Guid("22222222-2222-2222-2222-222222222222")]
        public com interface ISecond : IFirst { void C(); }

        public com class Thing : ISecond
        {
            int field;
            public void A() { }
            public void B() { }
            public void C() { }
        }
        """;

    /// <summary>
    /// The shapes, bound once.
    ///
    /// Symbols are compared by reference -- DerivesFrom asks whether this is
    /// that interface, not whether it has the same name -- so two binds would
    /// produce two IFirsts that agree about nothing.
    /// </summary>
    private static readonly Lazy<BoundProgram> ComProgram = new(() =>
    {
        var program = Front.BindModule(ComShapes, out var diagnostics);
        Assert.Empty(Front.Codes(diagnostics));
        return program;
    });

    private static ComInterfaceTypeSymbol Com(string name) =>
        ComProgram.Value.ComInterfaces.First(i => i.Name == name);

    /// <summary>
    /// IUnknown itself, which no declaration here names: an interface reaches
    /// it by extending nothing, and the program's list holds only what was
    /// written.
    /// </summary>
    private static ComInterfaceTypeSymbol Unknown() => Com("IFirst").BaseInterface!;

    /// <summary>
    /// Every COM vtable begins with QueryInterface, AddRef and Release, so an
    /// interface's own methods start at slot three -- and a root one extends
    /// IUnknown whether or not that was written.
    /// </summary>
    [Fact]
    public void AComVtableStartsAfterIUnknown()
    {
        Assert.Equal(3, ComInterfaceTypeSymbol.UnknownSlots);
        Assert.Equal("IUnknown", Com("IFirst").BaseInterface?.Name);
        Assert.Equal(ComInterfaceTypeSymbol.UnknownSlots,
                     Unknown().VirtualTable.Count);
    }

    /// <summary>
    /// Slots are numbered root-down: a derived interface's table is its base's
    /// followed by its own, which is what lets a derived pointer be used as a
    /// base one with no conversion.
    /// </summary>
    [Fact]
    public void SlotsAreNumberedRootDown()
    {
        var first = Com("IFirst");
        var second = Com("ISecond");

        Assert.Equal(5, first.VirtualTable.Count);
        Assert.Equal(6, second.VirtualTable.Count);

        // ISecond's first five slots are IFirst's, in the same order.
        Assert.Equal(first.VirtualTable.Select(m => m.Name),
                     second.VirtualTable.Take(5).Select(m => m.Name));
    }

    [Fact]
    public void SelfAndBasesRunFromTheLeafToTheRoot() =>
        Assert.Equal(["ISecond", "IFirst", "IUnknown"],
                     Com("ISecond").SelfAndBases().Select(i => i.Name));

    [Fact]
    public void DerivesFromFollowsTheChain()
    {
        Assert.True(Com("ISecond").DerivesFrom(Com("IFirst")));
        Assert.True(Com("ISecond").DerivesFrom(Unknown()));
        Assert.False(Com("IFirst").DerivesFrom(Com("ISecond")));

        // An interface derives from itself, which is what makes a cast to the
        // type you already hold succeed rather than querying for it.
        Assert.True(Com("IFirst").DerivesFrom(Com("IFirst")));
    }

    [Fact]
    public void AGuidAttributeFoldsToAnIid() =>
        Assert.Equal(Guid.Parse("11111111-1111-1111-1111-111111111111"), Com("IFirst").Iid);

    /// <summary>
    /// A com class carries one tear-off per interface it presents, each after
    /// its fields, and each is a vtable pointer and the distance back to the
    /// object header.
    /// </summary>
    [Fact]
    public void AComClassCarriesOneTearOffPerInterface()
    {
        var thing = ComProgram.Value.Classes.First(c => c.Name == "Thing");

        Assert.True(thing.IsCom);
        Assert.Equal(["ISecond", "IFirst"], thing.ComInterfaces.Select(i => i.Name));
        Assert.Equal(16, ClassTypeSymbol.TearOffSize);

        // Header, then the int field rounded up to eight, then the tear-offs.
        Assert.Equal(4, thing.FieldsSize);
        Assert.Equal(32, thing.TearOffsStart);
        Assert.Equal(32, thing.TearOffOffset(thing.ComInterfaces[0]));
        Assert.Equal(48, thing.TearOffOffset(thing.ComInterfaces[1]));
        Assert.Equal(64, thing.InstanceSize);
    }

    /// <summary>
    /// A COM reference is one pointer -- to the vtable pointer, not to the
    /// object -- which is the whole reason the tear-offs exist.
    /// </summary>
    [Fact]
    public void AComReferenceIsOnePointer()
    {
        var type = Com("IFirst");
        Assert.Equal(8, type.Size);
        Assert.Equal(8, type.Alignment);
        Assert.True(type.IsReferenceType);
        Assert.True(type.IsManaged);
    }

    /// <summary>Both kinds of interface are contracts, and no other type is.</summary>
    [Fact]
    public void OnlyAnInterfaceIsAContract()
    {
        var program = Front.BindModule(
            """
            public interface IPlain { int F(); }
            public class C { }
            public struct S { public int A; }
            """, out _);

        Assert.True(program.Interfaces.First(i => i.Name == "IPlain").IsContract);
        Assert.False(program.Classes.First(c => c.Name == "C").IsContract);
        Assert.False(program.Structs.First(s => s.Name == "S").IsContract);
        Assert.True(Com("IFirst").IsContract);
    }
}
