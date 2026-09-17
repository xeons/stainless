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

using System.Text.RegularExpressions;
using Stainless.Binding;
using Stainless.Source;

namespace Stainless.Driver;

/// <summary>
/// Turns the assembler's complaint about an <c>asm</c> block into a diagnostic
/// on the line of source it was about.
///
/// <para>
/// The compiler never reads the text of a block, so a misspelt instruction is
/// found by LLVM, while the IR is being lowered, as part of what the driver
/// calls linking. Left alone it came back as the toolchain rejecting the
/// generated IR, "a compiler bug, not a bug in your program" — which is exactly
/// backwards, and names a line of a file the reader never wrote.
/// </para>
///
/// <para>
/// LLVM reports <c>&lt;inline asm&gt;:line:column</c>, counted within the one
/// block, and does not say which block. It does echo the line, so the block is
/// found by looking for one whose text has that line at that number. Two
/// blocks with the same line at the same place both match, and the first is
/// taken: they are the same mistake, and either is the right place to fix it.
/// </para>
/// </summary>
public static partial class AssemblerDiagnosis
{
    /// <summary>Whether this toolchain output is the assembler refusing a block.</summary>
    public static bool Rejected(string output) =>
        output.Contains("<inline asm>", StringComparison.Ordinal) ||
        output.Contains("cannot compile inline asm", StringComparison.Ordinal);

    [GeneratedRegex(@"^<inline asm>:(\d+):(\d+): error: (.*)$")]
    private static partial Regex ErrorLine { get; }

    /// <summary>
    /// Reports each error in the output against the block and line it came
    /// from, as SL0723. Anything that cannot be placed is reported against the
    /// first block, with LLVM's words, rather than dropped.
    /// </summary>
    public static void Report(
        string output, IReadOnlyList<BoundAsm> blocks, TargetPlatform target, DiagnosticBag diagnostics)
    {
        if (blocks.Count == 0) return;

        // On x86 the assembler is handed a line of its own ahead of the text —
        // the switch to Intel syntax — so what it calls line 2 is the block's
        // first. ARM has one syntax and nothing is put in front.
        int offset = target.Architecture == TargetArch.Arm64 ? 0 : 1;

        string[] lines = output.Replace("\r", "").Split('\n');
        var reported = new HashSet<(int Start, string Message)>();
        bool placed = false;

        for (int i = 0; i < lines.Length; i++)
        {
            var match = ErrorLine.Match(lines[i]);
            if (!match.Success) continue;

            int line = int.Parse(match.Groups[1].Value) - 1 - offset;
            string message = match.Groups[3].Value;
            string echoed = i + 1 < lines.Length ? lines[i + 1] : "";

            if (Locate(blocks, line, echoed) is not { } span) continue;

            placed = true;
            if (!reported.Add((span.Start, message))) continue;

            diagnostics.Error("SL0723", span,
                $"the assembler rejected this line of an 'asm' block: {message}");
        }

        if (placed) return;

        diagnostics.Error("SL0723", blocks[0].TextSpan,
            "the assembler rejected an 'asm' block, and did not say which line:\n" +
            output.Trim());
    }

    /// <summary>
    /// The span of the line numbered <paramref name="line"/> (from zero) in the
    /// first block whose line there reads <paramref name="echoed"/>.
    /// </summary>
    private static SourceSpan? Locate(IReadOnlyList<BoundAsm> blocks, int line, string echoed)
    {
        if (line < 0) return null;

        foreach (var block in blocks)
        {
            string[] text = block.Text.Split('\n');
            if (line >= text.Length) continue;
            if (text[line].TrimEnd('\r').TrimEnd() != echoed.TrimEnd()) continue;

            // The text starts one character into the span, after the brace.
            int start = block.TextSpan.Start + 1;
            for (int k = 0; k < line; k++)
                start += text[k].Length + 1;

            string written = text[line].TrimEnd('\r');
            int leading = written.Length - written.TrimStart().Length;
            int length = written.Trim().Length;

            return new SourceSpan(block.TextSpan.File, start + leading, start + leading + Math.Max(length, 1));
        }

        return null;
    }
}
