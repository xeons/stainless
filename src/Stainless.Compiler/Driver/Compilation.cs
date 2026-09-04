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

    /// <summary>
    /// Where to write the module metadata another Stainless compilation binds
    /// against. The C header and this describe the same library to two
    /// different audiences.
    /// </summary>
    public string? MetadataPath { get; init; }

    /// <summary>Metadata files describing libraries this program links against.</summary>
    public IReadOnlyList<string> References { get; init; } = [];

    public bool KeepIntermediates { get; init; }
    public bool EmitIrOnly { get; init; }

    /// <summary>
    /// Describe the program to a debugger: line tables, function names, and the
    /// name, type and stack slot of every local and parameter.
    ///
    /// It also writes the standard library's sources out beside the object
    /// files, because they are compiled from inside the compiler's own assembly
    /// and a debugger cannot step into a file that is not on disk.
    /// </summary>
    public bool Debug { get; init; }

    /// <summary>
    /// Symbols <c>#if</c> tests, from <c>-D</c>. The compiler adds the ones that
    /// describe the target on top of these, so a program never has to be told
    /// what machine it is being built for.
    /// </summary>
    public IReadOnlyList<string> Defines { get; init; } = [];

    /// <summary>
    /// Which C and C++ ABI to agree with, or null for the host's.
    ///
    /// It decides two things that must match the compiler on the other side of
    /// a boundary: how a C++ name is mangled, and how bit-fields are packed into
    /// storage units. The two ABIs differ on the second in ordinary cases, not
    /// only in corners.
    /// </summary>
    public Binding.CppAbi? CppAbi { get; init; }
}

public sealed record CompilationResult
{
    public required bool Success { get; init; }
    public required IReadOnlyList<Diagnostic> Diagnostics { get; init; }
    public string? OutputPath { get; init; }
    public string? IrPath { get; init; }
    public string? Ir { get; init; }
    public string? HeaderPath { get; init; }
    public string? MetadataPath { get; init; }

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
        // Fixed before anything is parsed, because with debug info on the
        // standard library is written here and parsed from disk rather than from
        // the compiler's own resources: a debugger cannot step into a file that
        // does not exist. `List.Add` is as much a place to stop as anything in
        // the program, and it is written in Stainless like the rest.
        string intermediate = IntermediateDirectory(options);
        string? librarySources = options.Debug ? Path.Combine(intermediate, "stdlib") : null;

        if (librarySources is not null)
        {
            try
            {
                Directory.CreateDirectory(librarySources);
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                return Failure($"could not write the standard library's sources to " +
                               $"'{librarySources}' for debugging: {e.Message}");
            }
        }

        var symbols = BuildSymbols(options);

        foreach (var (name, text) in StandardLibrary.Sources())
        {
            string path = name;

            if (librarySources is not null)
            {
                path = Path.Combine(librarySources, Path.GetFileName(name));
                if (!File.Exists(path) || File.ReadAllText(path) != text)
                    File.WriteAllText(path, text);
            }

            units.Add(new Parser(new SourceText(path, text), diagnostics, symbols)
                .ParseCompilationUnit());
        }

        // Everything after this point is the program's own, which is what a
        // library's metadata describes.
        int standardUnits = units.Count;

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

