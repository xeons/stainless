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

namespace Stainless.Bindgen;

/// <summary>
/// A C type as clang prints one, with its qualifiers gone: <c>const</c>,
/// <c>volatile</c> and nullability say nothing a binding can keep.
/// </summary>
public abstract record CType;

/// <summary><c>unsigned long</c>, <c>void</c>, <c>_Bool</c>: a type C builds in.</summary>
public sealed record CBuiltin(string Name) : CType;

/// <summary>A typedef's name, which the program resolves or keeps.</summary>
public sealed record CTypedef(string Name) : CType;

/// <summary><c>struct CGRect</c>, <c>union X</c>, <c>enum Y</c>.</summary>
public sealed record CTag(CTagKind Kind, string Name) : CType;

/// <summary>
/// A struct, union or enum with no name, which clang prints as
/// <c>struct (unnamed struct at /path/CFBase.h:12:3)</c>; the place is what
/// identifies it.
/// </summary>
public sealed record CAnonymous(CTagKind Kind, string Where) : CType;

public sealed record CPointer(CType Pointee) : CType;

/// <summary><c>void (^)(int)</c>: a block, whose type is always a function's.</summary>
public sealed record CBlock(CFunction Function) : CType;

/// <summary><c>char [16]</c>; a length of null is <c>[]</c>.</summary>
public sealed record CArray(CType Element, long? Length) : CType;

public sealed record CFunction(CType Result, IReadOnlyList<CType> Parameters, bool Variadic) : CType
{
    /// <summary>What each parameter's outermost type says about nil; empty when nothing was read.</summary>
    public IReadOnlyList<Nullability> ParameterNullability { get; init; } = [];

    public Nullability ResultNullability { get; init; }

    public bool Equals(CFunction? other) =>
        other is not null && Result.Equals(other.Result) && Variadic == other.Variadic &&
        Parameters.SequenceEqual(other.Parameters);

    public override int GetHashCode() => HashCode.Combine(Result, Parameters.Count, Variadic);
}

/// <summary>
/// <c>NSArray&lt;NSString *&gt;</c> or <c>id&lt;NSCopying&gt;</c>: a type with a list
/// in angle brackets, which is a class's type arguments or the protocols an
/// object adopts; which of the two depends on the type, and is decided by
/// whoever knows it.
/// </summary>
public sealed record CObjCQualified(CType Base, IReadOnlyList<CType> Arguments) : CType
{
    public bool Equals(CObjCQualified? other) =>
        other is not null && Base.Equals(other.Base) && Arguments.SequenceEqual(other.Arguments);

    public override int GetHashCode() => HashCode.Combine(Base, Arguments.Count);
}

/// <summary>What <c>_Nonnull</c>, <c>_Nullable</c> or nothing said about a pointer.</summary>
public enum Nullability { Unspecified, Nullable, NonNull }

/// <summary>What a binding cannot spell: an atomic, a complex number, a 16-bit float.</summary>
public sealed record CUnsupported(string Why) : CType;

/// <summary>
/// <c>ext_vector_type(N)</c>, counted in lanes, or <c>vector_size(N)</c>,
/// counted in bytes: a SIMD vector of <paramref name="Element"/>.
/// </summary>
public sealed record CVector(CType Element, int Count, bool CountIsBytes) : CType;

public enum CTagKind { Struct, Union, Enum }

/// <summary>
/// Reads the type spellings clang writes into its JSON dump: a list of
/// specifiers, then an abstract declarator, as C writes them.
/// </summary>
public sealed partial class CTypeParser
{
    private static readonly HashSet<string> Qualifiers = new(StringComparer.Ordinal)
    {
        "const", "volatile", "restrict", "__restrict", "_Nonnull", "_Nullable", "_Null_unspecified",
        "_Nullable_result", "__unsafe_unretained", "__strong", "__weak", "__autoreleasing", "__kindof",
        "__single", "__unsafe_indexable", "__counted_by", "__ptrauth",
    };

