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

using System.Diagnostics;
using Stainless.Driver;

namespace Stainless.Tests;

/// <summary>
/// The Stainless end-to-end test runner.
///
/// Each test is a directory under tests/cases containing the .sl (and optionally
/// .c or .cpp) files that make up one program, plus exactly one expectation file:
///
///   expected.txt   the program must compile, run, and print this
///   errors.txt     the program must fail to compile, and every diagnostic code
///                  this file names -- warnings included -- must be reported
///
/// A case may also contain args.txt, one command-line argument per line, and
/// stdin.txt, fed to the program verbatim. Without them a program gets no
/// arguments and an input that is closed at once.
///
/// A case containing warnings.txt must additionally report every code that file
/// names, whether or not the build then fails. It is how a warning is pinned --
/// what a library's metadata leaves out, above all, which is reported where the
/// library is built rather than where a consumer trips over it, and so is not
/// among the diagnostics of the compilation the case is otherwise about.
///
/// A case containing defines.txt is built with each of its lines passed as -D,
/// and one containing abi.txt is built for the ABI that file names.
///
/// A case containing debug.txt is additionally built with debug information, and
/// every line of that file must appear somewhere in the generated IR. Linking at
/// all is most of the test: clang runs LLVM's verifier over the metadata, so a
/// malformed description fails the build rather than producing a quiet lie.
///
/// A case containing ir.txt has every line of that file matched against the
/// generated IR, the same way debug.txt is but without asking for debug
/// information. It is how a signature is pinned: running a program proves the
/// two halves of a call agree with each other, and only the text proves they
/// agree with the C compiler.
///
/// A case containing shared.txt is built as a shared library with a generated
/// header named library.h, and its .c files are then compiled against it. That
/// exercises the export table and the C header rather than just the compiler.
///
/// A case containing sources.txt is compiled together with the paths that file
/// names, each relative to the repository root, and one containing libraries.txt
/// links the libraries it names with -l. Between them they are how a case is
/// written against bindings/ rather than only against the standard library.
///
/// A case containing platform.txt runs only on the platform it names -- windows,
/// linux or macos -- and is reported as skipped elsewhere. Only a case that
/// cannot mean anything on another platform should have one.
///
/// A case containing expected.windows.txt, expected.linux.txt or
/// expected.macos.txt is measured against that instead of expected.txt where it
/// applies. That is for a case whose subject really does differ -- `Path.Join`
/// answers differently because a backslash is a separator on one platform and a
/// filename character on another -- and not for one that merely came out
/// differently and was easier to accept than to explain.
///
/// Testing through the real driver rather than through unit seams means every
/// pass -- lexer, binder, emitter, LLVM and the linker -- is covered by every case.
/// </summary>
internal static class Program
{
    private static int Main(string[] args)
    {
        string root = FindCasesDirectory();
        if (root.Length == 0)
        {
            Console.Error.WriteLine("error: could not locate tests/cases");
            return 2;
        }

        string? filter = args.FirstOrDefault(a => !a.StartsWith('-'));
        bool verbose = args.Contains("-v") || args.Contains("--verbose");

        var cases = Directory.EnumerateDirectories(root)
            .Where(d => filter is null ||
                        Path.GetFileName(d).Contains(filter, StringComparison.OrdinalIgnoreCase))
            .OrderBy(d => d, StringComparer.Ordinal)
            .ToList();

        if (cases.Count == 0)
        {
            Console.Error.WriteLine($"error: no test cases found in {root}");
            return 2;
        }

        string workDirectory = Path.Combine(Path.GetTempPath(), "stainless-tests");
        Directory.CreateDirectory(workDirectory);

        int passed = 0;
        int skipped = 0;
        var failures = new List<(string Name, string Detail)>();
        var stopwatch = Stopwatch.StartNew();

        foreach (string directory in cases)
        {
            string name = Path.GetFileName(directory);

            if (SkipReason(directory) is { } reason)
            {
                skipped++;
                Console.WriteLine($"  \u001b[33mskip\u001b[0m  {name}  ({reason})");
                continue;
            }

            var (ok, detail) = RunCase(directory, workDirectory);

            if (ok)
            {
                passed++;
                Console.WriteLine($"  \u001b[32mpass\u001b[0m  {name}");
                if (verbose && detail.Length > 0) Console.WriteLine(Indent(detail));
            }
            else
            {
                failures.Add((name, detail));
                Console.WriteLine($"  \u001b[31mFAIL\u001b[0m  {name}");
            }
        }

        stopwatch.Stop();
        Console.WriteLine();

        foreach (var (name, detail) in failures)
        {
            Console.WriteLine($"\u001b[31m{name}\u001b[0m");
            Console.WriteLine(Indent(detail));
            Console.WriteLine();
        }

        string summary = failures.Count == 0
            ? $"\u001b[32mall {passed} tests passed\u001b[0m{Skipped(skipped)} in {stopwatch.ElapsedMilliseconds} ms"
            : $"\u001b[31m{failures.Count} failed\u001b[0m, {passed} passed{Skipped(skipped)} in {stopwatch.ElapsedMilliseconds} ms";
        Console.WriteLine(summary);

        return failures.Count == 0 ? 0 : 1;
    }

