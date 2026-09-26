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

namespace Stainless.Source;

/// <summary>
/// A fault in the compiler rather than in the program: a node a pass has no
/// case for, or a bound tree that breaks a rule a later pass relies on.
///
/// It is thrown rather than reported. A diagnostic tells an author what to
/// change, and nothing in the source is wrong.
/// </summary>
public sealed class InternalCompilerError(string problem, SourceSpan span = default)
    : Exception(Describe(problem, span))
{
    /// <summary>What went wrong, without where; the fuzzer groups findings by it.</summary>
    public string Problem { get; } = problem;

    /// <summary>Where, or a span with no file when nothing in the source is to blame.</summary>
    public SourceSpan Span { get; } = span;

    private static string Describe(string problem, SourceSpan span) =>
        "internal compiler error: " + problem +
        (span.File is null ? "" : $" at {span}") +
        "; this is a compiler bug, not a bug in your program";
}
