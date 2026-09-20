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

using System.Text;
using System.Text.RegularExpressions;
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
    /// Windows resource scripts to compile and fold into the binary.
    ///
    /// Apart from the other native inputs because these are not handed to the
    /// linker as they stand: each is compiled to a .res first, and on a target
    /// that has no resource section there is nothing useful to do with one.
    /// </summary>
    public IReadOnlyList<string> ResourceScripts { get; init; } = [];

    /// <summary>
    /// Libraries to link by name rather than by path, from <c>-l</c>. The linker
    /// finds them on its own search path, which is how a platform's own import
    /// libraries are reached: <c>-l user32</c> rather than the full path into
    /// whichever Windows SDK happens to be installed.
    /// </summary>
    public IReadOnlyList<string> Libraries { get; init; } = [];
    public string? OutputPath { get; init; }
    public string? IntermediateDirectory { get; init; }
    public int OptimizationLevel { get; init; } = 2;

    /// <summary>Build a shared library rather than an executable.</summary>
    public bool Shared { get; init; }

    /// <summary>Where to write a C header for the exported surface, if anywhere.</summary>
    public string? HeaderPath { get; init; }

    /// <summary>
    /// A module definition file to hand the linker, for export names the
    /// declarations cannot state: an alias, an ordinal, a data export, or a
    /// name that differs from the function's.
    ///
    /// Whatever the compiler would have generated is kept as well, appended in
    /// a section of its own — otherwise passing one of these to add an export
    /// would silently drop the renames that make a decorated symbol reachable
    /// under its declared name. See <see cref="ModuleDefinition"/>.
    /// </summary>
    public string? ModuleDefinitionPath { get; init; }

    /// <summary>
    /// Where to write the module metadata another Stainless compilation binds
    /// against. The C header and this describe the same library to two
    /// different audiences.
    /// </summary>
    public string? MetadataPath { get; init; }

    /// <summary>Metadata files describing libraries this program links against.</summary>
    public IReadOnlyList<string> References { get; init; } = [];

    /// <summary>
    /// The package this build is of, and the version it publishes itself as.
    /// Both null for a build driven straight from a command line, which is not
    /// part of a package and has nothing to claim.
    ///
    /// They go into the metadata, where they are what lets a consumer be told
    /// it was handed the wrong version rather than finding out at the first
    /// call. See <see cref="ProjectFile"/>.
    /// </summary>
    public string? PackageName { get; init; }
    public string? PackageVersion { get; init; }

    /// <summary>
    /// Whether the runtime is one shared library everything links, or a copy
    /// compiled into this binary. Null asks for whichever the build needs.
    ///
    /// It matters only where two Stainless binaries meet. A copy each means two
    /// allocators, two sets of reference counts and two stdio buffers: an object
    /// made on one side and released on the other is counted twice, the
    /// <c>TypeInfo</c> a <c>String</c> carries is not the one the other side
    /// compares against, and output written in a library does not interleave
    /// with its consumer's. One shared runtime closes all three.
    ///
    /// A program with no such boundary has nothing to gain and a file to carry,
    /// so it keeps the copy. <see cref="NeedsSharedRuntime"/> is that rule.
    /// </summary>
    public bool? SharedRuntime { get; init; }

    /// <summary>
    /// True when this build has a Stainless library boundary in it: either it is
    /// producing metadata for a Stainless consumer, or it is binding against
    /// some. A C consumer does not count -- it has no runtime of its own for a
    /// second copy to disagree with.
    /// </summary>
    public bool NeedsSharedRuntime =>
        SharedRuntime ?? (MetadataPath is not null || References.Count > 0);

    public bool KeepIntermediates { get; init; }
    public bool EmitIrOnly { get; init; }

    /// <summary>
    /// Where to write reference documentation generated from the <c>///</c>
    /// blocks, or null for none.
    ///
    /// Written after binding and before emission, because a page is only worth
    /// writing about source the compiler accepted: a signature nobody could
    /// compile is not documentation, it is a claim.
    /// </summary>
    public string? DocumentationPath { get; init; }

    /// <summary>
    /// Document the standard library rather than the program's own modules.
    ///
    /// The standard library is compiled into every program, so its units are
    /// always there to walk; what this chooses is which half of them the pages
    /// are about.
    /// </summary>
    public bool DocumentStandardLibrary { get; init; }

    /// <summary>
    /// Stop once the documentation is written. Nothing is emitted, assembled or
    /// linked, so this needs no toolchain -- which matters, because generating
    /// documentation is something a machine with no clang should be able to do.
    /// </summary>
    public bool DocumentationOnly { get; init; }

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
    /// Which debugger's format to describe it in, or null for what the target
    /// reads: CodeView for Windows, DWARF everywhere else.
    ///
    /// The default follows the target and MUST NOT follow the host. A build
    /// cross-compiled from Windows to Linux needs DWARF, which is what the
    /// resulting ELF's own debuggers read.
    /// </summary>
    public Emit.DebugFormat? DebugFormat { get; init; }

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
    ///
    /// It does not decide how a struct is passed in registers. That is Win64
    /// whichever ABI is named, because the SysV classifier is not written -- so
    /// naming Itanium on Windows gives Itanium bit-fields and Win64 argument
    /// passing, which is self-consistent within one program and not a
    /// cross-compilation.
    /// </summary>
    public Binding.CppAbi? CppAbi { get; init; }

    /// <summary>
    /// The machine this build is for. Null is this one, 64-bit.
    ///
    /// It decides how wide a pointer is, which is not a question the emitter
    /// alone can answer: the binder lays out every struct against it, so it has
    /// to be settled before anything is bound.
    /// </summary>
    public Binding.TargetPlatform? Target { get; init; }
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

    /// <summary>The documentation pages written, or empty.</summary>
    public IReadOnlyList<string> DocumentationFiles { get; init; } = [];

    /// <summary>
    /// Every file an <c>embed</c> carried into the output, as a full path.
    ///
    /// They are inputs to the build as much as the sources are, and something
    /// deciding whether a build is up to date has to be able to ask for them:
    /// only the binder knows which files a program embeds.
    /// </summary>
    public IReadOnlyList<string> EmbeddedFiles { get; init; } = [];

    /// <summary>A failure outside the source program: a missing tool, unreadable file, bad IR.</summary>
    public string? DriverError { get; init; }
}

