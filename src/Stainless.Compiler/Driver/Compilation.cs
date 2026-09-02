using Stainless.Binding;
using Stainless.Emit;
using Stainless.Source;
using Stainless.Syntax;

namespace Stainless.Driver;

public sealed record CompilationOptions
{
    public required IReadOnlyList<string> SourcePaths { get; init; }

    /// <summary>
    /// C sources, object files and libraries to link in. Because Stainless uses the
    /// platform C ABI, these need no wrapper, binding or marshalling layer.
    /// </summary>
    public IReadOnlyList<string> NativeInputs { get; init; } = [];

    /// <summary>
    /// Module names derived from where each file sits, keyed by full path. A
    /// file that declares its own <c>module</c> ignores this.
    /// </summary>
    public IReadOnlyDictionary<string, string> InferredModules { get; init; } =
        new Dictionary<string, string>();
    public string? OutputPath { get; init; }
    public string? IntermediateDirectory { get; init; }
    public int OptimizationLevel { get; init; } = 2;

    /// <summary>Build a shared library rather than an executable.</summary>
    public bool Shared { get; init; }

    /// <summary>Where to write a C header for the exported surface, if anywhere.</summary>
    public string? HeaderPath { get; init; }
    public bool KeepIntermediates { get; init; }
    public bool EmitIrOnly { get; init; }
}

public sealed record CompilationResult
{
    public required bool Success { get; init; }
    public required IReadOnlyList<Diagnostic> Diagnostics { get; init; }
    public string? OutputPath { get; init; }
    public string? IrPath { get; init; }
    public string? Ir { get; init; }
    public string? HeaderPath { get; init; }

    /// <summary>A failure outside the source program: a missing tool, unreadable file, bad IR.</summary>
    public string? DriverError { get; init; }
}

/// <summary>What a set of command-line paths expanded to.</summary>
public sealed record SourceSet
{
    public required IReadOnlyList<string> Sources { get; init; }
    public required IReadOnlyList<string> NativeInputs { get; init; }

    /// <summary>Module names derived from each file's path, keyed by full path.</summary>
    public required IReadOnlyDictionary<string, string> InferredModules { get; init; }

    public required IReadOnlyList<string> Errors { get; init; }
}

/// <summary>
/// The front-to-back pipeline: source files in, native executable out.
/// </summary>
public sealed class Compilation
{
    public const string SourceExtension = ".sl";

    /// <summary>File kinds handed straight to the native toolchain rather than parsed.</summary>
    private static readonly string[] NativeExtensions =
        [".c", ".cc", ".cpp", ".cxx", ".o", ".obj", ".lib", ".a"];

    public static bool IsNativeInput(string path) =>
        NativeExtensions.Contains(Path.GetExtension(path), StringComparer.OrdinalIgnoreCase);

    /// <summary>
    /// Expands directories into their .sl files, separates native inputs, and
    /// derives a module name for each file from where it sits.
    ///
    /// A directory given on the command line is that file's package root, so
    /// <c>src/Shop/Catalog.sl</c> under <c>src</c> becomes <c>Shop.Catalog</c>.
    /// That is what keeps two files called <c>Utils.sl</c> in different folders
    /// from claiming the same module.
    /// </summary>
    public static SourceSet CollectSourceFiles(IEnumerable<string> paths)
    {
        var files = new List<string>();
        var nativeInputs = new List<string>();
        var errors = new List<string>();
        var inferred = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        foreach (string path in paths)
        {
            if (IsNativeInput(path))
            {
                if (File.Exists(path)) nativeInputs.Add(Path.GetFullPath(path));
                else errors.Add($"'{path}' does not exist");
                continue;
            }

            if (Directory.Exists(path))
            {
                string root = Path.GetFullPath(path);

                var all = Directory
                    .EnumerateFiles(root, "*", SearchOption.AllDirectories)
                    .Select(Path.GetFullPath)
                    .OrderBy(p => p, StringComparer.Ordinal)
                    .ToList();

                var found = all
                    .Where(f => Path.GetExtension(f)
                        .Equals(SourceExtension, StringComparison.OrdinalIgnoreCase))
                    .ToList();

                if (found.Count == 0)
                    errors.Add($"no {SourceExtension} files were found under '{path}'");

                foreach (string file in found)
                {
                    files.Add(file);
                    if (ModuleNameFor(root, file) is { } name) inferred[file] = name;
                }

                // C sources sitting beside the Stainless ones belong to the same
                // program; a directory would otherwise drop them silently.
                nativeInputs.AddRange(all.Where(IsNativeInput));
            }
            else if (File.Exists(path))
            {
                // A file named on its own has no root, so only its own name applies.
                files.Add(Path.GetFullPath(path));
            }
            else
            {
                errors.Add($"'{path}' does not exist");
            }
        }

        return new SourceSet
        {
            Sources = files.Distinct(StringComparer.OrdinalIgnoreCase).ToList(),
            NativeInputs = nativeInputs
                .Where(f => !IsBuildArtifact(f))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList(),
            InferredModules = inferred,
            Errors = errors,
        };
    }

