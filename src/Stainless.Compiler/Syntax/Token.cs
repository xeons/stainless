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
