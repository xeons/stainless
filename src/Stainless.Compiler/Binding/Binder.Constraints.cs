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
/// Whether a template's <c>where</c> clauses make sense on their own.
///
/// A constraint is verified against a type argument where the template is
/// instantiated. What is checked here is the part that needs no argument: that
/// the clauses name the template's parameters once each, that each constraint
/// could be satisfied by something, and that no two contradict. A template
/// nobody instantiates is checked this far and no further.
/// </summary>
public sealed partial class Binder
{
    /// <summary>After pass 5, when every class knows whether it is sealed.</summary>
    private void CheckConstraintDeclarations()
    {
        foreach (var module in _modules.Values)
        {
            foreach (var template in module.GenericTypes.Values)
            {
                var declaration = template.Declaration;
                CheckWhereClauses(declaration.Constraints, declaration.TypeParameters, [],
                    template.Scope, $"'{template.Name}'", isOverride: false);

                foreach (var method in declaration.Members.OfType<FunctionDeclSyntax>()
                             .Where(m => m.TypeParameters.Count > 0))
                    CheckWhereClauses(method.Constraints, method.TypeParameters,
                        declaration.TypeParameters, template.Scope, $"'{method.Name}'",
                        method.Modifiers.HasFlag(Modifiers.Override));
            }

            foreach (var template in module.GenericFunctions.Where(f => f.Local is null))
                CheckWhereClauses(template.Declaration.Constraints, template.Parameters, [],
                    template.Scope, $"'{template.Name}'",
                    template.Declaration.Modifiers.HasFlag(Modifiers.Override));

            foreach (var type in module.Types.Values.Where(t => t.Template is null))
                foreach (var template in type.GenericMethods)
                    CheckWhereClauses(template.Declaration.Constraints, template.Parameters, [],
                        template.Scope, $"'{template.Name}'",
                        template.Declaration.Modifiers.HasFlag(Modifiers.Override));
        }
    }

    /// <param name="outer">
    /// The enclosing type's parameters, for a method of a generic type: in scope,
    /// so a constraint may mention them.
    /// </param>
    private void CheckWhereClauses(
        IReadOnlyList<WhereClauseSyntax> clauses, IReadOnlyList<string> parameters,
        IReadOnlyList<string> outer, FileScope scope, string owner, bool isOverride)
    {
        if (clauses.Count == 0) return;

        var inScope = new HashSet<string>(parameters.Concat(outer), StringComparer.Ordinal);
        var seen = new Dictionary<string, WhereClauseSyntax>(StringComparer.Ordinal);

        // Parameter to the parameters it is constrained to be, for the cycle.
        var edges = new Dictionary<string, List<(string To, SourceSpan Span)>>(StringComparer.Ordinal);

        foreach (var clause in clauses)
        {
            if (!inScope.Contains(clause.TypeParameter))
            {
                diagnostics.Error("SL0330", clause.Span,
                    $"'{clause.TypeParameter}' is not a type parameter of {owner}; " +
                    $"it declares {string.Join(", ", parameters.Select(p => "'" + p + "'"))}");
                continue;
            }

            if (seen.ContainsKey(clause.TypeParameter))
            {
                diagnostics.Error("SL0788", clause.Span,
                    $"'{clause.TypeParameter}' already has a 'where' clause in {owner}; write " +
                    "everything asked of one parameter in one clause, separated by commas");
                continue;
            }

            seen[clause.TypeParameter] = clause;

            if (!isOverride && clause.Constraints.Any(c => c.Kind == ConstraintKind.Default))
                diagnostics.Error("SL0792",
                    clause.Constraints.First(c => c.Kind == ConstraintKind.Default).Span,
                    $"'default' says '{clause.TypeParameter}' is unconstrained, which is what " +
                    "leaving the clause out already says; it is for an 'override', which " +
                    "otherwise takes its constraints from what it replaces");

            CheckClause(clause, inScope, scope, owner, edges);
        }

        ReportConstraintCycles(edges);
    }

