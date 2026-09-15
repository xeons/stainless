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

using Stainless.Source;

namespace Stainless.Syntax;

/// <summary>
/// A hand-written recursive-descent parser with a precedence-climbing
/// expression parser. It parses one file into one <see cref="CompilationUnitSyntax"/>;
/// nothing here needs to know about any other file, which is what makes
/// header-free separate compilation possible.
/// </summary>
public sealed class Parser
{
    private readonly List<Token> _tokens;
    private readonly SourceText _source;
    private readonly Lexer? _lexer;
    private DiagnosticBag _diagnostics;
    private int _pos;

    /// <summary>
    /// How many levels of nesting are open. See <see cref="Source.Recursion"/>:
    /// a recursive-descent parser recurses once per level, so without a bound
    /// a deeply nested file ends the process instead of being diagnosed.
    /// </summary>
    private int _depth;

    public Parser(
        SourceText source, DiagnosticBag diagnostics, IReadOnlyCollection<string>? symbols = null)
    {
        _source = source;
        _diagnostics = diagnostics;
        _lexer = new Lexer(source, diagnostics, symbols);
        _tokens = _lexer.Tokenize();
    }

    /// <summary>
    /// A parser over tokens somebody else lexed: one interpolation's hole.
    ///
    /// The tokens came from the same file and carry their real positions, so
    /// everything this parser reports points where it should.
    /// </summary>
    private Parser(SourceText source, DiagnosticBag diagnostics, IReadOnlyList<Token> tokens)
    {
        _source = source;
        _diagnostics = diagnostics;
        _lexer = null;

        // Copied, because the parser rewrites a `>>` into two `>` in place
        // when it closes nested type arguments, and the lexer's list is not
        // this parser's to change.
        _tokens = [.. tokens];
    }

    // ------------------------------------------------------------ nesting

    /// <summary>
    /// Opens one level of nesting, or reports that there are too many.
    ///
    /// False means the caller must not descend: it should consume something
    /// and return a node standing for what it could not parse, exactly as it
    /// would for any other malformed input. Reported once per file, because a
    /// program this deep would otherwise produce one message per level.
    /// </summary>
    private bool Descend()
    {
        if (++_depth <= Source.Recursion.MaxDepth) return true;

        _depth--;

        if (!_tooDeep)
        {
            _tooDeep = true;
            _diagnostics.Error("SL0108", Current.Span,
                $"this is nested more than {Source.Recursion.MaxDepth} levels deep, which is " +
                "past what can be compiled; the usual cause is generated source, and the fix " +
                "is to give the inner part a name of its own");

            // Nothing further in this file can be read usefully: every open
            // construct is about to be closed by an unwind that did not parse
            // what was inside it. Going to the end makes that unwind quiet,
            // which leaves the one message that says what happened.
            _pos = _tokens.Count - 1;
        }

        return false;
    }

    private void Ascend() => _depth--;

    /// <summary>
    /// What stands in for an expression that could not be read. The same
    /// zero SL0107 leaves behind, so nothing downstream has a second shape
    /// to know about.
    /// </summary>
    private ExpressionSyntax Unreadable(int start) =>
        new LiteralSyntax(SpanFrom(start), TokenKind.IntLiteral, 0UL);

    private bool _tooDeep;

    // ------------------------------------------------------------ token helpers

    private Token Current => Peek(0);
    private Token Peek(int offset)
    {
        int index = Math.Min(_pos + offset, _tokens.Count - 1);
        return _tokens[index];
    }

    private bool At(TokenKind kind) => Current.Kind == kind;
    private bool AtAny(params TokenKind[] kinds) => kinds.Contains(Current.Kind);

    private Token Advance() => _tokens[Math.Min(_pos++, _tokens.Count - 1)];

    private bool Match(TokenKind kind)
    {
        if (!At(kind)) return false;
        Advance();
        return true;
    }

    private Token Expect(TokenKind kind)
    {
        if (At(kind)) return Advance();
        if (!_tooDeep)
            _diagnostics.Error("SL0100", Current.Span,
                $"expected {kind.Describe()}, found {Current.Kind.Describe()}");
        return new Token(kind, Current.Span, kind.FixedText() ?? "");
    }

    private string ExpectIdentifier()
    {
        if (At(TokenKind.Identifier)) return Advance().Text;
        if (!_tooDeep)
            _diagnostics.Error("SL0101", Current.Span,
                $"expected an identifier, found {Current.Kind.Describe()}");
        return "?";
    }

    private SourceSpan SpanFrom(int startIndex) =>
        new(_source, _tokens[startIndex].Span.Start, _tokens[Math.Max(0, _pos - 1)].Span.End);

    /// <summary>
    /// Runs <paramref name="attempt"/> without committing: token position is
    /// restored and diagnostics are discarded unless the attempt succeeds.
    /// This is how casts and local declarations are told apart from expressions.
    /// </summary>
    private bool Speculate<T>(Func<T?> attempt, out T? result) where T : class
    {
        int savedPos = _pos;
        int savedDepth = _depth;
        bool savedTooDeep = _tooDeep;
        var savedDiagnostics = _diagnostics;
        _diagnostics = new DiagnosticBag();
        try
        {
            result = attempt();
            if (result is not null && !_diagnostics.HasErrors) return true;
            _pos = savedPos;
            result = null;
            return false;
        }
        finally
        {
            _diagnostics = savedDiagnostics;

            // An attempt that is thrown away leaves nothing behind, the depth
            // limit's "already said so" included: the same tokens are about to
            // be parsed again for real, and that parse has to be able to say it.
            _depth = savedDepth;
            _tooDeep = savedTooDeep;
        }
    }

    // ------------------------------------------------------------ compilation unit

    public CompilationUnitSyntax ParseCompilationUnit()
    {
        int start = _pos;

        string? documentation = Current.Documentation;

        QualifiedName? moduleName = null;
        if (Match(TokenKind.ModuleKeyword))
        {
            moduleName = ParseQualifiedName();
            Expect(TokenKind.Semicolon);
        }
        else
        {
            // No module clause, so the block above the first token belongs to
            // whatever that token declares rather than to the file.
            documentation = null;
        }

        var imports = new List<ImportSyntax>();
        while (At(TokenKind.ImportKeyword))
        {
            int importStart = _pos;
            Advance();
            var name = ParseQualifiedName();
            string? alias = Match(TokenKind.AsKeyword) ? ExpectIdentifier() : null;
            Expect(TokenKind.Semicolon);
            imports.Add(new ImportSyntax(SpanFrom(importStart), name, alias));
        }

        var declarations = new List<Declaration>();
        while (!At(TokenKind.EndOfFile))
        {
            int before = _pos;
            declarations.AddRange(ParseDeclaration(enclosingType: null));
            if (_pos == before) Advance();          // guarantee progress on malformed input
        }

        // The lexer is null only for the sub-parser over one interpolation's
        // hole, and that one parses an expression rather than a file.
        return new CompilationUnitSyntax(
            SpanFrom(start), _source, moduleName, imports, declarations, _lexer!.Libraries)
        {
            Documentation = documentation,
        };
    }

    private QualifiedName ParseQualifiedName()
    {
        int start = _pos;
        var parts = new List<string> { ExpectIdentifier() };
        while (At(TokenKind.Dot) && Peek(1).Kind == TokenKind.Identifier)
        {
            Advance();
            parts.Add(Advance().Text);
        }
        return new QualifiedName(SpanFrom(start), parts);
    }

    // ------------------------------------------------------------ declarations

    /// <summary>
    /// Parses one declaration. Returns several when an <c>extern "C" { }</c>
    /// block is flattened into its members.
    /// </summary>
    private List<Declaration> ParseDeclaration(string? enclosingType)
    {
        // Every declaration funnels through here, so taking the block once and
        // applying it to whatever comes back is the whole of the plumbing --
        // the twenty methods below never mention documentation.
        string? documentation = Current.Documentation;

        var declarations = ParseDeclarationCore(enclosingType);
        if (documentation is null) return declarations;

        // Only the first: an anonymous struct hoisted out of its parent is a
        // second declaration from the same source, and the block was written
        // about the type the reader can see.
        if (declarations.Count > 0)
            declarations[0] = declarations[0] with { Documentation = documentation };

        return declarations;
    }

    private List<Declaration> ParseDeclarationCore(string? enclosingType)
    {
        int start = _pos;
        var attributes = ParseAttributeLists();
        var modifiers = ParseModifiers();

        if (modifiers.HasFlag(Modifiers.Static) && StaticIsAboutNothing() is { } what)
        {
            string article = "aeiou".Contains(what[0]) ? "an" : "a";

            _diagnostics.Error("SL0578", SpanFrom(start),
                $"{article} {what} cannot be 'static': the word means that a thing belongs to " +
                $"its type rather than to an object of it, and {article} {what} has neither. " +
                "Only a class may be static, and a module is usually the better answer");
            modifiers &= ~Modifiers.Static;
        }

        if (At(TokenKind.ExternKeyword) || At(TokenKind.ExportKeyword))
            return ParseLinkageDeclaration(start, modifiers);

        if (AtAny(TokenKind.ClassKeyword, TokenKind.StructKeyword,
                  TokenKind.InterfaceKeyword, TokenKind.AttributeKeyword,
                  TokenKind.VariantKeyword, TokenKind.UnionKeyword))
        {
            var hoisted = new List<Declaration>();
            var declared = ParseTypeDeclaration(start, modifiers, attributes, hoisted);

            // The type first, then the anonymous members lifted out of it.
            // Order does not matter to the binder, and this reads better in a
            // dump of the tree.
            hoisted.Insert(0, declared);
            return hoisted;
        }

        if (At(TokenKind.UsingKeyword))
            return [ParseAliasDeclaration(start, modifiers)];

        if (At(TokenKind.EnumKeyword))
            return [ParseEnumDeclaration(start, modifiers, attributes)];

        if (At(TokenKind.DelegateKeyword) || AtClosureDeclaration())
            return [ParseDelegateDeclaration(start, modifiers)];

        if (At(TokenKind.Tilde) && enclosingType is not null)
            return [ParseDestructor(start, enclosingType)];

        if (AtEventDeclaration())
            return [ParseEventDeclaration(start, modifiers, attributes)];

        if (modifiers.HasFlag(Modifiers.Static))
            return AtOperatorDeclaration()
                ? [ParseOperatorDeclaration(start, modifiers)]
                : [ParseStaticDeclaration(start, modifiers, enclosingType)];

        if (modifiers.HasFlag(Modifiers.Const))
            return [ParseGlobalConst(start, modifiers)];

        // A constructor looks like `TypeName(` inside its own type.
        if (enclosingType is not null &&
            At(TokenKind.Identifier) && Current.Text == enclosingType &&
            Peek(1).Kind == TokenKind.OpenParen)
        {
            Advance();
            var ctorParams = ParseParameterList(out bool ctorVariadic);
            var ctorBody = ParseBlock();

            if (ctorVariadic)
                _diagnostics.Error("SL0493", SpanFrom(start),
                    $"'{enclosingType}' cannot have a variadic constructor; '...' may only " +
                    "be written on an 'extern \"C\"' declaration, because there is no " +
                    "'va_list' to read the extra arguments with");

            return [new ConstructorDeclSyntax(SpanFrom(start), modifiers, enclosingType, ctorParams, ctorBody)];
        }

        return [ParseFunctionOrField(start, modifiers, LinkageKind.Stainless, attributes)];
    }

    /// <summary>
    /// Parses any number of <c>[Name(args)]</c> groups, each of which may list
    /// several attributes separated by commas.
    /// </summary>
    private List<AttributeSyntax> ParseAttributeLists()
    {
        var attributes = new List<AttributeSyntax>();

        while (At(TokenKind.OpenBracket))
        {
            Advance();
            do
            {
                int start = _pos;
                var name = ParseQualifiedName();
                var arguments = At(TokenKind.OpenParen) ? ParseArgumentList() : [];
                attributes.Add(new AttributeSyntax(SpanFrom(start), name, arguments));
            }
            while (Match(TokenKind.Comma));

            Expect(TokenKind.CloseBracket);
        }

        return attributes;
    }

    /// <summary>
    /// What is about to be declared, when <c>static</c> could not be about it,
    /// or null when the word is in a place it might mean something.
    /// </summary>
    private string? StaticIsAboutNothing() => Current.Kind switch
    {
        TokenKind.StructKeyword => "struct",
        TokenKind.InterfaceKeyword => "interface",
        TokenKind.VariantKeyword => "variant",
        TokenKind.UnionKeyword => "union",
        TokenKind.AttributeKeyword => "attribute",
        TokenKind.EnumKeyword => "enum",
        TokenKind.DelegateKeyword => "delegate",
        TokenKind.UsingKeyword => "type alias",
        TokenKind.ExternKeyword or TokenKind.ExportKeyword => "foreign declaration",
        _ => null,
    };