/// <summary>Turns a linker failure into an explanation of who has to fix it.</summary>
public static class LinkDiagnosis
{
    /// <summary>
    /// An undefined symbol is normally the program's own doing: an <c>extern "C"</c>
    /// declaration whose library nothing linked, or a Stainless library bound
    /// against through <c>--reference</c> whose binary was not beside its
    /// metadata. Saying "compiler bug" there sends the reader to the wrong
    /// place, so that claim is kept for the case where the toolchain objected to
    /// something the compiler itself wrote.
    ///
    /// The two causes are told apart by the name, because they are fixed in
    /// different places. Every name the program itself had to write as
    /// <c>extern "C"</c> is a C name; a Stainless one is mangled, and starts
    /// with <c>_SL</c>. This said <c>extern "C"</c> of both, which sent the
    /// reader of <c>_SL3Lib5Total...</c> looking for a declaration that was
    /// never written.
    /// </summary>
    /// <param name="unlinkedReferences">
    /// The libraries named by <c>--reference</c> metadata that could not be
    /// found to link, by the name the metadata gives them.
    /// </param>
    public static string Explain(
        string linkerOutput, string irPath, IReadOnlyList<string>? unlinkedReferences = null)
    {
        if (!Undefined(linkerOutput))
            return "the native toolchain rejected the generated IR:\n" + linkerOutput +
                   $"\nThe IR is at {irPath}; this is a compiler bug, not a bug in your program.";

        var names = UndefinedNames(linkerOutput).ToList();
        bool stainless = names.Any(IsStainlessName);

        // A linker whose spelling was not recognised still said "undefined", so
        // with no names to go on the C explanation stands as it always did.
        bool c = names.Count == 0 || names.Any(n => !IsStainlessName(n));

        var text = new StringBuilder("the linker could not find everything the program refers to:\n")
            .Append(linkerOutput);

        if (stainless)
        {
            text.Append("\nA name starting '_SL' is a Stainless function or type, and comes from " +
                        "the library\nthat compiled it.");

            bool one = unlinkedReferences is { Count: 1 };
            if (unlinkedReferences is { Count: > 0 })
                text.Append($" {Listed(unlinkedReferences)} {(one ? "was" : "were")} not beside " +
                            $"{(one ? "its" : "their")} metadata to be linked, so\n" +
                            $"pass {(one ? "it" : "each")} as an ordinary input -- the import " +
                            "library, on Windows.");
            else
                text.Append(" Pass that library as an ordinary input -- the import library, on\n" +
                            "Windows -- or keep it beside the metadata '--reference' names.");
        }

        if (c)
            text.Append("\nA name declared 'extern \"C\"' has to come from somewhere. Link what defines " +
                        "it:\n'-l <name>' for a library the linker can find on its own, or its path as " +
                        "an\nordinary input.");

        return text.ToString();
    }

    private static string Listed(IReadOnlyList<string> libraries) =>
        string.Join(", ", libraries.Select(l => $"'{l}'"));

    /// <summary>How the three linkers Stainless drives each spell it.</summary>
    private static bool Undefined(string output) =>
        output.Contains("undefined symbol", StringComparison.OrdinalIgnoreCase) ||
        output.Contains("undefined reference", StringComparison.OrdinalIgnoreCase) ||
        output.Contains("unresolved external symbol", StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// The missing names, as lld-link (<c>undefined symbol: name</c>), GNU ld and
    /// lld (<c>undefined reference to `name'</c> and <c>undefined symbol: name</c>)
    /// and link.exe (<c>unresolved external symbol name</c>) write them.
    /// </summary>
    private static IEnumerable<string> UndefinedNames(string output) =>
        Regex.Matches(
                output,
                @"(?:undefined symbol:\s*|undefined reference to [`']|unresolved external symbol\s+)" +
                @"([^\s`'""()]+)",
                RegexOptions.IgnoreCase)
            .Select(m => m.Groups[1].Value);

    /// <summary>
    /// A mangled Stainless name. On 32-bit Windows the target's own underscore
    /// comes first, so one or two of them may precede the <c>SL</c>.
    /// </summary>
    private static bool IsStainlessName(string name) =>
        Regex.IsMatch(name, @"^_{1,2}SL(?:\d|ti|destroy_)");
}

/// <summary>
/// The parts of the standard library that are written in Stainless and shipped
/// inside the compiler.
/// </summary>
public static class StandardLibrary
{
    private const string Prefix = "Stainless.Library.";