    private static readonly HashSet<string> BuiltinWords = new(StringComparer.Ordinal)
    {
        "void", "char", "short", "int", "long", "signed", "unsigned", "float", "double", "_Bool", "bool",
        "__int128", "_Float16", "__fp16", "__bf16", "_Complex", "wchar_t", "char8_t", "char16_t", "char32_t",
    };

    private readonly List<string> _tokens;
    private int _at;

    private CTypeParser(string spelling)
    {
        _tokens = Tokenize(QualifiedAnonymous().Replace(spelling, "$1 (unnamed at $2)"));
    }

    /// <summary>
    /// <c>union Outer::(anonymous union)::(anonymous at file:1:2)</c>, the way
    /// clang names an unnamed record nested in another: the last place is
    /// the record's.
    /// </summary>
    [System.Text.RegularExpressions.GeneratedRegex(
        @"\b(struct|union|enum)\s+[A-Za-z_][A-Za-z0-9_]*::.*?\((?:anonymous|unnamed)(?: (?:struct|union|enum))? at ([^()]+)\)")]
    private static partial System.Text.RegularExpressions.Regex QualifiedAnonymous();

    /// <summary>The type <paramref name="spelling"/> names.</summary>
    public static CType Parse(string spelling) => ParseAnnotated(spelling).Type;

    /// <summary>
    /// The type <paramref name="spelling"/> names, and what its outermost
    /// level says about nil: the qualifier after the last <c>*</c> or
    /// <c>^</c>, or beside the type's name when there is no pointer.
    /// </summary>
    public static (CType Type, Nullability Nullability) ParseAnnotated(string spelling)
    {
        var parser = new CTypeParser(spelling);
        var (type, nullability) = parser.ParseType();
        return parser._at == parser._tokens.Count
            ? (type, nullability)
            : (new CUnsupported($"'{spelling}' has more after the type"), Nullability.Unspecified);
    }

    private static Nullability? NullabilityOf(string token) => token switch
    {
        "_Nonnull" => Nullability.NonNull,
        "_Nullable" or "_Nullable_result" => Nullability.Nullable,
        "_Null_unspecified" => Nullability.Unspecified,
        _ => null,
    };

    private string? Current => _at < _tokens.Count ? _tokens[_at] : null;

    private string Take() => _tokens[_at++];

    private bool Accept(string token)
    {
        if (Current != token) return false;
        _at++;
        return true;
    }

    private void Expect(string token)
    {
        if (!Accept(token))
            throw new FormatException($"expected '{token}' at token {_at} of '{string.Join(" ", _tokens)}'");
    }

    private (CType Type, Nullability Nullability) ParseType()
    {
        var (baseType, nullability) = ParseSpecifiers();
        var (apply, outermost) = ParseDeclarator(nullability);
        return (apply(baseType), outermost ?? nullability);
    }