    private Modifiers ParseModifiers()
    {
        var modifiers = Modifiers.None;
        while (true)
        {
            switch (Current.Kind)
            {
                case TokenKind.PublicKeyword: modifiers |= Modifiers.Public; Advance(); break;
                case TokenKind.PrivateKeyword: modifiers |= Modifiers.Private; Advance(); break;
                case TokenKind.ConstKeyword: modifiers |= Modifiers.Const; Advance(); break;
                case TokenKind.ProtectedKeyword: modifiers |= Modifiers.Protected; Advance(); break;
                case TokenKind.VirtualKeyword: modifiers |= Modifiers.Virtual; Advance(); break;
                case TokenKind.OverrideKeyword: modifiers |= Modifiers.Override; Advance(); break;
                case TokenKind.AbstractKeyword: modifiers |= Modifiers.Abstract; Advance(); break;
                case TokenKind.SealedKeyword: modifiers |= Modifiers.Sealed; Advance(); break;
                case TokenKind.StaticKeyword: modifiers |= Modifiers.Static; Advance(); break;
                case TokenKind.ThreadsafeKeyword:
                    modifiers |= Modifiers.Threadsafe; Advance(); break;

                // `com` reads as a modifier and means a different kind of
                // declaration; only `interface` and `class` may follow it,
                // which ParseTypeDeclaration checks.
                case TokenKind.ComKeyword: modifiers |= Modifiers.Com; Advance(); break;
                default: return modifiers;
            }
        }
    }

    /// <summary>
    /// <c>__stdcall</c> and its relatives, written after the linkage string.
    ///
    /// They are identifiers rather than keywords, matched by their text where
    /// one may appear. Two underscores is not a name anybody writes by accident,
    /// and making them keywords would take four of them from every program to
    /// serve a declaration form most programs never use.
    /// </summary>
    private CallingConvention ParseCallingConvention()
    {
        if (!At(TokenKind.Identifier)) return CallingConvention.Default;

        var convention = Current.Text switch
        {
            "__cdecl" => CallingConvention.Cdecl,
            "__stdcall" => CallingConvention.Stdcall,
            "__fastcall" => CallingConvention.Fastcall,
            "__vectorcall" => CallingConvention.Vectorcall,
            _ => CallingConvention.Default,
        };

        if (convention != CallingConvention.Default) Advance();
        return convention;
    }

    private List<Declaration> ParseLinkageDeclaration(int start, Modifiers modifiers)
    {
        bool isExtern = At(TokenKind.ExternKeyword);
        bool isCpp = false;
        Advance();

        // The convention string is required and, for now, must be "C".
        if (At(TokenKind.StringLiteral))
        {
            string convention = (string)(Advance().Value ?? "");
            if (convention is not ("C" or "C++"))
                _diagnostics.Error("SL0102", SpanFrom(start),
                    $"unsupported linkage convention \"{convention}\"; \"C\" and \"C++\" are supported");

            isCpp = convention == "C++";
        }
        else
        {
            _diagnostics.Error("SL0103", Current.Span,
                $"expected a linkage convention string such as \"C\" after '{(isExtern ? "extern" : "export")}'");
        }

        var linkage = (isExtern, isCpp) switch
        {
            (true, false) => LinkageKind.ExternC,
            (true, true) => LinkageKind.ExternCpp,
            (false, false) => LinkageKind.ExportC,
            _ => LinkageKind.ExportCpp,
        };

        // Before the block or the single declaration, so that a binding module
        // says `extern "C" __stdcall { ... }` once rather than on two hundred
        // lines. A declaration inside the block may still name its own.
        var blockConvention = ParseCallingConvention();

        // Block form: extern "C" { ... }
        //
        // A modifier written on the block belongs to every declaration in it,
        // which is the whole reason to write one there: a binding module that
        // re-exports two hundred entry points should say 'public' once.
        if (Match(TokenKind.OpenBrace))
        {
            var members = new List<Declaration>();
            while (!At(TokenKind.CloseBrace) && !At(TokenKind.EndOfFile))
            {
                int before = _pos;
                int memberStart = _pos;
                var memberModifiers = modifiers | ParseModifiers();
                var memberConvention = ParseCallingConvention();
                if (memberConvention == CallingConvention.Default)
                    memberConvention = blockConvention;

                members.Add(WithConvention(
                    ParseFunctionOrField(memberStart, memberModifiers, linkage), memberConvention));
                if (_pos == before) Advance();
            }
            Expect(TokenKind.CloseBrace);
            return members;
        }

        // Single-declaration form: extern "C" int puts(byte* s);
        var singleModifiers = modifiers | ParseModifiers();
        var singleConvention = ParseCallingConvention();
        if (singleConvention == CallingConvention.Default) singleConvention = blockConvention;

        return [WithConvention(
            ParseFunctionOrField(start, singleModifiers, linkage), singleConvention)];
    }

    /// <summary>
    /// Puts the convention on the declaration, where the declaration is a
    /// function. A field cannot have one, and one written before a field is
    /// reported rather than dropped.
    /// </summary>
    private Declaration WithConvention(Declaration declaration, CallingConvention convention)
    {
        if (convention == CallingConvention.Default) return declaration;

        if (declaration is FunctionDeclSyntax function)
            return function with { CallingConvention = convention };

        _diagnostics.Error("SL0592", declaration.Span,
            "a calling convention says how a function is called, so it can only be written on " +
            "one; this declares a value");

        return declaration;
    }

    /// <summary>
    /// A type declaration.
    ///
    /// A nameless <c>struct { }</c> or <c>union { }</c> member has no name to be
    /// declared under, so one is generated and the type is lifted into
    /// <paramref name="hoisted"/> to be declared beside its parent. The parent
    /// keeps an ordinary field of it, marked anonymous, which is what carries
    /// the layout; only name lookup knows the difference.
    /// </summary>
    private TypeDeclSyntax ParseTypeDeclaration(
        int start, Modifiers modifiers, IReadOnlyList<AttributeSyntax> attributes,
        List<Declaration> hoisted, string? generatedName = null)
    {
        var kind = Current.Kind switch
        {
            TokenKind.ClassKeyword => TypeDeclKind.Class,
            TokenKind.InterfaceKeyword => TypeDeclKind.Interface,
            TokenKind.AttributeKeyword => TypeDeclKind.Attribute,
            TokenKind.VariantKeyword => TypeDeclKind.Variant,
            TokenKind.UnionKeyword => TypeDeclKind.Union,
            _ => TypeDeclKind.Struct,
        };
        Advance();

        // A nameless member has no identifier to read; its name was made for it.
        string name = generatedName ?? ExpectIdentifier();
        var typeParameters = generatedName is null ? ParseTypeParameterList() : [];

        // `class Circle : Shape, Comparable<Circle>` -- a list of interfaces,
        // which may themselves be generic, so these are full types not bare names.
        var implements = new List<TypeSyntax>();
        if (Match(TokenKind.Colon))
        {
            do { implements.Add(ParseType()); }
            while (Match(TokenKind.Comma));
        }

        var constraints = ParseWhereClauses();

        // `struct HWND__;` -- a type declared here and laid out somewhere else.
        // It is C's incomplete type and not a forward declaration: nothing
        // completes it, which is the point, and the binder says so if a second
        // declaration tries to.
        if (Match(TokenKind.Semicolon))
            return new TypeDeclSyntax(
                SpanFrom(start), modifiers, kind, name, typeParameters,
                constraints, implements, [], attributes) { IsOpaque = true };

        Expect(TokenKind.OpenBrace);

        var members = new List<Declaration>();
        var cases = new List<VariantCaseSyntax>();

        int anonymous = 0;

        while (!At(TokenKind.CloseBrace) && !At(TokenKind.EndOfFile))
        {
            int before = _pos;

            // `struct {` or `union {` with nothing between the keyword and the
            // brace is a member without a name, as in C. An access modifier may
            // come first, which C has no place for and Stainless does.
            if (AtAnonymousMember())
            {
                var memberModifiers = ParseModifiers();
                members.Add(
                    ParseAnonymousMember(name, anonymous++, memberModifiers, hoisted));
                continue;
            }

            // Inside a variant, `Name(...)` and `Name;` are cases. Nothing else
            // in a member position has that shape: a method writes its return
            // type first, a property opens a brace, and a variant has no
            // constructor, because its cases are how one is built.
            if (kind == TypeDeclKind.Variant && At(TokenKind.Identifier) &&
                Peek(1).Kind is TokenKind.OpenParen or TokenKind.Semicolon)
            {
                cases.Add(ParseVariantCase());
                continue;
            }

            foreach (var member in ParseDeclaration(enclosingType: name))
            {
                // A type declared inside another is lifted out beside it and
                // named for where it was written, so `Outer.Inner` is its name
                // everywhere -- in a diagnostic, in the mangled symbol, and at
                // a use site. Nesting is about where a name is *reached from*;
                // it says nothing about layout or about what the inner type may
                // see, and hoisting is what keeps it that way.
                //
                // The parse of the inner type has already hoisted whatever was
                // inside *it*, so this walks the whole list rather than the
                // first entry: `Outer.Inner.Deeper` gets its full name by being
                // prefixed once at each level on the way out.
                switch (member)
                {
                    case TypeDeclSyntax inner:
                        hoisted.Add(inner with { Name = name + "." + inner.Name });
                        break;

                    case EnumDeclSyntax inner:
                        hoisted.Add(inner with { Name = name + "." + inner.Name });
                        break;

                    case DelegateDeclSyntax inner:
                        hoisted.Add(inner with { Name = name + "." + inner.Name });
                        break;

                    default:
                        members.Add(member);
                        break;
                }
            }

            if (_pos == before) Advance();
        }
        Expect(TokenKind.CloseBrace);

        if (constraints.Count > 0 && typeParameters.Count == 0)
            _diagnostics.Error("SL0331", SpanFrom(start),
                $"'{name}' is not generic, so it cannot have a 'where' clause");

        if (kind == TypeDeclKind.Variant && cases.Count == 0)
            _diagnostics.Error("SL0430", SpanFrom(start),
                $"variant '{name}' has no cases; a variant is the choice between its cases, " +
                "so one with none has no values at all");

        return new TypeDeclSyntax(
            SpanFrom(start), modifiers, kind, name, typeParameters, constraints,
            implements, members, attributes) { Cases = cases };
    }

    /// <summary>
    /// A nameless <c>struct { }</c> or <c>union { }</c> member.
    ///
    /// The generated names carry a <c>$</c>, which no source identifier may, so
    /// neither the type nor the field can be written or collided with.
    /// </summary>
    /// <summary>
    /// True when the next member is a nameless <c>struct { }</c> or
    /// <c>union { }</c>, looking past any access modifier in front of it.
    /// </summary>
    private bool AtAnonymousMember()
    {
        int at = 0;
        while (Peek(at).Kind is TokenKind.PublicKeyword or TokenKind.PrivateKeyword) at++;

        return Peek(at).Kind is TokenKind.StructKeyword or TokenKind.UnionKeyword &&
               Peek(at + 1).Kind == TokenKind.OpenBrace;
    }

    private FieldDeclSyntax ParseAnonymousMember(
        string owner, int index, Modifiers modifiers, List<Declaration> hoisted)
    {
        int start = _pos;

        // ParseTypeDeclaration reads the kind from the keyword it is sitting on,
        // so `struct` and `union` both arrive here and neither needs saying twice.
        string typeName = $"{owner}$anon{index}";
        var declaration =
            ParseTypeDeclaration(start, Modifiers.Public, [], hoisted, typeName);

        hoisted.Add(declaration);

        // C ends the member with a semicolon; ParseTypeDeclaration does not
        // consume one, so an optional one is taken here.
        Match(TokenKind.Semicolon);

        var span = SpanFrom(start);
        var type = new NamedTypeSyntax(span, new QualifiedName(span, [typeName]), []);
        return new FieldDeclSyntax(span, modifiers, type, $"${index}", null, [])
        {
            IsAnonymous = true,
        };
    }

    /// <summary><c>Circle(double radius);</c> or <c>Empty;</c>.</summary>
    private VariantCaseSyntax ParseVariantCase()
    {
        int start = _pos;
        string? documentation = Current.Documentation;

        string name = ExpectIdentifier();

        IReadOnlyList<ParameterSyntax> parameters = [];
        bool variadic = false;

        if (At(TokenKind.OpenParen)) parameters = ParseParameterList(out variadic);

        if (variadic)
            _diagnostics.Error("SL0431", SpanFrom(start),
                $"case '{name}' cannot be variadic; a case's parameters are the fields it " +
                "carries, and a value has a fixed number of them");

        Expect(TokenKind.Semicolon);
        return new VariantCaseSyntax(SpanFrom(start), name, parameters)
        {
            Documentation = documentation,
        };
    }

    /// <summary><c>using Handle = void*;</c></summary>
    private Declaration ParseAliasDeclaration(int start, Modifiers modifiers)
    {
        Expect(TokenKind.UsingKeyword);
        string name = ExpectIdentifier();
        Expect(TokenKind.Equals);
        var target = ParseType();
        Expect(TokenKind.Semicolon);

        return new AliasDeclSyntax(SpanFrom(start), modifiers, name, target);
    }