    /// <summary>Why this case is not being run here, or null when it is.</summary>
    /// <summary>
    /// The expectation to measure against, which may be this platform's.
    ///
    /// A case that tests a platform difference cannot have one expectation.
    /// `Path.Join` really does answer differently on Windows and on Linux --
    /// a backslash is a separator on one and an ordinary character in a
    /// filename on the other -- so `expected.linux.txt` beside `expected.txt`
    /// is the honest way to say so. Neutralising the assertions would delete
    /// the thing being tested.
    /// </summary>
    private static string ExpectedOutputPath(string directory)
    {
        string specific = Path.Combine(directory, $"expected.{ThisPlatform}.txt");
        return File.Exists(specific) ? specific : Path.Combine(directory, "expected.txt");
    }

    /// <summary>What this platform is called in a file name.</summary>
    private static string ThisPlatform =>
        OperatingSystem.IsWindows() ? "windows"
        : OperatingSystem.IsMacOS() ? "macos"
        : OperatingSystem.IsLinux() ? "linux"
        : "unknown";

    private static string? SkipReason(string directory)
    {
        string path = Path.Combine(directory, "platform.txt");
        if (!File.Exists(path)) return null;

        string wanted = File.ReadAllText(path).Trim().ToLowerInvariant();
        bool here = wanted switch
        {
            "windows" => OperatingSystem.IsWindows(),
            "linux" => OperatingSystem.IsLinux(),
            "macos" => OperatingSystem.IsMacOS(),
            var other => throw new InvalidOperationException($"unknown platform '{other}'"),
        };

        return here ? null : $"{wanted} only";
    }

    private static string Skipped(int count) => count == 0 ? "" : $", {count} skipped";

    /// <summary>
    /// A marker file's lines, trimmed, without blanks or # comments. A missing
    /// file is an empty list: every marker read this way is optional.
    /// </summary>
    private static List<string> Lines(string directory, string fileName)
    {
        string path = Path.Combine(directory, fileName);
        if (!File.Exists(path)) return [];

        return [.. File.ReadAllLines(path)
            .Select(line => line.Trim())
            .Where(line => line.Length > 0 && !line.StartsWith('#'))];
    }

    /// <summary>The repository root, which is the directory tests/cases sits under.</summary>
    private static string RepositoryRoot() =>
        Path.GetDirectoryName(Path.GetDirectoryName(FindCasesDirectory()))!;

