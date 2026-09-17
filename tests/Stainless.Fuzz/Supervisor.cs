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

namespace Stainless.Fuzz;

/// <summary>
/// Starts the workers, restarts the ones that die, and keeps what killed them.
/// </summary>
internal static class Supervisor
{
    /// <summary>
    /// How long a worker may go without finishing a compilation. A real one
    /// takes well under a second; a mutant six hundred copies long takes a few.
    /// Anything past this is a loop.
    /// </summary>
    private static readonly TimeSpan s_quiet = TimeSpan.FromSeconds(30);

    private sealed class Slot
    {
        public required Process Process;
        public DateTime Heard;
    }

    public static int Run(string repository, string output, int workers, double minutes)
    {
        Directory.CreateDirectory(Path.Combine(output, "crashes"));
        Console.WriteLine($"fuzzing with {workers} workers for {minutes} minutes; findings in {output}");

        var slots = new Slot[workers];
        var stages = new SortedDictionary<string, long>();
        var gate = new object();
        int deaths = 0;

        void Start(int id)
        {
            var info = new ProcessStartInfo(Environment.ProcessPath!,
                ["worker", output, id.ToString(), Random.Shared.Next().ToString()])
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };

            var process = Process.Start(info)!;
            var slot = new Slot { Process = process, Heard = DateTime.UtcNow.AddSeconds(60) };
            slots[id] = slot;

            process.OutputDataReceived += (_, e) =>
            {
                if (e.Data is null)
                    return;
                lock (gate)
                {
                    slot.Heard = DateTime.UtcNow;
                    string stage = e.Data[(e.Data.IndexOf(' ') + 1)..];
                    stages[stage] = stages.GetValueOrDefault(stage) + 1;
                }
            };
            process.ErrorDataReceived += (_, e) =>
            {
                if (e.Data is not null)
                    File.AppendAllText(Path.Combine(output, "work", $"{id}.stderr"), e.Data + "\n");
            };
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
        }

        Directory.CreateDirectory(Path.Combine(output, "work"));
        for (int i = 0; i < workers; i++)
            Start(i);

        var stop = DateTime.UtcNow.AddMinutes(minutes);
        var report = Stopwatch.StartNew();
        while (DateTime.UtcNow < stop)
        {
            Thread.Sleep(1000);

            for (int id = 0; id < workers; id++)
            {
                var slot = slots[id];
                bool died = slot.Process.HasExited;
                bool hung;
                lock (gate)
                    hung = !died && DateTime.UtcNow - slot.Heard > s_quiet;
                if (!died && !hung)
                    continue;

                if (hung)
                    Kill(slot.Process);

                deaths++;
                Keep(output, id, died ? "died" : "hung");
                Start(id);
            }

            if (report.Elapsed.TotalSeconds >= 30)
            {
                report.Restart();
                lock (gate)
                    Console.WriteLine(
                        $"{DateTime.Now:HH:mm:ss}  {stages.Values.Sum()} compilations " +
                        $"({string.Join(", ", stages.Select(s => $"{s.Value} {s.Key}"))}), " +
                        $"{Directory.GetDirectories(Path.Combine(output, "crashes")).Length} findings, " +
                        $"{deaths} workers lost");
            }
        }

        foreach (var slot in slots)
            Kill(slot.Process);

        return 0;
    }

    /// <summary>
    /// Keeps the input a worker was compiling when it died or hung, named by the
    /// compiler frames of the stack overflow where there is one, so a thousand
    /// deaths in the same recursion are one finding.
    /// </summary>
    private static void Keep(string output, int id, string how)
    {
        string input = Path.Combine(output, "work", $"{id}.sl");
        string errors = Path.Combine(output, "work", $"{id}.stderr");
        string stderr = File.Exists(errors) ? File.ReadAllText(errors) : "";

        string signature = how == "hung"
            ? "hung: " + (File.Exists(input) ? Worker.Hash(File.ReadAllText(input)) : "unknown")
            : $"died: {string.Join(" < ", Pipeline.Frames(stderr.Replace("   at ", "at ")))}";

        string directory = Path.Combine(output, "crashes", $"{how}-{Worker.Hash(signature)}");
        if (!Directory.Exists(directory))
        {
            Directory.CreateDirectory(directory);
            File.WriteAllText(Path.Combine(directory, "signature.txt"), signature + "\n\n" + stderr);
            if (File.Exists(input))
                File.Copy(input, Path.Combine(directory, "0-input.sl"), overwrite: true);
        }

        if (File.Exists(errors))
            File.Delete(errors);
    }

    private static void Kill(Process process)
    {
        try
        {
            process.Kill(entireProcessTree: true);
            process.WaitForExit();
        }
        catch (InvalidOperationException)
        {
            // It had already exited, which is what was wanted.
        }
    }
}