    /// <summary>
    /// <c>enum Level : byte { Low, High = 9 }</c>. The underlying type defaults
    /// to <c>int</c>; a member without a value continues from the one before it.
    /// </summary>
    private Declaration ParseEnumDeclaration(
        int start, Modifiers modifiers, IReadOnlyList<AttributeSyntax> attributes)
    {
        Expect(TokenKind.EnumKeyword);
        string name = ExpectIdentifier();

        TypeSyntax? underlying = Match(TokenKind.Colon) ? ParseType() : null;

        Expect(TokenKind.OpenBrace);

        var members = new List<EnumMemberSyntax>();
        while (!At(TokenKind.CloseBrace) && !At(TokenKind.EndOfFile))
        {
            int memberStart = _pos;
            string? memberDoc = Current.Documentation;

            string memberName = ExpectIdentifier();
            ExpressionSyntax? value = Match(TokenKind.Equals) ? ParseExpression() : null;

            members.Add(new EnumMemberSyntax(SpanFrom(memberStart), memberName, value)
            {
                Documentation = memberDoc,
            });

            if (!Match(TokenKind.Comma)) break;
        }

        Expect(TokenKind.CloseBrace);

        return new EnumDeclSyntax(
            SpanFrom(start), modifiers, name, underlying, members, attributes);
    }

    /// <summary>
    /// <c>delegate int Comparison(int a, int b);</c>. The parameter names are
    /// documentation only, exactly as in a C prototype.
    /// </summary>
    private Declaration ParseDelegateDeclaration(int start, Modifiers modifiers)
    {
        // `closure` is the same declaration with a receiver, and is contextual
        // for the reason `event` is: it is a good enough variable name that
        // taking it would cost every program for a feature most do not use.
        bool carriesReceiver = !At(TokenKind.DelegateKeyword);
        Advance();

        // Before the return type, which is where `extern "C" __stdcall int f()`
        // already puts it. A convention reads as a property of the call rather
        // than of the answer, so it goes in front of both.
        var convention = ParseCallingConvention();

        var returnType = ParseType();

        string name = ExpectIdentifier();
        var typeParameters = At(TokenKind.Less) ? ParseTypeParameterList() : [];
        var parameters = ParseParameterList(out bool variadic);

        string kind = carriesReceiver ? "closure" : "delegate";

        if (variadic)
            _diagnostics.Error("SL0358", SpanFrom(start),
                $"{kind} '{name}' cannot be variadic; there is no way to call one safely");

        // A closure is a pointer *and* a receiver, and the receiver is passed
        // as an ordinary first argument by machinery this language emits. There
        // is no foreign function on the other end of one, so a convention would
        // describe nothing.
        if (carriesReceiver && convention != CallingConvention.Default)
            _diagnostics.Error("SL0621", SpanFrom(start),
                $"closure '{name}' cannot name a calling convention; only a delegate can, "
                + "because only a delegate is a C function pointer");

        Expect(TokenKind.Semicolon);
        return new DelegateDeclSyntax(
            SpanFrom(start), modifiers, name, returnType, parameters, carriesReceiver,
            typeParameters, carriesReceiver ? CallingConvention.Default : convention);
    }

    /// <summary>
    /// Whether <c>out</c> here is the modifier rather than a name.
    ///
    /// Contextual, and the standard library is what decided it: <c>out</c> is a
    /// local in <c>Convert.sl</c> and <c>Encoding.sl</c>, written long before
    /// this existed. The modifier is always followed by something that starts a
    /// type or a name, and never by an operator, so one token settles it.
    /// </summary>
    private bool AtOutModifier()
    {
        if (!At(TokenKind.Identifier) || Current.Text != "out") return false;

        // A literal is here so that `out 5` reaches the binder and is told it
        // has no storage to write back to, rather than dying in the parser
        // with a message about a parenthesis.
        var next = Peek(1).Kind;
        return next is TokenKind.Identifier or TokenKind.VarKeyword or TokenKind.Star
                    or TokenKind.ThisKeyword or TokenKind.IntLiteral or TokenKind.FloatLiteral
                    or TokenKind.StringLiteral or TokenKind.CharLiteral ||
               PrimitiveKeywords.Contains(next);
    }

    /// <summary>
    /// <c>out x</c>, <c>out int x</c> and <c>out var x</c>.
    ///
    /// The last two declare the variable at the call, which is most of the
    /// point: it exists to catch the answer, and a line above saying so is a
    /// line about the mechanism rather than about the program.
    /// </summary>
    private ExpressionSyntax ParseOutArgument(int start)
    {
        Advance();

        if (Match(TokenKind.VarKeyword))
        {
            var inferred = Current;
            string inferredName = ExpectIdentifier();
            return new OutArgumentSyntax(
                SpanFrom(start), null, null, inferredName, inferred.Span);
        }

        // `out x` names something that exists; `out int x` declares one. Both
        // begin with an identifier, so this speculates on reading a type and
        // finding a name after it.
        if (Speculate(TryParseOutDeclaration, out var declared) && declared is not null)
            return new OutArgumentSyntax(
                SpanFrom(start), null, declared.Type, declared.Name, declared.NameSpan);

        return new OutArgumentSyntax(SpanFrom(start), ParseExpression(), null, null, default);
    }

    private sealed record OutDeclaration(TypeSyntax Type, string Name, SourceSpan NameSpan);

    private OutDeclaration? TryParseOutDeclaration()
    {
        var type = ParseType();
        if (!At(TokenKind.Identifier)) return null;

        var name = Advance();

        // A declaration is the whole argument, so the next token closes the
        // list. Anything else means what was read as a type was an expression.
        if (!AtAny(TokenKind.Comma, TokenKind.CloseParen)) return null;

        return new OutDeclaration(type, name.Text, name.Span);
    }

    /// <summary>
    /// Whether the word here is <c>checked</c> or <c>unchecked</c>.
    ///
    /// Contextual, and it had to be: <c>tests/cases/static-methods</c> has a
    /// parameter named <c>checked</c>, written long before this existed. The
    /// price is that a function of that exact name could not be called, which
    /// is the same price <c>closure</c> pays.
    /// </summary>
    private bool AtCheckedWord() =>
        At(TokenKind.Identifier) && Current.Text is "checked" or "unchecked";

    /// <summary>
    /// Whether this is <c>closure R Name(...)</c> rather than something that
    /// merely begins with the word. Contextual, as <c>event</c> is.
    /// </summary>
    private bool AtClosureDeclaration()
    {
        if (!At(TokenKind.Identifier) || Current.Text != "closure") return false;

        var next = Peek(1).Kind;
        return next == TokenKind.Identifier || PrimitiveKeywords.Contains(next);
    }

    /// <summary>
    /// Whether this is <c>event T Name;</c> rather than something that merely
    /// begins with the word. Contextual on the same terms as <c>closure</c>:
    /// <c>int event = 3;</c> still declares a field called event, and the price
    /// is that a *type* called event could not be written here.
    /// </summary>
    private bool AtEventDeclaration()
    {
        if (!At(TokenKind.Identifier) || Current.Text != "event") return false;

        var next = Peek(1).Kind;
        return next == TokenKind.Identifier || PrimitiveKeywords.Contains(next);
    }

    /// <summary>
    /// <c>public event Notify Fired;</c>
    ///
    /// One type and one name. There is no <c>{ add; remove; }</c> form: the two
    /// methods an event lowers to are always the generated ones, because what
    /// they do -- copy the list, add or drop one -- is the whole of what an
    /// event is, and a hand-written pair would only be a way to get it wrong.
    /// </summary>
    private Declaration ParseEventDeclaration(
        int start, Modifiers modifiers, IReadOnlyList<AttributeSyntax> attributes)
    {
        Advance();

        var type = ParseType();
        string name = ExpectIdentifier();

        // `= handler` on an event would be an assignment, which is the thing an
        // event exists to refuse. Said here rather than at the binder, because
        // the parser is where the reader is still looking at the '='.
        if (At(TokenKind.Equals))
            _diagnostics.Error("SL0547", SpanFrom(start),
                $"'{name}' is an event, so it cannot be given a value: an event is the " +
                "subscribers it has, and it starts with none. Subscribe with '+='");

        Expect(TokenKind.Semicolon);
        return new EventDeclSyntax(SpanFrom(start), modifiers, type, name, attributes);
    }

    /// <summary>
    /// Whether what follows the modifiers is an operator rather than a member.
    ///
    /// The return type comes first and may be several tokens long --
    /// <c>List&lt;int&gt;</c>, <c>int</c>, a qualified name -- so this looks
    /// ahead for <c>operator</c> before the parameter list rather than trying
    /// to parse a type and back out.
    /// </summary>
    private bool AtOperatorDeclaration()
    {
        for (int at = 0; at < 16; at++)
        {
            var kind = Peek(at).Kind;
            if (kind == TokenKind.OperatorKeyword) return true;
            if (kind is TokenKind.Equals or TokenKind.Semicolon or TokenKind.OpenParen
                or TokenKind.OpenBrace or TokenKind.EndOfFile) return false;
        }
        return false;
    }

    /// <summary>
    /// <c>public static Money operator +(Money left, Money right)</c>.
    ///
    /// C#'s shape: inside the type it belongs to, static, with every operand
    /// written out. The last part is what makes <c>2 * money</c> expressible --
    /// an operator whose left operand is not the declaring type has no
    /// receiver to hang off, and would be unwritable as a method.
    ///
    /// It becomes an ordinary function named <c>op_Add</c> and so on, which is
    /// the same lowering C# uses. Nothing can call that name: it is registered
    /// among the type's operators rather than its methods.
    /// </summary>
    private Declaration ParseOperatorDeclaration(int start, Modifiers modifiers)
    {
        // `static implicit operator Money(long cents)`. The two words are
        // contextual, as `checked` and `closure` are: neither is reserved, and
        // `operator` straight after one is what settles it.
        if (At(TokenKind.Identifier) && Current.Text is "implicit" or "explicit" &&
            Peek(1).Kind == TokenKind.OperatorKeyword)
            return ParseConversionDeclaration(start, modifiers);

        var returnType = ParseType();
        Expect(TokenKind.OperatorKeyword);

        var token = Current;
        string? name = OperatorNames.For(token.Kind);

        if (name is null)
        {
            _diagnostics.Error("SL0558", token.Span,
                $"'{token.Text}' cannot be overloaded. The operators that can are " +
                OperatorNames.List);
            name = "op_Error";
        }

        Advance();

        var parameters = ParseParameterList(out _);
        var body = At(TokenKind.OpenBrace) ? ParseBlock() : null;

        if (body is null)
        {
            Expect(TokenKind.Semicolon);
            _diagnostics.Error("SL0559", SpanFrom(start), "an operator needs a body");
        }

        return new FunctionDeclSyntax(
            SpanFrom(start), modifiers, LinkageKind.Stainless, returnType, name,
            [], [], parameters, IsVariadic: false, body)
        { IsOperator = true, OperatorToken = token.Kind };
    }

    /// <summary>
    /// <c>public static implicit operator Money(long cents)</c>.
    ///
    /// The target type stands where an operator's symbol does, because that is
    /// what this operator is named: a conversion from its parameter to it. It
    /// becomes an ordinary function -- <c>op_ToMoney</c> -- and nothing can
    /// call that name, on the same terms as every other operator.
    /// </summary>
    private Declaration ParseConversionDeclaration(int start, Modifiers modifiers)
    {
        bool isImplicit = Advance().Text == "implicit";
        Expect(TokenKind.OperatorKeyword);

        var targetStart = _pos;
        var target = ParseType();
        var parameters = ParseParameterList(out bool variadic);
        var body = At(TokenKind.OpenBrace) ? ParseBlock() : null;

        if (variadic)
            _diagnostics.Error("SL0615", SpanFrom(start),
                "a conversion takes exactly the value it converts, so it cannot be variadic");

        if (body is null)
        {
            Expect(TokenKind.Semicolon);
            _diagnostics.Error("SL0559", SpanFrom(start), "an operator needs a body");
        }

        return new FunctionDeclSyntax(
            SpanFrom(start), modifiers, LinkageKind.Stainless, target,
            ConversionName(target, SpanFrom(targetStart)), [], [], parameters,
            IsVariadic: false, body)
        {
            IsOperator = true,
            IsConversion = true,
            IsImplicitConversion = isImplicit,
        };
    }

    /// <summary>
    /// The lowered name of a conversion to <paramref name="target"/>.
    ///
    /// It has to carry the target, because the parameter list does not: a type
    /// may convert to two things from the same one, and two functions whose
    /// name and parameters both match would be one symbol at the linker.
    /// </summary>
    private string ConversionName(TypeSyntax target, SourceSpan span) =>
        "op_To" + Binding.Mangler.SymbolSafe(
            span.File.Text[span.Start..span.End].Trim());