    /// <summary>
    /// Turns a path below <paramref name="root"/> into a dotted module name, or
    /// null when a folder is not a usable identifier.
    /// </summary>
    private static string? ModuleNameFor(string root, string file)
    {
        string relative = Path.GetRelativePath(root, Path.ChangeExtension(file, null));
        var segments = relative.Split(
            [Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar],
            StringSplitOptions.RemoveEmptyEntries);

        if (segments.Length == 0 || segments.Any(s => !IsIdentifier(s))) return null;
        return string.Join('.', segments);
    }

    private static bool IsIdentifier(string text) =>
        text.Length > 0 &&
        (char.IsLetter(text[0]) || text[0] == '_') &&
        text.All(c => char.IsLetterOrDigit(c) || c == '_');

    /// <summary>
    /// True for files a previous build produced. Without this, scanning a directory
    /// would feed stale object files back into the next link.
    /// </summary>
    private static bool IsBuildArtifact(string path)
    {
        string? directory = Path.GetFileName(Path.GetDirectoryName(path));
        return string.Equals(directory, "obj", StringComparison.OrdinalIgnoreCase)
            || string.Equals(directory, "bin", StringComparison.OrdinalIgnoreCase);
    }

    public CompilationResult Compile(CompilationOptions options)
    {
        var diagnostics = new DiagnosticBag();

        // --- parse -------------------------------------------------------
        var units = new List<CompilationUnitSyntax>();
        foreach (string path in options.SourcePaths)
        {
            SourceText source;
            try
            {
                source = SourceText.FromFile(path);
            }
            catch (IOException e)
            {
                return Failure($"could not read '{path}': {e.Message}");
            }

            units.Add(new Parser(source, diagnostics).ParseCompilationUnit());
        }

        if (diagnostics.HasErrors) return Failed(diagnostics);

        // --- bind --------------------------------------------------------
        var program = new Binder(diagnostics, requireEntryPoint: !options.Shared,
            inferredModules: options.InferredModules).Bind(units);
        if (diagnostics.HasErrors) return Failed(diagnostics);

        if (program.EntryPoint is null && !options.EmitIrOnly && !options.Shared)
            diagnostics.Error("SL0290", units[0].Span,
                "no entry point was found; declare 'int Main()' in one of the compiled modules, " +
                "or pass --shared to build a library instead");

        if (options.Shared && !program.Modules.SelectMany(m => m.Functions)
                .Any(f => f.Linkage == LinkageKind.ExportC))
            diagnostics.Warning("SL0291", units[0].Span,
                "this library exports nothing; mark a function 'export \"C\"' to add it to the " +
                "export table");

        if (diagnostics.HasErrors) return Failed(diagnostics);

        // --- emit --------------------------------------------------------
        string ir = new LlvmEmitter(forSharedLibrary: options.Shared).Emit(program);

        string output = options.OutputPath
            ?? DefaultOutputPath(program, options.SourcePaths, options.Shared);
        string intermediate = options.IntermediateDirectory
            ?? Path.Combine(Path.GetDirectoryName(Path.GetFullPath(output)) ?? ".", "obj");

        Directory.CreateDirectory(intermediate);
        string irPath = Path.Combine(intermediate,
            Path.GetFileNameWithoutExtension(output) + ".ll");
        File.WriteAllText(irPath, ir);

        if (options.EmitIrOnly)
            return new CompilationResult
            {
                Success = true,
                Diagnostics = diagnostics.Sorted().ToList(),
                IrPath = irPath,
                Ir = ir,
            };

        // --- assemble and link -------------------------------------------
        var toolchain = Toolchain.Locate(out string toolchainError);
        if (toolchain is null) return Failure(toolchainError);

        IReadOnlyList<string> runtimeObjects;
        try
        {
            runtimeObjects = toolchain.BuildRuntime(intermediate);
        }
        catch (Exception e) when (e is InvalidOperationException or IOException)
        {
            return Failure(e.Message);
        }

        var link = toolchain.Link(
            irPath, runtimeObjects, options.NativeInputs, output, options.OptimizationLevel,
            options.Shared);
        if (!link.Success)
            return Failure($"the native toolchain rejected the generated IR:\n{link.StandardError.TrimEnd()}\n" +
                           $"The IR is at {irPath}; this is a compiler bug, not a bug in your program.");

        if (!options.KeepIntermediates)
        {
            // The runtime object is worth caching; the IR is not, unless asked for.
            TryDelete(irPath);
            irPath = "";
        }

        // The header restates what the ABI already guarantees, so it is written
        // from the same symbols the emitter used.
        string? headerPath = null;
        if (options.HeaderPath is not null)
        {
            headerPath = Path.GetFullPath(options.HeaderPath);
            Directory.CreateDirectory(Path.GetDirectoryName(headerPath) ?? ".");
            File.WriteAllText(headerPath, CHeaderWriter.Write(program, headerPath));
        }

        return new CompilationResult
        {
            Success = true,
            Diagnostics = diagnostics.Sorted().ToList(),
            OutputPath = output,
            IrPath = irPath.Length == 0 ? null : irPath,
            Ir = ir,
            HeaderPath = headerPath,
        };
    }

