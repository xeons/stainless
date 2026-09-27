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

using System.Text;
using System.Text.RegularExpressions;

namespace Stainless.Driver;

/// <summary>
/// What LLVM's verifier found wrong with a module the compiler emitted, and the
/// function it was in when that can be told.
///
/// The verifier names a function only for a fault in its signature or its
/// description. For a fault in a body it prints the instructions involved, so
/// the function is the one whose body holds them.
/// </summary>
public sealed partial record IrFault(string Message, string? Function)
{
    /// <summary>More than this many lines of the verifier's output are cut.</summary>
    private const int MaxLines = 24;

    /// <summary>
    /// Whether the tool dropped the module's debug information for being
    /// invalid, which it does with a warning and a zero exit code.
    /// </summary>
    public static bool StrippedDebugInfo(string output) =>
        output.Contains("ignoring invalid debug info", StringComparison.Ordinal);

    /// <summary>
    /// Whether clang refused a module as it read it: it would not parse, or it
    /// parsed and failed the verifier.
    /// </summary>
    public static bool RejectedByClang(string output) =>
        output.Contains(ClangPrefix, StringComparison.Ordinal) ||
        output.Replace("\r", "").Split('\n').Any(l => ParseError.Match(l).Success);

    /// <summary>The fault a verifier's output describes, placed in <paramref name="ir"/>.</summary>
    public static IrFault FromVerifier(string output, string ir)
    {
        var lines = output.Replace("\r", "").Split('\n')
            .Where(l => l.Trim().Length > 0 && !IsToolChatter(l))
            .Select(l => l.StartsWith(ClangPrefix, StringComparison.Ordinal) ? l[ClangPrefix.Length..] : l)
            .ToList();

        // A module that does not parse never reaches the verifier. The parser
        // gives a line, and quotes it under a caret; the line is the better
        // half, since the IR is to hand.
        foreach (string line in lines)
        {
            var parse = ParseError.Match(line);
            if (!parse.Success)
                continue;

            int number = int.Parse(parse.Groups["line"].Value);
            string[] module = ir.Split('\n');
            string quoted = number >= 1 && number <= module.Length ? module[number - 1].Trim() : "";

            return new IrFault(
                $"{parse.Groups["message"].Value} (line {number} of the module)\n  {quoted}",
                FunctionAt(module, number - 1));
        }

        if (lines.Count == 0)
            lines.Add(output.Trim().Length > 0 ? output.Trim() : "the verifier failed and said nothing");

        var message = new StringBuilder(string.Join("\n", lines.Take(MaxLines)));
        if (lines.Count > MaxLines)
            message.Append($"\n({lines.Count - MaxLines} more lines)");

        return new IrFault(message.ToString(), Locate(lines, ir));
    }

    /// <summary>What to tell someone who did not write the IR and cannot fix it.</summary>
    public string Explain(string? irPath) =>
        "internal compiler error: LLVM's verifier rejected the emitted IR" +
        (Function is null ? "" : $" in '{Function}'") + ":\n" +
        Indented(Message) + "\n" +
        (irPath is null ? "" : $"The IR is at {irPath}; ") +
        "this is a compiler bug, not a bug in your program.";

    /// <summary>What clang puts in front of the verifier's first line.</summary>
    private const string ClangPrefix = "error: invalid LLVM IR input: ";

    private static bool IsToolChatter(string line) =>
        ErrorsGenerated.IsMatch(line) ||
        line.Contains("input module is broken", StringComparison.Ordinal) ||
        line.Contains("Broken module found", StringComparison.Ordinal) ||
        line.Contains("-Woverride-module", StringComparison.Ordinal) ||
        StrippedDebugInfo(line);

    [GeneratedRegex(@"^\d+ (?:error|warning)s? generated\.$")]
    private static partial Regex ErrorsGenerated { get; }

    /// <summary>The IR parser's complaint, about standard input or a .ll file.</summary>
    [GeneratedRegex(@"^(?:.*\.ll|<stdin>):(?<line>\d+):\d+: error: (?<message>.*)$")]
    private static partial Regex ParseError { get; }

    /// <summary>The function whose body holds line <paramref name="index"/>, from zero.</summary>
    private static string? FunctionAt(string[] module, int index)
    {
        for (int at = Math.Min(index, module.Length - 1); at >= 0; at--)
        {
            string line = module[at].TrimEnd('\r');
            if (line == "}" && at != index)
                return null;
            if (!line.StartsWith("define ", StringComparison.Ordinal))
                continue;

            var name = DefinedName.Match(line);
            return name.Success ? name.Groups[1].Value.Trim('"') : null;
        }

        return null;
    }

    /// <summary>A function printed as a value, which is how the verifier names one.</summary>
    [GeneratedRegex(@"^ptr @(""(?:[^""\\]|\\.)*""|[-\w$.]+)$")]
    private static partial Regex FunctionValue { get; }

    [GeneratedRegex(@"@(""(?:[^""\\]|\\.)*""|[-\w$.]+)\(")]
    private static partial Regex DefinedName { get; }

    /// <summary>
    /// The function the fault is in: one the verifier printed as a value, or
    /// else the first whose body holds every instruction it printed.
    /// </summary>
    private static string? Locate(IReadOnlyList<string> lines, string ir)
    {
        foreach (string line in lines)
        {
            var named = FunctionValue.Match(line.Trim());
            if (named.Success)
                return named.Groups[1].Value.Trim('"');
        }

        var printed = lines
            .Where(l => l.StartsWith("  ", StringComparison.Ordinal))
            .Select(Normalized)
            .Where(l => l.Length > 0)
            .ToHashSet(StringComparer.Ordinal);
        if (printed.Count == 0)
            return null;

        string? current = null;
        string? first = null;
        var seen = new HashSet<string>(StringComparer.Ordinal);

        foreach (string raw in ir.Split('\n'))
        {
            string line = raw.TrimEnd('\r');
            if (line.StartsWith("define ", StringComparison.Ordinal))
            {
                var name = DefinedName.Match(line);
                current = name.Success ? name.Groups[1].Value.Trim('"') : null;
                seen.Clear();
                continue;
            }

            if (line == "}")
            {
                current = null;
                continue;
            }

            if (current is null || !printed.Contains(Normalized(line)))
                continue;

            first ??= current;
            seen.Add(Normalized(line));
            if (seen.Count == printed.Count)
                return current;
        }

        return first;
    }

    /// <summary>
    /// An instruction without its metadata attachments, which the verifier
    /// prints renumbered.
    /// </summary>
    private static string Normalized(string line)
    {
        string trimmed = line.Trim();
        int attachment = trimmed.IndexOf(", !", StringComparison.Ordinal);
        return attachment < 0 ? trimmed : trimmed[..attachment];
    }

    private static string Indented(string text) =>
        string.Join("\n", text.Split('\n').Select(l => "  " + l));
}
