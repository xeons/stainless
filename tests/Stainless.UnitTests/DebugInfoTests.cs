// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This file is part of the Stainless compiler. It is free software: you
// can redistribute it and/or modify it under the terms of the GNU General
// Public License as published by the Free Software Foundation, either
// version 3 of the License, or (at your option) any later version.
//
// It is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

using Stainless.Emit;
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// What a variable's description actually points at.
/// </summary>
/// <remarks>
/// <para>
/// <c>tests/cases/debug-info</c> checks that the right nodes are <i>emitted</i>,
/// which is most of what matters and is not all of it: a variable's
/// <c>type:</c> is a node number, and the case file leaves numbers out on
/// purpose so that adding a type somewhere else does not break it. That left a
/// gap a real bug lived in — every class after the first got the composite
/// where it should have had the pointer — and it verified, and it ran, and only
/// a debugger reading a local noticed.
/// </para>
/// <para>
/// These tests follow the number.
/// </para>
/// </remarks>
public class DebugInfoTests
{
    /// <summary>
    /// A reference is a pointer, and stays one however many of them there are.
    /// </summary>
    /// <remarks>
    /// Two locals of the same class type is the whole test: the first use
    /// registered the pointer node and the class body then overwrote it, so one
    /// variable of a type looked perfect and the second was a 40-byte structure
    /// read out of an 8-byte slot.
    /// </remarks>
    [Theory]
    [InlineData("first")]
    [InlineData("second")]
    public void AClassLocalIsDescribedAsAPointer(string local)
    {
        string ir = Front.ModuleDebugIr("""
            public class Node { public int Value; }

            public void Use()
            {
                Node first = new Node();
                Node second = first;
                first.Value = second.Value;
            }
            """);

        int type = Front.LocalVariableTypeNode(ir, "Use", local);
        Assert.True(type >= 0, $"no DILocalVariable for '{local}'");

        string node = Front.MetadataNode(ir, type);
        Assert.Contains("DW_TAG_pointer_type", node);
    }

    /// <summary>
    /// And the thing it points at is the class body, with its header.
    /// </summary>
    [Fact]
    public void ThatPointerNamesTheClassBody()
    {
        string ir = Front.ModuleDebugIr("""
            public class Node { public int Value; }

            public void Use()
            {
                Node only = new Node();
                only.Value = 1;
            }
            """);

        string node = Front.MetadataNode(ir, Front.LocalVariableTypeNode(ir, "Use", "only"));
        int body = int.Parse(new string(node[(node.IndexOf("baseType: !") + 11)..]
            .TakeWhile(char.IsDigit).ToArray()));

        string described = Front.MetadataNode(ir, body);
        Assert.Contains("DW_TAG_structure_type", described);
        Assert.Contains("Test.Node", described);
    }

    /// <summary>
    /// An array is a reference too, and was never wrong — which is what made
    /// the class case look like something about classes rather than about the
    /// map they were registered in.
    /// </summary>
    [Fact]
    public void AnArrayLocalIsAPointerAsWell()
    {
        string ir = Front.ModuleDebugIr("""
            public void Use()
            {
                int[] values = new int[2];
                values[0] = 1;
            }
            """);

        string node = Front.MetadataNode(ir, Front.LocalVariableTypeNode(ir, "Use", "values"));
        Assert.Contains("DW_TAG_pointer_type", node);
    }

    /// <summary>
    /// A struct is not a reference, and must not acquire a pointer from this.
    /// </summary>
    [Fact]
    public void AStructLocalIsTheStructItself()
    {
        string ir = Front.ModuleDebugIr("""
            public struct Point { public int X; public int Y; }

            public void Use()
            {
                Point here;
                here.X = 1;
                here.Y = 2;
            }
            """);

        string node = Front.MetadataNode(ir, Front.LocalVariableTypeNode(ir, "Use", "here"));
        Assert.Contains("DW_TAG_structure_type", node);
        Assert.DoesNotContain("DW_TAG_pointer_type", node);
    }