    /// <summary>
    /// What stands in for a directory in a standard-library source's path.
    ///
    /// These are compiled out of the compiler's own resources and have no file
    /// on disk, so the "path" is a label -- one that reads as a label in a
    /// diagnostic rather than as a directory somebody could go and look in.
    /// Anything wanting to point at the real source rewrites this; see
    /// <see cref="RepositoryPath"/>.
    /// </summary>
    public const string PathMarker = "<standard>";

    /// <summary>Where these files live in the repository they are written in.</summary>
    public const string RepositoryPath = "stdlib";

    public static IEnumerable<(string Name, string Text)> Sources()
    {
        var assembly = System.Reflection.Assembly.GetExecutingAssembly();

        foreach (string resource in assembly.GetManifestResourceNames().Order(StringComparer.Ordinal))
        {
            if (!resource.StartsWith(Prefix, StringComparison.Ordinal)) continue;

            using var stream = assembly.GetManifestResourceStream(resource);
            if (stream is null) continue;

            using var reader = new StreamReader(stream);
            yield return (PathMarker + "/" + resource[Prefix.Length..], reader.ReadToEnd());
        }
    }
}

/// <summary>What a set of command-line paths expanded to.</summary>
public sealed record SourceSet
{
    public required IReadOnlyList<string> Sources { get; init; }
    public required IReadOnlyList<string> NativeInputs { get; init; }

    /// <summary>Windows resource scripts, which are compiled before they are linked.</summary>
    public IReadOnlyList<string> ResourceScripts { get; init; } = [];

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

    /// <summary>The extension a Windows resource script goes by.</summary>
    public const string ResourceExtension = ".rc";

