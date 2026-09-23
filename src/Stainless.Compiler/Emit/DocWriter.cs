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

using System.Text;
using Stainless.Syntax;

namespace Stainless.Emit;

/// <summary>
/// Turns the <c>///</c> blocks into browsable reference documentation: one
/// Markdown page per module, each public member with its signature, its block
/// and a link to the line it is declared on.
///
/// <para>
/// <b>It reads the syntax tree rather than the bound program</b>, which is the
/// one decision here worth explaining. Two reasons, and the second is decisive:
/// </para>
///
/// <para>
/// A reader wants the signature that was <i>written</i>. Binding resolves an
/// alias to what it names, a <c>var</c> to what it inferred and a generic to
/// whatever it was instantiated with, and every one of those makes a reference
/// page say something other than what the source says.
/// </para>
///
/// <para>
/// A generic emits nothing until it is instantiated, so <c>List&lt;T&gt;</c>,
/// <c>Dictionary&lt;K, V&gt;</c> and <c>Optional&lt;T&gt;</c> have no bound
/// symbol at all unless some program happened to use them. Documentation that
/// covered only the instantiated half of the standard library would be worse
/// than none, because nothing on the page would say which half that was.
/// </para>
///
/// <para>
/// The compilation still binds first, and this runs only if it succeeded. That
/// is what keeps the pages honest: a signature here is one the compiler
/// accepted, not one that merely parsed.
/// </para>
/// </summary>
public static class DocWriter
{
    /// <summary>
    /// Writes a page per module into <paramref name="directory"/>, plus an
    /// <c>index.md</c> listing them. Returns the files written, in the order
    /// they were written.
    /// </summary>
    /// <param name="sourceRoot">
    /// What source links are made relative to, so a page can point at the
    /// declaration. Null leaves the link out rather than writing an absolute
    /// path from the machine that happened to build it.
    /// </param>
    public static IReadOnlyList<string> Write(
        IReadOnlyList<CompilationUnitSyntax> units,
        string directory,
        string? sourceRoot = null,
        (string From, string To)? rewritePath = null)
    {
        // What a run needs to know -- where the sources are, which page is
        // being written, what every name links to -- is held in static fields,
        // so two runs at once would read each other's. One at a time is the
        // whole of the fix: this writes a few dozen files and is never on a
        // path where the wait matters.
        lock (s_writing) return WriteOnce(units, directory, sourceRoot, rewritePath);
    }

    private static readonly object s_writing = new();

    private static IReadOnlyList<string> WriteOnce(
        IReadOnlyList<CompilationUnitSyntax> units,
        string directory,
        string? sourceRoot,
        (string From, string To)? rewritePath)
    {
        Directory.CreateDirectory(directory);

        _rewrite = rewritePath;
        _sourceRoot = sourceRoot;
        _output = directory;

        var modules = Gather(units);
        IndexLinkTargets(modules);

        var written = new List<string>();

        foreach (var module in modules)
        {
            string path = Path.Combine(directory, FileNameOf(module.Name));
            _page = FileNameOf(module.Name);
            File.WriteAllText(path, Page(module, sourceRoot), Utf8);
            written.Add(path);
        }

        string index = Path.Combine(directory, "index.md");
        File.WriteAllText(index, Index(modules), Utf8);
        written.Add(index);

        return written;
    }

    /// <summary>
    /// No byte order mark. It is not wrong in UTF-8 and it is not wanted: these
    /// files are read by tools that expect a plain text file to begin with its
    /// first character.
    /// </summary>
    private static readonly UTF8Encoding Utf8 = new(encoderShouldEmitUTF8Identifier: false);

    /// <summary>
    /// A prefix to replace in a source path before a link is made from it.
    ///
    /// The standard library is compiled from the compiler's own resources, so
    /// its files carry a label rather than a path and a link built from one
    /// would point nowhere. The caller says what that label really is, because
    /// the caller is what knows.
    /// </summary>
    private static (string From, string To)? _rewrite;

    /// <summary>What a source path is relative to, and where the pages go.</summary>
    private static string? _sourceRoot;
    private static string _output = ".";

    // ================================================================ model

    /// <summary>One module's public surface, gathered from however many files
    /// declared it.</summary>
    private sealed record Module(string Name)
    {
        public string? Documentation { get; set; }
        public List<Entry> Types { get; } = [];
        public List<Entry> Functions { get; } = [];
        public List<Entry> Constants { get; } = [];
    }

