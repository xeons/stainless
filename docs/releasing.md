<sub>[Stainless](../README.md) &rsaquo; Releasing</sub>

# Releasing

What a version number means here, how a release is cut, and what it holds.

---

## The version

**A version is `<major>.<minor>.<count>`**, and the count is the number of
commits reachable from the one being built — `git rev-list --count HEAD`. So a
commit has exactly one version, and the number only rises along a branch.
`VersionPrefix` in [Directory.Build.props](../Directory.Build.props) is the
major and minor, and the only place either is written.

```
$ stainless --version
stainless 0.1.478+a13d1a2
```

After the `+` is the short hash of the commit, and `-dirty` when a tracked file
differed from it at build time. A CI build never says `-dirty`: its checkout is
clean by construction, and the check is skipped there.

[tools/Version.proj](../tools/Version.proj) computes all of it, and every
project's assembly and file version is stamped from it. It runs once per build,
not once per project, because every project reaches it through one shared
evaluation. To see what the tree would build as:

```
dotnet msbuild tools/Version.proj -t:ComputeStainlessVersion -getProperty:StainlessInformationalVersion
```

**A tree with no history builds as `<major>.<minor>.0`**: a source archive, a
shallow clone, a machine with no git. `-p:StainlessBuildNumber=` and
`-p:StainlessCommit=` override what git would say. CI checks out with
`fetch-depth: 0` for this reason.

A new major or minor is a one-line change to `VersionPrefix`. The count carries
on from where it was rather than restarting, so `0.2.500` may follow `0.1.499`.

## Publishing

```
.\tools\publish.ps1                  # Windows, win-x64 unless -Runtime says
tools/publish.sh                     # Linux, linux-x64 unless an argument says
```

Each publishes the compiler single-file, self-contained and ReadyToRun into
`artifacts/<rid>/publish`, then runs it: `--version` MUST answer the version
Version.proj computed, and `samples/hello.sl` MUST build in an empty directory
and print its line. Then it packages. A runtime identifier for another machine
is published and packaged untested, with a warning.

**The binary needs no .NET install**, and is about 90 MB. ReadyToRun is most of
that, and is what makes a compile start warm: `emit-ir` of the IDE takes
1.00 s published, against 1.43 s for a Release build that JITs and 1.63 s for
Debug. Compressing inside the single file would halve it and add a tenth of a
second to every run, so it is not done; the archive is compressed anyway.
Trimming is off, because the compiler reads its project, lock and metadata
files with reflection-based `System.Text.Json`. The binary runs with invariant
globalization, so it does not need libicu on Linux.

**It still needs clang**, which it hands its IR to. Nothing about that changes
from a development build: `STAINLESS_CLANG`, then `PATH`, then the usual
install directories.

**The archive** is `artifacts/stainless-<version>-<rid>.zip` on Windows and
`.tar.gz` on Linux, unpacking to one directory of the same name:

| | |
|---|---|
| `stainless`, `stainless.exe` | the compiler, with the runtime and standard library inside |
| `INSTALL.txt` | clang, and where the compiler looks for it |
| `README.md`, `LICENSE`, `LICENSE.RUNTIME` | |
| `docs/`, `samples/` | as in the repository |
| `bindings/`, `forms/` | source, which a program compiles in by naming it |

Only tracked files go in, so a publish needs a git checkout.

**Only x64 is published.** The compiler targets ARM64, but the ARM64 cases stop
at an object file because there is no ARM64 machine to run them, and macOS is
not tested at all. Either is a matrix entry in the release workflow once
something runs its cases.

## Cutting a release

[.github/workflows/release.yml](../.github/workflows/release.yml) does it,
started either way:

- **Push a tag** `v<version>` on the commit to release. The tag MUST be that
  commit's version, so find it first:

  ```
  git rev-list --count HEAD          # 478, so the tag is v0.1.478
  git tag v0.1.478
  git push origin v0.1.478
  ```

- **Or run the workflow by hand** from the Actions tab, on the branch to
  release. It releases the head of that branch and makes the tag itself.

A tag whose major and minor disagree with `VersionPrefix`, or that sits on a
commit building as a different number, fails before anything is built, and
says which.

The workflow then runs [ci.yml](../.github/workflows/ci.yml) in full — both
suites, on Linux and Windows — as its gate. It publishes each runtime on its
own platform, and creates the GitHub release: `Stainless <version>`, notes
generated from the commits and pull requests since the last one, and the
archives with a `SHA256SUMS` beside them.

A release that has to be redone is deleted with its tag and run again:
`gh release delete v0.1.478 --cleanup-tag`.