    /// <summary>
    /// True for a Windows resource script.
    ///
    /// Not among <see cref="NativeExtensions"/> because a .rc is not something
    /// the linker takes: it is compiled to a .res on the way, and only that is
    /// a native input.
    /// </summary>
    public static bool IsResourceScript(string path) =>
        Path.GetExtension(path).Equals(ResourceExtension, StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// Expands directories into their .sl files and separates native inputs.
    ///
    /// Where a file sits has no bearing on which module it joins; that is stated
    /// in the file. Folders are for people, not for the compiler.
    /// </summary>
    /// <summary>
    /// Every source a set of paths names, with the directories in
    /// <paramref name="excluded"/> left out of any scan.
    /// </summary>
    /// <remarks>
    /// <b>A project scans its own output.</b> With <c>sources</c> of
    /// <c>"."</c> the build directory and the object directory are both under
    /// the scan, and a <c>-g</c> build writes the standard library into
    /// <c>obj/stdlib/</c> -- so the second build compiles a second copy of it
    /// and every module of <c>Standard</c> is declared twice. The project says
    /// where its output goes, so the caller that has a project passes those
    /// directories here rather than anything guessing by name.
    ///
    /// A path named outright is still taken as given: a guess about what
    /// belongs is what this excludes, and a path somebody typed is not a
    /// guess.
    /// </remarks>
    public static SourceSet CollectSourceFiles(
        IEnumerable<string> paths, IReadOnlyList<string>? excluded = null)
    {
        var away = excluded is null
            ? []
            : excluded.Select(d => Path.GetFullPath(d).TrimEnd(
                Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar))
                .ToList();

        var files = new List<string>();
        var nativeInputs = new List<string>();
        var resourceScripts = new List<string>();
        var errors = new List<string>();

        foreach (string path in paths)
        {
            if (IsNativeInput(path) || IsResourceScript(path))
            {
                if (!File.Exists(path)) errors.Add($"'{path}' does not exist");
                else if (IsResourceScript(path)) resourceScripts.Add(Path.GetFullPath(path));
                else nativeInputs.Add(Path.GetFullPath(path));
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
                    .Where(f => !IsUnder(f, away))
                    .ToList();

                if (found.Count == 0)
                    errors.Add($"no {SourceExtension} files were found under '{path}'");

                files.AddRange(found);

                // C sources sitting beside the Stainless ones belong to the same
                // program; a directory would otherwise drop them silently.
                //
                // What a previous build wrote is left out here, and only here:
                // a scan is a guess about what belongs, and feeding a stale
                // object file back into the next link is the way that guess
                // goes wrong. A path somebody typed is not a guess.
                nativeInputs.AddRange(all.Where(
                    f => IsNativeInput(f) && !IsBuildArtifact(f) && !IsUnder(f, away)));

                // A resource script beside the sources belongs to the program
                // for the same reason a C source does. What a previous build
                // wrote is left out here too: the .res it produced sits under
                // obj, and feeding that back in would embed every resource
                // twice.
                resourceScripts.AddRange(all.Where(
                    f => IsResourceScript(f) && !IsBuildArtifact(f) && !IsUnder(f, away)));
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
            NativeInputs = nativeInputs.Distinct(StringComparer.OrdinalIgnoreCase).ToList(),
            ResourceScripts = resourceScripts.Distinct(StringComparer.OrdinalIgnoreCase).ToList(),
            Errors = errors,
        };
    }

    /// <summary>
    /// True for files a previous build produced, judged by the directory they
    /// sit in.
    /// </summary>
    /// <remarks>
    /// A guess by name, and applied only to the files a scan picks up
    /// <i>beside</i> the sources -- C, C++ and .rc. It MUST NOT be used on
    /// <c>.sl</c> files: <c>ide/src/Build/</c> is a module of the IDE's, and a
    /// rule that reads a directory called <c>Build</c> as output would drop
    /// it. What a project's own output directories are is a thing the project
    /// says, and <see cref="CollectSourceFiles"/> takes them as
    /// <c>excluded</c>.
    /// </remarks>
    private static bool IsBuildArtifact(string path)
    {
        string? directory = Path.GetFileName(Path.GetDirectoryName(path));

        return string.Equals(directory, "obj", StringComparison.OrdinalIgnoreCase)
            || string.Equals(directory, "bin", StringComparison.OrdinalIgnoreCase)
            || string.Equals(directory, "build", StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>Whether <paramref name="path"/> sits under any of them.</summary>
    private static bool IsUnder(string path, IReadOnlyList<string> directories)
    {
        foreach (string directory in directories)
        {
            if (path.StartsWith(directory, StringComparison.OrdinalIgnoreCase)
                && path.Length > directory.Length
                && (path[directory.Length] == Path.DirectorySeparatorChar
                    || path[directory.Length] == Path.AltDirectorySeparatorChar))
                return true;
        }
        return false;
    }

    /// <summary>
    /// Compiles, on a stack deep enough for what parsing and binding recurse
    /// over. See <see cref="Source.Recursion"/>: the depth limit is what turns
    /// absurdly nested source into a diagnostic, and this is what keeps the
    /// limit from having to be small enough to be reached by real code.
    /// </summary>
    public CompilationResult Compile(CompilationOptions options) =>
        Source.Recursion.OnADeepStack(() => CompileHere(options));

    private CompilationResult CompileHere(CompilationOptions options)
    {
        var diagnostics = new DiagnosticBag();

        // Before anything is parsed or bound, because the binder lays out every
        // struct against it and a layout computed for the wrong width is not
        // something a later pass could correct.
        //
        // `--abi` still has the last word on the name mangling, which is a
        // separate question from the width: a 64-bit Windows build may be asked
        // for Itanium names so that the scheme this host does not use still gets
        // exercised against a real compiler.
        var target = options.Target ?? Binding.TargetPlatform.Host;
        if (options.CppAbi is { } chosenAbi) target = target with { Abi = chosenAbi };

        Binding.TargetPlatform.Current = target;

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
        var referenceLinkInputs = new List<string>();
        var unlinkedReferences = new List<string>();
        foreach (string path in options.References)
        {
            var metadata = ModuleMetadata.Read(path, out string referenceError);
            if (metadata is null) return Failure(referenceError);

            // Both sides of a boundary have to reach the same runtime, or there
            // are two allocators and two sets of counts and nothing says so.
            // The default agrees on its own -- a '--metadata' build and a
            // '--reference' one both share -- so this only catches an override.
            if (metadata.SharedRuntime != options.NeedsSharedRuntime)
                return Failure(
                    $"'{metadata.Library}' was built with a " +
                    $"{(metadata.SharedRuntime ? "shared" : "static")} runtime and this program " +
                    $"is being built with a {(options.NeedsSharedRuntime ? "shared" : "static")} " +
                    "one. Two runtimes means two allocators and two sets of reference counts, so " +
                    "an object could not cross between them; build both with the same " +
                    "'--runtime'.");

            references.Add(metadata);

            // The metadata names the library it describes, and a library built
            // with '--metadata' leaves the two side by side. So what to link is
            // already known, and asking for it again on the command line only
            // gave a link error to anyone who took '--reference' to mean what it
            // says. A library that has been moved away from its metadata is
            // still linked by naming it as an input, and is explained below if
            // it is not.
            string linkInput = ReferencedLinkInput(path, metadata, target);
            if (File.Exists(linkInput)) referenceLinkInputs.Add(linkInput);
            else unlinkedReferences.Add(metadata.Library);
        }

        // Documenting is reading, not building: there is nothing to run, so
        // demanding a 'Main' would make `stainless doc` refuse exactly the
        // libraries it is most wanted for.
        bool needsEntryPoint = !options.Shared && !options.DocumentationOnly;

        var program = new Binder(
            diagnostics, requireEntryPoint: needsEntryPoint, references: references,
            cppAbi: options.CppAbi).Bind(units);
        if (diagnostics.HasErrors) return Failed(diagnostics);

        // Against the program's own first file rather than units[0], which is
        // the standard library's: neither of these is about a place in the
        // source, and pointing at a file nobody wrote reads as a compiler bug.
        var programSpan = units[standardUnits < units.Count ? standardUnits : 0].Span;

        if (program.EntryPoint is null && !options.EmitIrOnly && needsEntryPoint)
            diagnostics.Error("SL0290", programSpan,
                "no entry point was found; declare 'int Main()' in one of the compiled modules, " +
                "or pass --shared to build a library instead");

        // A library built for Stainless consumers exports its public surface
        // through the metadata, so it is not silent even with no export "C".
        if (options.Shared && options.MetadataPath is null &&
            !program.Modules.SelectMany(m => m.Functions)
                .Any(f => f.Linkage == LinkageKind.ExportC))
            diagnostics.Warning("SL0476", programSpan,
                "this library exports nothing; mark a function 'export \"C\"' to add it to the " +
                "export table");

        // Static initializers run from the entry point, and a library has none.
        // Better to say so than to hand back a library whose statics are zero.
        //
        // A variable declared `extern "C"` is not one of these. It has no
        // initializer to run -- the storage is defined elsewhere and this names
        // it -- so there is nothing for a missing entry point to fail to do.
        // `Standard.Resources` declares two, so without this exception no
        // --shared build would compile at all.
        // A static whose value is a constant is written onto the global itself
        // and needs no entry point -- see StaticSymbol.HasConstantInitializer.
        // Without that exception a module compiled into every program could
        // remember nothing, which is what stopped `Standard.Drawing` caching
        // the imaging library it had loaded.
        var uninitialized = program.Statics
            .Where(s => !s.IsImported && !s.HasConstantInitializer)
            .ToList();
        if (options.Shared && uninitialized.Count > 0)
            diagnostics.Error("SL0380", uninitialized[0].Span,
                $"'{uninitialized[0].Name}' is a static, and a --shared library has no entry " +
                "point to initialize one from; hold the value behind an exported function " +
                "instead, or build this module into an executable");

        if (diagnostics.HasErrors) return Failed(diagnostics);

        // --- document ----------------------------------------------------
        if (options.DocumentationPath is not null)
        {
            // The standard library's units come first and the program's after,
            // which is what `standardUnits` divides. One or the other, never
            // both: a page mixing `Standard.Text` with a program's own modules
            // is a reference to nothing in particular.
            var documented = options.DocumentStandardLibrary
                ? units.Take(standardUnits).ToList()
                : units.Skip(standardUnits).ToList();

            IReadOnlyList<string> pages;
            try
            {
                pages = Emit.DocWriter.Write(
                    documented,
                    Path.GetFullPath(options.DocumentationPath),
                    sourceRoot: Environment.CurrentDirectory,
                    rewritePath: (StandardLibrary.PathMarker, StandardLibrary.RepositoryPath));
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                return Failure($"could not write the documentation to " +
                               $"'{options.DocumentationPath}': {e.Message}");
            }

            if (options.DocumentationOnly)
                return new CompilationResult
                {
                    Success = true,
                    Diagnostics = diagnostics.Sorted().ToList(),
                    DocumentationFiles = pages,
                };
        }

        // --- resources ---------------------------------------------------
        //
        // Before emission rather than beside the link, because on a target with
        // no resource section the bytes travel in the IR as ordinary constant
        // data: the emitter needs them, and the emitter runs first.
        //
        // The toolchain is located here and only here, because compiling a .rc
        // is the one thing before the link that needs an external tool, and a
        // documentation-only build must still work on a machine with no clang.
        IReadOnlyList<string> compiledResources = [];
        byte[]? resourceBlob = null;

        if (options.ResourceScripts.Count > 0)
        {
            var resourceTools = Toolchain.Locate(out string resourceToolError);
            if (resourceTools is null) return Failure(resourceToolError);

            Directory.CreateDirectory(IntermediateDirectory(options));
            compiledResources = CompileResources(
                resourceTools, options, target, IntermediateDirectory(options),
                out string resourceError);
            if (resourceError.Length > 0) return Failure(resourceError);
        }

        // A PE has somewhere to put these and the linker fills it from the same
        // .res, so a Windows build carries them once, in the resource
        // directory. Everything else carries them as data. The empty blob is
        // deliberate: the symbol resolves whether or not a program has any.
        if (!target.IsWindows)
        {
            resourceBlob = ReadResourceBlob(compiledResources);
            WarnAboutUnreadTypes(resourceBlob, target, diagnostics);
        }

        // --- emit --------------------------------------------------------
        var debug = options.Debug
            ? new DebugInfo(
                units[^1].Span.File,
                "Stainless " + typeof(Compilation).Assembly.GetName().Version?.ToString(3),
                options.DebugFormat ?? DefaultDebugFormat(target))
            : null;

        var emitter = new LlvmEmitter(
            forSharedLibrary: options.Shared,
            forStainlessConsumers: options.MetadataPath is not null,
            debug: debug,
            sharedRuntime: options.NeedsSharedRuntime,
            abi: target.Abi,
            resourceBlob: resourceBlob);
        string ir = emitter.Emit(program);

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
                EmbeddedFiles = EmbeddedFiles(program),
            };

        // --- assemble and link -------------------------------------------
        var toolchain = Toolchain.Locate(out string toolchainError);
        if (toolchain is null) return Failure(toolchainError);

        // The linker will not make the directory it is writing into, and says
        // so in its own terms -- which read as a compiler bug rather than as a
        // missing folder. A project puts its output under 'build' by default,
        // so this is the ordinary case rather than a corner.
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output)) ?? ".");
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return Failure($"could not create the directory for '{output}': {e.Message}");
        }

