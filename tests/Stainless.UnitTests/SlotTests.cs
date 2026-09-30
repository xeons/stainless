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
/// <c>Slot&lt;T&gt;</c>: a <c>T</c> when <c>T</c> has a zero value, an
/// <c>Optional&lt;T&gt;</c> of the same size when it has none, and always
/// empty at zero.
/// </summary>
public class SlotTests
{
    private const string Types = """
        public struct Entry { public int Id; public String Name; }
        """;

    private static void Under(TargetPlatform target, Action body)
    {
        var before = TargetPlatform.Current;
        TargetPlatform.Current = target;
        try { body(); }
        finally { TargetPlatform.Current = before; }
    }

    private static SlotTypeSymbol SlotOf(string element) =>
        Assert.IsType<SlotTypeSymbol>(
            Front.Struct(Types + $"public struct Probe {{ public Slot<{element}> Held; }}", "Probe")
                .Fields[0].Type);

    [Theory]
    [InlineData("String", 8, true)]
    [InlineData("Entry", 16, true)]
    [InlineData("int", 4, false)]
    [InlineData("long", 8, false)]
    [InlineData("String?", 8, false)]
    [InlineData("Optional<int>", 8, false)]
    [InlineData("Result<String, int>", 24, true)]
    public void ASlotIsItsElementOrAnOptionalOfIt(string element, int size, bool isChecked)
    {
        var slot = SlotOf(element);
        Assert.Equal(size, slot.Size);
        Assert.Equal(isChecked, slot.IsChecked);
        Assert.Equal(isChecked, slot.ValueField.Type is VariantTypeSymbol { Template.Name: "Optional" } &&
                                !element.StartsWith("Optional", StringComparison.Ordinal));
    }

    [Fact]
    public void OnX86ASlotOfAStringIsFourBytes() =>
        Under(TargetPlatform.X86Windows, () => Assert.Equal(4, SlotOf("String").Size));

    [Theory]
    [InlineData("Slot<String>[] room = new Slot<String>[4];")]
    [InlineData("Slot<Entry> one = default;")]
    [InlineData("Slot<String> one; var copy = one;")]
    public void AnEmptySlotIsAZeroValue(string body) =>
        Assert.Empty(Front.ModuleCodes(Types + $"void F() {{ {body} }}").Where(c => c.StartsWith("SL081")));

    [Fact]
    public void ASlotOfAStringIsCheckedOnRead()
    {
        string body = Front.TestFunction(Front.ModuleIr(
            "public String F(Slot<String>[] room, nuint at) => room[at].Value;"), "F");

        Assert.Contains("icmp ne ptr", body);
        Assert.Contains("call void @sl_slot_empty(", body);
    }

    [Fact]
    public void ASlotOfAnIntIsReadAsAnInt()
    {
        string body = Front.TestFunction(Front.ModuleIr(
            "public int F(Slot<int>[] room, nuint at) => room[at].Value;"), "F");

        Assert.DoesNotContain("sl_slot_empty", body);
        Assert.DoesNotContain("icmp ne ptr", body);
    }

    /// <summary>
    /// <c>Array.Create</c> is the one way to make an array of a type with no
    /// zero value without a slot, so it is filled in place, in order, where it
    /// is called: an allocation and a loop, and no call to the library.
    /// </summary>
    [Fact]
    public void ArrayCreateFillsInPlace()
    {
        string body = Front.TestFunction(Front.ModuleIr(
            "public String[] F(nuint count) => Array.Create(count, (i) => \"item\");"), "F");

        Assert.Contains("call ptr @sl_array_alloc(", body);
        Assert.Contains("fill.head", body);
        Assert.DoesNotContain("5Array6Create", body);
    }

    [Fact]
    public void AValueWritesASlot() =>
        Assert.Empty(Front.ModuleCodes("""
            void F(Slot<String>[] room, String word)
            {
                room[0] = word;
                room[1] = room[0];
                room[0].Clear();
            }
            """));

    [Fact]
    public void AValueIsNotWrittenThroughTheReader() =>
        Assert.NotEmpty(Front.ModuleCodes("""
            void F(Slot<String>[] room, String word)
            {
                room[0].Value = word;
            }
            """));
}
