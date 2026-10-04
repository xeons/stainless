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
using System.Text;
using System.Text.Json;

namespace Stainless.Bindgen;

/// <summary>
/// Generates <c>bindings/macos/&lt;Framework&gt;/</c> from the macOS SDK.
///
/// Runs on a Mac: each framework's headers are compiled by clang for both
/// targets, the declarations each framework owns are written as Stainless,
/// and where the two targets disagree a declaration is written under
/// <c>#if ARM64</c> and <c>#else</c>.
/// </summary>
internal static class Program
{
    private static readonly (string Triple, string Name)[] Targets =
        [("arm64-apple-macosx13.0", "arm64"), ("x86_64-apple-macosx13.0", "x64")];

    private static int Main(string[] args)
    {
        string output = "bindings/macos";
        string clang = Environment.GetEnvironmentVariable("STAINLESS_CLANG") ?? "clang";
        string? sdk = null;
        string? probeCase = null;
        var frameworks = new List<string>();

        for (int i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--out": output = args[++i]; break;
                case "--clang": clang = args[++i]; break;
                case "--sdk": sdk = args[++i]; break;
                case "--case": probeCase = args[++i]; break;
                default: frameworks.Add(args[i]); break;
            }
        }

        sdk ??= Run("xcrun", ["--show-sdk-path"]).Trim();
        if (frameworks.Count == 0)
        {
            Console.Error.WriteLine("usage: Stainless.Bindgen [--out dir] [--clang path] [--sdk path] Framework...");
            return 2;
        }

        // Per target, every declaration written, by owner and header, in order.
        var perTarget = new Dictionary<string, List<Emitted>>();
        var skips = new Dictionary<string, Skipped>(StringComparer.Ordinal);

        foreach (var (triple, target) in Targets)
        {
            var written = new List<Emitted>();
            var system = new Dictionary<string, Emitted>(StringComparer.Ordinal);

            foreach (string framework in frameworks)
            {
                Console.Error.WriteLine($"{framework} for {target}");
                var translation = Compile(clang, sdk, framework, triple);
                var writer = new Writer(translation, frameworks.ToHashSet(StringComparer.Ordinal));

                // On what was written: a forward declaration writes nothing
                // once its definition is known, and the definition is kept.
                var seen = new HashSet<string>(StringComparer.Ordinal);
                foreach (var declaration in translation.Declarations)
                {
                    if (Writer.OwnerOf(declaration.File) != framework) continue;
                    if (writer.Write(declaration) is { } emitted && seen.Add(emitted.Key)) written.Add(emitted);
                }

                // What the framework used from outside every framework, and
                // what that uses in turn.
                var done = new HashSet<CDecl>();
                while (writer.SystemNeeded.Except(done).ToList() is { Count: > 0 } pending)
                {
                    foreach (var declaration in pending)
                    {
                        done.Add(declaration);
                        if (writer.Write(declaration) is { } emitted)
                            system.TryAdd(emitted.Key, emitted);
                    }
                }

                foreach (var skip in writer.Skips)
                    skips.TryAdd($"{skip.Owner}/{skip.Header}/{skip.Name}", skip);
            }

            written.AddRange(system.Values.OrderBy(e => e.Header, StringComparer.Ordinal));
            perTarget[target] = Unify(written, frameworks);
        }

        // A framework that is only headers has nothing to link.
        var linkable = frameworks
            .Where(f => Directory.EnumerateFiles(
                    Path.Combine(sdk, "System/Library/Frameworks", f + ".framework"), "*.tbd", SearchOption.AllDirectories)
                .Any())
            .ToHashSet(StringComparer.Ordinal);

