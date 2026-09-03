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

namespace Stainless.Cli;

internal static class Program
{
    private const string Version = "0.1.0";

    private static int Main(string[] args)
    {
        Console.OutputEncoding = System.Text.Encoding.UTF8;

        if (args.Length == 0 || args[0] is "-h" or "--help" or "help")
        {
            PrintUsage();
            return args.Length == 0 ? 1 : 0;
        }

        if (args[0] is "-v" or "--version" or "version")
        {
            Console.WriteLine($"stainless {Version}");
            return 0;
        }

        string command = args[0];
        string[] rest = args[1..];

        return command switch
        {
            "build" => Build(rest, run: false),
            "run" => Build(rest, run: true),
            "emit-ir" => EmitIr(rest),
            _ => UnknownCommand(command),
        };
    }

    private static int UnknownCommand(string command)
    {
        Error($"unknown command '{command}'");
        Console.Error.WriteLine("Run 'stainless --help' to see the available commands.");
        return 1;
    }

    private static void PrintUsage()
    {
        Console.WriteLine($"""
            stainless {Version} — the Stainless compiler

            USAGE
              stainless build <paths...> [options]   compile to a native executable
              stainless run   <paths...> [options]   compile, then run it
              stainless emit-ir <paths...>           print the generated LLVM IR

            PATHS
              Any mix of .sl files and directories. Directories are searched
              recursively. Every file given is compiled together as one program,
              in any order — Stainless has no headers and no declaration order.

              C sources (.c/.cpp) and binaries (.o/.obj/.lib/.a) may be listed
              too; they are handed to the native linker. No bindings are needed,
              because Stainless already speaks the platform C ABI.

            OPTIONS
              -o, --out <path>     output file (default: after the first source)
              --shared             build a shared library instead of an executable
              --header <path>      write a C header for the exported surface
              --metadata <path>    write module metadata for a Stainless consumer
              --reference <path>   bind against a library's module metadata
              -O<0-3>              optimization level (default: -O2)
              --keep               keep the generated .ll next to the output
              --obj <dir>          directory for intermediates (default: ./obj)
              -h, --help           show this message
              -v, --version        show the version

            LIBRARIES
              A '--shared' build needs no Main. Its export table contains exactly
              the functions marked 'export "C"'; everything else stays internal,
              including 'public' declarations, which are visible only to other
              Stainless modules.

            EXAMPLES
              stainless run samples/hello.sl
              stainless build src -o build/app.exe -O3
              stainless build src --shared -o build/math.dll --header build/math.h
              stainless emit-ir samples/hello.sl
            """);
    }

    // ------------------------------------------------------------ commands

    private static int Build(string[] args, bool run)
    {
        if (!TryParse(args, out var options, out var programArguments)) return 1;
        if (options is null) return 1;

        var stopwatch = Stopwatch.StartNew();
        var result = new Compilation().Compile(options);
        stopwatch.Stop();

        if (!Report(result)) return 1;

        Success($"built {Relative(result.OutputPath!)} in {stopwatch.ElapsedMilliseconds} ms");
        if (result.HeaderPath is not null)
            Console.WriteLine($"  header: {Relative(result.HeaderPath)}");

        if (result.MetadataPath is not null)
            Console.WriteLine($"  metadata: {Relative(result.MetadataPath)}");
        if (result.IrPath is not null) Console.WriteLine($"  IR: {Relative(result.IrPath)}");

        if (options.Shared)
        {
            // Running a library is meaningless; say so rather than failing oddly.
            if (run) Error("a shared library cannot be run");
            return run ? 1 : 0;
        }

        if (!run) return 0;

        Console.WriteLine();
        var process = Process.Start(new ProcessStartInfo(result.OutputPath!)
        {
            UseShellExecute = false,
            ArgumentList = { },
        });

        foreach (string argument in programArguments) _ = argument;   // reserved for Main(args)

        if (process is null)
        {
            Error($"could not start {result.OutputPath}");
            return 1;
        }

        process.WaitForExit();
        return process.ExitCode;
    }

    private static int EmitIr(string[] args)
    {
        if (!TryParse(args, out var options, out _)) return 1;
        if (options is null) return 1;

        var result = new Compilation().Compile(options with { EmitIrOnly = true });
        if (!Report(result)) return 1;

        Console.WriteLine(result.Ir);
        return 0;
    }

