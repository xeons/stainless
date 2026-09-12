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
            "init" => Init(rest),
            "restore" => Restore(rest),
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
              stainless build [paths...] [options]   compile to a native executable
              stainless run   [paths...] [options]   compile, then run it
              stainless emit-ir [paths...]           print the generated LLVM IR
              stainless init [name]                  write a {ProjectFile.FileName} here
              stainless restore [options]            resolve dependencies and lock them

            PATHS
              Any mix of .sl files and directories. Directories are searched
              recursively. Every file given is compiled together as one program,
              in any order — Stainless has no headers and no declaration order.

              C sources (.c/.cpp) and binaries (.o/.obj/.lib/.a) may be listed
              too; they are handed to the native linker. No bindings are needed,
              because Stainless already speaks the platform C ABI.

              A library the linker can find for itself is named with '-l'
              instead of by path: '-l user32' rather than the full path into
              whichever Windows SDK happens to be installed. A source file can
              name one itself with '#pragma comment(lib, "user32")', which is
              usually better: the module that calls into a library is the one
              that knows it needs it.

            PROJECTS
              With no paths, the build looks for a '{ProjectFile.FileName}' here or in
              a parent directory and builds that project — its sources, its
              dependencies, and the options it states. A directory holding one
              can also be named directly.

              A project file is a document rather than a script, which is the
              point of it: what a Makefile can only do, this can also be read.

            OPTIONS
              -o, --out <path>     output file (default: after the first source)
              --shared             build a shared library instead of an executable
              --header <path>      write a C header for the exported surface
              --metadata <path>    write module metadata for a Stainless consumer
              --reference <path>   bind against a library's module metadata
              --project <path>     the project file to build, or the directory holding it
              --no-project         ignore any project file and use the paths alone
              --locked             fail rather than change the lock file (for CI)
              --offline            use the package cache and never the network
              --update             re-resolve dependencies, ignoring the lock
              --runtime <shared|static>
                                   whether the runtime is one shared library or a
                                   copy in this binary. The default is shared where
                                   two Stainless binaries meet -- a '--metadata'
                                   build or a '--reference' one -- and static
                                   everywhere else, because a program with no
                                   library boundary has nothing to gain and a file
                                   to carry
              -O<0-3>              optimization level (default: -O2)
              -g, --debug          describe the program to a debugger
              -D, --define <name>  define a symbol for '#if' to test
              -l, --library <name> link a library the linker finds by name
              --abi <microsoft|itanium>
                                   which C and C++ ABI to agree with: name
                                   mangling, bit-field layout and how a struct
                                   is passed (default: the host's)
              --keep               keep the generated .ll next to the output
              --obj <dir>          directory for intermediates (default: ./obj)
              -h, --help           show this message
              -v, --version        show the version

            LIBRARIES
              A '--shared' build needs no Main. Its export table contains exactly
              the functions marked 'export "C"'; everything else stays internal,
              including 'public' declarations, which are visible only to other
              Stainless modules.

              Adding '--metadata' says the consumer will be Stainless rather than
              C, and widens the table to the public declarations that metadata
              describes. The consumer then passes '--reference' and links the
              library, and writes ordinary Stainless against a module it has no
              source for.

            EXAMPLES
              stainless run samples/hello.sl
              stainless build                       (the project here)
              stainless init myapp
              stainless restore --update
              stainless build src -o build/app.exe -O3
              stainless build src --shared -o build/math.dll --header build/math.h
              stainless build lib --shared -o build/shapes.dll --metadata build/shapes.slmod
              stainless build app.sl -r build/shapes.slmod build/shapes.lib -o app.exe
              stainless build gui.sl -l user32 -l gdi32 -o gui.exe
              stainless emit-ir samples/hello.sl
            """);
    }

    // ------------------------------------------------------------ commands

    private static int Build(string[] args, bool run)
    {
        if (!TryParse(args, out var arguments) || arguments is null) return 1;

        var project = FindProject(arguments);
        if (project is null && arguments.ProjectError is not null)
        {
            Error(arguments.ProjectError);
            return 1;
        }

        return project is not null
            ? BuildProject(project, arguments, run)
            : BuildPaths(arguments, run);
    }

    private static int EmitIr(string[] args)
    {
        if (!TryParse(args, out var arguments) || arguments is null) return 1;

        arguments.EmitIrOnly = true;

        var project = FindProject(arguments);
        if (project is null && arguments.ProjectError is not null)
        {
            Error(arguments.ProjectError);
            return 1;
        }

        if (project is not null)
        {
            var plan = Resolve(project, arguments);
            if (plan is null) return 1;

            var built = new ProjectBuilder(project, plan, Note).Build(arguments.ToOverrides());
            if (!ReportProject(built)) return 1;

            Console.WriteLine(built.Root!.Ir);
            return 0;
        }

        var options = arguments.ToCompilationOptions();
        if (options is null) return 1;

        var result = new Compilation().Compile(options with { EmitIrOnly = true });
        if (!Report(result)) return 1;

        Console.WriteLine(result.Ir);
        return 0;
    }

    /// <summary>
    /// Writes a project file for the directory it is run in.
    ///
    /// It guesses two things and states both, because the alternative is asking
    /// two questions nobody wants to answer: what the package is called, and
    /// where its sources are.
    /// </summary>
    private static int Init(string[] args)
    {
        string directory = Environment.CurrentDirectory;
        string path = Path.Combine(directory, ProjectFile.FileName);

        if (File.Exists(path))
        {
            Error($"there is already a {ProjectFile.FileName} here");
            return 1;
        }

        string name = args.FirstOrDefault(a => !a.StartsWith('-'))
                      ?? new DirectoryInfo(directory).Name;

        if (!ProjectFile.IsValidName(name))
        {
            Error($"'{name}' is not a package name; it is letters, digits, '_', '-' and '.'");
            return 1;
        }

        bool library = args.Contains("--library") || args.Contains("--shared");

        // Whatever is already there: 'src' if it exists, and otherwise this
        // directory, so 'init' in a folder of .sl files produces something that
        // builds rather than something that needs editing first.
        string sources =
            Directory.Exists(Path.Combine(directory, "src")) ? "src"
            : Directory.EnumerateFiles(directory, "*" + Compilation.SourceExtension).Any() ? "."
            : "src";

        var project = new ProjectFile
        {
            Name = name,
            Version = "0.1.0",
            Kind = library ? ProjectKind.Library : ProjectKind.Executable,
            Sources = [sources],
            Directory = directory,
        };

        try
        {
            project.WriteStarter(path);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Error($"could not write '{path}': {e.Message}");
            return 1;
        }

        Success($"wrote {Relative(path)}");
        Console.WriteLine($"  name:    {name}");
        Console.WriteLine($"  kind:    {(library ? "library" : "executable")}");
        Console.WriteLine($"  sources: {sources}");
        return 0;
    }

    private static int Restore(string[] args)
    {
        if (!TryParse(args, out var arguments) || arguments is null) return 1;

        var project = FindProject(arguments);
        if (project is null)
        {
            Error(arguments.ProjectError ??
                  $"there is no {ProjectFile.FileName} here or in any parent directory");
            return 1;
        }

        var plan = Resolve(project, arguments);
        if (plan is null) return 1;

        if (plan.Order.Count == 0)
        {
            Success($"{project.Name} has no dependencies");
            return 0;
        }

        Success($"resolved {plan.Order.Count} " +
                $"package{(plan.Order.Count == 1 ? "" : "s")} for {project.Name}");

        foreach (var package in plan.Order)
            Console.WriteLine(
                $"  {package.Name} {package.Project.Version}  " +
                $"{package.Source}{(package.Revision is null ? "" : $" ({package.Revision[..Math.Min(12, package.Revision.Length)]})")}  " +
                $"[{package.Link.ToString().ToLowerInvariant()}]");

        return 0;
    }

    // ------------------------------------------------------------ projects

    /// <summary>
    /// Which project this build is of, if it is of one.
    ///
    /// Explicit paths win: someone who named a file meant that file, even from
    /// inside a project. What is left is the two ways of meaning a project --
    /// naming it, and standing in it -- and standing in it is the common one.
    /// </summary>
    private static ProjectFile? FindProject(Arguments arguments)
    {
        if (arguments.NoProject) return null;

        string? path = null;

        if (arguments.Project is not null)
        {
            path = Directory.Exists(arguments.Project)
                ? Path.Combine(arguments.Project, ProjectFile.FileName)
                : arguments.Project;

            if (!File.Exists(path))
            {
                arguments.ProjectError = $"there is no project file at '{arguments.Project}'";
                return null;
            }
        }
        else if (arguments.Paths.Count == 0)
        {
            path = ProjectFile.Find(Environment.CurrentDirectory);

            if (path is null)
            {
                arguments.ProjectError =
                    $"no source files were given, and there is no {ProjectFile.FileName} here or " +
                    "in any parent directory. Name what to compile, or run 'stainless init'.";
                return null;
            }
        }
        else if (arguments.Paths.Count == 1 && Directory.Exists(arguments.Paths[0]))
        {
            // A directory that *is* a project is read as one. A directory of
            // loose sources is not, and still means what it always meant.
            string candidate = Path.Combine(arguments.Paths[0], ProjectFile.FileName);
            if (File.Exists(candidate))
            {
                path = candidate;
                arguments.Paths.Clear();
            }
        }

        if (path is null) return null;

        var project = ProjectFile.Read(path, out string error);
        if (project is null) arguments.ProjectError = error;

        return project;
    }

    /// <summary>
    /// Works out what to build, from the lock file where there is one and from
    /// the project file where there is not.
    /// </summary>
    private static Resolution? Resolve(ProjectFile project, Arguments arguments)
    {
        string lockPath = PackageLock.PathFor(project);

        var existing = PackageLock.Read(lockPath, out string lockError);
        if (existing is null && lockError.Length > 0)
        {
            Error(lockError);
            return null;
        }

        var resolution = new PackageResolver(offline: arguments.Offline, log: Note)
            .Resolve(project, existing, arguments.Update);

        if (!resolution.Success)
        {
            Error(resolution.Error!);
            return null;
        }

        if (!WriteLock(lockPath, existing, resolution.Lock, arguments)) return null;

        return resolution;
    }

    /// <summary>
    /// Writes the lock file, unless it would say the same thing or the build was
    /// told it must not change.
    /// </summary>
    private static bool WriteLock(
        string path, PackageLock? existing, PackageLock? resolved, Arguments arguments)
    {
        if (resolved is null) return true;

        // Nothing to lock and nothing locked: writing an empty file for a
        // project with no dependencies would be litter.
        if (resolved.Packages.Count == 0 && existing is null) return true;

        if (existing is not null && Same(existing, resolved)) return true;

        if (arguments.Locked)
        {
            Error($"'{Relative(path)}' is out of date and this build was run with --locked. Run " +
                  "'stainless restore' and commit the result.");
            return false;
        }

        try
        {
            resolved.Write(path);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Error($"could not write '{path}': {e.Message}");
            return false;
        }

        return true;
    }

    /// <summary>
    /// Whether two locks describe the same build. The ABI digest is left out:
    /// it is filled in after a build rather than by resolution, so comparing it
    /// here would call every first build a change.
    /// </summary>
    private static bool Same(PackageLock left, PackageLock right) =>
        left.Root == right.Root &&
        left.Packages.Count == right.Packages.Count &&
        left.Packages.Zip(right.Packages).All(pair =>
            pair.First.Name == pair.Second.Name &&
            pair.First.Version == pair.Second.Version &&
            pair.First.Source == pair.Second.Source &&
            pair.First.Revision == pair.Second.Revision &&
            pair.First.Link == pair.Second.Link &&
            pair.First.SourceDigest == pair.Second.SourceDigest);

    private static int BuildProject(ProjectFile project, Arguments arguments, bool run)
    {
        WarnAboutIgnoredOptions(project, arguments);

        var plan = Resolve(project, arguments);
        if (plan is null) return 1;

        var stopwatch = Stopwatch.StartNew();
        var built = new ProjectBuilder(project, plan, Note).Build(arguments.ToOverrides());
        stopwatch.Stop();

        if (!ReportProject(built)) return 1;

        var result = built.Root!;

        Success($"built {Relative(result.OutputPath!)} in {stopwatch.ElapsedMilliseconds} ms");

        // Built and reused said separately, because "nothing was done" is the
        // interesting half: a dependency that should have been rebuilt and was
        // not is a program linked against stale code, and the only chance of
        // noticing is the build having said so.
        if (built.Built.Count > 0)
            Console.WriteLine($"  built: {string.Join(", ", built.Built)}");
        if (built.Reused.Count > 0)
            Console.WriteLine($"  up to date: {string.Join(", ", built.Reused)}");
        if (result.HeaderPath is not null)
            Console.WriteLine($"  header: {Relative(result.HeaderPath)}");
        if (result.MetadataPath is not null)
            Console.WriteLine($"  metadata: {Relative(result.MetadataPath)}");
        if (result.IrPath is not null)
            Console.WriteLine($"  IR: {Relative(result.IrPath)}");

        // What the build learned about its dependencies' surfaces, which only a
        // build can know. Written after it, so a failed build never records a
        // digest for a library it did not finish.
        if (built.Lock is not null && !arguments.Locked)
            WriteLock(PackageLock.PathFor(project), null, built.Lock, arguments);

        if (project.IsLibrary)
        {
            if (run) Error("a library cannot be run");
            return run ? 1 : 0;
        }

        return run ? RunProgram(result.OutputPath!, arguments.ProgramArguments) : 0;
    }

    /// <summary>
    /// Says so when an option the project file already answers was passed
    /// anyway.
    ///
    /// These are the three that a project states rather than overrides: what
    /// kind of thing it is, and what it depends on. Quietly ignoring one would
    /// leave somebody watching for an effect that was never going to happen.
    /// </summary>
    private static void WarnAboutIgnoredOptions(ProjectFile project, Arguments arguments)
    {
        if (arguments.Shared && !project.IsLibrary)
            Note($"'--shared' is ignored here; '{Relative(project.Path)}' says " +
                 $"\"kind\": \"{project.Kind.ToString().ToLowerInvariant()}\"");

        if (arguments.Metadata is not null)
            Note("'--metadata' is ignored here; a library project writes its metadata beside " +
                 "its binary");

        if (arguments.References.Count > 0)
            Note("'--reference' is ignored here; a project says what it depends on in " +
                 "'dependencies', which is also what gets built and linked");
    }

    private static int BuildPaths(Arguments arguments, bool run)
    {
        var options = arguments.ToCompilationOptions();
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

        return run ? RunProgram(result.OutputPath!, arguments.ProgramArguments) : 0;
    }

    private static int RunProgram(string output, IReadOnlyList<string> programArguments)
    {
        Console.WriteLine();

        // The full path, because Windows resolves a bare name against PATH
        // rather than against the working directory -- so 'run -o app.exe'
        // would look for an app.exe anywhere but the one just built.
        string program = Path.GetFullPath(output);

        Process? process;
        try
        {
            var start = new ProcessStartInfo(program) { UseShellExecute = false };

            // Everything after `--`, handed over as written. ArgumentList
            // quotes each one for the platform, so an argument with a space in
            // it arrives as one argument rather than two.
            foreach (string argument in programArguments) start.ArgumentList.Add(argument);

            process = Process.Start(start);
        }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or IOException)
        {
            Error($"could not start {Relative(program)}: {e.Message}");
            return 1;
        }

        if (process is null)
        {
            Error($"could not start {Relative(program)}");
            return 1;
        }

        process.WaitForExit();
        return process.ExitCode;
    }

    // ------------------------------------------------------------ argument parsing

    /// <summary>
    /// What the command line said, before anything decides whether it is
    /// building a project or a list of files. Kept as one record because both
    /// routes want most of it and they want it in different shapes.
    /// </summary>
    private sealed class Arguments
    {
        public List<string> Paths { get; } = [];
        public List<string> ProgramArguments { get; } = [];
        public List<string> Defines { get; } = [];
        public List<string> Libraries { get; } = [];
        public List<string> References { get; } = [];

        public string? Output { get; set; }
        public string? ObjectDirectory { get; set; }
        public string? Header { get; set; }
        public string? Metadata { get; set; }
        public string? Project { get; set; }
        public string? ProjectError { get; set; }

        public int Optimization { get; set; } = 2;
        public bool OptimizationGiven { get; set; }
        public bool Keep { get; set; }
        public bool Debug { get; set; }
        public bool Shared { get; set; }
        public bool EmitIrOnly { get; set; }
        public bool NoProject { get; set; }
        public bool Locked { get; set; }
        public bool Offline { get; set; }
        public bool Update { get; set; }

        public Stainless.Binding.CppAbi? Abi { get; set; }
        public bool? SharedRuntime { get; set; }

        public BuildOverrides ToOverrides() => new()
        {
            OutputPath = Output,
            IntermediateDirectory = ObjectDirectory,
            OptimizationLevel = OptimizationGiven ? Optimization : null,
            Debug = Debug ? true : null,
            KeepIntermediates = Keep,
            EmitIrOnly = EmitIrOnly,
            Defines = Defines,
            Libraries = Libraries,
            CppAbi = Abi,
            SharedRuntime = SharedRuntime,
            HeaderPath = Header,
            ExtraPaths = Paths,
        };

        /// <summary>
        /// The options for a build driven by paths alone, which is what every
        /// build was before there was a project file and what a one-file program
        /// should stay.
        /// </summary>
        public CompilationOptions? ToCompilationOptions()
        {
            if (Paths.Count == 0)
            {
                Error("no source files were given");
                Console.Error.WriteLine("Run 'stainless --help' for usage.");
                return null;
            }

            var sources = Compilation.CollectSourceFiles(Paths);
            foreach (string error in sources.Errors) Error(error);
            if (sources.Errors.Count > 0) return null;

            if (sources.Sources.Count == 0)
            {
                Error("no .sl source files were found");
                return null;
            }

            // -O2 is the default rather than a choice, and stepping through code
            // the optimiser has rearranged is the usual first surprise. Say so
            // once, and leave an explicit -O alone: asking for both is a
            // legitimate thing to do.
            if (Debug && Optimization > 0 && !OptimizationGiven)
                Console.Error.WriteLine(
                    $"note: building at -O{Optimization} with -g; pass -O0 to step through the " +
                    "code as it was written");

            if (Metadata is not null && !Shared)
                Console.Error.WriteLine(
                    "note: '--metadata' describes a library's surface, which only a '--shared' " +
                    "build has");

            if (Header is not null && !Shared)
                Console.Error.WriteLine(
                    "note: '--header' describes an exported surface, which only a '--shared' " +
                    "build has");

            return new CompilationOptions
            {
                SourcePaths = sources.Sources,
                NativeInputs = sources.NativeInputs,
                Libraries = Libraries,
                OutputPath = Output,
                IntermediateDirectory = ObjectDirectory,
                OptimizationLevel = Optimization,
                KeepIntermediates = Keep,
                Debug = Debug,
                Defines = Defines,
                CppAbi = Abi,
                Shared = Shared,
                HeaderPath = Header,
                MetadataPath = Metadata,
                References = References,
                SharedRuntime = SharedRuntime,
            };
        }
    }

    private static bool TryParse(string[] args, out Arguments? parsed)
    {
        var arguments = new Arguments();
        parsed = null;

        for (int i = 0; i < args.Length; i++)
        {
            string argument = args[i];

            switch (argument)
            {
                case "-o" or "--out":
                    if (++i >= args.Length) { Error("'-o' needs a path"); return false; }
                    arguments.Output = args[i];
                    continue;

                case "--obj":
                    if (++i >= args.Length) { Error("'--obj' needs a directory"); return false; }
                    arguments.ObjectDirectory = args[i];
                    continue;

                case "--project" or "-p":
                    if (++i >= args.Length) { Error("'--project' needs a path"); return false; }
                    arguments.Project = args[i];
                    continue;

                case "--no-project":
                    arguments.NoProject = true;
                    continue;

                case "--locked":
                    arguments.Locked = true;
                    continue;

                case "--offline":
                    arguments.Offline = true;
                    continue;

                case "--update":
                    arguments.Update = true;
                    continue;

                case "-g" or "--debug":
                    arguments.Debug = true;
                    continue;

                case "-D" or "--define":
                    if (++i >= args.Length) { Error("'-D' needs a name"); return false; }
                    arguments.Defines.Add(args[i]);
                    continue;

                case "--abi":
                    if (++i >= args.Length) { Error("'--abi' needs a name"); return false; }
                    arguments.Abi = ProjectFile.ParseAbi(args[i]);
                    if (arguments.Abi is null)
                    {
                        Error($"'{args[i]}' is not an ABI; it is 'microsoft' or 'itanium'");
                        return false;
                    }
                    continue;

                case "-l" or "--library":
                    if (++i >= args.Length) { Error("'-l' needs a library name"); return false; }
                    arguments.Libraries.Add(args[i]);
                    continue;

                case "--keep":
                    arguments.Keep = true;
                    continue;

                case "--shared":
                    arguments.Shared = true;
                    continue;

                case "--metadata":
                    if (++i >= args.Length) { Error("'--metadata' needs a path"); return false; }
                    arguments.Metadata = args[i];
                    continue;

                case "--reference" or "-r":
                    if (++i >= args.Length) { Error("'--reference' needs a path"); return false; }
                    arguments.References.Add(args[i]);
                    continue;

                case "--runtime":
                    if (++i >= args.Length)
                    {
                        Error("'--runtime' needs 'shared' or 'static'");
                        return false;
                    }
                    switch (args[i])
                    {
                        case "shared": arguments.SharedRuntime = true; break;
                        case "static": arguments.SharedRuntime = false; break;
                        default:
                            Error($"unknown runtime '{args[i]}'; it is 'shared' or 'static'");
                            return false;
                    }
                    continue;

                case "--header":
                    if (++i >= args.Length) { Error("'--header' needs a path"); return false; }
                    arguments.Header = args[i];
                    continue;

                case "--":
                    arguments.ProgramArguments.AddRange(args[(i + 1)..]);
                    i = args.Length;
                    continue;
            }

            if (argument.Length == 3 && argument.StartsWith("-O", StringComparison.Ordinal) &&
                char.IsDigit(argument[2]))
            {
                arguments.Optimization = argument[2] - '0';
                arguments.OptimizationGiven = true;
                continue;
            }

            if (argument.Length > 2 && argument.StartsWith("-l", StringComparison.Ordinal))
            {
                arguments.Libraries.Add(argument[2..]);
                continue;
            }

            if (argument.StartsWith('-'))
            {
                Error($"unknown option '{argument}'");
                return false;
            }

            arguments.Paths.Add(argument);
        }

        parsed = arguments;
        return true;
    }

    // ------------------------------------------------------------ output

    private static bool ReportProject(ProjectBuildResult built)
    {
        foreach (string warning in built.Warnings) Note(warning);

        if (built.Root is not null && !Report(built.Root))
        {
            if (built.Error is not null) Error(built.Error);
            return false;
        }

        if (built.Success) return true;

        if (built.Error is not null) Error(built.Error);
        return false;
    }

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

    private static void Note(string message)
    {
        bool color = !Console.IsErrorRedirected;
        Console.Error.WriteLine($"{(color ? "\u001b[1;36m" : "")}note{(color ? "\u001b[0m" : "")}: {message}");
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
