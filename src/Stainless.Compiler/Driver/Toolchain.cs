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

    /// <summary>
    /// Writes the ARC runtime out of the compiler's own resources and compiles it
    /// to an object file, reusing the result when it is already current.
    /// </summary>
    public string BuildRuntime(string objectDirectory)
    {
        Directory.CreateDirectory(objectDirectory);

        string source = Path.Combine(objectDirectory, "stainless_rt.c");
        string objectFile = Path.Combine(objectDirectory, "stainless_rt.o");

        string text = ReadEmbeddedRuntime();
        bool sourceChanged = !File.Exists(source) || File.ReadAllText(source) != text;
        if (sourceChanged) File.WriteAllText(source, text);

        if (!sourceChanged && File.Exists(objectFile)) return objectFile;

        var result = Run(ClangPath, ["-c", source, "-O2", "-o", objectFile]);
        if (!result.Success)
            throw new InvalidOperationException(
                $"failed to compile the Stainless runtime:\n{result.StandardError}");

        return objectFile;
    }

    private static string ReadEmbeddedRuntime()
    {
        var assembly = Assembly.GetExecutingAssembly();
        const string name = "Stainless.Runtime.stainless_rt.c";

        using var stream = assembly.GetManifestResourceStream(name)
            ?? throw new InvalidOperationException(
                $"the runtime source '{name}' is missing from the compiler assembly");

        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }

    /// <summary>
    /// Compiles the emitted IR and links it against the runtime and any C sources,
    /// object files or libraries the program asked for.
    /// </summary>
    public ToolResult Link(
        string irPath,
        string runtimeObject,
        IReadOnlyList<string> nativeInputs,
        string outputPath,
        int optimizationLevel)
    {
        List<string> arguments = [irPath, runtimeObject];
        arguments.AddRange(nativeInputs);
        arguments.AddRange([
            $"-O{optimizationLevel}",
            "-o", outputPath,
            "-Wno-override-module",     // the triple is intentionally left to clang
        ]);

        return Run(ClangPath, arguments);
    }

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