    /// <summary>
    /// <c>static readonly T Name = value;</c>, or <c>static T Name(...)</c>.
    ///
    /// The word means the same thing in both: belonging to the enclosing scope
    /// rather than to an instance. Which one is being written is decided by
    /// <c>readonly</c>, because storage must have it and a method cannot.
    /// </summary>
    private Declaration ParseStaticDeclaration(
        int start, Modifiers modifiers, string? enclosingType)
    {
        // `static Name() { }` inside `class Name`: the type's own initializer.
        // It has no return type, which is what tells it from a method.
        if (enclosingType is not null &&
            At(TokenKind.Identifier) && Current.Text == enclosingType &&
            Peek(1).Kind == TokenKind.OpenParen && Peek(2).Kind == TokenKind.CloseParen)
        {
            Advance();
            Advance();
            Advance();
            return new StaticConstructorDeclSyntax(SpanFrom(start), enclosingType, ParseBlock());
        }

        bool isReadonly = Match(TokenKind.ReadonlyKeyword);

        // `static T Name(...)` is a method; `static T Name = v;` is storage.
        // Only a parameter list tells them apart, and the type in front of the
        // name may be several tokens long, so the member parser decides.
        var member = ParseFunctionOrField(start, modifiers, LinkageKind.Stainless);

        if (member is FunctionDeclSyntax function)
        {
            if (isReadonly)
                _diagnostics.Error("SL0376", SpanFrom(start),
                    $"'{function.Name}' is a method, and 'readonly' is about storage");
            return member;
        }

        // A property is the third thing, and its accessors carry the word for
        // it: what a static property is, is two static methods.
        if (member is PropertyDeclSyntax) return member;

        if (member is not FieldDeclSyntax field)
        {
            _diagnostics.Error("SL0376", SpanFrom(start),
                $"'static' cannot be written on this");
            return member;
        }

        if (field.Initializer is null)
        {
            _diagnostics.Error("SL0376", field.Span,
                $"'{field.Name}' is a static, so it needs a value: the initializers run in " +
                "dependency order before 'Main', and there is no later moment at which one " +
                "could be given a first value");

            return new StaticDeclSyntax(
                SpanFrom(start), modifiers, field.Type, field.Name,
                new LiteralSyntax(field.Span, TokenKind.IntLiteral, 0L), isReadonly);
        }

        return new StaticDeclSyntax(
            SpanFrom(start), modifiers, field.Type, field.Name, field.Initializer, isReadonly);
    }

    private Declaration ParseDestructor(int start, string enclosingType)
    {
        Expect(TokenKind.Tilde);
        string name = ExpectIdentifier();
        if (name != enclosingType && name != "?")
            _diagnostics.Error("SL0104", SpanFrom(start),
                $"destructor name '{name}' does not match enclosing type '{enclosingType}'");
        Expect(TokenKind.OpenParen);
        Expect(TokenKind.CloseParen);
        var body = ParseBlock();
        return new DestructorDeclSyntax(SpanFrom(start), enclosingType, body);
    }

    private Declaration ParseGlobalConst(int start, Modifiers modifiers)
    {
        // `const int Limit = 64;` or `const Limit = 64;`
        TypeSyntax? type = null;
        if (!(At(TokenKind.Identifier) && Peek(1).Kind == TokenKind.Equals))
            type = ParseType();
        string name = ExpectIdentifier();
        Expect(TokenKind.Equals);
        var value = ParseExpression();
        Expect(TokenKind.Semicolon);
        return new GlobalConstDeclSyntax(SpanFrom(start), modifiers, type, name, value);
    }

    /// <summary>
    /// Both start `Type Name`; a following '(' makes it a function, otherwise
    /// it is a field. This is the C#/C++ shape, minus any header ambiguity.
    /// </summary>
    private Declaration ParseFunctionOrField(
        int start, Modifiers modifiers, LinkageKind linkage,
        IReadOnlyList<AttributeSyntax>? attributes = null)
    {
        var returnType = ParseType();

        // `T this[...]` is an indexer: a property whose accessors take
        // arguments. It is spelled with `this` because that is what is being
        // indexed, and because no other name could avoid colliding with a
        // member somebody wanted to call `Item`.
        if (At(TokenKind.ThisKeyword) && Peek(1).Kind == TokenKind.OpenBracket)
            return ParseIndexer(start, modifiers, returnType, attributes ?? []);

        string name = ExpectIdentifier();

        // `int geometry::Area(int, int)`. Only a C++ declaration may be
        // qualified, because only C++ has a namespace to name.
        var enclosing = new List<string>();
        while (linkage.IsCpp() && At(TokenKind.Colon) && Peek(1).Kind == TokenKind.Colon)
        {
            Advance();
            Advance();
            enclosing.Add(name);
            name = ExpectIdentifier();
        }

        // `T Max<T>(T a, T b)`. Only a function may be generic, so the list is
        // accepted here and rejected below if no parameter list follows.
        var typeParameters = At(TokenKind.Less) ? ParseTypeParameterList() : [];

        if (At(TokenKind.OpenParen))
        {
            var parameters = ParseParameterList(out bool isVariadic);
            var constraints = ParseWhereClauses();

            BlockSyntax? body = null;
            if (At(TokenKind.OpenBrace)) body = ParseBlock();
            else Expect(TokenKind.Semicolon);

            if (constraints.Count > 0 && typeParameters.Count == 0)
                _diagnostics.Error("SL0331", SpanFrom(start),
                    $"'{name}' is not generic, so it cannot have a 'where' clause");

            if (linkage.IsImport() && body is not null)
            {
                string how = linkage == LinkageKind.ExternC ? "C" : "C++";
                _diagnostics.Error("SL0105", SpanFrom(start),
                    $"'extern \"{how}\"' declares an external function, so '{name}' must not " +
                    $"have a body; use 'export \"{how}\"' to define one");
            }

            // Calling a C variadic is fine; being one is not. Nothing in the
            // language can read the extra arguments -- there is no 'va_list' --
            // so the definition would ignore them, while the header written for
            // it promises the variadic convention and a caller obeying that
            // leaves its floating-point arguments where the callee never looks.
            // Refusing the declaration is the only honest answer available.
            if (isVariadic && !linkage.IsImport())
                _diagnostics.Error("SL0493", SpanFrom(start),
                    $"'{name}' cannot be variadic; '...' may only be written on an " +
                    "'extern \"C\"' declaration, because there is no 'va_list' to read " +
                    "the extra arguments with. Take an array, a slice, or a count and a pointer");

            return new FunctionDeclSyntax(
                SpanFrom(start), modifiers, linkage, returnType, name, typeParameters,
                constraints, parameters, isVariadic, body) { Namespace = enclosing };
        }

        // `Type Name {` and `Type Name =>` are the two ways a property starts.
        // Neither can be anything else here, because a field ends at '=' or ';'.
        if (At(TokenKind.OpenBrace) || At(TokenKind.EqualsGreater))
        {
            if (typeParameters.Count > 0)
                _diagnostics.Error("SL0320", SpanFrom(start),
                    $"'{name}' is a property and cannot have type parameters");

            return ParseProperty(start, modifiers, returnType, name, attributes ?? []);
        }

        if (typeParameters.Count > 0)
            _diagnostics.Error("SL0320", SpanFrom(start),
                $"'{name}' is a field and cannot have type parameters");

        // `int flags : 3;` — a field that is some of the bits of one. Nothing
        // else can follow a field's name with a colon, so no lookahead is needed.
        ExpressionSyntax? bits = Match(TokenKind.Colon) ? ParseExpression() : null;

        ExpressionSyntax? initializer = Match(TokenKind.Equals) ? ParseExpression() : null;
        Expect(TokenKind.Semicolon);
        return new FieldDeclSyntax(
            SpanFrom(start), modifiers, returnType, name, initializer, attributes ?? [])
        {
            BitWidth = bits,
            Linkage = linkage,
        };
    }

    /// <summary>
    /// <c>public T this[nuint i] { get; set; }</c>.
    ///
    /// A property that takes arguments, and lowered like one: to
    /// <c>get_Item(i)</c> and <c>set_Item(i, value)</c>, which is C#'s
    /// spelling of the same idea. Nothing can call those names -- they are the
    /// lowering, reached by writing <c>a[i]</c>.
    ///
    /// There is no automatic form. <c>{ get; set; }</c> on a property makes
    /// the compiler find storage for it, and there is nothing to find here:
    /// what an index means is the whole of what an indexer is for, so both
    /// accessors are written.
    /// </summary>
    private Declaration ParseIndexer(
        int start, Modifiers modifiers, TypeSyntax returnType,
        IReadOnlyList<AttributeSyntax> attributes)
    {
        Expect(TokenKind.ThisKeyword);
        Expect(TokenKind.OpenBracket);

        var parameters = new List<ParameterSyntax>();
        while (!At(TokenKind.CloseBracket) && !At(TokenKind.EndOfFile))
        {
            int at = _pos;
            var type = ParseType();
            string name = ExpectIdentifier();
            parameters.Add(new ParameterSyntax(SpanFrom(at), type, name));

            if (!Match(TokenKind.Comma)) break;
        }

        Expect(TokenKind.CloseBracket);

        if (parameters.Count == 0)
            _diagnostics.Error("SL0568", SpanFrom(start),
                "an indexer takes at least one index; `this[]` indexes by nothing");

        var accessors = ParseAccessorList("this[]");

        return new PropertyDeclSyntax(
            SpanFrom(start), modifiers, returnType, "Item", accessors, attributes)
        { Indices = parameters };
    }

    /// <summary>
    /// <c>{ Name = value, ... }</c> or <c>{ value, ... }</c> after a
    /// construction.
    ///
    /// One list either way; the binder decides which kind it is from whether
    /// the entries are named, because that is also what decides whether the
    /// type has to have the members or an <c>Add</c>.
    /// </summary>
    private ObjectInitializerSyntax ParseObjectInitializer()
    {
        int start = _pos;
        Expect(TokenKind.OpenBrace);

        var entries = new List<InitializerEntrySyntax>();

        while (!At(TokenKind.CloseBrace) && !At(TokenKind.EndOfFile))
        {
            int at = _pos;

            // `Name = value`. Nothing else in an expression puts a bare name
            // in front of a single `=`, so one token of lookahead settles it.
            if (At(TokenKind.Identifier) && Peek(1).Kind == TokenKind.Equals)
            {
                var name = Advance();
                Advance();
                entries.Add(new InitializerEntrySyntax(
                    SpanFrom(at), name.Text, name.Span, ParseExpression()));
            }
            else
            {
                entries.Add(new InitializerEntrySyntax(
                    SpanFrom(at), null, SpanFrom(at), ParseExpression()));
            }

            if (!Match(TokenKind.Comma)) break;
        }

        Expect(TokenKind.CloseBrace);
        return new ObjectInitializerSyntax(SpanFrom(start), entries);
    }

    /// <summary>
    /// The accessor list of a property, or the single expression that stands in
    /// for one: <c>int Area =&gt; width * height;</c> is <c>{ get { return ...; } }</c>.
    /// </summary>
    private Declaration ParseProperty(
        int start, Modifiers modifiers, TypeSyntax type, string name,
        IReadOnlyList<AttributeSyntax> attributes)
    {
        // `T Name => expression;` is a getter and nothing else. An indexer has
        // no such form, which is why this is here and not in the shared part.
        if (Match(TokenKind.EqualsGreater))
        {
            var arrow = new List<AccessorSyntax>
            {
                new(SpanFrom(start), Modifiers.None, IsGetter: true, ParseArrowBody(isGetter: true)),
            };
            Expect(TokenKind.Semicolon);
            return new PropertyDeclSyntax(SpanFrom(start), modifiers, type, name, arrow, attributes);
        }

        var accessors = ParseAccessorList(name);

        // `public int Width { get; set; } = 80;`. The storage an automatic
        // property owns is a field like any other, so it takes a value the
        // same way one does -- and the binder refuses it where there is no
        // storage to give a value to.
        var initializer = Match(TokenKind.Equals) ? ParseExpression() : null;
        if (initializer is not null) Expect(TokenKind.Semicolon);

        return new PropertyDeclSyntax(
            SpanFrom(start), modifiers, type, name, accessors, attributes)
        {
            Initializer = initializer,
        };
    }

    /// <summary>
    /// <c>{ get; set; }</c> and its written-out forms, shared by a property
    /// and an indexer -- which differ in what precedes this and nothing else.
    /// </summary>
    private List<AccessorSyntax> ParseAccessorList(string name)
    {
        var accessors = new List<AccessorSyntax>();
        Expect(TokenKind.OpenBrace);

        while (!At(TokenKind.CloseBrace) && !At(TokenKind.EndOfFile))
        {
            int before = _pos;
            int accessorStart = _pos;
            var accessorModifiers = ParseModifiers();

            // 'get' and 'set' stay ordinary identifiers everywhere else in the
            // language, so they are recognised by text rather than reserved.
            if (!(At(TokenKind.Identifier) && Current.Text is "get" or "set"))
            {
                _diagnostics.Error("SL0385", Current.Span,
                    $"expected 'get' or 'set' in property '{name}'");
                if (_pos == before) Advance();
                continue;
            }

            bool isGetter = Advance().Text == "get";

            // A block body stands on its own; a bare accessor and an arrow body
            // are both statements and end at a semicolon.
            if (At(TokenKind.OpenBrace))
            {
                accessors.Add(new AccessorSyntax(
                    SpanFrom(accessorStart), accessorModifiers, isGetter, ParseBlock()));
                continue;
            }

            var body = Match(TokenKind.EqualsGreater) ? ParseArrowBody(isGetter) : null;
            Expect(TokenKind.Semicolon);

            accessors.Add(new AccessorSyntax(
                SpanFrom(accessorStart), accessorModifiers, isGetter, body));
        }

        Expect(TokenKind.CloseBrace);
        return accessors;
    }

