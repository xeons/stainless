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
using Stainless.Syntax;

namespace Stainless.Binding;

/// <summary>
/// Reaching into a value: a field, a property, a method group, a
/// variant's payload, and the two indirections -- a pointer and an
/// anonymous member -- that a name may cross without saying so.
/// </summary>
public sealed partial class Binder
{
    private BoundExpression BindMemberAccess(MemberAccessSyntax syntax)
    {
        // `Module.Member` is a qualified name, not a value access. A module,
        // a variant and an enum are all names, so `->` reaches none of them:
        // there is nothing there to be pointed at.
        if (!syntax.ThroughPointer && ResolveModulePrefix(syntax.Target) is { } importedModule)
        {
            if (importedModule.Constants.TryGetValue(syntax.Member, out var constant) && constant.IsPublic)
                return new BoundConstantAccess(syntax.Span, constant);

            if (importedModule.Statics.TryGetValue(syntax.Member, out var shared) && shared.IsPublic)
                return new BoundStaticAccess(syntax.Span, shared);

            diagnostics.Error("SL0246", syntax.Span,
                $"module '{importedModule.Name}' has no public member named '{syntax.Member}'");
            return new BoundErrorExpression(syntax.Span);
        }

        // `Shape.Empty` builds a variant whose case carries nothing. One that
        // does carry something is a call, and BindCall handles it.
        if (!syntax.ThroughPointer && ResolveVariantPrefix(syntax.Target) is { } variantType)
        {
            if (variantType.FindCase(syntax.Member) is not { } named)
            {
                diagnostics.Error("SL0435", syntax.Span,
                    $"variant '{variantType.Name}' has no case named '{syntax.Member}'; it has " +
                    Listed(variantType.Cases.Select(c => c.Name)));
                return new BoundErrorExpression(syntax.Span);
            }

            return BindVariantConstruction(variantType, named, [], syntax.Span);
        }

        // `Color.Red` names a constant of an enum type, not a member of a value.
        if (!syntax.ThroughPointer && ResolveEnumPrefix(syntax.Target) is { } enumType)
        {
            if (enumType.FindMember(syntax.Member) is { } member)
                return new BoundLiteral(syntax.Span, enumType, member.Value);

            diagnostics.Error("SL0355", syntax.Span,
                $"enum '{enumType.Name}' has no member named '{syntax.Member}'");
            return new BoundErrorExpression(syntax.Span);
        }

        var receiver = syntax.Target is BaseSyntax
            ? BindBaseReceiver(syntax.Target.Span)
            : BindExpression(syntax.Target);

        if (receiver is null || receiver.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        // An inline array's length was written in its type, so it is a constant
        // rather than a load -- and, unlike the other two, it never had to be
        // stored anywhere.
        if (receiver.Type is FixedArrayTypeSymbol inline)
        {
            if (syntax.Member == "Length")
                return new BoundLiteral(
                    syntax.Span, PrimitiveTypeSymbol.NUInt, (ulong)inline.Length);

            diagnostics.Error("SL0313", syntax.Span,
                $"'{inline.Name}' has no member named '{syntax.Member}'; " +
                "an inline array has only 'Length', and is indexed");
            return new BoundErrorExpression(syntax.Span);
        }

        // An array's only member is its length, which lives in the header; a
        // slice's is the one it carries, and it answers to the same name.
        if (receiver.Type is ArrayTypeSymbol or SliceTypeSymbol)
        {
            if (syntax.Member == "Length")
                return new BoundArrayLength(syntax.Span, PrimitiveTypeSymbol.NUInt, receiver);

            diagnostics.Error("SL0313", syntax.Span,
                $"'{receiver.Type.Name}' has no member named '{syntax.Member}'; " +
                (receiver.Type is SliceTypeSymbol
                    ? "a slice has only 'Length', and is indexed and sliced further"
                    : "an array has only 'Length'"));
            return new BoundErrorExpression(syntax.Span);
        }

        if (ReachThroughPointer(syntax, receiver) is not { } reachedThrough)
            return new BoundErrorExpression(syntax.Span);
        receiver = reachedThrough;

        if (receiver.Type is not NamedTypeSymbol && receiver.Type.AsClass() is null)
        {
            diagnostics.Error("SL0247", syntax.Span,
                $"'{receiver.Type.Name}' has no member named '{syntax.Member}'");
            return new BoundErrorExpression(syntax.Span);
        }

        var namedType = receiver.Type as NamedTypeSymbol ?? receiver.Type.AsClass()!;

        if (receiver.Type is OptionalTypeSymbol or WeakTypeSymbol)
        {
            // A weak reference may die between the check and the use, so no
            // check could establish anything about it. Reading it into a strong
            // optional is what makes it safe to look at, and is the only way.
            if (receiver.Type is WeakTypeSymbol weakReceiver)
                diagnostics.Error("SL0248", syntax.Span,
                    $"'{receiver.Type.Name}' may already have died, so checking it against " +
                    $"null would prove nothing about the moment after; read it into a " +
                    $"'{weakReceiver.Element.Name}?' first, and check that");

            // A check can only be about a name. Narrowing a field would prove
            // something about one evaluation and let it be read from another,
            // which is the rule variants already follow (SL0285).
            else if (NarrowableSubject(receiver) is null)
                diagnostics.Error("SL0248", syntax.Span,
                    $"'{receiver.Type.Name}' may be null, and this is not something a check " +
                    "can be about: a field or a call result may be a different value by the " +
                    $"time it is read. Put it in a local, check that against null, and reach " +
                    $"'{syntax.Member}' through it");

            else
                diagnostics.Error("SL0248", syntax.Span,
                    $"'{receiver.Type.Name}' may be null; check it against null before " +
                    $"accessing '{syntax.Member}'");

            return new BoundErrorExpression(syntax.Span);
        }

        // A variant's members are its cases and their payloads, neither of
        // which is a field the source may reach directly.
        if (receiver.Type is VariantTypeSymbol variantReceiver)
            return BindVariantRead(syntax, receiver, variantReceiver);

        // Properties come first: an automatic one has a field of the same name,
        // and reaching that field directly would skip the accessor and, through
        // an interface, skip dispatch with it.
        if (namedType.FindProperty(syntax.Member) is { } property)
            return BindPropertyRead(syntax.Span, receiver, property);

        if (namedType.FindField(syntax.Member) is { } field)
        {
            if (!CanReach(field.IsPublic, field.IsProtected, field.ContainingType))
            {
                diagnostics.Error("SL0249", syntax.Span,
                    NotVisible(field.ContainingType, syntax.Member, field.IsProtected));
                return new BoundErrorExpression(syntax.Span);
            }
            return new BoundFieldAccess(syntax.Span, receiver, field);
        }

        // A member of a nameless struct or union reads as the parent's own, so
        // what is built is the chain of field accesses that reaches it. The
        // layout already put it where C would; this is only the name.
        if (ReachThroughAnonymous(syntax.Span, receiver, namedType, syntax.Member) is { } reached)
            return reached;

        if (namedType.FindMethod(syntax.Member) is not null)
        {
            // Methods are only reachable through a call, which BindCall handles.
            diagnostics.Error("SL0250", syntax.Span,
                $"'{namedType.Name}.{syntax.Member}' is a method; call it with '()'");
            return new BoundErrorExpression(syntax.Span);
        }

        diagnostics.Error("SL0247", syntax.Span,
            $"'{namedType.Name}' has no member named '{syntax.Member}'");
        return new BoundErrorExpression(syntax.Span);
    }

    /// <summary>
    /// Applies <c>.</c> and <c>-&gt;</c> to a receiver that may be a pointer.
    ///
    /// Both spellings dereference, which is why <c>p.field</c> has always meant
    /// <c>(*p).field</c>. They differ only in what they refuse: an arrow says
    /// the programmer expected a pointer, so finding a value there is a mistake
    /// worth reporting rather than a spelling to accept.
    ///
    /// Returns null when it has reported one.
    /// </summary>
    private BoundExpression? ReachThroughPointer(
        MemberAccessSyntax syntax, BoundExpression receiver)
    {
        if (receiver.Type is PointerTypeSymbol { Element: NamedTypeSymbol } pointer)
            return new BoundDereference(syntax.Span, pointer.Element, receiver);

        if (!syntax.ThroughPointer) return receiver;

        diagnostics.Error("SL0494", syntax.Span,
            receiver.Type is PointerTypeSymbol pointed
                ? $"'{pointed.Name}' points at '{pointed.Element.Name}', which has no members, " +
                  $"so '->{syntax.Member}' reaches nothing"
                : $"'{receiver.Type.Name}' is not a pointer, so '->' does not apply to it; " +
                  $"write '.{syntax.Member}'");

        return null;
    }

    /// <summary>
    /// Finds <paramref name="member"/> inside this type's nameless members, and
    /// returns the access that reaches it -- one field access per level.
    ///
    /// The search is breadth-first so that the shallowest match wins, which is
    /// the rule C uses and the only one that keeps an outer name from being
    /// shadowed by a deeper one.
    /// </summary>
    private BoundExpression? ReachThroughAnonymous(
        SourceSpan span, BoundExpression receiver, NamedTypeSymbol type, string member)
    {
        var level = new List<(BoundExpression Access, NamedTypeSymbol Type)> { (receiver, type) };

        while (level.Count > 0)
        {
            var next = new List<(BoundExpression Access, NamedTypeSymbol Type)>();

            var found = new List<(BoundExpression Access, NamedTypeSymbol Owner)>();

            foreach (var (access, current) in level)
            {
                foreach (var anonymous in current.Fields.Where(f => f.IsAnonymous))
                {
                    if (anonymous.Type is not NamedTypeSymbol inner) continue;

                    var reached = new BoundFieldAccess(span, access, anonymous);
                    if (inner.FindField(member) is { } field)
                        found.Add((new BoundFieldAccess(span, reached, field), inner));

                    next.Add((reached, inner));
                }
            }

            // Two nameless members at the same depth both offering the name is
            // a question with no answer, so it is asked rather than guessed.
            if (found.Count > 1)
            {
                // The generated names are deliberately unwritable, so naming
                // them here would point at something the reader cannot use.
                diagnostics.Error("SL0492", span,
                    $"'{member}' is ambiguous: {Counted(found.Count, "nameless member")} " +
                    $"of '{type.Name}' declare{(found.Count == 1 ? "s" : "")} it. Give one of " +
                    "them a name, so that the one you mean can be said");
                return new BoundErrorExpression(span);
            }

            if (found.Count == 1) return found[0].Access;

            level = next;
        }

        return null;
    }

    /// <summary>
    /// <c>r.Ok</c>, <c>r.Value</c> and <c>r.Error</c>.
    ///
    /// The storage is module-private and this reads it directly, so the three
    /// names cost a field load and no call. What <c>Value</c> and <c>Error</c>
    /// additionally cost is a proof: it is readable only where the compiler has
    /// already established the case it belongs to, which is what makes a variant
    /// different from a struct whose fields happen to sit together.
    /// </summary>
    /// <summary>
    /// <c>Ok(x)</c> - a case named without its variant, held as a draft until
    /// something says which variant was meant.
    ///
    /// This is how <c>Ok</c> and <c>Fail</c> have always worked, generalized:
    /// one value cannot say what a variant's type arguments are, so the case is
    /// resolved from the type it is being returned or assigned into, the same
    /// rule a lambda obeys. Functions win a name outright - a bare call is only
    /// a draft when nothing else answers to it - so a case name costs a program
    /// nothing it was already using.
    /// </summary>
    private BoundExpression BindVariantDraft(
        CallSyntax syntax, string name, List<BoundExpression> arguments) =>
        new BoundVariantDraft(syntax.Span, name, arguments);

    /// <summary>
    /// The case a name would build if it were written bare in this file, or
    /// null. It is what SL0414 refuses to let a module-level function shadow.
    /// </summary>
    private VariantCaseSymbol? CaseNamed(FileScope scope, string name)
    {
        var previous = _currentScope;
        _currentScope = scope;

        try
        {
            var found = VariantsWithCase(name).FirstOrDefault()?.FindCase(name);
            if (found is not null) return found;

            // A generic variant has no symbol until it is instantiated, so its
            // template's cases are read from the syntax -- which is also how
            // Result's Ok and Fail are found before any Result exists.
            foreach (var template in VisibleModules().SelectMany(m => m.GenericTypes.Values))
            {
                if (template.Declaration.Kind != TypeDeclKind.Variant) continue;
                if (template.Declaration.Cases.All(c => c.Name != name)) continue;

                return new VariantCaseSymbol
                {
                    Name = name,
                    Tag = 0,
                    Span = template.Declaration.Span,
                    DeclaringVariant = new VariantTypeSymbol
                    {
                        SimpleName = template.Name,
                        ModuleName = template.Module.Name,
                    },
                };
            }

            return null;
        }
        finally
        {
            _currentScope = previous;
        }
    }

    /// <summary>Every variant this file can see with a case of that name.</summary>
    private List<VariantTypeSymbol> VariantsWithCase(string name)
    {
        return VisibleModules()
            .Distinct()
            .SelectMany(m => m.Types.Values)
            .OfType<VariantTypeSymbol>()
            .Where(v => v.FindCase(name) is not null)
            .Distinct()
            .ToList();
    }

    /// <summary>
    /// True when a bare <c>Name(...)</c> could be building a variant, which is
    /// what makes it worth holding as a draft rather than reporting as an
    /// unknown function.
    ///
    /// A generic variant is not in any module's type table until it has been
    /// instantiated, so its template's cases are read from the syntax. That is
    /// what keeps <c>Ok(x)</c> working in a program that has not yet named a
    /// <c>Result&lt;T, E&gt;</c> anywhere.
    /// </summary>
    private bool CouldBeVariantCase(string name)
    {
        if (VariantsWithCase(name).Count > 0) return true;

        return VisibleModules()
            .SelectMany(m => m.GenericTypes.Values)
            .Any(t => t.Declaration.Kind == TypeDeclKind.Variant &&
                      t.Declaration.Cases.Any(c => c.Name == name));
    }

    /// <summary>
    /// Settles a draft against the variant it is becoming, converting each
    /// argument to the field it is stored in.
    /// </summary>
    private BoundExpression BindVariantSettle(
        BoundVariantDraft draft, TypeSymbol target, SourceSpan span)
    {
        if (target is not VariantTypeSymbol variant)
        {
            diagnostics.Error("SL0413", span,
                $"'{draft.Case}' names a variant's case, but '{target.Name}' is expected here");
            return new BoundErrorExpression(span);
        }

        if (variant.FindCase(draft.Case) is not { } variantCase)
        {
            diagnostics.Error("SL0435", span,
                $"'{variant.Name}' has no case named '{draft.Case}'; it has " +
                Listed(variant.Cases.Select(c => c.Name)));
            return new BoundErrorExpression(span);
        }

        return BindVariantConstruction(variant, variantCase, draft.Arguments, span);
    }

    /// <summary>Checks the arguments against a case's fields and builds the value.</summary>
    private BoundExpression BindVariantConstruction(
        VariantTypeSymbol variant,
        VariantCaseSymbol variantCase,
        IReadOnlyList<BoundExpression> arguments,
        SourceSpan span)
    {
        var fields = variantCase.Fields;

        if (arguments.Count != fields.Count)
        {
            diagnostics.Error("SL0289", span,
                $"'{variant.Name}.{variantCase.Name}' carries {Counted(fields.Count, "field")}, " +
                $"but {Given(arguments.Count)}; " +
                $"it is written '{variantCase.Signature}'");
            return new BoundErrorExpression(span);
        }

        var converted = arguments
            .Select((argument, i) => BindConversion(argument, fields[i].Type, argument.Span))
            .ToList();

        return new BoundVariantConstruction(span, variant, variantCase, converted);
    }

    /// <summary>
    /// <c>v.Case</c>, which asks the tag, and <c>v.field</c>, which reads a
    /// payload once something has said which case is there.
    ///
    /// The proof is the whole point. A payload field is storage that only means
    /// anything when its case is the one present, so reading it without having
    /// established that is refused rather than answered.
    /// </summary>
    private BoundExpression BindVariantRead(
        MemberAccessSyntax syntax, BoundExpression receiver, VariantTypeSymbol variant)
    {
        if (variant.FindCase(syntax.Member) is { } tested)
            return new BoundVariantTest(
                syntax.Span, PrimitiveTypeSymbol.Bool, receiver, tested);

        // A variant may carry ordinary members too, and Result's ValueOr is one.
        if (variant.FindProperty(syntax.Member) is { } property)
            return BindPropertyRead(syntax.Span, receiver, property);

        var carrying = variant.Cases.Where(c => c.FindField(syntax.Member) is not null).ToList();

        if (carrying.Count == 0)
        {
            if (variant.FindMethod(syntax.Member) is not null)
            {
                diagnostics.Error("SL0250", syntax.Span,
                    $"'{variant.Name}.{syntax.Member}' is a method; call it with '()'");
                return new BoundErrorExpression(syntax.Span);
            }

            diagnostics.Error("SL0247", syntax.Span,
                $"'{variant.Name}' has no case or field named '{syntax.Member}'; its cases are " +
                Listed(variant.Cases.Select(c => c.Signature)));
            return new BoundErrorExpression(syntax.Span);
        }

        var subject = NarrowableSubject(receiver);

        if (subject is null)
        {
            diagnostics.Error("SL0285", syntax.Span,
                $"'{syntax.Member}' can only be read from a variant held in a local or a " +
                "parameter, because that is the only thing a check can be about; assign " +
                "this to one first, then test which case it is");
            return new BoundErrorExpression(syntax.Span);
        }

        var known = _variantFacts.TryGetValue(subject, out var fact) ? fact.Case : null;
        string name = SubjectName(subject);

        if (known is null)
        {
            var suggestion = carrying[0];
            diagnostics.Error("SL0286", syntax.Span,
                $"'{name}.{syntax.Member}' is not readable here, because nothing has " +
                $"established that '{name}' is '{suggestion.Name}'; " +
                $"check 'if ({name}.{suggestion.Name})' first, or switch over '{name}'");
            return new BoundErrorExpression(syntax.Span);
        }

        if (known.FindField(syntax.Member) is not { } field)
        {
            diagnostics.Error("SL0286", syntax.Span,
                $"'{name}' is known to be '{known.Name}' here, and '{known.Signature}' does " +
                $"not carry '{syntax.Member}'; that field belongs to " +
                Listed(carrying.Select(c => "'" + c.Name + "'")));
            return new BoundErrorExpression(syntax.Span);
        }

        return new BoundVariantPayload(syntax.Span, receiver, known, field);
    }

    /// <summary>
    /// A read of an optional that has been checked, as the thing it holds.
    ///
    /// Applied where the name is bound rather than at each use, so a narrowed
    /// value is narrowed for everything at once -- a call on it, an argument
    /// made of it, an assignment from it. The cost is that the three places
    /// which want the optional back have to say so; see <see cref="Widened"/>.
    /// </summary>
    private BoundExpression Narrowed(BoundExpression access, object subject)
    {
        if (access.Type is not OptionalTypeSymbol optional) return access;
        if (!_variantFacts.TryGetValue(subject, out var fact)) return access;
        if (!fact.ProvesNotNull) return access;

        return new BoundConversion(
            access.Span, optional.Element, access, ConversionKind.NarrowOptional);
    }

    /// <summary>
    /// The optional behind a narrowing, for the places a value is written
    /// rather than read.
    ///
    /// `x = null` is legal inside `if (x != null)`: the check said what x held,
    /// not what it may hold next. Same for `&x`, whose type is the storage's
    /// and not the moment's.
    /// </summary>
    private static BoundExpression Widened(BoundExpression expression) =>
        expression is BoundConversion { Kind: ConversionKind.NarrowOptional } narrowed
            ? narrowed.Operand
            : expression;

    /// <summary>The modules a name written in the current file resolves against.</summary>
    private IEnumerable<ModuleSymbol> VisibleModules()
    {
        if (_currentScope is null) return [];
        return _currentScope.Imports.Values.Prepend(_currentScope.Module).Distinct();
    }

    private static string SubjectName(object subject) => subject switch
    {
        LocalSymbol local => local.Name,
        ParameterSymbol parameter => parameter.Name,
        _ => "it",
    };

    /// <summary>"a, b and c" - for a diagnostic that lists what was available.</summary>
    private static string Listed(IEnumerable<string> items)
    {
        var list = items.ToList();
        return list.Count switch
        {
            0 => "nothing",
            1 => list[0],
            _ => string.Join(", ", list.Take(list.Count - 1)) + " and " + list[^1],
        };
    }

    private static string Counted(int count, string noun) =>
        count == 1 ? "1 " + noun : $"{count} {noun}s";

    /// <summary>"1 was given" / "3 were given", so the verb agrees with the count.</summary>
    private static string Given(int count) => count == 1 ? "1 was given" : $"{count} were given";
}
