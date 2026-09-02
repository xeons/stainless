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

using Stainless.Source;

namespace Stainless.Syntax;

/// <summary>
/// A lexical token. <paramref name="Value"/> carries the decoded literal:
/// <c>ulong</c> for integers, <c>double</c> for floats, <c>string</c> for
/// strings, <c>char</c> for chars, <c>bool</c> for true/false.
/// </summary>
public sealed record Token(TokenKind Kind, SourceSpan Span, string Text, object? Value = null)
{
    public override string ToString() => $"{Kind} '{Text}'";
}
