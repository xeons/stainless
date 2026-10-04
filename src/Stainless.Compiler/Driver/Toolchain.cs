// Stainless - an experimental general-purpose language.
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
using System.Globalization;
using System.Reflection;
using System.Text.RegularExpressions;

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

    /// <summary>
    /// What marks an Apple framework in a library list: <c>framework:AppKit</c>
    /// links with <c>-framework AppKit</c>. One list for both keeps a
    /// project's overlay, a pragma and the command line saying it one way.
    /// </summary>
    public const string FrameworkPrefix = "framework:";

    /// <summary>
    /// Homebrew's <c>lib</c>, which a Darwin link searches for a named library,
    /// or null. ld64 searches <c>/usr/local/lib</c> on its own, which covers an
    /// Intel Mac; Apple silicon's Homebrew is in <c>/opt/homebrew</c>, which it
    /// does not.
    /// </summary>
    public string? HomebrewLibraryDirectory { get; }

    private Toolchain(string clangPath, string? homebrewLibraryDirectory = null)
    {
        ClangPath = clangPath;
        HomebrewLibraryDirectory = homebrewLibraryDirectory;
    }

    /// <summary>
    /// <c>--target=</c> where the build names a triple, and nothing otherwise.
    ///
    /// A native build names none: clang's default is the target whose headers
    /// and libraries are certainly installed. A build is cross when either the
    /// architecture or the operating system differs from the host.
    ///
    /// Darwin always names one. Its triple carries the deployment version, and
    /// the program and the runtime MUST agree on it.
    ///
    /// A Darwin build on a Mac with <c>SDKROOT</c> set names that SDK too.
    /// Apple's clang reads it on its own; Homebrew's has the Command Line
    /// Tools' SDK in its configuration file, which only an explicit
    /// <c>-isysroot</c> overrides. The headers and the linker MUST come from
    /// one release: a newer SDK's clang emits stubs an older ld cannot make.
    /// </summary>
    public static IReadOnlyList<string> TargetArgumentsFor(
        Binding.TargetPlatform target, Binding.TargetPlatform host, string? sdkRoot = null)
    {
        List<string> arguments = [];
        if (NamesTriple(target, host))
            arguments.Add("--target=" + target.Triple);

        if (target.Cpu is { } cpu)
            arguments.Add("-march=" + cpu);

        if (target.IsDarwin && host.IsDarwin && !string.IsNullOrWhiteSpace(sdkRoot))
            arguments.AddRange(["-isysroot", sdkRoot]);

        return arguments;
    }

    private static bool NamesTriple(Binding.TargetPlatform target, Binding.TargetPlatform host) =>
        target.IsDarwin || target.Architecture != host.Architecture || target.Os != host.Os;

    private static IReadOnlyList<string> TargetArguments =>
        TargetArgumentsFor(Binding.TargetPlatform.Current, Binding.TargetPlatform.Host,
                           Environment.GetEnvironmentVariable("SDKROOT"));

    /// <summary>
    /// The triple this build actually uses: the one named on the command line
    /// when there is one, and clang's own default when there is not.
    /// </summary>
    private string EffectiveTriple =>
        NamesTriple(Binding.TargetPlatform.Current, Binding.TargetPlatform.Host)
            ? Binding.TargetPlatform.Current.Triple
            : TargetTriple;

    private string? _targetTriple;

    /// <summary>
    /// The triple clang builds for by default, asked once and remembered. It
    /// says which Windows linker flavour is in use, and clang is the only thing
    /// that actually knows.
    /// </summary>
    private string TargetTriple =>
        _targetTriple ??= Run(ClangPath, ["-print-target-triple"]) is { Success: true } probe
            ? probe.StandardOutput.Trim()
            : "";

    /// <summary>
    /// The linker argument that drops sections nothing referenced.
    ///
    /// Every stdlib function is emitted whether or not a program calls it. At
    /// -O2 LLVM deletes the internal ones nothing references; at -O0 it keeps
    /// them all, and a section per function lets the linker drop them instead.
    /// </summary>
    private string DeadStripArgument =>
        Binding.TargetPlatform.Current.IsDarwin ? "-Wl,-dead_strip"
        : EffectiveTriple.Contains("windows-msvc", StringComparison.Ordinal) ? "-Wl,/OPT:REF"
        : "-Wl,--gc-sections";

    /// <summary>Returns the toolchain, or null with an explanation if clang is missing.</summary>
    public static Toolchain? Locate(out string error)
    {
        error = "";

        // An explicit override always wins.
        string? configured = Environment.GetEnvironmentVariable("STAINLESS_CLANG");
        if (!string.IsNullOrWhiteSpace(configured) && File.Exists(configured))
            return new Toolchain(configured, FindHomebrewLibraryDirectory());

        string? tooOld = null;
        foreach (string candidate in CandidatePaths())
        {
            if (!File.Exists(candidate))
                continue;

            // Only a Mac is checked: /usr/bin/clang there is Apple's, and it
            // can be older than the IR this compiler writes.
            if (OperatingSystem.IsMacOS() &&
                !(Run(candidate, ["--version"]) is { Success: true } version &&
                  IsSupportedClangVersion(version.StandardOutput)))
            {
                tooOld ??= candidate;
                continue;
            }

            return new Toolchain(candidate, FindHomebrewLibraryDirectory());
        }

        error = MissingClang(tooOld);
        return null;
    }

    /// <summary>The toolchain for a clang already found, without looking for one.</summary>
    public static Toolchain FromClang(string clangPath, string? homebrewLibraryDirectory = null) =>
        new(clangPath, homebrewLibraryDirectory);

    /// <summary>
    /// <c>$HOMEBREW_PREFIX/lib</c>, else <c>/opt/homebrew/lib</c>, where it
    /// exists on a Mac; null anywhere else.
    /// </summary>
    private static string? FindHomebrewLibraryDirectory()
    {
        if (!OperatingSystem.IsMacOS())
            return null;

        string? prefix = Environment.GetEnvironmentVariable("HOMEBREW_PREFIX");
        string directory = Path.Combine(
            string.IsNullOrWhiteSpace(prefix) ? "/opt/homebrew" : prefix, "lib");
        return Directory.Exists(directory) ? directory : null;
    }

    /// <summary>
    /// Whether <c>clang --version</c> describes LLVM 16 or later. Apple numbers
    /// its clang apart from LLVM, and its 15 is LLVM's 16.
    /// </summary>
    public static bool IsSupportedClangVersion(string versionOutput)
    {
        var match = Regex.Match(
            versionOutput, @"(Apple )?clang version (\d+)");
        if (!match.Success)
            return false;

        int major = int.Parse(match.Groups[2].Value, CultureInfo.InvariantCulture);
        return major >= (match.Groups[1].Success ? 15 : 16);
    }

    /// <summary>What to tell someone whose machine has no usable clang.</summary>
    private static string MissingClang(string? tooOld)
    {
        const string why = "Stainless emits LLVM IR and needs clang to produce a native binary.\n";

        if (OperatingSystem.IsMacOS())
            return "could not find a clang from LLVM 16 or later. " + why +
                   (tooOld is null ? "" : $"  '{tooOld}' is older than that.\n") +
                   "  Install Homebrew's with:  brew install llvm\n" +
                   "  Or point Stainless at an existing copy:  " +
                   "export STAINLESS_CLANG=/opt/homebrew/opt/llvm/bin/clang";

        if (OperatingSystem.IsWindows())
            return "could not find 'clang'. " + why +
                   "  Install it with:  winget install LLVM.LLVM\n" +
                   "  Or point Stainless at an existing copy:  set STAINLESS_CLANG=C:\\path\\to\\clang.exe";

        return "could not find 'clang'. " + why +
               "  On Debian and Ubuntu install it with:  sudo apt install clang\n" +
               "  Or point Stainless at an existing copy:  export STAINLESS_CLANG=/path/to/clang";
    }

    private static IEnumerable<string> CandidatePaths()
    {
        string executable = OperatingSystem.IsWindows() ? "clang.exe" : "clang";

        // Homebrew's LLVM before PATH, which always holds Apple's clang.
        if (OperatingSystem.IsMacOS())
        {
            yield return "/opt/homebrew/opt/llvm/bin/clang";
            yield return "/usr/local/opt/llvm/bin/clang";
        }

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

        if (OperatingSystem.IsMacOS() && FindWithXcrun("clang") is { } apple)
            yield return apple;
    }

    /// <summary>Where the Xcode tools say <paramref name="tool"/> is, or null.</summary>
    private static string? FindWithXcrun(string tool)
    {
        try
        {
            return Run("/usr/bin/xcrun", ["-f", tool]) is { Success: true } found
                ? found.StandardOutput.Trim()
                : null;
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return null;
        }
    }

    private string? _resourceCompilerPath;
    private bool _lookedForResourceCompiler;

    /// <summary>
    /// The Windows resource compiler, or null when there is none to be found.
    ///
    /// Looked for beside clang before anywhere else, because llvm-rc ships in
    /// the same bin directory as the clang that is already driving this build --
    /// so the copy beside it is the copy that matches, and an older one earlier
    /// on PATH is not.
    ///
    /// Null rather than an error, because a missing resource compiler is only a
    /// problem for a program that has a .rc in it, and most do not.
    /// </summary>
    public string? ResourceCompilerPath
    {
        get
        {
            if (_lookedForResourceCompiler) return _resourceCompilerPath;
            _lookedForResourceCompiler = true;

            string? configured = Environment.GetEnvironmentVariable("STAINLESS_RC");
            if (!string.IsNullOrWhiteSpace(configured) && File.Exists(configured))
                return _resourceCompilerPath = configured;

            foreach (string candidate in ResourceCompilerCandidates())
                if (File.Exists(candidate))
                    return _resourceCompilerPath = candidate;

            return _resourceCompilerPath = null;
        }
    }

    private IEnumerable<string> ResourceCompilerCandidates()
    {
        string executable = OperatingSystem.IsWindows() ? "llvm-rc.exe" : "llvm-rc";

        // Beside clang, and beside what clang *resolves to*. Debian and Ubuntu
        // put the real toolchain in /usr/lib/llvm-21/bin and leave a symlink at
        // /usr/bin/clang; llvm-rc is in the first and not the second, so
        // following the link is the difference between finding it and not.
        foreach (string near in new[] { ClangPath, RealPath(ClangPath) })
            if (Path.GetDirectoryName(near) is { Length: > 0 } beside)
                yield return Path.Combine(beside, executable);

        foreach (string directory in (Environment.GetEnvironmentVariable("PATH") ?? "")
                     .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            string trimmed = directory.Trim('"');
            if (trimmed.Length == 0) continue;

            yield return Path.Combine(trimmed, executable);

            // Those distributions also ship the tools under a versioned name,
            // so `llvm-rc-21` is on PATH where plain `llvm-rc` is not.
            if (!OperatingSystem.IsWindows())
                for (int version = 30; version >= 15; version -= 1)
                    yield return Path.Combine(trimmed, $"llvm-rc-{version}");
        }

        if (OperatingSystem.IsWindows())
        {
            yield return @"C:\Program Files\LLVM\bin\llvm-rc.exe";
            yield return @"C:\Program Files (x86)\LLVM\bin\llvm-rc.exe";
        }
    }

    /// <summary>What a path points at once symbolic links are followed.</summary>
    private static string RealPath(string path)
    {
        try
        {
            return File.ResolveLinkTarget(path, returnFinalTarget: true)?.FullName ?? path;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return path;
        }
    }

    /// <summary>What to tell someone whose program has a .rc and whose machine has no llvm-rc.</summary>
    public static string MissingResourceCompiler => OperatingSystem.IsWindows()
        ? WindowsMissingResourceCompiler
        : "could not find 'llvm-rc'. A .rc file is a resource script, and compiling one needs it.\n" +
          "  It ships with LLVM, beside the clang this build already found. On Debian and Ubuntu\n" +
          "  it is in the llvm package for that version:  sudo apt install llvm\n" +
          "  Or point Stainless at an existing copy:  export STAINLESS_RC=/path/to/llvm-rc";

    private const string WindowsMissingResourceCompiler =
        "could not find 'llvm-rc'. A .rc file is a Windows resource script, and compiling one needs it.\n" +
        "  It ships with LLVM, in the same directory as the clang this build already found:\n" +
        "    winget install LLVM.LLVM\n" +
        @"  Or point Stainless at an existing copy:  set STAINLESS_RC=C:\path\to\llvm-rc.exe";

    /// <summary>
    /// Compiles a Windows resource script to the .res an executable carries.
    ///
    /// There is no cvtres step and no dependency on a particular linker: clang
    /// takes a .res on its command line and hands it through, and every linker
    /// that can produce a PE knows how to fold one in.
    ///
    /// llvm-rc resolves an <c>#include</c>, and a bitmap or manifest named by a
    /// relative path, against the script's own directory rather than the
    /// working directory. That is what lets a script keep its files beside it
    /// and still be built from anywhere, and it is the one place where llvm-rc
    /// deliberately differs from Microsoft's rc.exe.
    /// </summary>
    public ToolResult CompileResource(
        string scriptPath, string outputPath, Binding.TargetPlatform target,
        IEnumerable<string>? defines = null)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outputPath)) ?? ".");

        List<string> arguments = [];

        // The same symbols `#if` tests in Stainless and `-D` defines in C, so
        // one set of names describes the program to all three languages in it.
        foreach (string define in defines ?? []) arguments.Add("-D" + define);

        // What the Windows headers call this target, for a script that asks.
        arguments.Add(target.PointerWidth == 8 ? "-D_WIN64" : "-D_WIN32");

        // llvm-rc reads an argument starting with '/' as an option on every
        // host, so without the `--` a script under /Users is `/U` with a value.
        arguments.AddRange(["-fo", outputPath, "--", scriptPath]);

        return Run(ResourceCompilerPath!, arguments);
    }

    private const string RuntimeResourcePrefix = "Stainless.Runtime.";

    /// <summary>
    /// What a runtime object's name ends in, so that each build of it has its
    /// own file beside the one shared source.
    ///
    /// A debug, shared or leak-checking object is a different object. So is
    /// one for another target, and it is named by the whole target: an object
    /// for x64 Windows and one for x64 Linux differ, and a linker handed the
    /// wrong one reports an unknown file type. Any build that names a triple
    /// names it here, Darwin's included, so an object compiled without its
    /// deployment version is never reused.
    /// </summary>
    public static string RuntimeObjectSuffix(
        Binding.TargetPlatform target, Binding.TargetPlatform host,
        bool shared, bool debug, bool leakCheck) =>
        (NamesTriple(target, host) ? "." + target.Name : "")
        + (shared ? ".so" : "") + (debug ? ".g" : "") + (leakCheck ? ".leak" : "") + ".o";

    /// <summary>
    /// Writes the runtime out of the compiler's own resources and compiles each
    /// translation unit, reusing object files whose source has not changed.
    ///
    /// The runtime ships as several files split by feature rather than one blob,
    /// so a change to, say, the array code does not force the string code to be
    /// rebuilt, and each unit stays small enough to read in one sitting.
    /// </summary>
    public IReadOnlyList<string> BuildRuntime(
        string objectDirectory, bool debug = false, bool shared = false,
        bool leakCheck = false)
    {
        Directory.CreateDirectory(objectDirectory);

        var sources = ReadEmbeddedRuntime();
        if (sources.Count == 0)
            throw new InvalidOperationException("the runtime is missing from the compiler assembly");

        // A header change invalidates every object file, since any unit may
        // include it -- so every object is checked against all of them below.
        var headers = new List<string>();
        foreach (var (name, text) in sources.Where(s => s.Key.EndsWith(".h", StringComparison.Ordinal)))
        {
            string header = Path.Combine(objectDirectory, name);
            WriteIfChanged(header, text);
            headers.Add(header);
        }

        var objectFiles = new List<string>();

        foreach (var (name, text) in sources
                     .Where(s => s.Key.EndsWith(".c", StringComparison.Ordinal))
                     .OrderBy(s => s.Key, StringComparer.Ordinal))
        {
            string source = Path.Combine(objectDirectory, name);

            var target = Binding.TargetPlatform.Current;
            string suffix = RuntimeObjectSuffix(
                target, Binding.TargetPlatform.Host, shared, debug, leakCheck);
            string objectFile = Path.ChangeExtension(source, suffix);
            objectFiles.Add(objectFile);

            WriteIfChanged(source, text);

            // **Compared by time, not by "did this call write it".** That was
            // the test, and it is wrong the moment one object directory holds
            // two builds: the suffix above gives debug, shared and each target
            // an object of their own, but they all share the one `.c` on disk.
            // So a debug build after a compiler upgrade rewrote `process.c`,
            // rebuilt `process.g.o`, and left the release build to find an
            // unchanged source beside its own stale `process.o` -- which it
            // kept, and which the linker then reported as an undefined symbol
            // in a function that plainly exists. Whether *this* object is
            // older than the source is a question about this object, and
            // survives another build having asked it first.
            if (IsUpToDate(objectFile, [source, .. headers])) continue;

            List<string> arguments =
                [.. TargetArguments,
                 "-c", source, "-ffunction-sections", "-fdata-sections", "-o", objectFile];

            if (shared)
            {
                // Everything the runtime means to export says so in the header.
                // Hiding the rest keeps the library's surface the one documented
                // rather than every symbol that happened to have external
                // linkage, and lets the linker resolve the rest internally.
                arguments.Add("-DSTAINLESS_RUNTIME_BUILD");

                // Windows relocates a DLL at load time and rejects the flag;
                // everywhere else a shared object has to be built for it. The
                // question is about the binary being produced, so it is the
                // target's to answer and not the machine's.
                if (!target.IsWindows)
                    arguments.AddRange(["-fPIC", "-fvisibility=hidden"]);
            }

            // Every reference-counted allocation records itself and every free
            // forgets itself, and what is left when the program ends is
            // reported. Off, the calls are not compiled at all.
            if (leakCheck) arguments.Add("-DSL_LEAK_CHECK");

            // -O0 alongside -g, because a runtime compiled at -O2 has had the
            // frames a debugger wants to show inlined away.
            arguments.AddRange(debug ? ["-O0", "-g"] : ["-O2"]);

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
    /// The name of one build of the shared runtime, without prefix or extension.
    ///
    /// Each variant is a different library to the loader. Two binaries in one
    /// process MUST agree on it, or each loads its own and there are two
    /// runtimes again; the metadata records it so a consumer can check.
    /// </summary>
    public static string SharedRuntimeName(bool debug, bool leakCheck) =>
        RuntimeName + (debug ? "-g" : "") + (leakCheck ? "-leak" : "");

    /// <summary>
    /// Builds the runtime as one shared library, and returns what a link line
    /// should name to use it.
    ///
    /// On Windows that is the import library beside the DLL; everywhere else it
    /// is the shared object itself, which the linker reads directly. Both are
    /// rebuilt only when an input is newer, because every build in a session
    /// asks for this and the answer is almost always the same one.
    /// </summary>
    public SharedRuntime BuildSharedRuntime(
        string objectDirectory, bool debug = false, bool leakCheck = false)
    {
        var objects = BuildRuntime(objectDirectory, debug, shared: true, leakCheck: leakCheck);

        var target = Binding.TargetPlatform.Current;
        string library = Path.Combine(objectDirectory,
            SharedLibraryFileName(SharedRuntimeName(debug, leakCheck), target));
        string linkInput = LinkInputFor(library, target);

        var arguments = SharedRuntimeLinkArguments(objects, library, debug);

        // The link line is part of what the library is, so one linked by a
        // different line is out of date however new it is.
        string stamp = library + ".link";
        string line = string.Join("\n", arguments);
        if (IsUpToDate(library, objects) && File.Exists(linkInput) &&
            File.Exists(stamp) && File.ReadAllText(stamp) == line)
            return new SharedRuntime(library, linkInput);

        var result = Run(ClangPath, arguments);
        if (!result.Success)
            throw new InvalidOperationException(
                $"failed to link the Stainless runtime:\n{result.StandardError}");

        File.WriteAllText(stamp, line);
        return new SharedRuntime(library, linkInput);
    }

    /// <summary>
    /// The clang command line that links the shared runtime from its objects,
    /// for the current target.
    /// </summary>
    public IReadOnlyList<string> SharedRuntimeLinkArguments(
        IReadOnlyList<string> objects, string library, bool debug)
    {
        var target = Binding.TargetPlatform.Current;

        List<string> arguments =
            [.. TargetArguments, .. objects, SharedLibraryFlag(target), "-o", library];
        if (debug) arguments.Add("-g");

        // A shared library resolves everything it needs at link time on Windows
        // and Darwin, and would happily leave a hole on Linux; saying so keeps a
        // mistake in the runtime from turning into a missing symbol in someone's
        // program.
        if (target.IsLinux)
            arguments.Add("-Wl,--no-undefined");

        // A binary records the name a library gives itself, or the path it was
        // linked by when it gives none. Each build links the copy in its own
        // intermediate directory, so without a name a program and its library
        // record two paths and the loader maps two runtimes. By name, the copy
        // beside the binary is found through the rpath Link writes, and a
        // second binary asking for the same name gets the one already loaded.
        // Windows matches a DLL by its file name already.
        if (LibraryNameArgument(target, library) is { } name)
            arguments.Add(name);

        return arguments;
    }

    /// <summary>What tells clang to link a shared library rather than a program.</summary>
    private static string SharedLibraryFlag(Binding.TargetPlatform target) =>
        target.IsDarwin ? "-dynamiclib" : "-shared";

    /// <summary>
    /// The name a shared library records for itself, so that a consumer finds
    /// it by name wherever the two are put together; null on Windows, where a
    /// DLL is found by its file name.
    /// </summary>
    private static string? LibraryNameArgument(Binding.TargetPlatform target, string library) =>
        target.Os switch
        {
            Binding.TargetOS.MacOS => "-Wl,-install_name,@rpath/" + Path.GetFileName(library),
            Binding.TargetOS.Linux => "-Wl,-soname," + Path.GetFileName(library),
            _ => null,
        };

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
    /// Compiles one part of a divided program to an object file, for
    /// <see cref="Link"/> to take in place of the IR.
    /// </summary>
    public ToolResult CompilePart(string irPath, string objectPath, int optimizationLevel) =>
        Run(ClangPath, [
            .. TargetArguments,
            "-c", irPath,
            $"-O{optimizationLevel}",
            "-o", objectPath,
            "-Wno-override-module",
            "-ffunction-sections",
            "-fdata-sections",
        ]);

    /// <summary>
    /// Compiles the emitted IR -- or takes the objects its parts were compiled
    /// to -- and links it against the runtime, any C sources, object files or
    /// libraries the program named by path, and any it named by name for the
    /// linker to find.
    /// </summary>
    public ToolResult Link(
        IReadOnlyList<string> program,
        IReadOnlyList<string> runtimeObjects,
        IReadOnlyList<string> nativeInputs,
        string outputPath,
        int optimizationLevel,
        bool shared = false,
        bool debug = false,
        IReadOnlyList<string>? libraries = null,
        SharedRuntime? sharedRuntime = null,
        string? moduleDefinition = null,
        bool loadsLibrariesBeside = false) =>
        Run(ClangPath, LinkArguments(
            program, runtimeObjects, nativeInputs, outputPath, optimizationLevel, shared,
            debug, libraries, sharedRuntime, moduleDefinition, loadsLibrariesBeside));

    /// <summary>The clang command line <see cref="Link"/> runs, for the current target.</summary>
    public IReadOnlyList<string> LinkArguments(
        IReadOnlyList<string> program,
        IReadOnlyList<string> runtimeObjects,
        IReadOnlyList<string> nativeInputs,
        string outputPath,
        int optimizationLevel,
        bool shared = false,
        bool debug = false,
        IReadOnlyList<string>? libraries = null,
        SharedRuntime? sharedRuntime = null,
        string? moduleDefinition = null,
        bool loadsLibrariesBeside = false)
    {
        var target = Binding.TargetPlatform.Current;

        // The IR is compiled in this same invocation, which is what makes
        // clang's Darwin driver run dsymutil after a -g link. Without that the
        // DWARF would stay in a temporary object clang deletes.
        List<string> arguments = [.. TargetArguments, .. program];

        // The lld-link beside clang rather than whichever linker clang would
        // pick, which before clang 22 is Visual Studio's link.exe wherever
        // Visual Studio is installed. The two disagree: link.exe drops a
        // resource that holds no bytes, so the same program found it or not by
        // what else was on the machine.
        if (target.IsWindows && EffectiveTriple.Contains("windows-msvc", StringComparison.Ordinal) &&
            HasLldLinkBesideClang)
            arguments.Add("-fuse-ld=lld");

        // 32-bit Windows keeps the printf family inline in <stdio.h>, so a
        // program that calls one has no symbol to link against: the UCRT
        // import library exports `printf` for x64 and `_printf` for nothing.
        // This is the compatibility library that defines them out of line, and
        // it is what a C program built for the same target gets too.
        if (target.Architecture == Binding.TargetArch.X86 && target.IsWindows)
            arguments.Add("-llegacy_stdio_definitions");

        // 128-bit division and the conversions between int128 and the floats
        // are calls into compiler-rt, which the MSVC runtime has not got and
        // every other target's C library carries. Asked only where LLVM ships
        // the library for this architecture, so an install without it still
        // links whatever does not need it.
        if (target.IsWindows && EffectiveTriple.Contains("windows-msvc", StringComparison.Ordinal) &&
            HasCompilerRtBuiltins)
            arguments.Add("--rtlib=compiler-rt");

        // One or the other: the runtime is either compiled into this binary or
        // reached in the one library everything shares. Both at once would be
        // two allocators and two sets of counts, which is the whole thing the
        // shared build exists to prevent.
        if (sharedRuntime is not null) arguments.Add(sharedRuntime.LinkInput);
        else arguments.AddRange(runtimeObjects);

        // Objective-C beside a Stainless program is counted as Stainless is,
        // so its objects and the program's agree about who owns what.
        if (nativeInputs.Any(i => i.EndsWith(".m", StringComparison.OrdinalIgnoreCase) ||
                                  i.EndsWith(".mm", StringComparison.OrdinalIgnoreCase)))
            arguments.Add("-fobjc-arc");

        arguments.AddRange(nativeInputs);

        // Named libraries come after the objects that reference them, because a
        // static archive is searched once, in order, on every platform that
        // matters. clang spells this the same way on Windows, where -luser32
        // reaches the Windows SDK's user32.lib through the linker's own paths.
        if (target.IsDarwin && HomebrewLibraryDirectory is { } homebrew && libraries is { Count: > 0 })
            arguments.Add("-L" + homebrew);
        foreach (string library in libraries ?? [])
        {
            if (library.StartsWith(FrameworkPrefix, StringComparison.Ordinal))
                arguments.AddRange(["-framework", library[FrameworkPrefix.Length..]]);
            else
                arguments.Add("-l" + library);
        }

        // Windows puts the maths and the threads in the C runtime; ELF systems
        // keep libm separate to this day, and kept libpthread separate until
        // glibc 2.34. `Standard.Math` declares sqrt and the rest `extern "C"`,
        // so a program that touches any of them fails to link without this --
        // and `--as-needed`, which is the default on every distribution that
        // matters, drops whichever of the two nothing reached. Darwin's SDK
        // has both as stubs over libSystem.
        if (!target.IsWindows) arguments.AddRange(["-lm", "-lpthread"]);

        // A shared library has no entry point; the linker also emits the import
        // library beside the DLL on Windows.
        if (shared) arguments.Add(SharedLibraryFlag(target));

        // A module definition file, which names exports independently of what
        // the symbols are called. Only ever written where the two differ; see
        // ModuleDefinition. Only a PE linker reads one.
        if (moduleDefinition is not null && target.Format == Binding.ObjectFormat.Coff)
            arguments.Add("-Wl,/DEF:" + moduleDefinition);

        // -g here is not about the IR, which already carries its own description.
        // It tells clang to keep it through to the binary: on Windows by asking
        // the linker for the .pdb, and on Darwin by running dsymutil.
        if (debug) arguments.Add("-g");

        // The runtime and any Stainless library sit beside whatever loaded
        // them, so that is where a binary is told to look. Windows searches its
        // own directory already; ELF and Mach-O have to be asked, and each
        // spells it differently.
        if ((sharedRuntime is not null || loadsLibrariesBeside) && !target.IsWindows)
            arguments.Add(target.IsDarwin
                ? "-Wl,-rpath,@loader_path"
                : "-Wl,-rpath,$ORIGIN");

        // A library named by its file name rather than by the path it was
        // linked from, so a consumer finds it wherever the two are put
        // together, as a DLL is found on Windows.
        if (shared && LibraryNameArgument(target, outputPath) is { } name)
            arguments.Add(name);

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

        return arguments;
    }

    /// <summary>
    /// Compiles IR to an object file for a target, and does not link it.
    ///
    /// It is what a target this machine cannot finish a build for still allows.
    /// LLVM's verifier runs over the whole module and the back end lowers every
    /// instruction in it, so a signature the target cannot express is a failure
    /// here rather than a belief -- and that is most of what a calling
    /// convention is. Linking would need that system's C library and running
    /// would need its processor; neither is a reason to leave the IR unchecked.
    /// </summary>
    public ToolResult Assemble(
        string irPath, string objectPath, Binding.TargetPlatform target) =>
        Run(ClangPath, [
            "--target=" + target.Triple,
            .. target.Cpu is { } cpu ? ["-march=" + cpu] : Array.Empty<string>(),
            "-c", irPath,
            "-o", objectPath,
            "-Wno-override-module",
        ]);

    /// <summary>Whether <c>lld-link</c> ships beside clang, as it does in LLVM's Windows installer.</summary>
    private bool? _hasCompilerRtBuiltins;

    /// <summary>Whether clang has compiler-rt's builtins library for the target, asked once.</summary>
    private bool HasCompilerRtBuiltins => _hasCompilerRtBuiltins ??= AskCompilerRtBuiltins();

    private bool AskCompilerRtBuiltins()
    {
        try
        {
            var asked = Run(ClangPath, [.. TargetArguments, "--rtlib=compiler-rt", "-print-libgcc-file-name"]);
            string path = asked.StandardOutput.Trim();
            return path.Length > 0 && File.Exists(path);
        }
        catch (Exception e) when (e is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            return false;
        }
    }

    private bool HasLldLinkBesideClang =>
        new[] { ClangPath, RealPath(ClangPath) }
            .Select(Path.GetDirectoryName)
            .Any(beside => beside is { Length: > 0 } && File.Exists(Path.Combine(beside, "lld-link.exe")));

    private string? _optPath;
    private bool _lookedForOpt;

    /// <summary>
    /// LLVM's <c>opt</c>, from the directory clang is in or the one it
    /// resolves to, or null. Nowhere else: an <c>opt</c> from another LLVM
    /// judges the IR by a different version's rules. The Windows installer
    /// ships none, and Debian's LLVM ships one beside its clang.
    /// </summary>
    public string? OptPath
    {
        get
        {
            if (_lookedForOpt) return _optPath;
            _lookedForOpt = true;

            string executable = OperatingSystem.IsWindows() ? "opt.exe" : "opt";
            foreach (string near in new[] { ClangPath, RealPath(ClangPath) })
            {
                if (Path.GetDirectoryName(near) is not { Length: > 0 } beside)
                    continue;

                string candidate = Path.Combine(beside, executable);
                if (File.Exists(candidate))
                    return _optPath = candidate;
            }

            return _optPath = null;
        }
    }

    /// <summary>
    /// Runs LLVM's verifier over a module, and returns what it found wrong, or
    /// null when nothing was.
    ///
    /// <c>opt -passes=verify</c> where it is installed. Otherwise clang's own
    /// compiler, <c>-cc1</c>, reading the module and emitting nothing. It MUST
    /// be <c>-cc1</c> and not the driver: a release build of the driver passes
    /// <c>-disable-llvm-verifier</c>, and before clang 21 nothing else verified
    /// IR it read, so clang 18 compiles a broken module without a word. Both
    /// take about a tenth of a second on a module holding the whole standard
    /// library.
    ///
    /// Invalid debug information is not an error to either tool. It is
    /// stripped with a warning and the build goes on without it, so that
    /// warning is a failure here.
    /// </summary>
    public IrFault? VerifyIr(string ir)
    {
        var result = OptPath is { } opt
            ? Run(opt, ["-passes=verify", "-disable-output", "-"], ir)
            : Run(ClangPath, [
                "-cc1", "-triple", EffectiveTriple,
                "-x", "ir", "-emit-llvm-only",
                "-Wno-override-module",
                "-",
            ], ir);

        return result.Success && !IrFault.StrippedDebugInfo(result.StandardError)
            ? null
            : IrFault.FromVerifier(result.StandardError, ir);
    }

    /// <summary>
    /// What a shared library built from a package of this name is called, for
    /// <paramref name="target"/>.
    ///
    /// The <c>lib</c> prefix is not decoration: outside Windows it is what makes
    /// a library findable as <c>-lshapes</c> rather than only by its full path,
    /// and the runtime has always been named this way. A generated name should
    /// be the platform's, the same reason an executable is not called
    /// <c>app.exe</c> on Linux.
    /// </summary>
    public static string SharedLibraryFileName(string name, Binding.TargetPlatform target) =>
        (target.IsWindows ? "" : "lib") + name + SharedLibraryExtensionFor(target);

    /// <summary>
    /// <see cref="SharedLibraryFileName(string, Binding.TargetPlatform)"/> for
    /// the current target.
    /// </summary>
    public static string SharedLibraryFileName(string name) =>
        SharedLibraryFileName(name, Binding.TargetPlatform.Current);

    /// <summary>The conventional shared-library extension for a target.</summary>
    public static string SharedLibraryExtensionFor(Binding.TargetPlatform target) => target.Os switch
    {
        Binding.TargetOS.Windows => ".dll",
        Binding.TargetOS.MacOS => ".dylib",
        _ => ".so",
    };

    /// <summary>The shared-library extension for the current target.</summary>
    public static string SharedLibraryExtension =>
        SharedLibraryExtensionFor(Binding.TargetPlatform.Current);

    /// <summary>
    /// The conventional executable extension for a target, which is nothing at
    /// all outside Windows.
    /// </summary>
    public static string ExecutableExtensionFor(Binding.TargetPlatform target) =>
        target.IsWindows ? ".exe" : "";

    /// <summary>The executable extension for the current target.</summary>
    public static string ExecutableExtension =>
        ExecutableExtensionFor(Binding.TargetPlatform.Current);

    /// <summary>
    /// What a link line names for a shared library: the import library beside
    /// it on Windows, and the library itself everywhere else.
    /// </summary>
    public static string LinkInputFor(string library, Binding.TargetPlatform target) =>
        target.IsWindows ? Path.ChangeExtension(library, ".lib") : library;

    /// <summary>
    /// Runs a tool to completion. <paramref name="input"/>, when given, is its
    /// standard input; otherwise the tool inherits this process's.
    /// </summary>
    public static ToolResult Run(string executable, IReadOnlyList<string> arguments, string? input = null)
    {
        var startInfo = new ProcessStartInfo(executable)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            RedirectStandardInput = input is not null,
            UseShellExecute = false,
        };

        // UTF-8 without a mark, which is what a .ll on disk is. The default
        // is the console's code page, and a byte-order mark is not IR.
        if (input is not null)
            startInfo.StandardInputEncoding = new System.Text.UTF8Encoding(false);
        foreach (string argument in arguments) startInfo.ArgumentList.Add(argument);

        var clock = Stopwatch.StartNew();
        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException($"could not start '{executable}'");

        // Both streams at once, and the input beside them: a tool that fills
        // one pipe while this waits on another never finishes.
        var output = process.StandardOutput.ReadToEndAsync();
        var error = process.StandardError.ReadToEndAsync();

        if (input is not null)
        {
            try
            {
                process.StandardInput.Write(input);
                process.StandardInput.Close();
            }
            catch (IOException)
            {
                // The tool stopped reading, and its exit code says why.
            }
        }

        process.WaitForExit();
        if (Compilation.s_reportsPhases)
            Console.Error.WriteLine(
                $"tool {Path.GetFileNameWithoutExtension(executable)} {DescribeToolOutput(arguments)}: " +
                $"{clock.Elapsed.TotalMilliseconds:F1} ms");
        return new ToolResult(process.ExitCode, output.Result, error.Result);
    }

    /// <summary>What a tool run wrote, by the name after its <c>-o</c>.</summary>
    private static string DescribeToolOutput(IReadOnlyList<string> arguments)
    {
        for (int i = 0; i + 1 < arguments.Count; i++)
            if (arguments[i] == "-o")
                return Path.GetFileName(arguments[i + 1]);
        return "";
    }
}
