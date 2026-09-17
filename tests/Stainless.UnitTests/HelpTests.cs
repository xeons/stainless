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
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// `stainless --help` against the parser that reads what it describes.
///
/// The two live in one file and were still allowed to drift: `-r`, `-p` and
/// `--` were all accepted and none of them was in the help, which docs/cli.md
/// calls the authority. Read as text rather than run, because the command line
/// is not a library this project references -- the same way SampleTests reads
/// the samples directory.
/// </summary>
public class HelpTests
{
    private static readonly string Source =
        File.ReadAllText(Path.Combine(Repository.Root, "src", "Stainless.Cli", "Program.cs"));

    [Fact]
    public void EveryOptionTheParserAcceptsIsInTheHelp()
    {
        string help = Between(Source, "private static void PrintUsage()", "\"\"\");");
        string parser = Between(Source, "private static bool TryParse(", "parsed = arguments;");

        // The option cases, at the indentation of the switch over arguments: a
        // nested switch over an option's value ('shared', 'static') is deeper.
        var options = Regex.Matches(parser, @"^ {16}case (""[^""]+""(?: or ""[^""]+"")*):", RegexOptions.Multiline)
            .SelectMany(m => Regex.Matches(m.Groups[1].Value, @"""([^""]+)""").Select(o => o.Groups[1].Value))
            .ToList();

        Assert.NotEmpty(options);

        // Where an option is listed rather than mentioned: at the start of a
        // line, or after the short form it shares one with.
        var missing = options
            .Where(option => !Regex.IsMatch(
                help, @"^\s+(?:-\S+,\s+)?" + Regex.Escape(option) + @"(?=[\s,]|$)", RegexOptions.Multiline))
            .ToList();

        Assert.True(missing.Count == 0, "not in 'stainless --help': " + string.Join(", ", missing));
    }

    private static string Between(string text, string start, string end)
    {
        int from = text.IndexOf(start, StringComparison.Ordinal);
        Assert.True(from >= 0, $"'{start}' is not in Program.cs");

        int to = text.IndexOf(end, from, StringComparison.Ordinal);
        Assert.True(to >= 0, $"'{end}' does not follow '{start}' in Program.cs");

        return text[from..to];
    }
}
