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

/// <summary>
/// The parts of the standard library that are written in Stainless and shipped
/// inside the compiler.
/// </summary>
public static class StandardLibrary
{
    private const string Prefix = "Stainless.Library.";

    public static IEnumerable<(string Name, string Text)> Sources()
    {
        var assembly = System.Reflection.Assembly.GetExecutingAssembly();

        foreach (string resource in assembly.GetManifestResourceNames().Order(StringComparer.Ordinal))
        {
            if (!resource.StartsWith(Prefix, StringComparison.Ordinal)) continue;

            using var stream = assembly.GetManifestResourceStream(resource);
            if (stream is null) continue;

            using var reader = new StreamReader(stream);
            yield return ("<standard>/" + resource[Prefix.Length..], reader.ReadToEnd());
        }
    }
}

/// <summary>What a set of command-line paths expanded to.</summary>
public sealed record SourceSet
{
    public required IReadOnlyList<string> Sources { get; init; }
    public required IReadOnlyList<string> NativeInputs { get; init; }

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
    /// Expands directories into their .sl files and separates native inputs.
    ///
    /// Where a file sits has no bearing on which module it joins; that is stated
    /// in the file. Folders are for people, not for the compiler.
    /// </summary>
    public static SourceSet CollectSourceFiles(IEnumerable<string> paths)
    {
        var files = new List<string>();
        var nativeInputs = new List<string>();
        var errors = new List<string>();

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
                    .EnumerateFiles(Path.GetFullPath(path), "*", SearchOption.AllDirectories)
                    .Select(Path.GetFullPath)
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

        return new SourceSet
        {
            Sources = files.Distinct(StringComparer.OrdinalIgnoreCase).ToList(),
            NativeInputs = nativeInputs
                .Where(f => !IsBuildArtifact(f))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList(),
            Errors = errors,
        };
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

        // The standard library is ordinary Stainless, compiled with the program
        // rather than linked against it. Generics and unused types emit nothing,
        // so a program that ignores it pays nothing for it.
        foreach (var (name, text) in StandardLibrary.Sources())
            units.Add(new Parser(new SourceText(name, text), diagnostics).ParseCompilationUnit());

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
        var program = new Binder(diagnostics, requireEntryPoint: !options.Shared).Bind(units);
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

        // Static initializers run from the entry point, and a library has none.
        // Better to say so than to hand back a library whose statics are zero.
        if (options.Shared && program.Statics.Count > 0)
            diagnostics.Error("SL0380", program.Statics[0].Span,
                $"'{program.Statics[0].Name}' is a static, and a --shared library has no entry " +
                "point to initialize one from; hold the value behind an exported function " +
                "instead, or build this module into an executable");

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
