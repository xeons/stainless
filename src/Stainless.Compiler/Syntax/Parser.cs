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
/// A hand-written recursive-descent parser with a precedence-climbing
/// expression parser. It parses one file into one <see cref="CompilationUnitSyntax"/>;
/// nothing here needs to know about any other file, which is what makes
/// header-free separate compilation possible.
/// </summary>
public sealed class Parser
{
    private readonly List<Token> _tokens;
    private readonly SourceText _source;
    private readonly Lexer _lexer;
    private DiagnosticBag _diagnostics;
    private int _pos;

    public Parser(
        SourceText source, DiagnosticBag diagnostics, IReadOnlyCollection<string>? symbols = null)
    {
        _source = source;
        _diagnostics = diagnostics;
        _lexer = new Lexer(source, diagnostics, symbols);
        _tokens = _lexer.Tokenize();
    }

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
        _diagnostics.Error("SL0100", Current.Span,
            $"expected {kind.Describe()}, found {Current.Kind.Describe()}");
        return new Token(kind, Current.Span, kind.FixedText() ?? "");
    }

    private string ExpectIdentifier()
    {
        if (At(TokenKind.Identifier)) return Advance().Text;
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
        }
    }

    // ------------------------------------------------------------ compilation unit

    public CompilationUnitSyntax ParseCompilationUnit()
    {
        int start = _pos;

        QualifiedName? moduleName = null;
        if (Match(TokenKind.ModuleKeyword))
        {
            moduleName = ParseQualifiedName();
            Expect(TokenKind.Semicolon);
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

        return new CompilationUnitSyntax(
            SpanFrom(start), _source, moduleName, imports, declarations, _lexer.Libraries);
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
        int start = _pos;
        var attributes = ParseAttributeLists();
        var modifiers = ParseModifiers();

        if (At(TokenKind.ExternKeyword) || At(TokenKind.ExportKeyword))
            return ParseLinkageDeclaration(start, modifiers);

        if (AtAny(TokenKind.ClassKeyword, TokenKind.StructKeyword,
                  TokenKind.InterfaceKeyword, TokenKind.AttributeKeyword,
                  TokenKind.VariantKeyword, TokenKind.UnionKeyword))
            return [ParseTypeDeclaration(start, modifiers, attributes)];

        if (At(TokenKind.EnumKeyword))
            return [ParseEnumDeclaration(start, modifiers, attributes)];

        if (At(TokenKind.DelegateKeyword))
            return [ParseDelegateDeclaration(start, modifiers)];

        if (At(TokenKind.Tilde) && enclosingType is not null)
            return [ParseDestructor(start, enclosingType)];

        if (At(TokenKind.StaticKeyword))
            return [ParseStaticDeclaration(start, modifiers)];

        if (modifiers.HasFlag(Modifiers.Const))
            return [ParseGlobalConst(start, modifiers)];

        // A constructor looks like `TypeName(` inside its own type.
        if (enclosingType is not null &&
            At(TokenKind.Identifier) && Current.Text == enclosingType &&
            Peek(1).Kind == TokenKind.OpenParen)
        {
            Advance();
            var ctorParams = ParseParameterList(out _);
            var ctorBody = ParseBlock();
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
                default: return modifiers;
            }
        }
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
                members.Add(ParseFunctionOrField(memberStart, memberModifiers, linkage));
                if (_pos == before) Advance();
            }
            Expect(TokenKind.CloseBrace);
            return members;
        }

        // Single-declaration form: extern "C" int puts(byte* s);
        var singleModifiers = modifiers | ParseModifiers();
        return [ParseFunctionOrField(start, singleModifiers, linkage)];
    }

    private Declaration ParseTypeDeclaration(
        int start, Modifiers modifiers, IReadOnlyList<AttributeSyntax> attributes)
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
        string name = ExpectIdentifier();
        var typeParameters = ParseTypeParameterList();

        // `class Circle : Shape, Comparable<Circle>` -- a list of interfaces,
        // which may themselves be generic, so these are full types not bare names.
        var implements = new List<TypeSyntax>();
        if (Match(TokenKind.Colon))
        {
            do { implements.Add(ParseType()); }
            while (Match(TokenKind.Comma));
        }

        var constraints = ParseWhereClauses();
        Expect(TokenKind.OpenBrace);

        var members = new List<Declaration>();
        var cases = new List<VariantCaseSyntax>();

        while (!At(TokenKind.CloseBrace) && !At(TokenKind.EndOfFile))
        {
            int before = _pos;

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

            members.AddRange(ParseDeclaration(enclosingType: name));
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

    /// <summary><c>Circle(double radius);</c> or <c>Empty;</c>.</summary>
    private VariantCaseSyntax ParseVariantCase()
    {
        int start = _pos;
        string name = ExpectIdentifier();

        IReadOnlyList<ParameterSyntax> parameters = [];
        bool variadic = false;

        if (At(TokenKind.OpenParen)) parameters = ParseParameterList(out variadic);

        if (variadic)
            _diagnostics.Error("SL0431", SpanFrom(start),
                $"case '{name}' cannot be variadic; a case's parameters are the fields it " +
                "carries, and a value has a fixed number of them");

        Expect(TokenKind.Semicolon);
        return new VariantCaseSyntax(SpanFrom(start), name, parameters);
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
            string memberName = ExpectIdentifier();
            ExpressionSyntax? value = Match(TokenKind.Equals) ? ParseExpression() : null;
            members.Add(new EnumMemberSyntax(SpanFrom(memberStart), memberName, value));

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
        Expect(TokenKind.DelegateKeyword);
        var returnType = ParseType();
        string name = ExpectIdentifier();
        var parameters = ParseParameterList(out bool variadic);

        if (variadic)
            _diagnostics.Error("SL0358", SpanFrom(start),
                $"delegate '{name}' cannot be variadic; there is no way to call one safely");

        Expect(TokenKind.Semicolon);
        return new DelegateDeclSyntax(SpanFrom(start), modifiers, name, returnType, parameters);
    }

    /// <summary>
    /// <c>static readonly T Name = value;</c>. The type is written out, as a C#
    /// field's is; <c>var</c> infers for locals only.
    /// </summary>
    private Declaration ParseStaticDeclaration(int start, Modifiers modifiers)
    {
        Expect(TokenKind.StaticKeyword);

        if (!Match(TokenKind.ReadonlyKeyword))
        {
            _diagnostics.Error("SL0376", SpanFrom(start),
                "a 'static' must be 'readonly'; there is no mutable global in Stainless, " +
                "because nothing would synchronize it. Hold the mutable part in a type " +
                "that says how it is safe, as in 'static readonly AtomicLong Count = ...'");
        }

        var type = ParseType();
        string name = ExpectIdentifier();
        Expect(TokenKind.Equals);
        var value = ParseExpression();
        Expect(TokenKind.Semicolon);

        return new StaticDeclSyntax(SpanFrom(start), modifiers, type, name, value);
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
        };
    }

    /// <summary>
    /// The accessor list of a property, or the single expression that stands in
    /// for one: <c>int Area =&gt; width * height;</c> is <c>{ get { return ...; } }</c>.
    /// </summary>
    private Declaration ParseProperty(
        int start, Modifiers modifiers, TypeSyntax type, string name,
        IReadOnlyList<AttributeSyntax> attributes)
    {
        var accessors = new List<AccessorSyntax>();

        if (Match(TokenKind.EqualsGreater))
        {
            accessors.Add(new AccessorSyntax(
                SpanFrom(start), Modifiers.None, IsGetter: true, ParseArrowBody(isGetter: true)));
            Expect(TokenKind.Semicolon);
            return new PropertyDeclSyntax(
                SpanFrom(start), modifiers, type, name, accessors, attributes);
        }

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
        return new PropertyDeclSyntax(SpanFrom(start), modifiers, type, name, accessors, attributes);
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

            var type = ParseType();
            string name = ExpectIdentifier();
            parameters.Add(new ParameterSyntax(SpanFrom(paramStart), type, name, mode));

            if (!Match(TokenKind.Comma)) break;
        }

        Expect(TokenKind.CloseParen);
        return parameters;
    }

    // ------------------------------------------------------------ types

    private static readonly TokenKind[] PrimitiveKeywords =
    [
        TokenKind.VoidKeyword, TokenKind.BoolKeyword, TokenKind.CharKeyword,
        TokenKind.SByteKeyword, TokenKind.ShortKeyword, TokenKind.IntKeyword,
        TokenKind.LongKeyword, TokenKind.NIntKeyword,
        TokenKind.ByteKeyword, TokenKind.UShortKeyword, TokenKind.UIntKeyword,
        TokenKind.ULongKeyword, TokenKind.NUIntKeyword,
        TokenKind.FloatKeyword, TokenKind.DoubleKeyword,
    ];

    private bool AtTypeStart() =>
        AtAny(PrimitiveKeywords) || At(TokenKind.Identifier) || At(TokenKind.WeakKeyword);

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

        if (Match(TokenKind.WeakKeyword))
        {
            var inner = ParseType(allowFixedLength);
            return new WeakTypeSyntax(SpanFrom(start), inner);
        }

        TypeSyntax type;
        if (AtAny(PrimitiveKeywords))
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

            var constraints = new List<TypeSyntax>();
            do { constraints.Add(ParseType()); }
            while (Match(TokenKind.Comma));

            clauses.Add(new WhereClauseSyntax(SpanFrom(start), parameter, constraints));
        }

        return clauses;
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

            default:
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

                    // `case Circle c:` names a variant's case and binds its
                    // payload. Two identifiers in a row is the whole of the
                    // test: no expression starts that way.
                    if (At(TokenKind.Identifier) && Peek(1).Kind == TokenKind.Identifier)
                    {
                        string caseName = ExpectIdentifier();
                        string binding = ExpectIdentifier();
                        bindings.Add(new CaseBindingSyntax(
                            SpanFrom(labelStart), caseName, binding));
                    }
                    else
                    {
                        labels.Add(ParseExpression());
                    }
                }

                Expect(TokenKind.Colon);
            }

            if (labels.Count == 0 && bindings.Count == 0 && !hasDefault)
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
                SpanFrom(sectionStart), labels, hasDefault, statements) { Bindings = bindings });
        }

        Expect(TokenKind.CloseBrace);
        return new SwitchSyntax(SpanFrom(start), value, sections);
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
        _ => 0,
    };

    private static readonly TokenKind[] AssignmentOperators =
    [
        TokenKind.Equals,
        TokenKind.PlusEquals, TokenKind.MinusEquals, TokenKind.StarEquals,
        TokenKind.SlashEquals, TokenKind.PercentEquals,
        TokenKind.AmpEquals, TokenKind.PipeEquals, TokenKind.CaretEquals,
        TokenKind.LessLessEquals, TokenKind.GreaterGreaterEquals,
    ];

    public ExpressionSyntax ParseExpression() => ParseAssignment();

    private ExpressionSyntax ParseAssignment()
    {
        int start = _pos;

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
            if (At(TokenKind.Dot))
            {
                Advance();
                string member = ExpectIdentifier();
                expression = new MemberAccessSyntax(SpanFrom(start), expression, member);
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

            // `ref x` is written at the call too. `in` is not: it promises the
            // callee will not write, which changes nothing the caller must see.
            if (Match(TokenKind.RefKeyword))
                arguments.Add(new RefArgumentSyntax(SpanFrom(start), ParseExpression()));
            else
                arguments.Add(ParseExpression());

            if (!Match(TokenKind.Comma)) break;
        }
        Expect(TokenKind.CloseParen);
        return arguments;
    }

    private ExpressionSyntax ParsePrimary()
    {
        int start = _pos;
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

            case TokenKind.NullKeyword:
                Advance();
                return new LiteralSyntax(SpanFrom(start), TokenKind.NullKeyword, null);

            case TokenKind.ThisKeyword:
                Advance();
                return new ThisSyntax(SpanFrom(start));

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
                return new NewSyntax(SpanFrom(start), type, arguments);
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
            TokenKind.ThisKeyword, TokenKind.NewKeyword, TokenKind.SizeofKeyword,
            TokenKind.AlignofKeyword, TokenKind.OffsetofKeyword,
            TokenKind.TypeofKeyword,
            TokenKind.TrueKeyword, TokenKind.FalseKeyword, TokenKind.NullKeyword,
            TokenKind.Bang, TokenKind.Tilde);

        return typeIsUnambiguous || operandFollows ? type : null;
    }
}