    /// <summary>One clause: nothing twice, one class at most, and no contradiction.</summary>
    private void CheckClause(
        WhereClauseSyntax clause, HashSet<string> inScope, FileScope scope, string owner,
        Dictionary<string, List<(string To, SourceSpan Span)>> edges)
    {
        string parameter = clause.TypeParameter;
        var written = new List<string>();
        ConstraintSyntax? baseClass = null;
        var kind = clause.Constraints.FirstOrDefault(c => IsKindConstraint(c.Kind));

        foreach (var constraint in clause.Constraints)
        {
            string spelled = constraint.Type is { } shown
                ? SpellType(shown)
                : constraint.Kind.ToString();

            if (written.Contains(spelled))
            {
                diagnostics.Error("SL0789", constraint.Span,
                    $"'{parameter}' is already constrained to '{DisplayConstraint(constraint)}'");
                continue;
            }

            written.Add(spelled);
            if (constraint.Type is null) continue;

            // Another parameter: whatever it turns out to be, the argument has
            // to be that too. Only a cycle can be wrong here.
            if (constraint.Type is NamedTypeSyntax
                {
                    Name.Parts.Count: 1, TypeArguments.Count: 0,
                } named && inScope.Contains(named.Name.Parts[0]))
            {
                if (!edges.TryGetValue(parameter, out var list))
                    edges[parameter] = list = [];
                list.Add((named.Name.Parts[0], constraint.Span));
                continue;
            }

            switch (ConstraintTarget(constraint.Type, inScope, scope))
            {
                case ClassTypeSymbol { IsSealed: true } sealedClass:
                    diagnostics.Error("SL0329", constraint.Span,
                        $"'{sealedClass.Name}' cannot constrain '{parameter}': it is sealed, so " +
                        "the only type that could satisfy it is itself, and a parameter that can " +
                        $"only be one type is that type. Write '{sealedClass.Name}' instead",
                        sealedClass);
                    break;

                case ClassTypeSymbol or GenericTypeTemplate { Declaration.Kind: TypeDeclKind.Class }:
                    if (baseClass is not null)
                    {
                        diagnostics.Error("SL0790", constraint.Span,
                            $"'{parameter}' is already constrained to derive from " +
                            $"'{SpellType(baseClass.Type!)}', and a class has one base chain: " +
                            "constrain it to the more derived of the two");
                        break;
                    }

                    baseClass = constraint;
                    if (kind is { Kind: ConstraintKind.Struct or ConstraintKind.Unmanaged })
                        diagnostics.Error("SL0581", constraint.Span,
                            $"'{KindWord(kind.Kind)}' and a base class contradict each other: " +
                            $"only a class derives from '{SpellType(constraint.Type)}'");
                    break;

                case InterfaceTypeSymbol or GenericTypeTemplate { Declaration.Kind: TypeDeclKind.Interface }:
                    break;

                case TypeSymbol { } other when !other.IsError():
                    diagnostics.Error("SL0329", constraint.Span,
                        $"'{other.Name}' cannot constrain '{parameter}': a constraint is an " +
                        "interface to implement, a class to derive from, 'class', 'struct' or " +
                        $"'new()', and nothing derives from a {KindOf(other)}",
                        other);
                    break;

                case GenericTypeTemplate other:
                    diagnostics.Error("SL0329", constraint.Span,
                        $"'{other.Name}' cannot constrain '{parameter}': a constraint is an " +
                        "interface to implement or a class to derive from, and nothing derives " +
                        $"from a {other.Declaration.Kind.ToString().ToLowerInvariant()}");
                    break;
            }
        }
    }

