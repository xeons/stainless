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
///   errors.txt     the program must fail to compile with these diagnostic codes
///
/// A case containing defines.txt is built with each of its lines passed as -D,
/// and one containing abi.txt is built for the ABI that file names.
///
/// A case containing debug.txt is additionally built with debug information, and
/// every line of that file must appear somewhere in the generated IR. Linking at
/// all is most of the test: clang runs LLVM's verifier over the metadata, so a
/// malformed description fails the build rather than producing a quiet lie.
///
/// A case containing shared.txt is built as a shared library with a generated
/// header named library.h, and its .c files are then compiled against it. That
/// exercises the export table and the C header rather than just the compiler.
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
        var failures = new List<(string Name, string Detail)>();
        var stopwatch = Stopwatch.StartNew();

        foreach (string directory in cases)
        {
            string name = Path.GetFileName(directory);
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
            ? $"\u001b[32mall {passed} tests passed\u001b[0m in {stopwatch.ElapsedMilliseconds} ms"
            : $"\u001b[31m{failures.Count} failed\u001b[0m, {passed} passed in {stopwatch.ElapsedMilliseconds} ms";
        Console.WriteLine(summary);

        return failures.Count == 0 ? 0 : 1;
    }

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
        string expectedOutputPath = Path.Combine(directory, "expected.txt");
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

        string definesPath = Path.Combine(directory, "defines.txt");
        var defines = File.Exists(definesPath)
            ? File.ReadAllLines(definesPath)
                .Select(l => l.Trim())
                .Where(l => l.Length > 0 && !l.StartsWith('#'))
                .ToList()
            : [];

        // A `library/` subdirectory is built first, as a Stainless library with
        // module metadata, and the case's own sources are then compiled against
        // it. That is the two-compilation shape the metadata exists for, and the
        // only way to test it is to actually perform both.
        string libraryDirectory = Path.Combine(directory, "library");
        string? referencePath = null;
        string? importLibrary = null;

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
                caseWork, name + (shared ? Toolchain.SharedLibraryExtension : ".exe")),
            IntermediateDirectory = Path.Combine(caseWork, "obj"),
            Shared = shared,
            HeaderPath = shared ? Path.Combine(caseWork, "library.h") : null,

            // -O0 alongside it: the point of a debug case is the description of
            // the code as written, and the optimiser rewrites what it describes.
            OptimizationLevel = debug ? 0 : 1,
            Debug = debug,
            Defines = defines,
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

            var actual = result.Diagnostics
                .Where(d => d.Severity == Source.Severity.Error)
                .Select(d => d.Code)
                .ToList();

            var missing = wanted.Where(w => !actual.Contains(w)).ToList();
            if (missing.Count > 0)
                return (false,
                    $"expected error(s) {string.Join(", ", missing)}\n" +
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

        if (debug)
        {
            var wanted = File.ReadAllLines(debugPath)
                .Select(l => l.Trim())
                .Where(l => l.Length > 0 && !l.StartsWith('#'))
                .ToList();

            var absent = wanted
                .Where(w => result.Ir?.Contains(w, StringComparison.Ordinal) != true)
                .ToList();

            if (absent.Count > 0)
                return (false, "the debug metadata is missing:" + Environment.NewLine + "  " +
                               string.Join(Environment.NewLine + "  ", absent));
        }

        string expected = Normalize(File.ReadAllText(expectedOutputPath));
        var (exitCode, output) = Execute(executable);
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

        string consumer = Path.Combine(caseWork, name + "-consumer.exe");
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

    private static (int ExitCode, string Output) Execute(string executablePath)
    {
        var startInfo = new ProcessStartInfo(executablePath)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };

        using var process = Process.Start(startInfo)!;
        string output = process.StandardOutput.ReadToEnd() + process.StandardError.ReadToEnd();

        if (!process.WaitForExit(20_000))
        {
            process.Kill(entireProcessTree: true);
            return (-1, output + "\n[the program did not finish within 20 seconds]");
        }

        return (process.ExitCode, output);
    }

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