        IReadOnlyList<string> runtimeObjects = [];
        SharedRuntime? sharedRuntime = null;
        try
        {
            if (options.NeedsSharedRuntime)
                sharedRuntime = toolchain.BuildSharedRuntime(intermediate, options.Debug);
            else
                // `options.Shared` and not just the shared-runtime case: an
                // object linked into a shared library has to be
                // position-independent, and these were compiled without asking
                // for that. Windows relocates a DLL at load time and never
                // noticed; an ELF linker refuses the relocation outright.
                runtimeObjects = toolchain.BuildRuntime(
                    intermediate, options.Debug, shared: options.Shared);
        }
        catch (Exception e) when (e is InvalidOperationException or IOException)
        {
            return Failure(e.Message);
        }

        // What the command line asked for, plus what the sources asked for with
        // '#pragma comment(lib, ...)'. A binding knows which library it needs;
        // repeating that on every command line is the thing the pragma removes.
        var libraries = new List<string>(options.Libraries);
        foreach (var unit in units)
            foreach (string library in unit.Libraries)
                if (!libraries.Contains(library, StringComparer.Ordinal))
                    libraries.Add(library);

        // The .res files were compiled before emission. Only a PE linker takes
        // one; elsewhere the bytes are already in the IR as constant data.
        var nativeInputs = new List<string>(options.NativeInputs);
        if (target.IsWindows) nativeInputs.AddRange(compiledResources);

