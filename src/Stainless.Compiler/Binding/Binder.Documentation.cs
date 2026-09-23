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
using Stainless.Syntax;

namespace Stainless.Binding;

/// <summary>
/// Checking the <c>@tags</c> in a <c>///</c> block against what they document.
///
/// <para>
/// <b>A tag is a claim about the declaration under it</b> -- that it has a
/// parameter of that name, that it can fail that way, that the type it points
/// at exists -- and every one of those claims is one the compiler has already
/// resolved for itself. Checking them is what separates documentation that is
/// kept true from documentation that is merely present.
/// </para>
///
/// <para>
/// <b>They are warnings and not errors.</b> A mistake in a block is a mistake
/// in prose: worth reporting where it was written, never worth refusing the
/// program over.
/// </para>
///
/// <para>
/// This is a pass of its own, run last, because a <c>cref</c> may name
/// anything in the program and nothing is fully known until the rest is done.
/// </para>
/// </summary>
public sealed partial class Binder
{
    // ============================================================ the pass

    private void CheckDocumentation()
    {
        foreach (var (scope, unit) in _units)
        {
            _currentScope = scope;

            Check(unit.Documentation, unit.DocumentationSpan, unit.Span,
                new Documented($"module {unit.ModuleName?.Text ?? scope.Module.Name}",
                    DocumentedKind.Module));

            foreach (var declaration in unit.Declarations)
                CheckDeclaration(declaration);
        }

        _currentScope = null;
    }

    /// <summary>
    /// The type whose members are being checked, so that a name written bare
    /// in one of their blocks resolves the way it would in the code beside it.
    /// </summary>
    private NamedTypeSymbol? _documentedType;

    /// <summary>The symbol a type declaration made, or null where it is not one.</summary>
    private NamedTypeSymbol? TypeDeclared(TypeDeclSyntax type) =>
        _currentScope!.Module.Types.TryGetValue(type.Name, out var declared)
            ? declared as NamedTypeSymbol
            : null;

    /// <summary>What a block is written above, and what may be said about it.</summary>
    private enum DocumentedKind
    {
        Module,
        Type,
        Function,
        Property,
        Storage,
        Case,
    }

    /// <summary>
    /// The declaration a block documents, reduced to what a tag can be checked
    /// against: its name for the message, its parameters, and the return type
    /// a <c>@returns</c> or a <c>@failure</c> is about.
    /// </summary>
    private sealed record Documented(string Name, DocumentedKind Kind)
    {
        public IReadOnlyList<string> Parameters { get; init; } = [];
        public IReadOnlyList<string> TypeParameters { get; init; } = [];
        public TypeSyntax? Returns { get; init; }
    }

    // ====================================================== the declarations

