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

using Stainless.Binding;
using Stainless.Driver;
using Xunit;
using ProcessArchitecture = System.Runtime.InteropServices.Architecture;

namespace Stainless.UnitTests;

/// <summary>
/// The clang command lines a build runs, read without running them. Each
/// question is the target's to answer, so a macOS build is checked here from
/// whatever machine runs the suite.
///
/// <para>
/// The targets are chosen to name a triple on every host: Darwin always does,
/// and nothing hosts a 32-bit build. A native target would make the toolchain
/// ask clang for its default triple, and the clang here is not real.
/// </para>
/// </summary>
public class ToolchainTests
{
    private static readonly Toolchain Tools = Toolchain.FromClang("clang-that-is-never-run");

    private static readonly TargetPlatform Mac =
        TargetPlatform.HostFor(TargetOS.MacOS, ProcessArchitecture.Arm64);

    private static readonly TargetPlatform Windows =
        TargetPlatform.HostFor(TargetOS.Windows, ProcessArchitecture.X64);

    private static T Under<T>(TargetPlatform target, Func<T> body)
    {
        var before = TargetPlatform.Current;
        TargetPlatform.Current = target;
        try { return body(); }
        finally { TargetPlatform.Current = before; }
    }

    private static IReadOnlyList<string> LinkFor(
        TargetPlatform target, bool shared = false, bool debug = false,
        SharedRuntime? sharedRuntime = null, string? moduleDefinition = null) =>
        Under(target, () => Tools.LinkArguments(
            ["app.ll"], ["arc.o"], [], shared ? Toolchain.SharedLibraryFileName("shapes", target) : "app", 0,
            shared: shared, debug: debug, sharedRuntime: sharedRuntime,
            moduleDefinition: moduleDefinition));

    // ------------------------------------------------------------ --target

    [Fact]
    public void DarwinNamesItsTripleEvenOnAMac()
    {
        Assert.Contains("--target=arm64-apple-macosx13.0",
            Toolchain.TargetArgumentsFor(TargetPlatform.Arm64MacOS, Mac));
        Assert.Contains("--target=arm64-apple-macosx13.0",
            Toolchain.TargetArgumentsFor(TargetPlatform.Arm64MacOS, Windows));
    }

    [Fact]
    public void ANativeBuildElsewhereNamesNoTriple()
    {
        Assert.Empty(Toolchain.TargetArgumentsFor(TargetPlatform.X64Windows, Windows));
        Assert.Contains("--target=x86_64-pc-linux-gnu",
            Toolchain.TargetArgumentsFor(TargetPlatform.X64Linux, Windows));
    }

    // ------------------------------------------------------------ the link

    [Fact]
    public void AMacProgramIsLinkedForDarwin()
    {
        var arguments = LinkFor(TargetPlatform.Arm64MacOS);

        Assert.Contains("--target=arm64-apple-macosx13.0", arguments);
        Assert.Contains("-Wl,-dead_strip", arguments);
        Assert.DoesNotContain("-Wl,--gc-sections", arguments);
        Assert.DoesNotContain("-fuse-ld=lld", arguments);
    }

    [Fact]
    public void AMacSearchesHomebrewForANamedLibrary()
    {
        var brewed = Toolchain.FromClang("clang-that-is-never-run", "/opt/homebrew/lib");
        IReadOnlyList<string> Link(TargetPlatform target, IReadOnlyList<string> libraries) =>
            Under(target, () => brewed.LinkArguments(["app.ll"], ["arc.o"], [], "app", 0, libraries: libraries));

        var arguments = Link(TargetPlatform.Arm64MacOS, ["gtk-3"]).ToList();
        int search = arguments.IndexOf("-L/opt/homebrew/lib");
        Assert.InRange(search, 0, arguments.IndexOf("-lgtk-3") - 1);
        Assert.DoesNotContain("-L/opt/homebrew/lib", Link(TargetPlatform.Arm64MacOS, []));
        Assert.DoesNotContain("-L/opt/homebrew/lib", Link(TargetPlatform.X86Linux, ["gtk-3"]));
        Assert.DoesNotContain(LinkFor(TargetPlatform.Arm64MacOS), a => a.StartsWith("-L", StringComparison.Ordinal));
    }

    [Fact]
    public void AMacLibraryIsADylibNamedThroughTheRpath()
    {
        var runtime = new SharedRuntime("libstainless-rt.dylib", "libstainless-rt.dylib");
        var arguments = LinkFor(TargetPlatform.Arm64MacOS, shared: true, sharedRuntime: runtime);

        Assert.Contains("-dynamiclib", arguments);
        Assert.DoesNotContain("-shared", arguments);
        Assert.Contains("-Wl,-install_name,@rpath/libshapes.dylib", arguments);
        Assert.Contains("-Wl,-rpath,@loader_path", arguments);
        Assert.DoesNotContain(arguments, a => a.Contains("-soname", StringComparison.Ordinal));
    }

