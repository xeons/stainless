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
/// LLVM's verifier, as the compiler drives it: what it is told, and how what
/// it says is turned into the function a fault is in.
/// </summary>
public class IrVerifierTests
{
    /// <summary>One valid function and one whose use comes before its definition.</summary>
    private const string Broken = """
        define i32 @fine(i32 %x) {
        entry:
          ret i32 %x
        }

        define i32 @"_SL4Test5Twice"(i32 %x) {
        entry:
          %y = add i32 %x, 1
          br label %next
        next:
          %z = add i32 %w, 1
          %w = add i32 %y, 1
          ret i32 %z
        }
        """;

    /// <summary>
    /// Every emitter test's IR goes through <see cref="Front.Verified"/>, which
    /// verifies nothing on a machine with no clang. This is what says so.
    /// </summary>
    [Fact]
    public void TheVerifierIsAvailable()
    {
        if (Front.Tools.Value is null)
            Assert.Skip("no clang was found, so no emitted IR in this run was verified");
    }

    [Fact]
    public void AModuleThatBreaksARuleIsRefusedAndPlaced()
    {
        if (Front.Tools.Value is not { } tools)
        {
            Assert.Skip("no clang was found");
            return;
        }

        var fault = tools.VerifyIr(Broken);

        Assert.NotNull(fault);
        Assert.Equal("_SL4Test5Twice", fault.Function);
        Assert.Contains("does not dominate all uses", fault.Message);
    }

    [Fact]
    public void AValidModuleIsAccepted()
    {
        if (Front.Tools.Value is not { } tools)
        {
            Assert.Skip("no clang was found");
            return;
        }

        Assert.Null(tools.VerifyIr("define void @f() {\nentry:\n  ret void\n}\n"));
    }

    /// <summary>
    /// A description LLVM finds invalid is stripped with a warning and a zero
    /// exit code, by clang and by opt alike. Accepting that would ship a
    /// binary no debugger can read.
    /// </summary>
    [Fact]
    public void InvalidDebugInformationIsAFault()
    {
        if (Front.Tools.Value is not { } tools)
        {
            Assert.Skip("no clang was found");
            return;
        }

        const string ir = """
            define i32 @f(i32 %x) !dbg !4 {
            entry:
              ret i32 %x, !dbg !7
            }

            !llvm.dbg.cu = !{!0}
            !llvm.module.flags = !{!2}
            !0 = distinct !DICompileUnit(language: DW_LANG_C, file: !1, producer: "t", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug)
            !1 = !DIFile(filename: "a.sl", directory: "/")
            !2 = !{i32 2, !"Debug Info Version", i32 3}
            !4 = distinct !DISubprogram(name: "f", scope: !1, file: !1, line: 1, type: !5, spFlags: DISPFlagDefinition, unit: !0)
            !5 = !DISubroutineType(types: !6)
            !6 = !{}
            !7 = !DILocation(line: 2, scope: !1)
            """;

        var fault = tools.VerifyIr(ir);

        Assert.NotNull(fault);
        Assert.Equal("f", fault.Function);
    }

    /// <summary>
    /// clang's framing is dropped and the verifier's own words kept, and the
    /// instructions it printed are found in the body that holds them.
    /// </summary>
    [Fact]
    public void ClangsOutputIsReducedToTheVerifiersMessage()
    {
        const string output = """
            error: invalid LLVM IR input: Instruction does not dominate all uses!
              %w = add i32 %y, 1
              %z = add i32 %w, 1

            1 error generated.
            """;

        var fault = IrFault.FromVerifier(output, Broken);

        Assert.Equal("_SL4Test5Twice", fault.Function);
        Assert.StartsWith("Instruction does not dominate all uses!", fault.Message);
        Assert.DoesNotContain("generated", fault.Message);
        Assert.True(IrFault.RejectedByClang(output));
    }

    /// <summary>
    /// A module that does not parse never reaches the verifier, and the parser
    /// names a line rather than an instruction.
    /// </summary>
    [Fact]
    public void AParseErrorIsPlacedByItsLine()
    {
        const string output = """
            obj\app.ll:11:18: error: use of undefined value '%w'
               11 |   %z = add i32 %w, 1
                  |                ^
            1 error generated.
            """;

        var fault = IrFault.FromVerifier(output, Broken);

        Assert.True(IrFault.RejectedByClang(output));
        Assert.Equal("_SL4Test5Twice", fault.Function);
        Assert.Equal("use of undefined value '%w' (line 11 of the module)\n  %z = add i32 %w, 1", fault.Message);
    }

    [Fact]
    public void AFunctionTheVerifierNamesIsTakenAsNamed()
    {
        const string output = """
            Attribute 'sret' applied to incompatible type!
            ptr @"_SL4Test5Twice"
            /usr/lib/llvm-21/bin/opt: <stdin>: error: input module is broken!
            """;

        var fault = IrFault.FromVerifier(output, Broken);

        Assert.Equal("_SL4Test5Twice", fault.Function);
        Assert.DoesNotContain("input module is broken", fault.Message);
    }

    [Fact]
    public void TheExplanationBlamesTheCompiler()
    {
        var fault = new IrFault("Instruction does not dominate all uses!", "_SL4Test5Twice");

        string explained = fault.Explain("obj/app.ll");

        Assert.StartsWith("internal compiler error:", explained);
        Assert.Contains("'_SL4Test5Twice'", explained);
        Assert.Contains("obj/app.ll", explained);
        Assert.Contains("compiler bug", explained);
    }
}
