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

namespace Stainless.Fuzz;

/// <summary>
/// What one compilation did: how far it got, what it reported, and -- if it
/// failed in a way a compiler must not -- the exception and its signature.
/// </summary>
internal sealed record Outcome(string Stage, IReadOnlyList<string> Codes, Exception? Failure, string? Signature);

/// <summary>A diagnostic whose span is not a place in its file.</summary>
internal sealed class BadSpanException(Diagnostic diagnostic)
    : Exception($"{diagnostic.Code} has span {diagnostic.Span.Start}..{diagnostic.Span.End} " +
                $"in a file of {diagnostic.Span.File.Text.Length} characters")
{
    public string Code => diagnostic.Code;
}

/// <summary>
/// The driver's pipeline -- parse, bind, emit -- in process.
///
/// It stops where <c>Compilation</c> stops: a program that does not parse is
/// never bound, so a crash in the binder on a tree the parser rejected is not a
/// crash anyone could meet and is not reported.
/// </summary>
internal static class Pipeline
{
    private static readonly HashSet<string> s_symbols = Compilation.PlatformSymbols([]);

    /// <summary>
    /// The standard library, parsed once and shared by every compilation. Safe
    /// for the reason <c>Front</c> in the unit tests gives: a syntax tree is
    /// immutable, and each binder builds its own symbols over it.
    /// </summary>
    private static readonly Dictionary<string, CompilationUnitSyntax> s_library = ParseLibrary();

    private static Dictionary<string, CompilationUnitSyntax> ParseLibrary()
    {
        var diagnostics = new DiagnosticBag();
        return StandardLibrary.Sources().ToDictionary(
            s => Path.GetFileName(s.Name),
            s => new Parser(new SourceText(s.Name, s.Text), diagnostics, s_symbols).ParseCompilationUnit());
    }

    /// <summary>
    /// Compiles the files as one program. A file under a <c>stdlib</c> directory
    /// replaces the standard library file of that name rather than joining it,
    /// so the library's own source can be mutated too.
    /// </summary>
    public static Outcome Run(IReadOnlyList<SourceFile> files)
    {
        string stage = "parse";
        var diagnostics = new DiagnosticBag();
        bool trace = Environment.GetEnvironmentVariable("STAINLESS_FUZZ_TRACE") is not null;

        try
        {
            return Recursion.OnADeepStack(() =>
            {
                var replaced = files
                    .Where(f => f.Path.Replace('\\', '/').Contains("stdlib/"))
                    .Select(f => Path.GetFileName(f.Path))
                    .ToHashSet();

                var units = s_library
                    .Where(l => !replaced.Contains(l.Key))
                    .Select(l => l.Value)
                    .ToList();
                foreach (var file in files)
                    units.Add(new Parser(new SourceText(file.Path, file.Text), diagnostics, s_symbols).ParseCompilationUnit());

                CheckSpans(diagnostics);
                if (diagnostics.HasErrors)
                    return Stopped(stage, diagnostics);

                stage = "bind";
                if (trace)
                    Console.Error.WriteLine(stage);

                bool executable = files.Any(f => f.Text.Contains("Main"));
                var program = new Binder(diagnostics, requireEntryPoint: executable).Bind(units);
                CheckSpans(diagnostics);
                if (diagnostics.HasErrors)
                    return Stopped(stage, diagnostics);

                // What the driver refuses for a library before it emits one.
                bool shared = program.EntryPoint is null;
                if (shared && program.Statics.Any(s => !s.IsImported && !s.HasConstantInitializer))
                    return Stopped(stage, diagnostics);

                stage = "emit";
                if (trace)
                    Console.Error.WriteLine(stage);

                new LlvmEmitter(forSharedLibrary: shared).Emit(program);
                return Stopped("done", diagnostics);
            });
        }
        catch (Exception e)
        {
            return new Outcome(stage, Codes(diagnostics), e, Signature(stage, e));
        }
    }

    private static Outcome Stopped(string stage, DiagnosticBag diagnostics) =>
        new(stage, Codes(diagnostics), null, null);

    private static IReadOnlyList<string> Codes(DiagnosticBag diagnostics) =>
        diagnostics.Items.Select(d => d.Code).Distinct().Order().ToList();

    /// <summary>
    /// A span past the end of its file, or ending before it starts, renders as
    /// a caret under nothing -- or throws in whatever slices the source by it.
    /// </summary>
    private static void CheckSpans(DiagnosticBag diagnostics)
    {
        foreach (var d in diagnostics.Items)
        {
            if (d.Span.File is null)
                continue;
            if (d.Span.Start < 0 || d.Span.End < d.Span.Start || d.Span.End > d.Span.File.Text.Length)
                throw new BadSpanException(d);
        }
    }

    /// <summary>
    /// The stage, the exception type and the innermost three compiler frames,
    /// without line numbers: the same bug reached from two programs has the
    /// same signature, and a finding is recorded once per signature.
    /// </summary>
    public static string Signature(string stage, Exception e)
    {
        while (e is AggregateException { InnerException: not null } or TypeInitializationException { InnerException: not null })
            e = e.InnerException!;

        if (e is BadSpanException bad)
            return $"{stage}: a span outside its file on {bad.Code}";

        return $"{stage}: {e.GetType().Name} in {string.Join(" < ", Frames(e.StackTrace ?? ""))}";
    }

    /// <summary>The compiler's own frames in a .NET stack trace, innermost first.</summary>
    public static IEnumerable<string> Frames(string trace) => trace
        .Split('\n')
        .Select(l => l.Trim())
        .Where(l => l.StartsWith("at Stainless.") &&
                    !l.StartsWith("at Stainless.Fuzz") &&
                    !l.StartsWith("at Stainless.Source.Recursion"))
        .Select(l => l[3..].Split('(')[0])
        .Distinct()
        .Take(3);
}
