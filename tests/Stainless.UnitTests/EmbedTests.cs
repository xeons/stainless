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
using Stainless.Driver;
using Stainless.Emit;
using Stainless.Source;
using Stainless.Syntax;
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// <c>embed</c>: the rules the binder holds an embed to, and the assembly it
/// becomes on each target.
///
/// The end-to-end cases prove that the object links and reads back on the
/// machines here. These ask what no program's output shows — which section a
/// default lands in, what the flags are spelled as on a target nothing here
/// runs, and which of two nearly identical embeds is refused and why.
/// </summary>
public class EmbedTests
{
    /// <summary>
    /// A directory holding a source file and the files it embeds. The source
    /// on disk is empty: the binder is handed the text, and asks of the file
    /// only that it exists, which is what gives it a directory at all.
    /// </summary>
    private sealed class Scratch
    {
        public string Directory { get; } = Path.Combine(
            Path.GetTempPath(), "stainless-embed", Path.GetRandomFileName());

        public Scratch()
        {
            System.IO.Directory.CreateDirectory(System.IO.Path.Combine(Directory, "data"));
            File.WriteAllBytes(SourcePath, []);
            File.WriteAllBytes(Path.Combine(Directory, "data", "table.bin"), [1, 2, 0, 255]);
            File.WriteAllBytes(Path.Combine(Directory, "stub.bin"), [0xB8, 42, 0, 0, 0, 0xC3]);
        }

        public string SourcePath => Path.Combine(Directory, "probe.sl");

        public BoundProgram Bind(string body, out DiagnosticBag diagnostics) =>
            Front.BindAt(SourcePath, "module Test;\n" + body, out diagnostics);

        /// <summary>The codes reported about this source, and not the library's.</summary>
        public string[] Codes(string body)
        {
            Bind(body, out var diagnostics);
            return diagnostics.Items
                .Where(d => d.Span.File?.Path == SourcePath)
                .Select(d => d.Code)
                .ToArray();
        }
    }

    private static void Under(TargetPlatform target, Action body)
    {
        var before = TargetPlatform.Current;
        TargetPlatform.Current = target;
        try
        {
            body();
        }
        finally
        {
            TargetPlatform.Current = before;
        }
    }

    // ------------------------------------------------------------- syntax

    [Fact]
    public void EmbedIsAKeyword() =>
        Assert.Equal([TokenKind.EmbedKeyword], Front.Kinds("embed"));

    [Fact]
    public void TheArgumentsAreKeptAsWrittenNamedOnesIncluded()
    {
        var embedded = Assert.IsType<EmbedSyntax>(
            Front.Expression("""embed("stub.bin", section: ".stub", access: "rx")"""));

        Assert.Equal(3, embedded.Arguments.Count);
        Assert.IsType<LiteralSyntax>(embedded.Arguments[0]);
        Assert.Equal("section", Assert.IsType<NamedArgumentSyntax>(embedded.Arguments[1]).Name);
        Assert.Equal("access", Assert.IsType<NamedArgumentSyntax>(embedded.Arguments[2]).Name);
    }

    // ------------------------------------------------------------- access

    [Theory]
    [InlineData("r", EmbedAccess.Read)]
    [InlineData("rw", EmbedAccess.Read | EmbedAccess.Write)]
    [InlineData("wr", EmbedAccess.Read | EmbedAccess.Write)]
    [InlineData("xr", EmbedAccess.Read | EmbedAccess.Execute)]
    [InlineData("xwr", EmbedAccess.Read | EmbedAccess.Write | EmbedAccess.Execute)]
    public void AccessIsLettersInAnyOrder(string written, EmbedAccess expected) =>
        Assert.Equal(expected, EmbeddedFile.ParseAccess(written));

    [Theory]
    [InlineData("")]
    [InlineData("w")]
    [InlineData("wx")]
    [InlineData("rr")]
    [InlineData("rwr")]
    [InlineData("R")]
    [InlineData("r ")]
    public void AccessWithoutReadOrWithARepeatIsNotOne(string written) =>
        Assert.Null(EmbeddedFile.ParseAccess(written));

