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

using System.Reflection;
using System.Runtime.CompilerServices;
using Stainless.Binding;
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// The bound tree's one walker, and the analyses built on it.
/// </summary>
public class BoundTreeTests
{
    private static readonly Assembly Compiler = typeof(BoundExpression).Assembly;

    public static TheoryData<string> NodeTypes()
    {
        var data = new TheoryData<string>();
        foreach (var type in Compiler.GetTypes()
                     .Where(t => !t.IsAbstract && IsNode(t))
                     .OrderBy(t => t.Name, StringComparer.Ordinal))
            data.Add(type.FullName!);
        return data;
    }

    /// <summary>
    /// Every child of every node type is visited, and visited once.
    ///
    /// Each property that can hold a node is filled with fresh nodes, and the
    /// walk has to hand back exactly those. A node type the walker has no case
    /// for fails here, and so does a child it forgets — which is what a hand
    /// written walker used to do without anyone noticing.
    /// </summary>
    [Theory]
    [MemberData(nameof(NodeTypes))]
    public void EveryChildIsVisitedOnce(string typeName)
    {
        var type = Compiler.GetType(typeName)!;
        var node = RuntimeHelpers.GetUninitializedObject(type);
        var expected = new List<object>();
        Fill(node, expected);

        var recorder = new Recorder();
        if (node is BoundExpression expression)
            recorder.VisitChildren(expression);
        else
            recorder.VisitChildren((BoundStatement)node);

        Assert.Equal(expected.Count, recorder.Seen.Count);
        foreach (var child in expected)
            Assert.Single(recorder.Seen, seen => ReferenceEquals(seen, child));
    }

    private static bool IsNode(Type type) =>
        typeof(BoundExpression).IsAssignableFrom(type) || typeof(BoundStatement).IsAssignableFrom(type);

    /// <summary>Puts a fresh node in every property that holds nodes, and lists those a walk should reach.</summary>
    private static void Fill(object owner, List<object> expected)
    {
        foreach (var property in owner.GetType().GetProperties(BindingFlags.Public | BindingFlags.Instance))
        {
            var backing = BackingField(owner.GetType(), property.Name);
            if (backing is null)
                continue;

            bool shared = property.GetCustomAttribute<SharedSubtreeAttribute>() is not null;
            var into = shared ? [] : expected;
            var value = Children(property.PropertyType, into);
            if (value is null)
            {
                Assert.False(Mentions(property.PropertyType),
                    $"{owner.GetType().Name}.{property.Name} holds nodes in a shape this test does not know");
                continue;
            }

            backing.SetValue(owner, value);
        }
    }

    /// <summary>A value for a property of this type holding fresh nodes, or null for one that holds none.</summary>
    private static object? Children(Type type, List<object> expected)
    {
        if (IsNode(type))
            return Node(type, expected);

        if (type == typeof(BoundSwitchSection) || type == typeof(BoundAsmOperand))
        {
            var part = RuntimeHelpers.GetUninitializedObject(type);
            Fill(part, expected);
            return part;
        }

        if (type.IsGenericType && type.GetGenericTypeDefinition() is var definition &&
            (definition == typeof(IReadOnlyList<>) || definition == typeof(List<>)))
        {
            var element = type.GetGenericArguments()[0];
            var list = (System.Collections.IList)Activator.CreateInstance(typeof(List<>).MakeGenericType(element))!;

            if (element == typeof((FieldSymbol, BoundExpression)))
            {
                for (int i = 0; i < 2; i++)
                    list.Add(((FieldSymbol)null!, (BoundExpression)Node(typeof(BoundExpression), expected)));
                return list;
            }

            if (!Mentions(element))
                return null;

            for (int i = 0; i < 2; i++)
                list.Add(Children(element, expected));
            return list;
        }

        return null;
    }

    /// <summary>A node of the type a property asks for, which a walk records and does not enter.</summary>
    private static object Node(Type wanted, List<object> expected)
    {
        var concrete = wanted.IsAbstract
            ? wanted == typeof(BoundStatement) ? typeof(BoundBreak) : typeof(BoundLiteral)
            : wanted;
        var node = RuntimeHelpers.GetUninitializedObject(concrete);
        expected.Add(node);
        return node;
    }

