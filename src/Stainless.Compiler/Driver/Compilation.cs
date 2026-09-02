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
    public string? OutputPath { get; init; }
    public string? IntermediateDirectory { get; init; }
    public int OptimizationLevel { get; init; } = 2;
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

    /// <summary>A failure outside the source program: a missing tool, unreadable file, bad IR.</summary>
    public string? DriverError { get; init; }
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
    /// rejects anything unreadable.
    /// </summary>
    public static List<string> CollectSourceFiles(
        IEnumerable<string> paths, out List<string> nativeInputs, out List<string> errors)
    {
        var files = new List<string>();
        nativeInputs = [];
        errors = [];

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
                var all = Directory
                    .EnumerateFiles(path, "*", SearchOption.AllDirectories)
                    .OrderBy(p => p, StringComparer.Ordinal)
                    .ToList();

                var found = all
                    .Where(f => Path.GetExtension(f)
                        .Equals(SourceExtension, StringComparison.OrdinalIgnoreCase))
                    .ToList();

                if (found.Count == 0)
                    errors.Add($"no {SourceExtension} files were found under '{path}'");

                files.AddRange(found);

                // C sources sitting beside the Stainless ones belong to the same
                // program; a directory would otherwise drop them silently.
                nativeInputs.AddRange(all.Where(IsNativeInput));
            }
            else if (File.Exists(path))
            {
                files.Add(Path.GetFullPath(path));
            }
            else
            {
                errors.Add($"'{path}' does not exist");
            }
        }

        nativeInputs = nativeInputs
            .Where(f => !IsBuildArtifact(f))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        return files.Distinct(StringComparer.OrdinalIgnoreCase).ToList();
    }

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
        var program = new Binder(diagnostics).Bind(units);
        if (diagnostics.HasErrors) return Failed(diagnostics);

        if (program.EntryPoint is null && !options.EmitIrOnly)
            diagnostics.Error("SL0290", units[0].Span,
                "no entry point was found; declare 'int Main()' in one of the compiled modules");

        if (diagnostics.HasErrors) return Failed(diagnostics);

        // --- emit --------------------------------------------------------
        string ir = new LlvmEmitter().Emit(program);

        string output = options.OutputPath ?? DefaultOutputPath(options.SourcePaths[0]);
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
            irPath, runtimeObjects, options.NativeInputs, output, options.OptimizationLevel);
        if (!link.Success)
            return Failure($"the native toolchain rejected the generated IR:\n{link.StandardError.TrimEnd()}\n" +
                           $"The IR is at {irPath}; this is a compiler bug, not a bug in your program.");

        if (!options.KeepIntermediates)
        {
            // The runtime object is worth caching; the IR is not, unless asked for.
            TryDelete(irPath);
            irPath = "";
        }

        return new CompilationResult
        {
            Success = true,
            Diagnostics = diagnostics.Sorted().ToList(),
            OutputPath = output,
            IrPath = irPath.Length == 0 ? null : irPath,
            Ir = ir,
        };
    }

    private static void TryDelete(string path)
    {
        try { File.Delete(path); } catch (IOException) { /* leaving a stale file is harmless */ }
    }

    private static string DefaultOutputPath(string firstSource)
    {
        string name = Path.GetFileNameWithoutExtension(firstSource);
        string directory = Path.GetDirectoryName(Path.GetFullPath(firstSource)) ?? ".";
        return Path.Combine(directory, name + (OperatingSystem.IsWindows() ? ".exe" : ""));
    }

    private static CompilationResult Failed(DiagnosticBag diagnostics) =>
        new() { Success = false, Diagnostics = diagnostics.Sorted().ToList() };

    private static CompilationResult Failure(string message) =>
        new() { Success = false, Diagnostics = [], DriverError = message };
}