    /// <summary>The words before the declarator, which name the base type, and what they say about nil.</summary>
    private (CType Type, Nullability Nullability) ParseSpecifiers()
    {
        var builtin = new List<string>();
        CType? named = null;
        var nullability = Nullability.Unspecified;
        (int Count, bool Bytes)? vector = null;
        bool packed = false;

        while (Current is { } token)
        {
            if (Qualifiers.Contains(token))
            {
                if (NullabilityOf(token) is { } said) nullability = said;
                _at++;
                // A pointer-authentication or bounds qualifier takes arguments;
                // after any other, a parenthesis begins the declarator.
                if (Current == "(" && token is "__ptrauth" or "__counted_by") SkipBalanced();
                continue;
            }

            if (token == "__attribute__")
            {
                _at++;
                string attribute = SkipBalanced();
                var declared = VectorAttribute().Match(attribute);
                if (declared.Success)
                {
                    vector = (int.Parse(declared.Groups[2].Value, System.Globalization.CultureInfo.InvariantCulture),
                              declared.Groups[1].Value == "vector_size");
                    packed = attribute.Contains("aligned", StringComparison.Ordinal);
                }
                else if (attribute.Contains("vector_size") || attribute.Contains("ext_vector_type"))
                    named = new CUnsupported("a vector counted by an expression");
                continue;
            }

            if (token is "_Atomic")
            {
                _at++;
                if (Current == "(") SkipBalanced();
                named = new CUnsupported("an atomic type");
                continue;
            }

            if (token is "typeof" or "__typeof__" or "__typeof")
            {
                _at++;
                SkipBalanced();
                named = new CUnsupported("a typeof type");
                continue;
            }

            if (BuiltinWords.Contains(token) && named is null)
            {
                builtin.Add(Take());
                continue;
            }

            if (token is "struct" or "union" or "enum" && named is null && builtin.Count == 0)
            {
                _at++;
                var kind = token switch { "struct" => CTagKind.Struct, "union" => CTagKind.Union, _ => CTagKind.Enum };
                if (Current is { } where && where.StartsWith("(", StringComparison.Ordinal))
                    named = new CAnonymous(kind, Take());
                else
                    named = new CTag(kind, Take());
                continue;
            }

            // `CF_AVAILABLE(10_2, 2_0) CFStringRef` and `CF_RETURNS_RETAINED
            // SecKeyRef`: an attribute clang prints as the macro that spelled
            // it, which a type name follows.
            if (named is null && builtin.Count == 0 && IsAttributeMacro(token) && AttributeMacroLength() is { } length)
            {
                _at += length;
                continue;
            }

            // `id<NSCopying>`, `NSObject<NSCopying> *` and `NSArray<NSString *> *`:
            // protocols an object adopts, or a class's type arguments.
            if (token == "<" && named is not null)
            {
                _at++;
                var arguments = new List<CType>();
                while (Current is not null && !Accept(">"))
                {
                    arguments.Add(ParseType().Type);
                    Accept(",");
                }
                named = named is CUnsupported ? named : new CObjCQualified(named, arguments);
                continue;
            }

            if (IsIdentifier(token) && named is null && builtin.Count == 0)
            {
                named = new CTypedef(Take());
                continue;
            }

            break;
        }

        if (named is null && builtin.Count == 0) throw new FormatException($"no type at token {_at}");
        var type = named ?? Builtin(builtin);

        // Apple's simd_packed types are aligned to a lane rather than to the
        // vector, which no Stainless vector is.
        if (packed) return (new CUnsupported("a packed vector, aligned less than a vector is"), nullability);
        return (vector is { } lanes ? new CVector(type, lanes.Count, lanes.Bytes) : type, nullability);
    }

    [System.Text.RegularExpressions.GeneratedRegex(@"(?:__)?(ext_vector_type|vector_size)(?:__)?\s*\(\s*(\d+)\s*\)")]
    private static partial System.Text.RegularExpressions.Regex VectorAttribute();

    /// <summary>The builtin <paramref name="words"/> spell, in a canonical order.</summary>
    private static CType Builtin(List<string> words)
    {
        if (words.Contains("_Complex")) return new CUnsupported("a complex number");
        if (words.Contains("__int128"))
            return new CBuiltin(words.Contains("unsigned") ? "unsigned __int128" : "__int128");
        if (words is ["long", "double"] or ["double", "long"]) return new CBuiltin("long double");
        if (words.Contains("_Float16") || words.Contains("__fp16") || words.Contains("__bf16"))
            return new CUnsupported("a 16-bit float");

        bool unsigned = words.Contains("unsigned");
        int longs = words.Count(w => w == "long");
        string? kind = words.FirstOrDefault(w => w is "void" or "char" or "short" or "float" or "double"
            or "_Bool" or "bool" or "wchar_t" or "char8_t" or "char16_t" or "char32_t");

        string name = kind switch
        {
            "void" => "void",
            "float" => "float",
            "double" => "double",
            "_Bool" or "bool" => "bool",
            "char" => words.Contains("signed") ? "signed char" : unsigned ? "unsigned char" : "char",
            "short" => unsigned ? "unsigned short" : "short",
            "wchar_t" => "wchar_t",
            "char8_t" => "unsigned char",
            "char16_t" => "char16_t",
            "char32_t" => "char32_t",
            _ => longs switch
            {
                0 => unsigned ? "unsigned int" : "int",
                1 => unsigned ? "unsigned long" : "long",
                _ => unsigned ? "unsigned long long" : "long long",
            },
        };
        return new CBuiltin(name);
    }