    /// <summary>
    /// The body behind <c>=&gt;</c>: an expression a getter returns, or one a
    /// setter simply evaluates.
    /// </summary>
    private BlockSyntax ParseArrowBody(bool isGetter)
    {
        int start = _pos;
        var expression = ParseExpression();
        var span = SpanFrom(start);

        StatementSyntax statement = isGetter
            ? new ReturnSyntax(span, expression)
            : new ExpressionStatementSyntax(span, expression);

        return new BlockSyntax(span, [statement]);
    }

    private List<ParameterSyntax> ParseParameterList(out bool isVariadic)
    {
        isVariadic = false;
        var parameters = new List<ParameterSyntax>();
        Expect(TokenKind.OpenParen);

        while (!At(TokenKind.CloseParen) && !At(TokenKind.EndOfFile))
        {
            // A C-style '...' arrives as three Dot tokens.
            if (At(TokenKind.Dot) && Peek(1).Kind == TokenKind.Dot && Peek(2).Kind == TokenKind.Dot)
            {
                Advance(); Advance(); Advance();
                isVariadic = true;
                break;
            }

            int paramStart = _pos;

            var mode = ParameterMode.Value;
            if (Match(TokenKind.RefKeyword)) mode = ParameterMode.Ref;
            else if (Match(TokenKind.InKeyword)) mode = ParameterMode.In;
            else if (AtOutModifier()) { Advance(); mode = ParameterMode.Out; }

            var type = ParseType();
            string name = ExpectIdentifier();

            // `int width = 80`. Parsed wherever a parameter list is, so that a
            // default written where one cannot mean anything -- a variant's
            // case, a delegate -- is refused with a sentence rather than with
            // "expected ')'".
            var fallback = Match(TokenKind.Equals) ? ParseExpression() : null;

            parameters.Add(new ParameterSyntax(SpanFrom(paramStart), type, name, mode, fallback));

            if (!Match(TokenKind.Comma)) break;
        }

        Expect(TokenKind.CloseParen);
        return parameters;
    }

    // ------------------------------------------------------------ types

    private static readonly TokenKind[] PrimitiveKeywords =
    [
        TokenKind.VoidKeyword, TokenKind.BoolKeyword, TokenKind.CharKeyword,
        TokenKind.Char16Keyword, TokenKind.Char32Keyword,
        TokenKind.SByteKeyword, TokenKind.ShortKeyword, TokenKind.IntKeyword,
        TokenKind.LongKeyword, TokenKind.NIntKeyword,
        TokenKind.ByteKeyword, TokenKind.UShortKeyword, TokenKind.UIntKeyword,
        TokenKind.ULongKeyword, TokenKind.NUIntKeyword,
        TokenKind.FloatKeyword, TokenKind.DoubleKeyword,
    ];

    private bool AtTypeStart() =>
        AtAny(PrimitiveKeywords) || At(TokenKind.Identifier) || At(TokenKind.WeakKeyword) ||
        At(TokenKind.OpenParen);

    /// <summary>
    /// A type.
    ///
    /// <paramref name="allowFixedLength"/> is false only under <c>new</c>, where
    /// <c>new int[10]</c> has to stay "ten ints on the heap" rather than becoming
    /// the fixed-array type <c>int[10]</c>. Everywhere else a length in brackets
    /// is part of the type.
    /// </summary>
    private TypeSyntax ParseType(bool allowFixedLength = true)
    {
        int start = _pos;

        if (!Descend())
        {
            Advance();
            var span = SpanFrom(start);
            return new NamedTypeSyntax(span, new QualifiedName(span, ["?"]));
        }

        try { return ParseTypeCore(start, allowFixedLength); }
        finally { Ascend(); }
    }

    private TypeSyntax ParseTypeCore(int start, bool allowFixedLength)
    {
        if (Match(TokenKind.WeakKeyword))
        {
            var inner = ParseType(allowFixedLength);
            return new WeakTypeSyntax(SpanFrom(start), inner);
        }

        TypeSyntax type;
        if (At(TokenKind.OpenParen))
        {
            // `(int, String)`. One element is not a tuple, and a type in
            // parentheses is not something this language writes, so the comma
            // is required rather than merely expected.
            Advance();

            var elements = new List<TypeSyntax>();
            do { elements.Add(ParseType()); } while (Match(TokenKind.Comma));

            Expect(TokenKind.CloseParen);

            if (elements.Count < 2)
                _diagnostics.Error("SL0606", SpanFrom(start),
                    "a tuple type has at least two elements; one value in parentheses is " +
                    "that value");

            type = new TupleTypeSyntax(SpanFrom(start), elements);
        }
        else if (AtAny(PrimitiveKeywords))
        {
            var keyword = Advance().Kind;
            type = new PrimitiveTypeSyntax(SpanFrom(start), keyword);
        }
        else
        {
            var name = ParseQualifiedName();
            var arguments = ParseTypeArgumentList();
            type = new NamedTypeSyntax(SpanFrom(start), name, arguments);
        }

        while (true)
        {
            if (Match(TokenKind.Star)) { type = new PointerTypeSyntax(SpanFrom(start), type); continue; }
            if (Match(TokenKind.Question)) { type = new NullableTypeSyntax(SpanFrom(start), type); continue; }

            if (At(TokenKind.OpenBracket) && Peek(1).Kind == TokenKind.CloseBracket)
            {
                Advance();
                Advance();
                type = new ArrayTypeSyntax(SpanFrom(start), type);
                continue;
            }

            // `T[N]` is N of them, laid out here. Under `new` this is left
            // alone, so that `new int[10]` keeps its length for the caller.
            if (allowFixedLength && At(TokenKind.OpenBracket) &&
                Peek(1).Kind != TokenKind.CloseBracket && Peek(1).Kind != TokenKind.Colon)
            {
                Advance();
                var length = ParseExpression();
                Expect(TokenKind.CloseBracket);
                type = new FixedArrayTypeSyntax(SpanFrom(start), type, length);
                continue;
            }

            // `T[:]` is the slice of one. Nothing else can follow an open
            // bracket with a colon, so this needs no lookahead beyond it.
            if (At(TokenKind.OpenBracket) && Peek(1).Kind == TokenKind.Colon &&
                Peek(2).Kind == TokenKind.CloseBracket)
            {
                Advance();
                Advance();
                Advance();
                type = new SliceTypeSyntax(SpanFrom(start), type);
                continue;
            }

            break;
        }

        return type;
    }

    /// <summary>
    /// Parses <c>&lt;int, String&gt;</c> after a type name. In type position a
    /// '&lt;' can only begin type arguments, so no lookahead is needed here; in
    /// expression position the caller speculates instead.
    /// </summary>
    private List<TypeSyntax> ParseTypeArgumentList()
    {
        var arguments = new List<TypeSyntax>();
        if (!Match(TokenKind.Less)) return arguments;

        do { arguments.Add(ParseType()); }
        while (Match(TokenKind.Comma));

        ExpectTypeArgumentEnd();
        return arguments;
    }

    /// <summary>
    /// Parses any number of <c>where T : Shape, Named</c> clauses. They follow
    /// the base list and precede the body, as in C#.
    /// </summary>
    private List<WhereClauseSyntax> ParseWhereClauses()
    {
        var clauses = new List<WhereClauseSyntax>();

        while (At(TokenKind.WhereKeyword))
        {
            int start = _pos;
            Advance();

            string parameter = ExpectIdentifier();
            Expect(TokenKind.Colon);

            var constraints = new List<ConstraintSyntax>();
            do { constraints.Add(ParseConstraint()); }
            while (Match(TokenKind.Comma));

            CheckConstraintOrder(constraints);
            clauses.Add(new WhereClauseSyntax(SpanFrom(start), parameter, constraints));
        }

        return clauses;
    }

    /// <summary>
    /// One constraint. Three of the four are keywords, which is why this is not
    /// simply <see cref="ParseType"/>.
    /// </summary>
    private ConstraintSyntax ParseConstraint()
    {
        int start = _pos;

        if (Match(TokenKind.ClassKeyword))
            return new ConstraintSyntax(SpanFrom(start), ConstraintKind.Class, null);

        if (Match(TokenKind.StructKeyword))
            return new ConstraintSyntax(SpanFrom(start), ConstraintKind.Struct, null);

        if (Match(TokenKind.ThreadsafeKeyword))
            return new ConstraintSyntax(SpanFrom(start), ConstraintKind.Threadsafe, null);

        // `new()`, with the parentheses C# writes and no parameters in them:
        // there is nothing else a constructor constraint could ask for, since
        // a body that wanted arguments would have to know their types.
        if (Match(TokenKind.NewKeyword))
        {
            Expect(TokenKind.OpenParen);
            if (!At(TokenKind.CloseParen))
                _diagnostics.Error("SL0579", SpanFrom(start),
                    "a 'new()' constraint takes no parameters; it says the type can be made " +
                    "with none, which is the only promise a template could rely on");
            while (!At(TokenKind.CloseParen) && !At(TokenKind.EndOfFile)) Advance();
            Expect(TokenKind.CloseParen);
            return new ConstraintSyntax(SpanFrom(start), ConstraintKind.New, null);
        }

        return new ConstraintSyntax(SpanFrom(start), ConstraintKind.Type, ParseType());
    }

    /// <summary>
    /// C#'s ordering rule, and C#'s reason for it: <c>class</c> or
    /// <c>struct</c> says what kind of type this is and so comes first, and
    /// <c>new()</c> is the last thing asked of it. The order carries no
    /// meaning, but a fixed one means every <c>where</c> reads the same way.
    /// </summary>
    private void CheckConstraintOrder(List<ConstraintSyntax> constraints)
    {
        // Reported first, because `class, struct` is one mistake and saying
        // the second word is out of order as well would bury it.
        bool bothKinds =
            constraints.Count(c => c.Kind is ConstraintKind.Class or ConstraintKind.Struct) > 1;

        if (bothKinds)
            _diagnostics.Error("SL0581", constraints[0].Span,
                "a type parameter is a reference type or a value type, not both");

        for (int i = 0; i < constraints.Count; i++)
        {
            var constraint = constraints[i];

            if (!bothKinds &&
                constraint.Kind is ConstraintKind.Class or ConstraintKind.Struct && i != 0)
                _diagnostics.Error("SL0580", constraint.Span,
                    $"'{(constraint.Kind == ConstraintKind.Class ? "class" : "struct")}' says " +
                    "what kind of type this is, so it comes first in the clause");

            if (constraint.Kind == ConstraintKind.New && i != constraints.Count - 1)
                _diagnostics.Error("SL0580", constraint.Span,
                    "'new()' is the last thing asked of a type parameter, so it comes last " +
                    "in the clause");
        }

        if (constraints.Count > 1 &&
            constraints[0].Kind == ConstraintKind.Struct &&
            constraints.Any(c => c.Kind == ConstraintKind.New))
            _diagnostics.Error("SL0581", constraints[0].Span,
                "'struct' and 'new()' contradict each other: 'new' allocates, and only a class " +
                "is allocated. A struct is declared where it is used");
    }

    /// <summary>
    /// Consumes the <c>&gt;</c> that closes a type argument list, splitting a
    /// <c>&gt;&gt;</c> in half when it finds one.
    ///
    /// The lexer cannot tell the two apart: in <c>List&lt;Box&lt;int&gt;&gt;</c>
    /// the last two characters are one shift operator by every rule it knows.
    /// Only the parser knows a type argument list is open, so it is the parser
    /// that puts the second <c>&gt;</c> back.
    /// </summary>
    private void ExpectTypeArgumentEnd()
    {
        if (!At(TokenKind.GreaterGreater))
        {
            Expect(TokenKind.Greater);
            return;
        }

        var shift = _tokens[_pos];
        var span = shift.Span;

        // Put back the half this list did not need, so the enclosing one closes.
        _tokens[_pos] = new Token(
            TokenKind.Greater,
            new SourceSpan(span.File, span.Start + 1, span.End),
            ">");
    }

    /// <summary>Parses <c>&lt;T, U&gt;</c> in a declaration.</summary>
    private List<string> ParseTypeParameterList()
    {
        var parameters = new List<string>();
        if (!Match(TokenKind.Less)) return parameters;

        do { parameters.Add(ExpectIdentifier()); }
        while (Match(TokenKind.Comma));

        ExpectTypeArgumentEnd();
        return parameters;
    }

    // ------------------------------------------------------------ statements

    private BlockSyntax ParseBlock()
    {
        int start = _pos;
        Expect(TokenKind.OpenBrace);
        var statements = new List<StatementSyntax>();
        while (!At(TokenKind.CloseBrace) && !At(TokenKind.EndOfFile))
        {
            int before = _pos;
            statements.Add(ParseStatement());
            if (_pos == before) Advance();
        }
        Expect(TokenKind.CloseBrace);
        return new BlockSyntax(SpanFrom(start), statements);
    }

    private StatementSyntax ParseStatement()
    {
        int start = _pos;

        if (!Descend()) { Advance(); return new ExpressionStatementSyntax(
            SpanFrom(start), Unreadable(start)); }

        try { return ParseStatementCore(start); }
        finally { Ascend(); }
    }

