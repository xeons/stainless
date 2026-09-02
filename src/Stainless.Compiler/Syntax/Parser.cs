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
    private DiagnosticBag _diagnostics;
    private int _pos;

    public Parser(SourceText source, DiagnosticBag diagnostics)
    {
        _source = source;
        _diagnostics = diagnostics;
        _tokens = new Lexer(source, diagnostics).Tokenize();
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

        return new CompilationUnitSyntax(SpanFrom(start), _source, moduleName, imports, declarations);
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
                  TokenKind.InterfaceKeyword, TokenKind.AttributeKeyword))
            return [ParseTypeDeclaration(start, modifiers, attributes)];

        if (At(TokenKind.Tilde) && enclosingType is not null)
            return [ParseDestructor(start, enclosingType)];

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
        Advance();

        // The convention string is required and, for now, must be "C".
        if (At(TokenKind.StringLiteral))
        {
            string convention = (string)(Advance().Value ?? "");
            if (convention != "C")
                _diagnostics.Error("SL0102", SpanFrom(start),
                    $"unsupported linkage convention \"{convention}\"; only \"C\" is supported");
        }
        else
        {
            _diagnostics.Error("SL0103", Current.Span,
                $"expected a linkage convention string such as \"C\" after '{(isExtern ? "extern" : "export")}'");
        }

        var linkage = isExtern ? LinkageKind.ExternC : LinkageKind.ExportC;

        // Block form: extern "C" { ... }
        if (Match(TokenKind.OpenBrace))
        {
            var members = new List<Declaration>();
            while (!At(TokenKind.CloseBrace) && !At(TokenKind.EndOfFile))
            {
                int before = _pos;
                int memberStart = _pos;
                var memberModifiers = ParseModifiers();
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
        while (!At(TokenKind.CloseBrace) && !At(TokenKind.EndOfFile))
        {
            int before = _pos;
            members.AddRange(ParseDeclaration(enclosingType: name));
            if (_pos == before) Advance();
        }
        Expect(TokenKind.CloseBrace);

        if (constraints.Count > 0 && typeParameters.Count == 0)
            _diagnostics.Error("SL0331", SpanFrom(start),
                $"'{name}' is not generic, so it cannot have a 'where' clause");

        return new TypeDeclSyntax(
            SpanFrom(start), modifiers, kind, name, typeParameters, constraints,
            implements, members, attributes);
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

            if (linkage == LinkageKind.ExternC && body is not null)
                _diagnostics.Error("SL0105", SpanFrom(start),
                    $"'extern \"C\"' declares an external function, so '{name}' must not have a body; use 'export \"C\"' to define one");

            return new FunctionDeclSyntax(
                SpanFrom(start), modifiers, linkage, returnType, name, typeParameters,
                constraints, parameters, isVariadic, body);
        }

        if (typeParameters.Count > 0)
            _diagnostics.Error("SL0320", SpanFrom(start),
                $"'{name}' is a field and cannot have type parameters");

        ExpressionSyntax? initializer = Match(TokenKind.Equals) ? ParseExpression() : null;
        Expect(TokenKind.Semicolon);
        return new FieldDeclSyntax(
            SpanFrom(start), modifiers, returnType, name, initializer, attributes ?? []);
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
            var type = ParseType();
            string name = ExpectIdentifier();
            parameters.Add(new ParameterSyntax(SpanFrom(paramStart), type, name));

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

    private TypeSyntax ParseType()
    {
        int start = _pos;

        if (Match(TokenKind.WeakKeyword))
        {
            var inner = ParseType();
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

            // Only empty brackets are part of a type. `new int[10]` keeps its
            // length expression for the caller to read.
            if (At(TokenKind.OpenBracket) && Peek(1).Kind == TokenKind.CloseBracket)
            {
                Advance();
                Advance();
                type = new ArrayTypeSyntax(SpanFrom(start), type);
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

        Expect(TokenKind.Greater);
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

    /// <summary>Parses <c>&lt;T, U&gt;</c> in a declaration.</summary>
    private List<string> ParseTypeParameterList()
    {
        var parameters = new List<string>();
        if (!Match(TokenKind.Less)) return parameters;

        do { parameters.Add(ExpectIdentifier()); }
        while (Match(TokenKind.Comma));

        Expect(TokenKind.Greater);
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
        var left = ParseBinary(1);

        if (AtAny(AssignmentOperators))
        {
            var op = Advance().Kind;
            var right = ParseAssignment();               // right-associative
            return new AssignmentSyntax(SpanFrom(start), left, op, right);
        }

        return left;
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
                var index = ParseExpression();
                Expect(TokenKind.CloseBracket);
                expression = new IndexSyntax(SpanFrom(start), expression, index);
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
                var type = ParseType();

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

    private TypeSyntax? TryParseCastHead()
    {
        Expect(TokenKind.OpenParen);
        if (!AtTypeStart()) return null;

        var type = ParseType();
        if (!At(TokenKind.CloseParen)) return null;
        Advance();

        // `(x)` and `(x) + 1` must stay expressions. A bare name in parentheses
        // only reads as a cast when what follows can only begin an operand.
        bool typeIsUnambiguous = type is not NamedTypeSyntax;
        bool operandFollows = AtAny(
            TokenKind.Identifier, TokenKind.IntLiteral, TokenKind.FloatLiteral,
            TokenKind.StringLiteral, TokenKind.CharLiteral, TokenKind.OpenParen,
            TokenKind.ThisKeyword, TokenKind.NewKeyword, TokenKind.SizeofKeyword,
            TokenKind.TypeofKeyword,
            TokenKind.TrueKeyword, TokenKind.FalseKeyword, TokenKind.NullKeyword,
            TokenKind.Bang, TokenKind.Tilde);

        return typeIsUnambiguous || operandFollows ? type : null;
    }
}