        // Once each, however it was reached: a project build and a command line
        // that still names the import library both pass it already.
        foreach (string linkInput in referenceLinkInputs)
            if (!nativeInputs.Any(given => SamePath(given, linkInput)))
                nativeInputs.Add(linkInput);

        // A library whose export names differ from its symbols needs the linker
        // told which is which, and the author may have names of their own to
        // add. Null where neither is true, which is the usual answer.
        string? moduleDefinition = ModuleDefinition.Resolve(
            program, options.ModuleDefinitionPath, options.Shared, intermediate, output);

        var link = toolchain.Link(
            irPath, runtimeObjects, nativeInputs, output, options.OptimizationLevel,
            options.Shared, options.Debug, libraries, sharedRuntime, moduleDefinition);
        if (!link.Success)
        {
            // An 'asm' block is the one part of the IR whose text the program
            // wrote rather than the compiler, so a complaint about it is the
            // program's to fix and goes back to its line.
            if (AssemblerDiagnosis.Rejected(link.StandardError) && emitter.AsmBlocks.Count > 0)
            {
                AssemblerDiagnosis.Report(link.StandardError, emitter.AsmBlocks, target, diagnostics);
                return Failed(diagnostics);
            }

            return Failure(LinkDiagnosis.Explain(link.StandardError.TrimEnd(), irPath, unlinkedReferences));
        }

