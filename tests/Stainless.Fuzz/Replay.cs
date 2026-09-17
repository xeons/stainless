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
/// Runs every finding again against the compiler as it is now, each in a
/// process of its own with a time limit -- a finding that used to overflow the
/// stack or hang would otherwise take the replay down with it.
/// </summary>
internal static class Replay
{
    private static readonly TimeSpan s_limit = TimeSpan.FromSeconds(60);

    public static int Run(string output)
    {
        string crashes = Path.Combine(output, "crashes");
        if (!Directory.Exists(crashes))
        {
            Console.Error.WriteLine($"no findings under '{output}'");
            return 1;
        }

        int failing = 0;
        foreach (string directory in Directory.GetDirectories(crashes).Order())
        {
            // The whole program, with the minimised file in place of the one it came from.
            var files = Directory.GetFiles(directory, "*.sl")
                .Where(f => !Path.GetFileName(f).StartsWith("minimal-"))
                .Order()
                .ToList();
            foreach (string minimal in Directory.GetFiles(directory, "minimal-*.sl"))
            {
                int which = int.Parse(Path.GetFileNameWithoutExtension(minimal)["minimal-".Length..]);
                if (which < files.Count)
                    files[which] = minimal;
            }

            string verdict = Check(files);
            if (verdict != "fixed")
                failing++;

            string first = File.ReadLines(Path.Combine(directory, "signature.txt")).FirstOrDefault() ?? "";
            Console.WriteLine($"{verdict,-8} {Path.GetFileName(directory)}  {first}");
        }

        Console.WriteLine($"{failing} still failing");
        return failing == 0 ? 0 : 1;
    }

    private static string Check(List<string> files)
    {
        var info = new ProcessStartInfo(Environment.ProcessPath!, ["repro", .. files])
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };

        using var process = Process.Start(info)!;
        var drain = Task.WhenAll(process.StandardOutput.ReadToEndAsync(), process.StandardError.ReadToEndAsync());
        if (!process.WaitForExit(s_limit))
        {
            process.Kill(entireProcessTree: true);
            return "hangs";
        }

        drain.Wait();
        return process.ExitCode switch
        {
            0 => "fixed",
            1 => "throws",
            _ => "dies",
        };
    }
}