    // ------------------------------------------------------------ binding

    [Fact]
    public void AnEmbedIsAByteArray()
    {
        var scratch = new Scratch();
        var program = scratch.Bind(
            """public nuint Length() { byte[] table = embed("data/table.bin"); return table.Length; }""",
            out var diagnostics);

        Assert.False(diagnostics.HasErrors);
        var file = Assert.Single(program.Embeds);
        Assert.Equal(4, file.Length);
        Assert.Equal(Path.Combine(scratch.Directory, "data", "table.bin"), file.Path);
    }

    /// <summary>
    /// The same file, section and access is one object, and changing any of
    /// the three is another.
    /// </summary>
    [Fact]
    public void IdenticalEmbedsAreOneObject()
    {
        var scratch = new Scratch();
        var program = scratch.Bind("""
            public void F()
            {
                var a = embed("data/table.bin");
                var b = embed("data/../data/table.bin");
                var c = embed("data/table.bin", access: "rw");
                var d = embed("data/table.bin", section: ".mine");
            }
            """, out var diagnostics);

        Assert.False(diagnostics.HasErrors);
        Assert.Equal(3, program.Embeds.Count);
    }

    /// <summary>
    /// What makes a static legal in a <c>--shared</c> library, and what lets the
    /// emitter write the address on the global rather than run code for it.
    /// </summary>
    [Fact]
    public void AStaticHoldingAnEmbedHasAConstantInitializer()
    {
        var scratch = new Scratch();
        var program = scratch.Bind(
            """public static class Held { public static readonly byte[] Table = embed("data/table.bin"); }""",
            out var diagnostics);

        Assert.False(diagnostics.HasErrors);
        Assert.True(program.Statics.Single(s => s.Name == "Table").HasConstantInitializer);
    }

    [Fact]
    public void AnAbsolutePathIsTakenAsItIs()
    {
        var scratch = new Scratch();
        string absolute = Path.Combine(scratch.Directory, "stub.bin").Replace('\\', '/');

        Assert.Empty(scratch.Codes($$"""public void F() { var s = embed("{{absolute}}"); }"""));
    }

    /// <summary>
    /// A source with no file behind it has no directory, and a relative path
    /// is refused rather than resolved against wherever the compiler happens
    /// to be running.
    /// </summary>
    [Fact]
    public void ARelativePathNeedsASourceOnDisk()
    {
        var diagnostic = Front.Only(Diagnostics("""public void F() { var s = embed("stub.bin"); }"""));

        Assert.Equal("SL0705", diagnostic.Code);
    }

    private static DiagnosticBag Diagnostics(string body)
    {
        Front.BindModule(body, out var diagnostics);
        return diagnostics;
    }

    [Theory]
    [InlineData("""embed()""", "SL0703")]
    [InlineData("""embed("stub.bin", "stub.bin")""", "SL0703")]
    [InlineData("""embed("stub.bin", align: "8")""", "SL0703")]
    [InlineData("""embed("stub.bin", access: "r", access: "r")""", "SL0703")]
    [InlineData("""embed(Path)""", "SL0704")]
    [InlineData("""embed("stub.bin", access: Path)""", "SL0704")]
    [InlineData("""embed("missing.bin")""", "SL0706")]
    [InlineData("""embed("data")""", "SL0706")]
    [InlineData("""embed("")""", "SL0706")]
    [InlineData("""embed("stub.bin", access: "x")""", "SL0707")]
    [InlineData("""embed("stub.bin", access: "rwx")""", "SL0708")]
    [InlineData("""embed("stub.bin", section: ".a b")""", "SL0709")]
    [InlineData("""embed("stub.bin", section: ".a\tb")""", "SL0709")]
    [InlineData("""embed("stub.bin", section: "")""", "SL0709")]
    [InlineData("""embed("stub.bin", section: ".text")""", "SL0711")]
    [InlineData("""embed("stub.bin", section: ".data")""", "SL0711")]
    [InlineData("""embed("stub.bin", section: ".bss")""", "SL0711")]
    public void EachRuleHasItsCode(string expression, string code)
    {
        var scratch = new Scratch();

        Assert.Equal([code], scratch.Codes(
            $"static readonly String Path = \"stub.bin\";\npublic void F() {{ var s = {expression}; }}"));
    }

