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
              -o, --out <path>     output executable (default: after the first source)
              -O<0-3>              optimization level (default: -O2)
              --keep               keep the generated .ll next to the executable
              --obj <dir>          directory for intermediates (default: ./obj)
              -h, --help           show this message
              -v, --version        show the version

            EXAMPLES
              stainless run samples/hello.sl
              stainless build src -o build/app.exe -O3
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
        if (result.IrPath is not null) Console.WriteLine($"  IR: {Relative(result.IrPath)}");

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

        var files = Compilation.CollectSourceFiles(paths, out var nativeInputs, out var errors);
        foreach (string error in errors) Error(error);
        if (errors.Count > 0) return false;

        if (files.Count == 0)
        {
            Error("no .sl source files were found");
            return false;
        }

        options = new CompilationOptions
        {
            SourcePaths = files,
            NativeInputs = nativeInputs,
            OutputPath = output,
            IntermediateDirectory = objectDirectory,
            OptimizationLevel = optimization,
            KeepIntermediates = keep,
        };
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