    private StatementSyntax ParseStatementCore(int start)
    {
        switch (Current.Kind)
        {
            case TokenKind.OpenBrace:
                return ParseBlock();

            case TokenKind.IfKeyword:
            {
                Advance();
                Expect(TokenKind.OpenParen);
                var condition = ParseExpression();
                Expect(TokenKind.CloseParen);
                var then = ParseStatement();
                StatementSyntax? otherwise = Match(TokenKind.ElseKeyword) ? ParseStatement() : null;
                return new IfSyntax(SpanFrom(start), condition, then, otherwise);
            }

            case TokenKind.WhileKeyword:
            {
                Advance();
                Expect(TokenKind.OpenParen);
                var condition = ParseExpression();
                Expect(TokenKind.CloseParen);
                var body = ParseStatement();
                return new WhileSyntax(SpanFrom(start), condition, body);
            }

            case TokenKind.DoKeyword:
            {
                Advance();
                var body = ParseStatement();
                Expect(TokenKind.WhileKeyword);
                Expect(TokenKind.OpenParen);
                var condition = ParseExpression();
                Expect(TokenKind.CloseParen);

                // The semicolon is C's, and it is what stops `do { } while (c)`
                // from reading as a `do` followed by an ordinary `while` loop.
                Expect(TokenKind.Semicolon);
                return new DoWhileSyntax(SpanFrom(start), body, condition);
            }

            case TokenKind.GotoKeyword:
            {
                Advance();
                var label = Current;
                string name = ExpectIdentifier();
                Expect(TokenKind.Semicolon);
                return new GotoSyntax(SpanFrom(start), name, label.Span);
            }

            case TokenKind.ForKeyword:
            {
                Advance();
                Expect(TokenKind.OpenParen);
                StatementSyntax? initializer = At(TokenKind.Semicolon)
                    ? null
                    : ParseSimpleStatement(requireSemicolon: true);
                if (initializer is null) Expect(TokenKind.Semicolon);

                ExpressionSyntax? condition = At(TokenKind.Semicolon) ? null : ParseExpression();
                Expect(TokenKind.Semicolon);
                ExpressionSyntax? step = At(TokenKind.CloseParen) ? null : ParseExpression();
                Expect(TokenKind.CloseParen);

                var body = ParseStatement();
                return new ForSyntax(SpanFrom(start), initializer, condition, step, body);
            }

            case TokenKind.ParallelKeyword:
            {
                Advance();

                // `parallel for (...)` splits a counted loop; `parallel { }` is
                // a scope that `spawn` queues work on.
                if (At(TokenKind.ForKeyword))
                {
                    Advance();
                    Expect(TokenKind.OpenParen);

                    var loopInit = ParseSimpleStatement(requireSemicolon: true);
                    var loopCondition = ParseExpression();
                    Expect(TokenKind.Semicolon);
                    var loopStep = ParseExpression();
                    Expect(TokenKind.CloseParen);

                    return new ParallelForSyntax(
                        SpanFrom(start), loopInit, loopCondition, loopStep, ParseStatement());
                }

                return new ParallelSyntax(SpanFrom(start), ParseBlock());
            }

            case TokenKind.SpawnKeyword:
            {
                Advance();

                var spawned = ParseExpression();
                Expect(TokenKind.Semicolon);

                // `spawn x = f()` parses as an assignment; split it back apart so
                // the call and the place its result lands stay separate.
                if (spawned is AssignmentSyntax { Operator: TokenKind.Equals } assignment)
                    return new SpawnSyntax(SpanFrom(start), assignment.Target, assignment.Value);

                return new SpawnSyntax(SpanFrom(start), null, spawned);
            }

            case TokenKind.ForeachKeyword:
            {
                Advance();
                Expect(TokenKind.OpenParen);

                // `foreach (var x in xs)` infers; anything else names a type.
                TypeSyntax? elementType = null;
                if (At(TokenKind.VarKeyword)) Advance();
                else elementType = ParseType();

                string name = ExpectIdentifier();
                Expect(TokenKind.InKeyword);
                var collection = ParseExpression();
                Expect(TokenKind.CloseParen);

                var loopBody = ParseStatement();
                return new ForEachSyntax(SpanFrom(start), elementType, name, collection, loopBody);
            }

            case TokenKind.SwitchKeyword:
                return ParseSwitch(start);

            case TokenKind.ReturnKeyword:
            {
                Advance();
                ExpressionSyntax? value = At(TokenKind.Semicolon) ? null : ParseExpression();
                Expect(TokenKind.Semicolon);
                return new ReturnSyntax(SpanFrom(start), value);
            }

            case TokenKind.BreakKeyword:
                Advance();
                Expect(TokenKind.Semicolon);
                return new BreakSyntax(SpanFrom(start));

            case TokenKind.ContinueKeyword:
                Advance();
                Expect(TokenKind.Semicolon);
                return new ContinueSyntax(SpanFrom(start));

            case TokenKind.Semicolon:
                Advance();
                return new BlockSyntax(SpanFrom(start), []);

            case TokenKind.VarKeyword when Peek(1).Kind == TokenKind.OpenParen:
            {
                // `var (a, b) = ...`. `var` is otherwise followed by a name, so
                // the parenthesis settles it with no speculation.
                Advance();
                Advance();

                var names = new List<string>();
                var spans = new List<SourceSpan>();

                do
                {
                    var name = Current;
                    names.Add(ExpectIdentifier());
                    spans.Add(name.Span);
                }
                while (Match(TokenKind.Comma));

                Expect(TokenKind.CloseParen);
                Expect(TokenKind.Equals);

                var value = ParseExpression();
                Expect(TokenKind.Semicolon);
                return new DeconstructSyntax(SpanFrom(start), names, spans, value);
            }

            default:
                // `checked { ... }`. Contextual, for the reason `closure` is:
                // the word is a good enough name that a test in this very
                // repository had a parameter called it. `checked(e)` is an
                // expression and is recognised further down.
                if (AtCheckedWord() && Peek(1).Kind == TokenKind.OpenBrace)
                {
                    bool wanted = Current.Text == "checked";
                    Advance();
                    return new CheckedBlockSyntax(SpanFrom(start), ParseBlock(), wanted);
                }

                // `name:` is a label. Nothing else in the grammar puts a colon
                // straight after a leading identifier -- a local declaration is
                // two names, a call is a paren, and a ternary's colon has an
                // expression and a '?' before it -- so one token of lookahead
                // settles it.
                if (At(TokenKind.Identifier) && Peek(1).Kind == TokenKind.Colon)
                {
                    string name = Advance().Text;
                    Advance();
                    return new LabelSyntax(SpanFrom(start), name);
                }

                return ParseSimpleStatement(requireSemicolon: true);
        }
    }

    /// <summary>A local declaration or an expression statement.</summary>
    /// <summary>
    /// <c>switch (value) { case ...: ... }</c>. Labels stack: every <c>case</c>
    /// and <c>default</c> written before the first statement belongs to the
    /// same section, which is how <c>case 1: case 2:</c> shares one body.
    /// </summary>
    private StatementSyntax ParseSwitch(int start)
    {
        Expect(TokenKind.SwitchKeyword);
        Expect(TokenKind.OpenParen);
        var value = ParseExpression();
        Expect(TokenKind.CloseParen);
        Expect(TokenKind.OpenBrace);

        var sections = new List<SwitchSectionSyntax>();

        while (!At(TokenKind.CloseBrace) && !At(TokenKind.EndOfFile))
        {
            int sectionStart = _pos;
            var labels = new List<ExpressionSyntax>();
            var patterns = new List<PatternSyntax>();
            var guards = new List<ExpressionSyntax?>();
            var bindings = new List<CaseBindingSyntax>();
            bool hasDefault = false;

            while (AtAny(TokenKind.CaseKeyword, TokenKind.DefaultKeyword))
            {
                if (Match(TokenKind.DefaultKeyword))
                {
                    hasDefault = true;
                }
                else
                {
                    int labelStart = _pos;
                    Advance();

                    var pattern = ParsePattern();
                    patterns.Add(pattern);
                    guards.Add(AtWhenWord() ? ParseGuard() : null);

                    // A plain constant is kept as an expression as well, because
                    // a switch all of whose labels are constants becomes one
                    // LLVM `switch` instruction -- and that is most switches.
                    if (pattern is ConstantPatternSyntax constant && guards[^1] is null)
                        labels.Add(constant.Value);

                    // `case Circle c:` names a variant's case and binds its
                    // payload. It is a type pattern here, and the binder is
                    // where a case and a class are told apart -- but the older
                    // shape is kept for a variant, whose section machinery is
                    // written against it.
                    if (pattern is TypePatternSyntax
                        {
                            Binding: not null,
                            Type: NamedTypeSyntax { Name.Parts: [var only], TypeArguments.Count: 0 },
                        } named && guards[^1] is null)
                        bindings.Add(new CaseBindingSyntax(
                            SpanFrom(labelStart), only, named.Binding!));
                }

                Expect(TokenKind.Colon);
            }

            if (patterns.Count == 0 && !hasDefault)
            {
                _diagnostics.Error("SL0402", Current.Span,
                    "expected 'case' or 'default'; every statement in a switch belongs to a " +
                    "labelled section");
                Advance();
                continue;
            }

            var statements = new List<StatementSyntax>();
            while (!AtAny(TokenKind.CaseKeyword, TokenKind.DefaultKeyword,
                          TokenKind.CloseBrace, TokenKind.EndOfFile))
            {
                int before = _pos;
                statements.Add(ParseStatement());
                if (_pos == before) Advance();
            }

            sections.Add(new SwitchSectionSyntax(
                SpanFrom(sectionStart), labels, hasDefault, statements)
            {
                Bindings = bindings,
                Patterns = patterns,
                Guards = guards,
            });
        }

        Expect(TokenKind.CloseBrace);
        return new SwitchSyntax(SpanFrom(start), value, sections);
    }

    /// <summary>
    /// <c>value switch { pattern =&gt; result, ... }</c>.
    ///
    /// The arms are separated by commas rather than closed by semicolons,
    /// because each one is an expression and not a statement -- which is the
    /// whole difference between this and the statement it is named after.
    /// </summary>
    private ExpressionSyntax ParseSwitchExpression(int start, ExpressionSyntax value)
    {
        Expect(TokenKind.SwitchKeyword);
        Expect(TokenKind.OpenBrace);

        var arms = new List<SwitchArmSyntax>();

        while (!At(TokenKind.CloseBrace) && !At(TokenKind.EndOfFile))
        {
            int at = _pos;
            var pattern = ParsePattern();
            var guard = AtWhenWord() ? ParseGuard() : null;

            Expect(TokenKind.EqualsGreater);
            arms.Add(new SwitchArmSyntax(SpanFrom(at), pattern, guard, ParseExpression()));

            if (!Match(TokenKind.Comma)) break;
        }

        Expect(TokenKind.CloseBrace);
        return new SwitchExpressionSyntax(SpanFrom(start), value, arms);
    }

    /// <summary>Whether the next word is a contextual <c>when</c>.</summary>
    private bool AtWhenWord() => At(TokenKind.Identifier) && Current.Text == "when";

    /// <summary>
    /// <c>when condition</c> after a pattern. The word is contextual, for the
    /// reason <c>checked</c> is: it is a good enough name that somebody's
    /// parameter is called it.
    /// </summary>
    private ExpressionSyntax ParseGuard()
    {
        Advance();
        return ParseExpression();
    }

    /// <summary>
    /// A pattern, with <c>or</c> loosest and <c>and</c> tighter, as in C#.
    ///
    /// Both words are contextual and both are read here rather than by the
    /// expression parser, because a pattern is not an expression: what
    /// <c>1 or 2</c> means is two questions about one value, and there is no
    /// value called <c>1 or 2</c>.
    /// </summary>
    private PatternSyntax ParsePattern()
    {
        int start = _pos;
        var left = ParsePatternAnd();

        while (At(TokenKind.Identifier) && Current.Text == "or")
        {
            Advance();
            left = new BinaryPatternSyntax(SpanFrom(start), left, IsOr: true, ParsePatternAnd());
        }

        return left;
    }

    private PatternSyntax ParsePatternAnd()
    {
        int start = _pos;
        var left = ParsePatternPrimary();

        while (At(TokenKind.Identifier) && Current.Text == "and")
        {
            Advance();
            left = new BinaryPatternSyntax(SpanFrom(start), left, IsOr: false, ParsePatternPrimary());
        }

        return left;
    }

    private PatternSyntax ParsePatternPrimary()
    {
        int start = _pos;

        if (At(TokenKind.Identifier) && Current.Text == "not")
        {
            Advance();
            return new NotPatternSyntax(SpanFrom(start), ParsePatternPrimary());
        }

        // `_` matches anything. It is an ordinary identifier to the lexer, and
        // a pattern is the one place it means this.
        if (At(TokenKind.Identifier) && Current.Text == "_" &&
            Peek(1).Kind is TokenKind.Colon or TokenKind.EqualsGreater or TokenKind.Comma)
        {
            Advance();
            return new DiscardPatternSyntax(SpanFrom(start));
        }

        // `> 5`, `<= 0`. One comparison against a constant, and the operator is
        // what says this is a pattern rather than a value.
        if (AtAny(TokenKind.Less, TokenKind.LessEquals, TokenKind.Greater, TokenKind.GreaterEquals))
        {
            var op = Advance().Kind;
            return new RelationalPatternSyntax(SpanFrom(start), op, ParsePatternConstant());
        }

        if (At(TokenKind.OpenParen))
        {
            Advance();
            var inner = ParsePattern();
            Expect(TokenKind.CloseParen);
            return inner;
        }

        // `Square s` and `Circle c`: a type and a name for what it found. Two
        // identifiers in a row is the whole of the test -- no expression starts
        // that way -- and a qualified type is allowed, so the lookahead walks
        // the dots first.
        if (At(TokenKind.Identifier) && AtTypeThenName())
        {
            var type = ParseType();
            var name = Current;
            string binding = ExpectIdentifier();
            return new TypePatternSyntax(SpanFrom(start), type, binding, name.Span);
        }

        // Everything else is a constant: a literal, a qualified name, a
        // negated number. A bare name may still turn out to name a variant's
        // case or a type, and the binder is where that is settled.
        return new ConstantPatternSyntax(SpanFrom(start), ParsePatternConstant());
    }

