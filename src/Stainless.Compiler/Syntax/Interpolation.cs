// Stainless - an experimental systems language.
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

namespace Stainless.Syntax;

/// <summary>
/// One piece of an interpolated string, as the lexer left it: either text that
/// goes through unchanged, or the tokens of a hole.
///
/// The hole is carried as tokens rather than as a substring because the lexer
/// read them in place, so each one already knows where in the file it came
/// from. A second lexer over a copy would have to have its positions patched
/// afterwards, and a diagnostic that pointed at the copy would be worse than
/// no diagnostic.
/// </summary>
public sealed record InterpolationSegment(string? Literal, IReadOnlyList<Token>? Tokens)
{
    public static InterpolationSegment Text(string literal) => new(literal, null);

    public static InterpolationSegment Hole(IReadOnlyList<Token> tokens) => new(null, tokens);

    public bool IsHole => Tokens is not null;
}
