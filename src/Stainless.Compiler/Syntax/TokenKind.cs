namespace Stainless.Syntax;

public enum TokenKind
{
    // Literals and names
    Identifier, IntLiteral, FloatLiteral, StringLiteral, CharLiteral,

    // Declaration keywords
    ModuleKeyword, ImportKeyword, AsKeyword,
    PublicKeyword, PrivateKeyword,
    ClassKeyword, StructKeyword, InterfaceKeyword,
    ExternKeyword, ExportKeyword,

    // Statement keywords
    IfKeyword, ElseKeyword, WhileKeyword, ForKeyword,
    ReturnKeyword, BreakKeyword, ContinueKeyword,
    VarKeyword, ConstKeyword,

    // Expression keywords
    NewKeyword, DeleteKeyword, NullKeyword, TrueKeyword, FalseKeyword,
    SizeofKeyword, ThisKeyword, WeakKeyword,

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
    LessLess, GreaterGreater,

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
        TokenKind.ExternKeyword => "extern",
        TokenKind.ExportKeyword => "export",
        TokenKind.IfKeyword => "if",
        TokenKind.ElseKeyword => "else",
        TokenKind.WhileKeyword => "while",
        TokenKind.ForKeyword => "for",
        TokenKind.ReturnKeyword => "return",
        TokenKind.BreakKeyword => "break",
        TokenKind.ContinueKeyword => "continue",
        TokenKind.VarKeyword => "var",
        TokenKind.ConstKeyword => "const",
        TokenKind.NewKeyword => "new",
        TokenKind.DeleteKeyword => "delete",
        TokenKind.NullKeyword => "null",
        TokenKind.TrueKeyword => "true",
        TokenKind.FalseKeyword => "false",
        TokenKind.SizeofKeyword => "sizeof",
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
