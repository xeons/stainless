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
using System.Security.Cryptography;
using System.Text;

namespace Stainless.Driver;

/// <summary>One package, settled: where it is, what it is, and what it needs.</summary>
public sealed record ResolvedPackage
{
    public required string Name { get; init; }

    /// <summary>Its own project file, read from wherever it was materialized.</summary>
    public required ProjectFile Project { get; init; }

    /// <summary>Where it is on disk now: a sibling directory, or the cache.</summary>
    public required string Directory { get; init; }

    public required DependencyLink Link { get; init; }

    /// <summary>The identity a lock file compares: "path:..." or "git:...".</summary>
    public required string Source { get; init; }

    public string? Revision { get; init; }
    public string SourceDigest { get; init; } = "";

    /// <summary>What this package depends on, by name.</summary>
    public IReadOnlyList<string> Dependencies { get; init; } = [];

    /// <summary>Who first asked for it, so a conflict can say where it came from.</summary>
    public required string RequestedBy { get; init; }
}

public sealed record Resolution
{
    public required bool Success { get; init; }
    public string? Error { get; init; }

    /// <summary>
    /// Every package the root needs, dependencies before the packages that
    /// depend on them, so building in this order never waits for anything.
    /// </summary>
    public IReadOnlyList<ResolvedPackage> Order { get; init; } = [];

    /// <summary>What this resolution decided.</summary>
    public PackageLock? Lock { get; init; }

    /// <summary>
    /// What the last one decided, if there was one.
    ///
    /// Kept separate from <see cref="Lock"/> because the build has questions
    /// that are about the difference between the two -- did this dependency's
    /// files change since it was locked -- and comparing the new lock against
    /// itself would answer every one of them "no".
    /// </summary>
    public PackageLock? Previous { get; init; }

    public static Resolution Failed(string error) => new() { Success = false, Error = error };
}

