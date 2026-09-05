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
using Stainless.Driver;
using Stainless.Emit;
using Stainless.Source;
using Stainless.Syntax;

namespace Stainless.UnitTests;

/// <summary>
/// Drives the compiler's front end on a string, with no disk and no clang.
///
/// The end-to-end suite compiles, links and runs a program, which proves the
/// whole pipeline and takes a fifth of a second per case. These tests ask
/// smaller questions -- what did the lexer make of this, where exactly does
/// this error point -- and answering one takes a millisecond, so they can be
/// asked by the hundred.
/// </summary>
public static class Front
{
    /// <summary>What <c>#if</c> sees, matching what the driver would pass.</summary>
    private static readonly HashSet<string> Symbols = Compilation.PlatformSymbols([]);

    /// <summary>The path a test's own source is given, to tell it from the library's.</summary>
    public const string TestFile = "<test>";

    /// <summary>
    /// The standard library, parsed once.
    ///
    /// Every binder test needs it -- <c>String</c> and <c>int.ToString()</c>
    /// come from there -- and it is thirty files. Sharing the trees is safe
    /// because the syntax is immutable: a binder reads it and builds its own
    /// symbols, so two binders over the same trees cannot see each other.
    /// </summary>
    private static readonly Lazy<IReadOnlyList<CompilationUnitSyntax>> Library = new(() =>
    {
        var diagnostics = new DiagnosticBag();
        var units = StandardLibrary.Sources()
            .Select(s => new Parser(new SourceText(s.Name, s.Text), diagnostics, Symbols)
                .ParseCompilationUnit())
            .ToList();

        // A standard library that does not parse would fail every test below
        // with something unrelated to what the test is about.
        if (diagnostics.HasErrors)
            throw new InvalidOperationException(
                "the standard library does not parse: " +
                string.Join("; ", diagnostics.Items.Select(d => d.Code + " " + d.Message)));

        return units;
    });

    public static SourceText Text(string source) => new(TestFile, source);

    // ---------------------------------------------------------------- lexing

    public static IReadOnlyList<Token> Tokens(string source) => Tokens(source, out _);

    public static IReadOnlyList<Token> Tokens(string source, out DiagnosticBag diagnostics)
    {
        diagnostics = new DiagnosticBag();
        return new Lexer(Text(source), diagnostics, Symbols).Tokenize();
    }

    /// <summary>Token kinds with the trailing end-of-file dropped.</summary>
    public static TokenKind[] Kinds(string source) =>
        Tokens(source).Select(t => t.Kind).Where(k => k != TokenKind.EndOfFile).ToArray();

    /// <summary>The decoded value of a source that is one literal.</summary>
    public static object? Value(string source) => Tokens(source)[0].Value;

    // --------------------------------------------------------------- parsing

    public static CompilationUnitSyntax Parse(string source) => Parse(source, out _);

    public static CompilationUnitSyntax Parse(string source, out DiagnosticBag diagnostics)
    {
        diagnostics = new DiagnosticBag();
        return new Parser(Text(source), diagnostics, Symbols).ParseCompilationUnit();
    }

    /// <summary>Parses one expression, as an expression rather than as a file.</summary>
    public static ExpressionSyntax Expression(string source) => Expression(source, out _);

    public static ExpressionSyntax Expression(string source, out DiagnosticBag diagnostics)
    {
        diagnostics = new DiagnosticBag();
        return new Parser(Text(source), diagnostics, Symbols).ParseExpression();
    }

    // --------------------------------------------------------------- binding

    /// <summary>
    /// Binds a whole file against the standard library. The source is taken as
    /// written, so it must carry its own <c>module</c> line.
    /// </summary>
    public static BoundProgram Bind(string source, out DiagnosticBag diagnostics,
                                    CppAbi? abi = null, bool shared = false)
    {
        diagnostics = new DiagnosticBag();
        var unit = new Parser(Text(source), diagnostics, Symbols).ParseCompilationUnit();
        var units = Library.Value.Append(unit).ToList();

        return new Binder(diagnostics, requireEntryPoint: !shared, cppAbi: abi).Bind(units);
    }

    /// <summary>
    /// Binds a module body: the <c>module</c> line is supplied, so a test can be
    /// one declaration long.
    /// </summary>
    public static BoundProgram BindModule(string body, out DiagnosticBag diagnostics,
                                          CppAbi? abi = null) =>
        Bind("module Test;\n" + body, out diagnostics, abi, shared: true);

    /// <summary>Binds a function body, for a test that is one statement long.</summary>
    public static BoundProgram BindBody(string body, out DiagnosticBag diagnostics,
                                        CppAbi? abi = null) =>
        BindModule("int Main()\n{\n" + body + "\n    return 0;\n}", out diagnostics, abi);

    // ----------------------------------------------------------------- codes