    // ------------------------------------------------------------ argument parsing

    private static bool TryParse(
        string[] args, out CompilationOptions? options, out List<string> programArguments)
    {
        options = null;
        programArguments = [];

        var paths = new List<string>();
        string? output = null;
        string? objectDirectory = null;
        int optimization = 2;
        bool keep = false;
        bool shared = false;
        string? header = null;
        string? metadata = null;
        var references = new List<string>();

        for (int i = 0; i < args.Length; i++)
        {
            string argument = args[i];

            switch (argument)
            {
                case "-o" or "--out":
                    if (++i >= args.Length) { Error("'-o' needs a path"); return false; }
                    output = args[i];
                    continue;

                case "--obj":
                    if (++i >= args.Length) { Error("'--obj' needs a directory"); return false; }
                    objectDirectory = args[i];
                    continue;

                case "--keep":
                    keep = true;
                    continue;

                case "--shared":
                    shared = true;
                    continue;

                case "--metadata":
                    if (++i >= args.Length) { Error("'--metadata' needs a path"); return false; }
                    metadata = args[i];
                    continue;

                case "--reference" or "-r":
                    if (++i >= args.Length) { Error("'--reference' needs a path"); return false; }
                    references.Add(args[i]);
                    continue;

                case "--header":
                    if (++i >= args.Length) { Error("'--header' needs a path"); return false; }
                    header = args[i];
                    continue;

                case "--":
                    programArguments.AddRange(args[(i + 1)..]);
                    i = args.Length;
                    continue;
            }

            if (argument.Length == 3 && argument.StartsWith("-O", StringComparison.Ordinal) &&
                char.IsDigit(argument[2]))
            {
                optimization = argument[2] - '0';
                continue;
            }

            if (argument.StartsWith('-'))
            {
                Error($"unknown option '{argument}'");
                return false;
            }

            paths.Add(argument);
        }

        if (paths.Count == 0)
        {
            Error("no source files were given");
            Console.Error.WriteLine("Run 'stainless --help' for usage.");
            return false;
        }

        var sources = Compilation.CollectSourceFiles(paths);
        foreach (string error in sources.Errors) Error(error);
        if (sources.Errors.Count > 0) return false;

        if (sources.Sources.Count == 0)
        {
            Error("no .sl source files were found");
            return false;
        }

        options = new CompilationOptions
        {
            SourcePaths = sources.Sources,
            NativeInputs = sources.NativeInputs,
            OutputPath = output,
            IntermediateDirectory = objectDirectory,
            OptimizationLevel = optimization,
            KeepIntermediates = keep,
            Shared = shared,
            HeaderPath = header,
            MetadataPath = metadata,
            References = references,
        };

        if (metadata is not null && !shared)
            Console.Error.WriteLine(
                "note: '--metadata' describes a library's surface, which only a '--shared' " +
                "build has");

        if (header is not null && !shared)
            Console.Error.WriteLine(
                "note: '--header' describes an exported surface, which only a '--shared' build has");

        return true;
    }

    // ------------------------------------------------------------ output

    private static bool Report(CompilationResult result)
    {
        bool color = !Console.IsErrorRedirected;

        foreach (var diagnostic in result.Diagnostics)
            Console.Error.WriteLine(diagnostic.Render(color));

        if (result.DriverError is not null) Error(result.DriverError);

        if (!result.Success)
        {
            int errors = result.Diagnostics.Count(d => d.Severity == Source.Severity.Error);
            if (errors > 0)
                Console.Error.WriteLine(
                    $"compilation failed with {errors} error{(errors == 1 ? "" : "s")}.");
            return false;
        }

        return true;
    }

    private static void Error(string message)
    {
        bool color = !Console.IsErrorRedirected;
        Console.Error.WriteLine($"{(color ? "\u001b[1;31m" : "")}error{(color ? "\u001b[0m" : "")}: {message}");
    }

    private static void Success(string message)
    {
        bool color = !Console.IsOutputRedirected;
        Console.WriteLine($"{(color ? "\u001b[1;32m" : "")}ok{(color ? "\u001b[0m" : "")}: {message}");
    }

    private static string Relative(string path)
    {
        string relative = Path.GetRelativePath(Environment.CurrentDirectory, path);
        return relative.Length < path.Length ? relative : path;
    }
}
