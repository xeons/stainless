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

using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// Every sample still binds.
///
/// Nothing compiled these. The end-to-end suite runs <c>tests/cases</c> and
/// the samples are not among them, so a sample could stop matching the
/// language and the only thing that would notice is somebody reading it --
/// which is the one audience a sample has.
///
/// Binding rather than building: it takes a millisecond and catches everything
/// a sample can get wrong, since a sample is source and its mistakes are
/// source mistakes. What it does not catch is a link error, which is what
/// <c>samples/interop</c> would need its C file for.
/// </summary>
public class SampleTests
{
    /// <summary>
    /// One program's worth of sample, and what it needs to bind.
    ///
    /// Spelled out rather than discovered, because "every .sl under samples/"
    /// is not one program: <c>samples/shop</c> is six files that are one, and
    /// <c>samples/modules</c> is two. A list that has to be edited when a
    /// sample is added is the point -- a discovered one would silently stop
    /// covering a sample that moved.
    /// </summary>
    private sealed record Sample(string Name, string[] Paths)
    {
        /// <summary>A library has no <c>Main</c> and must not be asked for one.</summary>
        public bool Shared { get; init; }

        /// <summary>Windows-only, because of what it is written against.</summary>
        public bool WindowsOnly { get; init; }
    }

    private static readonly Sample[] Samples =
    [
        new("hello", ["samples/hello.sl"]),
        new("arrays", ["samples/arrays.sl"]),
        new("collections", ["samples/collections.sl"]),
        new("constraints", ["samples/constraints.sl"]),
        new("counter", ["samples/counter.sl"]),
        new("generics", ["samples/generics.sl"]),
        new("interfaces", ["samples/interfaces.sl"]),
        new("json", ["samples/json.sl"]),
        new("shapes", ["samples/shapes.sl"]),
        new("stress", ["samples/stress.sl"]),
        new("strings", ["samples/strings.sl"]),
        new("interop", ["samples/interop/interop.sl"]),

        new("modules", ["samples/modules/App.sl", "samples/modules/Geometry.sl"]),

        new("shop", [
            "samples/shop/src/Program.sl",
            "samples/shop/src/Shop/Bundles.sl",
            "samples/shop/src/Shop/Catalog/Books.sl",
            "samples/shop/src/Shop/Catalog/Subscriptions.sl",
            "samples/shop/src/Shop/Inventory.sl",
            "samples/shop/src/Shop/Pricing.sl",
        ]),

        new("library", ["samples/library/src/math.sl"]) { Shared = true },

        new("win32/report", ["samples/win32/report.sl"]) { WindowsOnly = true },
        new("win32/window", ["samples/win32/window.sl"]) { WindowsOnly = true },
    ];

    /// <summary>The Win32 samples are written against the bindings.</summary>
    private static string[] Win32Bindings() =>
        Directory.EnumerateFiles(Path.Combine(Repository.Root, "bindings", "win32"),
                                 "*.sl", SearchOption.AllDirectories)
            .OrderBy(p => p, StringComparer.Ordinal)
            .ToArray();

    public static TheoryData<string> Names()
    {
        var data = new TheoryData<string>();
        foreach (var sample in Samples) data.Add(sample.Name);
        return data;
    }

    [Theory]
    [MemberData(nameof(Names))]
    public void ASampleStillBinds(string name)
    {
        var sample = Samples.First(s => s.Name == name);

        // A Windows sample is written against `#if WINDOWS`, so on any other
        // platform it is a file of skipped text and binding it proves nothing.
        if (sample.WindowsOnly && !OperatingSystem.IsWindows()) return;

        var paths = sample.Paths.Select(p => Path.Combine(Repository.Root, p)).ToList();
        if (sample.WindowsOnly) paths.AddRange(Win32Bindings());

        Front.BindFiles(paths, out var diagnostics, sample.Shared);

        var complaints = diagnostics.Items
            .Where(d => d.Span.File is null ||
                        d.Span.File.Path.Contains("samples", StringComparison.Ordinal))
            .Select(d => $"{d.Code} {d.Message}")
            .ToList();

        Assert.Empty(complaints);
    }

    /// <summary>
    /// And every sample on disk is in the list above.
    ///
    /// The list is the thing that rots: a sample added and not listed is a
    /// sample nothing checks, which is the state all of them were in.
    /// </summary>
    [Fact]
    public void EverySampleOnDiskIsListed()
    {
        var listed = Samples
            .SelectMany(s => s.Paths)
            .Select(p => p.Replace('/', Path.DirectorySeparatorChar))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        var found = Directory
            .EnumerateFiles(Path.Combine(Repository.Root, "samples"), "*.sl",
                            SearchOption.AllDirectories)
            .Select(p => Path.GetRelativePath(Repository.Root, p))
            .ToList();

        Assert.DoesNotContain(found, p => !listed.Contains(p));
    }
}