    [Fact]
    public void AModuleDefinitionReachesOnlyAPeLinker()
    {
        Assert.DoesNotContain(
            LinkFor(TargetPlatform.Arm64MacOS, shared: true, moduleDefinition: "shapes.def"),
            a => a.Contains("/DEF:", StringComparison.Ordinal));
        Assert.DoesNotContain(
            LinkFor(TargetPlatform.X86Linux, shared: true, moduleDefinition: "shapes.def"),
            a => a.Contains("/DEF:", StringComparison.Ordinal));
        Assert.Contains("-Wl,/DEF:shapes.def",
            LinkFor(TargetPlatform.X86Windows, shared: true, moduleDefinition: "shapes.def"));
    }

    /// <summary>
    /// clang's Darwin driver runs dsymutil after a <c>-g</c> link that also
    /// compiled something. The IR is that something, so it MUST be compiled
    /// in the link's own invocation for the DWARF to reach a .dSYM.
    /// </summary>
    [Fact]
    public void AMacDebugLinkCompilesTheIrItself()
    {
        var arguments = LinkFor(TargetPlatform.Arm64MacOS, debug: true);

        Assert.Contains("-g", arguments);
        Assert.Contains("app.ll", arguments);
        Assert.DoesNotContain("-c", arguments);
    }

    [Fact]
    public void ALinuxLibraryStillHasASoname()
    {
        var runtime = new SharedRuntime("libstainless-rt.so", "libstainless-rt.so");
        var arguments = LinkFor(TargetPlatform.X86Linux, shared: true, sharedRuntime: runtime);

        Assert.Contains("-shared", arguments);
        Assert.Contains("-Wl,-soname,libshapes.so", arguments);
        Assert.Contains("-Wl,-rpath,$ORIGIN", arguments);
        Assert.Contains("-Wl,--gc-sections", arguments);
    }

    // ------------------------------------------------------------ the runtime

    [Fact]
    public void TheMacRuntimeIsADylibNamedThroughTheRpath()
    {
        var arguments = Under(TargetPlatform.Arm64MacOS, () =>
            Tools.SharedRuntimeLinkArguments(["arc.o"], "obj/libstainless-rt.dylib", debug: false));

        Assert.Contains("--target=arm64-apple-macosx13.0", arguments);
        Assert.Contains("-dynamiclib", arguments);
        Assert.Contains("-Wl,-install_name,@rpath/libstainless-rt.dylib", arguments);
        Assert.DoesNotContain("-Wl,--no-undefined", arguments);
    }

    [Fact]
    public void ACrossBuiltRuntimeIsLinkedForItsTarget() =>
        Assert.Contains("--target=i686-pc-linux-gnu", Under(TargetPlatform.X86Linux, () =>
            Tools.SharedRuntimeLinkArguments(["arc.o"], "obj/libstainless-rt.so", debug: false)));

    [Fact]
    public void ADarwinRuntimeObjectIsNamedForItsTarget()
    {
        Assert.Equal(".arm64-macos.o", Toolchain.RuntimeObjectSuffix(
            TargetPlatform.Arm64MacOS, Windows, shared: false, debug: false, leakCheck: false));
        Assert.Equal(".arm64-macos.so.g.o", Toolchain.RuntimeObjectSuffix(
            TargetPlatform.Arm64MacOS, Mac, shared: true, debug: true, leakCheck: false));
        Assert.Equal(".o", Toolchain.RuntimeObjectSuffix(
            TargetPlatform.X64Windows, Windows, shared: false, debug: false, leakCheck: false));
    }

    // ------------------------------------------------------------ the names

    [Theory]
    [InlineData("X64Windows", "shapes.dll", ".exe")]
    [InlineData("X64Linux", "libshapes.so", "")]
    [InlineData("Arm64MacOS", "libshapes.dylib", "")]
    public void FileNamesFollowTheTarget(string target, string library, string executable)
    {
        var platform = (TargetPlatform)typeof(TargetPlatform).GetField(target)!.GetValue(null)!;

        Assert.Equal(library, Toolchain.SharedLibraryFileName("shapes", platform));
        Assert.Equal(executable, Toolchain.ExecutableExtensionFor(platform));
    }

    // ------------------------------------------------------------ the clang

    [Theory]
    [InlineData("Homebrew clang version 23.1.2\nTarget: arm64-apple-darwin24.6.0", true)]
    [InlineData("Ubuntu clang version 18.1.3 (1ubuntu1)", true)]
    [InlineData("clang version 16.0.0", true)]
    [InlineData("clang version 15.0.7", false)]
    [InlineData("Apple clang version 15.0.0 (clang-1500.3.9.4)", true)]
    [InlineData("Apple clang version 14.0.3 (clang-1403.0.22.14.1)", false)]
    [InlineData("gcc (GCC) 13.2.0", false)]
    public void OnlyLlvm16OrLaterIsAccepted(string versionOutput, bool supported) =>
        Assert.Equal(supported, Toolchain.IsSupportedClangVersion(versionOutput));
}