    private static void TryDelete(string path)
    {
        try { File.Delete(path); } catch (IOException) { /* leaving a stale file is harmless */ }
    }

    /// <summary>
    /// Where the output goes when nothing was asked for: named after the module
    /// holding <c>Main</c>, in the directory the sources share. Naming it after
    /// whichever file happened to sort first was surprising for a directory
    /// build, where that file is rarely the interesting one.
    /// </summary>
    private static string DefaultOutputPath(
        BoundProgram program, IReadOnlyList<string> sources, bool shared)
    {
        string name = program.EntryPoint is not null
            ? program.EntryPoint.ModuleName.Split('.')[^1]
            : Path.GetFileNameWithoutExtension(sources[0]);

        string extension = shared
            ? Toolchain.SharedLibraryExtension
            : OperatingSystem.IsWindows() ? ".exe" : "";

        return Path.Combine(CommonDirectory(sources), name + extension);
    }

    /// <summary>The deepest directory containing every source file.</summary>
    private static string CommonDirectory(IReadOnlyList<string> sources)
    {
        var directories = sources
            .Select(s => Path.GetDirectoryName(Path.GetFullPath(s)) ?? ".")
            .ToList();

        string common = directories[0];
        foreach (string directory in directories.Skip(1))
        {
            while (!directory.StartsWith(common, StringComparison.OrdinalIgnoreCase))
            {
                var parent = Directory.GetParent(common);
                if (parent is null) return directories[0];
                common = parent.FullName;
            }
        }

        return common;
    }

    private static CompilationResult Failed(DiagnosticBag diagnostics) =>
        new() { Success = false, Diagnostics = diagnostics.Sorted().ToList() };

    private static CompilationResult Failure(string message) =>
        new() { Success = false, Diagnostics = [], DriverError = message };
}