    private void CheckDeclaration(Declaration declaration)
    {
        switch (declaration)
        {
            case FunctionDeclSyntax function:
                Check(function.Documentation, function.DocumentationSpan, function.Span,
                    new Documented(function.Name, DocumentedKind.Function)
                    {
                        Parameters = [.. function.Parameters.Select(p => p.Name)],
                        TypeParameters = function.TypeParameters,
                        Returns = function.ReturnType,
                    });
                break;

            case PropertyDeclSyntax property:
                Check(property.Documentation, property.DocumentationSpan, property.Span,
                    new Documented(property.Name, DocumentedKind.Property)
                    {
                        Parameters = [.. property.Indices.Select(i => i.Name)],
                        Returns = property.Type,
                    });
                break;

            case ConstructorDeclSyntax constructor:
                Check(constructor.Documentation, constructor.DocumentationSpan, constructor.Span,
                    new Documented(constructor.TypeName, DocumentedKind.Function)
                    {
                        Parameters = [.. constructor.Parameters.Select(p => p.Name)],
                    });
                break;

            case DelegateDeclSyntax handler:
                Check(handler.Documentation, handler.DocumentationSpan, handler.Span,
                    new Documented(handler.Name, DocumentedKind.Function)
                    {
                        Parameters = [.. handler.Parameters.Select(p => p.Name)],
                        TypeParameters = handler.TypeParameters,
                        Returns = handler.ReturnType,
                    });
                break;

            case TypeDeclSyntax type:
            {
                var outer = _documentedType;
                _documentedType = TypeDeclared(type);

                Check(type.Documentation, type.DocumentationSpan, type.Span,
                    new Documented(type.Name, DocumentedKind.Type)
                    {
                        TypeParameters = type.TypeParameters,
                    });

                foreach (var member in type.Members)
                    CheckDeclaration(member);

                foreach (var variantCase in type.Cases)
                    Check(variantCase.Documentation, variantCase.DocumentationSpan,
                        variantCase.Span, new Documented(variantCase.Name, DocumentedKind.Case));

                _documentedType = outer;
                break;
            }

            case EnumDeclSyntax enumeration:
            {
                Check(enumeration.Documentation, enumeration.DocumentationSpan, enumeration.Span,
                    new Documented(enumeration.Name, DocumentedKind.Type));

                foreach (var member in enumeration.Members)
                    Check(member.Documentation, member.DocumentationSpan, member.Span,
                        new Documented(member.Name, DocumentedKind.Case));
                break;
            }

            case FieldDeclSyntax field:
                Check(field.Documentation, field.DocumentationSpan, field.Span,
                    new Documented(field.Name, DocumentedKind.Storage) { Returns = field.Type });
                break;

            case StaticDeclSyntax shared:
                Check(shared.Documentation, shared.DocumentationSpan, shared.Span,
                    new Documented(shared.Name, DocumentedKind.Storage) { Returns = shared.Type });
                break;

            case GlobalConstDeclSyntax constant:
                Check(constant.Documentation, constant.DocumentationSpan, constant.Span,
                    new Documented(constant.Name, DocumentedKind.Storage));
                break;

            case AliasDeclSyntax alias:
                Check(alias.Documentation, alias.DocumentationSpan, alias.Span,
                    new Documented(alias.Name, DocumentedKind.Type));
                break;

            case EventDeclSyntax declared:
                Check(declared.Documentation, declared.DocumentationSpan, declared.Span,
                    new Documented(declared.Name, DocumentedKind.Storage));
                break;
        }
    }

    // =========================================================== the checks

    private void Check(
        string? documentation, SourceSpan? block, SourceSpan declaration, Documented subject)
    {
        if (documentation is null) return;

        var read = DocComment.Parse(documentation, block);
        if (read.Tags.Count == 0) return;

        var documentedParameters = new Dictionary<string, SourceSpan?>(StringComparer.Ordinal);

        foreach (var tag in read.Tags)
        {
            var where = tag.Span ?? declaration;

            if (tag.Kind == DocTagKind.Unknown)
            {
                diagnostics.Warning("SL0739", where,
                    $"'@{tag.Word}' is not a tag{Instead(tag.Word)}");
                continue;
            }

            if (!Applies(tag.Kind, subject.Kind))
            {
                diagnostics.Warning("SL0743", where,
                    $"'@{tag.Word}' says nothing about {Describe(subject)}; " +
                    $"it belongs on {WhereItBelongs(tag.Kind)}");
                continue;
            }

            switch (tag.Kind)
            {
                case DocTagKind.Param:
                    CheckParameter(tag, where, subject, documentedParameters);
                    break;

                case DocTagKind.TypeParam:
                    if (tag.Name is null || !subject.TypeParameters.Contains(tag.Name))
                        diagnostics.Warning("SL0742", where,
                            $"'{subject.Name}' has no type parameter named " +
                            $"'{tag.Name ?? ""}'{Among(subject.TypeParameters)}");
                    break;

                case DocTagKind.Returns:
                    if (subject.Returns is PrimitiveTypeSyntax { Keyword: TokenKind.VoidKeyword })
                        diagnostics.Warning("SL0743", where,
                            $"'{subject.Name}' returns nothing, so there is nothing for " +
                            "'@returns' to describe");
                    break;

                case DocTagKind.Failure:
                    CheckFailure(tag, where, subject);
                    break;

                case DocTagKind.See:
                case DocTagKind.SeeAlso:
                case DocTagKind.InheritDoc:
                    CheckCref(tag, where);
                    break;
            }
        }

        CheckEveryParameterDocumented(read, declaration, subject, documentedParameters);
    }