    /// <summary>
    /// An abstract declarator, returned as what it does to the type before
    /// it: pointers bind looser than the arrays and parameter lists after
    /// them, and a parenthesised declarator applies last. With it, what the
    /// outermost level says about nil, or null when that is the base type's.
    /// </summary>
    private (Func<CType, CType> Apply, Nullability? Outermost) ParseDeclarator(Nullability baseNullability)
    {
        var pointers = new List<string>();
        Nullability? pointerNullability = null;
        while (Current is "*" or "^" || (Current is { } q && Qualifiers.Contains(q)))
        {
            string token = Take();
            if (token is "*" or "^")
            {
                pointers.Add(token);
                pointerNullability = Nullability.Unspecified;
            }
            else if (pointers.Count > 0 && NullabilityOf(token) is { } said)
                pointerNullability = said;
            else if (Current == "(" && token is "__ptrauth" or "__counted_by") SkipBalanced();
        }

        // What a function returns is what the pointers say, or the base type.
        var resultNullability = pointerNullability ?? baseNullability;

        Func<CType, CType>? inner = null;
        Nullability? innerOutermost = null;
        if (Current == "(" && Peek(1) is "*" or "^" or "(")
        {
            Expect("(");
            (inner, innerOutermost) = ParseDeclarator(Nullability.Unspecified);
            Expect(")");
        }

        var suffixes = new List<Func<CType, CType>>();
        while (true)
        {
            if (Accept("["))
            {
                long? length = null;
                if (Current != "]")
                {
                    string text = Take();
                    length = long.TryParse(text, out long parsed) ? parsed : null;
                    while (Current != "]") _at++;
                }
                Expect("]");
                long? captured = length;
                suffixes.Add(t => new CArray(t, captured));
                continue;
            }

            if (Current == "(")
            {
                var (parameters, nullabilities, variadic) = ParseParameters();
                bool first = suffixes.Count == 0;
                suffixes.Add(t => new CFunction(t, parameters, variadic)
                {
                    ParameterNullability = nullabilities,
                    ResultNullability = first ? resultNullability : Nullability.Unspecified,
                });
                continue;
            }

            // A function type's own attributes, printed after its parameters.
            if (Current == "__attribute__")
            {
                _at++;
                SkipBalanced();
                continue;
            }

            break;
        }

        Nullability? outermost = inner is not null ? innerOutermost
            : suffixes.Count > 0 ? Nullability.Unspecified
            : pointerNullability;

        return (type =>
        {
            foreach (string pointer in pointers)
                type = pointer == "^"
                    ? type is CFunction function ? new CBlock(function) : new CUnsupported("a block of a non-function")
                    : new CPointer(type);

            for (int i = suffixes.Count - 1; i >= 0; i--)
                type = suffixes[i](type);

            if (inner is not null)
            {
                // `(^)` around a function: the block's own syntax.
                type = inner(type);
            }

            return type;
        }, outermost);
    }

