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
using System.Reflection;

namespace Stainless.Driver;

public sealed record ToolResult(int ExitCode, string StandardOutput, string StandardError)
{
    public bool Success => ExitCode == 0;
}

/// <summary>
/// The runtime built as one shared library: the file itself, and what a link
/// line should name to use it. On Windows those differ -- a link line names the
/// import library and the loader finds the DLL -- and everywhere else they are
/// the same file.
/// </summary>
public sealed record SharedRuntime(string Library, string LinkInput);

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

    private string? _targetTriple;

    /// <summary>
    /// The triple clang builds for, asked once and remembered. It decides which
    /// spelling of "discard unreferenced sections" the linker understands, and
    /// clang is the only thing that actually knows.
    /// </summary>
    private string TargetTriple =>
        _targetTriple ??= Run(ClangPath, ["-print-target-triple"]) is { Success: true } probe
            ? probe.StandardOutput.Trim()
            : "";

    /// <summary>
    /// The linker argument that drops sections nothing referenced.
    ///
    /// Nothing prunes dead code in the compiler yet, so every stdlib function is
    /// emitted whether or not a program calls it. Splitting each into its own
    /// section lets the linker do what the compiler has not: it takes about a
    /// quarter off a hello-world binary, and costs a flag.
    /// </summary>
    private string DeadStripArgument =>
        TargetTriple.Contains("windows-msvc", StringComparison.Ordinal) ? "-Wl,/OPT:REF"
        : TargetTriple.Contains("apple", StringComparison.Ordinal) ||
          TargetTriple.Contains("darwin", StringComparison.Ordinal) ? "-Wl,-dead_strip"
        : "-Wl,--gc-sections";

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
    public IReadOnlyList<string> BuildRuntime(
        string objectDirectory, bool debug = false, bool shared = false)
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

            // A debug object is a different object, so it gets a different name.
            // Sharing one would hand whichever build ran second the other's.
            // A shared one differs again: it is compiled position-independent
            // and with its exports marked, and neither is true of the other.
            string suffix = (shared ? ".so" : "") + (debug ? ".g" : "") + ".o";
            string objectFile = Path.ChangeExtension(source, suffix);
            objectFiles.Add(objectFile);

            bool changed = WriteIfChanged(source, text);
            if (!changed && !headersChanged && File.Exists(objectFile)) continue;

            List<string> arguments =
                ["-c", source, "-ffunction-sections", "-fdata-sections", "-o", objectFile];

            if (shared)
            {
                // Everything the runtime means to export says so in the header.
                // Hiding the rest keeps the library's surface the one documented
                // rather than every symbol that happened to have external
                // linkage, and lets the linker resolve the rest internally.
                arguments.Add("-DSTAINLESS_RUNTIME_BUILD");

                // Windows relocates a DLL at load time and rejects the flag;
                // everywhere else a shared object has to be built for it.
                if (!OperatingSystem.IsWindows())
                    arguments.AddRange(["-fPIC", "-fvisibility=hidden"]);
            }

            // -O0 alongside -g, because a runtime compiled at -O2 has had the
            // frames a debugger wants to show inlined away.
            arguments.InsertRange(2, debug ? ["-O0", "-g"] : ["-O2"]);

            var result = Run(ClangPath, arguments);
            if (!result.Success)
                throw new InvalidOperationException(
                    $"failed to compile the Stainless runtime ({name}):\n{result.StandardError}");
        }

        return objectFiles;
    }

    /// <summary>The file name the runtime is built under.</summary>
    public const string RuntimeName = "stainless-rt";

    /// <summary>
    /// Builds the runtime as one shared library, and returns what a link line
    /// should name to use it.
    ///
    /// On Windows that is the import library beside the DLL; everywhere else it
    /// is the shared object itself, which the linker reads directly. Both are
    /// rebuilt only when an input is newer, because every build in a session
    /// asks for this and the answer is almost always the same one.
    /// </summary>
    public SharedRuntime BuildSharedRuntime(string objectDirectory, bool debug = false)
    {
        var objects = BuildRuntime(objectDirectory, debug, shared: true);

        string library = Path.Combine(objectDirectory,
            (OperatingSystem.IsWindows() ? "" : "lib") + RuntimeName +
            (debug ? "-g" : "") + SharedLibraryExtension);

        // The import library is what a Windows link line names, and the linker
        // writes it beside the DLL rather than being told where to put it.
        string linkInput = OperatingSystem.IsWindows()
            ? Path.ChangeExtension(library, ".lib")
            : library;

        if (IsUpToDate(library, objects) && File.Exists(linkInput))
            return new SharedRuntime(library, linkInput);

        List<string> arguments = [.. objects, "-shared", "-o", library];
        if (debug) arguments.Add("-g");

        // A shared library resolves everything it needs at link time on Windows
        // and would happily leave a hole elsewhere; saying so keeps a mistake in
        // the runtime from turning into a missing symbol in someone's program.
        if (!OperatingSystem.IsWindows() && !OperatingSystem.IsMacOS())
            arguments.Add("-Wl,--no-undefined");

        var result = Run(ClangPath, arguments);
        if (!result.Success)
            throw new InvalidOperationException(
                $"failed to link the Stainless runtime:\n{result.StandardError}");

        return new SharedRuntime(library, linkInput);
    }

    /// <summary>True when <paramref name="output"/> is newer than every input.</summary>
    private static bool IsUpToDate(string output, IEnumerable<string> inputs)
    {
        if (!File.Exists(output)) return false;

        var built = File.GetLastWriteTimeUtc(output);
        return inputs.All(i => File.Exists(i) && File.GetLastWriteTimeUtc(i) <= built);
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
    /// Compiles the emitted IR and links it against the runtime, any C sources,
    /// object files or libraries the program named by path, and any it named by
    /// name for the linker to find.
    /// </summary>
    public ToolResult Link(
        string irPath,
        IReadOnlyList<string> runtimeObjects,
        IReadOnlyList<string> nativeInputs,
        string outputPath,
        int optimizationLevel,
        bool shared = false,
        bool debug = false,
        IReadOnlyList<string>? libraries = null,
        SharedRuntime? sharedRuntime = null)
    {
        List<string> arguments = [irPath];

        // One or the other: the runtime is either compiled into this binary or
        // reached in the one library everything shares. Both at once would be
        // two allocators and two sets of counts, which is the whole thing the
        // shared build exists to prevent.
        if (sharedRuntime is not null) arguments.Add(sharedRuntime.LinkInput);
        else arguments.AddRange(runtimeObjects);

        arguments.AddRange(nativeInputs);

        // Named libraries come after the objects that reference them, because a
        // static archive is searched once, in order, on every platform that
        // matters. clang spells this the same way on Windows, where -luser32
        // reaches the Windows SDK's user32.lib through the linker's own paths.
        foreach (string library in libraries ?? []) arguments.Add("-l" + library);

        // A shared library has no entry point; the linker also emits the import
        // library beside the DLL on Windows.
        if (shared) arguments.Add("-shared");

        // -g here is not about the IR, which already carries its own description.
        // It tells clang to keep it through to the binary, and on Windows to ask
        // the linker for the .pdb the debugger actually reads.
        if (debug) arguments.Add("-g");

        // The runtime sits beside whatever loaded it, so that is where a
        // binary is told to look. Windows searches its own directory already;
        // ELF and Mach-O have to be asked, and each spells it differently.
        if (sharedRuntime is not null && !OperatingSystem.IsWindows())
            arguments.Add(OperatingSystem.IsMacOS()
                ? "-Wl,-rpath,@loader_path"
                : "-Wl,-rpath,$ORIGIN");

        arguments.AddRange([
            $"-O{optimizationLevel}",
            "-o", outputPath,
            "-Wno-override-module",     // the triple is intentionally left to clang

            // One section per function and per datum, then let the linker drop
            // the ones nothing reached. A library keeps its exports either way:
            // they are roots, which is what being exported means.
            "-ffunction-sections",
            "-fdata-sections",
            DeadStripArgument,
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
