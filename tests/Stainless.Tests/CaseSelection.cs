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

namespace Stainless.Tests;

/// <summary>
/// Which cases a host runs, and what each is measured against. Every answer
/// takes the host as an argument, so the unit tests can ask as a Mac would.
/// The unit test project compiles this file too.
/// </summary>
internal static class CaseSelection
{
    /// <summary>What a platform is called in platform.txt and expected.*.txt.</summary>
    public static string FormatPlatformName(TargetOS os) => os switch
    {
        TargetOS.Windows => "windows",
        TargetOS.Linux => "linux",
        TargetOS.MacOS => "macos",
        _ => throw new ArgumentOutOfRangeException(nameof(os)),
    };

    /// <summary>
    /// Why this case is not run on <paramref name="host"/>, or null when it is.
    /// A case without a target.txt is built for <paramref name="defaultTarget"/>,
    /// or for the host when that is null. <paramref name="rosetta"/> says an
    /// Apple silicon host can run Intel binaries.
    /// </summary>
    public static string? FindSkipReason(
        string directory, TargetPlatform host, TargetPlatform? defaultTarget = null, bool rosetta = false)
    {
        string platformPath = Path.Combine(directory, "platform.txt");
        if (File.Exists(platformPath))
        {
            string wanted = File.ReadAllText(platformPath).Trim().ToLowerInvariant();
            if (wanted is not ("windows" or "linux" or "macos"))
                throw new InvalidOperationException($"unknown platform '{wanted}'");
            if (wanted != FormatPlatformName(host.Os))
                return $"{wanted} only";
        }

        string targetPath = Path.Combine(directory, "target.txt");
        TargetPlatform target;
        if (File.Exists(targetPath))
        {
            string named = File.ReadAllText(targetPath).Trim();
            if (TargetPlatform.Parse(named, host.Os) is not { } parsed)
            {
                if (TargetPlatform.RefusalFor(named, host.Os) is null)
                    throw new InvalidOperationException($"unknown target '{named}'");
                return $"no {named} target on {FormatPlatformName(host.Os)}";
            }
            target = parsed;
        }
        else if (defaultTarget is null)
        {
            return null;
        }
        else
        {
            target = defaultTarget;
        }

        // Only a case that runs what it built needs a machine for the target.
        // An assemble-only case stops at an object file and an errors.txt case
        // at a diagnostic, and every host builds those.
        bool runs = !File.Exists(Path.Combine(directory, "assemble.txt"))
                    && !File.Exists(Path.Combine(directory, "errors.txt"));

        return runs && !CanRun(host, target, rosetta) ? $"{target.Name} cannot run on {host.Name}" : null;
    }

    /// <summary>
    /// Whether a program built for <paramref name="target"/> runs on
    /// <paramref name="host"/>. Another system never does. WOW64 and Linux run
    /// x86 on x86-64, and Windows on ARM emulates both. Apple silicon runs an
    /// Intel binary only through Rosetta, which is installed separately and is
    /// what <paramref name="rosetta"/> says.
    /// </summary>
    public static bool CanRun(TargetPlatform host, TargetPlatform target, bool rosetta = false)
    {
        if (target.Os != host.Os)
            return false;
        if (target.Architecture == host.Architecture)
            return true;

        return (host.Os, host.Architecture, target.Architecture) switch
        {
            (TargetOS.Windows or TargetOS.Linux, TargetArch.X64, TargetArch.X86) => true,
            (TargetOS.Windows, TargetArch.Arm64, TargetArch.X64 or TargetArch.X86) => true,
            (TargetOS.MacOS, TargetArch.Arm64, TargetArch.X64) => rosetta,
            _ => false,
        };
    }

    /// <summary>
    /// The expectation to measure against: <c>expected.&lt;platform&gt;.txt</c>
    /// for this host, then, on macOS only, <c>expected.linux.txt</c>, then
    /// <c>expected.txt</c>. Every case with a Linux file differs from Windows
    /// by POSIX behaviour, which macOS shares. A Mac that answers differently
    /// MUST say so with an <c>expected.macos.txt</c> of its own.
    /// </summary>
    public static string FindExpectedOutputPath(string directory, TargetOS host)
    {
        string specific = Path.Combine(directory, $"expected.{FormatPlatformName(host)}.txt");
        if (File.Exists(specific))
            return specific;

        string posix = Path.Combine(directory, "expected.linux.txt");
        if (host == TargetOS.MacOS && File.Exists(posix))
            return posix;

        return Path.Combine(directory, "expected.txt");
    }

    /// <summary>
    /// Whether this Mac has Rosetta. The runtime it installs is what an Intel
    /// binary is translated by, and it is absent until someone installs it.
    /// </summary>
    public static bool HasRosetta =>
        OperatingSystem.IsMacOS() && File.Exists("/Library/Apple/usr/libexec/oah/libRosettaRuntime");

    /// <summary>
    /// The flag that lets a C consumer find the library beside it, or null
    /// where the loader looks there anyway, as Windows does for a DLL.
    /// </summary>
    public static string? FormatConsumerRunPath(TargetOS host) => host switch
    {
        TargetOS.Windows => null,
        TargetOS.Linux => "-Wl,-rpath,$ORIGIN",
        TargetOS.MacOS => "-Wl,-rpath,@loader_path",
        _ => throw new ArgumentOutOfRangeException(nameof(host)),
    };
}