            units.Add(new Parser(source, diagnostics, symbols).ParseCompilationUnit());
        }

        if (diagnostics.HasErrors) return Failed(diagnostics);

        // --- bind --------------------------------------------------------
        var references = new List<ModuleMetadata>();
        foreach (string path in options.References)
        {
            var metadata = ModuleMetadata.Read(path, out string referenceError);
            if (metadata is null) return Failure(referenceError);
            references.Add(metadata);
        }

        var program = new Binder(
            diagnostics, requireEntryPoint: !options.Shared, references: references,
            cppAbi: options.CppAbi).Bind(units);
        if (diagnostics.HasErrors) return Failed(diagnostics);

        // Against the program's own first file rather than units[0], which is
        // the standard library's: neither of these is about a place in the
        // source, and pointing at a file nobody wrote reads as a compiler bug.
        var programSpan = units[standardUnits < units.Count ? standardUnits : 0].Span;

        if (program.EntryPoint is null && !options.EmitIrOnly && !options.Shared)
            diagnostics.Error("SL0290", programSpan,
                "no entry point was found; declare 'int Main()' in one of the compiled modules, " +
                "or pass --shared to build a library instead");

        // A library built for Stainless consumers exports its public surface
        // through the metadata, so it is not silent even with no export "C".
        if (options.Shared && options.MetadataPath is null &&
            !program.Modules.SelectMany(m => m.Functions)
                .Any(f => f.Linkage == LinkageKind.ExportC))
            diagnostics.Warning("SL0291", programSpan,
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
        var debug = options.Debug
            ? new DebugInfo(
                units[^1].Span.File,
                "Stainless " + typeof(Compilation).Assembly.GetName().Version?.ToString(3),
                codeView: OperatingSystem.IsWindows())
            : null;

        string ir = new LlvmEmitter(
            forSharedLibrary: options.Shared,
            forStainlessConsumers: options.MetadataPath is not null,
            debug: debug).Emit(program);

        string output = options.OutputPath
            ?? DefaultOutputPath(program, options.SourcePaths, options.Shared);

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
            runtimeObjects = toolchain.BuildRuntime(intermediate, options.Debug);
        }
        catch (Exception e) when (e is InvalidOperationException or IOException)
        {
            return Failure(e.Message);
        }

        var link = toolchain.Link(
            irPath, runtimeObjects, options.NativeInputs, output, options.OptimizationLevel,
            options.Shared, options.Debug);
        if (!link.Success)
            return Failure($"the native toolchain rejected the generated IR:\n{link.StandardError.TrimEnd()}\n" +
                           $"The IR is at {irPath}; this is a compiler bug, not a bug in your program.");

        // Debug info points at the .ll only for the runtime's C, but a build that
        // asked to be debuggable should keep what it described either way.
        if (!options.KeepIntermediates && !options.Debug)
        {
            // The runtime object is worth caching; the IR is not, unless asked for.
            TryDelete(irPath);
            irPath = "";
        }

        // The header restates what the ABI already guarantees, so it is written
        // from the same symbols the emitter used.
        string? headerPath = null;
        string? metadataPath = null;
        if (options.MetadataPath is not null)
        {
            metadataPath = Path.GetFullPath(options.MetadataPath);
            Directory.CreateDirectory(Path.GetDirectoryName(metadataPath) ?? ".");
            var ownModules = units
                .Skip(standardUnits)
                .Select(u => u.ModuleName?.Text)
                .OfType<string>()
                .ToHashSet(StringComparer.Ordinal);

            File.WriteAllText(metadataPath,
                MetadataWriter.Write(program, Path.GetFileName(output), ownModules, diagnostics)
                    .ToJson());
        }

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
            MetadataPath = metadataPath,
        };
    }

    private static void TryDelete(string path)
    {
        try { File.Delete(path); } catch (IOException) { /* leaving a stale file is harmless */ }
    }

    /// <summary>
    /// What <c>#if</c> can test: the target's own description, then whatever
    /// <c>-D</c> added.
    ///
    /// The built-in ones are about the machine and nothing else. A name like
    /// DEBUG is deliberately not among them: what it should mean is the
    /// programmer's business, and guessing it from an optimisation level would
    /// be a rule nobody asked for.
    /// </summary>
    private static HashSet<string> BuildSymbols(CompilationOptions options)
    {
        var symbols = new HashSet<string>(StringComparer.Ordinal) { "STAINLESS" };

        if (OperatingSystem.IsWindows()) symbols.Add("WINDOWS");
        if (OperatingSystem.IsLinux()) { symbols.Add("LINUX"); symbols.Add("UNIX"); }
        if (OperatingSystem.IsMacOS()) { symbols.Add("MACOS"); symbols.Add("UNIX"); }
        if (OperatingSystem.IsFreeBSD()) { symbols.Add("FREEBSD"); symbols.Add("UNIX"); }

        symbols.Add(System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture switch
        {
            System.Runtime.InteropServices.Architecture.X64 => "X64",
            System.Runtime.InteropServices.Architecture.Arm64 => "ARM64",
            System.Runtime.InteropServices.Architecture.X86 => "X86",
            System.Runtime.InteropServices.Architecture.Arm => "ARM",
            var other => other.ToString().ToUpperInvariant(),
        });

        foreach (string defined in options.Defines) symbols.Add(defined);
        return symbols;
    }

    /// <summary>
    /// Where object files, the generated IR and the runtime's sources go.
    ///
    /// It is derived from the options alone rather than from the output path,
    /// because a debug build needs it before the program has been bound and so
    /// before the default output name is known.
    /// </summary>
    private static string IntermediateDirectory(CompilationOptions options) =>
        options.IntermediateDirectory
        ?? Path.Combine(
            options.OutputPath is { } given
                ? Path.GetDirectoryName(Path.GetFullPath(given)) ?? "."
                : CommonDirectory(options.SourcePaths),
            "obj");

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
