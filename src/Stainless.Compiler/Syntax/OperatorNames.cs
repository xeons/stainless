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
/// Which operators may be overloaded, and the function name each becomes.
///
/// The name is the lowering, as <c>op_Addition</c> is in C#: an operator is
/// reached by writing it, never by calling the name, and the type keeps these
/// apart from its methods so that nothing can.
///
/// What is deliberately absent is as much of the design as what is here.
/// <c>&amp;&amp;</c> and <c>||</c> short-circuit, and an overload would have to
/// evaluate both sides to be called at all -- so overloading them would change
/// what the operator means rather than what it does. <c>=</c> is not an
/// operator but a store. The compound forms are not overloaded either: <c>+=</c>
/// is defined as <c>a = a + b</c> and picks up whatever <c>+</c> does, which is
/// one rule instead of two that could disagree.
/// </summary>
public static class OperatorNames
{
    private static readonly Dictionary<TokenKind, string> Names = new()
    {
        [TokenKind.Plus] = "op_Add",
        [TokenKind.Minus] = "op_Subtract",
        [TokenKind.Star] = "op_Multiply",
        [TokenKind.Slash] = "op_Divide",
        [TokenKind.Percent] = "op_Remainder",

        [TokenKind.Amp] = "op_BitAnd",
        [TokenKind.Pipe] = "op_BitOr",
        [TokenKind.Caret] = "op_BitXor",
        [TokenKind.LessLess] = "op_ShiftLeft",
        [TokenKind.GreaterGreater] = "op_ShiftRight",

        [TokenKind.EqualsEquals] = "op_Equal",
        [TokenKind.BangEquals] = "op_NotEqual",
        [TokenKind.Less] = "op_Less",
        [TokenKind.LessEquals] = "op_LessEqual",
        [TokenKind.Greater] = "op_Greater",
        [TokenKind.GreaterEquals] = "op_GreaterEqual",

        [TokenKind.Bang] = "op_Not",
        [TokenKind.Tilde] = "op_Complement",
    };

    public static string? For(TokenKind kind) => Names.GetValueOrDefault(kind);

    /// <summary>
    /// The ones that must be declared together, because a program that can ask
    /// one question and not its opposite is a trap. C# arrived at the same
    /// rule for the same reason.
    /// </summary>
    public static readonly IReadOnlyDictionary<TokenKind, TokenKind> Pairs =
        new Dictionary<TokenKind, TokenKind>
        {
            [TokenKind.EqualsEquals] = TokenKind.BangEquals,
            [TokenKind.BangEquals] = TokenKind.EqualsEquals,
            [TokenKind.Less] = TokenKind.Greater,
            [TokenKind.Greater] = TokenKind.Less,
            [TokenKind.LessEquals] = TokenKind.GreaterEquals,
            [TokenKind.GreaterEquals] = TokenKind.LessEquals,
        };

    /// <summary>The ones taking a single operand.</summary>
    public static bool IsUnary(TokenKind kind) =>
        kind is TokenKind.Bang or TokenKind.Tilde;

    /// <summary>The ones that may take one operand or two.</summary>
    public static bool IsEither(TokenKind kind) =>
        kind is TokenKind.Minus or TokenKind.Plus;

    /// <summary>The ones whose result has to be <c>bool</c>.</summary>
    public static bool IsComparison(TokenKind kind) =>
        kind is TokenKind.EqualsEquals or TokenKind.BangEquals or TokenKind.Less
            or TokenKind.LessEquals or TokenKind.Greater or TokenKind.GreaterEquals;

    /// <summary>For the diagnostic that says which ones there are.</summary>
    public static string List =>
        string.Join(" ", Names.Keys.Select(k => k.FixedText()).Order(StringComparer.Ordinal));
}