    /// <summary>
    /// One documented thing: what to print as its heading, what to print as its
    /// signature, its block, where it came from, and its members.
    /// </summary>
    private sealed record Entry(
        string Name, string Signature, string? Documentation, SourceLocation? Where)
    {
        public List<Entry> Members { get; } = [];
        public string Kind { get; init; } = "";

        /// <summary>
        /// For a type, what it was declared with after the colon: its base
        /// class and the interfaces it implements, as they were written. It is
        /// what a bare '@inheritdoc' on a member searches.
        /// </summary>
        public IReadOnlyList<string> Inherits { get; init; } = [];
    }

    private sealed record SourceLocation(string File, int Line);

    // ============================================================ gathering

    private static List<Module> Gather(IReadOnlyList<CompilationUnitSyntax> units)
    {
        var byName = new Dictionary<string, Module>(StringComparer.Ordinal);

        foreach (var unit in units)
        {
            if (unit.ModuleName is null) continue;

            string name = string.Join(".", unit.ModuleName.Parts);
            if (!byName.TryGetValue(name, out var module))
                byName[name] = module = new Module(name);

            // A module may span files and each may carry a block. The first one
            // wins rather than the longest or the concatenation: a module's
            // overview is written once, in whichever file is its centre, and
            // joining two would read as one argument that changes subject.
            module.Documentation ??= unit.Documentation;

            foreach (var declaration in unit.Declarations)
                Add(module, declaration, unit);
        }

        return byName.Values.OrderBy(m => m.Name, StringComparer.Ordinal).ToList();
    }

    private static void Add(Module module, Declaration declaration, CompilationUnitSyntax unit)
    {
        if (!declaration.Modifiers.HasFlag(Modifiers.Public)) return;

        switch (declaration)
        {
            case TypeDeclSyntax type:
                module.Types.Add(DescribeType(type, unit));
                break;

            case EnumDeclSyntax enumeration:
                module.Types.Add(DescribeEnum(enumeration, unit));
                break;

            case DelegateDeclSyntax handler:
                module.Types.Add(DescribeDelegate(handler, unit));
                break;

            // An `extern "C"` declaration is the runtime's, not the library's:
            // it names a symbol a consumer cannot call and has no meaning
            // outside the file that declares it.
            case FunctionDeclSyntax { Linkage: LinkageKind.Stainless } function:
                module.Functions.Add(DescribeFunction(function, unit));
                break;

            case GlobalConstDeclSyntax constant:
                module.Constants.Add(new Entry(
                    constant.Name,
                    Constant(constant),
                    constant.Documentation,
                    Locate(unit, constant.Span))
                { Kind = "constant" });
                break;

            case StaticDeclSyntax stored:
                module.Constants.Add(new Entry(
                    stored.Name,
                    $"static readonly {Render(stored.Type)} {stored.Name}",
                    stored.Documentation,
                    Locate(unit, stored.Span))
                { Kind = "static" });
                break;

            case AliasDeclSyntax alias:
                module.Types.Add(new Entry(
                    alias.Name,
                    $"using {alias.Name} = {Render(alias.Target)}",
                    alias.Documentation,
                    Locate(unit, alias.Span))
                { Kind = "alias" });
                break;
        }
    }

    /// <summary>
    /// A <c>const</c> as it was written. The type is optional in the source --
    /// <c>const Pi = 3.14;</c> takes it from the value -- and the page says
    /// what the source says rather than the type the binder worked out.
    /// </summary>
    private static string Constant(GlobalConstDeclSyntax constant)
    {
        string type = constant.Type is null ? "" : Render(constant.Type) + " ";
        return $"const {type}{constant.Name} = {Render(constant.Value)}";
    }