    private void CheckParameter(
        DocTag tag, SourceSpan where, Documented subject,
        Dictionary<string, SourceSpan?> documented)
    {
        if (tag.Name is null || !subject.Parameters.Contains(tag.Name))
        {
            diagnostics.Warning("SL0740", where,
                $"'{subject.Name}' has no parameter named " +
                $"'{tag.Name ?? ""}'{Among(subject.Parameters)}");
            return;
        }

        if (!documented.TryAdd(tag.Name, tag.Span))
            diagnostics.Warning("SL0740", where,
                $"'{tag.Name}' is documented twice, and the second is what a reader would " +
                "have to notice is not the first");
    }

    /// <summary>
    /// A block that documents some parameters and not others, which is C#'s
    /// CS1573 and exists for the same reason: the missing one reads as an
    /// oversight, and nothing else says whether it is.
    /// </summary>
    private void CheckEveryParameterDocumented(
        DocComment read, SourceSpan declaration, Documented subject,
        Dictionary<string, SourceSpan?> documented)
    {
        if (documented.Count == 0 || documented.Count == subject.Parameters.Count) return;

        var missing = subject.Parameters.Where(p => !documented.ContainsKey(p)).ToList();
        if (missing.Count == 0) return;

        var where = read.FirstOfKind(DocTagKind.Param)?.Span ?? declaration;

        diagnostics.Warning("SL0741", where,
            $"'{subject.Name}' documents some of its parameters and not " +
            Listed(missing.Select(m => "'" + m + "'")) +
            "; document all of them or none");
    }

    /// <summary>
    /// <c>@failure</c> names an error a call can report, so it is checked
    /// against the error type the signature declares: a case that is not one of
    /// that type's is a failure that cannot happen.
    /// </summary>
    private void CheckFailure(DocTag tag, SourceSpan where, Documented subject)
    {
        if (ErrorTypeOf(subject.Returns) is not { } declared)
        {
            diagnostics.Warning("SL0744", where,
                $"'{subject.Name}' reports no failure, so there is nothing for '@failure' to " +
                "name; a call that can fail returns a 'Result' or the error itself");
            return;
        }

        if (tag.Name is null)
        {
            diagnostics.Warning("SL0744", where,
                "'@failure' names the error it is about, as in " +
                $"'@failure {declared.Name}.Something what went wrong'");
            return;
        }

        // The error type's own name may be written in front of the case, as the
        // language writes it everywhere else, or left off where it is obvious.
        string cased = tag.Name.StartsWith(declared.Name + ".", StringComparison.Ordinal)
            ? tag.Name[(declared.Name.Length + 1)..]
            : tag.Name;

        if (CaseNames(declared) is not { } cases) return;

        if (!cases.Contains(cased))
            diagnostics.Warning("SL0744", where,
                $"'{declared.Name}' has no case named '{cased}'{Among(cases)}");
    }

    private void CheckCref(DocTag tag, SourceSpan where)
    {
        // `@inheritdoc` with nothing after it takes the member it overrides,
        // which is not named and so is not a cref to check.
        if (tag.Name is null)
        {
            if (tag.Kind != DocTagKind.InheritDoc)
                diagnostics.Warning("SL0745", where,
                    $"'@{tag.Word}' names what it points at, and this one names nothing");
            return;
        }

        if (!Resolves(tag.Name))
            diagnostics.Warning("SL0745", where,
                $"'{tag.Name}' is not a type, a member or a module this file can see");
    }

