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
/// A type whose zero would hold a null in a never-null reference has no zero
/// value, and nothing may make one: the definite assignment of a local a slot
/// at a time, a constructor's fields through its private helpers, and the
/// forms that stay legal because nothing is ever zero in them.
/// </summary>
public class ZeroValueTests
{
    private const string Types = """
        public struct Holder { public byte[] Data; public int Count; }
        public struct Pair { public Holder Left; public String Name; }
        public class Node { public Node() { } }
        Holder Make() { Holder h; h.Data = []; return h; }
        """;

    private static string[] Codes(string body) =>
        Front.ModuleCodes(Types + "void Probe(bool flag)\n{\n" + body + "\n}\n");

    [Theory]
    [InlineData("int n; n = 1;")]
    [InlineData("String s; s = \"x\"; var t = s;")]
    [InlineData("String s; if (flag) s = \"a\"; else s = \"b\"; var t = s;")]
    [InlineData("Holder h; h.Data = [1]; var t = h;")]
    [InlineData("Holder h; h.Count = 2; var n = h.Count;")]
    [InlineData("Pair p; p.Name = \"n\"; p.Left.Data = [1]; var t = p;")]
    [InlineData("Pair p; p.Name = \"n\"; var n = p.Left.Count;")]
    [InlineData("Holder h; h = Make(); var t = h;")]
    [InlineData("while (flag) { Holder h; h.Data = [1]; var t = h; }")]
    [InlineData("String[] none = new String[0];")]
    [InlineData("Node? maybe = default;")]
    [InlineData("int[] numbers = new int[4];")]
    public void NothingZeroIsReadHere(string body) =>
        Assert.Empty(Codes(body).Where(c => c.StartsWith("SL081")));

    [Theory]
    [InlineData("String s; var t = s;")]
    [InlineData("String s; if (flag) s = \"a\"; var t = s;")]
    [InlineData("Holder h; h.Count = 1; var t = h;")]
    [InlineData("Pair p; p.Name = \"n\"; var t = p.Left;")]
    [InlineData("Holder h; var n = h.Data.Length;")]
    [InlineData("Holder h; while (flag) { var t = h; h.Data = [1]; }")]
    public void AReadBeforeEverySlotIsWrittenIsRefused(string body) =>
        Assert.Contains("SLO0028", Codes(body));

    [Theory]
    [InlineData("var h = default(Holder);", "SLO0027")]
    [InlineData("Node n = default;", "SLO0027")]
    [InlineData("var words = new String[3];", "SLO0029")]
    [InlineData("var nodes = new Node[1];", "SLO0029")]
    public void AZeroIsNotMadeOfATypeWithoutOne(string body, string code) =>
        Assert.Contains(code, Codes(body));

    [Fact]
    public void AFieldAPrivateHelperWritesIsWritten() =>
        Assert.DoesNotContain("SLO0030", Front.ModuleCodes("""
            public class Form
            {
                private String _title;
                public Form() { InitializeComponent(); }
                private void InitializeComponent() { _title = "form"; }
            }
            """));

    [Fact]
    public void AHelperThatOnlySometimesWritesDoesNot() =>
        Assert.Contains("SLO0030", Front.ModuleCodes("""
            public class Form
            {
                private String _title;
                public Form(bool flag) { InitializeComponent(flag); }
                private void InitializeComponent(bool flag)
                {
                    if (flag)
                        return;
                    _title = "form";
                }
            }
            """));

    [Fact]
    public void APublicMethodIsNotFollowed() =>
        Assert.Contains("SLO0030", Front.ModuleCodes("""
            public class Form
            {
                private String _title;
                public Form() { Reset(); }
                public void Reset() { _title = "form"; }
            }
            """));

    [Theory]
    [InlineData("private String _name = \"x\";")]
    [InlineData("public required String Name;")]
    [InlineData("private String? _name;")]
    [InlineData("private int _count;")]
    [InlineData("public Node Badge { get => field ??= new Node(); }")]
    public void AFieldThatStartsWithAValueNeedsNoConstructorToGiveItOne(string member) =>
        Assert.DoesNotContain("SLO0030",
            Front.ModuleCodes(Types + $"public class Owner {{ {member} }}"));

    [Fact]
    public void AStructFieldMayBeWrittenAFieldAtATime() =>
        Assert.DoesNotContain("SLO0030", Front.ModuleCodes(Types + """
            public class Owner
            {
                private Pair _pair;
                public Owner() { _pair.Name = "n"; _pair.Left.Data = []; }
            }
            """));

    [Fact]
    public void DelegatingHandsTheObligationOn() =>
        Assert.Empty(Front.ModuleCodes("""
            public class Named
            {
                private String _name;
                public Named(String name) { _name = name; }
                public Named() : this("none") { }
            }
            """));

    [Fact]
    public void AGenericBodyIsJudgedPerInstantiation() =>
        Assert.Contains("SLO0027", Front.ModuleCodes("""
            T Blank<T>() => default(T);
            void Use() { int n = Blank<int>(); String s = Blank<String>(); }
            """));

    /// <summary>
    /// No module is exempt. The standard library's own collections hold
    /// their spare capacity in slots, so a program that uses every one of
    /// them binds with nothing reported.
    /// </summary>
    [Fact]
    public void TheCollectionsNeedNoExemption() =>
        Assert.Empty(Front.ModuleCodes("""
            import Standard.Collections;
            void Use()
            {
                var list = new List<String>();
                list.Add("a");
                list.RemoveAt(0u);
                var map = new Dictionary<String, String>();
                map.SetValue("k", "v");
                map.Remove("k");
                var set = new HashSet<String>();
                set.Add("a");
                var queue = new Queue<String>();
                queue.Enqueue("a");
                queue.Dequeue();
                var stack = new Stack<String>();
                stack.Push("a");
                stack.Pop();
                var sorted = new SortedList<String, String>();
                sorted.SetValue("k", "v");
                var linked = new LinkedList<String>();
                linked.AddLast("a");
                String[] made = ["x", ..list];
                Sort(made);
            }
            """));

    [Fact]
    public void TheUncheckedModuleIsGone() =>
        Assert.NotEmpty(Front.ModuleCodes("""
            import Standard.Unchecked;
            void Use() { }
            """));
}