    private static Entry DescribeType(TypeDeclSyntax type, CompilationUnitSyntax unit)
    {
        string kind = type.Kind switch
        {
            TypeDeclKind.Class => "class",
            TypeDeclKind.Struct => "struct",
            TypeDeclKind.Interface => "interface",
            TypeDeclKind.Variant => "variant",
            TypeDeclKind.Union => "union",
            TypeDeclKind.Attribute => "attribute",
            _ => "type",
        };

        var signature = new StringBuilder();
        if (type.Modifiers.HasFlag(Modifiers.Threadsafe)) signature.Append("threadsafe ");
        if (type.Modifiers.HasFlag(Modifiers.Abstract)) signature.Append("abstract ");
        if (type.Modifiers.HasFlag(Modifiers.Sealed)) signature.Append("sealed ");

        signature.Append(kind).Append(' ').Append(type.Name).Append(Parameters(type.TypeParameters));

        if (type.Implements.Count > 0)
            signature.Append(" : ").Append(string.Join(", ", type.Implements.Select(Render)));

        foreach (var clause in type.Constraints)
            signature.Append("\n    where ").Append(clause.TypeParameter).Append(" : ")
                     .Append(string.Join(", ", clause.Constraints.Select(Render)));

        var entry = new Entry(
            type.Name + Parameters(type.TypeParameters),
            signature.ToString(),
            type.Documentation,
            Locate(unit, type.Span))
        {
            Kind = kind,
            Inherits = [.. type.Implements.Select(Render)],
        };

        foreach (var variantCase in type.Cases)
            entry.Members.Add(new Entry(
                variantCase.Name,
                variantCase.Parameters.Count == 0
                    ? variantCase.Name
                    : variantCase.Name + "(" +
                      string.Join(", ", variantCase.Parameters.Select(Render)) + ")",
                variantCase.Documentation,
                Locate(unit, variantCase.Span))
            { Kind = "case" });

        foreach (var member in type.Members)
            AddMember(entry, member, unit, type.Name);

        return entry;
    }

    private static void AddMember(
        Entry owner, Declaration member, CompilationUnitSyntax unit, string typeName)
    {
        // An interface's members are its contract, so they are public whether or
        // not the word is written -- exactly as the binder reads them.
        bool contract = owner.Kind is "interface";
        if (!contract && !member.Modifiers.HasFlag(Modifiers.Public)) return;

        switch (member)
        {
            case FunctionDeclSyntax function:
                owner.Members.Add(DescribeFunction(function, unit, typeName));
                break;

            case PropertyDeclSyntax property:
                owner.Members.Add(DescribeProperty(property, unit));
                break;

            case FieldDeclSyntax { IsAnonymous: false } field:
                owner.Members.Add(new Entry(
                    field.Name,
                    $"{Render(field.Type)} {field.Name}",
                    field.Documentation,
                    Locate(unit, field.Span))
                { Kind = "field" });
                break;

            case GlobalConstDeclSyntax constant:
                owner.Members.Add(new Entry(
                    constant.Name,
                    Constant(constant),
                    constant.Documentation,
                    Locate(unit, constant.Span))
                { Kind = "constant" });
                break;

            case EnumDeclSyntax nested:
                owner.Members.Add(DescribeEnum(nested, unit));
                break;

            case TypeDeclSyntax nested:
                owner.Members.Add(DescribeType(nested, unit));
                break;
        }
    }

    private static Entry DescribeFunction(
        FunctionDeclSyntax function, CompilationUnitSyntax unit, string? typeName = null)
    {
        var signature = new StringBuilder();

        if (function.Modifiers.HasFlag(Modifiers.Static)) signature.Append("static ");
        if (function.Modifiers.HasFlag(Modifiers.Abstract)) signature.Append("abstract ");
        else if (function.Modifiers.HasFlag(Modifiers.Override)) signature.Append("override ");
        else if (function.Modifiers.HasFlag(Modifiers.Virtual)) signature.Append("virtual ");

        // A constructor is the type's name with no return type, and a
        // destructor is that with a tilde. Both read wrong with `void` in front.
        bool isConstructor = typeName is not null && function.Name == typeName;
        bool isDestructor = function.Name.StartsWith('~');

        if (!isConstructor && !isDestructor)
            signature.Append(Render(function.ReturnType)).Append(' ');

        string name = function.IsOperator
            ? "operator " + OperatorText(function.OperatorToken)
            : function.Name;

        signature.Append(name).Append(Parameters(function.TypeParameters));

        var written = function.Parameters.Select(Render).ToList();
        if (function.IsVariadic) written.Add("...");
        signature.Append('(').Append(string.Join(", ", written)).Append(')');

        foreach (var clause in function.Constraints)
            signature.Append("\n    where ").Append(clause.TypeParameter).Append(" : ")
                     .Append(string.Join(", ", clause.Constraints.Select(Render)));

        string kind = isConstructor ? "constructor"
            : isDestructor ? "destructor"
            : function.IsOperator ? "operator"
            : typeName is null ? "function" : "method";

        return new Entry(name, signature.ToString(), function.Documentation,
                         Locate(unit, function.Span))
        { Kind = kind };
    }

