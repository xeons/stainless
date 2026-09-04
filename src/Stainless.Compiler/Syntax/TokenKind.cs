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

public enum TokenKind
{
    // Literals and names
    Identifier, IntLiteral, FloatLiteral, StringLiteral, CharLiteral,

    // Declaration keywords
    ModuleKeyword, ImportKeyword, AsKeyword,
    PublicKeyword, PrivateKeyword,
    ClassKeyword, StructKeyword, InterfaceKeyword, AttributeKeyword, EnumKeyword,
    VariantKeyword, DelegateKeyword,
    ExternKeyword, ExportKeyword,

    // Statement keywords
    IfKeyword, ElseKeyword, WhileKeyword, ForKeyword, ForeachKeyword, InKeyword,
    SwitchKeyword, CaseKeyword, DefaultKeyword,
    ParallelKeyword, SpawnKeyword,
    ReturnKeyword, BreakKeyword, ContinueKeyword,
    VarKeyword, ConstKeyword, WhereKeyword, StaticKeyword, ReadonlyKeyword,
    RefKeyword,

    // Expression keywords
    NewKeyword, DeleteKeyword, NullKeyword, TrueKeyword, FalseKeyword,
    SizeofKeyword, TypeofKeyword, ThisKeyword, WeakKeyword,

    // Primitive type keywords
    VoidKeyword, BoolKeyword, CharKeyword,
    SByteKeyword, ShortKeyword, IntKeyword, LongKeyword, NIntKeyword,
    ByteKeyword, UShortKeyword, UIntKeyword, ULongKeyword, NUIntKeyword,
    FloatKeyword, DoubleKeyword,

    // Punctuation
    OpenParen, CloseParen, OpenBrace, CloseBrace, OpenBracket, CloseBracket,
    Comma, Semicolon, Colon, Dot, Question, Tilde,

    // Operators
    Equals, EqualsEquals, Bang, BangEquals,
    Less, LessEquals, Greater, GreaterEquals,
    Plus, Minus, Star, Slash, Percent,
    Amp, AmpAmp, Pipe, PipePipe, Caret,
    LessLess, GreaterGreater, EqualsGreater,

    // Compound assignment
    PlusEquals, MinusEquals, StarEquals, SlashEquals, PercentEquals,
    AmpEquals, PipeEquals, CaretEquals, LessLessEquals, GreaterGreaterEquals,

    EndOfFile, Bad,
}