    [Fact]
    public void WritableAndExecutableIsAllowedWhenTheSectionIsNamed()
    {
        var scratch = new Scratch();

        Assert.Empty(scratch.Codes(
            """public void F() { var s = embed("stub.bin", section: ".jit", access: "rwx"); }"""));
    }

    [Fact]
    public void ASectionTheTargetDefinesTakesItsOwnAccess()
    {
        var scratch = new Scratch();

        Assert.Empty(scratch.Codes(
            """public void F() { var s = embed("stub.bin", section: ".text", access: "rx"); }"""));
    }

    [Fact]
    public void TwoEmbedsCannotGiveOneSectionTwoAccesses()
    {
        var scratch = new Scratch();
        var codes = scratch.Codes("""
            public void F()
            {
                var a = embed("stub.bin", section: ".shared");
                var b = embed("data/table.bin", section: ".shared");
                var c = embed("stub.bin", section: ".shared", access: "rw");
            }
            """);

        Assert.Equal(["SL0711"], codes);
    }

    /// <summary>
    /// The names each format already owns are its own: `.rdata` is a section
    /// Windows defines and ELF does not, and the other way about for `.rodata`.
    /// </summary>
    [Fact]
    public void WhichSectionsAreDecidedDependsOnTheObjectFormat()
    {
        Assert.Equal(EmbedAccess.Read,
            EmbeddedFile.KnownSectionAccess(".rdata", TargetPlatform.X64Windows));
        Assert.Null(EmbeddedFile.KnownSectionAccess(".rdata", TargetPlatform.X64Linux));
        Assert.Equal(EmbedAccess.Read,
            EmbeddedFile.KnownSectionAccess(".rodata.logo", TargetPlatform.Arm64Linux));
        Assert.Equal(EmbedAccess.Read | EmbedAccess.Execute,
            EmbeddedFile.KnownSectionAccess(".text$stub", TargetPlatform.X86Windows));
        Assert.Null(EmbeddedFile.KnownSectionAccess(".textual", TargetPlatform.X64Linux));
        Assert.Null(EmbeddedFile.KnownSectionAccess(".stub", TargetPlatform.X64Windows));
    }

    /// <summary>
    /// Eight bytes is a PE image's limit, so only a Windows target warns — and
    /// it is a warning, because the bytes still arrive.
    /// </summary>
    [Fact]
    public void ALongSectionNameWarnsOnlyWhereItWillBeCut()
    {
        var scratch = new Scratch();
        const string body =
            """public void F() { var s = embed("stub.bin", section: ".embedded_logo"); }""";

        Under(TargetPlatform.X64Windows, () =>
        {
            scratch.Bind(body, out var diagnostics);
            var warning = Assert.Single(diagnostics.Items, d => d.Code == "SL0710");
            Assert.Equal(Severity.Warning, warning.Severity);
            Assert.Contains("'.embedde'", warning.Message);
        });

        Under(TargetPlatform.X64Linux, () => Assert.Empty(scratch.Codes(body)));
        Under(TargetPlatform.X64Windows, () =>
            Assert.Empty(scratch.Codes(
                """public void F() { var s = embed("stub.bin", section: ".embedde"); }""")));
    }

    [Fact]
    public void TheDefaultSectionFollowsTheAccessAndTheFormat()
    {
        Assert.Equal(".rdata", EmbeddedFile.DefaultSection(EmbedAccess.Read, TargetPlatform.X86Windows));
        Assert.Equal(".rodata", EmbeddedFile.DefaultSection(EmbedAccess.Read, TargetPlatform.X86Linux));
        Assert.Equal(".data", EmbeddedFile.DefaultSection(
            EmbedAccess.Read | EmbedAccess.Write, TargetPlatform.Arm64Windows));
        Assert.Equal(".text", EmbeddedFile.DefaultSection(
            EmbedAccess.Read | EmbedAccess.Execute, TargetPlatform.Arm64Linux));
        Assert.Null(EmbeddedFile.DefaultSection(
            EmbedAccess.Read | EmbedAccess.Write | EmbedAccess.Execute, TargetPlatform.X64Linux));
    }