    /// <summary>
    /// The value side of a constant or relational pattern. Deliberately not a
    /// whole expression: <c>or</c> and <c>and</c> belong to the pattern, and a
    /// ternary's <c>:</c> would eat the label's own.
    /// </summary>
    private ExpressionSyntax ParsePatternConstant() => ParseBinary(TypeTestPrecedence);

    /// <summary>
    /// Whether what follows is a type and then a name, which is what separates
    /// <c>case Square s:</c> from <c>case Square:</c>.
    /// </summary>
    private bool AtTypeThenName()
    {
        int at = 0;

        // A qualified name: `Shapes.Square`.
        while (Peek(at).Kind == TokenKind.Identifier && Peek(at + 1).Kind == TokenKind.Dot)
            at += 2;

        if (Peek(at).Kind != TokenKind.Identifier) return false;
        at++;

        // Type arguments, as one balanced group.
        if (Peek(at).Kind == TokenKind.Less)
        {
            int depth = 0;

            while (true)
            {
                var kind = Peek(at).Kind;
                if (kind == TokenKind.EndOfFile) return false;
                if (kind == TokenKind.Less) depth++;
                else if (kind == TokenKind.Greater) { depth--; at++; if (depth == 0) break; continue; }
                else if (kind is TokenKind.Colon or TokenKind.EqualsGreater or TokenKind.Semicolon)
                    return false;
                at++;
            }
        }

        return Peek(at).Kind == TokenKind.Identifier && Peek(at).Text != "when" &&
               Peek(at).Text != "or" && Peek(at).Text != "and";
    }

    private StatementSyntax ParseSimpleStatement(bool requireSemicolon)
    {
        int start = _pos;

        if (At(TokenKind.VarKeyword) || At(TokenKind.ConstKeyword))
        {
            bool isConst = At(TokenKind.ConstKeyword);
            Advance();

            // `const int x = 1;` still names a type; `var x = 1;` never does.
            TypeSyntax? type = null;
            if (isConst && !(At(TokenKind.Identifier) && Peek(1).Kind == TokenKind.Equals))
                type = ParseType();

            string name = ExpectIdentifier();
            ExpressionSyntax? initializer = Match(TokenKind.Equals) ? ParseExpression() : null;
            if (requireSemicolon) Expect(TokenKind.Semicolon);
            return new LocalDeclSyntax(SpanFrom(start), type, name, initializer, isConst);
        }

        // `Type name ...` is a declaration; anything else is an expression.
        if (AtTypeStart() && Speculate(TryParseLocalDeclarationHead, out var head) && head is not null)
        {
            ExpressionSyntax? initializer = Match(TokenKind.Equals) ? ParseExpression() : null;
            if (requireSemicolon) Expect(TokenKind.Semicolon);
            return new LocalDeclSyntax(SpanFrom(start), head.Type, head.Name, initializer, IsConst: false);
        }

        var expression = ParseExpression();
        if (requireSemicolon) Expect(TokenKind.Semicolon);
        return new ExpressionStatementSyntax(SpanFrom(start), expression);
    }

    private sealed record LocalDeclHead(TypeSyntax Type, string Name);

    private LocalDeclHead? TryParseLocalDeclarationHead()
    {
        var type = ParseType();
        if (!At(TokenKind.Identifier)) return null;
        string name = Advance().Text;

        // Only `= expr`, `;` or (in a for-initializer) nothing may follow a declarator.
        if (!AtAny(TokenKind.Equals, TokenKind.Semicolon)) return null;
        return new LocalDeclHead(type, name);
    }

    // ------------------------------------------------------------ expressions

    /// <summary>Binary precedence; higher binds tighter. 0 means "not a binary operator".</summary>
    private static int BinaryPrecedence(TokenKind kind) => kind switch
    {
        TokenKind.Star or TokenKind.Slash or TokenKind.Percent => 10,
        TokenKind.Plus or TokenKind.Minus => 9,
        TokenKind.LessLess or TokenKind.GreaterGreater => 8,
        TokenKind.Less or TokenKind.LessEquals or
        TokenKind.Greater or TokenKind.GreaterEquals => 7,
        TokenKind.EqualsEquals or TokenKind.BangEquals => 6,
        TokenKind.Amp => 5,
        TokenKind.Caret => 4,
        TokenKind.Pipe => 3,
        TokenKind.AmpAmp => 2,
        TokenKind.PipePipe => 1,

        // Looser than `||`, so `a ?? b || c` is `a ?? (b || c)` -- which is
        // what it looks like, the fallback being the whole of what follows.
        TokenKind.QuestionQuestion => 1,
        _ => 0,
    };

    /// <summary>Where <c>is</c> and <c>as</c> bind: exactly where a relational operator does.</summary>
    private const int TypeTestPrecedence = 7;

    private static readonly TokenKind[] AssignmentOperators =
    [
        TokenKind.Equals,
        TokenKind.PlusEquals, TokenKind.MinusEquals, TokenKind.StarEquals,
        TokenKind.SlashEquals, TokenKind.PercentEquals,
        TokenKind.AmpEquals, TokenKind.PipeEquals, TokenKind.CaretEquals,
        TokenKind.LessLessEquals, TokenKind.GreaterGreaterEquals,
        TokenKind.QuestionQuestionEquals,
    ];

    public ExpressionSyntax ParseExpression() => ParseAssignment();

    private ExpressionSyntax ParseAssignment()
    {
        int start = _pos;

        if (!Descend()) { Advance(); return Unreadable(start); }

        try { return ParseAssignmentCore(start); }
        finally { Ascend(); }
    }

    private ExpressionSyntax ParseAssignmentCore(int start)
    {
        // A lambda binds looser than anything else, so it is recognised before
        // the operator chain rather than inside it.
        if (TryParseLambda() is { } lambda) return lambda;

        var left = ParseConditional();

        if (AtAny(AssignmentOperators))
        {
            var op = Advance().Kind;
            var right = ParseAssignment();               // right-associative
            return new AssignmentSyntax(SpanFrom(start), left, op, right);
        }

        return left;
    }

    /// <summary>
    /// <c>a ? b : c</c>, binding looser than every binary operator and tighter
    /// than assignment. The false arm recurses, so <c>a ? b : c ? d : e</c>
    /// groups to the right as it does in C.
    /// </summary>
    /// <summary>
    /// Recognises <c>a =&gt; ...</c>, <c>(a, b) =&gt; ...</c> and
    /// <c>(int a) =&gt; ...</c>, or returns null having consumed nothing.
    ///
    /// The parenthesised forms need speculation, because up to the arrow they
    /// are indistinguishable from a parenthesised expression or a cast.
    /// </summary>
    private ExpressionSyntax? TryParseLambda()
    {
        int start = _pos;

        // The one form that needs no lookahead past a single token.
        if (At(TokenKind.Identifier) && Peek(1).Kind == TokenKind.EqualsGreater)
        {
            var single = new LambdaParameterSyntax(SpanFrom(_pos), null, Advance().Text);
            Advance();
            return FinishLambda(start, [single]);
        }

        if (!At(TokenKind.OpenParen)) return null;
        if (!Speculate(TryParseLambdaParameters, out var parameters) || parameters is null) return null;

        return FinishLambda(start, parameters);
    }

    private sealed record LambdaHead(List<LambdaParameterSyntax> Parameters);

    private List<LambdaParameterSyntax>? TryParseLambdaParameters()
    {
        Expect(TokenKind.OpenParen);

        var parameters = new List<LambdaParameterSyntax>();

        if (!At(TokenKind.CloseParen))
        {
            do
            {
                int parameterStart = _pos;

                // `(a, b)` names only; `(int a, int b)` names types too. A bare
                // identifier followed by ',' or ')' is a name.
                TypeSyntax? type = null;
                if (!(At(TokenKind.Identifier) &&
                      (Peek(1).Kind is TokenKind.Comma or TokenKind.CloseParen)))
                    type = ParseType();

                if (!At(TokenKind.Identifier)) return null;
                string name = Advance().Text;

                parameters.Add(new LambdaParameterSyntax(SpanFrom(parameterStart), type, name));
            }
            while (Match(TokenKind.Comma));
        }

        if (!Match(TokenKind.CloseParen)) return null;
        if (!Match(TokenKind.EqualsGreater)) return null;

        return parameters;
    }

    private ExpressionSyntax FinishLambda(int start, List<LambdaParameterSyntax> parameters)
    {
        if (At(TokenKind.OpenBrace))
            return new LambdaSyntax(SpanFrom(start), parameters, null, ParseBlock());

        return new LambdaSyntax(SpanFrom(start), parameters, ParseExpression(), null);
    }

    private ExpressionSyntax ParseConditional()
    {
        int start = _pos;
        var condition = ParseBinary(1);

        if (!At(TokenKind.Question)) return condition;
        Advance();

        // The true arm is delimited by ':', so a full expression is unambiguous.
        var whenTrue = ParseExpression();
        Expect(TokenKind.Colon);
        var whenFalse = ParseAssignment();

        return new ConditionalSyntax(SpanFrom(start), condition, whenTrue, whenFalse);
    }

    private ExpressionSyntax ParseBinary(int minPrecedence)
    {
        int start = _pos;
        var left = ParseUnary();

        while (true)
        {
            // `x is Shape` sits where a comparison does, and takes a type on the
            // right rather than an expression -- which is the whole reason it is
            // not an ordinary binary operator.
            if (At(TokenKind.IsKeyword) && TypeTestPrecedence >= minPrecedence)
            {
                Advance();
                var tested = ParseType();

                // `x is Circle c` names what the test found. Nothing else in
                // the grammar puts an identifier straight after an expression,
                // so no lookahead is needed to tell the two apart.
                if (At(TokenKind.Identifier))
                {
                    var name = Advance();
                    left = new TypeTestSyntax(
                        SpanFrom(start), left, tested, name.Text, name.Span);
                }
                else left = new TypeTestSyntax(SpanFrom(start), left, tested);

                continue;
            }

            // `x as Shape` sits beside it and answers with a value rather than
            // a branch. `as` is a keyword already -- an import names its alias
            // with one -- so nothing here is speculative.
            if (At(TokenKind.AsKeyword) && TypeTestPrecedence >= minPrecedence)
            {
                Advance();
                left = new AsCastSyntax(SpanFrom(start), left, ParseType());
                continue;
            }

            // `x switch { ... }` -- the value goes first, which is what makes a
            // chain of them read left to right.
            if (At(TokenKind.SwitchKeyword) && TypeTestPrecedence >= minPrecedence)
            {
                left = ParseSwitchExpression(start, left);
                continue;
            }

            int precedence = BinaryPrecedence(Current.Kind);
            if (precedence == 0 || precedence < minPrecedence) break;

            var op = Advance().Kind;
            var right = ParseBinary(precedence + 1);     // left-associative
            left = new BinarySyntax(SpanFrom(start), left, op, right);
        }

        return left;
    }

    private ExpressionSyntax ParseUnary()
    {
        int start = _pos;

        // A prefix chain -- `!!!x`, `- - -x` -- recurses here without passing
        // back through ParseAssignment, so it is counted here too.
        if (!Descend()) { Advance(); return Unreadable(start); }

        try { return ParseUnaryCore(start); }
        finally { Ascend(); }
    }

    private ExpressionSyntax ParseUnaryCore(int start)
    {
        // `try` binds like any other prefix, so `try a + b` is `(try a) + b`
        // and `try f().x` covers the whole chain. Anything wider is written
        // with parentheses, which is where a reader would look for it.
        if (At(TokenKind.TryKeyword))
        {
            Advance();
            return new TrySyntax(SpanFrom(start), ParseUnary());
        }

        // `++x` and `--x`. The operand is a unary rather than a postfix so that
        // `++*p` reads, and the parse is the same shape the postfix form gets.
        if (AtAny(TokenKind.PlusPlus, TokenKind.MinusMinus))
        {
            bool up = At(TokenKind.PlusPlus);
            Advance();
            return new IncrementSyntax(SpanFrom(start), ParseUnary(), IsPrefix: true, IsIncrement: up);
        }

        if (AtAny(TokenKind.Minus, TokenKind.Plus, TokenKind.Bang, TokenKind.Tilde,
                  TokenKind.Star, TokenKind.Amp))
        {
            var op = Advance().Kind;
            var operand = ParseUnary();
            return new UnarySyntax(SpanFrom(start), op, operand);
        }
        return ParsePostfix();
    }

