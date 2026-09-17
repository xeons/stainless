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

using System.Security.Cryptography;
using System.Text;

namespace Stainless.Fuzz;

/// <summary>
/// One process, mutating and compiling until it is killed.
///
/// A process and not a thread, because the two worst failures cannot be caught
/// from inside: .NET ends the process on a stack overflow whatever handler is
/// installed, and a loop that never returns cannot be interrupted. So before
/// each compilation the worker writes its input where the supervisor can find
/// it, and prints a line after -- a worker that dies or goes quiet has left
/// behind the input that did it.
/// </summary>
internal static class Worker
{
    /// <summary>A kept mutant larger than this is more likely to be slow than interesting.</summary>
    private const int MaxKeptLength = 200_000;

    private const int MaxCorpus = 20_000;

    public static int Run(string repository, string output, int id, int seed)
    {
        var random = new Random(seed);
        var corpus = Corpus.Load(repository);
        var mutator = new Mutator(random, corpus.SelectMany(p => p.Select(f => f.Text)).ToList());
        var behaviours = new HashSet<string>();
        var signatures = new HashSet<string>();

        string current = Path.Combine(output, "work", $"{id}.sl");
        Directory.CreateDirectory(Path.GetDirectoryName(current)!);

        for (long run = 0; ; run++)
        {
            var program = corpus[random.Next(corpus.Count)];
            int which = random.Next(program.Count);
            var files = program.ToList();
            files[which] = program[which] with { Text = mutator.Mutate(program[which].Text) };

            File.WriteAllText(current, $"// mutated from {program[which].Path}\n" + files[which].Text);
            var outcome = Pipeline.Run(files);

            // Novelty standing in for coverage: a mutant that gets the compiler to
            // say something it has not said yet is kept, to be mutated further.
            string behaviour = outcome.Stage + ":" + string.Join(',', outcome.Codes);
            if (behaviours.Add(behaviour) && corpus.Count < MaxCorpus && files[which].Text.Length < MaxKeptLength)
                corpus.Add(files);

            if (outcome.Signature is not null && signatures.Add(outcome.Signature))
                Record(output, outcome, files, which);

            Console.WriteLine($"{run} {outcome.Stage}");
        }
    }

    public static string Hash(string signature) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(signature)))[..10].ToLowerInvariant();

    private static void Record(string output, Outcome outcome, List<SourceFile> files, int which)
    {
        string directory = Path.Combine(output, "crashes", Hash(outcome.Signature!));
        if (Directory.Exists(directory))
            return;

        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, "signature.txt"), outcome.Signature + "\n\n" + outcome.Failure);
        for (int i = 0; i < files.Count; i++)
            File.WriteAllText(Path.Combine(directory, $"{i}-{Path.GetFileName(files[i].Path)}"), files[i].Text);

        // Replayed before it is believed: a failure that depends on something an
        // earlier compilation in this process left behind is a different bug.
        if (Pipeline.Run(files).Signature != outcome.Signature)
        {
            File.WriteAllText(Path.Combine(directory, "flaky.txt"), "did not fail the same way a second time\n");
            return;
        }

        string minimal = Minimiser.Run(files[which].Text, text =>
        {
            var candidate = files.ToList();
            candidate[which] = files[which] with { Text = text };
            return Pipeline.Run(candidate).Signature == outcome.Signature;
        });
        File.WriteAllText(Path.Combine(directory, $"minimal-{which}.sl"), minimal);
    }
}

internal static class Corpus
{
    /// <summary>
    /// Every program in the tree, as its files. A test case directory is one
    /// program, because half of what the binder does is between files.
    /// </summary>
    public static List<List<SourceFile>> Load(string repository)
    {
        var programs = new List<List<SourceFile>>();

        foreach (string directory in Directory.GetDirectories(Path.Combine(repository, "tests", "cases")))
        {
            var files = Directory.GetFiles(directory, "*.sl").Select(Read).ToList();
            if (files.Count > 0)
                programs.Add(files);
        }

        foreach (string file in Directory.GetFiles(Path.Combine(repository, "samples"), "*.sl", SearchOption.AllDirectories))
            programs.Add([Read(file)]);

        foreach (string file in Directory.GetFiles(Path.Combine(repository, "stdlib"), "*.sl"))
            programs.Add([Read(file)]);

        return programs;
    }

    private static SourceFile Read(string path) => new(path.Replace('\\', '/'), File.ReadAllText(path));
}
