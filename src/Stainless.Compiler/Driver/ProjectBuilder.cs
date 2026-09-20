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

namespace Stainless.Driver;

/// <summary>
/// What the command line still gets to say about a build the project file
/// already described.
///
/// Every field is nullable and null means "whatever the project said". A build
/// should mean the same thing from one machine to the next, so the project file
/// is the default for everything; these are the handful of answers that are
/// about this run rather than about the program -- where the output goes, and
/// how hard to look at it.
/// </summary>
public sealed record BuildOverrides
{
    public string? OutputPath { get; init; }
    public string? IntermediateDirectory { get; init; }
    public int? OptimizationLevel { get; init; }
    public bool? Debug { get; init; }

    /// <summary>
    /// Which debugger's format, or null for what the target reads. No project
    /// field backs this: the format is a property of the reader, not of the
    /// program.
    /// </summary>
    public Emit.DebugFormat? DebugFormat { get; init; }

    public bool KeepIntermediates { get; init; }
    public bool EmitIrOnly { get; init; }
    public IReadOnlyList<string> Defines { get; init; } = [];
    public IReadOnlyList<string> Libraries { get; init; } = [];
    public Binding.CppAbi? CppAbi { get; init; }
    public bool? SharedRuntime { get; init; }
    public string? HeaderPath { get; init; }

    /// <summary>A module definition file to hand the linker, or null.</summary>
    public string? ModuleDefinitionPath { get; init; }

    /// <summary>Where to write reference documentation, or null for none.</summary>
    public string? DocumentationPath { get; init; }

    /// <summary>Document the standard library rather than the project's own modules.</summary>
    public bool DocumentStandardLibrary { get; init; }

    /// <summary>Stop once the documentation is written, emitting nothing.</summary>
    public bool DocumentationOnly { get; init; }

    /// <summary>Extra paths named on the command line alongside the project.</summary>
    public IReadOnlyList<string> ExtraPaths { get; init; } = [];

    /// <summary>
    /// What is being built for, or null for this machine.
    ///
    /// **A project build ignored <c>--target</c> entirely** until this was
    /// here: the options a project produced never set it, so the flag was
    /// parsed, carried, and dropped. It decides the platform overlay as well
    /// as the code, which is why it had to stop being ignored before an
    /// overlay could mean anything.
    /// </summary>
    public Binding.TargetPlatform? Target { get; init; }
}

public sealed record ProjectBuildResult
{
    public required bool Success { get; init; }
    public string? Error { get; init; }

    /// <summary>The root's compilation, once every dependency has been built.</summary>
    public CompilationResult? Root { get; init; }

    /// <summary>Each shared dependency that was built, in the order it was built.</summary>
    public IReadOnlyList<string> Built { get; init; } = [];

    /// <summary>
    /// Each shared dependency that did not need building. Reported rather than
    /// silent: a build that skipped work should say which work, or the first
    /// time it skips something it should not have there is nothing to have
    /// noticed.
    /// </summary>
    public IReadOnlyList<string> Reused { get; init; } = [];

    /// <summary>Things worth saying that are not worth stopping for.</summary>
    public IReadOnlyList<string> Warnings { get; init; } = [];

    /// <summary>The lock with whatever this build learned written into it.</summary>
    public PackageLock? Lock { get; init; }

    public static ProjectBuildResult Failed(string error) =>
        new() { Success = false, Error = error };
}