    // ------------------------------------------------------------ emitting

    private static EmbeddedFile File_(string section, EmbedAccess access, long length = 6) =>
        new(0, "/data/with \"quotes\"/stub.bin", section, access, length);

    [Theory]
    [InlineData("x64-windows", ".section \".rdata\",\"dr\"")]
    [InlineData("x86-windows", ".section \".rdata\",\"dr\"")]
    [InlineData("arm64-windows", ".section \".rdata\",\"dr\"")]
    [InlineData("x64-linux", ".section \".rodata\",\"a\",%progbits")]
    [InlineData("x86-linux", ".section \".rodata\",\"a\",%progbits")]
    [InlineData("arm64-linux", ".section \".rodata\",\"a\",%progbits")]
    public void ReadOnlyDataIsTheFormatsOwnSection(string target, string directive)
    {
        var platform = TargetPlatform.Parse(target)!;
        var file = File_(EmbeddedFile.DefaultSection(EmbedAccess.Read, platform)!, EmbedAccess.Read);

        Assert.Equal(directive, file.SectionDirective(platform));
    }

    [Theory]
    [InlineData(EmbedAccess.Read | EmbedAccess.Write, "\"dw\"", "\"aw\",%progbits")]
    [InlineData(EmbedAccess.Read | EmbedAccess.Execute, "\"xr\"", "\"ax\",%progbits")]
    [InlineData(EmbedAccess.Read | EmbedAccess.Write | EmbedAccess.Execute, "\"xw\"", "\"awx\",%progbits")]
    public void TheFlagsAreSpelledPerFormat(EmbedAccess access, string coff, string elf)
    {
        var file = File_(".stub", access);

        Assert.Equal(".section \".stub\"," + coff, file.SectionDirective(TargetPlatform.X64Windows));
        Assert.Equal(".section \".stub\"," + elf, file.SectionDirective(TargetPlatform.Arm64Linux));
    }

    /// <summary>
    /// Four words, each pointer-sized: two immortal counts, a zero where the
    /// type would be, and the length — then the file, held to that length.
    /// </summary>
    [Fact]
    public void TheObjectIsAHeaderThenTheFile()
    {
        var file = File_(".rdata", EmbedAccess.Read);

        Assert.Equal(
            [
                ".section \".rdata\",\"dr\"",
                ".p2align 3",
                "_SLembed0:",
                ".quad -1",
                ".quad -1",
                ".quad 0",
                ".quad 6",
                ".incbin \"/data/with \\\"quotes\\\"/stub.bin\",0,6",
                ".text",
            ],
            file.Assembly(TargetPlatform.X64Windows));

        Assert.Equal(
            [
                ".section \".rdata\",\"dr\"",
                ".p2align 2",
                "_SLembed0:",
                ".long -1",
                ".long -1",
                ".long 0",
                ".long 6",
                ".incbin \"/data/with \\\"quotes\\\"/stub.bin\",0,6",
                ".text",
            ],
            file.Assembly(TargetPlatform.X86Windows));
    }

    [Fact]
    public void AnEmptyFileIsAHeaderAlone() =>
        Assert.DoesNotContain(
            File_(".rodata", EmbedAccess.Read, length: 0).Assembly(TargetPlatform.X64Linux),
            line => line.StartsWith(".incbin", StringComparison.Ordinal));

    [Fact]
    public void AnAssemblyLineIsEscapedForAnIrString() =>
        Assert.Equal(
            ".incbin \\22C:\\5CD\\C3\\A9j\\C3\\A0/x.bin\\22",
            EmbeddedFile.IrString(".incbin \"C:\\Déjà/x.bin\""));