    private static (bool Ok, string Detail) RunCase(string directory, string workDirectory)
    {
        var sources = Directory.EnumerateFiles(directory, "*.sl")
            .OrderBy(p => p, StringComparer.Ordinal).ToList();
        // C and C++ both, so a case can link against either language.
        var natives = Directory.EnumerateFiles(directory, "*.c")
            .Concat(Directory.EnumerateFiles(directory, "*.cpp"))
            .OrderBy(p => p, StringComparer.Ordinal).ToList();

        if (sources.Count == 0) return (false, "the case directory contains no .sl files");

        string name = Path.GetFileName(directory);

        // Sources from outside the case, named relative to the repository root.
        // This is how a case is written against bindings/, which is not compiled
        // into every program the way the standard library is.
        foreach (string extra in Lines(directory, "sources.txt"))
        {
            string path = Path.Combine(RepositoryRoot(), extra);
            // Recursively, as the CLI searches a directory given on the
            // command line -- bindings/win32 has its raw layer in a subdirectory.
            if (Directory.Exists(path))
                sources.AddRange(Directory
                    .EnumerateFiles(path, "*.sl", SearchOption.AllDirectories)
                    .OrderBy(f => f, StringComparer.Ordinal));
            else
                sources.Add(path);
        }

        var libraries = Lines(directory, "libraries.txt");

        string expectedOutputPath = ExpectedOutputPath(directory);
        string expectedErrorsPath = Path.Combine(directory, "errors.txt");

        bool expectsFailure = File.Exists(expectedErrorsPath);
        if (!expectsFailure && !File.Exists(expectedOutputPath))
            return (false, "the case has neither expected.txt nor errors.txt");

        string caseWork = Path.Combine(workDirectory, name);
        Directory.CreateDirectory(caseWork);

        bool shared = File.Exists(Path.Combine(directory, "shared.txt"));

        string debugPath = Path.Combine(directory, "debug.txt");
        bool debug = File.Exists(debugPath);

        // A case containing defines.txt is built with each of its lines passed
        // as -D, which is the only way to exercise a build flag end to end.
        string abiPath = Path.Combine(directory, "abi.txt");
        Binding.CppAbi? abi = File.Exists(abiPath)
            ? File.ReadAllText(abiPath).Trim().ToLowerInvariant() switch
            {
                "itanium" => Binding.CppAbi.Itanium,
                "microsoft" => Binding.CppAbi.Microsoft,
                var other => throw new InvalidOperationException($"unknown abi '{other}'"),
            }
            : null;

        var defines = Lines(directory, "defines.txt");

        // A `library/` subdirectory is built first, as a Stainless library with
        // module metadata, and the case's own sources are then compiled against
        // it. That is the two-compilation shape the metadata exists for, and the
        // only way to test it is to actually perform both.
        string libraryDirectory = Path.Combine(directory, "library");
        string? referencePath = null;
        string? importLibrary = null;

        // A warning about what a library's metadata leaves out is reported where
        // the library is built, so that build's diagnostics have to be kept for
        // warnings.txt to be able to name one.
        IReadOnlyList<Source.Diagnostic> libraryDiagnostics = [];

        if (Directory.Exists(libraryDirectory))
        {
            var librarySources = Directory.EnumerateFiles(libraryDirectory, "*.sl")
                .OrderBy(p => p, StringComparer.Ordinal).ToList();

            string libraryOutput =
                Path.Combine(caseWork, name + "-library" + Toolchain.SharedLibraryExtension);
            referencePath = Path.Combine(caseWork, name + ".slmod");

            var libraryResult = new Compilation().Compile(new CompilationOptions
            {
                SourcePaths = librarySources,
                OutputPath = libraryOutput,
                IntermediateDirectory = Path.Combine(caseWork, "obj-library"),
                OptimizationLevel = 1,
                Shared = true,
                MetadataPath = referencePath,
            });

            libraryDiagnostics = libraryResult.Diagnostics;

            if (!libraryResult.Success)
                return (false, "the library failed to build:\n" +
                               (libraryResult.DriverError ?? string.Join("\n",
                                   libraryResult.Diagnostics.Select(d => d.Render(color: false)))));

            string beside = Path.ChangeExtension(libraryOutput, ".lib");
            importLibrary = File.Exists(beside) ? beside : libraryOutput;
        }

        var options = new CompilationOptions
        {
            SourcePaths = sources,
            // A shared case compiles its C separately, against the built library.
            NativeInputs = shared
                ? []
                : importLibrary is null ? natives : [.. natives, importLibrary],
            References = referencePath is null ? [] : [referencePath],
            OutputPath = Path.Combine(
                caseWork,
                name + (shared ? Toolchain.SharedLibraryExtension
                               : Toolchain.ExecutableExtension)),
            IntermediateDirectory = Path.Combine(caseWork, "obj"),
            Shared = shared,
            HeaderPath = shared ? Path.Combine(caseWork, "library.h") : null,

            // -O0 alongside it: the point of a debug case is the description of
            // the code as written, and the optimiser rewrites what it describes.
            OptimizationLevel = debug ? 0 : 1,
            Debug = debug,
            Defines = defines,
            Libraries = libraries,
            CppAbi = abi,
        };

        CompilationResult result;
        try
        {
            result = new Compilation().Compile(options);
        }
        catch (Exception e)
        {
            return (false, $"the compiler threw {e.GetType().Name}: {e.Message}\n{e.StackTrace}");
        }

        // --- warnings, whether or not the build went on to fail -----------
        string expectedWarningsPath = Path.Combine(directory, "warnings.txt");
        if (File.Exists(expectedWarningsPath))
        {
            var wanted = File.ReadAllLines(expectedWarningsPath)
                .Select(l => l.Trim())
                .Where(l => l.Length > 0 && !l.StartsWith('#'))
                .ToList();

            var reported = libraryDiagnostics
                .Select(d => d.Code)
                .Concat(result.Diagnostics.Select(d => d.Code))
                .ToList();

            var absent = wanted.Where(w => !reported.Contains(w)).ToList();
            if (absent.Count > 0)
                return (false,
                    $"expected warning(s) {string.Join(", ", absent)}\n" +
                    $"but got          {(reported.Count == 0 ? "(none)" : string.Join(", ", reported))}");
        }

        // --- compile-failure cases ---------------------------------------
        if (expectsFailure)
        {
            var wanted = File.ReadAllLines(expectedErrorsPath)
                .Select(l => l.Trim())
                .Where(l => l.Length > 0 && !l.StartsWith('#'))
                .ToList();

            if (result.Success)
                return (false, $"expected compilation to fail with {string.Join(", ", wanted)}, " +
                               "but it succeeded");

            // Warnings count, so that a documented one can be pinned by the
            // same file rather than going untested. The case must still fail to
            // compile, which is what tells a warning apart from a passing run.
            var actual = result.Diagnostics.Select(d => d.Code).ToList();

            var missing = wanted.Where(w => !actual.Contains(w)).ToList();
            if (missing.Count > 0)
                return (false,
                    $"expected diagnostic(s) {string.Join(", ", missing)}\n" +
                    $"but got        {(actual.Count == 0 ? "(none)" : string.Join(", ", actual))}\n\n" +
                    string.Join("\n", result.Diagnostics.Select(d => d.Render(color: false))));

            return (true, string.Join(", ", actual));
        }

        // --- run cases ---------------------------------------------------
        if (!result.Success)
        {
            string detail = result.DriverError
                ?? string.Join("\n", result.Diagnostics.Select(d => d.Render(color: false)));
            return (false, "compilation failed:\n" + detail);
        }

        // A library is exercised through a C consumer, not run directly.
        string executable = result.OutputPath!;
        if (shared)
        {
            var built = BuildConsumer(caseWork, name, result.OutputPath!, natives);
            if (built.Error is not null) return (false, built.Error);
            executable = built.Path!;
        }

        if (debug && MissingFromIr(debugPath, result.Ir) is { Count: > 0 } absentDebug)
            return (false, "the debug metadata is missing:" + Environment.NewLine + "  " +
                           string.Join(Environment.NewLine + "  ", absentDebug));

        string irPath = Path.Combine(directory, "ir.txt");
        if (File.Exists(irPath) && MissingFromIr(irPath, result.Ir) is { Count: > 0 } absentIr)
            return (false, "the generated IR is missing:" + Environment.NewLine + "  " +
                           string.Join(Environment.NewLine + "  ", absentIr));

        string expected = Normalize(File.ReadAllText(expectedOutputPath));
        var (exitCode, output) = Execute(executable, directory);
        string actualOutput = Normalize(output);

        if (actualOutput != expected)
            return (false, Diff(expected, actualOutput));

        if (exitCode != 0)
            return (false, $"the program exited with code {exitCode}");

        return (true, $"{actualOutput.Split('\n').Length} line(s) matched");
    }

