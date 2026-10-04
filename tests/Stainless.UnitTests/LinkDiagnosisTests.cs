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
/// What a link failure is explained as. The explanation decides where the
/// reader goes looking, so the one thing it must not do is name a cause the
/// program does not have: a Stainless function missing because its library was
/// not linked was once blamed on an <c>extern "C"</c> nobody had written.
/// </summary>
public class LinkDiagnosisTests
{
    private const string MissingStainless =
        "lld-link: error: undefined symbol: _SL3Lib5TotalS15Standard_int___Ei\n" +
        ">>> referenced by app.o:(main)";

    private const string MissingC =
        "lld-link: error: undefined symbol: sqlite3_open\n>>> referenced by app.o:(main)";

    [Fact]
    public void AStainlessNameIsNotCalledExternC()
    {
        string text = LinkDiagnosis.Explain(MissingStainless, "app.ll");

        Assert.DoesNotContain("extern \"C\"", text);
        Assert.Contains("Stainless", text);
        Assert.DoesNotContain("compiler bug", text);
    }

    [Fact]
    public void AReferenceWithNoLibraryBesideItIsNamed()
    {
        string text = LinkDiagnosis.Explain(MissingStainless, "app.ll", ["Lib.dll"]);

        Assert.Contains("'Lib.dll'", text);
        Assert.DoesNotContain("extern \"C\"", text);
    }

    [Fact]
    public void ACNameStillIsExternC()
    {
        string text = LinkDiagnosis.Explain(MissingC, "app.ll");

        Assert.Contains("extern \"C\"", text);
        Assert.DoesNotContain("'_SL'", text);
    }

    /// <summary>
    /// A C input is compiled in the same clang run as the IR, so its compile
    /// error arrives where the toolchain's objections to the IR do, and it is
    /// the C file's author who has to fix it.
    /// </summary>
    [Theory]
    [InlineData("/home/me/case/loaded.c:29:10: fatal error: 'link.h' file not found\n" +
                "   29 | #include <link.h>\n1 error generated.", "/home/me/case/loaded.c")]
    [InlineData(@"E:\case\shim.cpp:4:1: error: unknown type name 'widget'", @"E:\case\shim.cpp")]
    [InlineData("/tmp/case/probe.m:81:12: error: call to undeclared function 'class_getName'", "/tmp/case/probe.m")]
    [InlineData("In file included from app.c:2:\ninclude/api.h:7:3: error: expected ';'", "include/api.h")]
    public void ACSourceErrorIsTheSourcesNotTheCompilers(string output, string file)
    {
        string text = LinkDiagnosis.Explain(output, "app.ll");

        Assert.StartsWith($"'{file}' did not compile:", text);
        Assert.DoesNotContain("compiler bug", text);
    }

    /// <summary>
    /// A library or framework the program named and the system has not got
    /// is the program's to fix, whichever linker said so.
    /// </summary>
    [Theory]
    [InlineData("ld: framework 'CoreAudioTypes' not found\nclang: error: linker command failed", "the framework 'CoreAudioTypes'")]
    [InlineData("ld: library 'nonesuch' not found", "the library 'nonesuch'")]
    [InlineData("ld: library not found for -lnonesuch", "the library 'nonesuch'")]
    [InlineData("/usr/bin/ld: cannot find -lnonesuch: No such file or directory", "the library 'nonesuch'")]
    [InlineData("lld-link: error: could not open 'nonesuch.lib': no such file or directory", "the library 'nonesuch.lib'")]
    public void AMissingLibraryIsTheProgramsNotTheCompilers(string output, string missing)
    {
        string text = LinkDiagnosis.Explain(output, "app.ll");

        Assert.StartsWith($"the linker could not find {missing}:", text);
        Assert.DoesNotContain("compiler bug", text);
    }

    [Fact]
    public void AnErrorInTheIrIsStillTheCompilers()
    {
        string text = LinkDiagnosis.Explain("obj/app.ll:12:3: error: expected type", "obj/app.ll");

        Assert.Contains("compiler bug", text);
    }

    [Theory]
    // i686 Windows puts the target's own underscore in front of the mangled one.
    [InlineData("lld-link: error: undefined symbol: __SL3Lib5TotalS15Standard_int___Ei")]
    [InlineData("app.c:(.text+0x1c): undefined reference to `_SL3Lib5TotalS15Standard_int___Ei'")]
    [InlineData("error LNK2019: unresolved external symbol _SL3Lib5TotalS15Standard_int___Ei referenced in function main")]
    public void EveryLinkerSpellingIsRead(string output) =>
        Assert.DoesNotContain("extern \"C\"", LinkDiagnosis.Explain(output, "app.ll"));