    /// <summary>
    /// Through the real emitter: the bytes in module assembly, a declaration
    /// that is hidden and not constant, and a static born holding its address
    /// rather than written by an initializer.
    /// </summary>
    [Fact]
    public void TheModuleCarriesTheObjectAndTheStaticHoldsIt()
    {
        var scratch = new Scratch();

        Under(TargetPlatform.X64Linux, () =>
        {
            var program = scratch.Bind(
                """public static class Held { public static readonly byte[] Stub = embed("stub.bin", section: ".stub", access: "rx"); }""",
                out var diagnostics);
            Assert.False(diagnostics.HasErrors);

            string ir = new LlvmEmitter(forSharedLibrary: true).Emit(program).ReplaceLineEndings("\n");

            Assert.Contains("module asm \".section \\22.stub\\22,\\22ax\\22,%progbits\"\n", ir);
            Assert.Contains("module asm \"_SLembed0:\"\n", ir);
            Assert.Contains(
                "@\"\\01_SLembed0\" = external hidden global { i64, i64, ptr, i64, [6 x i8] }, align 8",
                ir);
            Assert.Contains(
                "@_SLstatic_Test_Held_Stub = internal global ptr @\"\\01_SLembed0\", align 8", ir);
            Assert.DoesNotContain("store ptr @\"\\01_SLembed0\", ptr @_SLstatic_Test_Held_Stub", ir);
        });
    }
}

/// <summary>
/// The build stamp's half of <c>embed</c>: a dependency is rebuilt when a file
/// it embeds changes, wherever that file is.
/// </summary>
public class EmbeddedStampTests
{
    private static string Temp()
    {
        string directory = Path.Combine(
            Path.GetTempPath(), "stainless-stamp", Path.GetRandomFileName());

        Directory.CreateDirectory(directory);
        return directory;
    }

    [Fact]
    public void AnUntouchedFileIsUnchanged()
    {
        string file = Path.Combine(Temp(), "logo.bin");
        File.WriteAllBytes(file, [1, 2, 3]);

        var stamp = new BuildStamp { Inputs = "a", AbiDigest = "b", Embedded = BuildStamp.Digests([file]) };

        Assert.True(stamp.EmbeddedFilesAreUnchanged());
    }

    [Fact]
    public void AnEditedFileIsNot()
    {
        string file = Path.Combine(Temp(), "logo.bin");
        File.WriteAllBytes(file, [1, 2, 3]);
        var stamp = new BuildStamp { Inputs = "a", AbiDigest = "b", Embedded = BuildStamp.Digests([file]) };

        File.WriteAllBytes(file, [1, 2, 4]);

        Assert.False(stamp.EmbeddedFilesAreUnchanged());
    }

    [Fact]
    public void ADeletedFileIsNot()
    {
        string file = Path.Combine(Temp(), "logo.bin");
        File.WriteAllBytes(file, [1, 2, 3]);
        var stamp = new BuildStamp { Inputs = "a", AbiDigest = "b", Embedded = BuildStamp.Digests([file]) };

        File.Delete(file);

        Assert.False(stamp.EmbeddedFilesAreUnchanged());
    }

    /// <summary>
    /// The list survives being written and read back, which is the only way
    /// the next build ever sees it.
    /// </summary>
    [Fact]
    public void TheFilesAreKeptInTheStamp()
    {
        string directory = Temp();
        string file = Path.Combine(directory, "logo.bin");
        File.WriteAllBytes(file, [9]);

        string path = Path.Combine(directory, BuildStamp.FileName);
        new BuildStamp { Inputs = "a", AbiDigest = "b", Embedded = BuildStamp.Digests([file, file]) }
            .Write(path);

        var read = BuildStamp.Read(path);

        Assert.NotNull(read);
        var only = Assert.Single(read.Embedded);
        Assert.Equal(file, only.Path);
        Assert.True(read.EmbeddedFilesAreUnchanged());

        File.WriteAllBytes(file, [10]);
        Assert.False(read.EmbeddedFilesAreUnchanged());
    }
}