public static class TokenKindExtensions
{
    /// <summary>The exact source text for fixed-text tokens; null for literals and names.</summary>
    public static string? FixedText(this TokenKind kind) => kind switch
    {
        TokenKind.ModuleKeyword => "module",
        TokenKind.ImportKeyword => "import",
        TokenKind.AsKeyword => "as",
        TokenKind.PublicKeyword => "public",
        TokenKind.PrivateKeyword => "private",
        TokenKind.ClassKeyword => "class",
        TokenKind.StructKeyword => "struct",
        TokenKind.InterfaceKeyword => "interface",
        TokenKind.AttributeKeyword => "attribute",
        TokenKind.EnumKeyword => "enum",
        TokenKind.VariantKeyword => "variant",
        TokenKind.DelegateKeyword => "delegate",
        TokenKind.ExternKeyword => "extern",
        TokenKind.ExportKeyword => "export",
        TokenKind.IfKeyword => "if",
        TokenKind.ElseKeyword => "else",
        TokenKind.WhileKeyword => "while",
        TokenKind.ForKeyword => "for",
        TokenKind.ForeachKeyword => "foreach",
        TokenKind.InKeyword => "in",
        TokenKind.SwitchKeyword => "switch",
        TokenKind.CaseKeyword => "case",
        TokenKind.DefaultKeyword => "default",
        TokenKind.ParallelKeyword => "parallel",
        TokenKind.SpawnKeyword => "spawn",
        TokenKind.ReturnKeyword => "return",
        TokenKind.BreakKeyword => "break",
        TokenKind.ContinueKeyword => "continue",
        TokenKind.VarKeyword => "var",
        TokenKind.ConstKeyword => "const",
        TokenKind.RefKeyword => "ref",
        TokenKind.StaticKeyword => "static",
        TokenKind.ReadonlyKeyword => "readonly",
        TokenKind.WhereKeyword => "where",
        TokenKind.NewKeyword => "new",
        TokenKind.DeleteKeyword => "delete",
        TokenKind.NullKeyword => "null",
        TokenKind.TrueKeyword => "true",
        TokenKind.FalseKeyword => "false",
        TokenKind.SizeofKeyword => "sizeof",
        TokenKind.TypeofKeyword => "typeof",
        TokenKind.ThisKeyword => "this",
        TokenKind.WeakKeyword => "weak",
        TokenKind.VoidKeyword => "void",
        TokenKind.BoolKeyword => "bool",
        TokenKind.CharKeyword => "char",
        TokenKind.SByteKeyword => "sbyte",
        TokenKind.ShortKeyword => "short",
        TokenKind.IntKeyword => "int",
        TokenKind.LongKeyword => "long",
        TokenKind.NIntKeyword => "nint",
        TokenKind.ByteKeyword => "byte",
        TokenKind.UShortKeyword => "ushort",
        TokenKind.UIntKeyword => "uint",
        TokenKind.ULongKeyword => "ulong",
        TokenKind.NUIntKeyword => "nuint",
        TokenKind.FloatKeyword => "float",
        TokenKind.DoubleKeyword => "double",
        TokenKind.OpenParen => "(",
        TokenKind.CloseParen => ")",
        TokenKind.OpenBrace => "{",
        TokenKind.CloseBrace => "}",
        TokenKind.OpenBracket => "[",
        TokenKind.CloseBracket => "]",
        TokenKind.Comma => ",",
        TokenKind.Semicolon => ";",
        TokenKind.Colon => ":",
        TokenKind.Dot => ".",
        TokenKind.Question => "?",
        TokenKind.Tilde => "~",
        TokenKind.Equals => "=",
        TokenKind.EqualsEquals => "==",
        TokenKind.Bang => "!",
        TokenKind.BangEquals => "!=",
        TokenKind.Less => "<",
        TokenKind.LessEquals => "<=",
        TokenKind.Greater => ">",
        TokenKind.GreaterEquals => ">=",
        TokenKind.Plus => "+",
        TokenKind.Minus => "-",
        TokenKind.Star => "*",
        TokenKind.Slash => "/",
        TokenKind.Percent => "%",
        TokenKind.Amp => "&",
        TokenKind.AmpAmp => "&&",
        TokenKind.Pipe => "|",
        TokenKind.PipePipe => "||",
        TokenKind.Caret => "^",
        TokenKind.LessLess => "<<",
        TokenKind.GreaterGreater => ">>",
        TokenKind.EqualsGreater => "=>",
        TokenKind.PlusEquals => "+=",
        TokenKind.MinusEquals => "-=",
        TokenKind.StarEquals => "*=",
        TokenKind.SlashEquals => "/=",
        TokenKind.PercentEquals => "%=",
        TokenKind.AmpEquals => "&=",
        TokenKind.PipeEquals => "|=",
        TokenKind.CaretEquals => "^=",
        TokenKind.LessLessEquals => "<<=",
        TokenKind.GreaterGreaterEquals => ">>=",
        TokenKind.EndOfFile => "end of file",
        _ => null,
    };

    public static string Describe(this TokenKind kind) => kind switch
    {
        TokenKind.Identifier => "an identifier",
        TokenKind.IntLiteral => "an integer literal",
        TokenKind.FloatLiteral => "a floating-point literal",
        TokenKind.StringLiteral => "a string literal",
        TokenKind.CharLiteral => "a character literal",
        TokenKind.EndOfFile => "end of file",
        _ => kind.FixedText() is { } t ? "'" + t + "'" : kind.ToString(),
    };

    public static readonly IReadOnlyDictionary<string, TokenKind> Keywords =
        Enum.GetValues<TokenKind>()
            .Select(k => (Kind: k, Text: k.FixedText()))
            .Where(p => p.Text is not null && p.Text.All(char.IsLetter))
            .ToDictionary(p => p.Text!, p => p.Kind, StringComparer.Ordinal);
}
