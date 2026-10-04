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

using System.Globalization;
using Stainless.Binding;

namespace Stainless.Fuzz;

/// <summary>
/// A mutation fuzzer for the compiler's front end and emitter.
///
/// It takes the programs already in the tree -- every test case, sample and
/// standard library file -- breaks them a little, and compiles the result in
/// process, the way <c>Compilation</c> does but with no disk and no clang. A
/// compiler is allowed to reject anything; it is not allowed to throw, overflow
/// its stack, spin, or point a diagnostic at a place that is not in the file.
///
/// It is not coverage-guided in the libFuzzer sense, because that would mean
/// instrumenting the compiler assembly and it has not been needed yet: a mutant
/// that makes the compiler say something it has not said before -- a new stage
/// reached with a new set of codes -- is kept and mutated further, which is
/// enough to walk past the first parse error into the binder. The first five
/// minutes of it found two dozen crashes the 317 cases had not.
/// </summary>
internal static class Program
{
    private static int Main(string[] args)
    {
        if (args.Length == 0)
            return Usage();

        string? targetName = Option(args, "--target");
        TargetPlatform? target = null;
        if (targetName is not null)
        {
            target = TargetPlatform.Parse(targetName);
            if (target is null)
            {
                Console.Error.WriteLine($"'{targetName}' is not a target; the targets are {TargetPlatform.Names}");
                return 2;
            }
        }

        Pipeline.Configure(target);

        string repository = Repository.Root();
        string defaultOutput = Path.Combine(Path.GetTempPath(), "stainless-fuzz");
        string? cases = Option(args, "--cases");
        string[] positional = Positional(args);

        return positional[0] switch
        {
            "fuzz" => Supervisor.Run(
                repository,
                Option(args, "--out") ?? defaultOutput,
                int.Parse(Option(args, "--workers") ?? Math.Max(1, Environment.ProcessorCount / 2).ToString()),
                double.Parse(Option(args, "--minutes") ?? "10", CultureInfo.InvariantCulture),
                cases),
            "worker" => Worker.Run(repository, positional[1], int.Parse(positional[2]), int.Parse(positional[3]), cases),
            "repro" when positional.Length > 1 => Repro(positional[1..]),
            "min" when positional.Length > 2 => Minimise(positional[1], positional[2]),
            "replay" => Replay.Run(positional.Length > 1 ? positional[1] : defaultOutput),
            _ => Usage(),
        };
    }

    /// <summary>Every option takes a value.</summary>
    private static readonly string[] s_options = ["--out", "--workers", "--minutes", "--target", "--cases"];

    private static string[] Positional(string[] args)
    {
        var positional = new List<string>();
        for (int i = 0; i < args.Length; i++)
        {
            if (s_options.Contains(args[i]))
                i++;
            else
                positional.Add(args[i]);
        }

        return [.. positional];
    }

    private static int Usage()
    {
        Console.Error.WriteLine(
            """
            usage: stainless-fuzz fuzz [--minutes N] [--workers N] [--out DIR] [--cases TEXT]
                   stainless-fuzz repro FILE.sl...      compile one program, say what happened
                   stainless-fuzz min FILE.sl OUT.sl    shrink a failing file, keeping its failure
                   stainless-fuzz replay [DIR]          re-run every finding, report which still fail

            Every command takes --target NAME, compiling for that target as
            stainless's own --target does; the default is this machine. --cases
            keeps only the programs whose path contains TEXT.

            Findings go to DIR/crashes, one directory per distinct failure; DIR defaults
            to %TEMP%/stainless-fuzz. A finding made for another target records it in
            target.txt, and replay compiles it for that target.
            """);
        return 2;
    }

    private static string? Option(string[] args, string name)
    {
        int at = Array.IndexOf(args, name);
        return at >= 0 && at + 1 < args.Length ? args[at + 1] : null;
    }

    private static int Repro(string[] paths)
    {
        var files = paths.Select(p => new SourceFile(p, File.ReadAllText(p))).ToList();
        var outcome = Pipeline.Run(files);

        Console.WriteLine($"reached {outcome.Stage}; reported {string.Join(' ', outcome.Codes)}");
        if (outcome.Failure is null)
            return 0;

        Console.WriteLine(outcome.Signature);
        Console.WriteLine(outcome.Failure);
        return 1;
    }

    private static int Minimise(string path, string output)
    {
        string text = File.ReadAllText(path);
        string? signature = Pipeline.Run([new SourceFile(path, text)]).Signature;
        if (signature is null)
        {
            Console.Error.WriteLine($"'{path}' compiles without failing; there is nothing to keep");
            return 1;
        }

        string smaller = Minimiser.Run(text, t => Pipeline.Run([new SourceFile(path, t)]).Signature == signature);
        File.WriteAllText(output, smaller);
        Console.WriteLine($"{text.Length} -> {smaller.Length} characters, still {signature}");
        return 0;
    }
}

/// <summary>One file of a program, as text.</summary>
internal sealed record SourceFile(string Path, string Text);

internal static class Repository
{
    /// <summary>The checkout this tool was built in, found by walking up to the solution.</summary>
    public static string Root()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
        {
            if (File.Exists(Path.Combine(dir.FullName, "Stainless.slnx")))
                return dir.FullName;
        }

        throw new InvalidOperationException("the fuzzer must be run from a build inside the repository");
    }
}
