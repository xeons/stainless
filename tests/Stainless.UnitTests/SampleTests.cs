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

using Stainless.Source;
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

        /// <summary>Unix-only, for the same reason: the GTK bindings are `#if UNIX`.</summary>
        public bool UnixOnly { get; init; }

        /// <summary>
        /// Written against the Forms library, so it needs those sources too --
        /// and the platform bindings the backend for <i>this</i> machine is
        /// written against.
        ///
        /// <para>
        /// <b>Not platform-specific, and it used to be marked as though it
        /// were.</b> A Forms program is the same source on both, so every one
        /// of these carried <c>WindowsOnly</c> only because it needed the Win32
        /// bindings to bind. The cost of saying it that way was that on Linux
        /// the sample was skipped entirely, and on Windows the GTK half of
        /// <c>forms/src</c> is <c>#if UNIX</c> and so never parsed -- which
        /// left <c>forms/src/Platform/Gtk/</c> bound by nothing, on either
        /// platform. A mechanical rewrite then broke it in four places and
        /// three suites stayed green.
        /// </para>
        /// </summary>
        public bool NeedsForms { get; init; }
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
        new("wc", ["samples/wc.sl"]),
        new("audio", ["samples/audio/audio.sl"]),
        new("interop", ["samples/interop/interop.sl"]),

        new("modules", ["samples/modules/App.sl", "samples/modules/Geometry.sl"]),

        // Two packages, which is two project files and one program. Bound
        // together here because that is what a source dependency is: the
        // project file decides where the files come from, and the binder sees
        // the same one program either way.
        new("packages", [
            "samples/packages/app/src/App.sl",
            "samples/packages/shapes/src/Shapes.sl",
        ]),

        new("shop", [
            "samples/shop/src/Program.sl",
            "samples/shop/src/Shop/Bundles.sl",
            "samples/shop/src/Shop/Catalog/Books.sl",
            "samples/shop/src/Shop/Catalog/Subscriptions.sl",
            "samples/shop/src/Shop/Inventory.sl",
            "samples/shop/src/Shop/Pricing.sl",
        ]),

        new("library", ["samples/library/src/math.sl"]) { Shared = true },

        // A COM server, so no Main: what it exports is DllGetClassObject, and
        // the thing that calls it is the C++ host beside it.
        new("com", ["samples/com/greeter.sl"]) { Shared = true },

        new("tour", [
            "samples/tour/Platform.sl",
            "samples/tour/Types.sl",
            "samples/tour/Types.Members.sl",
            "samples/tour/Tour.sl",
            "samples/tour/Library.sl",
        ]),

        new("win32/report", ["samples/win32/report.sl"]) { WindowsOnly = true },
        new("directx/triangle", ["samples/directx/triangle.sl"]) { WindowsOnly = true },
        new("directx/cube", [
            "samples/directx/cube.sl",
            "samples/directx/tracker.sl",
        ]) { WindowsOnly = true },
        new("win32/window", ["samples/win32/window.sl"]) { WindowsOnly = true },
        new("win32/resources", ["samples/win32/resources.sl"]) { WindowsOnly = true },

        new("forms/background", ["samples/forms/background.sl"]) { NeedsForms = true },
        new("forms/demo", ["samples/forms/demo.sl"]) { NeedsForms = true },
        new("forms/common", ["samples/forms/common.sl"]) { NeedsForms = true },
        new("forms/drawn", ["samples/forms/drawn.sl"]) { NeedsForms = true },
        new("forms/buttons", ["samples/forms/buttons.sl"]) { NeedsForms = true },
        new("forms/pictures", ["samples/forms/pictures.sl"]) { NeedsForms = true },
        new("forms/clipboard", ["samples/forms/clipboard.sl"]) { NeedsForms = true },
        new("forms/controls", ["samples/forms/controls.sl"]) { NeedsForms = true },
        new("forms/core", ["samples/forms/core.sl"]) { NeedsForms = true },

        new("gtk/hello", ["samples/gtk/hello.sl"]) { UnixOnly = true },
        new("gtk/control", ["samples/gtk/control.sl"]) { UnixOnly = true },
    ];

    /// <summary>The Win32 samples are written against the bindings.</summary>
    private static string[] Win32Bindings() => BindingsUnder("win32");

    /// <summary>The Forms library's own sources, for a sample written against it.</summary>
    private static string[] FormsSources() =>
        Directory.EnumerateFiles(Path.Combine(Repository.Root, "forms", "src"),
                                 "*.sl", SearchOption.AllDirectories)
            .OrderBy(p => p, StringComparer.Ordinal)
            .ToArray();

    /// <summary>And the GTK sample against those.</summary>
    private static string[] GtkBindings() => BindingsUnder("gtk");

    private static string[] BindingsUnder(string directory) =>
        Directory.EnumerateFiles(Path.Combine(Repository.Root, "bindings", directory),
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
        if (sample.UnixOnly && OperatingSystem.IsWindows()) return;

        var paths = sample.Paths.Select(p => Path.Combine(Repository.Root, p)).ToList();
        if (sample.WindowsOnly) paths.AddRange(Win32Bindings());
        if (sample.UnixOnly) paths.AddRange(GtkBindings());

        // A Forms program needs the backend for the machine it is being bound
        // on, because that is the half of `forms/src` the preprocessor will
        // keep. Asking for the other one's bindings would bind nothing.
        if (sample.NeedsForms)
        {
            paths.AddRange(FormsSources());
            paths.AddRange(OperatingSystem.IsWindows() ? Win32Bindings() : GtkBindings());
        }

        Front.BindFiles(paths, out var diagnostics, sample.Shared);

        // The standard library's own diagnostics are not what any of these
        // tests is asking about and would show up in all of them at once, so
        // only the code a sample actually drags in is read.
        //
        // **`forms` is in this list and was not**, which cost more than the
        // omission looks like: a Forms sample binds the whole of `forms/src`,
        // so an error in the library was bound and then discarded on the way to
        // the assertion. The GTK backend's `ClientBounds` was `override` against
        // a base member that no longer existed, and this test bound it, saw the
        // error, and threw it away.
        var complaints = diagnostics.Items
            .Where(d => d.Span.File is null ||
                        d.Span.File.Path.Contains("samples", StringComparison.Ordinal) ||
                        d.Span.File.Path.Contains("bindings", StringComparison.Ordinal) ||
                        // A library the sample drags in, so its *errors* are the
                        // sample's problem -- but not its warnings. `forms/`
                        // holds two statics the sendability rule advises
                        // guarding and that only the UI thread ever touches, and
                        // §3 of concurrency.md is explicit that wrapping those
                        // in a `Mutex` they do not need is the wrong answer:
                        // the wrapper would say nothing, because it is what you
                        // write to make the compiler quiet. Declining advice is
                        // allowed; being broken is not.
                        (d.Span.File.Path.Contains("forms", StringComparison.Ordinal)
                         && d.Severity == Severity.Error))
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