    private static Entry DescribeProperty(PropertyDeclSyntax property, CompilationUnitSyntax unit)
    {
        var signature = new StringBuilder();
        if (property.Modifiers.HasFlag(Modifiers.Static)) signature.Append("static ");

        signature.Append(Render(property.Type)).Append(' ');

        if (property.IsIndexer)
            signature.Append("this[")
                     .Append(string.Join(", ", property.Indices.Select(Render)))
                     .Append(']');
        else
            signature.Append(property.Name);

        // What a caller can do with it, which is the whole of what the accessor
        // list means from outside: a setter that is not public is not there.
        var accessors = new List<string>();
        foreach (var accessor in property.Accessors)
        {
            bool isSetter = !accessor.IsGetter;
            if (isSetter && accessor.Modifiers.HasFlag(Modifiers.Private)) continue;
            accessors.Add(isSetter ? "set;" : "get;");
        }

        signature.Append(" { ").Append(string.Join(" ", accessors)).Append(" }");

        return new Entry(
            property.IsIndexer ? "this[]" : property.Name,
            signature.ToString(),
            property.Documentation,
            Locate(unit, property.Span))
        { Kind = property.IsIndexer ? "indexer" : "property" };
    }

    private static Entry DescribeEnum(EnumDeclSyntax enumeration, CompilationUnitSyntax unit)
    {
        string underlying = enumeration.UnderlyingType is null
            ? ""
            : " : " + Render(enumeration.UnderlyingType);

        var entry = new Entry(
            enumeration.Name,
            $"enum {enumeration.Name}{underlying}",
            enumeration.Documentation,
            Locate(unit, enumeration.Span))
        { Kind = "enum" };

        foreach (var member in enumeration.Members)
            entry.Members.Add(new Entry(
                member.Name,
                member.Value is null ? member.Name : $"{member.Name} = {Render(member.Value)}",
                member.Documentation,
                Locate(unit, member.Span))
            { Kind = "case" });

        return entry;
    }

    private static Entry DescribeDelegate(DelegateDeclSyntax handler, CompilationUnitSyntax unit)
    {
        string keyword = handler.CarriesReceiver ? "closure" : "delegate";

        string signature =
            $"{keyword} {Render(handler.ReturnType)} {handler.Name}" +
            Parameters(handler.TypeParameters) +
            $"({string.Join(", ", handler.Parameters.Select(Render))})";

        return new Entry(
            handler.Name + Parameters(handler.TypeParameters),
            signature,
            handler.Documentation,
            Locate(unit, handler.Span))
        { Kind = keyword };
    }

    // ============================================================ rendering

    private static string Parameters(IReadOnlyList<string>? names) =>
        names is null || names.Count == 0 ? "" : "<" + string.Join(", ", names) + ">";

    private static string Render(ParameterSyntax parameter)
    {
        string mode = parameter.Mode switch
        {
            ParameterMode.Ref => "ref ",
            ParameterMode.In => "in ",
            ParameterMode.Out => "out ",
            _ => "",
        };
        return $"{mode}{Render(parameter.Type)} {parameter.Name}";
    }

    private static string Render(TypeSyntax type) => type switch
    {
        PrimitiveTypeSyntax primitive => Spell(primitive.Keyword),
        NamedTypeSyntax named =>
            string.Join(".", named.Name.Parts) +
            (named.TypeArguments.Count == 0
                ? ""
                : "<" + string.Join(", ", named.TypeArguments.Select(Render)) + ">"),
        PointerTypeSyntax pointer => Render(pointer.Element) + "*",
        ArrayTypeSyntax array => Render(array.Element) + "[]",
        SliceTypeSyntax slice => Render(slice.Element) + "[:]",
        FixedArrayTypeSyntax fixedArray =>
            Render(fixedArray.Element) + "[" + Render(fixedArray.Length) + "]",
        NullableTypeSyntax nullable => Render(nullable.Element) + "?",
        WeakTypeSyntax weak => "weak " + Render(weak.Element),
        TupleTypeSyntax tuple => "(" + string.Join(", ", tuple.Elements.Select(Render)) + ")",
        _ => "?",
    };