    private (IReadOnlyList<CType> Parameters, IReadOnlyList<Nullability> Nullabilities, bool Variadic) ParseParameters()
    {
        Expect("(");
        var parameters = new List<CType>();
        var nullabilities = new List<Nullability>();
        bool variadic = false;

        if (Accept(")")) return (parameters, nullabilities, false);

        while (true)
        {
            if (Accept("..."))
            {
                variadic = true;
                Expect(")");
                break;
            }

            var (parameter, nullability) = ParseType();
            parameters.Add(parameter);
            nullabilities.Add(nullability);
            if (Accept(")")) break;
            Expect(",");
        }

        // `(void)` is no parameters.
        if (parameters is [CBuiltin { Name: "void" }])
        {
            parameters.Clear();
            nullabilities.Clear();
        }
        return (parameters, nullabilities, variadic);
    }

    private string? Peek(int ahead) => _at + ahead < _tokens.Count ? _tokens[_at + ahead] : null;

    /// <summary>Skips a parenthesised run, returning its text.</summary>
    private string SkipBalanced()
    {
        if (Current != "(") return "";
        int depth = 0;
        var text = new List<string>();
        do
        {
            string token = Take();
            text.Add(token);
            if (token == "(") depth++;
            else if (token == ")") depth--;
        }
        while (depth > 0 && Current is not null);
        return string.Join(" ", text);
    }

    /// <summary>
    /// How many tokens the attribute macro at the current position takes --
    /// its name, and its arguments if it has any -- or null when what is
    /// there is a type name after all: a type name is not followed by another.
    /// </summary>
    private int? AttributeMacroLength()
    {
        int after = _at + 1;
        if (Peek(1) == "(")
        {
            if (Peek(2) is "*" or "^") return null;
            int depth = 0;
            do
            {
                if (_tokens[after] == "(") depth++;
                else if (_tokens[after] == ")") depth--;
                after++;
            }
            while (depth > 0 && after < _tokens.Count);
        }

        while (after < _tokens.Count && Qualifiers.Contains(_tokens[after])) after++;
        return after < _tokens.Count && IsIdentifier(_tokens[after]) ? after - _at : null;
    }

    /// <summary>An all-capitals name with an underscore in it, which only a macro is.</summary>
    private static bool IsAttributeMacro(string token) =>
        token.Contains('_') && token.All(c => char.IsAsciiLetterUpper(c) || char.IsAsciiDigit(c) || c == '_');

    private static bool IsIdentifier(string token) =>
        token.Length > 0 && (char.IsAsciiLetter(token[0]) || token[0] == '_' || token[0] == '$');

    /// <summary>
    /// Identifiers, numbers, punctuation and <c>...</c>; and an anonymous
    /// tag's <c>(unnamed struct at ...)</c> as one token, since its path may
    /// hold anything.
    /// </summary>
    private static List<string> Tokenize(string text)
    {
        var tokens = new List<string>();
        int i = 0;
        while (i < text.Length)
        {
            char c = text[i];
            if (char.IsWhiteSpace(c)) { i++; continue; }

            if (c == '(' && tokens.Count > 0 && tokens[^1] is "struct" or "union" or "enum" &&
                (Rest(text, i + 1, "unnamed") || Rest(text, i + 1, "anonymous")))
            {
                int depth = 0, start = i;
                do
                {
                    if (text[i] == '(') depth++;
                    else if (text[i] == ')') depth--;
                    i++;
                }
                while (depth > 0 && i < text.Length);
                tokens.Add(text[start..i]);
                continue;
            }

            if (Rest(text, i, "..."))
            {
                tokens.Add("...");
                i += 3;
                continue;
            }

            if (char.IsAsciiLetterOrDigit(c) || c is '_' or '$')
            {
                int start = i;
                while (i < text.Length && (char.IsAsciiLetterOrDigit(text[i]) || text[i] is '_' or '$')) i++;
                tokens.Add(text[start..i]);
                continue;
            }

            tokens.Add(c.ToString());
            i++;
        }

        return tokens;
    }

    private static bool Rest(string text, int at, string word) =>
        string.CompareOrdinal(text, at, word, 0, word.Length) == 0;
}