/// <summary>
/// Turns what a project asked for into exactly what will be built.
///
/// What this does not do is *choose* between versions, and it is worth being
/// straight about why: there is no registry, so nothing here can offer an
/// alternative. A path is whatever is in the directory and a git tag is whatever
/// that tag points at -- each source pins exactly one version, and resolving is
/// therefore unifying sources rather than searching versions. Every requirement
/// still has to accept what it gets, so an impossible set of requirements is a
/// message rather than a mystery; but the day a registry exists, the searching
/// goes here and nothing above it changes.
/// </summary>
public sealed class PackageResolver(
    string? cacheDirectory = null,
    bool offline = false,
    Action<string>? log = null)
{
    private readonly string _cache = cacheDirectory ?? DefaultCacheDirectory();

    private readonly Dictionary<string, ResolvedPackage> _chosen = new(StringComparer.Ordinal);
    private readonly List<ResolvedPackage> _order = [];

    /// <summary>Names currently being visited, which is what makes a cycle findable.</summary>
    private readonly List<string> _stack = [];

    /// <summary>
    /// Where fetched packages live. <c>STAINLESS_HOME</c> overrides it, which is
    /// what a build machine wanting the cache somewhere it controls will use.
    /// </summary>
    public static string DefaultCacheDirectory()
    {
        if (Environment.GetEnvironmentVariable("STAINLESS_HOME") is { Length: > 0 } home)
            return Path.Combine(home, "cache");

        // On Windows the cache needs saying, because LocalApplicationData holds
        // every kind of thing. Outside it, the directory is already a cache and
        // saying so again would name it ~/.cache/stainless/cache.
        if (OperatingSystem.IsWindows())
            return Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "stainless", "cache");

        string root = Environment.GetEnvironmentVariable("XDG_CACHE_HOME") is { Length: > 0 } xdg
            ? xdg
            : Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".cache");

        return Path.Combine(root, "stainless");
    }

    /// <summary>
    /// Resolves the whole graph below <paramref name="root"/>.
    ///
    /// <paramref name="existing"/> is last time's answer. Unless
    /// <paramref name="update"/> says otherwise it is believed for anything it
    /// still describes -- which is what makes a locked build reproducible, and
    /// what stops a tag that moved underneath from changing a build nobody
    /// touched.
    /// </summary>
    public Resolution Resolve(ProjectFile root, PackageLock? existing = null, bool update = false)
    {
        _chosen.Clear();
        _order.Clear();
        _stack.Clear();

        try
        {
            foreach (var (name, dependency) in root.Dependencies.OrderBy(d => d.Key, StringComparer.Ordinal))
                Visit(name, dependency, root, existing, update);
        }
        catch (ResolutionError e)
        {
            return Resolution.Failed(e.Message);
        }

        var locked = new PackageLock
        {
            Root = root.Name,
            Packages = _order.Select(p => new LockedPackage
            {
                Name = p.Name,
                Version = p.Project.Version,
                Source = p.Source,
                Revision = p.Revision,
                Link = p.Link,
                SourceDigest = p.SourceDigest,

                // Carried over rather than recomputed: it comes from a build,
                // and resolving is not one. The builder fills it in.
                //
                // Only where nothing about the source moved, though. A digest
                // kept across a change to the files it was taken from would be
                // a record of a build that no longer exists, and the check it
                // feeds would fire on every legitimate edit.
                AbiDigest = existing?.Find(p.Name) is { } previous &&
                            previous.Source == p.Source &&
                            previous.Revision == p.Revision &&
                            previous.SourceDigest == p.SourceDigest
                    ? previous.AbiDigest
                    : null,
                Dependencies = [.. p.Dependencies],
            }).ToList(),
        };

        return new Resolution
        {
            Success = true,
            Order = _order,
            Lock = locked,
            Previous = existing,
        };
    }

    private void Visit(
        string name, Dependency dependency, ProjectFile requester,
        PackageLock? existing, bool update)
    {
        if (_stack.Contains(name, StringComparer.Ordinal))
            throw new ResolutionError(
                $"the dependencies form a cycle: {string.Join(" -> ", _stack)} -> {name}. " +
                "A package cannot be built before itself; break the cycle by moving what both " +
                "sides need into a third package");

        string source = Identity(dependency);

        if (_chosen.TryGetValue(name, out var already))
        {
            Agree(name, already, dependency, source, requester);
            return;
        }

        var (directory, revision) = Materialize(name, dependency, requester, existing, update);

        string manifest = Path.Combine(directory, ProjectFile.FileName);
        if (!File.Exists(manifest))
            throw new ResolutionError(
                $"the dependency '{name}' is at '{Short(directory)}', which has no " +
                $"{ProjectFile.FileName}. A package is a directory with a project file in it; " +
                "a directory of sources is reached with a path in 'sources' instead");

        var project = ProjectFile.Read(manifest, out string error)
            ?? throw new ResolutionError(error);

        if (!string.Equals(project.Name, name, StringComparison.Ordinal))
            throw new ResolutionError(
                $"'{requester.Path}' calls this dependency '{name}', and '{Short(manifest)}' " +
                $"calls it '{project.Name}'. One package has one name -- two names for it is how " +
                "a lock file starts describing something that is not there");

        if (!project.IsLibrary)
            throw new ResolutionError(
                $"'{name}' is an executable, and an executable cannot be depended on: it has a " +
                $"Main and no surface to bind against. Set \"kind\": \"library\" in " +
                $"'{Short(manifest)}' if it is meant to be one");

        var requirement = dependency.Requirement();
        var version = project.SemanticVersion();

        if (!requirement.Accepts(version))
            throw new ResolutionError(
                $"'{requester.Name}' needs '{name}' {requirement}, and the one at " +
                $"'{Short(directory)}' is {version}");

        _stack.Add(name);

        var children = project.Dependencies.OrderBy(d => d.Key, StringComparer.Ordinal).ToList();
        foreach (var (childName, child) in children)
            Visit(childName, child, project, existing, update);

        _stack.RemoveAt(_stack.Count - 1);

        var resolved = new ResolvedPackage
        {
            Name = name,
            Project = project,
            Directory = directory,
            Link = dependency.Link,
            Source = source,
            Revision = revision,
            SourceDigest = Digest.OfDirectory(directory),
            Dependencies = children.Select(c => c.Key).ToList(),
            RequestedBy = requester.Name,
        };

        _chosen[name] = resolved;

        // After its children, so the list comes out with everything already
        // built by the time the thing needing it is reached.
        _order.Add(resolved);
    }

    /// <summary>
    /// Checks that a second request for a package can live with the first.
    ///
    /// The interesting failure is not two versions -- it is two *sources*, where
    /// a path dependency during development and a git one in the release
    /// quietly become two copies of a package with one name. Two copies of a
    /// class is two layouts, and the reference counts on either side of the
    /// boundary do not add up.
    /// </summary>
    private static void Agree(
        string name, ResolvedPackage already, Dependency dependency, string source,
        ProjectFile requester)
    {
        if (!string.Equals(already.Source, source, StringComparison.Ordinal))
            throw new ResolutionError(
                $"'{name}' is needed from two places: '{already.Source}' for " +
                $"'{already.RequestedBy}' and '{source}' for '{requester.Name}'. One package is " +
                "one copy -- two would be two layouts and two sets of reference counts under one " +
                "name");

        if (already.Link != dependency.Link)
            throw new ResolutionError(
                $"'{name}' is linked two ways: '{already.Link.ToString().ToLowerInvariant()}' for " +
                $"'{already.RequestedBy}' and '{dependency.Link.ToString().ToLowerInvariant()}' " +
                $"for '{requester.Name}'. Linking it both ways would compile its code into this " +
                "program and load another copy beside it");

        var requirement = dependency.Requirement();
        var version = already.Project.SemanticVersion();

        if (!requirement.Accepts(version))
            throw new ResolutionError(
                $"'{requester.Name}' needs '{name}' {requirement}, and what the rest of the " +
                $"program is using is {version} from '{already.Source}'. There is no registry to " +
                "offer another, so this is settled by changing a requirement or by moving one of " +
                "them to its own package");
    }

    /// <summary>The string a lock file compares two requests for one package by.</summary>
    private static string Identity(Dependency dependency)
    {
        if (dependency.Path is not null)
            // Forward slashes so a lock file written on one platform is the one
            // the other verifies against.
            return "path:" + dependency.Path.Replace('\\', '/');

        string pin = dependency.Tag is not null ? "#" + dependency.Tag
            : dependency.Rev is not null ? "@" + dependency.Rev
            : dependency.Branch is not null ? ":" + dependency.Branch
            : "";

        return "git:" + dependency.Git + pin +
               (dependency.Subdirectory is null ? "" : "/" + dependency.Subdirectory);
    }

    // ------------------------------------------------------------- fetching

    /// <summary>Puts a dependency somewhere on disk and says where.</summary>
    private (string Directory, string? Revision) Materialize(
        string name, Dependency dependency, ProjectFile requester,
        PackageLock? existing, bool update)
    {
        if (dependency.Path is not null)
        {
            string directory = requester.Resolve(dependency.Path);

            if (!Directory.Exists(directory))
                throw new ResolutionError(
                    $"'{requester.Path}' depends on '{name}' at '{dependency.Path}', and there " +
                    $"is no directory there. The path is relative to the project file, not to " +
                    "wherever the build was started");

            return (directory, null);
        }

        // A locked revision beats the tag that produced it: that is the whole
        // job of a lock file, since a tag can be moved and a branch is meant to.
        string? pinned = update
            ? null
            : existing?.Find(name) is { } locked && locked.Source == Identity(dependency)
                ? locked.Revision
                : null;

        return FetchGit(name, dependency, pinned, update);
    }

    private (string Directory, string? Revision) FetchGit(
        string name, Dependency dependency, string? pinned, bool update)
    {
        string url = dependency.Git!;

        // Keyed by what the project file asked for, not by what that resolved
        // to. A tag and the commit behind it are the same checkout, and keying
        // by the commit would clone the repository a second time the moment a
        // lock file turned the first one into the second.
        string pin = dependency.Tag ?? dependency.Rev ?? dependency.Branch ?? "HEAD";

        string checkout = Path.Combine(_cache, "git", name, ShortHash(url), Sanitize(pin));

        bool present = Directory.Exists(Path.Combine(checkout, ".git"));

        if (!present)
        {
            if (offline)
                throw new ResolutionError(
                    $"'{name}' is not in the package cache and this is an offline build. Run " +
                    "'stainless restore' with a network, or point the dependency at a path");

            Clone(name, url, pinned ?? pin, checkout, byRevision: pinned is not null || dependency.Rev is not null);
        }
        else if (pinned is null && !offline && (update || dependency.Branch is not null))
        {
            // Two reasons to go back to the remote for a checkout that is
            // already here. A branch is expected to move, so it is re-read every
            // time. A tag is not -- and 'stainless restore --update' is exactly
            // the request to check anyway, which is what makes a tag that was
            // moved underneath something that can be found rather than something
            // that quietly persists.
            //
            // A revision pinned in the project file is neither: it cannot have
            // changed, so it is never re-fetched.
            if (dependency.Rev is null)
            {
                Log($"updating {name} from {url} ({pin})");
                Git(checkout, ["fetch", "--quiet", "--depth", "1", "origin", pin]);
                Git(checkout, ["reset", "--quiet", "--hard", "FETCH_HEAD"]);
            }
        }

        string revision = Git(checkout, ["rev-parse", "HEAD"]).Trim();

        // The checkout is there and is not what the lock says. Either the tag
        // was moved under it or the branch advanced; the lock is what wins, and
        // fetching one commit is what gets there.
        if (pinned is not null && revision != pinned)
        {
            if (offline)
                throw new ResolutionError(
                    $"'{name}' is locked to {pinned[..Math.Min(12, pinned.Length)]}, the package " +
                    $"cache holds {revision[..Math.Min(12, revision.Length)]}, and this is an " +
                    "offline build. Run 'stainless restore' with a network");

            Log($"moving {name} to the locked {pinned[..Math.Min(12, pinned.Length)]}");
            Fetch(checkout, pinned);
            revision = Git(checkout, ["rev-parse", "HEAD"]).Trim();
        }

        string directory = dependency.Subdirectory is null
            ? checkout
            : Path.Combine(checkout, dependency.Subdirectory);

        if (!Directory.Exists(directory))
            throw new ResolutionError(
                $"'{name}' names the subdirectory '{dependency.Subdirectory}', which is not in " +
                $"{url} at {pin}");

        return (directory, revision);
    }

    private void Clone(string name, string url, string pin, string checkout, bool byRevision)
    {
        Log($"fetching {name} from {url} ({pin})");

        Directory.CreateDirectory(Path.GetDirectoryName(checkout)!);

        // A revision cannot be cloned shallowly by name -- '--branch' takes a
        // tag or a branch and nothing else -- so that case takes the whole
        // history and then checks out. Everything else takes one commit.
        if (byRevision)
        {
            Git(null, ["clone", "--quiet", url, checkout]);
            Git(checkout, ["checkout", "--quiet", pin]);
        }
        else if (pin == "HEAD")
        {
            Git(null, ["clone", "--quiet", "--depth", "1", url, checkout]);
        }
        else
        {
            Git(null, ["clone", "--quiet", "--depth", "1", "--branch", pin, url, checkout]);
        }
    }

    /// <summary>
    /// Gets one particular commit into an existing checkout.
    ///
    /// Fetching a bare revision is allowed by most servers and refused by some,
    /// and a shallow clone has nothing to walk back to when it is refused --
    /// so the fallback is to take the history and look the commit up in it.
    /// Slower, and it happens once.
    /// </summary>
    private static void Fetch(string checkout, string revision)
    {
        try
        {
            Git(checkout, ["fetch", "--quiet", "--depth", "1", "origin", revision]);
        }
        catch (ResolutionError)
        {
            Git(checkout, ["fetch", "--quiet", "--unshallow", "origin"]);
        }

        Git(checkout, ["checkout", "--quiet", revision]);
    }

    /// <summary>
    /// Runs git, and turns a failure into something that says which package was
    /// being fetched rather than only what git printed.
    /// </summary>
    private static string Git(string? workingDirectory, string[] arguments)
    {
        var start = new ProcessStartInfo("git")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };

        if (workingDirectory is not null) start.WorkingDirectory = workingDirectory;
        foreach (string argument in arguments) start.ArgumentList.Add(argument);

        Process? process;
        try
        {
            process = Process.Start(start);
        }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or IOException)
        {
            throw new ResolutionError(
                "a git dependency needs git on PATH, and it could not be started: " + e.Message);
        }

        if (process is null)
            throw new ResolutionError("a git dependency needs git on PATH, and it did not start");

        string output = process.StandardOutput.ReadToEnd();
        string errors = process.StandardError.ReadToEnd();
        process.WaitForExit();

        if (process.ExitCode != 0)
            throw new ResolutionError(
                $"git {string.Join(' ', arguments)} failed:\n{errors.TrimEnd()}");

        return output;
    }

    /// <summary>
    /// Enough of a hash of the URL to keep two repositories of the same package
    /// name apart, and short enough that the cache stays readable.
    /// </summary>
    private static string ShortHash(string text) =>
        Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(text)))[..12];

    /// <summary>
    /// A tag can hold a slash -- 'release/1.2' is a common one -- and a
    /// directory name cannot hold whatever the platform reserves.
    /// </summary>
    private static string Sanitize(string pin)
    {
        var text = new StringBuilder(pin.Length);

        foreach (char c in pin)
            text.Append(char.IsAsciiLetterOrDigit(c) || c is '.' or '-' or '_' ? c : '-');

        return text.ToString();
    }

    private static string Short(string path)
    {
        string relative = Path.GetRelativePath(Environment.CurrentDirectory, path);
        return relative.Length < path.Length ? relative : path;
    }

    private void Log(string message) => log?.Invoke(message);

    /// <summary>
    /// Thrown rather than returned, because resolution is a recursive walk and
    /// threading a failure back up through it by hand would be most of the code
    /// in this file.
    /// </summary>
    private sealed class ResolutionError(string message) : Exception(message);
}