    /// <summary>
    /// A constant's value as it was written, for the few shapes a constant
    /// actually takes. Anything else is elided rather than half-rendered: a
    /// documentation page saying <c>= ?</c> is more use than one saying
    /// something that is not what the source says.
    /// </summary>
    private static string Render(ExpressionSyntax expression) => expression switch
    {
        LiteralSyntax { Value: string text } => "\"" + text + "\"",
        LiteralSyntax { Value: bool flag } => flag ? "true" : "false",
        LiteralSyntax { Value: { } value } => value.ToString() ?? "…",
        NameSyntax name => string.Join(".", name.Name.Parts),
        MemberAccessSyntax access => Render(access.Target) + "." + access.Member,
        UnarySyntax unary => Spell(unary.Operator) + Render(unary.Operand),
        BinarySyntax binary =>
            Render(binary.Left) + " " + Spell(binary.Operator) + " " + Render(binary.Right),
        CastSyntax cast => "(" + Render(cast.Type) + ")" + Render(cast.Operand),
        _ => "…",
    };

    /// <summary>
    /// A token as it is written. Every token this reaches has fixed text -- an
    /// operator, a keyword, a piece of punctuation -- so the fallback is for a
    /// shape that should not get here rather than for one that does.
    /// </summary>
    private static string Spell(TokenKind token) => token.FixedText() ?? token.ToString();

    private static string OperatorText(TokenKind token) => Spell(token);

    /// <summary>
    /// One constraint after the colon. A <c>where T : class</c> names a kind
    /// rather than a type, which is why the type may be absent.
    /// </summary>
    private static string Render(ConstraintSyntax constraint) =>
        constraint.Type is { } type ? Render(type) : constraint.Kind.ToString().ToLowerInvariant();

    private static SourceLocation? Locate(CompilationUnitSyntax unit, Source.SourceSpan span)
    {
        string? path = unit.File.Path;
        if (string.IsNullOrEmpty(path)) return null;

        // One-based, because that is what an editor and a code host both count
        // in and a link that is off by one lands on the line above.
        int line = 1;
        string text = unit.File.Text;
        for (int i = 0; i < span.Start && i < text.Length; i++)
            if (text[i] == '\n') line++;

        return new SourceLocation(path, line);
    }

    // ================================================================ pages

    private static string Page(Module module, string? sourceRoot)
    {
        var page = new StringBuilder();

        page.Append("# ").Append(module.Name).Append("\n\n");
        page.Append(Generated()).Append("\n\n");

        if (module.Documentation is not null) WriteBlock(page, module.Documentation);

        // A contents list, because these pages are long and a module's shape is
        // the first thing to want. Left out where there is nothing to list.
        var sections = new (string Title, List<Entry> Entries)[]
        {
            ("Types", module.Types),
            ("Functions", module.Functions),
            ("Constants", module.Constants),
        };

        if (sections.Sum(s => s.Entries.Count) > 1)
        {
            page.Append("## Contents\n\n");
            foreach (var (title, entries) in sections)
            {
                if (entries.Count == 0) continue;
                page.Append("**").Append(title).Append("** &nbsp; ");
                page.Append(string.Join(" &middot; ", entries
                    .OrderBy(e => e.Name, StringComparer.Ordinal)
                    .Select(e => $"[{Escape(e.Name)}](#{Anchor(e)})")));
                page.Append("\n\n");
            }
        }

        foreach (var (title, entries) in sections)
        {
            if (entries.Count == 0) continue;

            page.Append("## ").Append(title).Append("\n\n");
            foreach (var entry in entries.OrderBy(e => e.Name, StringComparer.Ordinal))
                WriteEntry(page, entry, sourceRoot, depth: 3);
        }

        return page.ToString();
    }

    private static void WriteEntry(
        StringBuilder page, Entry entry, string? sourceRoot, int depth, Entry? owner = null)
    {
        page.Append(new string('#', depth)).Append(' ').Append(Escape(entry.Name));
        if (entry.Kind.Length > 0) page.Append(" *").Append(entry.Kind).Append('*');
        page.Append("\n\n");

        page.Append("```\n").Append(entry.Signature).Append("\n```\n\n");

        if (entry.Documentation is not null)
            WriteBlock(page, entry.Documentation, owner: owner, member: entry.Name);
        else
            // Said rather than left blank. A page that is silent about a member
            // looks the same whether the member needs no explanation or nobody
            // wrote one, and those are not the same thing.
            page.Append("*No documentation.*\n\n");

        if (entry.Where is { } where && Link(where, sourceRoot) is { } link)
            page.Append(link).Append("\n\n");

        foreach (var member in entry.Members)
            WriteEntry(page, member, sourceRoot, Math.Min(depth + 1, 6), owner: entry);
    }