    /// <summary>
    /// Compiles the case's C files against the library just built, exactly as a
    /// real consumer would: the generated header on the include path, and the
    /// import library on the link line.
    /// </summary>
    private static (string? Path, string? Error) BuildConsumer(
        string caseWork, string name, string libraryPath, IReadOnlyList<string> natives)
    {
        if (natives.Count == 0)
            return (null, "a shared case needs a .c consumer to exercise the library");

        var toolchain = Toolchain.Locate(out string error);
        if (toolchain is null) return (null, error);

        string consumer = Path.Combine(
            caseWork, name + "-consumer" + Toolchain.ExecutableExtension);
        List<string> arguments = [.. natives, "-I", caseWork];

        // On Windows the linker wants the import library beside the DLL.
        string importLibrary = Path.ChangeExtension(libraryPath, ".lib");
        arguments.Add(File.Exists(importLibrary) ? importLibrary : libraryPath);
        arguments.AddRange(["-O1", "-o", consumer]);

        var result = Toolchain.Run(toolchain.ClangPath, arguments);
        return result.Success
            ? (consumer, null)
            : (null, "the C consumer failed to build:\n" + result.StandardError.TrimEnd());
    }

    /// <summary>
    /// Runs the program, with whatever the case says to give it.
    ///
    /// A case may contain <c>args.txt</c>, one argument per line, and
    /// <c>stdin.txt</c>, fed to the program verbatim. Without them a program
    /// gets no arguments and an immediately closed input, which is what every
    /// case did before either existed.
    /// </summary>
    private static (int ExitCode, string Output) Execute(string executablePath, string directory)
    {
        var startInfo = new ProcessStartInfo(executablePath)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            RedirectStandardInput = true,
            UseShellExecute = false,
        };

