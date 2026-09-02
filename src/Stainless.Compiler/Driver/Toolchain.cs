using System.Diagnostics;
using System.Reflection;

namespace Stainless.Driver;

public sealed record ToolResult(int ExitCode, string StandardOutput, string StandardError)
{
    public bool Success => ExitCode == 0;
}

/// <summary>
/// Locates the native toolchain and drives it.
///
/// Stainless emits textual LLVM IR, so the only external tool it needs is one
/// that can turn a .ll file into an executable. clang does that directly, which
/// is why there is no dependency on llc, opt, or the LLVM C API.
/// </summary>
public sealed class Toolchain
{
    public string ClangPath { get; }

    private Toolchain(string clangPath) => ClangPath = clangPath;

    /// <summary>Returns the toolchain, or null with an explanation if clang is missing.</summary>
    public static Toolchain? Locate(out string error)
    {
        error = "";

        // An explicit override always wins.
        string? configured = Environment.GetEnvironmentVariable("STAINLESS_CLANG");
        if (!string.IsNullOrWhiteSpace(configured) && File.Exists(configured))
            return new Toolchain(configured);

        foreach (string candidate in CandidatePaths())
            if (File.Exists(candidate))
                return new Toolchain(candidate);

        error = "could not find 'clang'. Stainless emits LLVM IR and needs clang to " +
                "produce a native binary.\n" +
                "  Install it with:  winget install LLVM.LLVM\n" +
                "  Or point Stainless at an existing copy:  set STAINLESS_CLANG=C:\\path\\to\\clang.exe";
        return null;
    }

    private static IEnumerable<string> CandidatePaths()
    {
        string executable = OperatingSystem.IsWindows() ? "clang.exe" : "clang";

        foreach (string directory in (Environment.GetEnvironmentVariable("PATH") ?? "")
                     .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            string trimmed = directory.Trim('"');
            if (trimmed.Length > 0) yield return Path.Combine(trimmed, executable);
        }

        if (OperatingSystem.IsWindows())
        {
            yield return @"C:\Program Files\LLVM\bin\clang.exe";
            yield return @"C:\Program Files (x86)\LLVM\bin\clang.exe";
        }
        else
        {
            yield return "/usr/bin/clang";
            yield return "/usr/local/bin/clang";
        }
    }

    private const string RuntimeResourcePrefix = "Stainless.Runtime.";

    /// <summary>
    /// Writes the runtime out of the compiler's own resources and compiles each
    /// translation unit, reusing object files whose source has not changed.
    ///
    /// The runtime ships as several files split by feature rather than one blob,
    /// so a change to, say, the array code does not force the string code to be
    /// rebuilt, and each unit stays small enough to read in one sitting.
    /// </summary>
    public IReadOnlyList<string> BuildRuntime(string objectDirectory)
    {
        Directory.CreateDirectory(objectDirectory);

        var sources = ReadEmbeddedRuntime();
        if (sources.Count == 0)
            throw new InvalidOperationException("the runtime is missing from the compiler assembly");

        // A header change invalidates every object file, since any unit may include it.
        bool headersChanged = false;
        foreach (var (name, text) in sources.Where(s => s.Key.EndsWith(".h", StringComparison.Ordinal)))
            headersChanged |= WriteIfChanged(Path.Combine(objectDirectory, name), text);

        var objectFiles = new List<string>();

        foreach (var (name, text) in sources
                     .Where(s => s.Key.EndsWith(".c", StringComparison.Ordinal))
                     .OrderBy(s => s.Key, StringComparer.Ordinal))
        {
            string source = Path.Combine(objectDirectory, name);
            string objectFile = Path.ChangeExtension(source, ".o");
            objectFiles.Add(objectFile);

            bool changed = WriteIfChanged(source, text);
            if (!changed && !headersChanged && File.Exists(objectFile)) continue;

            var result = Run(ClangPath, ["-c", source, "-O2", "-o", objectFile]);
            if (!result.Success)
                throw new InvalidOperationException(
                    $"failed to compile the Stainless runtime ({name}):\n{result.StandardError}");
        }

        return objectFiles;
    }

    /// <summary>Writes the file only when it differs, and reports whether it did.</summary>
    private static bool WriteIfChanged(string path, string text)
    {
        if (File.Exists(path) && File.ReadAllText(path) == text) return false;
        File.WriteAllText(path, text);
        return true;
    }

    private static Dictionary<string, string> ReadEmbeddedRuntime()
    {
        var assembly = Assembly.GetExecutingAssembly();
        var sources = new Dictionary<string, string>(StringComparer.Ordinal);

        foreach (string resource in assembly.GetManifestResourceNames())
        {
            if (!resource.StartsWith(RuntimeResourcePrefix, StringComparison.Ordinal)) continue;

            using var stream = assembly.GetManifestResourceStream(resource);
            if (stream is null) continue;

            using var reader = new StreamReader(stream);
            sources[resource[RuntimeResourcePrefix.Length..]] = reader.ReadToEnd();
        }

        return sources;
    }

    /// <summary>
    /// Compiles the emitted IR and links it against the runtime and any C sources,
    /// object files or libraries the program asked for.
    /// </summary>
    public ToolResult Link(
        string irPath,
        IReadOnlyList<string> runtimeObjects,
        IReadOnlyList<string> nativeInputs,
        string outputPath,
        int optimizationLevel,
        bool shared = false)
    {
        List<string> arguments = [irPath];
        arguments.AddRange(runtimeObjects);
        arguments.AddRange(nativeInputs);

        // A shared library has no entry point; the linker also emits the import
        // library beside the DLL on Windows.
        if (shared) arguments.Add("-shared");

        arguments.AddRange([
            $"-O{optimizationLevel}",
            "-o", outputPath,
            "-Wno-override-module",     // the triple is intentionally left to clang
        ]);

        return Run(ClangPath, arguments);
    }

    /// <summary>The conventional shared-library extension for this platform.</summary>
    public static string SharedLibraryExtension =>
        OperatingSystem.IsWindows() ? ".dll" : OperatingSystem.IsMacOS() ? ".dylib" : ".so";

    public static ToolResult Run(string executable, IReadOnlyList<string> arguments)
    {
        var startInfo = new ProcessStartInfo(executable)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        foreach (string argument in arguments) startInfo.ArgumentList.Add(argument);

        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException($"could not start '{executable}'");

        string output = process.StandardOutput.ReadToEnd();
        string error = process.StandardError.ReadToEnd();
        process.WaitForExit();

        return new ToolResult(process.ExitCode, output, error);
    }
}