    private static string? Link(SourceLocation where, string? sourceRoot)
    {
        if (sourceRoot is null) return null;

        // The standard library is compiled from the compiler's own resources,
        // so its files carry a label where a path would be. Rewriting it to
        // where those files really live is what makes the link point at
        // something.
        string file = where.File;
        if (_rewrite is { } rewrite && file.StartsWith(rewrite.From, StringComparison.Ordinal))
            file = Path.Combine(sourceRoot, rewrite.To + file[rewrite.From.Length..]);

        string shown, href;
        try
        {
            shown = Path.GetRelativePath(sourceRoot, file).Replace('\\', '/');

            // Relative to where the page will be read from, not to the root --
            // the depth of the output directory is the caller's choice, and a
            // link with the wrong number of '..' in it is a link to nothing.
            href = Path.GetRelativePath(_output, file).Replace('\\', '/');
        }
        catch (ArgumentException)
        {
            return null;
        }

        // A source outside the root is one this page has no stable way to point
        // at: the path would be this machine's rather than the repository's.
        if (shown.StartsWith("..", StringComparison.Ordinal)) return null;

        return $"<sub>[{shown}:{where.Line}]({href}#L{where.Line})</sub>";
    }

    private static string Index(IReadOnlyList<Module> modules)
    {
        var page = new StringBuilder();

        page.Append("# The Stainless standard library\n\n");
        page.Append(Generated()).Append("\n\n");
        page.Append("One page per module. Each lists every public type, function, ")
            .Append("property, case and constant the module declares, with the ")
            .Append("signature as it is written in the source.\n\n");

        page.Append("| Module | |\n|---|---|\n");
        foreach (var module in modules)
        {
            page.Append("| [").Append(module.Name).Append("](")
                .Append(FileNameOf(module.Name)).Append(") | ");
            page.Append(Summary(module.Documentation)).Append(" |\n");
        }

        return page.ToString();
    }

    /// <summary>
    /// The first sentence of a block, for a table cell. Pipes are escaped, or a
    /// sentence with one in it would end the cell early.
    /// </summary>
    private static string Summary(string? documentation)
    {
        if (documentation is null) return "";

        string first = documentation.Split('\n')[0].Trim();
        return first.Replace("|", "\\|");
    }

    private static string Generated() =>
        "<sub>Generated from the `///` blocks in the source by `stainless doc`. " +
        "Edit the source, not this file.</sub>";

    private static string FileNameOf(string module) => module.Replace('.', '-') + ".md";

    /// <summary>
    /// The anchor GitHub will give this entry's heading.
    ///
    /// It has to be computed from the whole heading and not from the name,
    /// because <see cref="WriteEntry"/> writes the kind after it: the heading
    /// for <c>HexDigit</c> is <c>### HexDigit *function*</c>, which GitHub
    /// anchors as <c>hexdigit-function</c>. Anchoring the name alone produced
    /// <c>#hexdigit</c> and every contents link on every page missed.
    /// </summary>
    private static string Anchor(Entry entry) =>
        Anchor(entry.Kind.Length > 0 ? $"{entry.Name} {entry.Kind}" : entry.Name);

    /// <summary>
    /// A GitHub-flavoured heading anchor, taken over a heading's *rendered*
    /// text: lowercased, everything but a letter, digit, hyphen or underscore
    /// dropped, spaces hyphenated. Generic parameters make this worth doing
    /// rather than guessing -- <c>Dictionary&lt;K, V&gt;</c> becomes
    /// <c>dictionaryk-v</c>.
    ///
    /// There is deliberately no trimming, because GitHub does not trim either:
    /// a heading ending in punctuation after a space keeps a trailing hyphen.
    /// </summary>
    private static string Anchor(string heading)
    {
        var anchor = new StringBuilder();
        foreach (char c in heading.ToLowerInvariant())
        {
            if (char.IsLetterOrDigit(c) || c == '-' || c == '_') anchor.Append(c);
            else if (c == ' ') anchor.Append('-');
        }
        return anchor.ToString();
    }

    /// <summary>
    /// A block as Markdown. The text is already Markdown -- the standard library
    /// writes backticks, bold and indented code in these blocks -- so this only
    /// escapes what would otherwise be read as a heading of the page rather than
    /// of the block.
    /// </summary>
    private static string Prose(string documentation) => documentation.TrimEnd();