    /// <summary>
    /// Which module flag each format asks for.
    /// </summary>
    /// <remarks>
    /// <c>tests/cases/debug-format-*</c> pins that the default follows the
    /// target. This pins what each choice emits. <c>Both</c> is reachable
    /// nowhere else: the harness cannot pass a flag and no project file
    /// carries one.
    /// </remarks>
    [Theory]
    [InlineData(DebugFormat.Dwarf, true, false)]
    [InlineData(DebugFormat.CodeView, false, true)]
    [InlineData(DebugFormat.Both, true, true)]
    public void TheFormatDecidesWhichModuleFlagsAreAskedFor(
        DebugFormat format, bool dwarf, bool codeView)
    {
        string ir = Front.ModuleDebugIr("public void Use() { int a = 1; }",
                                        format: format);

        Assert.Equal(dwarf, ir.Contains("!\"Dwarf Version\"", StringComparison.Ordinal));
        Assert.Equal(codeView, ir.Contains("!\"CodeView\"", StringComparison.Ordinal));
    }

    /// <summary>
    /// A local declared inside a <c>{ }</c> is scoped to that block.
    /// </summary>
    /// <remarks>
    /// Which is what stops a debugger showing it on every line of the
    /// function, holding whatever its stack slot happened to contain.
    /// </remarks>
    [Fact]
    public void ALocalInsideABlockIsScopedToIt()
    {
        string ir = Front.ModuleDebugIr("""
            public void Use()
            {
                int throughout = 1;
                {
                    int onlyHere = 2;
                    throughout = onlyHere;
                }
            }
            """);

        int inner = Front.LocalVariableScopeNode(ir, "Use", "onlyHere");
        Assert.True(inner >= 0, "no DILocalVariable for 'onlyHere'");
        Assert.Contains("DILexicalBlock", Front.MetadataNode(ir, inner));
    }

    /// <summary>
    /// And one in the function body is scoped to the subprogram itself.
    /// </summary>
    /// <remarks>
    /// A lexical block for a function body would be an entry per function
    /// saying what <c>DW_TAG_subprogram</c> already says.
    /// </remarks>
    [Fact]
    public void ALocalInTheFunctionBodyIsScopedToTheFunction()
    {
        string ir = Front.ModuleDebugIr("""
            public void Use()
            {
                int throughout = 1;
                {
                    int onlyHere = 2;
                    throughout = onlyHere;
                }
            }
            """);

        int outer = Front.LocalVariableScopeNode(ir, "Use", "throughout");
        Assert.True(outer >= 0, "no DILocalVariable for 'throughout'");
        Assert.Contains("DISubprogram", Front.MetadataNode(ir, outer));
    }

    /// <summary>
    /// A <c>for</c> is a scope of its own, so its counter is not in scope
    /// after it.
    /// </summary>
    [Fact]
    public void AForLoopScopesItsOwnCounter()
    {
        string ir = Front.ModuleDebugIr("""
            public void Use()
            {
                int total = 0;
                for (int step = 0; step < 3; step++)
                    total = total + step;
            }
            """);

        int loop = Front.LocalVariableScopeNode(ir, "Use", "step");
        Assert.True(loop >= 0, "no DILocalVariable for 'step'");
        Assert.Contains("DILexicalBlock", Front.MetadataNode(ir, loop));
    }

    /// <summary>
    /// The compile unit says whether the code it describes was optimized.
    /// </summary>
    /// <remarks>
    /// It was hardcoded false while <c>-O2</c> is the default, so it was a lie
    /// in the common case — and a debugger reads it to decide whether to warn
    /// that a value may be stale, which makes it a lie that is acted on.
    /// </remarks>
    [Theory]
    [InlineData(false, "isOptimized: false")]
    [InlineData(true, "isOptimized: true")]
    public void TheCompileUnitSaysWhetherItWasOptimized(bool optimized, string expected)
    {
        string ir = Front.ModuleDebugIr("public void Use() { int a = 1; }",
                                        optimized: optimized);

        Assert.Contains(expected, Front.MetadataNode(ir, 0));
    }
}