        // The loader looks beside the binary, so that is where the runtime goes.
        // Both a program and a Stainless library need it there, and they are
        // usually the same directory -- copying twice is copying the same file.
        if (sharedRuntime is not null &&
            CopyRuntimeBeside(sharedRuntime.Library, output) is { } copyError)
            return Failure(copyError);

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
                MetadataWriter.Write(
                        program, Path.GetFileName(output), ownModules, diagnostics,
                        options.NeedsSharedRuntime, options.PackageName, options.PackageVersion)
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
            EmbeddedFiles = EmbeddedFiles(program),
        };
    }

    /// <summary>
    /// Compiles each resource script to a .res, and returns what the link line
    /// should name.
    ///
    /// The script is compiled for every target, because every target can carry
    /// what is in it. What differs is where it goes: a PE has a resource
    /// directory and the linker fills it from this, and everything else carries
    /// the same bytes as ordinary constant data for `Standard.Resources` to
    /// walk. What no other target has is an operating system that reads them --
    /// see SL0700.
    /// </summary>
    /// <summary>What a target's own debuggers read.</summary>
    private static Emit.DebugFormat DefaultDebugFormat(Binding.TargetPlatform target) =>
        target.IsWindows ? Emit.DebugFormat.CodeView : Emit.DebugFormat.Dwarf;

    private static IReadOnlyList<string> CompileResources(
        Toolchain toolchain, CompilationOptions options, Binding.TargetPlatform target,
        string intermediate, out string error)
    {
        error = "";

        if (toolchain.ResourceCompilerPath is null)
        {
            error = Toolchain.MissingResourceCompiler;
            return [];
        }

        var compiled = new List<string>();
        var taken = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (string script in options.ResourceScripts)
        {
            // Named for the script rather than for the program, because a
            // program may have more than one and one name would mean the
            // second overwriting the first -- which would link a binary
            // carrying one script's resources twice and the other's not at
            // all, with nothing said.
            //
            // Two scripts may still share a file name from different
            // directories, so a name already taken gets its full path's digest
            // appended. The digest is only on the collision, so the ordinary
            // obj/ holds `app.res` and stays readable.
            string stem = Path.GetFileNameWithoutExtension(script);
            if (!taken.Add(stem))
                stem += "." + Digest.OfParts([script])[..8];

            string res = Path.Combine(intermediate, stem + ".res");

            var result = toolchain.CompileResource(script, res, target, options.Defines);
            if (!result.Success)
            {
                // llvm-rc reports on stdout as readily as on stderr.
                string detail = result.StandardError.TrimEnd();
                if (detail.Length == 0) detail = result.StandardOutput.TrimEnd();

                error = $"could not compile the resource script '{script}':\n{detail}";
                return [];
            }

            compiled.Add(res);
        }

        return compiled;
    }

    /// <summary>
    /// The compiled resources as one blob, for a target that carries them as
    /// data rather than in a section of its own.
    ///
    /// Several scripts concatenate, because a .res is a flat list of records
    /// rather than a container: joining two of them end to end is a longer list
    /// and nothing else. Each begins with a null marker entry, so a joined blob
    /// has one in the middle, and the reader skips a marker wherever it appears
    /// for exactly that reason.
    ///
    /// Empty rather than null when there is nothing to carry, so the symbol is
    /// emitted either way and a program that asks gets an empty answer instead
    /// of failing to link.
    /// </summary>
    private static byte[] ReadResourceBlob(IReadOnlyList<string> compiled)
    {
        if (compiled.Count == 0) return [];

        var joined = new List<byte>();
        foreach (string path in compiled)
        {
            try
            {
                joined.AddRange(File.ReadAllBytes(path));
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                // The file was written moments ago by the resource compiler; if
                // it cannot be read now, the build has a bigger problem and the
                // link will say so in its own terms.
                return [.. joined];
            }
        }

        return [.. joined];
    }

    /// <summary>
    /// The resource types whose whole point is that the *system* reads them.
    ///
    /// Everything else in a script is bytes with a number on it, and bytes
    /// travel: `Standard.Resources` reads an RCDATA, a bitmap or a string table
    /// identically on every target. These are different. A manifest is read by
    /// the Windows loader before any code runs, an icon becomes the window's
    /// icon, and a dialog template becomes a window full of controls -- all of
    /// them by machinery that exists nowhere else. Carried elsewhere they are
    /// readable and inert, which is worth being told once rather than
    /// discovering when the icon does not appear.
    /// </summary>
    private static readonly (int Type, string Name)[] SystemReadTypes =
    [
        (1, "RT_CURSOR"), (3, "RT_ICON"), (4, "RT_MENU"), (5, "RT_DIALOG"),
        (9, "RT_ACCELERATOR"), (11, "RT_MESSAGETABLE"), (12, "RT_GROUP_CURSOR"),
        (14, "RT_GROUP_ICON"), (16, "RT_VERSION"), (24, "RT_MANIFEST"),
    ];

    /// <summary>
    /// Reports the types in a blob that only Windows knows how to act on.
    ///
    /// The blob is walked rather than the script, because the script is a
    /// language with includes and conditionals and the blob is a flat list of
    /// records with the types already resolved. Reading it here is the same
    /// walk <c>Standard.Resources</c> does at run time, and it is what lets the
    /// warning name what is actually in the program instead of firing on every
    /// build that has a .rc at all.
    /// </summary>
    private static void WarnAboutUnreadTypes(
        byte[] blob, Binding.TargetPlatform target, DiagnosticBag diagnostics)
    {
        var present = new SortedSet<string>(StringComparer.Ordinal);

        int at = 0;
        while (at + 8 <= blob.Length)
        {
            int dataSize = BitConverter.ToInt32(blob, at);
            int headerSize = BitConverter.ToInt32(blob, at + 4);
            if (headerSize < 32 || at + headerSize > blob.Length) break;

            // The type is the first field after the two sizes: 0xFFFF then a
            // 16-bit number, or a NUL-terminated UTF-16 string. Only a numbered
            // one can be a standard type, so a named one is skipped outright.
            if (BitConverter.ToUInt16(blob, at + 8) == 0xFFFF)
            {
                int type = BitConverter.ToUInt16(blob, at + 10);
                foreach (var (number, name) in SystemReadTypes)
                    if (number == type) present.Add(name);
            }

            int next = (at + headerSize + dataSize + 3) & ~3;
            if (next <= at) break;
            at = next;
        }

        if (present.Count == 0) return;

        diagnostics.Warning("SL0700", default,
            $"this program's resources include {string.Join(", ", present)}, which only Windows " +
            $"acts on: {target.Triple} carries them and 'Standard.Resources' can read them, but " +
            "nothing here turns one into a window icon, a menu or a manifest");
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
    private static HashSet<string> BuildSymbols(CompilationOptions options) =>
        PlatformSymbols(options.Defines, options.Target);

    /// <summary>
    /// What <c>#if</c> can see: the platform and architecture being built for,
    /// plus whatever <c>-D</c> added.
    ///
    /// <para>
    /// **Every one of them is the target's, not the host's.** <c>--target
    /// x86</c> on an x86-64 box used to define <c>X64</c>, so a binding guarded
    /// by <c>#if X86</c> compiled the wrong half of itself; the architecture
    /// was fixed then and the operating system was left behind, on the argument
    /// that a target did not change which platform the standard library binds
    /// to. That argument does not survive being looked at: the standard library
    /// chooses its platform <i>with these very symbols</i> -- <c>#if WINDOWS</c>
    /// is what picks GDI+ over libgd in <c>Standard.Drawing</c> -- and the C
    /// runtime beside it is compiled by clang for the triple, so its
    /// <c>#ifdef _WIN32</c> has followed the target all along. Leaving the
    /// operating system on the host meant a cross build compiled the Windows
    /// half of the Stainless code against the Linux half of the C.
    /// </para>
    ///
    /// <para>
    /// **A build with no <c>--target</c> answers exactly as it did**, from the
    /// host. That is not only for compatibility: <see
    /// cref="Binding.TargetPlatform"/> has no macOS or FreeBSD triple, so
    /// <see cref="Binding.TargetPlatform.Host"/> on either answers with a Linux
    /// one -- and deriving the symbols from that would take <c>MACOS</c> away
    /// from a machine that has it. What a target cannot yet name, the host is
    /// still asked about.
    /// </para>
    ///
    /// <para>
    /// This says what <c>#if</c> may compile, and nothing about whether the
    /// result links. Cross-compiling to another operating system also wants
    /// that system's libraries, which is a separate problem and an unsolved
    /// one; what changes here is that the half the compiler controls is now
    /// self-consistent.
    /// </para>
    ///
    /// <para>
    /// Public because anything that drives the front end directly -- the unit
    /// tests, above all -- has to lex with the same set the compiler does, and
    /// a second copy of this list would drift the first time one gained a name.
    /// </para>
    /// </summary>
    public static HashSet<string> PlatformSymbols(
        IEnumerable<string> defines, Binding.TargetPlatform? target = null)
    {
        var symbols = new HashSet<string>(StringComparer.Ordinal) { "STAINLESS" };

        if (target is null)
        {
            if (OperatingSystem.IsWindows()) symbols.Add("WINDOWS");
            if (OperatingSystem.IsLinux()) { symbols.Add("LINUX"); symbols.Add("UNIX"); }
            if (OperatingSystem.IsMacOS()) { symbols.Add("MACOS"); symbols.Add("UNIX"); }
            if (OperatingSystem.IsFreeBSD()) { symbols.Add("FREEBSD"); symbols.Add("UNIX"); }
        }
        else if (target.IsWindows)
        {
            symbols.Add("WINDOWS");
        }
        else
        {
            symbols.Add("LINUX");
            symbols.Add("UNIX");
        }

        symbols.Add((target ?? Binding.TargetPlatform.Host).Architecture switch
        {
            Binding.TargetArch.X86 => "X86",
            Binding.TargetArch.Arm64 => "ARM64",
            _ => "X64",
        });

        foreach (string defined in defines) symbols.Add(defined);
        return symbols;
    }

    /// <summary>
    /// Puts the runtime shared library next to what was just built, unless it
    /// is already there. Returns null on success, or what went wrong.
    /// </summary>
    private static string? CopyRuntimeBeside(string library, string output)
    {
        try
        {
            string directory = Path.GetDirectoryName(Path.GetFullPath(output)) ?? ".";
            string destination = Path.Combine(directory, Path.GetFileName(library));

            if (Path.GetFullPath(library) == Path.GetFullPath(destination)) return null;

            // Only when it would differ: a rebuild that changed nothing should
            // not keep replacing a file something else may have open.
            if (File.Exists(destination) &&
                File.GetLastWriteTimeUtc(destination) >= File.GetLastWriteTimeUtc(library))
                return null;

            Directory.CreateDirectory(directory);
            File.Copy(library, destination, overwrite: true);
            return null;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return $"could not put the Stainless runtime beside the output: {e.Message}";
        }
    }

    /// <summary>
    /// Where object files, the generated IR and the runtime's sources go.
    ///
    /// It is derived from the options alone rather than from the output path,
    /// because a debug build needs it before the program has been bound and so
    /// before the default output name is known.
    /// </summary>
    /// <summary>
    /// What a link line names for the library a <c>--reference</c> describes:
    /// its import library on Windows and the shared object itself elsewhere,
    /// looked for beside the metadata. The rule a project build links a shared
    /// dependency by, and the runtime too.
    /// </summary>
    private static string ReferencedLinkInput(string metadataPath, ModuleMetadata metadata, TargetPlatform target)
    {
        string library = Path.Combine(
            Path.GetDirectoryName(Path.GetFullPath(metadataPath)) ?? ".", metadata.Library);
        return target.IsWindows ? Path.ChangeExtension(library, ".lib") : library;
    }

    private static bool SamePath(string left, string right) =>
        string.Equals(
            Path.GetFullPath(left), Path.GetFullPath(right),
            OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal);

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
            : Toolchain.ExecutableExtension;

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

    /// <summary>Each file the program embeds, once, however many objects it makes.</summary>
    private static List<string> EmbeddedFiles(Binding.BoundProgram program) =>
        program.Embeds.Select(e => e.Path).Distinct(StringComparer.Ordinal).ToList();

    private static CompilationResult Failed(DiagnosticBag diagnostics) =>
        new() { Success = false, Diagnostics = diagnostics.Sorted().ToList() };

    private static CompilationResult Failure(string message) =>
        new() { Success = false, Diagnostics = [], DriverError = message };
}