/// <summary>
/// Builds a project and everything under it.
///
/// The order is the resolver's: dependencies first, so nothing ever waits. What
/// happens to each one depends on how it is linked, and the difference is the
/// whole reason <see cref="DependencyLink"/> has two cases rather than one --
/// a source dependency is *part of this program* and joins the same compilation
/// as everything else, where a shared one is a separate program that this one
/// links against. The first is the model the language has; the second is the
/// one that buys a boundary, and pays what a boundary costs.
/// </summary>
public sealed class ProjectBuilder(
    ProjectFile root,
    Resolution resolution,
    Action<string>? log = null)
{
    private readonly Dictionary<string, ResolvedPackage> _packages =
        resolution.Order.ToDictionary(p => p.Name, StringComparer.Ordinal);

    private readonly List<string> _warnings = [];
    private readonly List<string> _built = [];

    /// <summary>Dependencies whose last build was still good, so nothing was done.</summary>
    private readonly List<string> _reused = [];

    /// <summary>
    /// Each shared dependency once it has been built: where its metadata is,
    /// and what a link line should name to use it.
    ///
    /// Both remembered rather than one derived from the other. A library is
    /// <c>libshapes.so</c> here and <c>shapes.dll</c> there, its metadata is
    /// <c>shapes.slmod</c> on both, and what gets linked is a fourth name again
    /// on Windows -- four spellings that string surgery got to agree only by
    /// accident.
    /// </summary>
    private readonly Dictionary<string, Built> _libraries = new(StringComparer.Ordinal);

    private readonly record struct Built(string Metadata, string LinkInput);

    /// <summary>What each shared dependency's digest turned out to be.</summary>
    private readonly Dictionary<string, string> _digests = new(StringComparer.Ordinal);

    /// <summary>
    /// What every platform question is answered against: what was asked for,
    /// or this machine. Resolved once per build rather than per package, so a
    /// dependency cannot be collected for a different platform than the root.
    /// </summary>
    private Binding.TargetPlatform _target = Binding.TargetPlatform.Host;

    public ProjectBuildResult Build(BuildOverrides overrides)
    {
        _target = overrides.Target ?? Binding.TargetPlatform.Host;

        if (!resolution.Success)
            return ProjectBuildResult.Failed(resolution.Error ?? "the dependencies did not resolve");

        if (CheckSourceDigests() is { } tampered) return ProjectBuildResult.Failed(tampered);

        // A documentation run reads the root's own modules and emits nothing, so
        // there is no boundary for a dependency to be linked across. Building
        // them would cost a clang invocation each to produce libraries this run
        // will not open -- and would refuse on a machine with no toolchain,
        // which is exactly the machine that wants to generate documentation.
        //
        // A *source* dependency still contributes, because its files are
        // compiled in: `Collect` gathers those either way.
        if (!overrides.DocumentationOnly)
            foreach (var package in resolution.Order)
            {
                if (package.Link != DependencyLink.Shared) continue;

                if (BuildDependency(package, overrides) is { } failure) return failure;
            }

        var options = OptionsFor(root, overrides, output: overrides.OutputPath ?? root.OutputPath());
        if (options is null) return ProjectBuildResult.Failed(_error!);

        var result = new Compilation().Compile(options);

        return new ProjectBuildResult
        {
            Success = result.Success,
            Root = result,
            Built = _built,
            Reused = _reused,
            Warnings = _warnings,
            Lock = UpdatedLock(),
        };
    }

    private string? _error;

    // ------------------------------------------------------- dependencies

    /// <summary>
    /// Builds one dependency as a real shared library, then checks that what
    /// came out is what the lock file said would.
    /// </summary>
    private ProjectBuildResult? BuildDependency(ResolvedPackage package, BuildOverrides overrides)
    {
        string output = Path.Combine(
            BuildDirectory(overrides), Toolchain.SharedLibraryFileName(package.Name));

        string metadata = ProjectFile.MetadataBeside(output, package.Name);
        string linkInput = LinkInput(output);

        string intermediate = Path.Combine(IntermediateDirectory(overrides), package.Name);
        string stampPath = Path.Combine(intermediate, BuildStamp.FileName);

        string inputs = Fingerprint(package, overrides, output);

        // Nothing that fed the last build has changed, and everything it
        // produced is still there. Building it again would produce the same
        // bytes at the cost of a clang invocation and a link.
        if (BuildStamp.Read(stampPath) is { } stamp && stamp.Inputs == inputs &&
            stamp.EmbeddedFilesAreUnchanged() &&
            File.Exists(output) && File.Exists(metadata) && File.Exists(linkInput))
        {
            _libraries[package.Name] = new Built(metadata, linkInput);
            _digests[package.Name] = stamp.AbiDigest;
            _reused.Add(package.Name);
            return null;
        }

        // What the last build of this dependency said, read before this one
        // overwrites it. The lock file records a digest, but only one; the file
        // records every type's, which is the difference between "something
        // moved" and "Point moved".
        var before = File.Exists(metadata) ? ModuleMetadata.Read(metadata, out _) : null;

        var options = OptionsFor(
            package.Project, overrides, output,
            metadata: metadata,
            intermediate: intermediate);

        if (options is null) return ProjectBuildResult.Failed(_error!);

        Log($"building {package.Name} {package.Project.Version}");

        var result = new Compilation().Compile(options with { Shared = true });

        if (!result.Success)
            return new ProjectBuildResult
            {
                Success = false,
                Error = $"the dependency '{package.Name}' did not build",
                Root = result,
                Built = _built,
                Reused = _reused,
                Warnings = _warnings,
            };

        _built.Add(package.Name);
        _libraries[package.Name] = new Built(metadata, linkInput);

        var described = ModuleMetadata.Read(metadata, out string error);
        if (described is null) return ProjectBuildResult.Failed(error);

        _digests[package.Name] = described.AbiDigest;

        // Only after everything above succeeded. A stamp written beside a
        // half-built library would be a promise about a thing that is not there.
        new BuildStamp
        {
            Inputs = inputs,
            AbiDigest = described.AbiDigest,
            Embedded = BuildStamp.Digests(result.EmbeddedFiles),
        }.Write(stampPath);

        if (CheckAbiDigest(package, before, described) is { } mismatch)
        {
            // A path dependency being edited is the ordinary case and the whole
            // reason to use one, so it is told rather than stopped. Anything
            // else is pinned to a fixed commit, where the same version
            // describing two surfaces means the two builds were not the same
            // build -- and the code that uses it has one of the two layouts
            // compiled in.
            if (package.Source.StartsWith("path:", StringComparison.Ordinal))
                _warnings.Add(mismatch);
            else
                return ProjectBuildResult.Failed(mismatch);
        }

        return null;
    }

    /// <summary>
    /// Everything that decided what a dependency's last build produced.
    ///
    /// Every input or rebuild. There is no attempt here to work out that some
    /// change could not have mattered, because the cost of being wrong is not a
    /// slow build -- it is a program linked against a library that no longer
    /// matches its source, which links perfectly and reports nothing. So:
    ///
    ///   the compiler         a new one may lower the same source differently
    ///   the package          its own files, as a digest of their bytes
    ///   its source closure   compiled *into* it, so their files count too
    ///   its shared deps      their surfaces are what it was bound against
    ///   the flags            optimisation, debug, ABI, runtime, defines
    ///   where it goes        a moved output is a different build
    ///
    /// And one more that cannot be hashed here, because nothing knows it until
    /// the package has been bound: the files its <c>embed</c>s name. The stamp
    /// keeps those beside this hash, with their digests — see
    /// <see cref="BuildStamp.Embedded"/>.
    ///
    /// What is deliberately absent is timestamps. A file restored from an
    /// archive, a clock that went backwards, a checkout that rewrote mtimes --
    /// each of those makes a timestamp say "unchanged" about different bytes.
    /// </summary>
    private string Fingerprint(ResolvedPackage package, BuildOverrides overrides, string output)
    {
        var parts = new List<string>
        {
            "build",
            typeof(Compilation).Assembly.GetName().Version?.ToString() ?? "unknown",
            package.Name,
            package.Project.Version,
            package.SourceDigest,
            output,
        };

        // Its source closure, in a stable order: a package compiled into this
        // one is as much a part of it as its own files.
        foreach (string name in SourceClosure(package.Project).Order(StringComparer.Ordinal))
            parts.Add(name + "=" +
                      (_packages.TryGetValue(name, out var inner) ? inner.SourceDigest : "?"));

        // Its shared dependencies, by what they turned out to describe rather
        // than by what they were built from. Those are already built -- the
        // resolver put them first -- so the digest is known.
        foreach (string name in SharedClosure(package.Project).Order(StringComparer.Ordinal))
            parts.Add(name + ":" + (_digests.TryGetValue(name, out string? abi) ? abi : "?"));

        parts.AddRange([
            (overrides.OptimizationLevel ?? root.Optimize).ToString(),
            (overrides.Debug ?? root.Debug) ? "debug" : "",

            // Two builds differing only in the format produce different
            // objects and MUST NOT look alike to a stamp.
            overrides.DebugFormat?.ToString() ?? "target",
            (overrides.CppAbi ?? (root.Abi is null ? null : ProjectFile.ParseAbi(root.Abi)))
                ?.ToString() ?? "host",
            (overrides.SharedRuntime ?? (root.Runtime switch
            {
                "shared" => true,
                "static" => false,
                _ => (bool?)null,
            }))?.ToString() ?? "default",
        ]);

        // The target, because it decides the code *and* which platform overlay
        // was folded in below -- so two builds differing only in `--target`
        // must not look alike to a stamp.
        parts.Add(_target.Triple);

        parts.AddRange(package.Project.DefinesFor(_target));
        parts.AddRange(overrides.Defines);

        return Digest.OfParts(parts);
    }

    /// <summary>Every package whose files are compiled into this one.</summary>
    private HashSet<string> SourceClosure(ProjectFile project) =>
        Closure(project, DependencyLink.Source);

    /// <summary>Every library this one is bound against, directly or through one.</summary>
    private HashSet<string> SharedClosure(ProjectFile project) =>
        Closure(project, DependencyLink.Shared);

    /// <summary>
    /// The packages reachable from a project by one kind of link.
    ///
    /// The walk crosses a *source* edge whichever kind it is looking for: a
    /// source dependency's files are in this compilation, so both what it is
    /// made of and what it was bound against are this compilation's too. A
    /// shared edge is only crossed when looking for shared ones, because a
    /// shared dependency's own source stays on its side of the boundary.
    /// </summary>
    private HashSet<string> Closure(ProjectFile project, DependencyLink wanted)
    {
        var found = new HashSet<string>(StringComparer.Ordinal);
        Walk(project, wanted, found, new HashSet<string>(StringComparer.Ordinal));
        return found;
    }

    private void Walk(
        ProjectFile project, DependencyLink wanted, HashSet<string> found, HashSet<string> visited)
    {
        foreach (var (name, dependency) in project.Dependencies)
        {
            if (!_packages.TryGetValue(name, out var package)) continue;

            if (dependency.Link == wanted) found.Add(name);

            if (dependency.Link != DependencyLink.Source && wanted != DependencyLink.Shared)
                continue;

            // `visited` and not `found`, because a package can be walked
            // through without being one of the kind being collected -- and
            // because resolution rejects cycles, so this is about not walking a
            // diamond twice rather than about terminating.
            if (visited.Add(name)) Walk(package.Project, wanted, found, visited);
        }
    }

    /// <summary>
    /// Compares what a dependency just described against what the lock file
    /// recorded the last time it was built.
    ///
    /// A difference here, with the same source and the same commit, means the
    /// two builds were not the same build -- a different compiler, or a
    /// different ABI. That is worth stopping for, because the consumer's object
    /// code has one of those two layouts compiled into it and the linker cannot
    /// tell which.
    /// </summary>
    private static string? CheckAbiDigest(
        ResolvedPackage package, ModuleMetadata? before, ModuleMetadata after)
    {
        if (before is null || before.AbiDigest.Length == 0) return null;
        if (before.AbiDigest == after.AbiDigest) return null;

        // A new version is allowed to describe a new surface -- that is what a
        // version is for. What is worth saying is the other case: the number
        // stayed still and the layouts did not.
        if (before.PackageVersion != after.PackageVersion) return null;

        var broken = WhatBroke(before, after);

        // A surface that only grew is not a broken promise. Something compiled
        // against the smaller one calls what it always called, at the offsets it
        // always called them at -- a minor version would be the polite way to
        // announce the addition, and nothing is unsafe if it is not.
        if (broken.Count == 0) return null;

        return
            $"'{package.Name}' {after.PackageVersion} describes a different surface than the last " +
            $"build of {after.PackageVersion} did: {Name(broken)}. A version number is a promise " +
            "about exactly this, and whatever was compiled against the old surface has those " +
            "offsets and signatures built into it -- the linker cannot tell, because the symbols " +
            "did not change. Give the new surface a new version, and rebuild what depends on it.";
    }

    /// <summary>
    /// What a consumer of the old surface can no longer rely on: everything that
    /// changed shape, and everything that is gone.
    ///
    /// Additions are deliberately not in here. They are the one kind of change
    /// that cannot invalidate anything already compiled, and reporting them
    /// would make the common, harmless case look like the dangerous one.
    /// </summary>
    private static List<string> WhatBroke(ModuleMetadata before, ModuleMetadata after)
    {
        var broken = new List<string>();

        var types = after.Types.ToDictionary(t => t.Module + "." + t.Name, t => t.Digest,
            StringComparer.Ordinal);

        foreach (var type in before.Types)
        {
            string name = type.Module + "." + type.Name;

            if (!types.TryGetValue(name, out string? digest)) broken.Add(name + " (gone)");
            else if (digest != type.Digest) broken.Add(name);
        }

        var functions = after.Functions.ToDictionary(
            f => f.Symbol, Driver.Digest.OfFunction, StringComparer.Ordinal);

        foreach (var function in before.Functions)
        {
            string name = (function.Module is null ? "" : function.Module + ".") + function.Name;

            if (!functions.TryGetValue(function.Symbol, out string? digest))
                broken.Add(name + " (gone)");
            else if (digest != Driver.Digest.OfFunction(function))
                broken.Add(name);
        }

        broken.Sort(StringComparer.Ordinal);
        return broken;
    }

    /// <summary>
    /// Naming a few beats naming none; naming forty beats nothing only in
    /// theory.
    /// </summary>
    private static string Name(List<string> broken) =>
        broken.Count <= 4
            ? string.Join(", ", broken)
            : string.Join(", ", broken.Take(4)) + $", and {broken.Count - 4} more";

    /// <summary>
    /// Checks that the source being built is the source that was resolved.
    ///
    /// Git is held to it and a path is not, and the difference is what the two
    /// are for: a checkout that changed under a fixed commit is a cache that
    /// cannot be trusted, where a sibling directory changing is somebody
    /// working on it, which is the entire reason to use a path dependency. So
    /// one is an error and the other is worth a word.
    /// </summary>
    private string? CheckSourceDigests()
    {
        foreach (var package in resolution.Order)
        {
            var locked = resolution.Previous?.Find(package.Name);
            if (locked is null || locked.SourceDigest.Length == 0) continue;

            // Only where the resolver decided on the same thing it decided
            // last time. A new commit is meant to have new files in it, and so
            // is a dependency that now points somewhere else.
            if (locked.Source != package.Source || locked.Revision != package.Revision) continue;

            if (locked.SourceDigest == package.SourceDigest) continue;

            if (package.Source.StartsWith("path:", StringComparison.Ordinal))
            {
                _warnings.Add(
                    $"'{package.Name}' has changed since the lock file was written; it is a path " +
                    "dependency, so it is being built as it is now");
                continue;
            }

            string revision = package.Revision is null
                ? "the commit it was resolved to"
                : package.Revision[..Math.Min(12, package.Revision.Length)];

            return
                $"'{package.Name}' is locked to {revision}, and the files in the package cache " +
                "are not the ones that commit was resolved to. A fixed commit does not change, " +
                $"so the cache has been edited or damaged: delete '{package.Directory}' and run " +
                "'stainless restore'.";
        }

        return null;
    }

    // ------------------------------------------------------------- options

    /// <summary>
    /// The compilation for one package: its own sources, everything its source
    /// dependencies bring with them, and a reference to every shared one.
    /// </summary>
    private CompilationOptions? OptionsFor(
        ProjectFile project, BuildOverrides overrides, string output,
        string? metadata = null, string? intermediate = null)
    {
        _error = null;

        var paths = new List<string>();
        var libraries = new List<string>();
        var references = new List<string>();
        var linkInputs = new List<string>();

        Collect(project, paths, libraries, references, linkInputs, new HashSet<string>(StringComparer.Ordinal));

        bool isRoot = ReferenceEquals(project, root);
        if (isRoot) paths.AddRange(overrides.ExtraPaths);

        // Where this build puts what it writes, so that scanning `"."` does not
        // feed the last build's output back in.
        var sources = Compilation.CollectSourceFiles(paths, [
            BuildDirectory(overrides),
            IntermediateDirectory(overrides),
        ]);
        if (sources.Errors.Count > 0)
        {
            _error = string.Join("\n", sources.Errors);
            return null;
        }

        if (sources.Sources.Count == 0)
        {
            _error = $"'{project.Path}' found no {Compilation.SourceExtension} files under " +
                     string.Join(", ", project.SourcesFor(_target).Select(s => $"'{s}'"));
            return null;
        }

        if (isRoot)
        {
            libraries.AddRange(overrides.Libraries);

            // Beside the binary rather than at the project's own metadata path,
            // because '-o' may have moved the binary and the two are a pair.
            if (metadata is null && project.IsLibrary)
                metadata = ProjectFile.MetadataBeside(output, project.Name);
        }

        // A dependency is built for the program that needs it, so the answers
        // that have to match across a boundary are the root's: one ABI and one
        // runtime, whatever the dependency's own project file happens to say.
        // The rest -- optimisation, debug info -- is inherited for consistency
        // rather than for correctness.
        return new CompilationOptions
        {
            SourcePaths = sources.Sources,
            NativeInputs = [.. sources.NativeInputs, .. linkInputs],
            ResourceScripts = sources.ResourceScripts,
            Libraries = libraries.Distinct(StringComparer.Ordinal).ToList(),
            References = references,
            OutputPath = output,
            IntermediateDirectory = intermediate ?? IntermediateDirectory(overrides),
            OptimizationLevel = overrides.OptimizationLevel ?? root.Optimize,
            Debug = overrides.Debug ?? root.Debug,
            DebugFormat = overrides.DebugFormat,
            KeepIntermediates = overrides.KeepIntermediates,
            EmitIrOnly = overrides.EmitIrOnly && isRoot,
            DocumentationPath = isRoot ? overrides.DocumentationPath : null,
            DocumentStandardLibrary = overrides.DocumentStandardLibrary,
            DocumentationOnly = overrides.DocumentationOnly && isRoot,
            Defines = [.. project.DefinesFor(_target), .. overrides.Defines],
            Target = overrides.Target,
            CppAbi = overrides.CppAbi ?? (root.Abi is null ? null : ProjectFile.ParseAbi(root.Abi)),
            SharedRuntime = overrides.SharedRuntime ?? (root.Runtime switch
            {
                "shared" => true,
                "static" => false,
                _ => null,
            }),
            Shared = project.IsLibrary,
            MetadataPath = metadata,
            HeaderPath = isRoot ? overrides.HeaderPath ?? Resolved(project, project.Header) : null,
            ModuleDefinitionPath = isRoot ? overrides.ModuleDefinitionPath : null,
            PackageName = project.Name,
            PackageVersion = project.Version,
        };
    }

    private static string? Resolved(ProjectFile project, string? path) =>
        path is null ? null : project.Resolve(path);

    /// <summary>
    /// Walks what a package needs, gathering the two kinds separately.
    ///
    /// A source dependency contributes its files *and whatever it in turn needs*,
    /// because compiling it in means compiling in everything it is made of. A
    /// shared one contributes a reference and a thing to link, and its own
    /// sources stay on its side of the boundary -- but its shared dependencies
    /// come along, because its public surface may name their types and the
    /// consumer has to be able to resolve those names.
    /// </summary>
    private void Collect(
        ProjectFile project, List<string> paths, List<string> libraries,
        List<string> references, List<string> linkInputs, HashSet<string> seen)
    {
        foreach (string source in project.SourcesFor(_target))
            paths.Add(project.Resolve(source));

        libraries.AddRange(project.LibrariesFor(_target));

        foreach (var (name, dependency) in project.Dependencies
                     .OrderBy(d => d.Key, StringComparer.Ordinal))
        {
            if (!seen.Add(name)) continue;
            if (!_packages.TryGetValue(name, out var package)) continue;

            if (dependency.Link == DependencyLink.Source)
            {
                Collect(package.Project, paths, libraries, references, linkInputs, seen);
                continue;
            }

            if (!_libraries.TryGetValue(name, out var built)) continue;

            references.Add(built.Metadata);
            linkInputs.Add(built.LinkInput);

            // Its shared dependencies, whose types its surface may name.
            CollectShared(package.Project, references, linkInputs, seen);
        }
    }

    private void CollectShared(
        ProjectFile project, List<string> references, List<string> linkInputs, HashSet<string> seen)
    {
        foreach (var (name, dependency) in project.Dependencies
                     .OrderBy(d => d.Key, StringComparer.Ordinal))
        {
            if (dependency.Link != DependencyLink.Shared) continue;
            if (!seen.Add(name)) continue;
            if (!_libraries.TryGetValue(name, out var built)) continue;

            references.Add(built.Metadata);
            linkInputs.Add(built.LinkInput);

            if (_packages.TryGetValue(name, out var package))
                CollectShared(package.Project, references, linkInputs, seen);
        }
    }

    /// <summary>
    /// What a link line names for a shared library: the import library beside it
    /// on Windows, and the shared object itself everywhere else. The same rule
    /// the runtime is linked by, for the same reason.
    /// </summary>
    private static string LinkInput(string library) =>
        OperatingSystem.IsWindows() ? Path.ChangeExtension(library, ".lib") : library;

    private string BuildDirectory(BuildOverrides overrides) =>
        overrides.OutputPath is not null
            ? Path.GetDirectoryName(Path.GetFullPath(overrides.OutputPath)) ?? "."
            : root.Resolve(root.BuildDirectory);

    private string IntermediateDirectory(BuildOverrides overrides) =>
        overrides.IntermediateDirectory ?? root.Resolve(root.ObjectDirectory);

    /// <summary>
    /// The lock with what this build learned added to it: the digest of every
    /// shared dependency, which only a build can know.
    /// </summary>
    private PackageLock? UpdatedLock()
    {
        if (resolution.Lock is null || _digests.Count == 0) return resolution.Lock;

        return resolution.Lock with
        {
            Packages = resolution.Lock.Packages
                .Select(p => _digests.TryGetValue(p.Name, out string? digest)
                    ? p with { AbiDigest = digest }
                    : p)
                .ToList(),
        };
    }

    private void Log(string message) => log?.Invoke(message);
}