    private static bool Mentions(Type type) =>
        IsNode(type) || type == typeof(BoundSwitchSection) || type == typeof(BoundAsmOperand) ||
        type.IsGenericType && type.GetGenericArguments().Any(Mentions);

    private static FieldInfo? BackingField(Type? type, string name)
    {
        for (; type is not null; type = type.BaseType)
            if (type.GetField($"<{name}>k__BackingField", BindingFlags.NonPublic | BindingFlags.Instance) is { } field)
                return field;
        return null;
    }

    private sealed class Recorder : BoundTreeWalker
    {
        public List<object> Seen { get; } = [];

        public override void Visit(BoundExpression? expression)
        {
            if (expression is not null)
                Seen.Add(expression);
        }

        public override void Visit(BoundStatement? statement)
        {
            if (statement is not null)
                Seen.Add(statement);
        }
    }

    // ------------------------------------------------------------ 'out'

    private static string[] OutCodes(string function) =>
        Front.ModuleCodes(
            "struct Failure { public int Code; }\n" +
            "Result<int, Failure> Next() => Ok(1);\n" +
            "bool Give(out int x) { x = 1; return true; }\n" +
            function);

    [Fact]
    public void BreakingOutOfADoLeavesOutUnwritten() =>
        Assert.Contains("SL0600", OutCodes(
            "void F(bool stop, out int x)\n{\n    do\n    {\n        if (stop)\n            break;\n" +
            "        x = 1;\n    }\n    while (false);\n}"));

    [Fact]
    public void BreakingOutOfASwitchSectionLeavesOutUnwritten() =>
        Assert.Contains("SL0600", OutCodes(
            "void F(int n, out int x)\n{\n    switch (n)\n    {\n        case 0:\n" +
            "            if (n > 0)\n                break;\n            x = 1;\n            break;\n" +
            "        default:\n            x = 2;\n            break;\n    }\n}"));

    [Fact]
    public void TheRightOfAndIsNotCertain() =>
        Assert.Contains("SL0600", OutCodes(
            "bool F(bool first, out int x)\n{\n    bool both = first && Give(out x);\n    return both;\n}"));

    [Fact]
    public void ATryBeforeTheWriteCanReturnWithoutIt() =>
        Assert.Contains("SL0600", OutCodes(
            "Result<int, Failure> F(out int x)\n{\n    int n = try Next();\n    x = n;\n    return Ok(n);\n}"));

    [Fact]
    public void ATryAfterTheWriteIsFine() =>
        Assert.DoesNotContain("SL0600", OutCodes(
            "Result<int, Failure> F(out int x)\n{\n    x = 0;\n    int n = try Next();\n    return Ok(n);\n}"));

    [Fact]
    public void ALoopConditionAlwaysRuns() =>
        Assert.DoesNotContain("SL0600", OutCodes(
            "void F(out int x)\n{\n    while (Give(out x))\n        return;\n}"));

    [Fact]
    public void ASwitchedValueAlwaysRuns() =>
        Assert.DoesNotContain("SL0600", OutCodes(
            "void F(out int x)\n{\n    switch (Give(out x) ? 1 : 0)\n    {\n        case 1:\n            break;\n    }\n}"));

    [Fact]
    public void ADoConditionRunsWhenTheBodyEnds() =>
        Assert.DoesNotContain("SL0600", OutCodes(
            "void F(out int x)\n{\n    int i = 0;\n    do\n    {\n        i++;\n    }\n    while (!Give(out x));\n}"));

    // ------------------------------------------------------------ captured members

    /// <summary>
    /// A property whose getter reads a field through a switch expression — a
    /// held value and a chain of conditionals — is as stale in a closure as
    /// the field is.
    /// </summary>
    [Theory]
    [InlineData("String Mode => _level switch { 0 => \"idle\", _ => \"busy\" };")]
    [InlineData("String Mode => $\"{_level}\";")]
    [InlineData("int[] Mode => [_level];")]
    public void AGetterReadsItsFieldsWhereverTheyAre(string property) =>
        Assert.Contains("SL0610", Front.ModuleCodes($$"""
            public closure void Act();
            public class Panel
            {
                int _level;
                public Act Report;
                public {{property}}
                public Panel()
                {
                    Report = () => { var seen = Mode; };
                }
                public void Raise() => _level = _level + 1;
            }
            """));
}