    /// <summary>
    /// What a written constraint names: the type itself when it mentions no
    /// parameter, or the template when it does, since only an instantiation
    /// could say more. Null when it names nothing, which instantiation reports.
    /// </summary>
    private object? ConstraintTarget(TypeSyntax type, HashSet<string> inScope, FileScope scope)
    {
        if (type is NamedTypeSyntax { TypeArguments.Count: > 0 } constructed &&
            MentionsAny(type, inScope))
            return FindGenericType(constructed.Name, scope);

        if (MentionsAny(type, inScope)) return null;

        // Muted, because instantiation resolves it again and reports then.
        using (Enter(_context with { Substitution = new(StringComparer.Ordinal) }))
            return ResolveTypeQuietly(type, scope);
    }

    /// <summary>Whether a written type names any of these parameters, however deep.</summary>
    private static bool MentionsAny(TypeSyntax type, HashSet<string> names) => type switch
    {
        NamedTypeSyntax named =>
            (named.Name.Parts.Count == 1 && names.Contains(named.Name.Parts[0])) ||
            named.TypeArguments.Any(a => MentionsAny(a, names)),
        PointerTypeSyntax pointer => MentionsAny(pointer.Element, names),
        ArrayTypeSyntax array => MentionsAny(array.Element, names),
        SliceTypeSyntax slice => MentionsAny(slice.Element, names),
        FixedArrayTypeSyntax inline => MentionsAny(inline.Element, names),
        NullableTypeSyntax nullable => MentionsAny(nullable.Element, names),
        WeakTypeSyntax weak => MentionsAny(weak.Element, names),
        TupleTypeSyntax tuple => tuple.Elements.Any(e => MentionsAny(e, names)),
        _ => false,
    };

    /// <summary>
    /// <c>where T : U where U : T</c>: two parameters each required to be the
    /// other, which no pair of types is unless they are one.
    /// </summary>
    private void ReportConstraintCycles(Dictionary<string, List<(string To, SourceSpan Span)>> edges)
    {
        var reported = new HashSet<string>(StringComparer.Ordinal);

        foreach (var (start, _) in edges)
        {
            if (reported.Contains(start)) continue;

            var path = new List<string> { start };
            if (FindConstraintCycle(start, start, edges, path, []) is not { } closing) continue;

            foreach (string member in path) reported.Add(member);
            diagnostics.Error("SL0791", closing,
                $"the constraints on {string.Join(", ", path.Select(p => "'" + p + "'"))} " +
                "go round in a circle, so each would have to be the others; constrain one of " +
                "them to something that is not a parameter");
        }
    }

    private static SourceSpan? FindConstraintCycle(
        string start, string at, Dictionary<string, List<(string To, SourceSpan Span)>> edges,
        List<string> path, HashSet<string> visited)
    {
        if (!visited.Add(at) || !edges.TryGetValue(at, out var next)) return null;

        foreach (var (to, span) in next)
        {
            if (to == start) return span;

            path.Add(to);
            if (FindConstraintCycle(start, to, edges, path, visited) is { } found) return found;
            path.RemoveAt(path.Count - 1);
        }

        return null;
    }

    private static string DisplayConstraint(ConstraintSyntax constraint) =>
        constraint.Type is { } type ? SpellType(type) : KindWord(constraint.Kind);

    /// <summary>A written type as the source spelled it, for a message.</summary>
    private static string SpellType(TypeSyntax type) =>
        type.Span.File.Text[type.Span.Start..type.Span.End];

    private static bool IsKindConstraint(ConstraintKind kind) =>
        kind is ConstraintKind.Class or ConstraintKind.Struct or ConstraintKind.Unmanaged
            or ConstraintKind.NotNull or ConstraintKind.Default;

    private static string KindWord(ConstraintKind kind) => kind switch
    {
        ConstraintKind.Class => "class",
        ConstraintKind.Struct => "struct",
        ConstraintKind.Unmanaged => "unmanaged",
        ConstraintKind.NotNull => "notnull",
        ConstraintKind.Default => "default",
        ConstraintKind.New => "new()",
        _ => "threadsafe",
    };
}