    /// <summary>
    /// Where a name written in a <c>@see</c> is documented: the page and the
    /// heading on it.
    ///
    /// A name is indexed under every spelling that reaches it -- <c>Substring</c>,
    /// <c>String.Substring</c> and <c>Standard.Text.String.Substring</c> are
    /// one entry -- because a block writes the shortest one that is clear where
    /// it stands. A spelling two things answer to is left out rather than
    /// pointed at one of them: an ambiguous link is worse than none, since a
    /// reader cannot see it went somewhere else.
    /// </summary>
    private static readonly Dictionary<string, string> s_links = new(StringComparer.Ordinal);

    /// <summary>Spellings that reach more than one thing, and so link nowhere.</summary>
    private static readonly HashSet<string> s_ambiguous = new(StringComparer.Ordinal);

    /// <summary>
    /// The block each spelling documents, which is what <c>@inheritdoc</c>
    /// copies.
    /// </summary>
    private static readonly Dictionary<string, Entry> s_entries = new(StringComparer.Ordinal);

    /// <summary>The page being written, so a link to something on it is just an anchor.</summary>
    private static string _page = "";

    private static void IndexLinkTargets(List<Module> modules)
    {
        s_links.Clear();
        s_ambiguous.Clear();
        s_entries.Clear();

        foreach (var module in modules)
        {
            string page = FileNameOf(module.Name);

            Note(module.Name, page);

            // A file that imports `Standard.Json` reaches it as `Json`, so a
            // block writes `Json.Parse` and that is the spelling to index --
            // alongside the written-out one, which is what a block in another
            // module with a name of its own has to write.
            string shortName = module.Name[(module.Name.LastIndexOf('.') + 1)..];

            foreach (var entry in module.Types.Concat(module.Functions).Concat(module.Constants))
            {
                string target = page + "#" + Anchor(entry);

                Note(entry.Name, target, entry);
                Note(module.Name + "." + entry.Name, target, entry);
                Note(shortName + "." + entry.Name, target, entry);

                foreach (var member in entry.Members)
                {
                    string inner = page + "#" + Anchor(member);

                    Note(entry.Name + "." + member.Name, inner, member);
                    Note(module.Name + "." + entry.Name + "." + member.Name, inner, member);
                    Note(shortName + "." + entry.Name + "." + member.Name, inner, member);
                }
            }
        }
    }

    /// <summary>
    /// Records one spelling. A second thing answering to it makes the spelling
    /// ambiguous, and an overload does not -- two <c>FromInteger</c>s are one
    /// name a reader is following, and both are on the same page.
    /// </summary>
    private static void Note(string spelling, string target, Entry? entry = null)
    {
        if (s_links.TryGetValue(spelling, out string? already))
        {
            if (already != target) s_ambiguous.Add(spelling);
            return;
        }

        s_links[spelling] = target;
        if (entry is not null) s_entries[spelling] = entry;
    }

    /// <summary>
    /// A name as a link to where it is documented, or as code when nothing here
    /// documents it -- a type from another library, or one that is not public.
    /// </summary>
    private static string Pointer(string name)
    {
        if (s_ambiguous.Contains(name) || !s_links.TryGetValue(name, out string? target))
            return $"`{name}`";

        // On this page it is an anchor and nothing more, which is what the
        // contents list at the top already writes.
        if (target.StartsWith(_page + "#", StringComparison.Ordinal))
            target = target[_page.Length..];

        return $"[{Escape(name)}]({target})";
    }