    /// <summary>
    /// ld64 quotes the Mach-O symbol, which carries an underscore the source
    /// never wrote. Taken off, a Stainless name is still one and a C name is
    /// the one declared.
    /// </summary>
    [Fact]
    public void Ld64IsReadWithoutTheMachOUnderscore()
    {
        const string output =
            "Undefined symbols for architecture arm64:\n" +
            "  \"__SL3Lib5TotalS15Standard_int___Ei\", referenced from:\n" +
            "      _main in app-5c1a2e.o\n" +
            "ld: symbol(s) not found for architecture arm64\n" +
            "clang: error: linker command failed with exit code 1 (use -v to see invocation)";

        string text = LinkDiagnosis.Explain(output, "app.ll");

        Assert.Contains("'_SL'", text);
        Assert.DoesNotContain("extern \"C\"", text);
        Assert.DoesNotContain("compiler bug", text);

        string c = LinkDiagnosis.Explain(
            "Undefined symbols for architecture arm64:\n" +
            "  \"_sqlite3_open\", referenced from:\n" +
            "      _main in app-5c1a2e.o\n", "app.ll");

        Assert.Contains("extern \"C\"", c);
        Assert.DoesNotContain("'_SL'", c);
    }

    [Fact]
    public void BothAreExplainedWhenBothAreMissing()
    {
        string text = LinkDiagnosis.Explain(MissingStainless + "\n" + MissingC, "app.ll");

        Assert.Contains("extern \"C\"", text);
        Assert.Contains("'_SL'", text);
    }

    [Fact]
    public void AnythingElseIsStillTheCompilers()
    {
        string text = LinkDiagnosis.Explain("error: invalid IR", "app.ll");
        Assert.Contains("compiler bug", text);
    }

    // ---------------------------------------------------------- the assembler

    /// <summary>A block whose braces start at the given offset of the source.</summary>
    private static Binding.BoundAsm Block(Source.SourceText file, int brace)
    {
        int end = file.Text.IndexOf('}', brace) + 1;
        var span = new Source.SourceSpan(file, brace, end);
        return new Binding.BoundAsm(span, file.Text[(brace + 1)..(end - 1)], span, [], []);
    }

    /// <summary>
    /// LLVM numbers the lines of what it was given and does not say which block
    /// it was. On x86 the text after the brace is its second line, and the line
    /// it echoes is what finds the block among several.
    /// </summary>
    [Fact]
    public void AnAssemblerErrorGoesBackToItsLine()
    {
        const string source = "asm {\n    nop\n}\nasm {\n    mov rax, 1\n    bogus rax\n}";
        var file = Front.Text(source);
        var blocks = new[] { Block(file, source.IndexOf('{')), Block(file, source.LastIndexOf('{')) };

        const string output =
            "<inline asm>:4:5: error: invalid instruction mnemonic 'bogus'\n" +
            "    bogus rax\n" +
            "    ^~~~~\n" +
            "error: cannot compile inline asm\n";

        Assert.True(AssemblerDiagnosis.Rejected(output));

        var diagnostics = new Source.DiagnosticBag();
        AssemblerDiagnosis.Report(output, blocks, Binding.TargetPlatform.X64Windows, diagnostics);

        var diagnostic = Assert.Single(diagnostics.Items);
        Assert.Equal("SL0723", diagnostic.Code);
        Assert.Equal("bogus rax", Front.Underlined(source, diagnostic));
        Assert.Contains("invalid instruction mnemonic 'bogus'", diagnostic.Message);
    }

    /// <summary>ARM has one syntax, so nothing comes before the block's own first line.</summary>
    [Fact]
    public void AnArm64AssemblerErrorIsNotOffset()
    {
        const string source = "asm { add x0, x0, #1\nbad x0 }";
        var file = Front.Text(source);

        const string output = "<inline asm>:2:1: error: unrecognized instruction mnemonic\nbad x0 \n^\n";

        var diagnostics = new Source.DiagnosticBag();
        AssemblerDiagnosis.Report(
            output, [Block(file, source.IndexOf('{'))], Binding.TargetPlatform.Arm64Linux, diagnostics);

        Assert.Equal("bad x0", Front.Underlined(source, Assert.Single(diagnostics.Items)));
    }

    /// <summary>
    /// An error with no line to put it on still belongs to the program rather
    /// than to the compiler, so it is reported against a block in LLVM's words.
    /// </summary>
    [Fact]
    public void AnAssemblerErrorWithNoLineIsStillTheProgramsOwn()
    {
        const string source = "asm { jmp nowhere }";
        var file = Front.Text(source);
        const string output = "<unknown>:0: error: assembler label 'nowhere' can not be undefined\n" +
                              "error: cannot compile inline asm\n";

        var diagnostics = new Source.DiagnosticBag();
        AssemblerDiagnosis.Report(
            output, [Block(file, source.IndexOf('{'))], Binding.TargetPlatform.X64Linux, diagnostics);

        var diagnostic = Assert.Single(diagnostics.Items);
        Assert.Equal("SL0723", diagnostic.Code);
        Assert.Contains("can not be undefined", diagnostic.Message);
    }
}