        string argumentsPath = Path.Combine(directory, "args.txt");
        if (File.Exists(argumentsPath))
            foreach (string argument in File.ReadAllLines(argumentsPath))
                if (argument.Length > 0)
                    startInfo.ArgumentList.Add(argument);

        using var process = Process.Start(startInfo)!;

        string inputPath = Path.Combine(directory, "stdin.txt");
        if (File.Exists(inputPath))
        {
            // Newlines normalised, so a case reads the same on both platforms
            // however the file was checked out.
            string text = File.ReadAllText(inputPath).Replace("\r\n", "\n");
            process.StandardInput.Write(text);
        }

        // Closed either way: a program that reads to end of input would
        // otherwise wait for one that is never coming.
        process.StandardInput.Close();

        string output = process.StandardOutput.ReadToEnd() + process.StandardError.ReadToEnd();

        if (!process.WaitForExit(20_000))
        {
            process.Kill(entireProcessTree: true);
            return (-1, output + "\n[the program did not finish within 20 seconds]");
        }

        return (process.ExitCode, output);
    }

    /// <summary>The lines of a file that do not appear in the IR.</summary>
    private static List<string> MissingFromIr(string path, string? ir) =>
        File.ReadAllLines(path)
            .Select(l => l.Trim())
            .Where(l => l.Length > 0 && !l.StartsWith('#'))
            .Where(l => ir?.Contains(l, StringComparison.Ordinal) != true)
            .ToList();

    private static string Normalize(string text) =>
        text.Replace("\r\n", "\n").TrimEnd('\n');

    private static string Diff(string expected, string actual)
    {
        string[] expectedLines = expected.Split('\n');
        string[] actualLines = actual.Split('\n');
        var report = new List<string> { "output did not match:" };

        for (int i = 0; i < Math.Max(expectedLines.Length, actualLines.Length); i++)
        {
            string e = i < expectedLines.Length ? expectedLines[i] : "<missing>";
            string a = i < actualLines.Length ? actualLines[i] : "<missing>";
            if (e == a) { report.Add($"    {e}"); continue; }
            report.Add($"  - {e}");
            report.Add($"  + {a}");
        }

        return string.Join("\n", report);
    }

    private static string Indent(string text) =>
        string.Join("\n", text.Split('\n').Select(l => "        " + l));

    /// <summary>Walks up from the binary to find the repository's tests/cases directory.</summary>
    private static string FindCasesDirectory()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            string candidate = Path.Combine(directory.FullName, "tests", "cases");
            if (Directory.Exists(candidate)) return candidate;
            directory = directory.Parent;
        }
        return "";
    }
}