        WriteModules(output, perTarget, linkable);
        WriteSkipped(output, skips.Values, frameworks);
        if (probeCase is not null)
            LayoutCase.Write(probeCase, output, frameworks, perTarget["arm64"], perTarget["x64"], Includes);
        return 0;
    }

    /// <summary>
    /// One struct, one module. A struct declared with no body in one
    /// framework's header and defined in another's is the defined one; a
    /// struct only ever declared is kept by the first framework asked for.
    /// What named a dropped declaration imports the module that keeps it.
    /// </summary>
    private static List<Emitted> Unify(List<Emitted> written, IReadOnlyList<string> frameworks)
    {
        int Rank(string owner) => owner == Writer.SystemOwner ? int.MaxValue : frameworks.ToList().IndexOf(owner);

        var keeper = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var emitted in written.Where(e => e.Key.StartsWith("Struct ", StringComparison.Ordinal)))
        {
            if (!keeper.TryGetValue(emitted.Key, out string? current))
                keeper[emitted.Key] = emitted.Owner;
            else if (!emitted.IsOpaque && written.Any(e => e.Owner == current && e.Key == emitted.Key && e.IsOpaque))
                keeper[emitted.Key] = emitted.Owner;
            else if (emitted.IsOpaque && written.Any(e => e.Owner == current && e.Key == emitted.Key && e.IsOpaque) &&
                     Rank(emitted.Owner) < Rank(current))
                keeper[emitted.Key] = emitted.Owner;
        }

        var kept = written
            .Where(e => !e.Key.StartsWith("Struct ", StringComparison.Ordinal) || keeper[e.Key] == e.Owner)
            .ToList();

        foreach (var emitted in kept)
            foreach (var (owner, key) in emitted.Uses)
                if (keeper.TryGetValue(key, out string? where) && where != owner && where != emitted.Owner)
                    emitted.Imports.Add(Writer.ModuleOf(where));

        return kept;
    }

    /// <summary>The framework's headers compiled for <paramref name="triple"/>, read.</summary>
    /// <summary>
    /// Headers that cannot be included beside the rest of their framework.
    /// OpenGL's core-profile <c>gl3.h</c> refuses to share a translation unit
    /// with the legacy <c>gl.h</c>, which the umbrella includes, and
    /// <c>CGLMacro.h</c> turns every GL function into a macro.
    /// </summary>
    private static readonly HashSet<string> Excluded = new(StringComparer.Ordinal)
    {
        "OpenGL/gl3.h", "OpenGL/gl3ext.h", "OpenGL/CGLMacro.h",
    };

    /// <summary>What each framework's translation unit included, for the layout probe to include alike.</summary>
    private static readonly Dictionary<string, string> Includes = new(StringComparer.Ordinal);

    private static Translation Compile(string clang, string sdk, string framework, string triple)
    {
        string headers = Path.Combine(sdk, "System/Library/Frameworks", framework + ".framework", "Headers");
        string umbrella = Path.Combine(headers, framework + ".h");

        // The umbrella first, which includes the headers in the order they
        // expect; then every header, the subframeworks' too, since an umbrella
        // need not include them all and what it leaves out is still the
        // framework's.
        var source = new StringBuilder();
        if (File.Exists(umbrella))
            source.Append($"#include <{framework}/{framework}.h>\n");
        foreach (string header in Directory.GetFiles(headers, "*.h").Order(StringComparer.Ordinal))
            if (!Excluded.Contains($"{framework}/{Path.GetFileName(header)}"))
                source.Append($"#include \"{header}\"\n");

        string subframeworks = Path.Combine(sdk, "System/Library/Frameworks", framework + ".framework", "Frameworks");
        if (Directory.Exists(subframeworks))
            // Each subframework's own Headers, and not the same files again
            // through its Versions symlinks or headers in subdirectories that
            // only other headers include.
            foreach (string header in Directory.GetDirectories(subframeworks, "*.framework")
                         .Select(f => Path.Combine(f, "Headers"))
                         .Where(Directory.Exists)
                         .SelectMany(h => Directory.GetFiles(h, "*.h"))
                         .Order(StringComparer.Ordinal))
                source.Append($"#include \"{header}\"\n");

        string directory = Path.Combine(Path.GetTempPath(), "stainless-bindgen");
        Directory.CreateDirectory(directory);
        string input = Path.Combine(directory, $"{framework}.m");
        string json = Path.Combine(directory, $"{framework}-{triple}.json");
        File.WriteAllText(input, source.ToString());
        Includes[framework] = source.ToString();
        string[] common = ["-x", "objective-c", "-fobjc-arc", "-target", triple, "-isysroot", sdk, "-Wno-everything"];

        // The framework's own #defines, then the lines that ask clang what
        // each is, compiled with the headers.
        string preprocessed = Run(clang, [.. common, "-E", "-dD", input]);
        var definitions = Macros.ReadDefinitions(preprocessed)
            .Where(d => Writer.OwnerOf(d.File) == framework)
            .GroupBy(d => d.Name).Select(g => g.Last())
            .ToList();
        string probe = Macros.Probe(definitions);
        File.WriteAllText(input, source + probe);
        var translation = Dump(clang, common, input, json, framework);

        // A struct under `#pragma pack` is asked its alignment, which is the
        // most any of its fields is aligned to: the dump does not say the
        // pragma's value.
        var packed = translation.Declarations.OfType<CRecordDecl>()
            .Where(r => r is { HasPragmaPack: true, IsComplete: true } && r.Name.Length > 0)
            .ToList();
        if (packed.Count > 0)
        {
            var asked = new StringBuilder(source.ToString()).Append(probe);
            for (int i = 0; i < packed.Count; i++)
                asked.Append($"enum {{ {PackPrefix}{i} = _Alignof({packed[i].CSpelling}) }};\n");
            File.WriteAllText(input, asked.ToString());

            var answered = Dump(clang, common, input, json, framework);
            var values = answered.Declarations.OfType<CEnumDecl>()
                .SelectMany(e => e.Members)
                .Where(m => m.IsWritten && m.Name.StartsWith(PackPrefix, StringComparison.Ordinal))
                .ToDictionary(m => int.Parse(m.Name[PackPrefix.Length..], System.Globalization.CultureInfo.InvariantCulture),
                              m => (int)m.Value);

            for (int i = 0; i < packed.Count; i++)
                if (values.TryGetValue(i, out int pack))
                    foreach (var record in SameRecord(translation, packed[i]))
                        record.Pack = pack;
        }


        // A macro with the name of something declared is spelling that
        // declaration, which is already bound.
        var declared = translation.Declarations.Select(d => d.Name)
            .Concat(translation.Declarations.OfType<CEnumDecl>().SelectMany(e => e.Members.Select(m => m.Name)))
            .ToHashSet(StringComparer.Ordinal);
        foreach (var macro in Macros.Resolve(translation, definitions))
            if (!declared.Contains(macro.Name))
                translation.Declarations.Add(macro);

        return translation;
    }

    private const string PackPrefix = "__sl_pack_value_";

    /// <summary>The same record wherever the translation keeps it: the list, and the tag table.</summary>
    private static IEnumerable<CRecordDecl> SameRecord(Translation translation, CRecordDecl record)
    {
        yield return record;
        if (translation.Records.TryGetValue((record.Kind, record.Name), out var tagged) && !ReferenceEquals(tagged, record))
            yield return tagged;
    }

    /// <summary>
    /// <paramref name="input"/> compiled to clang's JSON dump, and read. The
    /// probe's own failures are how a macro that is no constant says so; only
    /// the headers' are worth reporting.
    /// </summary>
    private static Translation Dump(string clang, string[] common, string input, string json, string framework)
    {
        var start = new ProcessStartInfo(clang)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        foreach (string argument in (string[])[
                     .. common, "-fsyntax-only", "-ferror-limit=0", "-Xclang", "-ast-dump=json", input])
            start.ArgumentList.Add(argument);

        using (var process = Process.Start(start)!)
        using (var file = File.Create(json))
        {
            var errors = process.StandardError.ReadToEndAsync();
            process.StandardOutput.BaseStream.CopyTo(file);
            process.WaitForExit();

            // The probe's own failures are how a macro that is no constant
            // says so; only the headers' are worth reporting.
            var headerErrors = errors.Result.Split('\n')
                .Where(l => l.Contains("error:", StringComparison.Ordinal) &&
                            !l.StartsWith(input, StringComparison.Ordinal))
                .Take(5)
                .ToList();
            if (headerErrors.Count > 0)
                Console.Error.WriteLine($"  clang reported errors for {framework}; what it did read is kept:\n" +
                                        string.Join('\n', headerErrors));
        }

        return AstReader.ReadFile(json);
    }

    /// <summary>
    /// Every module, a file per header. A declaration the two targets wrote
    /// alike is written once; one they wrote differently, or one only one of
    /// them has, is written under the target's condition.
    /// </summary>
    private static void WriteModules(
        string output, Dictionary<string, List<Emitted>> perTarget, IReadOnlySet<string> linkable)
    {
        var arm = perTarget["arm64"];
        var intel = perTarget["x64"];

        var files = new Dictionary<(string Owner, string Header), List<string>>();
        var texts = new Dictionary<(string, string), (string? Arm, string? Intel, HashSet<string> Imports)>();

        foreach (var (emitted, isArm) in arm.Select(e => (e, true)).Concat(intel.Select(e => (e, false))))
        {
            var file = (emitted.Owner, emitted.Header);
            if (!files.TryGetValue(file, out var keys)) files[file] = keys = [];

            var key = (emitted.Owner, emitted.Key);
            if (!texts.TryGetValue(key, out var entry))
            {
                keys.Add(emitted.Key);
                entry = (null, null, new HashSet<string>(StringComparer.Ordinal));
            }

            entry.Imports.UnionWith(emitted.Imports);
            texts[key] = isArm ? entry with { Arm = emitted.Text } : entry with { Intel = emitted.Text };
        }

        foreach (string owner in files.Keys.Select(f => f.Owner).Distinct())
        {
            string directory = Path.Combine(output, owner);
            if (Directory.Exists(directory))
                foreach (string stale in Directory.GetFiles(directory, "*.sl")) File.Delete(stale);
            Directory.CreateDirectory(directory);
        }

        foreach (var ((owner, header), keys) in files)
        {
            var body = new StringBuilder();
            var imports = new SortedSet<string>(StringComparer.Ordinal);

            foreach (string key in keys)
            {
                var (armText, intelText, used) = texts[(owner, key)];
                imports.UnionWith(used);

                if (armText == intelText)
                    body.Append(armText).Append('\n');
                else if (intelText is null)
                    body.Append("#if ARM64\n").Append(armText).Append("#endif\n\n");
                else if (armText is null)
                    body.Append("#if X64\n").Append(intelText).Append("#endif\n\n");
                else
                    body.Append("#if ARM64\n").Append(armText).Append("#else\n").Append(intelText).Append("#endif\n\n");
            }

            var file = new StringBuilder();
            file.Append(License);
            file.Append($"// Generated by tools/Stainless.Bindgen from {DescribeSource(owner, header)}.\n");
            file.Append("// Do not edit; regenerate with tools/bindgen.sh.\n");
            file.Append($"module {Writer.ModuleOf(owner)};\n\n");
            foreach (string import in imports) file.Append($"import {import};\n");
            if (imports.Count > 0) file.Append('\n');
            file.Append("#if MACOS\n\n");
            if (linkable.Contains(owner)) file.Append($"#pragma comment(framework, \"{owner}\")\n\n");
            file.Append(body.ToString().TrimEnd('\n')).Append("\n\n#endif\n");

            File.WriteAllText(Path.Combine(output, owner, header + ".sl"), file.ToString().ReplaceLineEndings("\n"));
        }
    }

    private static string DescribeSource(string owner, string header) =>
        owner == Writer.SystemOwner
            ? $"the SDK's usr/include ({header.Replace('_', '/')}.h)"
            : $"{owner}.framework ({header}.h)";

    /// <summary>What could not be bound, a line each, so a regeneration shows what started or stopped binding.</summary>
    private static void WriteSkipped(string output, IEnumerable<Skipped> skips, IReadOnlyList<string> frameworks)
    {
        string path = Path.Combine(output, "skipped.txt");
        var kept = File.Exists(path)
            ? File.ReadAllLines(path).Where(l => l.Length > 0 && !l.StartsWith('#') &&
                                                 !frameworks.Contains(l.Split('/')[0]) &&
                                                 !l.StartsWith(Writer.SystemOwner + "/", StringComparison.Ordinal))
            : [];

        var lines = skips.Select(s => $"{s.Owner}/{s.Header}: {s.Name} -- {s.Reason}")
            .Concat(kept)
            .Distinct()
            .Order(StringComparer.Ordinal);

        File.WriteAllText(path,
            "# Declarations tools/Stainless.Bindgen could not bind, and why. Regenerated with the bindings.\n" +
            string.Join("\n", lines) + "\n");
    }

    private static string Run(string program, IReadOnlyList<string> arguments)
    {
        var start = new ProcessStartInfo(program) { RedirectStandardOutput = true };
        foreach (string argument in arguments) start.ArgumentList.Add(argument);
        using var process = Process.Start(start)!;
        string text = process.StandardOutput.ReadToEnd();
        process.WaitForExit();
        return text;
    }

    private const string License = """
        // Stainless - an experimental general-purpose language.
        // Copyright (C) 2026 Brandon Scott
        //
        // This file is part of the Stainless runtime library. It is free
        // software: you can redistribute it and/or modify it under the terms of
        // the GNU General Public License as published by the Free Software
        // Foundation, either version 3 of the License, or (at your option) any
        // later version.
        //
        // It is distributed in the hope that it will be useful, but WITHOUT ANY
        // WARRANTY; without even the implied warranty of MERCHANTABILITY or
        // FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
        // for more details.
        //
        // As an additional permission under section 7 of that License, compiling
        // a program with Stainless does not by itself place that program under
        // the GNU General Public License. See LICENSE.RUNTIME.
        //
        // You should have received a copy of the GNU General Public License
        // along with this program.  If not, see <https://www.gnu.org/licenses/>.


        """;
}