    /// <summary>
    /// The codes reported about the test's own source.
    ///
    /// The library's own diagnostics are filtered out: a warning about
    /// something in the standard library is not what any of these tests is
    /// asking about, and would show up in every one of them at once.
    /// </summary>
    public static string[] Codes(DiagnosticBag diagnostics) => diagnostics.Items
        .Where(d => d.Span.File is null || d.Span.File.Path == TestFile)
        .Select(d => d.Code)
        .ToArray();

    /// <summary>The codes a module body reports.</summary>
    public static string[] ModuleCodes(string body)
    {
        BindModule(body, out var diagnostics);
        return Codes(diagnostics);
    }

    /// <summary>The codes a function body reports.</summary>
    public static string[] BodyCodes(string body)
    {
        BindBody(body, out var diagnostics);
        return Codes(diagnostics);
    }

    /// <summary>
    /// The one diagnostic a snippet reported, or a failure naming what it
    /// reported instead. Tests that assert a span need the diagnostic itself.
    /// </summary>
    public static Diagnostic Only(DiagnosticBag diagnostics)
    {
        var mine = diagnostics.Items.Where(d => d.Span.File?.Path == TestFile).ToList();
        if (mine.Count == 1) return mine[0];

        throw new InvalidOperationException(
            mine.Count == 0
                ? "no diagnostic was reported about the test's own source"
                : "expected one diagnostic, got " +
                  string.Join(", ", mine.Select(d => $"{d.Code} at {d.Span.Start}")));
    }

    // --------------------------------------------------------------- symbols

    /// <summary>
    /// The struct a module body declares, by name.
    ///
    /// Building a <c>StructTypeSymbol</c> by hand would mean laying it out by
    /// hand, and a layout the compiler did not compute is not the one an ABI
    /// test is asking about.
    /// </summary>
    public static StructTypeSymbol Struct(string declarations, string name)
    {
        var program = BindModule(declarations, out var diagnostics);

        if (diagnostics.HasErrors)
            throw new InvalidOperationException(
                "the declarations did not bind: " + string.Join("; ", diagnostics.Items
                    .Where(d => d.Severity == Severity.Error)
                    .Select(d => d.Code + " " + d.Message)));

        return program.Structs.FirstOrDefault(s => s.Name == name)
            ?? throw new InvalidOperationException($"no struct named '{name}' was declared");
    }

    /// <summary>The source a diagnostic's span covers, which is what it underlines.</summary>
    public static string Underlined(string source, Diagnostic diagnostic) =>
        source[diagnostic.Span.Start..diagnostic.Span.End];

    // -------------------------------------------------------------- emitting

    /// <summary>Binds and emits a module body, which needs no entry point.</summary>
    public static string ModuleIr(string body, CppAbi abi = CppAbi.Microsoft)
    {
        var program = Bind("module Test;\n" + body, out var diagnostics, abi, shared: true);

        if (diagnostics.HasErrors)
            throw new InvalidOperationException(
                "the source did not bind: " + string.Join("; ", diagnostics.Items
                    .Where(d => d.Severity == Severity.Error)
                    .Select(d => d.Code + " " + d.Message)));

        // Normalised, because the emitter builds its text with AppendLine and so
        // writes CRLF on Windows and LF everywhere else. A test that asserted on
        // a line would otherwise pass on one platform and fail on the other for
        // a reason that has nothing to do with what it is testing.
        return new LlvmEmitter(forSharedLibrary: true, abi: abi)
            .Emit(program)
            .ReplaceLineEndings("\n");
    }

    /// <summary>
    /// One function of the test's own module, by its Stainless name.
    ///
    /// The prefix is built rather than matched loosely because the standard
    /// library is in the same module text: searching for <c>1D</c> finds a
    /// function of the same shape in <c>Standard.Directory</c> long before it
    /// finds the one the test wrote.
    /// </summary>
    public static string TestFunction(string ir, string name) =>
        Function(ir, $"@_SL4Test{name.Length}{name}");

    /// <summary>
    /// One function's IR, from its <c>define</c> to the brace that closes it.
    /// Found by a fragment of the mangled name, since the mangling is not what
    /// a test about a body is asking.
    /// </summary>
    public static string Function(string ir, string nameFragment)
    {
        string[] lines = ir.ReplaceLineEndings("\n").Split('\n');

        for (int i = 0; i < lines.Length; i++)
        {
            if (!lines[i].StartsWith("define", StringComparison.Ordinal)) continue;
            if (!lines[i].Contains(nameFragment, StringComparison.Ordinal)) continue;

            int end = i;
            while (end < lines.Length && lines[end] != "}") end++;
            return string.Join("\n", lines[i..Math.Min(end + 1, lines.Length)]);
        }

        throw new InvalidOperationException($"no function in the IR is named '{nameFragment}'");
    }
}