    /// <summary>
    /// A <c>///</c> block as a page reads it: the summary, then a section per
    /// kind of tag, in the order a reader wants them -- what it takes, what it
    /// answers, how it fails, then the asides.
    ///
    /// <para>
    /// A block with no tags is its summary and nothing else, so a page of
    /// untagged blocks is exactly what it was before tags existed.
    /// </para>
    /// </summary>
    private static void WriteBlock(
        StringBuilder page, string documentation, int depth = 0,
        Entry? owner = null, string? member = null)
    {
        var read = DocComment.Parse(documentation);

        // `@inheritdoc` is the block it points at, written here. Following one
        // that itself inherits is fine and a ring is cut: the page has to be
        // written either way.
        if (read.FirstOfKind(DocTagKind.InheritDoc) is { } inherit && depth < 4 &&
            Inherited(inherit.Name, owner, member) is { } borrowed)
        {
            WriteBlock(page, borrowed, depth + 1);

            // What the overriding member adds is written after what it
            // inherited, which is the order a reader needs: the general first,
            // then what is different here. A block that opens with the tag has
            // its prose under it rather than before it, so both are written.
            if (read.Summary.Length > 0) page.Append(Prose(read.Summary)).Append("\n\n");
            if (inherit.Text.Length > 0) page.Append(Prose(inherit.Text)).Append("\n\n");
            return;
        }

        if (read.Summary.Length > 0) page.Append(Prose(read.Summary)).Append("\n\n");

        if (read.Tags.Count == 0) return;

        Section(page, "Parameters", read.OfKind(DocTagKind.Param));
        Section(page, "Type parameters", read.OfKind(DocTagKind.TypeParam));

        Sentence(page, "Returns", read.FirstOfKind(DocTagKind.Returns));
        Sentence(page, "Value", read.FirstOfKind(DocTagKind.Value));

        Section(page, "Fails with", read.OfKind(DocTagKind.Failure));

        foreach (var remark in read.OfKind(DocTagKind.Remarks))
            page.Append(Prose(remark.Text)).Append("\n\n");

        foreach (var example in read.OfKind(DocTagKind.Example))
            page.Append("**Example**\n\n").Append(Prose(example.Text)).Append("\n\n");

        var pointers = read.OfKind(DocTagKind.See)
            .Concat(read.OfKind(DocTagKind.SeeAlso))
            .Select(t => t.Name)
            .Where(n => n is not null)
            .ToList();

        if (pointers.Count > 0)
            page.Append("**See also** &nbsp; ")
                .Append(string.Join(" &middot; ", pointers.Select(n => Pointer(n!))))
                .Append("\n\n");
    }

    /// <summary>
    /// The block an <c>@inheritdoc</c> takes, or null when there is none to
    /// take.
    ///
    /// Named, it is whatever that name documents. Bare, it is the member of
    /// the same name on something the owner was declared with -- which is
    /// where an override's documentation lives, and the case the tag exists
    /// for.
    /// </summary>
    private static string? Inherited(string? cref, Entry? owner, string? member)
    {
        if (cref is not null)
            return s_entries.TryGetValue(cref, out var named) ? named.Documentation : null;

        if (owner is null || member is null) return null;

        foreach (string above in owner.Inherits)
            if (s_entries.TryGetValue(above + "." + member, out var found) &&
                found.Documentation is { } block)
                return block;

        return null;
    }

    /// <summary>
    /// A titled list, one entry per tag: the name it is about, then its prose.
    /// A list rather than a table because a description is a sentence and
    /// wraps, and a Markdown table cell cannot.
    /// </summary>
    private static void Section(StringBuilder page, string title, IEnumerable<DocTag> tags)
    {
        var written = tags.ToList();
        if (written.Count == 0) return;

        page.Append("**").Append(title).Append("**\n\n");

        foreach (var tag in written)
        {
            page.Append("- ");

            // A failure names a case of an error type, which is documented and
            // so is worth linking; a parameter is a name in the signature above
            // and links nowhere.
            if (tag.Name is not null)
                page.Append(tag.Kind == DocTagKind.Failure
                    ? Pointer(tag.Name)
                    : "`" + tag.Name + "`").Append(" — ");

            page.Append(OneLine(tag.Text)).Append('\n');
        }

        page.Append('\n');
    }

    /// <summary>A titled sentence: what a call answers, or what a property holds.</summary>
    private static void Sentence(StringBuilder page, string title, DocTag? tag)
    {
        if (tag is null || tag.Text.Length == 0) return;

        page.Append("**").Append(title).Append("** &nbsp; ").Append(OneLine(tag.Text))
            .Append("\n\n");
    }

    /// <summary>
    /// A tag's text as one line, since it stands inside a list item or after a
    /// bold lead-in. A blank line inside one would end the item it is part of.
    /// </summary>
    private static string OneLine(string text) =>
        string.Join(" ", text.Split('\n')
            .Select(line => line.Trim())
            .Where(line => line.Length > 0));

    /// <summary>
    /// A name in a heading. The angle brackets of a generic are the only thing
    /// here that Markdown would read as markup.
    /// </summary>
    private static string Escape(string name) =>
        name.Replace("<", "&lt;").Replace(">", "&gt;");
}