    // ======================================================== what tags mean

    /// <summary>Whether a tag says anything about this kind of declaration.</summary>
    private static bool Applies(DocTagKind kind, DocumentedKind subject) => kind switch
    {
        DocTagKind.Param => subject is DocumentedKind.Function or DocumentedKind.Property,
        DocTagKind.TypeParam => subject is DocumentedKind.Function or DocumentedKind.Type,
        DocTagKind.Returns => subject is DocumentedKind.Function,
        DocTagKind.Value => subject is DocumentedKind.Property or DocumentedKind.Storage,
        DocTagKind.Failure => subject is DocumentedKind.Function or DocumentedKind.Property,
        DocTagKind.InheritDoc => subject is not DocumentedKind.Module,

        // Prose about anything at all.
        _ => true,
    };

    private static string WhereItBelongs(DocTagKind kind) => kind switch
    {
        DocTagKind.Param => "a function, or an indexer, that takes one",
        DocTagKind.TypeParam => "a generic function or type",
        DocTagKind.Returns => "a function that answers something",
        DocTagKind.Value => "a property or a field",
        DocTagKind.Failure => "something returning a 'Result'",
        DocTagKind.InheritDoc => "a member that has one to inherit",
        _ => "a declaration",
    };

    private static string Describe(Documented subject) => subject.Kind switch
    {
        DocumentedKind.Module => "a module",
        DocumentedKind.Type => $"the type '{subject.Name}'",
        DocumentedKind.Function => $"'{subject.Name}'",
        DocumentedKind.Property => $"the property '{subject.Name}'",
        DocumentedKind.Storage => $"'{subject.Name}'",
        _ => $"'{subject.Name}'",
    };

    /// <summary>The tag a near miss was reaching for, as a hint, or nothing.</summary>
    private static string Instead(string word) => word switch
    {
        "summary" => "; the prose before the first tag is the summary",
        "return" => "; the tag is '@returns'",
        "throws" or "throw" or "exception" =>
            "; nothing is thrown here, and a call that can fail returns a 'Result' " +
            "whose cases '@failure' documents",
        "typeParam" or "typeparameter" => "; the tag is '@typeparam'",
        "parameter" or "arg" or "argument" => "; the tag is '@param'",
        "code" or "sample" => "; the tag is '@example', and a sample is indented Markdown",
        _ => "",
    };

    // ====================================================== resolving a name

    /// <summary>
    /// The type whose cases a <c>@failure</c> can name, or null where the
    /// declaration reports no failure.
    ///
    /// <para>
    /// There are two shapes and both are failure. An operation that produces
    /// something returns <c>Result&lt;T, TError&gt;</c> and the cases are
    /// <c>TError</c>'s; an operation that produces nothing returns the error
    /// itself, with <c>None</c> for success, which is what most of
    /// <c>Standard.File</c> does. Taking only the first would refuse the tag
    /// on exactly the calls that most need it.
    /// </para>
    ///
    /// <para>
    /// Read from the syntax rather than from the bound signature, because that
    /// is what the author wrote and what the message should quote.
    /// </para>
    /// </summary>
    private TypeSymbol? ErrorTypeOf(TypeSyntax? returns)
    {
        if (returns is not NamedTypeSyntax named) return null;

        var written = named.Name.Parts[^1] == "Result" && named.TypeArguments.Count == 2
            ? ResolveType(named.TypeArguments[1], _currentScope!)
            : ResolveType(named, _currentScope!);

        // A variant carries its cases and an enum is a set of them. Anything
        // else -- a String, a number -- is a value rather than a report.
        return written.IsError() || written is not (EnumTypeSymbol or VariantTypeSymbol)
            ? null
            : written;
    }

