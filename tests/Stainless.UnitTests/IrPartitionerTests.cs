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

using Stainless.Driver;
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// Dividing one module into several that compile at once. Every part is put
/// through LLVM's verifier, which is what says it stands on its own.
/// </summary>
public class IrPartitionerTests
{
    /// <summary>
    /// <c>main</c> and <c>Big</c> in one half, <c>Small</c> and <c>Counter</c>
    /// in the other, a string both read, and a function nothing calls.
    /// </summary>
    private const string Program = """
        %struct.Pair = type { i64, i64 }

        @.bytes.0 = private unnamed_addr constant [6 x i8] c"a@b.c\00"
        @_SLstatic_count = internal global i64 0, align 8

        declare void @puts(ptr)

        define i32 @main() {
        entry:
          call void @puts(ptr @.bytes.0)
          %n = call i64 @_SLBig(i64 1)
          %t = trunc i64 %n to i32
          ret i32 %t
        }

        define internal i64 @_SLBig(i64 %arg.x) {
        entry:
          %a = add i64 %arg.x, 1
          %b = add i64 %a, 2
          %c = add i64 %b, 3
          %d = add i64 %c, 4
          %e = add i64 %d, 5
          %f = add i64 %e, 6
          %g = add i64 %f, 7
          %h = add i64 %g, 8
          %i = add i64 %h, 9
          %j = add i64 %i, 10
          %k = add i64 %j, 11
          %l = add i64 %k, 12
          %m = add i64 %l, 13
          %n = add i64 %m, 14
          %o = add i64 %n, 15
          %p = add i64 %o, 16
          %q = add i64 %p, 17
          %r = call i64 @_SLSmall(i64 %q)
          ret i64 %r
        }

        define internal i64 @_SLSmall(i64 %arg.x) {
        entry:
          call void @puts(ptr @.bytes.0)
          %v = load i64, ptr @_SLstatic_count, align 8
          %w = add i64 %v, %arg.x
          store i64 %w, ptr @_SLstatic_count, align 8
          ret i64 %w
        }

        define internal i64 @_SLCounter(i64 %arg.x) {
        entry:
          %u = call i64 @_SLSmall(i64 %arg.x)
          %v = call i64 @_SLSmall(i64 %u)
          %w = call i64 @_SLSmall(i64 %v)
          %y = call i64 @_SLSmall(i64 %w)
          %z = call i64 @_SLSmall(i64 %y)
          %aa = call i64 @_SLSmall(i64 %z)
          %ab = call i64 @_SLSmall(i64 %aa)
          %ac = call i64 @_SLSmall(i64 %ab)
          %ad = call i64 @_SLSmall(i64 %ac)
          %ae = call i64 @_SLSmall(i64 %ad)
          %af = call i64 @_SLSmall(i64 %ae)
          %ag = call i64 @_SLSmall(i64 %af)
          %ah = call i64 @_SLSmall(i64 %ag)
          %ai = call i64 @_SLSmall(i64 %ah)
          %aj = call i64 @_SLSmall(i64 %ai)
          %ak = call i64 @_SLSmall(i64 %aj)
          %al = call i64 @_SLSmall(i64 %ak)
          ret i64 %al
        }

        define internal void @_SLNeverCalled() {
        entry:
          ret void
        }

        @llvm.global_ctors = appending global [1 x { i32, ptr, ptr }] [{ i32, ptr, ptr } { i32 1, ptr @_SLRegister, ptr null }]

        define internal void @_SLRegister() {
        entry:
          %c = call i64 @_SLCounter(i64 0)
          ret void
        }

        """;

    private static IReadOnlyList<string> Divided(string ir, int parts)
    {
        var result = IrPartitioner.Split(ir, parts, bytesPerPart: 0);
        foreach (string part in result)
            Front.Verified(part);
        return result;
    }

