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
/// Shrinks a failing input while it still fails the same way.
///
/// Delta debugging, twice: over lines first, because most of a mutated test
/// case is a whole function nothing needed, and then over tokens, because the
/// last few lines usually hold a dozen tokens of which three matter. "The same
/// way" is the signature, not merely "throws": left to shrink toward any
/// exception, a crash in the binder happily becomes an unrelated one in the
/// parser.
/// </summary>
internal static class Minimiser
{
    private static readonly TimeSpan s_budget = TimeSpan.FromMinutes(2);

    public static string Run(string text, Func<string, bool> stillFails)
    {
        var clock = Stopwatch.StartNew();
        text = Pass(Lines(text), stillFails, clock);
        return Pass(Tokens(text), stillFails, clock);
    }

    private static List<string> Lines(string text) =>
        text.Split('\n').Select((l, i) => i == 0 ? l : "\n" + l).ToList();

    /// <summary>Each token with the whitespace in front of it, so joining them gives the text back.</summary>
    private static List<string> Tokens(string text)
    {
        var pieces = new List<string>();
        int at = 0;
        foreach (var token in Mutator.Lex(text))
        {
            pieces.Add(text[at..token.Span.End]);
            at = token.Span.End;
        }

        pieces.Add(text[at..]);
        return pieces;
    }

    private static string Pass(List<string> pieces, Func<string, bool> stillFails, Stopwatch clock)
    {
        for (int chunk = Math.Max(1, pieces.Count / 2); chunk >= 1; chunk /= 2)
        {
            for (int i = 0; i < pieces.Count && clock.Elapsed < s_budget;)
            {
                var candidate = pieces.Take(i).Concat(pieces.Skip(i + chunk)).ToList();
                if (candidate.Count > 0 && stillFails(string.Concat(candidate)))
                    pieces = candidate;
                else
                    i += chunk;
            }
        }

        return string.Concat(pieces);
    }
}