    private ExpressionSyntax ParsePostfix()
    {
        int start = _pos;
        var expression = ParsePrimary();

        while (true)
        {
            if (AtAny(TokenKind.Dot, TokenKind.MinusGreater, TokenKind.QuestionDot))
            {
                bool arrow = At(TokenKind.MinusGreater);
                bool asking = At(TokenKind.QuestionDot);
                Advance();
                string member = ExpectIdentifier();
                expression = new MemberAccessSyntax(SpanFrom(start), expression, member)
                    { ThroughPointer = arrow, Conditional = asking };
                continue;
            }

            if (At(TokenKind.OpenParen))
            {
                var arguments = ParseArgumentList();
                expression = new CallSyntax(SpanFrom(start), expression, arguments);
                continue;
            }

            if (At(TokenKind.OpenBracket))
            {
                Advance();

                // `a[:]`, `a[i:]`, `a[:j]` and `a[i:j]` all slice; `a[i]`
                // indexes. The colon is what tells them apart, and a ternary
                // inside the brackets has already consumed its own by the time
                // this looks -- so any colon left here is this one.
                ExpressionSyntax? first =
                    AtAny(TokenKind.Colon, TokenKind.CloseBracket) ? null : ParseExpression();

                if (Match(TokenKind.Colon))
                {
                    ExpressionSyntax? last =
                        At(TokenKind.CloseBracket) ? null : ParseExpression();
                    Expect(TokenKind.CloseBracket);
                    expression = new SliceSyntax(SpanFrom(start), expression, first, last);
                    continue;
                }

                Expect(TokenKind.CloseBracket);

                if (first is null)
                {
                    _diagnostics.Error("SL0450", SpanFrom(start),
                        "an index is missing; write 'a[i]' to read one element, or 'a[i:j]' " +
                        "to take a slice");
                    continue;
                }

                expression = new IndexSyntax(SpanFrom(start), expression, first);
                continue;
            }

            // `x++` and `x--`, after the whole chain, so `a.b[i]++` increments
            // the element rather than anything on the way to it.
            if (AtAny(TokenKind.PlusPlus, TokenKind.MinusMinus))
            {
                bool up = At(TokenKind.PlusPlus);
                Advance();
                expression = new IncrementSyntax(
                    SpanFrom(start), expression, IsPrefix: false, IsIncrement: up);
                continue;
            }

            break;
        }

        return expression;
    }

    private List<ExpressionSyntax> ParseArgumentList()
    {
        var arguments = new List<ExpressionSyntax>();
        Expect(TokenKind.OpenParen);
        while (!At(TokenKind.CloseParen) && !At(TokenKind.EndOfFile))
        {
            int start = _pos;

            // `name: value`. Nothing else in an argument puts a colon straight
            // after a leading identifier -- a ternary has its own '?' and an
            // expression before the colon -- so one token of lookahead is
            // enough to tell them apart.
            if (At(TokenKind.Identifier) && Peek(1).Kind == TokenKind.Colon)
            {
                var label = Advance();
                Advance();
                arguments.Add(new NamedArgumentSyntax(
                    SpanFrom(start), label.Text, label.Span, ParseExpression()));

                if (!Match(TokenKind.Comma)) break;
                continue;
            }

            // `ref x` is written at the call too. `in` is not: it promises the
            // callee will not write, which changes nothing the caller must see.
            if (Match(TokenKind.RefKeyword))
                arguments.Add(new RefArgumentSyntax(SpanFrom(start), ParseExpression()));
            else if (AtOutModifier())
                arguments.Add(ParseOutArgument(start));
            else
                arguments.Add(ParseExpression());

            if (!Match(TokenKind.Comma)) break;
        }
        Expect(TokenKind.CloseParen);
        return arguments;
    }

    /// <summary>
    /// Each hole parsed as the expression it is, by a parser over the tokens
    /// the lexer already read for it.
    ///
    /// A hole is one expression and nothing more: anything left over after it
    /// is reported rather than ignored, because `$"{a b}"` is a mistake and
    /// silently writing `a` would hide it.
    /// </summary>
    private ExpressionSyntax ParseInterpolatedString()
    {
        int start = _pos;
        var token = Advance();

        var parts = new List<InterpolatedPartSyntax>();

        foreach (var segment in (IReadOnlyList<InterpolationSegment>)token.Value!)
        {
            if (!segment.IsHole)
            {
                parts.Add(new InterpolatedPartSyntax(segment.Literal, null));
                continue;
            }

            var inner = new Parser(_source, _diagnostics, segment.Tokens!);
            var value = inner.ParseExpression();

            if (!inner.At(TokenKind.EndOfFile))
                _diagnostics.Error("SL0556", inner.Current.Span,
                    $"an interpolation holds one expression, and {inner.Current.Kind.Describe()} " +
                    "follows this one");

            parts.Add(new InterpolatedPartSyntax(null, value));
        }

        return new InterpolatedStringSyntax(SpanFrom(start), parts);
    }

    private ExpressionSyntax ParsePrimary()
    {
        int start = _pos;

        // `checked(e)` and `unchecked(e)`, before the switch because the word
        // is an ordinary identifier to the lexer. The paren is what tells it
        // from a variable of the same name; a *call* to a function actually
        // named `checked` is the one thing this takes away.
        if (AtCheckedWord() && Peek(1).Kind == TokenKind.OpenParen)
        {
            bool wanted = Current.Text == "checked";
            Advance();
            Advance();
            var guarded = ParseExpression();
            Expect(TokenKind.CloseParen);
            return new CheckedSyntax(SpanFrom(start), guarded, wanted);
        }

        switch (Current.Kind)
        {
            case TokenKind.IntLiteral:
            case TokenKind.FloatLiteral:
            case TokenKind.StringLiteral:
            case TokenKind.CharLiteral:
            case TokenKind.TrueKeyword:
            case TokenKind.FalseKeyword:
            {
                var token = Advance();
                return new LiteralSyntax(SpanFrom(start), token.Kind, token.Value);
            }

            case TokenKind.InterpolatedString:
                return ParseInterpolatedString();

            case TokenKind.NullKeyword:
                Advance();
                return new LiteralSyntax(SpanFrom(start), TokenKind.NullKeyword, null);

            // `[a, b, c]`. Unambiguous here: an attribute list only precedes a
            // declaration, and an index only follows something to index.
            case TokenKind.OpenBracket:
            {
                Advance();
                var elements = new List<ExpressionSyntax>();

                while (!At(TokenKind.CloseBracket) && !At(TokenKind.EndOfFile))
                {
                    elements.Add(ParseExpression());

                    // A trailing comma is allowed, so a list written one entry
                    // per line can have every line end the same way.
                    if (!Match(TokenKind.Comma)) break;
                }

                Expect(TokenKind.CloseBracket);
                return new ArrayLiteralSyntax(SpanFrom(start), elements);
            }

            case TokenKind.ThisKeyword:
                Advance();
                return new ThisSyntax(SpanFrom(start));

            case TokenKind.BaseKeyword:
                Advance();
                return new BaseSyntax(SpanFrom(start));

            case TokenKind.NewKeyword:
            {
                Advance();
                var type = ParseType(allowFixedLength: false);

                // `new T[n]`: ParseType stopped at the bracket because a length
                // follows rather than a closing bracket.
                if (At(TokenKind.OpenBracket))
                {
                    Advance();
                    var length = ParseExpression();
                    Expect(TokenKind.CloseBracket);
                    return new NewArraySyntax(SpanFrom(start), type, length);
                }

                var arguments = At(TokenKind.OpenParen) ? ParseArgumentList() : [];

                return new NewSyntax(SpanFrom(start), type, arguments)
                {
                    Initializer = At(TokenKind.OpenBrace) ? ParseObjectInitializer() : null,
                };
            }

            case TokenKind.SizeofKeyword:
            {
                Advance();
                Expect(TokenKind.OpenParen);
                var type = ParseType();
                Expect(TokenKind.CloseParen);
                return new SizeofSyntax(SpanFrom(start), type);
            }

            case TokenKind.AlignofKeyword:
            {
                Advance();
                Expect(TokenKind.OpenParen);
                var type = ParseType();
                Expect(TokenKind.CloseParen);
                return new AlignofSyntax(SpanFrom(start), type);
            }

            case TokenKind.OffsetofKeyword:
            {
                Advance();
                Expect(TokenKind.OpenParen);
                var type = ParseType();
                Expect(TokenKind.Comma);

                var field = Current;
                Expect(TokenKind.Identifier);
                Expect(TokenKind.CloseParen);
                return new OffsetofSyntax(SpanFrom(start), type, field.Text, field.Span);
            }

            case TokenKind.TypeofKeyword:
            {
                Advance();
                Expect(TokenKind.OpenParen);
                var type = ParseType();
                Expect(TokenKind.CloseParen);
                return new TypeofSyntax(SpanFrom(start), type);
            }

            case TokenKind.DefaultKeyword:
            {
                Advance();
                Expect(TokenKind.OpenParen);
                var zeroed = ParseType();
                Expect(TokenKind.CloseParen);
                return new DefaultSyntax(SpanFrom(start), zeroed);
            }

            case TokenKind.NameofKeyword:
            {
                Advance();
                Expect(TokenKind.OpenParen);

                // An expression, not a type: what goes in is a thing that
                // exists, and the answer is the last name written. Binding it
                // is what checks the spelling, which is the whole point.
                var named = ParseExpression();
                Expect(TokenKind.CloseParen);
                return new NameofSyntax(SpanFrom(start), named);
            }


            case TokenKind.IidofKeyword:
            {
                Advance();
                Expect(TokenKind.OpenParen);
                var type = ParseType();
                Expect(TokenKind.CloseParen);
                return new IidofSyntax(SpanFrom(start), type);
            }

            case TokenKind.OpenParen:
            {
                // `(Type)operand` is a cast; anything else in parentheses is grouping.
                if (Speculate(TryParseCastHead, out var castType) && castType is not null)
                {
                    var operand = ParseUnary();
                    return new CastSyntax(SpanFrom(start), castType, operand);
                }

                Advance();
                var inner = ParseExpression();

                // `(a, b)` is a tuple; `(a)` is `a`. The comma is the whole of
                // the difference, and there is nothing to speculate about --
                // by here the cast and the lambda have both had their turn.
                if (At(TokenKind.Comma))
                {
                    var elements = new List<ExpressionSyntax> { inner };
                    while (Match(TokenKind.Comma)) elements.Add(ParseExpression());

                    Expect(TokenKind.CloseParen);
                    return new TupleSyntax(SpanFrom(start), elements);
                }

                Expect(TokenKind.CloseParen);
                return inner;
            }

            case TokenKind.Identifier:
            {
                // Just the one identifier. A following '.' is postfix member access,
                // which the binder later reinterprets as a module path when the
                // leading name turns out to be a module rather than a value.
                var identifier = Advance();
                return new NameSyntax(SpanFrom(start),
                    new QualifiedName(identifier.Span, [identifier.Text]));
            }

            default:
                if (AtAny(PrimitiveKeywords))
                {
                    // Reached via things like `int(x)`, which is not valid syntax here.
                    _diagnostics.Error("SL0106", Current.Span,
                        $"'{Current.Text}' is a type name and cannot be used as a value");
                    Advance();
                    return new LiteralSyntax(SpanFrom(start), TokenKind.IntLiteral, 0UL);
                }

                if (!_tooDeep)
                    _diagnostics.Error("SL0107", Current.Span,
                        $"expected an expression, found {Current.Kind.Describe()}");
                Advance();
                return new LiteralSyntax(SpanFrom(start), TokenKind.IntLiteral, 0UL);
        }
    }

    /// <summary>What a type is under any number of fixed-length brackets.</summary>
    private static TypeSyntax Core(TypeSyntax type) =>
        type is FixedArrayTypeSyntax fixedArray ? Core(fixedArray.Element) : type;

    private TypeSyntax? TryParseCastHead()
    {
        Expect(TokenKind.OpenParen);
        if (!AtTypeStart()) return null;

        var type = ParseType();
        if (!At(TokenKind.CloseParen)) return null;
        Advance();

        // `(x)` and `(x) + 1` must stay expressions. A bare name in parentheses
        // only reads as a cast when what follows can only begin an operand --
        // and `(a[4])` is the same problem wearing brackets, since it is an
        // index as readily as it is a fixed-array type.
        bool typeIsUnambiguous = Core(type) is not NamedTypeSyntax;
        bool operandFollows = AtAny(
            TokenKind.Identifier, TokenKind.IntLiteral, TokenKind.FloatLiteral,
            TokenKind.StringLiteral, TokenKind.CharLiteral, TokenKind.OpenParen,
            TokenKind.TryKeyword,
            TokenKind.ThisKeyword, TokenKind.BaseKeyword, TokenKind.NewKeyword,
            TokenKind.SizeofKeyword,
            TokenKind.AlignofKeyword, TokenKind.OffsetofKeyword,
            TokenKind.TypeofKeyword,
            TokenKind.TrueKeyword, TokenKind.FalseKeyword, TokenKind.NullKeyword,
            TokenKind.Bang, TokenKind.Tilde);

        return typeIsUnambiguous || operandFollows ? type : null;
    }
}