    /// <summary>The names of an enum's members or a variant's cases, or null.</summary>
    private static IReadOnlyList<string>? CaseNames(TypeSymbol type) => type switch
    {
        EnumTypeSymbol enumeration => [.. enumeration.Members.Select(m => m.Name)],
        VariantTypeSymbol variant => [.. variant.Cases.Select(c => c.Name)],
        _ => null,
    };

    /// <summary>
    /// Whether a <c>cref</c> names something: a type, a module, or a member of
    /// either.
    ///
    /// It asks the same questions an expression would and in the same order, so
    /// a name that works in code works here. What it does not do is choose
    /// between overloads -- <c>Text.FromInteger</c> names all three of them,
    /// which is what a reader following the link wants.
    /// </summary>
    private bool Resolves(string cref)
    {
        var parts = cref.Split('.', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0) return false;

        if (TypeNamed(parts) is not null) return true;
        if (ModuleNamed(parts) is not null) return true;

        var here = _currentScope!.Module;

        // A name in this module's own file may be written as a caller would
        // write it from outside -- `File.ReadAllText`, under the short name the
        // module is reached by -- or bare, as the code beside it writes it.
        // Both are the name a reader would use, so both resolve.
        if (parts.Length == 1 && HasModuleMember(here, parts[0])) return true;

        if (parts.Length == 2 && parts[0] == ShortName(here.Name) &&
            HasModuleMember(here, parts[1]))
            return true;

        // A member of the type the block is written inside, named on its own.
        if (parts.Length == 1 && _documentedType is { } enclosing &&
            HasMember(enclosing, parts[0]))
            return true;

        if (parts.Length < 2) return false;

        var owner = parts[..^1];
        string member = parts[^1];

        if (TypeNamed(owner) is { } type && HasMember(type, member)) return true;

        return ModuleNamed(owner) is { } module && HasModuleMember(module, member);
    }

    /// <summary>The last segment of a dotted module name, which is how a file that
    /// imports it reaches it.</summary>
    private static string ShortName(string module) => module[(module.LastIndexOf('.') + 1)..];

    /// <summary>
    /// Whether a module declares something of this name.
    ///
    /// A generic function is a template until a call says what its parameters
    /// are, so it is not among the ordinary functions -- and `Xml.Serialize` is
    /// exactly the sort of name a block points at.
    /// </summary>
    private static bool HasModuleMember(ModuleSymbol module, string member) =>
        module.Functions.Any(f => f.Name == member) ||
        module.GenericFunctions.Any(f => f.Name == member) ||
        module.Types.ContainsKey(member) ||
        module.GenericTypes.ContainsKey(member) ||
        module.GenericDelegates.ContainsKey(member) ||
        module.Aliases.ContainsKey(member) ||
        module.Constants.ContainsKey(member) ||
        module.Statics.ContainsKey(member);

    private ModuleSymbol? ModuleNamed(IReadOnlyList<string> parts)
    {
        string name = string.Join('.', parts);

        if (_currentScope!.Imports.TryGetValue(name, out var imported)) return imported;
        return _modules.TryGetValue(name, out var known) ? known : null;
    }

    private static bool HasMember(TypeSymbol owner, string member)
    {
        if (owner is not NamedTypeSymbol named) return false;

        if (named.FindMethods(member).Any()) return true;
        if (named.FindProperty(member) is not null) return true;
        if (named.FindStorage(member) is not null) return true;
        if (named.FindStatic(member) is not null) return true;
        if (named.FindConstant(member) is not null) return true;
        if (named.Events.Any(e => e.Name == member)) return true;
        if (named.GenericMethods.Any(m => m.Name == member)) return true;

        return CaseNames(named)?.Contains(member) == true;
    }

    /// <summary>The names a mistake could have meant, where there are few enough to say.</summary>
    private static string Among(IReadOnlyList<string> names) => names.Count switch
    {
        0 => "; it takes none",
        _ => "; it has " + Listed(names.Select(n => "'" + n + "'")),
    };
}
