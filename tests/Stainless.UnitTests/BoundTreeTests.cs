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
/// The bound tree's one walker, the analyses built on it, and the verifier.
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
        Walk(recorder, node);

        Assert.Equal(expected.Count, recorder.Seen.Count);
        foreach (var child in expected)
            Assert.Single(recorder.Seen, seen => ReferenceEquals(seen, child));
    }

    private static void Walk(BoundTreeWalker walker, object node)
    {
        switch (node)
        {
            case BoundExpression expression: walker.VisitChildren(expression); break;
            case BoundStatement statement: walker.VisitChildren(statement); break;
            default: walker.VisitChildren((BoundPattern)node); break;
        }
    }

    private static object Rebuild(BoundTreeRewriter rewriter, object node) => node switch
    {
        BoundExpression expression => rewriter.RewriteChildren(expression),
        BoundStatement statement => rewriter.RewriteChildren(statement),
        _ => rewriter.RewriteChildren((BoundPattern)node),
    };

    private static bool IsNode(Type type) =>
        typeof(BoundExpression).IsAssignableFrom(type) || typeof(BoundStatement).IsAssignableFrom(type) ||
        typeof(BoundPattern).IsAssignableFrom(type);

    /// <summary>
    /// A property that names a value rather than holding a child: the input a
    /// pattern is asked of, which is what its expressions read.
    /// </summary>
    private static bool IsName(Type type) => type == typeof(BoundPlaceholder);

    /// <summary>A part of a node that is not a node, whose own properties hold its children.</summary>
    private static bool IsHolder(Type type) =>
        type == typeof(BoundSwitchSection) || type == typeof(BoundAsmOperand) ||
        type == typeof(BoundSwitchLabel) || type == typeof(BoundSwitchArm) ||
        type == typeof(BoundWithAssignment);

    /// <summary>Puts a fresh node in every property that holds nodes, and lists those a walk should reach.</summary>
    private static void Fill(object owner, List<object> expected)
    {
        foreach (var property in owner.GetType().GetProperties(BindingFlags.Public | BindingFlags.Instance))
        {
            var backing = BackingField(owner.GetType(), property.Name);
            if (backing is null)
                continue;

            bool shared = property.GetCustomAttribute<SharedSubtreeAttribute>() is not null ||
                          IsName(property.PropertyType);
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

        if (IsHolder(type))
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
        var concrete = !wanted.IsAbstract ? wanted
            : wanted == typeof(BoundStatement) ? typeof(BoundBreak)
            : wanted == typeof(BoundPattern) ? typeof(BoundDiscardPattern)
            : typeof(BoundLiteral);
        var node = RuntimeHelpers.GetUninitializedObject(concrete);
        expected.Add(node);
        return node;
    }

    private static bool Mentions(Type type) =>
        IsNode(type) || IsHolder(type) ||
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

        public override void Visit(BoundPattern? pattern)
        {
            if (pattern is not null)
                Seen.Add(pattern);
        }
    }

    // ------------------------------------------------------------ the rewriter

    /// <summary>
    /// Every child of every node type is rebuilt, and rebuilt once, and the
    /// rebuilt node holds exactly the new children and everything else the old
    /// one held.
    ///
    /// Each child is replaced by a fresh node, which makes the rewriter build a
    /// new node around them. A child it forgets, visits twice or leaves out of
    /// the new node fails here, and so does a property -- a flag, a symbol, a
    /// list of locals -- that the rebuild drops.
    /// </summary>
    [Theory]
    [MemberData(nameof(NodeTypes))]
    public void EveryChildIsRebuiltOnce(string typeName)
    {
        var type = Compiler.GetType(typeName)!;
        var node = RuntimeHelpers.GetUninitializedObject(type);
        var expected = new List<object>();
        Fill(node, expected);
        FillScalars(node);

        var replacer = new Replacer(expected);
        object rebuilt = Rebuild(replacer, node);

        Assert.Equal(expected.Count, replacer.Seen.Count);
        foreach (var child in expected)
            Assert.Single(replacer.Seen, seen => ReferenceEquals(seen, child));

        if (expected.Count == 0)
        {
            Assert.Same(node, rebuilt);
            return;
        }

        Assert.NotSame(node, rebuilt);

        var recorder = new Recorder();
        Walk(recorder, rebuilt);

        Assert.Equal(replacer.Made.Count, recorder.Seen.Count);
        foreach (var child in replacer.Made)
            Assert.Single(recorder.Seen, seen => ReferenceEquals(seen, child));

        AssertSameScalars(node, rebuilt);
    }

    /// <summary>Unchanged children leave the node as it was.</summary>
    [Theory]
    [MemberData(nameof(NodeTypes))]
    public void NothingChangedIsNothingCopied(string typeName)
    {
        var type = Compiler.GetType(typeName)!;
        var node = RuntimeHelpers.GetUninitializedObject(type);
        Fill(node, []);
        FillScalars(node);

        var identity = new Replacer([]);
        object rebuilt = Rebuild(identity, node);

        Assert.Same(node, rebuilt);
    }

    private static readonly Source.SourceText Scratch = new("rewritten.sl", "rewritten");

    /// <summary>A value that is not a default in every property that holds no nodes.</summary>
    private static void FillScalars(object owner)
    {
        foreach (var property in owner.GetType().GetProperties(BindingFlags.Public | BindingFlags.Instance))
        {
            var backing = BackingField(owner.GetType(), property.Name);
            if (backing is null || Mentions(property.PropertyType))
            {
                if (backing?.GetValue(owner) is { } holder && IsHolder(holder.GetType()))
                    FillScalars(holder);
                if (backing?.GetValue(owner) is System.Collections.IEnumerable parts and not string)
                    foreach (var part in parts)
                        if (part is not null && IsHolder(part.GetType()))
                            FillScalars(part);
                continue;
            }

            // What a constructor works out from its other arguments is not
            // the rewriter's to carry.
            if (property.Name == nameof(BoundExpression.Type))
                continue;

            backing.SetValue(owner, Sample(property.PropertyType));
        }
    }

    private static object? Sample(Type type)
    {
        if (type == typeof(bool)) return true;
        if (type == typeof(int)) return 7;
        if (type == typeof(ulong)) return 7ul;
        if (type == typeof(string)) return "sample";
        if (type == typeof(object)) return new object();
        if (type.IsEnum)
        {
            var values = Enum.GetValues(type);
            return values.Length > 1 ? values.GetValue(1) : values.GetValue(0);
        }
        if (type == typeof(Source.SourceSpan)) return new Source.SourceSpan(Scratch, 1, 3);

        if (Nullable.GetUnderlyingType(type) is { } underlying)
            return Sample(underlying);

        if (type.IsGenericType && type.GetGenericTypeDefinition() is var definition &&
            (definition == typeof(IReadOnlyList<>) || definition == typeof(List<>)))
        {
            var element = type.GetGenericArguments()[0];
            var list = (System.Collections.IList)Activator.CreateInstance(typeof(List<>).MakeGenericType(element))!;
            for (int i = 0; i < 2; i++)
                list.Add(Sample(element));
            return list;
        }

        if (type.IsValueType)
            return Activator.CreateInstance(type);

        var concrete = type.IsAbstract
            ? Compiler.GetTypes().First(t => !t.IsAbstract && type.IsAssignableFrom(t))
            : type;
        return RuntimeHelpers.GetUninitializedObject(concrete);
    }

    /// <summary>Every property that holds no nodes is the same object, or the same sequence, after the rebuild.</summary>
    private static void AssertSameScalars(object before, object after)
    {
        foreach (var property in before.GetType().GetProperties(BindingFlags.Public | BindingFlags.Instance))
        {
            var backing = BackingField(before.GetType(), property.Name);
            if (backing is null || property.GetCustomAttribute<SharedSubtreeAttribute>() is not null ||
                property.Name == nameof(BoundExpression.Type))
                continue;

            object? was = backing.GetValue(before);
            object? now = backing.GetValue(after);

            if (Mentions(property.PropertyType) && !IsName(property.PropertyType))
            {
                if (was is not null && IsHolder(was.GetType()))
                    AssertSameScalars(was, now!);
                else if (was is System.Collections.IEnumerable parts and not string)
                    foreach (var (part, rebuilt) in parts.Cast<object>().Zip(((System.Collections.IEnumerable)now!).Cast<object>()))
                        if (IsHolder(part.GetType()))
                            AssertSameScalars(part, rebuilt);
                continue;
            }

            string where = $"{before.GetType().Name}.{property.Name}";
            if (was is System.Collections.IEnumerable sequence and not string)
                Assert.True(sequence.Cast<object?>().SequenceEqual(((System.Collections.IEnumerable)now!).Cast<object?>()),
                    $"{where} was not carried over");
            else
                Assert.True(Equals(was, now), $"{where} was not carried over");
        }
    }

    /// <summary>Replaces each child a test put in with a fresh node of the same kind.</summary>
    private sealed class Replacer(List<object> children) : BoundTreeRewriter
    {
        public List<object> Seen { get; } = [];

        public List<object> Made { get; } = [];

        public override BoundExpression Rewrite(BoundExpression expression) =>
            (BoundExpression)Replace(expression);

        public override BoundStatement Rewrite(BoundStatement statement) =>
            (BoundStatement)Replace(statement);

        public override BoundPattern Rewrite(BoundPattern pattern) =>
            (BoundPattern)Replace(pattern);

        private object Replace(object node)
        {
            Seen.Add(node);
            if (!children.Contains(node))
                return node;

            var fresh = RuntimeHelpers.GetUninitializedObject(node.GetType());
            Made.Add(fresh);
            return fresh;
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

    // ------------------------------------------------------------ the verifier

    private static void Verify(params BoundStatement[] body)
    {
        var function = new FunctionSymbol
        {
            Name = "F",
            ModuleName = "Test",
            ReturnType = PrimitiveTypeSymbol.Void,
            Linkage = Syntax.LinkageKind.Stainless,
            Span = default,
        };

        BoundTreeVerifier.Verify(new BoundProgram
        {
            Modules = [],
            Functions = [new BoundFunction(function, new BoundBlock(default, body))],
            Classes = [],
            Interfaces = [],
            ComInterfaces = [],
            Structs = [],
            Arrays = [],
            RuntimeFactories = [],
            ExternalFunctions = [],
            Statics = [],
            StaticConstructors = [],
            Initialization = [],
        }, BoundTreeForm.Semantic);
    }

    [Fact]
    public void TheVerifierRefusesADraft()
    {
        var error = Assert.Throws<Source.InternalCompilerError>(() => Verify(
            new BoundExpressionStatement(default, new BoundArrayDraft(default, ArrayDraftType.Instance, []))));
        Assert.Contains("BoundArrayDraft", error.Problem);
    }

    [Fact]
    public void TheVerifierRefusesALocalNothingDeclared()
    {
        var stray = new LocalSymbol("stray", PrimitiveTypeSymbol.Int, isConst: false);
        var error = Assert.Throws<Source.InternalCompilerError>(() => Verify(
            new BoundExpressionStatement(default, new BoundLocalAccess(default, stray))));
        Assert.Contains("'stray'", error.Problem);
    }

    [Fact]
    public void TheVerifierAcceptsALocalDeclaredFirst()
    {
        var local = new LocalSymbol("held", PrimitiveTypeSymbol.Int, isConst: false);
        Verify(
            new BoundLocalDeclaration(default, local, null),
            new BoundExpressionStatement(default, new BoundLocalAccess(default, local)));
    }

    [Fact]
    public void TheVerifierRefusesAWriteIntoACopy()
    {
        var local = new LocalSymbol("held", PrimitiveTypeSymbol.Int, isConst: false);
        var copy = new BoundConversion(
            default, PrimitiveTypeSymbol.Int, new BoundLocalAccess(default, local), ConversionKind.Identity);
        var error = Assert.Throws<Source.InternalCompilerError>(() => Verify(
            new BoundLocalDeclaration(default, local, null),
            new BoundExpressionStatement(default, new BoundAssignment(
                default, copy, new BoundLiteral(default, PrimitiveTypeSymbol.Int, 1ul)))));
        Assert.Contains("not storage", error.Problem);
    }
}