    /// <summary>The part that emits <paramref name="name"/>, as against one holding a copy.</summary>
    private static int PartDefining(IReadOnlyList<string> parts, string name)
    {
        var definition = new System.Text.RegularExpressions.Regex(
            @"^define (?!available_externally)[^@\n]*" + System.Text.RegularExpressions.Regex.Escape(name),
            System.Text.RegularExpressions.RegexOptions.Multiline);
        return parts.Select((text, index) => (text, index))
            .Single(p => definition.IsMatch(p.text))
            .index;
    }

    [Fact]
    public void EveryPartStandsOnItsOwn()
    {
        var parts = Divided(Program, 2);

        Assert.Equal(2, parts.Count);
    }

    [Fact]
    public void AFunctionReachedFromAnotherPartIsHiddenAndDeclaredThere()
    {
        var parts = Divided(Program, 2);
        int home = PartDefining(parts, "@_SLSmall(");

        Assert.Contains("define hidden i64 @_SLSmall(", parts[home]);
        Assert.Contains("@_SLSmall(", parts[1 - home]);
        Assert.DoesNotContain("define internal i64 @_SLSmall(", parts[1 - home]);
    }

    [Fact]
    public void ASmallFunctionIsCopiedForInliningAndTheRestAreDeclared()
    {
        var parts = Divided(Program, 2);
        int home = PartDefining(parts, "@_SLSmall(");

        Assert.Contains("define available_externally hidden i64 @_SLSmall(", parts[1 - home]);
        Assert.DoesNotContain("available_externally hidden i64 @_SLCounter(", string.Concat(parts));
    }

    [Fact]
    public void AStringIsCopiedIntoEveryPartThatReadsItAndAStaticIsNot()
    {
        var parts = Divided(Program, 2);

        Assert.All(parts, part => Assert.Contains("@.bytes.0 = private unnamed_addr constant", part));
        Assert.Single(parts, part => part.Contains("@_SLstatic_count = hidden global i64 0", StringComparison.Ordinal) ||
                                     part.Contains("@_SLstatic_count = internal global i64 0", StringComparison.Ordinal));
    }

    [Fact]
    public void WhatNothingReachesIsLeftOut()
    {
        var parts = Divided(Program, 2);

        Assert.All(parts, part => Assert.DoesNotContain("@_SLNeverCalled", part));
    }

    [Fact]
    public void AConstructorIsKeptThroughTheArrayThatRegistersIt()
    {
        var parts = Divided(Program, 2);

        Assert.Contains("@llvm.global_ctors", parts[0]);
        Assert.Contains(parts, part => part.Contains("@_SLRegister() {", StringComparison.Ordinal));
    }

    [Fact]
    public void LinesEndedInCrlfAreReadTheSame()
    {
        var parts = Divided(Program.ReplaceLineEndings("\r\n"), 2);

        Assert.Equal(2, parts.Count);
        Assert.All(parts, part => Assert.DoesNotContain("@_SLNeverCalled", part));
    }

    [Fact]
    public void WhatNamesALabelInModuleAssemblyStaysWithTheAssembly()
    {
        string ir = Program + """
            module asm ".section .rdata"
            module asm "_SLembed0:"
            module asm ".quad 7"
            @"\01_SLembed0" = external hidden global i64, align 8

            define i32 @second() {
            entry:
              %v = load i64, ptr @"\01_SLembed0", align 8
              %t = trunc i64 %v to i32
              ret i32 %t
            }

            """;

        var parts = Divided(ir, 2);

        Assert.Contains("define i32 @second()", parts[0]);
        Assert.Contains("module asm \"_SLembed0:\"", parts[0]);
        Assert.DoesNotContain("module asm", parts[1]);
    }

    [Fact]
    public void AModuleTooSmallToDivideComesBackWhole()
    {
        var parts = IrPartitioner.Split(Program, 8, bytesPerPart: 1_000_000);

        Assert.Single(parts);
        Assert.Same(Program, parts[0]);
    }
}
